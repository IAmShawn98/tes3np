(() => {
  if (window.top !== window) return;
  const roots = '[class^="emojiPicker_"], [class*=" emojiPicker_"], ' +
    '[class^="emojiPicker-"], [class*=" emojiPicker-"], [role="dialog"][aria-label*="Emoji" i]';
  const choices = '[class^="emojiItem_"], [class*=" emojiItem_"], [role="gridcell"], [data-emoji-id], [data-type="emoji"]';
  const search = 'input, [role="searchbox"], [contenteditable="true"][role="combobox"]';
  const marker = 'data-tes3np-native-emoji-picker';
  const loading = 'data-tes3np-emoji-loading';
  const isolated = 'data-tes3np-emoji-isolated';
  let displayedPicker;
  let style;
  let dismissed = false;

  function identifyPicker() {
    let selected;
    function consider(node) {
      const rect = node.getBoundingClientRect();
      if (rect.width < 120 || rect.height < 120 || rect.width > 700 || rect.height > 720) return;
      const rank = node.querySelector(search) ? 1 : 0;
      if (!selected || rank > selected.rank ||
          (rank === selected.rank && rect.width * rect.height < selected.rect.width * selected.rect.height))
        selected = { node, rect, rank };
    }
    for (const root of document.querySelectorAll(roots)) {
      if (root.querySelector(search) || root.querySelector(choices)) consider(root);
      // Some Discord layouts place search beside the grid within a popout wrapper.
      let node = root.parentElement;
      for (let depth = 0; depth < 3 && node && node !== document.body; depth++, node = node.parentElement) {
        if ((node.matches('[class*="positionLayer"], [class*="contentWrapper"], [role="dialog"]') ||
             node.querySelectorAll('input').length === 1) && node.querySelector(search) && node.querySelector(choices)) {
          consider(node);
        }
      }
    }
    if (!selected) {
      for (const layer of document.querySelectorAll('[class*="positionLayer_"], [class*="contentWrapper_"], [role="dialog"]')) {
        if (layer.querySelector(search) && layer.querySelector(choices)) consider(layer);
      }
    }
    return selected;
  }

  function ensureStyle() {
    if (style?.isConnected) return;
    style = document.createElement('style');
    style.textContent = `
      html[${loading}]::after { content: ''; position: fixed; inset: 0; z-index: 2147483647;
        background: #232428; pointer-events: none; }
      html[${isolated}], html[${isolated}] body { background: #232428 !important; }
      html[${isolated}] body :not([${marker}], [${marker}] *) { visibility: hidden !important; }
      html[${isolated}] [${marker}] { visibility: visible !important; }
    `;
    document.head.append(style);
  }

  window.tes3npPrepareReactionPicker = () => {
    ensureStyle();
    document.documentElement.setAttribute(loading, '');
    document.documentElement.removeAttribute(isolated);
    return true;
  };

  // Discord can dismiss popovers when the host window loses focus. Only retain
  // the top-level blur while this standalone reaction picker is being shown.
  window.addEventListener('blur', event => {
    if (event.target === window && displayedPicker?.isConnected)
      event.stopImmediatePropagation();
  }, true);

  document.addEventListener('keydown', event => {
    if (event.isTrusted && displayedPicker?.isConnected && event.key === 'Escape') dismissed = true;
  }, true);

  document.addEventListener('click', event => {
    const choice = event.isTrusted && !event.shiftKey && event.target.closest?.(choices);
    if (choice && displayedPicker?.contains(choice) && !choice.disabled && choice.getAttribute('aria-disabled') !== 'true')
      dismissed = true;
  }, true);

  window.tes3npReactionPickerView = () => {
    const picker = identifyPicker();
    if (!picker) return { Picker: null, Dismissed: dismissed };

    if (displayedPicker !== picker.node) {
      displayedPicker?.removeAttribute(marker);
      displayedPicker = picker.node;
      displayedPicker.setAttribute(marker, '');
    }
    // Visibility leaves the measured layout and Discord's React nodes in place.
    ensureStyle();
    document.documentElement.setAttribute(isolated, '');
    document.documentElement.removeAttribute(loading);
    const rect = picker.rect;
    return {
      Picker: { Left: rect.left, Top: rect.top, Right: rect.right, Bottom: rect.bottom,
        ViewWidth: window.innerWidth, ViewHeight: window.innerHeight },
      Dismissed: dismissed
    };
  };
})();
