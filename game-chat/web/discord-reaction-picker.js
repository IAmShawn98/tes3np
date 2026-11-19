(() => {
  if (window.top !== window) return;
  const roots = '[class^="emojiPicker_"], [class*=" emojiPicker_"], ' +
    '[class^="emojiPicker-"], [class*=" emojiPicker-"], [role="dialog"][aria-label="Emoji Picker" i]';
  const choices = '[class^="emojiItem_"], [class*=" emojiItem_"], [role="gridcell"], [data-emoji-id]';
  const marker = 'data-tes3np-native-emoji-picker';
  let displayedPicker;
  let style;
  let dismissed = false;

  function identifyPicker() {
    let selected;
    for (const node of document.querySelectorAll(roots)) {
      const rect = node.getBoundingClientRect();
      if (rect.width < 120 || rect.height < 120 || !node.querySelector('input, [role="searchbox"]')) continue;
      if (!selected || rect.width * rect.height < selected.rect.width * selected.rect.height)
        selected = { node, rect };
    }
    return selected;
  }

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
    if (!style?.isConnected) {
      // Visibility does not change the underlying Discord layout or move its React nodes.
      style = document.createElement('style');
      style.textContent = `
        html, body { background: #232428 !important; }
        body :not([${marker}], [${marker}] *) { visibility: hidden !important; }
        [${marker}] { visibility: visible !important; }
      `;
      document.head.append(style);
    }
    const rect = picker.rect;
    return {
      Picker: { Left: rect.left, Top: rect.top, Right: rect.right, Bottom: rect.bottom,
        ViewWidth: window.innerWidth, ViewHeight: window.innerHeight },
      Dismissed: dismissed
    };
  };
})();
