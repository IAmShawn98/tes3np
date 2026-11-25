(expectedId => {
  if (location.origin !== 'https://discord.com' ||
      location.pathname.replace(/\/$/, '') !== '/channels/509601787901116437/511706884584243210') return null;
  const list = document.querySelector('[data-list-id="chat-messages"]');
  if (!list) return null;
  const rows = [...list.querySelectorAll('[id^="chat-messages-"]')]
    .filter(row => /^chat-messages-511706884584243210-\d+$/.test(row.id));
  const row = rows.at(-1);
  if (!row || row.id !== 'chat-messages-511706884584243210-' + expectedId) return null;
  const author = row.querySelector('[class*="username_"]');
  if (author?.textContent?.trim().toLowerCase() !== 'yagrum' ||
      !author.closest('h3, [class*="header_"]')?.querySelector('[class*="botTag_"]')) return null;
  const urls = [...row.querySelectorAll('a[href*="/attachments/"], img[src*="/attachments/"]')]
    .map(node => node.tagName === 'A' ? node.href : node.currentSrc || node.src)
    .filter(url => {
      try {
        const u = new URL(url);
        return u.protocol === 'https:' &&
          ['cdn.discordapp.com','media.discordapp.net'].includes(u.hostname) &&
          u.pathname.startsWith('/attachments/511706884584243210/');
      } catch { return false; }
    });
  const unique = new Map();
  for (const url of urls) {
    const u = new URL(url), key = u.pathname;
    if (!unique.has(key) || u.hostname === 'cdn.discordapp.com') unique.set(key, url);
  }
  return unique.size === 1 ? [...unique.values()][0] : null;
})