(channel) => {
  if (window.top !== window || location.origin + location.pathname.replace(/\/$/, '') !== channel) return;

  function install() {
    const root = document.documentElement;
    const areaMarker = 'data-tes3np-composer';
    const editorMarker = 'data-tes3np-composer-editor';
    const sendMarker = 'data-tes3np-composer-send';
    const ancestorMarker = 'data-tes3np-composer-ancestor';
    const editorWrapperMarker = 'data-tes3np-composer-editor-wrapper';
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
      [${editorWrapperMarker}] {
        box-sizing: border-box !important; width: 100% !important; inline-size: 100% !important;
        min-width: 0 !important; min-inline-size: 0 !important; max-width: none !important; max-inline-size: none !important;
        flex: 1 1 0% !important;
      }
      [${areaMarker}] [class*="attachWrapper_"], [${areaMarker}] [class*="upload_"],
      [${areaMarker}] [class*="buttons_"] > :not(:where([${sendMarker}], :has([${sendMarker}]))),
      [${areaMarker}] :is(button, [role="button"]):not([${sendMarker}]) { display: none !important; }
      [${editorMarker}] {
        background: transparent !important; color: #f1e4ca !important; caret-color: #e0b971 !important;
        font: 14px/1.4 Georgia, serif !important; padding: 2px 0 !important;
        box-sizing: border-box !important; width: 100% !important; min-width: 0 !important; max-width: none !important;
        min-height: 1.4em !important; max-height: calc(var(--tes3np-compose-height) - 8px) !important;
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

    const widthProperties = ['width', 'min-width', 'max-width', 'inline-size', 'min-inline-size', 'max-inline-size'];
    const heightProperties = ['height', 'min-height', 'max-height', 'block-size', 'min-block-size', 'max-block-size'];
    const layoutObserver = new ResizeObserver(queueSearch);
    let widthFraction = 0, heightFraction = 0;
    let boundArea, boundEditor, boundSend, ancestors = [], editorWrappers = [], savedSizing = [];
    let previousState = '', queued = false;

    function publish(state, layout) {
      if (previousState === state) return;
      previousState = state;
      chrome.webview.postMessage({ type: 'tes3np-composer', state, ...layout });
    }

    function setArea(area) {
      if (boundArea === area) return;
      if (boundArea) {
        layoutObserver.unobserve(boundArea);
        boundArea.removeAttribute(areaMarker);
        for (const [name, value, priority] of savedSizing) {
          if (value) boundArea.style.setProperty(name, value, priority);
          else boundArea.style.removeProperty(name);
        }
      }
      for (const node of ancestors) node.removeAttribute(ancestorMarker);
      ancestors = [];
      savedSizing = [];
      boundArea = area;
      if (!area) return;
      area.setAttribute(areaMarker, '');
      layoutObserver.observe(area);
      savedSizing = [...widthProperties, ...heightProperties].map(name => [name, area.style.getPropertyValue(name), area.style.getPropertyPriority(name)]);
      for (let node = area.parentElement; node && node !== root; node = node.parentElement) {
        node.setAttribute(ancestorMarker, '');
        ancestors.push(node);
      }
    }

    function findComposer() {
      queued = false;
      const onChannel = location.origin + location.pathname.replace(/\/$/, '') === channel;
      const width = Math.round(window.innerWidth * widthFraction);
      const height = Math.round(window.innerHeight * heightFraction);
      const editors = '[contenteditable="true"][role="textbox"], [contenteditable="true"][data-slate-editor="true"]';
      const editor = onChannel && width > 0 && height > 0
        ? [...document.querySelectorAll(editors)].find(node =>
            node.closest('form') && node.closest('[class*="channelTextArea_"], [class*="channelTextArea-"], [class*="chatContent_"]') &&
            !node.closest('[aria-disabled="true"], [aria-hidden="true"], [inert]') &&
            node.getClientRects().length)
        : undefined;
      const area = editor?.closest('[class*="channelTextArea_"], [class*="channelTextArea-"]') ?? editor?.closest('form');
      const send = area?.querySelector('button[aria-label*="send message" i], [role="button"][aria-label*="send message" i], button[title*="send message" i], button[class*="sendButton_"]');

      const areaChanged = boundArea !== area;
      setArea(area);
      if (boundEditor !== editor || areaChanged) {
        for (const node of editorWrappers) node.removeAttribute(editorWrapperMarker);
        editorWrappers = [];
        if (boundEditor) {
          layoutObserver.unobserve(boundEditor);
          boundEditor.removeAttribute(editorMarker);
        }
        boundEditor = editor;
        if (editor) {
          editor.setAttribute(editorMarker, '');
          layoutObserver.observe(editor);
        }
        for (let node = editor?.parentElement; node && node !== area; node = node.parentElement) {
          node.setAttribute(editorWrapperMarker, '');
          editorWrappers.push(node);
        }
      }
      if (boundSend !== send) {
        boundSend?.removeAttribute(sendMarker);
        boundSend = send;
        send?.setAttribute(sendMarker, '');
      }
      if (area) {
        root.style.setProperty('--tes3np-compose-width', width + 'px');
        root.style.setProperty('--tes3np-compose-height', height + 'px');
        // Set both physical and logical sizes so Discord's width, min-size
        // or max-size rules cannot collapse the embedded channel composer.
        for (const name of widthProperties) area.style.setProperty(name, width + 'px', 'important');
        for (const name of heightProperties) area.style.setProperty(name, height + 'px', 'important');

        const bar = area.getBoundingClientRect();
        const text = editor.getBoundingClientRect();
        if (Math.abs(bar.width - width) <= 2 && bar.height >= height - 2 &&
            Math.abs(bar.left) <= 2 && Math.abs(bar.top) <= 2 &&
            text.width >= Math.min(60, width / 2) && text.height >= 10 &&
            text.left >= bar.left - 2 && text.right <= bar.right + 2)
          publish('ready');
        else publish('layout', {
          expectedWidth: width, barWidth: Math.round(bar.width), editorWidth: Math.round(text.width)
        });
      } else if (!onChannel || document.querySelector('[data-list-id="chat-messages"], [class*="chatContent_"] form'))
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
      widthFraction = Number.isFinite(data.widthFraction) ? Math.max(0, Math.min(1, data.widthFraction)) : 0;
      heightFraction = Number.isFinite(data.heightFraction) ? Math.max(0, Math.min(1, data.heightFraction)) : 0;
      queueSearch();
    });
    window.addEventListener('resize', queueSearch);
    new MutationObserver(queueSearch).observe(root, {
      subtree: true, childList: true, attributes: true, attributeFilter: ['contenteditable', 'aria-disabled', 'aria-hidden']
    });
    queueSearch();
  }

  if (document.documentElement) install();
  else document.addEventListener('DOMContentLoaded', install, { once: true });
}
