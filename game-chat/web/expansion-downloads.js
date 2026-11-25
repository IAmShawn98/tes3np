(() => {
  if (window.__tes3npExpansionFocus) {
    window.__tes3npExpansionFocus(); return;
  }
  const channel='/channels/509601787901116437/1555049936800718928';
  const attachmentHost=/^https:\/\/(?:cdn\.discordapp\.com|media\.discordapp\.net)\/attachments\//i;
  let scheduled=false, retryPending=false, lastStatus='', lastFileKey='';
  let panel, status, sender, link, size;
  let best=null, checkedPresent=false, backfillCount=0, phase='present';
  const recentPacks=new Map(), recentPackLimit=4;
  const packName=/^NP[ _.-]+Expansion[ _.-]+Pack[ _.-]+v\d{1,3}(?:\.\d{1,3}){1,3}[a-z]{0,3}\.zip$/i;
  let previousHistoryTop='', unchangedHistory=0, loadingRetries=0, presentRetries=0;
  const maxBackfills=12, maxLoadingRetries=30, maxPresentRetries=18;

  function report(value) {
    if (value===lastStatus) return;
    lastStatus=value;
    try { chrome.webview.postMessage({type:'expansion-layout',status:value}); } catch {}
  }
  function setup() {
    if (panel || !document.documentElement) return;
    /* TES3NP_THEME_FONT_LOAD */
    const style=document.createElement('style');
    style.textContent=[
      '#tes3np-zip-card {position:fixed!important;inset:0!important;',
      'z-index:2147483647!important;display:flex!important;',
      'flex-direction:column!important;justify-content:center!important;',
      'box-sizing:border-box!important;padding:12px 16px!important;',
      'background:#1b1b1f!important;color:#ece4d4!important;',
      'font:14px/1.5 "TES3NP Theme","Mystic Cards",Georgia,serif!important;overflow:auto!important}',
      '#tes3np-zip-card a {display:block;border:1px solid #4f4b52;',
      'background:#292a33;color:#77baff!important;border-radius:5px;',
      'padding:14px;text-decoration:none!important;overflow-wrap:anywhere}',
      '#tes3np-zip-card a:hover {background:#383943;border-color:#c8a566}',
      '#tes3np-zip-card .small {color:#b3abb1;font-size:12px}',
      '#tes3np-zip-card .sender {color:#d7ad6e;font-weight:600}'
    ].join('\n');
    document.documentElement.appendChild(style);
    panel=document.createElement('div'); panel.id='tes3np-zip-card';
    status=document.createElement('div');
    sender=document.createElement('div'); sender.className='sender';
    link=document.createElement('a');
    // The raw CDN navigation/download stalls this tiny child
    // WebView2 on some Windows machines. Keep the DOM card inside
    // the dialog but hand the actual ZIP URL to the native host.
    link.addEventListener('click',event=>{
      if (event.button!==0 || event.defaultPrevented) return;
      event.preventDefault();
      event.stopPropagation();
      const url=link.href;
      try {
        const uri=new URL(url);
        if (!attachmentHost.test(url) || !/\.zip$/i.test(uri.pathname)) {
          report('download-url-invalid');
          return;
        }
        chrome.webview.postMessage({type:'expansion-download',url});
        // This card stays ready while the default browser is
        // downloading. A cancelled/failed download requires no
        // reset, reload, or completion signal.
        // Leave the card unchanged; a persistent progress label
        // looked stuck even while the external browser handled it.
        status.textContent='';
        report('download-handed-to-browser');
      } catch {
        report('download-handoff-unavailable');
        status.textContent='Could not open the download. Use the Discord channel link below.';
      }
    });
    size=document.createElement('div'); size.className='small';
    panel.append(status,sender,link,size);
    document.documentElement.appendChild(panel);
    // Observe links as well as new messages: Discord periodically
    // replaces expiring, signed attachment URLs in the same node.
    new MutationObserver(changes=>{
      // Ignore updates to our own download card. Otherwise each
      // status/link update can trigger another full Discord scan.
      if (changes.every(change=>panel && (
          change.target===panel || panel.contains(change.target)))) return;
      schedule();
    }).observe(document.documentElement,
      {childList:true,subtree:true,characterData:true,
       attributes:true,attributeFilter:['href']});
    schedule();
  }
  function retry() {
    if (retryPending) return;
    retryPending=true;
    setTimeout(()=>{retryPending=false;schedule();},350);
  }
  function wait(message,kind) {
    if (lastFileKey==='waiting:'+kind) return;
    lastFileKey='waiting:'+kind;
    status.textContent=message;
    sender.style.display='none';
    link.style.display='none';
    size.style.display='none';
    report(kind);
  }
  function snowflake(message) {
    if (!message) return null;
    // Discord message IDs may live on a row, a nested element,
    // or an outer virtualized list item. Use each source before
    // falling back to the visual order of ZIP links.
    const parse=node=>{
      const raw=(node?.getAttribute?.('data-list-item-id')||'')+' '+
        (node?.id||'');
      // The existing native Game Chat parser confirms Discord
      // rows are chat-messages-<channelId>-<messageId>. Taking
      // the first number would compare the fixed channel ID and
      // accidentally fall back to displayed DOM order.
      const row=raw.match(/chat-messages-\d+-(\d{15,22})(?!\d)/);
      if (row) return BigInt(row[1]);
      // Some Discord virtualization builds store only the
      // message snowflake in data-list-item-id.
      const single=raw.match(/chat-messages___(\d{15,22})(?!\d)/);
      return single ? BigInt(single[1]) : null;
    };
    for (let el=message; el && el!==document.body; el=el.parentElement) {
      const id=parse(el);
      if (id!==null) return id;
    }
    const nested=message.querySelector?.(
      '[id^="chat-messages-"],[data-list-item-id^="chat-messages_"]');
    return nested ? parse(nested) : null;
  }
  function readCandidates(feed) {
    const anchors=Array.from(feed.querySelectorAll('a[href]'));
    const found=[];
    for (let i=0;i<anchors.length;i++) {
      const a=anchors[i], url=a.href||'';
      if (!attachmentHost.test(url)) continue;
      let filename='';
      try { filename=decodeURIComponent(new URL(url).pathname.split('/').pop()||''); }
      catch { continue; }
      if (!packName.test(filename)) continue;
      const row=a.closest(
        '[data-list-item-id^="chat-messages_"],[id^="chat-messages-"],[class*="messageListItem_"]'
      )||a.parentElement;
      const author=row?.querySelector('[class*="username_"]');
      const sizeMatch=(row?.textContent||'').match(/\b[\d,.]+\s*(?:GB|MB|KB)\b/i);
      found.push({
        url,filename,sender:(author?.textContent||'Nerevarine Prophecies').trim(),
        bytes:sizeMatch?sizeMatch[0]:'',id:snowflake(row),order:i
      });
    }
    return found;
  }
  function newestFirst(a,b) {
    const left=a.id??0n, right=b.id??0n;
    return left>right ? -1 : left<right ? 1 : b.order-a.order;
  }
  function remember(candidates) {
    for (const item of candidates) {
      recentPacks.set(new URL(item.url).pathname,item);
      // Snowflakes are chronological; when Discord's message ID
      // metadata is missing, DOM order is a best-effort fallback.
      if (!best ||
          (item.id!==null && best.id!==null && item.id>best.id) ||
          (item.id===best.id && item.order>=best.order) ||
          (item.id!==null && best.id===null)) best=item;
    }
    if (recentPacks.size>24) {
      const kept=Array.from(recentPacks.entries())
        .sort((a,b)=>newestFirst(a[1],b[1]))
        .slice(0,24);
      recentPacks.clear();
      for (const [key,item] of kept) recentPacks.set(key,item);
    }
  }
  function show(file) {
    const recent=Array.from(recentPacks.values())
      .filter(item=>new URL(item.url).pathname!==new URL(file.url).pathname)
      .sort(newestFirst)
      .slice(0,recentPackLimit-1);
    const key=file.url+'|'+recent.map(item=>item.url).join('|');
    if (lastFileKey===key) return;
    lastFileKey=key;
    status.textContent=file.id===null
      ? 'ZIP found in Discord (message date not verified)'
      : 'Latest Expansion Pack ZIP found in Discord';
    sender.style.display='block'; sender.textContent=file.sender;
    link.style.display='block'; link.href=file.url; link.textContent=file.filename;
    size.style.display=file.bytes?'block':'none'; size.textContent=file.bytes;
    // Save the live signed link for a native Download / Retry
    // control outside WebView2. The user can request it again even
    // if the embedded browser stops repainting after a download.
    try { chrome.webview.postMessage({
      type:'expansion-available',url:file.url,history:recent.map(item=>item.url)
    }); } catch {}
    report('latest-zip-ready');
  }
  function scrollerFor(feed) {
    // Match the established Game Chat scroller discovery. An
    // ancestor with overflow:hidden can have extra scrollHeight
    // without actually being scrollable.
    let cur=feed;
    while(cur && cur!==document.body) {
      const css=getComputedStyle(cur);
      if (cur.scrollHeight > cur.clientHeight+30 &&
          cur.clientHeight>30 &&
          /(auto|scroll)/.test(css.overflowY)) return cur;
      cur=cur.parentElement;
    }
    return feed.closest('[class*="scroller_"]');
  }
  function goToPresent(scroller) {
    if (!scroller) return true;
    const gap=scroller.scrollHeight-scroller.scrollTop-scroller.clientHeight;
    if (gap>45) {
      if (++presentRetries<=maxPresentRetries) {
        scroller.scrollTop=scroller.scrollHeight;
        retry();
      }
      return false;
    }
    presentRetries=0;
    return true;
  }
  function refresh() {
    if (!panel) return;
    if (location.pathname.replace(/\/+$/,'')!==channel) {
      wait('Open the Nerevarine Prophecies Expansion Pack channel in Discord.',
        'wrong-channel'); return;
    }
    const feed=document.querySelector('[data-list-id="chat-messages"]');
    if (!feed) {
      wait('Loading the official Expansion Pack download channel. If it stays empty, sign into Game Chat.',
        'waiting-for-channel');
      // The observer will also notice the Discord channel mounting.
      // Stop timed retries when signed out, instead of polling forever.
      if (++loadingRetries<=maxLoadingRetries) retry();
      return;
    }
    loadingRetries=0;
    const scroller=scrollerFor(feed);
    if (phase==='present') {
      // Discord may resume at an old read position. Do not trust
      // those old ZIP links before reaching the newest messages.
      if (!goToPresent(scroller)) {
        wait(presentRetries>maxPresentRetries
          ? 'Could not reach Discord\'s newest messages. Open the download channel link below.'
          : 'Checking the latest Discord uploads...', 'seeking-present');
        return;
      }
      checkedPresent=true;
      phase='search';
    }
    // A reopened/historically restored Discord scroller cannot
    // silently turn an older ZIP into a "latest" result.
    if (phase==='monitor' && !goToPresent(scroller)) {
      wait('Checking for newer Discord uploads...', 'seeking-present');
      return;
    }
    const files=readCandidates(feed);
    remember(files);
    if (phase==='search' && recentPacks.size<recentPackLimit && backfillCount<maxBackfills && scroller) {
      const first=feed.querySelector('[data-list-item-id],[id^="chat-messages-"]');
      const firstId=first?.getAttribute('data-list-item-id')||first?.id||'';
      if (firstId===previousHistoryTop) unchangedHistory++;
      else unchangedHistory=0;
      previousHistoryTop=firstId;
      if (unchangedHistory<3) {
        backfillCount++;
        scroller.scrollTop=0;
        wait('Looking through recent Expansion Pack uploads...', 'searching-history');
        retry();
        return;
      }
    }
    phase='monitor';
    if (best && checkedPresent) show(best);
    else wait('No ZIP attachment was found in the loaded Discord history. Open the channel link below to check for updates.',
              'no-zip-found');
    // When new messages arrive, stay at present and compare new
    // Discord snowflakes; don't replace a newer file with an older
    // entry from a virtualized/scrolled message list.
    // Further uploads are handled by the existing DOM observer.
  }
  function schedule() {
    if (scheduled) return;
    scheduled=true;
    // Discord's live React tree produces many mutations per
    // frame. Cap full scans so downloads cannot starve the child
    // browser while a large file is opened externally.
    setTimeout(()=>{scheduled=false;refresh();},150);
  }
  window.__tes3npExpansionFocus=schedule;
  if (document.readyState==='loading')
    document.addEventListener('DOMContentLoaded',setup,{once:true});
  else setup();
})();