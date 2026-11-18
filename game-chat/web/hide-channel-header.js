(() => {
  const hide = () => {
    const messages = document.querySelector('[data-list-id="chat-messages"]');
    if (!messages) return;
    const root = messages.closest('[class*="chat_"]') ||
                 messages.closest('main') || document.body;
    const scroller = messages.closest('[class*="scroller_"]');
    if (!scroller) return;
    const ancestors = new Set();
    let node = scroller;
    while (node && node !== root) { ancestors.add(node); node = node.parentElement; }
    // The Discord channel heading is a sibling preceding the message area.
    // Hide that entire sibling instead of chasing icon CSS class names.
    node = scroller;
    while (node && node !== root) {
      for (const sibling of Array.from(node.parentElement?.children || [])) {
        if (sibling === node || sibling.contains(messages)) continue;
        const rect = sibling.getBoundingClientRect();
        const msgRect = messages.getBoundingClientRect();
        if (rect.height > 0 && rect.height < 120 &&
            rect.top <= msgRect.top && rect.bottom <= msgRect.top + 10) {
          sibling.style.setProperty('display', 'none', 'important');
        }
      }
      node = node.parentElement;
    }
  };
  hide();
  if (!window.__tes3npHeaderObserver) {
    let queued = false;
    window.__tes3npHeaderObserver = new MutationObserver(() => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => { queued = false; hide(); });
    });
    window.__tes3npHeaderObserver.observe(document.body, {childList:true,subtree:true});
  }
})();