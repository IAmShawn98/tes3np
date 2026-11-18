(() => {
  const list = document.querySelector('[data-list-id="chat-messages"]');
  if (!list || document.readyState === 'loading') return null;

  // Discord can restore its last-read position. Read the live end of the channel.
  const chat = list.closest('[class*="chat_"], main') ?? list.parentElement;
  const jump = chat?.querySelector('[class*="jumpToPresentBar_"] button');
  if (jump) {
    if (window.__tes3npUpdatesJump !== jump) {
      window.__tes3npUpdatesJump = jump;
      jump.click();
    }
    return null;
  }

  const bodySelector = '[id^="message-content-"], [class*="messageContent_"], ' +
    '[class*="embedTitle_"], [class*="embedDescription_"], [class*="embedFieldName_"], [class*="embedFieldValue_"]';
  const updates = [];
  const rows = list.querySelectorAll('[id^="chat-messages-"]');
  if (!rows.length) return null;
  for (const row of rows) {
    const id = row.id.match(/^chat-messages-\d+-(\d+)$/)?.[1];
    if (!id) continue;
    const parts = [...row.querySelectorAll(bodySelector)]
      .filter(node => !node.parentElement?.closest(bodySelector))
      .map(node => (node.innerText || node.textContent || '').trim())
      .filter(Boolean);
    if (parts.length) updates.push({ Id: id, Body: [...new Set(parts)].join('\n').slice(0, 3801) });
  }
  return updates.slice(-12);
})()
