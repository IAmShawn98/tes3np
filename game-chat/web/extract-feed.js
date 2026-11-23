(() => {
  const list = document.querySelector('[data-list-id="chat-messages"]');
  if (!list) return '[]';
  const rows = [...list.querySelectorAll('[id^="chat-messages-"]')]
    .filter(el => /^chat-messages-[0-9]+-[0-9]+$/.test(el.id));
  const authors = rows.map(el => el.querySelector('[class*="username_"]'));
  // Read Discord's own palette before the compact theme recolors
  // usernames. Restore the stylesheet before reading message text.
  const theme = document.getElementById('tes3np-chat-style')?.sheet;
  const restoreTheme = theme && !theme.disabled;
  let authorColors;
  if (restoreTheme) theme.disabled = true;
  try {
    authorColors = authors.map(author => {
      if (!author) return '';
      const style = getComputedStyle(author);
      const color = style.getPropertyValue('--custom-display-name-styles-main-color').trim() ||
        style.getPropertyValue('--custom-gradient-color-1').trim() || style.color;
      // A transparent text fill from a visual effect would hide
      // the name without that effect. Use the chat color instead.
      const transparent = color === 'transparent' || /^rgba\(.*,\s*0\s*\)$/.test(color) || /\/\s*0\s*\)$/.test(color);
      return transparent ? '' : color;
    });
  } finally {
    if (restoreTheme) theme.disabled = false;
  }
  let lastVisibleAuthor = '';
  // Preserve an author already observed for this exact Discord message ID
  // when virtualized grouped messages lose their username header. Do not
  // infer authors for previously unseen headerless rows.
  const sourceAuthorById = window.__tes3npSourceAuthorById ||
    (window.__tes3npSourceAuthorById = new Map());
  if (sourceAuthorById.size > 5000) sourceAuthorById.clear();
  return JSON.stringify(rows.map((el, index) => {
    const usernameEl = authors[index];
    const user = usernameEl?.textContent?.trim() || '';
    if (user) lastVisibleAuthor = user;
    // Discord groups consecutive posts under one username.
    // Preserve the native chat layout's original user field,
    // but retain the source author when authenticating bot images.
    const sourceAuthor = user || sourceAuthorById.get(el.id) || lastVisibleAuthor;
    if (sourceAuthor) sourceAuthorById.set(el.id, sourceAuthor);
    // Reserve gold for the bot's own name, including when a
    // player chooses the same Discord display name.
    const isYagrum = user.toLowerCase() === 'yagrum' &&
      !!usernameEl?.closest('h3, [class*="header_"]')?.querySelector('[class*="botTag_"]');
    const contentNode = el.querySelector('[class*="messageContent_"]') ||
                        el.querySelector('[class*="markup_"]');
    const body = contentNode?.innerText?.trim() ||
                 contentNode?.textContent?.trim() || '';
    // Styled, rainbow Discord announcements may have per-letter
    // spans. Keep the raw textContent for independent detection.
    const matchText = contentNode?.textContent?.trim() || body;
    const media = [...el.querySelectorAll(
      '[class*="imageWrapper_"] img, [class*="imageContainer_"] img, ' +
      '[class*="attachment_"] img, [class*="embedMedia_"] img, ' +
      '[class*="embedImage_"] img, [class*="messageContent_"] img, ' +
      '[class*="markup_"] img, [class*="originalLink_"] img, ' +
      'a[href*="/attachments/"], a[href*="media.discordapp.net/"]'
    )];
    const urls = media.map(n => n.tagName === 'IMG'
        ? (n.currentSrc || n.src) : n.href)
      .filter(u => /^https:\/\//i.test(u) &&
        !/\/avatars\/|\/embed\/avatars\/|\/icons\/|\/emojis\//i.test(u) &&
        (/\.(png|jpe?g|gif|webp)(\?|$)/i.test(u) ||
         /\/(?:attachments|ephemeral-attachments)\//i.test(u)));
    // Discord exposes the same attachment through CDN and media-proxy URLs.
    // Deduplicate by attachment identity, not by the complete URL/query string.
    const uniqueImages = new Map();
    for (const url of urls) {
      try {
        const parsed = new URL(url);
        const match = parsed.pathname.match(/\/(?:attachments|ephemeral-attachments)\/([^?#]+)/i);
        const key = match ? 'attachment:' + match[1] : parsed.origin + parsed.pathname;
        const previous = uniqueImages.get(key);
        // Prefer the direct CDN link when both original and proxy are present.
        if (!previous || (parsed.hostname === 'cdn.discordapp.com' &&
            !previous.startsWith('https://cdn.discordapp.com/')))
          uniqueImages.set(key, url);
      } catch {}
    }
    return {id:el.id,user,sourceAuthor,body,matchText,isYagrum,authorColor:authorColors[index],images:[...uniqueImages.values()].slice(0,4)};
  }).filter(x => x.body || x.images.length));
})();