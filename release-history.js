/* TES3NP website release browser.
 * The verified alpha feed determines the downloadable version; only published
 * GitHub releases supply changelogs. The baked-in .21 page remains the fallback.
 */
(() => {
  'use strict';

  const repo = 'IAmShawn98/tes3np';
  const publishedUrl = 'https://api.github.com/repos/' + repo + '/releases?per_page=100';
  const feedUrl = 'https://raw.githubusercontent.com/' + repo + '/update-feed/alpha.json';
  const githubUrl = 'https://github.com/' + repo + '/releases/tag/';

  const byId = (id) => document.getElementById(id);
  const section = byId('latest-update');
  const releaseTab = byId('release-notes-tab');
  const hotfixTab = byId('hotfix-history-tab');
  const releasePanel = byId('release-notes-panel');
  const hotfixPanel = byId('hotfix-history-panel');

  if (!section || !releaseTab || !hotfixTab || !releasePanel || !hotfixPanel) {
    return;
  }

  const tabs = [releaseTab, hotfixTab];
  function showTab(selected) {
    tabs.forEach((tab) => {
      const active = tab === selected;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    releasePanel.hidden = selected !== releaseTab;
    hotfixPanel.hidden = selected !== hotfixTab;
  }

  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => showTab(tab));
    tab.addEventListener('keydown', (event) => {
      let selectedIndex = index;
      if (event.key === 'ArrowRight') selectedIndex = (index + 1) % tabs.length;
      else if (event.key === 'ArrowLeft') selectedIndex = (index + tabs.length - 1) % tabs.length;
      else if (event.key === 'Home') selectedIndex = 0;
      else if (event.key === 'End') selectedIndex = tabs.length - 1;
      else return;
      event.preventDefault();
      tabs[selectedIndex].focus();
      showTab(tabs[selectedIndex]);
    });
  });
  section.querySelector('.release-tabs').hidden = false;
  showTab(releaseTab);

  function parseTag(tag) {
    const match = /^v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})-alpha(?:\.([1-9][0-9]{0,8}))?$/.exec(tag);
    if (!match) return null;
    const feature = [Number(match[1]), Number(match[2]), Number(match[3])];
    return {
      tag,
      feature,
      hotfix: Number(match[4] || 0),
      baseTag: 'v' + feature.join('.') + '-alpha'
    };
  }

  function compareFeature(a, b) {
    for (let i = 0; i < 3; i += 1) {
      if (a.feature[i] !== b.feature[i]) return a.feature[i] - b.feature[i];
    }
    return a.hotfix - b.hotfix;
  }

  function formatDate(timestamp) {
    const date = new Date(timestamp);
    if (Number.isNaN(date.getTime())) return 'Publication date unavailable';
    return date.toLocaleDateString('en-US', {
      year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC'
    });
  }

  async function fetchJson(url) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 12000);
    try {
      const response = await fetch(url, {
        signal: controller.signal,
        cache: 'no-store',
        headers: { Accept: 'application/vnd.github+json, application/json' }
      });
      if (!response.ok) throw new Error('Public release lookup failed');
      return await response.json();
    } finally {
      clearTimeout(timeout);
    }
  }

  // Render public release Markdown through text nodes, never innerHTML.
  function addInline(target, source) {
    const text = String(source);
    const tokens = /(\*\*[^*]+\*\*|\[[^\]]+\]\(https:\/\/[^)\s]+\))/g;
    let last = 0;
    for (const match of text.matchAll(tokens)) {
      if (match.index > last) {
        target.appendChild(document.createTextNode(text.slice(last, match.index)));
      }
      const token = match[0];
      if (token.startsWith('**')) {
        const strong = document.createElement('strong');
        strong.textContent = token.slice(2, -2);
        target.appendChild(strong);
      } else {
        const linkMatch = /^\[([^\]]+)\]\((https:\/\/[^)\s]+)\)$/.exec(token);
        if (linkMatch) {
          const link = document.createElement('a');
          link.textContent = linkMatch[1];
          link.href = linkMatch[2];
          link.rel = 'noopener noreferrer';
          target.appendChild(link);
        }
      }
      last = match.index + token.length;
    }
    if (last < text.length) {
      target.appendChild(document.createTextNode(text.slice(last)));
    }
  }

  function renderNotes(markdown, target) {
    const fragment = document.createDocumentFragment();
    const lines = String(markdown || '').replace(/\r\n?/g, '\n').split('\n');
    let list = null;
    let paragraph = null;
    let entries = 0;

    for (const raw of lines) {
      const line = raw.trim();
      if (!line) {
        list = null;
        paragraph = null;
        continue;
      }

      // The visible release heading is already outside the notes panel.
      if (/^##\s+v[0-9]/.test(line)) {
        list = null;
        paragraph = null;
        continue;
      }

      const heading = /^(#{2,6})\s+(.+)$/.exec(line);
      if (heading) {
        const h = document.createElement(heading[1].length <= 3 ? 'h4' : 'h5');
        addInline(h, heading[2]);
        fragment.appendChild(h);
        list = null;
        paragraph = null;
        entries += 1;
        continue;
      }

      const bullet = /^[-*+]\s+(.+)$/.exec(line);
      if (bullet) {
        if (!list) {
          list = document.createElement('ul');
          fragment.appendChild(list);
        }
        const item = document.createElement('li');
        addInline(item, bullet[1]);
        list.appendChild(item);
        paragraph = null;
        entries += 1;
        continue;
      }

      list = null;
      if (!paragraph) {
        paragraph = document.createElement('p');
        fragment.appendChild(paragraph);
      } else {
        paragraph.appendChild(document.createTextNode(' '));
      }
      addInline(paragraph, line);
      entries += 1;
    }
    if (!entries) throw new Error('Published changelog is empty');
    target.replaceChildren(fragment);
  }

  function appendLink(target, title, url) {
    const link = document.createElement('a');
    link.textContent = title;
    link.href = url;
    link.rel = 'noopener noreferrer';
    target.appendChild(link);
  }

  function validateFeed(manifest) {
    if (!manifest || manifest.manifestVersion !== 2 ||
        manifest.product !== 'tes3np' || manifest.channel !== 'alpha' ||
        manifest.platform !== 'windows' || manifest.architecture !== 'x64' ||
        manifest.updateEnabled !== true || typeof manifest.version !== 'string') {
      throw new Error('Official alpha update feed is unavailable');
    }

    const id = 'v' + manifest.version;
    const info = parseTag(id);
    if (!info || manifest.releaseId !== id ||
        !manifest.package || typeof manifest.package !== 'object' ||
        manifest.package.fileName !== 'tes3np-' + id + '-windows.zip' ||
        !Number.isSafeInteger(manifest.package.size) || manifest.package.size <= 0 ||
        !/^[a-f0-9]{64}$/i.test(String(manifest.package.sha256 || ''))) {
      throw new Error('Official alpha update feed failed verification');
    }
    return info;
  }

  function publishedRelease(release) {
    return release && !release.draft && Boolean(release.published_at) &&
      typeof release.body === 'string' && Boolean(parseTag(release.tag_name));
  }

  async function loadPublishedHistory() {
    const [manifest, releaseList] = await Promise.all([
      fetchJson(feedUrl), fetchJson(publishedUrl)
    ]);
    const latest = validateFeed(manifest);
    if (!Array.isArray(releaseList)) throw new Error('Published release list is invalid');

    const published = releaseList.filter(publishedRelease);
    const latestRelease = published.find((release) => release.tag_name === latest.tag);
    const baseRelease = published.find((release) => release.tag_name === latest.baseTag);
    if (!latestRelease || !baseRelease || !baseRelease.body.trim()) {
      throw new Error('Verified release history is incomplete');
    }

    const exactAsset = Array.isArray(latestRelease.assets)
      ? latestRelease.assets.find((asset) =>
          asset.name === manifest.package.fileName &&
          asset.size === manifest.package.size && asset.state === 'uploaded')
      : null;
    if (!exactAsset) throw new Error('Verified public ZIP is not published');

    // Build all content before replacing the existing, working .21 fallback.
    const original = document.createElement('div');
    renderNotes(baseRelease.body, original);
    const history = document.createElement('div');
    const hotfixes = published.filter((release) => {
      const info = parseTag(release.tag_name);
      return info && info.baseTag === latest.baseTag &&
        info.hotfix > 0 && info.hotfix <= latest.hotfix;
    }).sort((a, b) => parseTag(b.tag_name).hotfix - parseTag(a.tag_name).hotfix);

    for (const release of hotfixes) {
      const article = document.createElement('article');
      article.className = 'release-hotfix';
      const heading = document.createElement('h4');
      heading.textContent = release.tag_name;
      article.appendChild(heading);
      const date = document.createElement('span');
      date.className = 'release-hotfix-date';
      date.textContent = 'Published ' + formatDate(release.published_at);
      article.appendChild(date);
      const body = document.createElement('div');
      renderNotes(release.body, body);
      article.appendChild(body);
      history.appendChild(article);
    }

    const previous = published.filter((release) => {
      const info = parseTag(release.tag_name);
      return info && info.hotfix === 0 && compareFeature(info, latest) < 0;
    }).sort((a, b) => compareFeature(parseTag(b.tag_name), parseTag(a.tag_name))).slice(0, 4);

    byId('release-notes-body').replaceChildren(...original.childNodes);
    byId('hotfix-history-body').replaceChildren(...history.childNodes);
    byId('hotfix-history-empty').hidden = hotfixes.length > 0;
    byId('release-version').textContent = latest.baseTag;
    byId('release-published-date').textContent = 'Published ' + formatDate(baseRelease.published_at);
    byId('release-current-build').textContent = 'Latest download: ' + latest.tag;

    const archive = byId('release-archive-links');
    archive.replaceChildren();
    if (previous.length) {
      previous.forEach((release) =>
        appendLink(archive, release.tag_name, githubUrl + release.tag_name));
    } else {
      archive.textContent = 'See GitHub Releases';
    }
    byId('current-release-link').href = githubUrl + latest.baseTag;

    // The download button follows the verified, published alpha feed only.
    const download = document.querySelector('.download-row .download');
    const downloadVersion = document.querySelector('.download-row .release');
    if (download && downloadVersion) {
      download.href = 'https://github.com/' + repo + '/releases/download/' +
        latest.tag + '/' + manifest.package.fileName;
      downloadVersion.textContent = latest.tag + ' · ZIP';
    }
    byId('release-history-status').textContent =
      'Showing officially published release notes from GitHub.';
  }

  loadPublishedHistory().catch(() => {
    // Preserve working download, original changelog and archive links.
    byId('hotfix-history-empty').textContent =
      'Live hotfix history is temporarily unavailable. Check GitHub Releases for the latest published fixes.';
    byId('release-history-status').textContent =
      'Live history could not be checked. Displaying the saved v0.1.21-alpha notes.';
  });
})();
