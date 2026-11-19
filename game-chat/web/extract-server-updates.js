((request = null) => {
  const list = document.querySelector('[data-list-id="chat-messages"]');
  if (!list || document.readyState === 'loading') return null;

  const pickerSelector = '[class^="emojiPicker_"], [class*=" emojiPicker_"], [aria-label="Emoji Picker" i]';
  const rows = list.querySelectorAll('[id^="chat-messages-"]');
  const messageId = row => row.id.match(/^chat-messages-510245417657827363-(\d+)$/)?.[1];

  function emojiSource(image) {
    const url = image?.getAttribute('src') || '';
    const custom = url.match(/^https:\/\/(?:cdn\.discordapp\.com|media\.discordapp\.net)\/emojis\/(\d+)\.(?:png|gif|webp|avif)(?:\?.*)?$/i);
    if (custom) return { id: custom[1], url };
    if (/^(?:https:\/\/discord\.com)?\/assets\/[a-z\d.-]+\.svg(?:\?.*)?$/i.test(url))
      return { id: null, url: new URL(url, 'https://discord.com').href };
    return { id: null, url: null };
  }

  function reactionsFor(row) {
    const reactions = [];
    const buttons = row.querySelectorAll('[class^="reaction_"], [class*=" reaction_"]');
    for (const button of buttons) {
      const count = button.querySelector('[class*="reactionCount_"]');
      const image = button.querySelector('img[alt]');
      const name = image?.alt || button.getAttribute('data-emoji-name');
      const total = Number(count?.textContent.replace(/[\s,]/g, ''));
      if (!name || !Number.isSafeInteger(total) || total < 1) continue;
      const source = emojiSource(image);
      const classes = button.getAttribute('class') || '';
      const burst = classes.includes('burstReaction') || classes.includes('shakeReaction');
      const key = (source.id || name) + (burst ? ':burst' : '');
      const control = button.matches('button, [role="button"]') ? button :
        button.querySelector('button, [role="button"]') ?? button;
      reactions.push({ button: control, value: { Key: key, Name: name, Image: source.url, Count: total,
        Mine: control.getAttribute('aria-pressed') === 'true' || button.getAttribute('aria-pressed') === 'true' ||
          classes.includes('reactionMe_') || (control.getAttribute('class') || '').includes('reactionMe_') } });
    }
    return reactions;
  }

  const emojiItemSelector = '[class^="emojiItem_"], [class*=" emojiItem_"], ' +
    '[data-type="emoji"], [role="gridcell"], button[data-emoji-id], button[data-name]';
  function getPicker() {
    return [...document.querySelectorAll(pickerSelector)].find(picker =>
      picker.querySelector('input, ' + emojiItemSelector));
  }

  function pickerChoices(picker) {
    const choices = new Map();
    const candidates = picker.querySelectorAll(emojiItemSelector);
    let scroller;
    for (let parent = candidates[0]?.parentElement; parent && picker.contains(parent); parent = parent.parentElement) {
      if (parent.scrollHeight > parent.clientHeight && /auto|scroll/.test(window.getComputedStyle(parent).overflowY)) {
        scroller = parent;
        break;
      }
    }
    for (const candidate of candidates) {
      const button = candidate.closest('button, [role="button"]') ??
        candidate.querySelector('button, [role="button"]') ?? candidate;
      if (!picker.contains(button) || button.disabled || button.getAttribute('aria-disabled') === 'true' ||
          /emojiItemDisabled|emojiItemLocked/.test(button.getAttribute('class') || '')) continue;
      const image = button.querySelector('img[alt]') ?? candidate.querySelector('img[alt]');
      const name = button.getAttribute('data-name') || button.getAttribute('data-emoji-name') ||
        candidate.getAttribute('data-name') || button.getAttribute('aria-label') || image?.alt;
      if (!name || typeof button.click !== 'function') continue;
      const source = emojiSource(image);
      const reactionKey = source.id || image?.alt || name;
      const key = source.id || button.getAttribute('data-emoji-id') || candidate.getAttribute('data-emoji-id') || name;
      choices.set(key, { button, value: { Key: key, Name: name, Text: image?.alt || name,
        Image: source.url, ReactionKey: reactionKey, Offset: Math.round(scroller?.scrollTop || 0) } });
    }
    return { choices, scroller };
  }

  if (request) {
    const row = [...rows].find(item => messageId(item) === request.Id);
    if (!row) return 'missing';
    if (request.Kind === 'read-reactions') return reactionsFor(row).map(item => item.value);
    if (request.Kind === 'toggle') {
      if (typeof request.Mine !== 'boolean') return 'unavailable';
      const reaction = reactionsFor(row).find(item => item.value.Key === request.Key);
      if ((reaction?.value.Mine ?? false) === request.Mine) return 'already';
      if (!reaction || reaction.button.disabled || reaction.button.getAttribute('aria-disabled') === 'true')
        return 'unavailable';
      reaction.button.click();
      return 'clicked';
    }
    if (request.Kind === 'picker') {
      if (getPicker()) {
        if (window.__tes3npPickerPost === request.Id) return 'clicked';
        const oldTrigger = window.__tes3npPickerTrigger;
        window.__tes3npPickerTrigger = null;
        if (oldTrigger?.isConnected) oldTrigger.click();
        return 'unavailable';
      }
      row.scrollIntoView({ block: 'center' });
      const message = row.querySelector('[class^="message_"], [class*=" message_"]') ?? row;
      message.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
      const add = row.querySelector('[class^="reactionBtn_"], [class*=" reactionBtn_"], ' +
        '[class*="addReactButton_"], [aria-label="Add Reaction" i], [data-list-item-id$="___add-reaction"]');
      if (!add || add.disabled || add.getAttribute('aria-disabled') === 'true') return 'unavailable';
      add.click();
      window.__tes3npPickerPost = request.Id;
      window.__tes3npPickerTrigger = add;
      return 'clicked';
    }
    if (window.__tes3npPickerPost !== request.Id) return 'missing';
    const picker = getPicker();
    if (!picker) return 'missing';
    if (request.Kind === 'picker-search') {
      const input = picker.querySelector('input[type="search"], input[role="searchbox"], input');
      if (!input) return 'unavailable';
      const { scroller } = pickerChoices(picker);
      if (scroller) scroller.scrollTop = 0;
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, request.Query || '');
      input.dispatchEvent(new Event('input', { bubbles: true }));
      return 'changed';
    }
    const { choices, scroller } = pickerChoices(picker);
    if (request.Kind === 'picker-page')
      return { Items: [...choices.values()].slice(0, 300).map(item => item.value),
        More: !!scroller && scroller.scrollTop + scroller.clientHeight < scroller.scrollHeight - 2 };
    if (request.Kind === 'picker-more' || request.Kind === 'picker-position') {
      if (scroller) scroller.scrollTop = request.Kind === 'picker-more'
        ? scroller.scrollTop + Math.max(1, scroller.clientHeight * 0.8) : request.Offset;
      return 'changed';
    }
    if (request.Kind === 'picker-select') {
      const choice = choices.get(request.Key);
      if (!choice) return 'unavailable';
      choice.button.click();
      return 'clicked';
    }
    return 'unavailable';
  }

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
  const updateIntro = /^\s*(?:\d{1,4}[/.\-]\d{1,2}[/.\-]\d{1,4}\s*[-–—:]?\s*)?server\s+update\s+notes[ \t]*:?[ \t]*(?:\r?\n|$)/i;

  function removeUpdateIntro(blocks) {
    // An intro can cross formatting runs or wrap at a Discord line break.
    const opening = blocks.slice(0, 3).map(block => block.Runs.map(run => run.Text).join('')).join('\n');
    let remaining = opening.match(updateIntro)?.[0].length || 0;
    while (remaining > 0 && blocks.length) {
      const block = blocks[0];
      for (const run of block.Runs) {
        const count = Math.min(remaining, run.Text.length);
        run.Text = run.Text.slice(count);
        remaining -= count;
      }
      block.Runs = block.Runs.filter(run => run.Text.length > 0);
      if (block.Runs.some(run => run.Text.trim())) return;
      blocks.shift();
      remaining--; // The separator added between blocks in "opening".
    }
  }

  function readBlocks(roots) {
    const blocks = [];
    let runs = [], style = '', number = 0, remaining = 3800;
    const flush = () => {
      if (runs.some(run => run.Text.trim())) blocks.push({ Style: style, Number: number, Runs: runs });
      runs = [];
    };
    const append = (text, bold) => {
      text = text.slice(0, remaining);
      if (!text) return;
      remaining -= text.length;
      const previous = runs.at(-1);
      if (previous?.Bold === bold) previous.Text += text;
      else runs.push({ Text: text, Bold: bold });
    };
    const visit = (node, bold = false) => {
      if (remaining <= 0) return;
      if (node.nodeType === 3) {
        append(node.textContent, bold);
        return;
      }
      if (node.nodeType !== 1) return;
      const tag = node.tagName;
      const classes = node.getAttribute('class') || '';
      // The DOM can contain hidden list separators that the Discord UI never paints.
      if (node.hasAttribute('hidden') || /visually[-_]?hidden|hidden[-_]?visually|screen[-_]?reader[-_]?only|\bsr-only\b/i.test(classes))
        return;
      if (!node.firstElementChild && node.textContent.trim() === ',') {
        const css = window.getComputedStyle(node);
        const bounds = node.getBoundingClientRect();
        if (css.display === 'none' || css.visibility === 'hidden' || css.visibility === 'collapse' ||
            css.opacity === '0' || (bounds.width <= 1 && bounds.height <= 1))
          return;
      }
      if (tag === 'BR') {
        flush();
        return;
      }
      if (tag === 'IMG') {
        if (classes.includes('emoji')) append(node.alt || '', bold);
        return;
      }
      const previousStyle = style, previousNumber = number;
      const heading = /^H[1-6]$/.test(tag) || classes.includes('embedTitle_') || classes.includes('embedFieldName_');
      const block = heading || ['P', 'DIV', 'LI', 'UL', 'OL', 'PRE', 'BLOCKQUOTE'].includes(tag);
      if (block) flush();
      if (heading) style = 'heading';
      if (tag === 'LI') {
        const parent = node.parentElement;
        style = parent?.tagName === 'OL' ? 'number' : 'bullet';
        if (style === 'number') number = [...parent.children].indexOf(node) + (Number(parent.getAttribute('start')) || 1);
      }
      for (const child of node.childNodes) visit(child, bold || tag === 'STRONG' || tag === 'B');
      if (block) {
        flush();
        style = previousStyle;
        number = previousNumber;
      }
    };
    for (const root of roots) {
      visit(root);
      flush();
    }
    return blocks;
  }

  function trimBlockEdges({ Runs: runs }) {
    // Keep inline formatting and spacing while removing blank lines at block edges.
    while (!runs[0].Text.trim()) runs.shift();
    while (!runs.at(-1).Text.trim()) runs.pop();
    runs[0].Text = runs[0].Text.trimStart();
    runs.at(-1).Text = runs.at(-1).Text.trimEnd();
  }

  const updates = [];
  if (!rows.length) return null;
  for (const row of rows) {
    const id = messageId(row);
    if (!id) continue;
    const roots = [...row.querySelectorAll(bodySelector)]
      .filter(node => !node.parentElement?.closest(bodySelector));
    const blocks = readBlocks(roots);
    removeUpdateIntro(blocks);
    if (blocks.length) {
      for (const block of blocks) trimBlockEdges(block);
      updates.push({ Id: id, Blocks: blocks, Reactions: reactionsFor(row).map(item => item.value) });
    }
  }
  return updates.slice(-12);
})
