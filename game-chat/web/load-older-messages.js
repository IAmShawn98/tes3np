(() => {
  const list = document.querySelector('[data-list-id="chat-messages"]');
  if (!list) return 'no-message-list';
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
  const before = scroller.scrollTop;
  const recovery = RECOVERY_FLAG;
  const first = list.querySelector('[id^="chat-messages-"]');
  const firstId = first?.id || 'none';
  const beforeCount = list.querySelectorAll('[id^="chat-messages-"]').length;
  const last = [...list.querySelectorAll('[id^="chat-messages-"]')].at(-1);
  const listRect = list.getBoundingClientRect();
  const scrollRect = scroller.getBoundingClientRect();
  const loading = !!document.querySelector('[class*="loadingMore"], [class*="loadingWrapper"], [class*="spinner"]');
  if (recovery) {
    // Ask Discord's virtualized list to reveal its first actual
    // message instead of repeatedly bouncing an already-top scroller.
    if (first) first.scrollIntoView({block:'start',behavior:'instant'});
    scroller.scrollTo({top:0,behavior:'instant'});
  } else {
    scroller.scrollTop = Math.min(350, Math.max(0, scroller.scrollHeight - scroller.clientHeight));
    scroller.dispatchEvent(new Event('scroll', {bubbles:true}));
    setTimeout(() => {
      if (!scroller.isConnected) return;
      scroller.scrollTo({top:0,behavior:'instant'});
      scroller.dispatchEvent(new Event('scroll', {bubbles:true}));
    }, 130);
  }
  return 'scroll=' + before + '->' + scroller.scrollTop +
    ' height=' + scroller.scrollHeight + ' client=' + scroller.clientHeight +
    ' first=' + firstId + ' rows=' + beforeCount +
    ' connected=' + scroller.isConnected +
    ' last=' + (last?.id || 'none') +
    ' listTop=' + Math.round(listRect.top) +
    ' scrollerTop=' + Math.round(scrollRect.top) +
    ' loading=' + loading;
})();