(fromHeader => {
  if (location.pathname !== '/login') return;
  const password = document.querySelector('input[type=password]');
  const form = password?.closest('form');
  if (!form) return;
  const firstPresentation = !form.hasAttribute('data-tes3np-login');
  form.setAttribute('data-tes3np-login', '');
  // Discord's responsive wrappers can become containing blocks
  // for the fixed form. Keep the actual form and React handlers
  // mounted, but let its box follow the browser viewport.
  for (let shell = form.parentElement; shell && shell !== document.body; shell = shell.parentElement)
    shell.setAttribute('data-tes3np-login-shell', '');
  let style = document.getElementById('tes3np-login-theme');
  if (!style) {
    style = document.createElement('style');
    style.id = 'tes3np-login-theme';
    document.head.appendChild(style);
  }
  if (!form.querySelector('[data-tes3np-login-heading]')) {
    const title = document.createElement('div');
    title.setAttribute('data-tes3np-login-heading', '');
    title.textContent = 'Discord Integration!';
    form.prepend(title);
  }
  // Hide the Discord logo and welcome panels by hiding
  // non-form siblings along the login container hierarchy.
  // Keep form siblings with controls (MFA, QR fallback, etc).
  let branch = form;
  for (let level = 0; level < 6; level++) {
    const parent = branch.parentElement;
    if (!parent || parent.id === 'app-mount' || parent === document.body) break;
    for (const sibling of parent.children) {
      if (sibling === branch || sibling.contains(form)) continue;
      if (sibling.querySelector('input,button,[role=button]')) continue;
      if (sibling.querySelector('svg,img,h1,h2,h3') &&
          !sibling.querySelector('form')) sibling.style.display='none';
    }
    branch = parent;
  }
  // Discord places its wordmark and welcome heading inside
  // the form in some layouts. Hide those specific decorations.
  for (const el of form.querySelectorAll('svg,img')) {
    if (el.closest('button,a,[role=button]')) continue;
    const block = el.closest('[class*="logo"],[class*="Logo"],[class*="header"],[class*="Header"]');
    if (block && block !== form && !block.querySelector('input')) block.style.display='none';
    else el.style.display='none';
  }
  for (const el of form.querySelectorAll('h1,h2,h3,div,span')) {
    if (el.children.length > 0) continue;
    const value = (el.textContent || '').trim();
    if (!/^(welcome back!?|we.re so excited to see you again!?)$/i.test(value)) continue;
    const block = el.closest('[class*="header"],[class*="Header"],[class*="title"],[class*="Title"]');
    if (block && block !== form && !block.querySelector('input')) block.style.display='none';
    else el.style.display='none';
  }
  // The gold scrollbar and frame belong to the message view,
  // not the Discord login page.
  document.getElementById('tes3np-chat-style')?.remove();
  document.getElementById('tes3np-frame')?.remove();
  // Discord can leave large empty spacer elements in its form.
  // Hide only elements without inputs, buttons, or links.
  for (const el of form.querySelectorAll('div')) {
    if (el.querySelector('input,button,a,[role=button],[role=link]')) continue;
    if (!el.textContent.trim() && !el.querySelector('img,svg,iframe'))
      el.style.display = 'none';
  }
  // Discord's recovery/account text is not always inside
  // the <form>. Search the entire login document and hide
  // only matching text elements, never the login controls.
  // Raw C# string: JS regex escapes must NOT be doubled.
  // Match the displayed phrases directly, including variants.
  const unwanted = text => {
    const t = (text || '').trim().toLowerCase();
    return t.startsWith('forgot your password') ||
      t.startsWith('need an account') ||
      t === 'register';
  };
  // Keep this idempotent: the login theme is reapplied while
  // Discord is loading and React may replace these elements.
  for (const el of document.querySelectorAll('a,[role=link],span,p,div')) {
    if (el === form || el.contains(form)) continue;
    if (el.querySelector('input,button,a,[role=link]')) continue;
    if (unwanted(el.textContent)) {
      el.style.setProperty('display', 'none', 'important');
    }
  }
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    if (!unwanted(node.textContent)) continue;
    const parent = node.parentElement;
    if (!parent || parent.closest('label,[type=submit]')) continue;
    parent.style.setProperty('display', 'none', 'important');
  }
  // Keep the introduction directly below the login heading.
  // Reposition on each refresh in case Discord rerenders the form.
  let benefit = document.querySelector('[data-tes3np-login-benefit]');
  if (!benefit) {
    benefit = document.createElement('p');
    benefit.setAttribute('data-tes3np-login-benefit', '');
  }
  const title = form.querySelector('[data-tes3np-login-heading]');
  if (title) {
    title.textContent = 'Discord Integration!';
    title.insertAdjacentElement('afterend', benefit);
  }
  benefit.textContent = fromHeader
    ? 'Discord integration enables live Game Chat, offline Happy Hour notifications, automated expansion pack installation, and more!'
    : "The feature you're trying to access requires Discord integration to function. Connecting to Discord unlocks realtime in-game chat, offline happy hour notifications, automatic expansion pack installation, and more!";
  let logo = form.querySelector('[data-tes3np-integration-logo]');
  if (!logo) {
    logo = document.createElement('img');
    logo.setAttribute('data-tes3np-integration-logo', '');
    logo.alt = 'Nerevarine Prophecies and Discord';
  }
  if (window.__tes3npIntegrationLogo) {
    logo.src = window.__tes3npIntegrationLogo;
    if (title) title.insertAdjacentElement('afterend', logo);
  }
  // Discord's passkey link can be outside the nested
  // password form, and Discord styles some form children
  // with explicit flex ordering. Appending to <form> was
  // therefore painting Not Now over the password fields.
  // Anchor it to the visible passkey row instead.
  let later = document.querySelector('[data-tes3np-not-now]');
  if (!later) {
    later = document.createElement('button');
    later.type = 'button';
    later.setAttribute('data-tes3np-not-now', '');
    later.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      try { chrome.webview.postMessage('tes3np-sign-in-later'); } catch {}
    });
  }
  later.textContent = 'Not Now';
  const passkey = [...document.querySelectorAll('a,button,[role=link],[role=button]')]
    .find(el => el !== later &&
      /sign in with a passkey/i.test(el.textContent || '') &&
      el.getClientRects().length > 0);
  if (passkey) {
    // Climb through link-only wrappers so the button lands
    // after the whole passkey row, not beside its text.
    let anchor = passkey;
    for (let depth = 0; depth < 4; depth++) {
      const parent = anchor.parentElement;
      if (!parent || parent === form || parent === document.body ||
          parent === document.documentElement ||
          parent.querySelector('input,button[type=submit]') ||
          parent.textContent.trim() !== anchor.textContent.trim())
        break;
      anchor = parent;
    }
    if (anchor.nextElementSibling !== later)
      anchor.insertAdjacentElement('afterend', later);
  } else if (later.isConnected) {
    // Do not put a fallback inside the password form.
    // The link appears once Discord completes rendering.
    later.remove();
  }
  style.textContent = `
    html:has([data-tes3np-login]), body:has([data-tes3np-login]) {
      margin:0 !important; padding:0 !important;
      background:#090807 !important; overflow:hidden !important; }
    [data-tes3np-login-shell]:has([data-tes3np-login]) {
      width:100% !important; min-width:0 !important; max-width:none !important;
      transform:none !important; translate:none !important;
      rotate:none !important; scale:none !important;
      perspective:none !important; filter:none !important;
      backdrop-filter:none !important; contain:none !important;
      container-type:normal !important; content-visibility:visible !important;
      will-change:auto !important; clip-path:none !important;
      overflow:visible !important;
    }
    [data-tes3np-login] > * { margin-top:0 !important; margin-bottom:0 !important; }
    [data-tes3np-login] div:empty { display:none !important; }
    [data-tes3np-login] {
      position:fixed !important; inset:10px 0 6px !important;
      width:auto !important; min-width:0 !important; max-width:none !important;
      height:auto !important; min-height:0 !important; max-height:none !important;
      transform:none !important; translate:none !important;
      margin:0 !important; padding:6px 12px 20px !important;
      overflow-y:auto !important; overflow-x:hidden !important;
      overscroll-behavior:contain !important;
      scrollbar-width:thin !important; scrollbar-color:#997644 #15100a !important;
      background:#090807 !important; border:0 !important;
      box-shadow:none !important; z-index:1000 !important;
      display:flex !important; flex-direction:column !important;
      gap:2px !important; box-sizing:border-box !important;
      font-family:"Palatino Linotype",Georgia,serif !important;
    }
    [data-tes3np-login] * { box-sizing:border-box !important; }
    [data-tes3np-integration-logo] {
      display:block !important; width:175px !important;
      height:135px !important; max-width:100% !important;
      object-fit:contain !important;
      margin:8px auto 4px !important; padding:0 !important;
    }
    [data-tes3np-login-benefit] {
      display:block !important;
      margin:3px 4px 8px !important;
      padding:5px 4px 0 !important;
      border-top:none !important;
      color:#ddc99d !important;
      font:13px/1.4 "Palatino Linotype",Georgia,serif !important;
      text-align:center !important;
      white-space:normal !important;
    }
    [data-tes3np-login] > div { min-height:0 !important; }
    [data-tes3np-login] > div:empty { display:none !important; }
    [data-tes3np-login] [class*="marginBottom"],
    [data-tes3np-login] [class*="marginTop"] {
      margin-top:0 !important; margin-bottom:0 !important;
    }
    [data-tes3np-login-heading] {
      text-align:center !important; color:#d9b469 !important;
      font:20px "Palatino Linotype",Georgia,serif !important;
      padding:8px 0 7px !important; margin:0 0 4px !important;
      border:0 !important; box-shadow:none !important;
      text-decoration:none !important;
    }
    [data-tes3np-login] label {
      color:#ddc99d !important; font:15px "Segoe UI",sans-serif !important;
      text-transform:none !important;
    }
    [data-tes3np-login] input {
      background:#100d09 !important; color:#f3e6c5 !important;
      border:1px solid #997644 !important; border-radius:0 !important;
      min-height:34px !important; height:34px !important;
      padding:5px 8px !important; width:100% !important;
      font:16px "Segoe UI",sans-serif !important;
    }
    [data-tes3np-login] button[type=submit] {
      background:#9b7439 !important; color:#fff0cb !important;
      border:1px solid #dfbb75 !important; border-radius:0 !important;
      min-height:35px !important; font:17px "Segoe UI",sans-serif !important;
    }
    [data-tes3np-login] a,[data-tes3np-login] [role=link],
    [data-tes3np-login] button[class*="link"] {
      color:#a85a31 !important; text-decoration:underline !important;
    }
    [data-tes3np-login] button,
    [data-tes3np-login] a,
    [data-tes3np-login] [role=button],
    [data-tes3np-login] [role=link] {
      cursor:pointer !important;
    }
    [data-tes3np-not-now] {
      display:block !important; position:static !important;
      order:2147483647 !important; flex:0 0 100% !important;
      grid-column:1/-1 !important; clear:both !important;
      width:100% !important; height:auto !important;
      min-height:44px !important; box-sizing:border-box !important;
      padding:9px 14px !important;
      margin:14px 0 12px !important;
      background:#991f1f !important; color:#fff !important;
      border:1px solid #dfbb75 !important; border-radius:0 !important;
      font:16px/1.4 "Segoe UI",sans-serif !important;
      text-align:center !important; cursor:pointer !important;
    }
    [data-tes3np-not-now]:hover {
      background:#b33030 !important;
    }
    @media (max-width:360px) {
      [data-tes3np-login] { padding-inline:8px !important; }
    }
    @media (max-height:480px) {
      [data-tes3np-login] { inset:0 !important; }
      [data-tes3np-integration-logo] {
        max-height:28vh !important;
        margin-block:4px 2px !important;
      }
    }
  `;
  if (firstPresentation) {
    const reset = () => {
      form.scrollTop = 0;
      document.documentElement.scrollTop = 0;
      if (document.scrollingElement) document.scrollingElement.scrollTop = 0;
    };
    // Discord may focus an input after React mounts and
    // restore an old scroll offset. Stop forcing the top as
    // soon as the player interacts with the form.
    let userInteracted = false;
    for (const eventName of ['pointerdown','keydown','wheel','touchstart'])
      form.addEventListener(eventName, () => { userInteracted = true; }, {once:true, passive:true});
    const resetIfUntouched = () => { if (!userInteracted) reset(); };
    resetIfUntouched();
    requestAnimationFrame(resetIfUntouched);
    setTimeout(resetIfUntouched, 180);
    setTimeout(resetIfUntouched, 500);
  }
})
