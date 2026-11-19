(channel) => {
  if (window.top !== window || location.origin + location.pathname.replace(/\/$/, '') !== channel) return;

  function install() {
    const root = document.documentElement;
    const areaMarker = 'data-tes3np-composer';
    const editorMarker = 'data-tes3np-composer-editor';
    const sendMarker = 'data-tes3np-composer-send';
    const ancestorMarker = 'data-tes3np-composer-ancestor';
    const style = document.createElement('style');
    style.textContent = `
      html, body { margin: 0 !important; overflow: hidden !important; background: #0a0908 !important; }
      body *:not(:where([${areaMarker}], [${areaMarker}] *)) { visibility: hidden !important; }
      svg :is(defs, mask, clipPath), svg :is(defs, mask, clipPath) * { visibility: visible !important; }
      [${ancestorMarker}] { overflow: visible !important; transform: none !important; contain: none !important; }
      [${areaMarker}] {
        visibility: visible !important; position: fixed !important; z-index: 2147483647 !important;
        inset: 0 auto auto 0 !important; box-sizing: border-box !important;
        width: var(--tes3np-compose-width) !important; height: var(--tes3np-compose-height) !important;
        display: flex !important; align-items: center !important; margin: 0 !important; padding: 0 7px !important;
        overflow: hidden !important; color: #f1e4ca !important; background: #17120e !important;
        border: 1px solid #907343 !important; border-radius: 3px !important;
      }
      [${areaMarker}] [class*="scrollableContainer_"], [${areaMarker}] [class*="inner_"] {
        background: transparent !important; border: 0 !important; margin: 0 !important; min-width: 0 !important;
        width: 100% !important; padding: 0 !important;
      }
      [${areaMarker}] [class*="textArea_"] { flex: 1 1 auto !important; min-width: 0 !important; }
      [${areaMarker}] [class*="attachWrapper_"], [${areaMarker}] [class*="upload_"],
      [${areaMarker}] [class*="buttons_"] > :not(:where([${sendMarker}], :has([${sendMarker}]))),
      [${areaMarker}] :is(button, [role="button"]):not([${sendMarker}]) { display: none !important; }
      [${editorMarker}] {
        background: transparent !important; color: #f1e4ca !important; caret-color: #e0b971 !important;
        font: 14px/1.4 Georgia, serif !important; padding: 2px 0 !important;
        min-height: 0 !important; max-height: calc(var(--tes3np-compose-height) - 8px) !important;
        overflow: auto !important; scrollbar-width: thin;
      }
      [${areaMarker}] [class*="placeholder_"] {
        color: #ad9773 !important; font: 14px/1.4 Georgia, serif !important;
        padding: 2px 0 !important;
      }
      [${sendMarker}] { color: #e5c68d !important; }
      [${areaMarker}]:focus-within { border-color: #d5b477 !important; }
    `;
    root.append(style);

    let width = 0, height = 0;
    let boundArea, boundEditor, boundSend, ancestors = [];
    let previousState = '', queued = false;

    function publish(state) {
      if (previousState === state) return;
      previousState = state;
      chrome.webview.postMessage({ type: 'tes3np-composer', state });
    }

    function setArea(area) {
      if (boundArea === area) return;
      boundArea?.removeAttribute(areaMarker);
      for (const node of ancestors) node.removeAttribute(ancestorMarker);
      ancestors = [];
      boundArea = area;
      if (!area) return;
      area.setAttribute(areaMarker, '');
      for (let node = area.parentElement; node && node !== root; node = node.parentElement) {
        node.setAttribute(ancestorMarker, '');
        ancestors.push(node);
      }
    }

    function findComposer() {
      queued = false;
      const onChannel = location.origin + location.pathname.replace(/\/$/, '') === channel;
      const editors = '[contenteditable="true"][role="textbox"], [contenteditable="true"][data-slate-editor="true"]';
      const editor = onChannel && width > 0 && height > 0
        ? [...document.querySelectorAll(editors)].find(node =>
            node.closest('form') && node.closest('[class*="channelTextArea_"], [class*="channelTextArea-"], [class*="chatContent_"]') &&
            !node.closest('[aria-disabled="true"], [aria-hidden="true"], [inert]') &&
            node.getClientRects().length)
        : undefined;
      const area = editor?.closest('[class*="channelTextArea_"], [class*="channelTextArea-"]') ?? editor?.closest('form');
      const send = area?.querySelector('button[aria-label*="send message" i], [role="button"][aria-label*="send message" i], button[title*="send message" i], button[class*="sendButton_"]');

      setArea(area);
      if (boundEditor !== editor) {
        boundEditor?.removeAttribute(editorMarker);
        boundEditor = editor;
        editor?.setAttribute(editorMarker, '');
      }
      if (boundSend !== send) {
        boundSend?.removeAttribute(sendMarker);
        boundSend = send;
        send?.setAttribute(sendMarker, '');
      }
      if (area) publish('ready');
      else if (!onChannel || document.querySelector('[data-list-id="chat-messages"], [class*="chatContent_"] form'))
        publish('unavailable');
      else publish('loading');
    }

    function queueSearch() {
      if (!queued) {
        queued = true;
        requestAnimationFrame(findComposer);
      }
    }

    chrome.webview.addEventListener('message', ({ data }) => {
      if (data?.type !== 'tes3np-composer-size') return;
      width = Number.isFinite(data.width) ? Math.max(0, data.width) : 0;
      height = Number.isFinite(data.height) ? Math.max(0, data.height) : 0;
      root.style.setProperty('--tes3np-compose-width', width + 'px');
      root.style.setProperty('--tes3np-compose-height', height + 'px');
      queueSearch();
    });
    new MutationObserver(queueSearch).observe(root, {
      subtree: true, childList: true, attributes: true, attributeFilter: ['contenteditable', 'aria-disabled', 'aria-hidden']
    });
    queueSearch();
  }

  if (document.documentElement) install();
  else document.addEventListener('DOMContentLoaded', install, { once: true });
}
