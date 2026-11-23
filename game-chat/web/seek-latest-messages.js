(() => {
  const list = document.querySelector('[data-list-id="chat-messages"]');
  if (!list) return 'no-message-list';

  // Discord can reopen a channel at an old read marker. Scrolling to the
  // bottom of that virtual window alone does not prove we reached the live
  // channel. Ask Discord's own "Jump to Present" control first when shown.
  // Source styling can hide Discord's native Jump to Present control.
  // Briefly disable only TES3NP's injected stylesheet while locating/clicking
  // the real Discord button, then restore the source appearance exactly.
  const sourceStyle = document.getElementById('tes3np-chat-style')?.sheet;
  const restoreStyle = sourceStyle && !sourceStyle.disabled;
  if (restoreStyle) sourceStyle.disabled = true;
  try {
    const jump = [...document.querySelectorAll('button, [role="button"]')].find(button => {
      const label = [button.getAttribute('aria-label'), button.getAttribute('title'),
        button.textContent].filter(Boolean).join(' ');
      return /jump to (?:present|latest)/i.test(label) &&
        button.getClientRects().length > 0;
    });
    if (jump) {
      jump.click();
      return 'jump-requested';
    }
  } finally {
    if (restoreStyle) sourceStyle.disabled = false;
  }

  let scroller = list;
  while (scroller && scroller !== document.body) {
    const css = getComputedStyle(scroller);
    if (scroller.scrollHeight > scroller.clientHeight + 20 &&
        /(auto|scroll)/.test(css.overflowY)) break;
    scroller = scroller.parentElement;
  }
  if (!scroller || scroller === document.body)
    scroller = list.closest('[class*="scroller_"]');
  if (!scroller) return 'no-scroller';

  const remaining = scroller.scrollHeight - scroller.clientHeight - scroller.scrollTop;
  if (remaining > 24) {
    scroller.scrollTo({top: scroller.scrollHeight, behavior: 'instant'});
    scroller.dispatchEvent(new Event('scroll', {bubbles: true}));
    return 'seeking';
  }
  if (document.querySelector('[class*="loadingMore"], [class*="loadingWrapper"], [class*="spinner"]'))
    return 'loading';
  const rows = [...list.querySelectorAll('[id^="chat-messages-"]')]
    .filter(el => /^chat-messages-[0-9]+-[0-9]+$/.test(el.id));
  const id = rows.at(-1)?.id.match(/^chat-messages-[0-9]+-([0-9]+)$/)?.[1];
  return id ? 'present:' + id : 'no-message-id';
})();
