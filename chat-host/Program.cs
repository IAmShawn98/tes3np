using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;

internal static class Program
{
    const string ChatBuild = "chat-inset-native-frame-20261008";
    const string Channel = "https://discord.com/channels/509601787901116437/1384271857842130994";
    // Same NP Discord guild as Game Chat, but a different channel and raw WebView2.
    const string ExpansionChannel = "https://discord.com/channels/509601787901116437/1555049936800718928";
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr hwnd);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    static extern IntPtr SetWindowOwner64(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    static extern int SetWindowOwner32(IntPtr hwnd, int index, int value);
    static void SetNativeWindowOwner(IntPtr hwnd, IntPtr ownerHwnd)
    {
        const int GWLP_HWNDPARENT = -8;
        if (IntPtr.Size == 8) SetWindowOwner64(hwnd, GWLP_HWNDPARENT, ownerHwnd);
        else SetWindowOwner32(hwnd, GWLP_HWNDPARENT, ownerHwnd.ToInt32());
    }
    delegate void WinEventCallback(IntPtr hook, uint eventType, IntPtr hwnd,
        int objectId, int childId, uint eventThread, uint eventTime);
    [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax,
        IntPtr module, WinEventCallback callback, uint processId, uint threadId, uint flags);
    [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr hook);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr hwnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    const int DWMWA_CLOAK = 13;
    [DllImport("user32.dll", EntryPoint = "PostMessageW")] static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] struct COPYDATASTRUCT
    {
        public IntPtr dwData;
        public int cbData;
        public IntPtr lpData;
    }
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    static extern IntPtr SendCopyDataTimeout(IntPtr hwnd, uint msg, IntPtr sender,
        ref COPYDATASTRUCT data, uint flags, uint milliseconds, out IntPtr result);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetWindowLongEx(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern int SetWindowLongEx(IntPtr hwnd, int index, int value);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint colorKey, byte alpha, uint flags);
    const int GWL_EXSTYLE = -20, WS_EX_LAYERED = 0x80000;
    const int WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000;
    const uint LWA_ALPHA = 2;
    const int GWL_STYLE = -16, WS_CHILD = 0x40000000, WS_POPUP = unchecked((int)0x80000000);
    const string Css = """
        /* TES3NP compact, read-only message feed */
        :root, html, body, #app-mount {
          background: #17130e !important; color: #ead6aa !important;
          overflow: hidden !important;
        }
        [class*="guilds_"], [class*="sidebar_"], [class*="sidebarList_"],
        [class*="membersWrap_"], [class*="members_"], [class*="panels_"],
        [class*="form_"], [class*="channelTextArea_"], [class*="toolbar_"],
        [class*="notice_"], [class*="titleWrapper_"], [class*="upperContainer_"],
        [class*="chatHeaderBar_"], [class*="jumpToPresentBar_"],
        [class*="newMessagesBar_"], [class*="typing_"],
        [class*="avatar_"], [class*="botTag_"], [class*="buttons_"],
        [class*="channelName_"], [class*="chatHeader_"], [class*="searchBar_"],
        [class*="topic_"], [class*="titleContainer_"], [class*="threadSidebar_"],
        [class*="sidebarRegion_"], [class*="pageHeader_"],
        [class*="scrollerSpacer_"], [class*="welcomeMessage_"] {
          display: none !important;
        }
        [class*="base_"], [class*="content_"], [class*="chat_"],
        [class*="chatContent_"], [class*="messagesWrapper_"],
        [class*="scroller_"], [class*="scrollerContent_"] {
          width: 100% !important; min-width: 0 !important; max-width: 100% !important;
          margin: 0 !important; padding-left: 0 !important;
          padding-right: 0 !important; border: 0 !important;
        }
        [data-list-id="chat-messages"] { padding: 4px 0 8px !important; }
        [class*="message_"] {
          min-height: 0 !important; padding: 5px 10px !important;
          margin: 0 !important; background: transparent !important;
          border: 0 !important; box-shadow: none !important;
        }
        [class*="messageContent_"], [class*="markup_"] {
          font: 13px/1.4 Georgia, "Palatino Linotype", serif !important;
          color: #ead6aa !important; white-space: pre-wrap !important;
          overflow-wrap: anywhere !important; letter-spacing: .08px !important;
        }
        [class*="username_"] {
          font: bold 12px/1.35 Georgia, serif !important;
          color: #d8b26d !important; letter-spacing: .2px !important;
        }
        [class*="timestamp_"], [class*="divider_"], [class*="repliedMessage_"],
        [class*="messageAccessories_"], [class*="reaction_"],
        [class*="buttonContainer_"], [class*="messageToolbar_"] {
          display: none !important;
        }
        ::-webkit-scrollbar { width: 7px !important; }
        ::-webkit-scrollbar-track { background: #211a13 !important; }
        ::-webkit-scrollbar-thumb {
          background: #876a43 !important; border: 1px solid #3c2b1b !important;
          border-radius: 3px !important;
        }
        """;
    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length < 1 || !long.TryParse(args[0], out long owner)) return;
        ApplicationConfiguration.Initialize();
        Application.Run(new ChatHost(new IntPtr(owner)));
    }
    sealed class FrameOverlay : Control
    {
        public FrameOverlay()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = System.Drawing.Color.Transparent;
        }
        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (Width < 30 || Height < 60) return;
            using var outline = new System.Drawing.Region(new System.Drawing.Rectangle(0, 0, Width, Height));
            outline.Exclude(new System.Drawing.Rectangle(15, 53, Width - 30, Height - 69));
            Region = outline.Clone();
            Invalidate();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            int w = Width, h = Height;
            if (w < 30 || h < 60) return;
            using var bronze = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(114, 83, 43));
            using var dark = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(14, 11, 8));
            using var gold = new System.Drawing.Pen(System.Drawing.Color.FromArgb(210, 180, 116), 2);
            using var inner = new System.Drawing.Pen(System.Drawing.Color.FromArgb(63, 43, 22), 2);
            using var ink = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(220, 187, 120));
            using var font = new System.Drawing.Font("Georgia", 12, System.Drawing.FontStyle.Regular);
            g.FillRectangle(bronze, 0, 0, w, 49);
            g.FillRectangle(bronze, 0, 53, 15, h - 53);
            g.FillRectangle(bronze, w - 15, 53, 15, h - 53);
            g.FillRectangle(bronze, 0, h - 16, w, 16);
            // Deterministic weathered bronze flecks approximate the in-game metalwork.
            var rng = new Random(5318);
            for (int n = 0; n < w * 2; n++)
            {
                int x = rng.Next(w), y = rng.Next(h);
                if (y >= 53 && x >= 15 && x < w - 15 && y < h - 16) continue;
                int v = rng.Next(0, 3);
                using var fleck = new System.Drawing.SolidBrush(
                    v == 0 ? System.Drawing.Color.FromArgb(62, 45, 24) :
                    v == 1 ? System.Drawing.Color.FromArgb(161, 128, 75) :
                             System.Drawing.Color.FromArgb(194, 159, 97));
                g.FillRectangle(fleck, x, y, rng.Next(1, 4), rng.Next(1, 3));
            }
            g.DrawRectangle(gold, 2, 2, w - 5, h - 5);
            g.DrawRectangle(inner, 6, 6, w - 13, h - 13);
            g.DrawLine(gold, 8, 50, w - 9, 50);
            var size = g.MeasureString("Chat", font);
            g.FillRectangle(dark, (w - size.Width) / 2 - 17, 5, size.Width + 34, 34);
            g.DrawString("Chat", font, ink, (w - size.Width) / 2, 8);
        }
    }
    sealed class BufferedScrollbar : Panel
    {
        public BufferedScrollbar()
        {
            DoubleBuffered = true;
            ResizeRedraw = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer, true);
        }
    }
    sealed class ScrollbarFreeRichTextBox : RichTextBox
    {
        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.Style &= ~0x00200000; // WS_VSCROLL
                cp.Style &= ~0x00100000; // WS_HSCROLL
                return cp;
            }
        }
    }
    sealed class ChatHost : Form
    {
        // WinForms shows its main Form before the Shown callback can dock it.
        // Cloak the very first HWND before that native show. Unlike hiding the
        // Form or moving it off-screen, this leaves the normal WinForms/WebView2
        // initialization lifecycle intact without painting an undocked window.
        bool startupPresentationPending = true;
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            if (startupPresentationPending)
                SetStartupWindowCloak(true);
        }
        void SetStartupWindowCloak(bool cloak)
        {
            if (!IsHandleCreated) return;
            int value = cloak ? 1 : 0;
            int hr = DwmSetWindowAttribute(Handle, DWMWA_CLOAK, ref value, sizeof(int));
            if (hr != 0)
                Log($"STARTUP | Window cloak {(cloak ? "enable" : "disable")} failed (0x{hr:X8})");
        }

    int ChatFirstLine() => browserScrollTop;
    int ChatLineCount() => Math.Max(1, browserScrollHeight);
    int ChatVisibleLines() => Math.Max(1, browserClientHeight);
    int ChatThumbY(int height, out int thumbHeight)
    {
        int track = Math.Max(1, height - 54);
        int total = ChatLineCount(), visible = ChatVisibleLines();
        thumbHeight = Math.Clamp((int)((long)track * Math.Min(total, visible) / total), Math.Min(20, track), track);
        return 27 + (int)((long)Math.Clamp(browserScrollTop, 0, Math.Max(0, total-visible))
            * (track-thumbHeight) / Math.Max(1,total-visible));
    }
    void ScrollChatToThumb(int y, int dragOffset)
    {
        if (!messageBrowserReady) return;
        int track = Math.Max(1, goldScrollbar.Height-54);
        ChatThumbY(goldScrollbar.Height, out int thumbHeight);
        double fraction = (double)Math.Clamp(y-dragOffset-27,0,Math.Max(1,track-thumbHeight)) /
            Math.Max(1,track-thumbHeight);
        _ = messageBrowser.CoreWebView2.ExecuteScriptAsync(
            "window.scrollFraction(" + fraction.ToString(System.Globalization.CultureInfo.InvariantCulture) + ")");
        if (fraction > 0.05) historyCatchupActive = false;
        if (fraction <= 0.01)
        {
            userScrolledChat = true;
            RequestOlderMessages(forceTop: true);
        }
    }


        readonly IntPtr owner;
        readonly WebView2 web = new() { Dock = DockStyle.None };
        // The download browser lives in the EXISTING ChatHost but is a native
        // child of the AutoHotkey mismatch dialog, not another owned popup.
        CoreWebView2Environment? discordEnvironment;
        Form? expansionDownloadsWindow;
        WebView2? expansionDownloadsBrowser;
        IntPtr expansionDownloadsParent = IntPtr.Zero;
        bool expansionDownloadsInitializing;
        // The latest *validated* signed URL lives only in this ChatHost
        // session; native retry never depends on a responsive WebView2.
        string? expansionLatestZipUrl;
        // Discord feature dialogs reuse the existing Chat Host authentication.
        int pendingExpansionPrompt;
        bool restoreChatAfterExpansionPrompt;
        readonly object expansionLinkPublishLock=new();
        // A single cancellable background transfer per Chat Host. The signed
        // CDN query remains in memory, never in a command line or log file.
        int expansionAutoDownloading;
        CancellationTokenSource? expansionAutoDownloadCancellation;
        readonly string expansionAutoDownloadFolder=Path.Combine(ChatDataRoot,"expansion-downloads");

        // Preserve Discord's React tree and grid intact behind an opaque card.
        // Extract ONLY the latest visible official ZIP attachment and link to
        // its actual Discord CDN URL. Never create a fake download link.
        // The Discord message list is virtualized. Only show a ZIP after we
        // reach the newest messages; compare real Discord snowflake IDs rather
        // than treating the last rendered anchor as the latest upload. A
        // bounded backfill handles archives where the ZIP is off-screen.
        // Discord can still change its DOM; the manual channel link remains.
        const string ExpansionDownloadsFocusScript = """
            (() => {
              if (window.__tes3npExpansionFocus) {
                window.__tes3npExpansionFocus(); return;
              }
              const channel='/channels/509601787901116437/1555049936800718928';
              const attachmentHost=/^https:\/\/(?:cdn\.discordapp\.com|media\.discordapp\.net)\/attachments\//i;
              let scheduled=false, retryPending=false, lastStatus='', lastFileKey='';
              let panel, status, sender, link, size;
              let best=null, checkedPresent=false, backfillCount=0, phase='present';
              let previousHistoryTop='', unchangedHistory=0, loadingRetries=0, presentRetries=0;
              const maxBackfills=12, maxLoadingRetries=30, maxPresentRetries=18;

              function report(value) {
                if (value===lastStatus) return;
                lastStatus=value;
                try { chrome.webview.postMessage({type:'expansion-layout',status:value}); } catch {}
              }
              function setup() {
                if (panel || !document.documentElement) return;
                const style=document.createElement('style');
                style.textContent=[
                  '#tes3np-zip-card {position:fixed!important;inset:0!important;',
                  'z-index:2147483647!important;display:flex!important;',
                  'flex-direction:column!important;justify-content:center!important;',
                  'box-sizing:border-box!important;padding:12px 16px!important;',
                  'background:#1b1b1f!important;color:#ece4d4!important;',
                  'font:14px/1.5 "Segoe UI",Arial,sans-serif!important;overflow:auto!important}',
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
                  if (!/\.zip$/i.test(filename)) continue;
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
              function remember(candidates) {
                for (const item of candidates) {
                  // Snowflakes are chronological; when Discord's message ID
                  // metadata is missing, DOM order is a best-effort fallback.
                  if (!best ||
                      (item.id!==null && best.id!==null && item.id>best.id) ||
                      (item.id===best.id && item.order>=best.order) ||
                      (item.id!==null && best.id===null)) best=item;
                }
              }
              function show(file) {
                const key=file.url+'|'+file.filename+'|'+file.sender+'|'+file.bytes;
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
                try { chrome.webview.postMessage({type:'expansion-available',url:file.url}); } catch {}
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
                if (phase==='search' && !best && backfillCount<maxBackfills && scroller) {
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
            """;

        void CloseEmbeddedExpansionDownloads(IntPtr requestedParent = default)
        {
            if (requestedParent != IntPtr.Zero && requestedParent != expansionDownloadsParent)
                return;
            try { expansionAutoDownloadCancellation?.Cancel(); }
            catch (ObjectDisposedException) { }
            expansionDownloadsParent=IntPtr.Zero;
            expansionLatestZipUrl=null;
            var window=expansionDownloadsWindow;
            expansionDownloadsWindow=null;
            expansionDownloadsBrowser=null;
            if (window is { IsDisposed: false }) {
                try { window.Dispose(); }
                catch (Exception ex) { Log("EXPANSION | Child cleanup: "+ex.GetType().Name); }
            }
        }

        void ShowEmbeddedExpansionDownloads(IntPtr placeholder)
        {
            if (!discordChannelReady || discordLoginVisible || closingChat)
            {
                Log("EXPANSION | Refused unauthenticated embedded Discord surface.");
                return;
            }
            if (closingChat || !IsWindow(owner) || !IsWindow(placeholder)) return;
            if (expansionDownloadsParent==placeholder &&
                expansionDownloadsWindow is { IsDisposed: false }) return;
            CloseEmbeddedExpansionDownloads();
            try
            {
                var window=new Form {
                    Text="tes3np Expansion ZIP",FormBorderStyle=FormBorderStyle.None,
                    ShowInTaskbar=false,StartPosition=FormStartPosition.Manual,
                    BackColor=System.Drawing.Color.FromArgb(27,27,31),
                    AutoScaleMode=AutoScaleMode.None
                };
                var browser=new WebView2 { Dock=DockStyle.Fill };
                window.Controls.Add(browser);
                // Register before native reparenting so even a failed SetParent
                // disposes the newly created Form and WebView2 together.
                expansionDownloadsWindow=window;
                expansionDownloadsBrowser=browser;
                expansionDownloadsParent=placeholder;
                IntPtr handle=window.Handle;
                int style=GetWindowLong(handle,GWL_STYLE);
                const int WS_CLIPSIBLINGS=0x04000000;
                SetWindowLong(handle,GWL_STYLE,
                    (style | WS_CHILD | WS_CLIPSIBLINGS) & ~WS_POPUP);
                SetParent(handle,placeholder);
                if (GetParent(handle)!=placeholder)
                    throw new InvalidOperationException("Discord browser did not attach to the dialog.");
                PositionEmbeddedExpansionDownloads();
                ShowWindow(handle,5);
                _=InitializeExpansionDownloadsBrowser();
                Log("EXPANSION | Embedded newest ZIP in plugin-mismatch dialog.");
            }
            catch(Exception ex)
            {
                Log("EXPANSION | Cannot mount browser: "+ex.GetType().Name);
                CloseEmbeddedExpansionDownloads();
            }
        }

        void HideEmbeddedExpansionDownloads(IntPtr placeholder)
        {
            // Never tear down or reparent a live WebView2 because a download
            // started. Hiding its native child keeps the shared Discord
            // environment and Game Chat untouched, and lets the launcher-owned
            // ZIP button handle subsequent clicks independently.
            if (placeholder==IntPtr.Zero || placeholder!=expansionDownloadsParent ||
                expansionLatestZipUrl==null || !IsWindow(placeholder))
                return;
            var window=expansionDownloadsWindow;
            if (window==null || window.IsDisposed || !window.IsHandleCreated)
                return;
            ShowWindow(window.Handle,0); // SW_HIDE; no Dispose and no new Form
            Log("EXPANSION | Discovery WebView hidden; launcher-native ZIP card remains.");
        }

        void PositionEmbeddedExpansionDownloads()
        {
            var window=expansionDownloadsWindow;
            if (window==null || window.IsDisposed || !window.IsHandleCreated ||
                !IsWindow(expansionDownloadsParent)) return;
            if (!GetClientRect(expansionDownloadsParent,out var box)) return;
            MoveWindow(window.Handle,0,0,Math.Max(1,box.Right-box.Left),
                Math.Max(1,box.Bottom-box.Top),true);
        }

        static bool IsOfficialExpansionDownloadUrl(string? value)
        {
            if (string.IsNullOrWhiteSpace(value) ||
                !Uri.TryCreate(value, UriKind.Absolute, out var uri))
                return false;
            if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
                (uri.Host != "cdn.discordapp.com" && uri.Host != "media.discordapp.net") ||
                uri.UserInfo.Length != 0 || !uri.AbsolutePath.StartsWith("/attachments/", StringComparison.Ordinal))
                return false;
            try {
                var filename=Uri.UnescapeDataString(
                    System.IO.Path.GetFileName(uri.AbsolutePath));
                return filename.EndsWith(".zip", StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        // Each click is an independent request; a cancelled browser download
        // cannot leave a busy flag set or disable a second attempt.
        void RequestExpansionDownload(string? url, string origin)
        {
            if (!IsOfficialExpansionDownloadUrl(url))
            {
                Log("EXPANSION | Download request rejected: invalid ZIP URL ("+origin+").");
                return;
            }
            string freshUrl=url!;
            // The original Discord popup stays open and is never rebuilt per
            // download. Cross-process WebView2 teardown on every click could
            // deadlock the launcher after one or two attempts.
            _=Task.Run(()=>{
                try {
                    using var started=System.Diagnostics.Process.Start(
                        new System.Diagnostics.ProcessStartInfo {
                            FileName=freshUrl,
                            UseShellExecute=true
                        });
                    if (started==null)
                        Log("EXPANSION | Shell returned no process handle ("+origin+").");
                    else
                        Log("EXPANSION | ZIP sent to default browser ("+origin+").");
                }
                catch (Exception ex) {
                    Log("EXPANSION | Browser ZIP handoff failed ("+origin+"): "+ex.GetType().Name);
                }
            });
        }

        // Command 13 is accepted only for the CURRENT authenticated Discord
        // preview slot. No generic external URL or arbitrary file path is
        // accepted from the launcher.
        void StartExpansionAutoDownload(IntPtr slot)
        {
            if (slot == IntPtr.Zero || slot != expansionDownloadsParent ||
                !IsWindow(slot) || !IsWindow(owner) || closingChat ||
                !discordChannelReady || discordLoginVisible ||
                !IsOfficialExpansionDownloadUrl(expansionLatestZipUrl))
            {
                Log("EXPANSION | Automatic download denied: no authenticated current ZIP.");
                if (slot==expansionDownloadsParent && IsWindow(owner))
                    PostMessage(owner,0x8338,new IntPtr(-1),Handle);
                return;
            }
            if (System.Threading.Interlocked.CompareExchange(ref expansionAutoDownloading,1,0)!=0)
            {
                PostMessage(owner,0x8338,new IntPtr(-1),Handle);
                return;
            }
            var cancellation=new CancellationTokenSource(TimeSpan.FromHours(4));
            expansionAutoDownloadCancellation=cancellation;
            string url=expansionLatestZipUrl!;
            IntPtr sender=Handle; // Capture HWND on the WinForms thread.
            PostMessage(owner,0x8338,IntPtr.Zero,sender);
            _=Task.Run(()=>DownloadExpansionZipAsync(url,slot,sender,cancellation));
        }

        async Task DownloadExpansionZipAsync(string url,IntPtr slot,IntPtr sender,
            CancellationTokenSource cancellation)
        {
            string? partial=null,completed=null;
            bool accepted=false;
            try
            {
                Directory.CreateDirectory(expansionAutoDownloadFolder);
                // Never trust a CDN-supplied filename for a local path.
                string stem="tes3np-"+Guid.NewGuid().ToString("N");
                partial=Path.Combine(expansionAutoDownloadFolder,stem+".partial");
                completed=Path.Combine(expansionAutoDownloadFolder,stem+".zip");
                using var handler=new HttpClientHandler { AllowAutoRedirect=false,UseCookies=false };
                using var client=new HttpClient(handler) { Timeout=System.Threading.Timeout.InfiniteTimeSpan };
                using var response=await client.GetAsync(url,
                    HttpCompletionOption.ResponseHeadersRead,cancellation.Token);
                response.EnsureSuccessStatusCode();
                const long maxZipBytes=16L*1024*1024*1024;
                long? declared=response.Content.Headers.ContentLength;
                if (declared.HasValue && (declared.Value<=0 || declared.Value>maxZipBytes))
                    throw new InvalidDataException("ZIP size outside allowed range.");
                var drive=new DriveInfo(Path.GetPathRoot(expansionAutoDownloadFolder)!);
                long space=drive.AvailableFreeSpace;
                if (space<512L*1024*1024 ||
                    (declared.HasValue && declared.Value>space-512L*1024*1024))
                    throw new IOException("Insufficient disk space for Expansion Pack download.");
                await using (var input=await response.Content.ReadAsStreamAsync(cancellation.Token))
                await using (var output=new FileStream(partial,FileMode.CreateNew,FileAccess.Write,
                    FileShare.None,131072,useAsync:true))
                {
                    byte[] buffer=new byte[131072];
                    long received=0;
                    int previousPercent=-1;
                    long lastReport=Environment.TickCount64;
                    int count;
                    while ((count=await input.ReadAsync(buffer,cancellation.Token))!=0)
                    {
                        received+=count;
                        if (received>maxZipBytes || received>space-512L*1024*1024)
                            throw new IOException("Expansion Pack download exceeded available space.");
                        await output.WriteAsync(buffer.AsMemory(0,count),cancellation.Token);
                        int percent=declared.HasValue
                            ? (int)Math.Clamp(received*100/declared.Value,1,99) : 0;
                        long now=Environment.TickCount64;
                        if (percent!=previousPercent && now-lastReport>=250)
                        {
                            PostMessage(owner,0x8338,new IntPtr(percent),sender);
                            previousPercent=percent;
                            lastReport=now;
                        }
                    }
                    if (received==0 || (declared.HasValue && received!=declared.Value))
                        throw new InvalidDataException("ZIP download was incomplete.");
                    await output.FlushAsync(cancellation.Token);
                }
                // Reject error pages masquerading as ZIPs before importing.
                using (var check=File.OpenRead(partial))
                {
                    byte[] prefix=new byte[4];
                    if (check.Read(prefix,0,4)!=4 || prefix[0]!=0x50 ||
                        prefix[1]!=0x4B || prefix[2]!=0x03 || prefix[3]!=0x04)
                        throw new InvalidDataException("Downloaded file is not a ZIP archive.");
                }
                cancellation.Token.ThrowIfCancellationRequested();
                File.Move(partial,completed);
                partial=null;
                string payload=slot.ToInt64().ToString(
                    System.Globalization.CultureInfo.InvariantCulture)+"|"+completed;
                IntPtr utf16=IntPtr.Zero;
                try
                {
                    utf16=Marshal.StringToHGlobalUni(payload);
                    var data=new COPYDATASTRUCT {
                        dwData=new IntPtr(0x8337),
                        cbData=checked((payload.Length+1)*2),
                        lpData=utf16
                    };
                    // Bounded IPC; AHK queues the importer after returning.
                    IntPtr delivered=SendCopyDataTimeout(owner,0x004A,sender,
                        ref data,0x0002,1500,out var acknowledged);
                    accepted=delivered!=IntPtr.Zero && acknowledged!=IntPtr.Zero;
                }
                finally { if (utf16!=IntPtr.Zero) Marshal.FreeHGlobal(utf16); }
                if (accepted) Log("EXPANSION | Verified ZIP transferred to installer.");
                else Log("EXPANSION | Download completed but installer did not acknowledge.");
            }
            catch (OperationCanceledException)
            {
                Log("EXPANSION | Automatic download cancelled or timed out.");
            }
            catch (Exception ex)
            {
                // Never log signed CDN URLs, private paths or exception messages.
                Log("EXPANSION | Automatic download failed: "+ex.GetType().Name);
            }
            finally
            {
                if (partial!=null) try { File.Delete(partial); } catch { }
                if (!accepted && completed!=null) try { File.Delete(completed); } catch { }
                if (!accepted && !cancellation.IsCancellationRequested)
                    PostMessage(owner,0x8338,new IntPtr(-1),sender);
                if (ReferenceEquals(expansionAutoDownloadCancellation,cancellation))
                    expansionAutoDownloadCancellation=null;
                System.Threading.Interlocked.Exchange(ref expansionAutoDownloading,0);
                cancellation.Dispose();
            }
        }

        // Share the validated signed CDN URL with the AHK-owned dialog
        // exactly once per discovered/updated ZIP. Its native retry button
        // must NOT depend on this WinForms message loop or a WebView repaint.
        void PublishExpansionUrlToLauncher(string url)
        {
            if (!IsOfficialExpansionDownloadUrl(url)) return;
            IntPtr slot=expansionDownloadsParent;
            if (slot==IntPtr.Zero || !IsWindow(slot) || !IsWindow(owner))
                return;
            // Snapshot sender HWND while on the WinForms UI thread. Never
            // access Control.Handle from the background IPC worker.
            IntPtr sender=Handle;
            _=Task.Run(()=>{
                lock (expansionLinkPublishLock)
                {
                    // A previously queued signed URL must never replace a
                    // newer ZIP or a link from a freshly recreated dialog.
                    if (expansionLatestZipUrl!=url || expansionDownloadsParent!=slot)
                        return;
                    string payload=slot.ToInt64().ToString(
                        System.Globalization.CultureInfo.InvariantCulture)+"|"+url;
                    IntPtr utf16=IntPtr.Zero;
                    try
                    {
                        utf16=Marshal.StringToHGlobalUni(payload);
                        var data=new COPYDATASTRUCT {
                            dwData=new IntPtr(0x8335),
                            cbData=checked((payload.Length+1)*2),
                            lpData=utf16
                        };
                        // SMTO_ABORTIFHUNG. Bounded IPC keeps the Chat Host
                        // independent if AHK's owner window becomes busy.
                        IntPtr delivered=SendCopyDataTimeout(owner,0x004A,sender,
                            ref data,0x0002,1500,out var result);
                        if (delivered==IntPtr.Zero || result==IntPtr.Zero)
                            Log("EXPANSION | Native ZIP retry link handoff was not acknowledged.");
                        else
                            Log("EXPANSION | Native ZIP retry link synchronized.");
                    }
                    catch (Exception ex)
                    {
                        Log("EXPANSION | Native ZIP link handoff failed: "+ex.GetType().Name);
                    }
                    finally
                    {
                        if (utf16!=IntPtr.Zero) Marshal.FreeHGlobal(utf16);
                    }
                }
            });
        }

        async Task InitializeExpansionDownloadsBrowser()
        {
            var browser=expansionDownloadsBrowser;
            var env=discordEnvironment;
            if (browser==null || browser.IsDisposed || env==null ||
                expansionDownloadsInitializing || browser.CoreWebView2!=null ||
                closingChat || !IsWindow(expansionDownloadsParent)) return;
            expansionDownloadsInitializing=true;
            try
            {
                await browser.EnsureCoreWebView2Async(env);
                if (closingChat || browser.IsDisposed || browser.CoreWebView2==null) return;
                await browser.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(
                    ExpansionDownloadsFocusScript);
                browser.CoreWebView2.WebMessageReceived+=(_,args)=>{
                    try {
                        using var json=System.Text.Json.JsonDocument.Parse(args.WebMessageAsJson);
                        if (!json.RootElement.TryGetProperty("type",out var kind)) return;
                        string? type=kind.GetString();
                        if (type=="expansion-layout" &&
                            json.RootElement.TryGetProperty("status",out var state))
                        {
                            Log("EXPANSION | ZIP card status updated.");
                        }
                        else if ((type=="expansion-available" || type=="expansion-download") &&
                            json.RootElement.TryGetProperty("url",out var requested) &&
                            requested.ValueKind==System.Text.Json.JsonValueKind.String)
                        {
                            string? link=requested.GetString();
                            if (!IsOfficialExpansionDownloadUrl(link))
                            {
                                Log("EXPANSION | Rejected invalid Discord ZIP link.");
                                return;
                            }
                            // A new post or refreshed CDN signature replaces the
                            // stored URL. Never persist it or log its auth query.
                            if (expansionLatestZipUrl!=link)
                            {
                                expansionLatestZipUrl=link;
                                PublishExpansionUrlToLauncher(link!);
                            }
                            if (type=="expansion-download")
                                RequestExpansionDownload(link,"embedded-card");
                        }
                    }
                    catch (Exception ex) {
                        Log("EXPANSION | Invalid download message: "+ex.GetType().Name);
                    }
                };
                browser.CoreWebView2.NavigationCompleted+=async (_,e)=>{
                    Log("EXPANSION | Discord page "+(e.IsSuccess?"loaded":"failed: "+e.WebErrorStatus));
                    if (!e.IsSuccess || browser.IsDisposed || browser.CoreWebView2==null) return;
                    try { await browser.CoreWebView2.ExecuteScriptAsync(ExpansionDownloadsFocusScript); }
                    catch (Exception ex) { Log("EXPANSION | Card refresh: "+ex.GetType().Name); }
                };
                // Defensive only: downloads are dispatched through WebMessageReceived.
                // An unexpected WebView2 download must not silently replace the
                // authenticated channel or navigate away from this ZIP card.
                browser.CoreWebView2.DownloadStarting+=(_,e)=>{
                    Log("EXPANSION | Unexpected in-WebView download; deferring to default browser.");
                    e.Cancel=true;
                };
                browser.CoreWebView2.Navigate(ExpansionChannel);
            }
            catch(Exception ex) { if (!closingChat) Log("EXPANSION | Embed load failed: "+ex.GetType().Name); }
            finally { expansionDownloadsInitializing=false; }
        }

        // A separate clipped viewport prevents the WebView's negative Y offset
        // from covering the custom frame and title.
        readonly Panel frameSurface = new() { BackColor = System.Drawing.Color.FromArgb(164, 128, 69), Margin = Padding.Empty };
        readonly Panel chatViewport = new() { BackColor = System.Drawing.Color.FromArgb(9, 8, 7), Margin = Padding.Empty };
        readonly Panel titleBar = new() { BackColor = System.Drawing.Color.FromArgb(115, 85, 43) };
        readonly Panel railLeft = new() { BackColor = System.Drawing.Color.FromArgb(164, 128, 69) };
        readonly Panel railRight = new() { BackColor = System.Drawing.Color.FromArgb(164, 128, 69) };
        readonly Panel railBottom = new() { BackColor = System.Drawing.Color.FromArgb(164, 128, 69) };
        readonly Panel railTop = new() { BackColor = System.Drawing.Color.FromArgb(164, 128, 69) };
        readonly FrameOverlay frame = new();
        readonly Label titleText = new() {
            Text = "Chat", TextAlign = System.Drawing.ContentAlignment.MiddleCenter,
            ForeColor = System.Drawing.Color.FromArgb(224, 194, 131),
            BackColor = System.Drawing.Color.FromArgb(18, 14, 10),
            Font = new System.Drawing.Font("Georgia", 14, System.Drawing.FontStyle.Bold)
        };


        static System.Drawing.Bitmap? LoadTexture(string filename)
        {
            try
            {
                string encoded = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, filename)).Trim();
                using var stream = new MemoryStream(Convert.FromBase64String(encoded));
                using var bitmap = new System.Drawing.Bitmap(stream);
                return new System.Drawing.Bitmap(bitmap);
            }
            catch { return null; }
        }
        readonly System.Drawing.Bitmap? borderTexture = LoadTexture("border-texture.b64") ?? LoadEmbeddedBorderTexture();
        static System.Drawing.Bitmap? LoadEmbeddedBorderTexture()
        {
            // Fallback when the published ChatHost does not include border-texture.b64.
            using var stream = new MemoryStream(Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAFgAAAAPCAMAAABXwPhJAAAAYFBMVEW2n22vlmGtjlWli1eihU+ggEybgU+afkuae0mZeUeUeUiVdkaSc0OOdEeMcESKbkKJbECIZzuBaUGAZTyAYjl/XTZ3Xjl0WzZ1WDRzUi9rVDRnTS5hRSpMPSdGNSJAMyFUiQp4AAADLklEQVR42o2T19qgKAyGFekl9CKg//3f5cTZ2TnYo+VRkBTU5P2O4zrP6zqP8/h34Aav40QH/9a/9gttuJL/l2AlY9xQYaVXylKmJFiFJmsjO40+iaIAxgZ0WUWZMdYoIix3UToQQjLJIEpFqYmYZ4TghFDhzRG9gARpzt5tXpZJO+47Gt3vXQgHDJPQclmRKV2c7qPUonWfvcGYoXQlRbjvOygYo5aoHVyEqtKOWKhLrs3dAayvVn5hePBYpborNU450dnDCAzw4DHvWoHm1VIKIdvYwNR74cHmXjUWwTtQRmk8guO+zeYSgOe07h0pi3UvT0hMvHUQzAllSVg7tz0MsdFrl5J3XkhPZdsrXLKMf1zRwMyCSimx7JdbT/cYGigx7dnAS1jvZicVF2AthOOGnDTvZ63nJiZiSso+RawwpXY+S0MP+63EhouIpAn1mh5aC4cFzsnrYlmUZo4yUqzLEgMidUd4T5aePsBaLu4Sy8V1692B0oapUvpMuXl/L1uioFfLhOgUDpqKw7a65mUMICS+bvX5FoaF0pyn2fpPo4qK3K1vUhVw3In0vJ4bp51u7wNSEN2yLZ7nwmT0Umg4qMwtVqXzHWME7vFHUsJWtsGIl+cV0lxtLMl0CTaPEILnCdzaaQwnvPd7puGJsqOUwKENG4IUyR2MwoeB0DjX4r4SXRy/v92WyoA/wHTzdQXFfMCgUWvWX+2cGaNwjZSCGVUqUe97OB4WUhe5T0ewsdY7ettvpMXRnimnLBTjh6KjMMFoLEbWqHMFWwsGScQ4BS9t+dqDNLFSQxjjrsH5WgcSjAd/fNE8ntucDAyVJRmuFEVCosLCGaoUs7jZu9zPYAdEg+AnZw3qgDvEzmkC9zORtjpRVAQVyFM/ytrVjjDeZTwQciVUsbVMnadiNDgUnpL2JDLsp813qKAJ4amFYAkOgZQmR1hAEBEKDIosMoIEH6nvde9e9m5t5J7XSqnPOcDfo6yFzeotYwdzf1Z/no/MjLB1VLFHweJ+zrJmW3uuiTpZYyHj8zne3+Pn5+d9nwfn53m/Z7y/5XP8/LGj433++H7b/zr+m/CF/QJdHU47F3ZmuwAAAABJRU5ErkJggg=="));
            using var image = new System.Drawing.Bitmap(stream);
            return new System.Drawing.Bitmap(image);
        }
        readonly System.Drawing.Bitmap? scrollbarTexture = LoadTexture("scrollbar-texture.b64");
        readonly System.Drawing.Bitmap? headerTexture = LoadTexture("header-texture.b64");
        readonly Panel messageClip = new() { BackColor = System.Drawing.Color.FromArgb(10, 9, 8), Margin = Padding.Empty };
        readonly BufferedScrollbar goldScrollbar = new() { BackColor = System.Drawing.Color.FromArgb(11, 10, 8), Margin = Padding.Empty };
        readonly ScrollbarFreeRichTextBox nativeMessages = new()
        {
            ReadOnly = true, BorderStyle = BorderStyle.None, ScrollBars = RichTextBoxScrollBars.None,
            BackColor = System.Drawing.Color.FromArgb(10, 9, 8),
            ForeColor = System.Drawing.Color.FromArgb(237, 231, 220),
            Font = new System.Drawing.Font("Georgia", 10, System.Drawing.FontStyle.Regular),
            DetectUrls = false, TabStop = false, ShortcutsEnabled = false
        };
        readonly WebView2 messageBrowser = new() { Dock = DockStyle.Fill, Visible = true };
        bool messageBrowserReady;
        int browserScrollTop, browserScrollHeight = 1, browserClientHeight = 1;
        const string MessagePage = """
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;background:#0a0908;color:#f1eee8;font:18px/1.38 Georgia,serif;overflow:hidden}
#feed{height:100vh;box-sizing:border-box;overflow-y:auto;overflow-x:hidden;scrollbar-width:none;padding:10px 9px;overflow-anchor:none}
#feed::-webkit-scrollbar{display:none}
.msg{margin:0 0 12px;padding:0 0 10px;border-bottom:1px solid #29231b;overflow-wrap:anywhere}
.msg-header{display:flex;align-items:baseline;flex-wrap:wrap;gap:4px 10px;margin-bottom:3px;line-height:1.3}
.user{color:#dbb243;font-size:17px;font-weight:bold}
.time{color:#b8a98e;font:13px Georgia,serif;white-space:nowrap}
.body{display:block;white-space:pre-wrap;line-height:1.42}
.preview{display:block;max-width:100%;height:auto;margin:7px 0 3px;object-fit:contain}
.placeholder{font-size:14px;color:#c9b68c}
.date-separator{display:flex;align-items:center;gap:9px;color:#d9c49c;font:14px Georgia,serif;margin:16px 0 13px;white-space:nowrap}
.date-separator:before,.date-separator:after{content:"";height:1px;background:#655237;flex:1}
</style></head><body><div id="feed"></div><script>
const feed=document.getElementById('feed');
let userHasScrolled=false;
feed.addEventListener('wheel',e=>{userHasScrolled=true;if(e.deltaY>0)chrome.webview.postMessage({type:'history-stop'});},{passive:true});
feed.addEventListener('pointerdown',()=>{userHasScrolled=true;});
function metrics(){chrome.webview.postMessage({type:'scroll',top:feed.scrollTop,height:feed.scrollHeight,client:feed.clientHeight,userScrolled:userHasScrolled});}
feed.addEventListener('scroll',metrics);
new ResizeObserver(metrics).observe(feed);
window.setMessages=function(messages,prepended=false){
  // Reconcile by message ID. Never tear down existing rows on a new message:
  // doing so resets image layout and can jump the scroll position.
  const existing=new Map([...feed.children].map(el=>[el.dataset.id,el]));
  const wasAtBottom=feed.children.length>0 &&
    feed.scrollHeight>feed.clientHeight &&
    feed.scrollHeight-feed.clientHeight-feed.scrollTop<=24;
  const anchor=[...feed.children].find(el=>el.getBoundingClientRect().bottom>feed.getBoundingClientRect().top);
  const anchorId=anchor?.dataset.id;
  const anchorY=anchor?.getBoundingClientRect().top;
  const pinnedAtOldest=userHasScrolled && feed.scrollTop<=3;
  // Date headings are derived from Discord message IDs and rebuilt each pass.
  for(const el of [...feed.querySelectorAll('.date-separator')])el.remove();
  const wanted=new Set(messages.map(m=>m.id));
  for(const [id,row] of existing)if(!wanted.has(id))row.remove();
  let next=null;
  for(let i=messages.length-1;i>=0;i--){
    const m=messages[i];
    let row=existing.get(m.id);
    const signature=JSON.stringify([m.user,m.body,m.color,m.images,m.timestamp]);
    if(!row||row.dataset.signature!==signature){
      const replacement=document.createElement('div');
      replacement.className='msg';replacement.dataset.id=m.id;replacement.dataset.signature=signature;
      const header=document.createElement('div');header.className='msg-header';
      if(m.user){const name=document.createElement('span');name.className='user';name.style.color=/^#[0-9a-f]{6}$/i.test(m.color)?m.color:'#dbb243';name.textContent=m.user;header.appendChild(name);}
      const time=document.createElement('span');time.className='time';time.textContent=new Date(m.timestamp).toLocaleTimeString(undefined,{hour:'numeric',minute:'2-digit'});time.title=new Date(m.timestamp).toLocaleString();header.appendChild(time);
      replacement.appendChild(header);
      const body=document.createElement('span');body.className='body';body.textContent=m.body;replacement.appendChild(body);
      for(const url of m.images){
        if(!/^https:\/\/(cdn\.discordapp\.com|media\.discordapp\.net)\//i.test(url))continue;
        const img=document.createElement('img');img.className='preview';img.loading='lazy';img.referrerPolicy='no-referrer';img.src=url;
        img.addEventListener('load',metrics);
        img.addEventListener('error',()=>{img.replaceWith(Object.assign(document.createElement('span'),{className:'placeholder',textContent:'[Image unavailable]'}));metrics();});
        replacement.appendChild(img);
      }
      if(row)row.replaceWith(replacement);
      row=replacement;
    }
    if(row.parentElement!==feed || row.nextElementSibling!==next)feed.insertBefore(row,next);
    next=row;
  }
  let previousDate='';
  for(const m of messages){
    const row=[...feed.children].find(el=>el.dataset.id===m.id);
    if(!row)continue;
    const date=new Date(m.timestamp).toLocaleDateString(undefined,{year:'numeric',month:'long',day:'numeric'});
    if(date!==previousDate){
      const divider=document.createElement('div');
      divider.className='date-separator';
      divider.textContent=date;
      feed.insertBefore(divider,row);
      previousDate=date;
    }
  }
  if(userHasScrolled && anchorId && !pinnedAtOldest){
    const kept=[...feed.children].find(el=>el.dataset.id===anchorId);
    if(kept)feed.scrollTop+=kept.getBoundingClientRect().top-anchorY;
  }
  // Follow live chat only if the user was already at the bottom.
  // Prepending history must never force either end of the scrollbar.
  if(!userHasScrolled)feed.scrollTop=feed.scrollHeight;
  else if(prepended && pinnedAtOldest)feed.scrollTop=0;
  else if(wasAtBottom&&!prepended)feed.scrollTop=feed.scrollHeight;
  metrics();
};
window.scrollChat=function(delta){userHasScrolled=true;feed.scrollTop+=delta;metrics();};
window.scrollFraction=function(f){userHasScrolled=true;feed.scrollTop=Math.max(0,feed.scrollHeight-feed.clientHeight)*f;metrics();};
window.scrollToLatest=function(){if(!userHasScrolled){feed.scrollTop=feed.scrollHeight;metrics();}};
metrics();
</script></body></html>
""";
        async Task InitMessageBrowser(CoreWebView2Environment env)
        {
            try
            {
                await messageBrowser.EnsureCoreWebView2Async(env);
                messageBrowser.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                messageBrowser.CoreWebView2.Settings.AreDevToolsEnabled = false;
                messageBrowser.CoreWebView2.WebMessageReceived += (_, args) =>
                {
                    try
                    {
                        using var doc = System.Text.Json.JsonDocument.Parse(args.WebMessageAsJson);
                        var root = doc.RootElement;
                        if (root.GetProperty("type").GetString() == "history-stop") { historyCatchupActive = false; return; }
                        if (root.GetProperty("type").GetString() != "scroll") return;
                        browserScrollTop = (int)Math.Round(root.GetProperty("top").GetDouble());
                        browserScrollHeight = (int)Math.Round(root.GetProperty("height").GetDouble());
                        browserClientHeight = (int)Math.Round(root.GetProperty("client").GetDouble());
                        userScrolledChat = root.TryGetProperty("userScrolled", out var interacted) && interacted.GetBoolean();
                        goldScrollbar.Invalidate();
                        if (userScrolledChat && browserScrollTop < Math.Max(900, browserClientHeight * 3)) RequestOlderMessages();
                    }
                    catch (Exception ex) { Log("HTML scroll telemetry error: " + ex.GetType().Name); }
                };
                // A fresh Discord login temporarily hides frameSurface.
                // Finish navigating the separate native renderer BEFORE we
                // hide its parent, rather than leave it awaiting a visible
                // HWND until the next launcher restart.
                var rendererNavigation = new TaskCompletionSource<bool>(
                    TaskCreationOptions.RunContinuationsAsynchronously);
                messageBrowser.NavigationCompleted += (_, e) => {
                    if (e.IsSuccess) {
                        messageBrowserReady = true;
                        Log("HTML message renderer ready");
                    }
                    else Log("HTML message renderer navigation failed: " + e.WebErrorStatus);
                    rendererNavigation.TrySetResult(e.IsSuccess);
                };
                Log("HTML message renderer navigating");
                messageBrowser.NavigateToString(MessagePage);
                try
                {
                    if (!await rendererNavigation.Task.WaitAsync(TimeSpan.FromSeconds(8)))
                        Log("CHAT | Native renderer navigation failed; continuing Discord login");
                }
                catch (TimeoutException)
                {
                    // Do not trap the user on a loading screen: the renderer
                    // completion callback can still mark itself ready later.
                    Log("CHAT | Native renderer still loading; continuing Discord login");
                }
            }
            catch (Exception ex) { Log("HTML renderer initialization failed: " + ex.GetType().Name); }
        }
        void ScrollHtml(int pixels)
        {
            if (messageBrowserReady && messageBrowser.CoreWebView2 != null)
                _ = messageBrowser.CoreWebView2.ExecuteScriptAsync("window.scrollChat(" + pixels + ")");
        }
        string lastFeed = "";
        readonly System.Collections.Generic.List<(string User, string Body)> renderedMessages = new();
        bool nativeMode;
        // Keep the established bronze frame and a native "Connecting..." label
        // visible during the first authenticated Discord feed transition.
        bool connectingChat;
        bool freshDiscordProfile;
        bool discordLoginVisible;
        bool discordSignInRequested;
        Form? discordSignInWindow;
        bool showChatAfterDiscordSignIn;
        string? discordIntegrationLogoDataUrl;
        // Authentication gates live Discord fetching/paging ONLY. A genuine
        // unexpired message already in the local chat archive is sufficient
        // to display Happy Hour, even if Discord is signed out.
        bool discordChannelReady;
        // Discord's initial sign-in often hands off to a partly mounted
        // channel SPA. Reload that channel exactly once after login so native
        // Game Chat receives a fully initialized post-auth feed.
        bool channelReloadAfterSignInPending;
        const string ExtractFeed = """
            (() => {
              const list = document.querySelector('[data-list-id="chat-messages"]');
              if (!list) return '[]';
              const rows = [...list.querySelectorAll('[id^="chat-messages-"]')]
                .filter(el => /^chat-messages-[0-9]+-[0-9]+$/.test(el.id));
              let lastVisibleAuthor = '';
              return JSON.stringify(rows.map(el => {
                const usernameEl = el.querySelector('[class*="username_"]');
                const user = usernameEl?.textContent?.trim() || '';
                if (user) lastVisibleAuthor = user;
                // Discord groups consecutive posts under one username.
                // Preserve the native chat layout's original user field,
                // but retain the source author when authenticating bot images.
                const sourceAuthor = user || lastVisibleAuthor;
                const color = usernameEl ? getComputedStyle(usernameEl).color : '';
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
                return {id:el.id,user,sourceAuthor,body,matchText,color,images:[...uniqueImages.values()].slice(0,4)};
              }).filter(x => x.body || x.images.length));
            })();
            """;
        readonly System.Collections.Generic.SortedDictionary<ulong, (string User, string Body, string Color, string[] Images)> history = new();
        // Discord snowflakes encode their original creation time in UTC.
        static DateTimeOffset DiscordTimestamp(ulong id) =>
            DateTimeOffset.FromUnixTimeMilliseconds((long)(id >> 22) + 1420070400000L);
        // Shared TES3NP data root, matching src/state.ahk::AppDataDirectory.
        // The chat companion runs in a separate process but must not invent
        // an independent persistent-data directory.
        static readonly string ChatDataRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "tes3np");
        readonly System.Collections.Generic.SortedDictionary<ulong, (string User, string Body)> archivedChat = new();
        // Image-only Discord posts must be indexed too: the rainbow Happy Hour
        // announcement is a picture, not searchable message text.
        readonly System.Collections.Generic.Dictionary<ulong, string[]> archivedImageUrls = new();
        readonly System.Collections.Generic.HashSet<ulong> verifiedHappyHourImageIds = new();
        readonly System.Collections.Generic.HashSet<ulong> loggedHappyHourImageCandidates = new();
        readonly System.Collections.Generic.HashSet<ulong> loggedHappyHourImageMisses = new();
        readonly string gameChatLogDirectory = Path.Combine(ChatDataRoot, "Logs");
        string GameChatLogFile => Path.Combine(gameChatLogDirectory, "game-chat.log");
        string GameChatIndexFile => Path.Combine(gameChatLogDirectory, "game-chat-index.json");
        bool chatLogLoaded;
        void EnsureChatLogLoaded()
        {
            if (chatLogLoaded) return;
            Directory.CreateDirectory(gameChatLogDirectory);
            if (File.Exists(GameChatIndexFile))
            {
                try
                {
                    var records = System.Text.Json.JsonSerializer.Deserialize<System.Collections.Generic.List<ChatArchiveEntry>>(
                        File.ReadAllText(GameChatIndexFile)) ?? new();
                    foreach (var entry in records)
                    {
                        if (entry.Id == 0) continue;
                        archivedChat[entry.Id] = (entry.User ?? "", entry.Body ?? "");
                        if (entry.Images is { Length: > 0 })
                            archivedImageUrls[entry.Id] = entry.Images;
                        // This flag is persisted only after real image pixels
                        // pass the announcement's visual signature.
                        if (entry.VerifiedHappyHourImage && entry.Images is { Length: > 0 })
                            verifiedHappyHourImageIds.Add(entry.Id);
                    }
                }
                catch (Exception ex)
                {
                    // A damaged JSON index must not disable fresh Discord
                    // history collection or prevent trying the readable log.
                    Log("CHAT | Saved message index unreadable: " + ex.GetType().Name);
                }
            }
            bool recoveredFromText = false;
            if (File.Exists(GameChatLogFile))
            {
                // Recover only log entries containing original Discord IDs.
                // Human-readable timestamps without IDs cannot provide exact
                // activation times and must never be guessed.
                foreach (string line in File.ReadLines(GameChatLogFile))
                {
                    var idMatch = System.Text.RegularExpressions.Regex.Match(
                        line, @"\[discord:(\d+)\]\s*$");
                    if (!idMatch.Success ||
                        !ulong.TryParse(idMatch.Groups[1].Value, out ulong id) ||
                        id == 0 || archivedChat.ContainsKey(id)) continue;
                    string content = line.Substring(0, idMatch.Index).TrimEnd();
                    int stampEnd = content.IndexOf(']');
                    if (stampEnd >= 0) content = content.Substring(stampEnd + 1).TrimStart();
                    int split = content.IndexOf(": ", StringComparison.Ordinal);
                    archivedChat[id] = split >= 0
                        ? (content.Substring(0, split), content.Substring(split + 2))
                        : ("", content);
                    recoveredFromText = true;
                }
            }
            chatLogLoaded = true;
            if (recoveredFromText)
            {
                try { SaveChatArchive(); }
                catch (Exception ex) { Log("CHAT | Recovered log indexing failed: " + ex.GetType().Name); }
            }
        }
        public sealed class ChatArchiveEntry
        {
            public ulong Id { get; set; }
            public string User { get; set; } = "";
            public string Body { get; set; } = "";
            public string[] Images { get; set; } = Array.Empty<string>();
            public bool VerifiedHappyHourImage { get; set; }
        }
        // Windows may terminate the chat host while Discord history is being
        // indexed. Replace each archive file atomically rather than truncate
        // the only recoverable copy in place.
        static void WriteChatArchiveAtomically(string path, string contents)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            string temporary = path + ".tmp";
            File.WriteAllText(temporary, contents);
            File.Move(temporary, path, true);
        }

        void SaveChatArchive()
        {
            var records = archivedChat.Select(e => new ChatArchiveEntry {
                Id = e.Key, User = e.Value.User, Body = e.Value.Body,
                Images = archivedImageUrls.TryGetValue(e.Key, out var imageUrls) ? imageUrls : Array.Empty<string>(),
                VerifiedHappyHourImage = verifiedHappyHourImageIds.Contains(e.Key)
            }).ToArray();
            WriteChatArchiveAtomically(GameChatIndexFile,
                System.Text.Json.JsonSerializer.Serialize(records));
            var output = new System.Text.StringBuilder();
            string previousDate = "";
            foreach (var entry in archivedChat)
            {
                var sent = DiscordTimestamp(entry.Key).ToLocalTime();
                string date = sent.ToString("dddd, MMMM d, yyyy");
                if (date != previousDate)
                {
                    if (output.Length > 0) output.AppendLine();
                    output.AppendLine("========== " + date + " ==========");
                    previousDate = date;
                }
                string user = entry.Value.User.Trim();
                string body = entry.Value.Body.Replace("\r\n", "\n").Replace('\r', '\n').Replace("\n", "\\n").Trim();
                if (body.Length == 0 && archivedImageUrls.TryGetValue(entry.Key, out var images) && images.Length > 0)
                    body = "[image attachment]";
                // Discord groups consecutive messages under one username. Some
                // extracted bodies therefore already begin with "Player: ".
                if (string.IsNullOrWhiteSpace(user))
                {
                    var prefix = System.Text.RegularExpressions.Regex.Match(body, @"^(.+? \(\d+\)): (.*)$");
                    if (prefix.Success) { user = prefix.Groups[1].Value; body = prefix.Groups[2].Value; }
                }
                else if (body.StartsWith(user + ": ", StringComparison.Ordinal))
                    body = body.Substring(user.Length + 2);
                if (string.IsNullOrWhiteSpace(user)) user = "System";
                // Keep the source message ID in the readable export so it
                // can rebuild an index after an interrupted/corrupt JSON save.
                output.AppendLine($"[{sent:hh:mm:ss tt}] {user}: {body} [discord:{entry.Key}]");
            }
            WriteChatArchiveAtomically(GameChatLogFile, output.ToString());
        }
        readonly System.Collections.Generic.Dictionary<string, System.Drawing.Image> imageCache = new();
        readonly System.Collections.Generic.Dictionary<string, bool> happyHourImageClassification = new();
        // Discord can virtualize an image-only message out of the DOM while
        // its image is downloading. Retain the original bot message IDs.
        readonly System.Collections.Generic.Dictionary<string, System.Collections.Generic.HashSet<ulong>> happyHourImageMessageIds = new();
        readonly System.Collections.Generic.HashSet<string> pendingImages = new();
        readonly System.Collections.Generic.Dictionary<string, DateTime> failedImages = new();
        static readonly System.Net.Http.HttpClient imageHttp = new() { Timeout = TimeSpan.FromSeconds(12) };
        bool imagesNeedRedraw;

        // The real Yagrum activation is a small rainbow-on-black image:
        // red/yellow at the left, cyan/violet in the middle and sustained
        // green lettering on the right. Compare decoded pixels, not body text
        // or attachment filenames. The original Discord snowflake still
        // supplies the ONLY event timestamp.
        static bool LooksLikeHappyHourImage(System.Drawing.Image source)
        {
            if (source is not System.Drawing.Bitmap bitmap) return false;
            int w = bitmap.Width, h = bitmap.Height;
            if (w < 120 || h < 8 || w < h * 5) return false;
            int red = 0, yellow = 0, cyan = 0, violet = 0, green = 0;
            for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                var pixel = bitmap.GetPixel(x, y);
                if (pixel.A < 70) continue;
                int r = pixel.R, g = pixel.G, b = pixel.B;
                double position = (double)x / w;
                if (position < .19 && r > 110 && r > g * 1.45 && r > b * 1.4) red++;
                if (position > .05 && position < .30 && r > 140 && g > 100 && b < 100 &&
                    r > b * 1.6 && g > b * 1.4) yellow++;
                if (position > .07 && position < .38 && b > 120 && g > 105 && r < 120) cyan++;
                if (position > .20 && position < .58 && r > 75 && b > 95 &&
                    g < Math.Max(r, b) * .8) violet++;
                if (position > .50 && g > 110 && g > r * 1.5 && g > b * 1.3) green++;
            }
            return red >= 10 && yellow >= 8 && cyan >= 6 &&
                   violet >= 10 && green >= 30;
        }

        bool IsVerifiedHappyHourImageUrl(string url)
        {
            if (happyHourImageClassification.TryGetValue(url, out bool verified))
                return verified;
            if (!imageCache.TryGetValue(url, out var image)) return false;
            verified = LooksLikeHappyHourImage(image);
            happyHourImageClassification[url] = verified;
            if (verified)
                Log("HAPPY HOUR | Matched rainbow announcement image pixels from Discord attachment");
            return verified;
        }

        void RecognizePendingHappyHourImage(string url)
        {
            if (!happyHourImageMessageIds.TryGetValue(url, out var messageIds) ||
                !IsVerifiedHappyHourImageUrl(url)) return;
            bool newlyVerified = false;
            foreach (ulong messageId in messageIds)
            {
                if (!verifiedHappyHourImageIds.Add(messageId)) continue;
                newlyVerified = true;
                Log("HAPPY HOUR | Verified real rainbow-image announcement " +
                    "messageId=" + messageId + "; sent=" +
                    DiscordTimestamp(messageId).ToString("O"));
            }
            if (!newlyVerified) return;
            // Save even if Discord has already replaced this virtualized
            // message in its source viewport. The next restart can shortcut.
            try { SaveChatArchive(); }
            catch (Exception ex) { Log("HAPPY HOUR | Failed to save verified image ID: " + ex.GetType().Name); }
            DetectLatestHappyHour();
        }

        async Task FetchChatImage(string url)
        {
            if (imageCache.ContainsKey(url) || (failedImages.TryGetValue(url, out var retryAt) && DateTime.UtcNow < retryAt) || !pendingImages.Add(url)) return;
            try
            {
                if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
                    uri.Scheme != Uri.UriSchemeHttps ||
                    !(uri.Host.EndsWith(".discordapp.com", StringComparison.OrdinalIgnoreCase) ||
                      uri.Host.EndsWith(".discordapp.net", StringComparison.OrdinalIgnoreCase) ||
                      uri.Host.Equals("cdn.discordapp.com", StringComparison.OrdinalIgnoreCase))) return;
                // Discord's image proxy may serve WebP/AVIF, which System.Drawing/GDI+ cannot decode.
                // Ask the proxy for PNG so the native RichEdit preview can load reliably.
                if (uri.Host.Equals("media.discordapp.net", StringComparison.OrdinalIgnoreCase))
                {
                    var builder = new UriBuilder(uri);
                    var queryParts = builder.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
                        .Where(part => !part.StartsWith("format=", StringComparison.OrdinalIgnoreCase) &&
                                       !part.StartsWith("fm=", StringComparison.OrdinalIgnoreCase))
                        .ToList();
                    queryParts.Add("format=png");
                    builder.Query = string.Join("&", queryParts);
                    uri = builder.Uri;
                }
                using var request = new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, uri);
                request.Headers.Referrer = new Uri("https://discord.com/");
                request.Headers.Accept.ParseAdd("image/png");
                using var response = await imageHttp.SendAsync(request, System.Net.Http.HttpCompletionOption.ResponseHeadersRead);
                if (!response.IsSuccessStatusCode)
                    throw new System.Net.Http.HttpRequestException("HTTP " + (int)response.StatusCode +
                        " from " + uri.Host);
                if (response.Content.Headers.ContentLength > 8_000_000) return;
                byte[] bytes = await response.Content.ReadAsByteArrayAsync();
                if (bytes.Length > 8_000_000) return;
                using var stream = new System.IO.MemoryStream(bytes);
                using var original = System.Drawing.Image.FromStream(stream);
                int width = Math.Min(250, original.Width);
                int height = Math.Max(1, (int)Math.Round((double)original.Height * width / original.Width));
                if (height > 400) { width = Math.Max(1, width * 400 / height); height = 400; }
                var preview = new System.Drawing.Bitmap(width, height);
                using (var graphics = System.Drawing.Graphics.FromImage(preview))
                {
                    graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    graphics.DrawImage(original, 0, 0, width, height);
                }
                if (IsDisposed || closingChat) { preview.Dispose(); return; }
                imageCache[url] = preview;
                RecognizePendingHappyHourImage(url);
                Log("Chat image decoded: " + original.Width + "x" + original.Height +
                    " (" + (response.Content.Headers.ContentType?.MediaType ?? "unknown type") + ")");
                imagesNeedRedraw = true;
            }
            catch (Exception ex)
            {
                Log("Chat image unavailable (" + (Uri.TryCreate(url, UriKind.Absolute, out var failedUri)
                    ? failedUri.Host : "invalid URL") + "): " + ex.GetType().Name);
                failedImages[url] = DateTime.UtcNow.AddMinutes(2);
            }
            finally
            {
                if (!imageCache.ContainsKey(url) && !failedImages.ContainsKey(url))
                    failedImages[url] = DateTime.UtcNow.AddMinutes(2);
                pendingImages.Remove(url);
                imagesNeedRedraw = true;
            }
        }
        DateTime lastHistoryRequest = DateTime.MinValue;
        bool loadingHistory;
        ulong lastHistoryOldestId = ulong.MaxValue;
        int historyStallCount;
        int historyNoProgressCount;
        string historyLastVisibleFirst = "";
        DateTime historyBackoffUntil = DateTime.MinValue;
        DateTime historyNavigationStarted = DateTime.MinValue;
        DateTime historyLastProgress = DateTime.MinValue;
        DateTime historyLastReanchor = DateTime.MinValue;
        bool historyAwaitingNavigation;
        async Task LoadOlderMessages()
        {
            if (loadingHistory || signInExpanded || web.CoreWebView2 == null ||
                DateTime.UtcNow - lastHistoryRequest < TimeSpan.FromMilliseconds(300) ||
                DateTime.UtcNow < historyBackoffUntil ||
                (historyAwaitingNavigation && DateTime.UtcNow - historyNavigationStarted < TimeSpan.FromMilliseconds(900))) return;
            loadingHistory = true;
            lastHistoryRequest = DateTime.UtcNow;
            try
            {
                ulong oldest = history.Count > 0 ? history.First().Key : ulong.MaxValue;
                if (oldest < lastHistoryOldestId)
                {
                    lastHistoryOldestId = oldest;
                    historyStallCount = 0;
                    historyNoProgressCount = 0;
                    historyLastProgress = DateTime.UtcNow;
                    Log("History advanced; oldest message: " + oldest);
                }
                // ExecuteScriptAsync waits for the JavaScript evaluation to finish.
                // Avoid the DevTools input dispatcher: it hangs in hidden WebView2.
                // Schedule the second movement asynchronously inside the page.
                int attempt = historyNoProgressCount + 1;
                // Discord can stop paging after its virtual list drops older rows.
                // Re-enter the channel at the oldest known message to let Discord
                // initialize a fresh window around that message. The native
                // renderer keeps the already-collected history across navigation.
                if (attempt >= 3 && oldest != ulong.MaxValue &&
                    DateTime.UtcNow - historyLastProgress >= TimeSpan.FromMilliseconds(1500) &&
                    DateTime.UtcNow - historyLastReanchor >= TimeSpan.FromSeconds(3))
                {
                    historyNoProgressCount = 0;
                    historyLastVisibleFirst = "";
                    historyNavigationStarted = DateTime.UtcNow;
                    historyLastReanchor = DateTime.UtcNow;
                    historyAwaitingNavigation = true;
                    historyBackoffUntil = DateTime.UtcNow.AddMilliseconds(900);
                    string olderWindow = Channel + "/" + oldest;
                    Log("History reanchor: navigating Discord to " + olderWindow);
                    web.CoreWebView2.Navigate(olderWindow);
                    return;
                }
                string scriptMode = attempt >= 4 ? "recovery" : "normal";
                string result = await web.CoreWebView2.ExecuteScriptAsync("""
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
                    """.Replace("RECOVERY_FLAG", attempt >= 4 ? "true" : "false")).WaitAsync(TimeSpan.FromSeconds(5));
                if (result.Contains("no-message-list") || result.Contains("no-scroller"))
                {
                    historyBackoffUntil = DateTime.UtcNow.AddMilliseconds(300);
                    Log("History waiting for Discord message list: " + result);
                    return;
                }
                historyAwaitingNavigation = false;
                // A changing first Discord row is evidence of virtual-list progress,
                // even before the native extractor has merged the new messages.
                // Don't waste recovery attempts while Discord is advancing.
                var firstMatch = System.Text.RegularExpressions.Regex.Match(result, @"first=(chat-messages-[0-9]+-[0-9]+)");
                string visibleFirst = firstMatch.Success ? firstMatch.Groups[1].Value : "";
                if (visibleFirst.Length > 0 && visibleFirst != historyLastVisibleFirst)
                {
                    historyLastVisibleFirst = visibleFirst;
                    historyNoProgressCount = 0;
                    historyStallCount = 0;
                    historyLastProgress = DateTime.UtcNow;
                    attempt = 1;
                }
                historyNoProgressCount = attempt;
                if (result.Contains("loading=true"))
                {
                    historyNoProgressCount = Math.Max(0, historyNoProgressCount - 1);
                    historyBackoffUntil = DateTime.UtcNow.AddMilliseconds(400);
                    Log("History waiting for Discord pagination: " + result);
                    return;
                }
                Log("History scroll (" + scriptMode + ", attempt=" + attempt + "): " + result);
                if (history.Count > 0 && history.First().Key < oldest)
                {
                    historyStallCount = 0;
                }
                else if (++historyStallCount >= 10)
                {
                    // Slow Discord responses are not proof of end-of-history.
                    // Keep retrying while the user remains near the top.
                    historyStallCount = 0;
                    historyBackoffUntil = DateTime.UtcNow.AddMilliseconds(900);
                    Log("History pending; retrying after 900ms if still near top");
                }
            }
            catch (TimeoutException) { Log("History load timed out after 5s; retrying on next refresh"); }
            catch (Exception ex) { Log("History load error: " + ex.GetType().Name); }
            finally { loadingHistory = false; }
        }
        DateTime lastHistoryGateLog = DateTime.MinValue;
        bool userScrolledChat;
        bool historyCatchupActive;
        // Scan backward for the latest verified Happy Hour. The alpha
        // detector extends the bounded search window to seven days if the
        // existing archive contains no verified event; production uses one hour.
        DateTime initialBackfillStarted = DateTime.MinValue;
        int initialBackfillAttempts;
        bool initialBackfillComplete;
        // Restoring Discord's hidden source from historical paging can load
        // previously unseen (but old) rows. Do not turn them into chat alerts.
        bool waitingForLiveFeedAfterHistory;
        string lastRestoredFeed = "";
        int restoredFeedStableTicks;
        void BackfillUntilHappyHour()
        {
            if (!discordChannelReady || initialBackfillComplete || !nativeMode || signInExpanded ||
                loadingHistory || web.CoreWebView2 == null || !messageBrowserReady ||
                history.Count == 0) return;
            if (initialBackfillStarted == DateTime.MinValue) {
                initialBackfillStarted = DateTime.UtcNow;
                Log("HAPPY HOUR | Searching Discord history backward for latest real activation");
            }
            ulong candidateId = LatestArchivedHappyHourId();
            DateTimeOffset oldestLoaded = DiscordTimestamp(history.First().Key);
            // The archive may already contain an older event from a previous
            // session. Don't stop until the current live history has paged back
            // through that event: newer activations could still be unseen.
            bool verifiedLatest = candidateId > 0 &&
                oldestLoaded <= DiscordTimestamp(candidateId);
            // Alpha detection may need a recent expired event missing from
            // disk, but paging is still bounded by the existing timeout.
            bool pastActiveWindow = oldestLoaded <=
                (ShowExpiredHappyHourForAlphaTest
                    ? DateTimeOffset.UtcNow.AddDays(-7)
                    : DateTimeOffset.UtcNow.AddHours(-1));
            bool complete = verifiedLatest || pastActiveWindow;
            // Discord may throttle or stop exposing history. Log partial
            // coverage rather than claiming detection succeeded.
            bool timedOut = initialBackfillAttempts >= 500 ||
                DateTime.UtcNow - initialBackfillStarted > TimeSpan.FromMinutes(6);
            if (complete || timedOut) {
                initialBackfillComplete = true;
                Log("HAPPY HOUR | History scan " +
                    (verifiedLatest ? "confirmed latest activation" :
                     pastActiveWindow ? "covered active hour" : "partial (paging limit)") +
                    "; detectedId=" + candidateId +
                    "; pages=" + initialBackfillAttempts +
                    "; " + history.Count + " messages; oldest=" +
                    oldestLoaded.ToString("O"));
                // Reanchoring an old Discord message changes the hidden
                // source browser's channel position. Restore the live channel
                // afterward, without losing the collected native history.
                if (initialBackfillAttempts > 0 && !closingChat) {
                    // This browser is the hidden Discord source, not the native
                    // visible chat. Restore live message monitoring after scan.
                    Log("CHAT | Returning hidden Discord source to newest messages");
                    waitingForLiveFeedAfterHistory = true;
                    lastRestoredFeed = "";
                    restoredFeedStableTicks = 0;
                    web.CoreWebView2.Navigate(Channel);
                }
                // In the visible chat, show the latest messages (roughly ten
                // on a typical viewport), not the oldest page we scanned.
                if (messageBrowserReady && messageBrowser.CoreWebView2 != null)
                    _ = messageBrowser.CoreWebView2.ExecuteScriptAsync("window.scrollToLatest()");
                return;
            }
            if (DateTime.UtcNow < historyBackoffUntil ||
                DateTime.UtcNow - lastHistoryRequest < TimeSpan.FromMilliseconds(600)) return;
            initialBackfillAttempts++;
            _ = LoadOlderMessages();
        }

        void RequestOlderMessages(bool forceTop = false)
        {
            // The live Discord source has one scroll position. During the
            // targeted HH search, reserve it for unattended pagination;
            // keep user scrolling entirely within the native chat renderer.
            if (!initialBackfillComplete || (!userScrolledChat && !forceTop)) return;
            bool nearTop = forceTop || ChatFirstLine() <= Math.Max(900, browserClientHeight * 3);
            if (userScrolledChat && nearTop) historyCatchupActive = true;
            bool canRequest = (nearTop || historyCatchupActive) && !loadingHistory && IsHandleCreated &&
                nativeMode && !signInExpanded && web.CoreWebView2 != null;
            if (!canRequest)
            {
                if (DateTime.UtcNow - lastHistoryGateLog > TimeSpan.FromSeconds(10))
                {
                    lastHistoryGateLog = DateTime.UtcNow;
                    Log("History gate: top=" + browserScrollTop +
                        " nearTop=" + nearTop + " loading=" + loadingHistory +
                        " handle=" + IsHandleCreated + " native=" + nativeMode +
                        " signIn=" + signInExpanded +
                        " webReady=" + (web.CoreWebView2 != null));
                }
                return;
            }
            _ = LoadOlderMessages();
        }
        static string ParseHtmlColor(string color)
        {
            // CSS computed color arrives as rgb(r, g, b) or rgba(r, g, b, a).
            // Avoid regex here: a malformed pattern must not block the entire chat feed.
            if (string.IsNullOrWhiteSpace(color)) return "#DBB243";
            int open = color.IndexOf('('), close = color.IndexOf(')', open + 1);
            if (open < 0 || close <= open) return "#DBB243";
            string prefix = color.Substring(0, open).Trim();
            if (!prefix.Equals("rgb", StringComparison.OrdinalIgnoreCase) &&
                !prefix.Equals("rgba", StringComparison.OrdinalIgnoreCase)) return "#DBB243";
            string[] parts = color.Substring(open + 1, close - open - 1).Split(',');
            if (parts.Length < 3 ||
                !byte.TryParse(parts[0].Trim(), out byte red) ||
                !byte.TryParse(parts[1].Trim(), out byte green) ||
                !byte.TryParse(parts[2].Trim(), out byte blue)) return "#DBB243";
            return $"#{red:X2}{green:X2}{blue:X2}";
        }
        // A Happy Hour exists only within one hour of its authentic Discord
        // activation message. Expired announcements are never displayed.
        ulong lastHappyHourMessageId;

        [DllImport("user32.dll")] static extern IntPtr GetLastActivePopup(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr hwnd);

        bool OtherLauncherDialogOpen()
        {
            if (!IsWindow(owner) || !IsWindowEnabled(owner)) return true;
            // Update/status dialogs are owned by the main launcher. Win32
            // identifies the current active popup even when it is not modal.
            IntPtr active = GetLastActivePopup(owner);
            if (active == IntPtr.Zero || active == owner || active == Handle ||
                (happyHourBanner != null && active == happyHourBanner.Handle))
                return false;
            return IsWindowVisible(active);
        }

        Form? happyHourBanner;
        DateTime lastHappyHourBannerGateLog = DateTime.MinValue;
        Panel? happyHourBannerTitleInset;
        Panel? happyHourBannerRainbow;
        string happyHourBannerClockText = "";
        System.Drawing.Color happyHourBannerClockColor = System.Drawing.Color.FromArgb(215, 170, 77);
        int happyHourBannerRequiredWidth = 620;
        bool happyHourBannerLayoutLogged;
        System.Windows.Forms.Timer? happyHourTicker;
        DateTimeOffset happyHourEndsAt;
        // Production behavior: ignore expired announcements and close the
        // existing banner when the real Discord activation turns one hour old.
        // The alpha expired-announcement display override remains disabled.
        const bool ShowExpiredHappyHourForAlphaTest = false;
        static Form GoldHappyHourWindow(int width, int height, string title)
        {
            return new Form {
                Text = title, StartPosition = FormStartPosition.CenterScreen,
                ClientSize = new System.Drawing.Size(width, height),
                FormBorderStyle = FormBorderStyle.FixedDialog,
                MaximizeBox = false, MinimizeBox = false, ShowInTaskbar = false,
                BackColor = System.Drawing.Color.FromArgb(23, 16, 8),
                ForeColor = System.Drawing.Color.FromArgb(197, 164, 92)
            };
        }

        static System.Drawing.Color HappyHourTimerColor(DateTimeOffset ends)
        {
            var remaining = ends - DateTimeOffset.UtcNow;
            if (remaining <= TimeSpan.FromMinutes(10))
                return System.Drawing.Color.FromArgb(230, 60, 55);
            if (remaining <= TimeSpan.FromMinutes(30))
                return System.Drawing.Color.FromArgb(255, 156, 49);
            return System.Drawing.Color.FromArgb(215, 170, 77);
        }

        // Measure the ACTUAL rendered fonts so the rainbow title, green XP
        // text and countdown never occupy overlapping or clipped rectangles.
        // The entire title plate grows to fit, without changing text sizes.
        // Paint the whole message on ONE surface. Separate WinForms labels
        // added layout padding, swallowed the '-' glyph and clipped words.
        // Measuring with the SAME GDI renderer used for drawing gives
        // natural single-space separation and no label wrapping.
        static System.Windows.Forms.TextFormatFlags HappyHourLineFlags =>
            System.Windows.Forms.TextFormatFlags.NoPadding |
            System.Windows.Forms.TextFormatFlags.NoPrefix |
            System.Windows.Forms.TextFormatFlags.SingleLine |
            System.Windows.Forms.TextFormatFlags.VerticalCenter;

        static int HappyHourRunWidth(string value, System.Drawing.Font font) =>
            System.Windows.Forms.TextRenderer.MeasureText(value, font,
                new System.Drawing.Size(4096, 32), HappyHourLineFlags).Width;

        // The banner uses compact unpadded seconds, while the original large
        // alert retains its established clock formatting.
        static string HappyHourBannerTime(DateTimeOffset end)
        {
            int seconds = (int)Math.Max(0, Math.Ceiling((end - DateTimeOffset.UtcNow).TotalSeconds));
            return "(" + (seconds / 60) + "m " + (seconds % 60) + "s)";
        }

        void LayoutHappyHourBannerContents()
        {
            if (happyHourBannerTitleInset == null || happyHourBannerRainbow == null) return;
            string heading = "HAPPY HOUR ACTIVE";
            using var greenFont = new System.Drawing.Font("Georgia", 12, System.Drawing.FontStyle.Bold);
            using var timerFont = new System.Drawing.Font("Georgia", 11, System.Drawing.FontStyle.Bold);
            int width = 8 + heading.Sum(ch => HappyHourRunWidth(ch.ToString(),
                happyHourBannerRainbow.Font));
            width += HappyHourRunWidth(" - ", happyHourBannerRainbow.Font);
            width += HappyHourRunWidth("Mastery Points Are Doubled!", greenFont);
            width += HappyHourRunWidth(" ", greenFont);
            width += HappyHourRunWidth(happyHourBannerClockText, timerFont);
            width += 8;
            happyHourBannerRainbow.SetBounds(0, 0, width, 32);
            happyHourBannerTitleInset.SetBounds(12, 7, width, 32);
            happyHourBannerRequiredWidth = happyHourBannerTitleInset.Right + 10;
            if (!happyHourBannerLayoutLogged) {
                happyHourBannerLayoutLogged = true;
                Log("HAPPY HOUR | Single-line banner measured width=" +
                    happyHourBannerRequiredWidth + "; text='" + heading +
                    " - Mastery Points Are Doubled! " +
                    happyHourBannerClockText + "'");
            }
            happyHourBannerRainbow.Invalidate();
        }

        void PaintHappyHourBannerLine(System.Drawing.Graphics graphics,
            System.Drawing.Font headingFont)
        {
            string heading = "HAPPY HOUR ACTIVE";
            string[] colors = { "#FF0000", "#FF7F00", "#FFFF00", "#7FFF00",
                "#00FF7F", "#00FFFF", "#007FFF", "#7F00FF", "#FF00FF", "#00FF00" };
            int x = 8;
            void DrawSegment(string value, System.Drawing.Font font,
                System.Drawing.Color color)
            {
                if (value.Length == 0) return;
                int width = HappyHourRunWidth(value, font);
                System.Windows.Forms.TextRenderer.DrawText(graphics, value, font,
                    new System.Drawing.Rectangle(x, 0, width + 2, 32),
                    color, HappyHourLineFlags);
                x += width;
            }
            for (int i = 0; i < heading.Length; i++)
                DrawSegment(heading[i].ToString(), headingFont,
                    System.Drawing.ColorTranslator.FromHtml(colors[i % colors.Length]));
            // Literal spaces surrounding a visible hyphen, as requested:
            // HAPPY HOUR ACTIVE - Mastery Points Are Doubled! (60m 0s)
            DrawSegment(" - ", headingFont, System.Drawing.Color.FromArgb(215, 170, 77));
            using var greenFont = new System.Drawing.Font("Georgia", 12, System.Drawing.FontStyle.Bold);
            using var timerFont = new System.Drawing.Font("Georgia", 11, System.Drawing.FontStyle.Bold);
            DrawSegment("Mastery Points Are Doubled!", greenFont,
                System.Drawing.Color.FromArgb(55, 216, 70));
            DrawSegment(" ", greenFont, System.Drawing.Color.FromArgb(215, 170, 77));
            DrawSegment(happyHourBannerClockText, timerFont, happyHourBannerClockColor);
        }

        // The launcher and this banner are separate *owned* top-level HWNDs:
        // ownership controls z-order/minimize, but Windows does not move an
        // owned popup with its owner. Follow the existing launcher movement
        // WinEvent hook with one native, non-activating position update.
        // This does not touch the countdown, Discord, or chat visibility.
        void PositionHappyHourBanner()
        {
            var banner = happyHourBanner;
            if (banner == null || banner.IsDisposed || !banner.IsHandleCreated ||
                !IsWindow(owner) || !GetWindowRect(owner, out var bounds) ||
                !IsWindowVisible(owner) || IsIconic(owner)) return;

            int x = bounds.Left, y = bounds.Top - 48;
            int width = Math.Max(bounds.Right - bounds.Left, happyHourBannerRequiredWidth);
            const int height = 46;
            // Avoid redundant native moves, especially during 500ms polling.
            if (GetWindowRect(banner.Handle, out var current) &&
                current.Left == x && current.Top == y &&
                current.Right - current.Left == width &&
                current.Bottom - current.Top == height) return;

            const uint SWP_NOZORDER_NOACTIVATE = 0x0004 | 0x0010;
            SetWindowPos(banner.Handle, IntPtr.Zero, x, y, width, height,
                SWP_NOZORDER_NOACTIVATE);
        }

        // This updates only the existing banner's text/colors, not its
        // visibility, ownership, z-order, or launcher focus. In particular,
        // it must run while Settings/Characters/other dialogs are open.
        void RefreshHappyHourBannerClock()
        {
            if (happyHourBanner is not { IsDisposed: false } ||
                happyHourBannerRainbow == null) return;
            bool active = happyHourEndsAt > DateTimeOffset.UtcNow;
            // Derive the remaining time from the immutable, real Discord
            // expiry on every tick; never decrement a paused local counter.
            happyHourBannerClockText = HappyHourBannerTime(happyHourEndsAt);
            happyHourBannerClockColor = active
                ? HappyHourTimerColor(happyHourEndsAt)
                : System.Drawing.Color.FromArgb(215, 170, 77);
            LayoutHappyHourBannerContents();
        }

        void RefreshHappyHourBanner()
        {
            if ((!ShowExpiredHappyHourForAlphaTest &&
                 happyHourEndsAt <= DateTimeOffset.UtcNow) || !IsWindow(owner))
            {
                if (happyHourBanner is { IsDisposed: false }) happyHourBanner.Close();
                happyHourBanner = null;
                return;
            }
            // Menus must not pause the active countdown. Leave the
            // separate dialog gate below to protect focus and z-order.
            RefreshHappyHourBannerClock();
            if (OtherLauncherDialogOpen()) {
                // Leave existing launcher dialogs in control of focus/z-order.
                // This is the only gate before the single Happy Hour banner.
                if (DateTime.UtcNow - lastHappyHourBannerGateLog > TimeSpan.FromSeconds(10)) {
                    lastHappyHourBannerGateLog = DateTime.UtcNow;
                    Log("HAPPY HOUR | Banner waiting for launcher dialog; messageId=" +
                        lastHappyHourMessageId);
                }
                return;
            }
            if (happyHourBanner == null || happyHourBanner.IsDisposed)
            {
                var banner = GoldHappyHourWindow(620, 46, "tes3np Happy Hour");
                banner.FormBorderStyle = FormBorderStyle.None;
                banner.StartPosition = FormStartPosition.Manual;
                banner.BackColor = System.Drawing.Color.FromArgb(143, 109, 60);
                banner.Paint += (_, e) => {
                    var g = e.Graphics;
                    int w = banner.ClientSize.Width, h = banner.ClientSize.Height;
                    // Match Game Chat's weathered bronze, without repeating a
                    // tiny image strip dozens of times across the header.
                    g.Clear(System.Drawing.Color.FromArgb(143, 109, 60));
                    // Match the actual Live Game Chat HEADER mottling (frameSurface.Paint),
                    // not the denser decorative frame grain. Coordinates are adapted
                    // to the 46-pixel banner while leaving its controls untouched.
                    var headerNoise = new Random(4108);
                    using var darkMottle = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(112, 83, 45));
                    using var lightMottle = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(184, 151, 92));
                    using var midMottle = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(165, 129, 72));
                    for (int n = 0; n < w * 10; n++) {
                        int px = headerNoise.Next(5, Math.Max(6, w - 5));
                        int py = headerNoise.Next(5, Math.Max(6, h - 5));
                        g.FillRectangle(n % 5 == 0 ? lightMottle : (n % 3 == 0 ? midMottle : darkMottle),
                            px, py, headerNoise.Next(1, 4), headerNoise.Next(1, 3));
                    }
                    if (borderTexture != null) {
                        using var trim = new System.Drawing.TextureBrush(borderTexture,
                            System.Drawing.Drawing2D.WrapMode.Tile);
                        g.FillRectangle(trim, 0, 0, w, 5);
                        g.FillRectangle(trim, 0, h - 5, w, 5);
                    }
                };
                // The black title plate hugs the actual content, not the window.
                var titleInset = new Panel {
                    BackColor = System.Drawing.Color.FromArgb(10, 9, 8)
                };
                titleInset.SetBounds(44, 7, 1, 32);
                banner.Controls.Add(titleInset);
                var rainbow = new Panel {
                    BackColor = System.Drawing.Color.FromArgb(10, 9, 8),
                    Font = new System.Drawing.Font("Georgia", 13, System.Drawing.FontStyle.Bold)
                };
                rainbow.SetBounds(0, 0, 1, 32);
                titleInset.Controls.Add(rainbow);
                rainbow.Paint += (_, e) => PaintHappyHourBannerLine(e.Graphics, rainbow.Font);
                happyHourBannerTitleInset = titleInset;
                happyHourBannerRainbow = rainbow;
                happyHourBanner = banner;
                banner.FormClosed += (_, _) => {
                    // The visual theme follows this exact genuine banner lifecycle.
                    // Closing an expired banner restores Jiub automatically.
                    NotifyLauncherHappyHourFace(false);
                    if (ReferenceEquals(happyHourBanner, banner)) {
                        happyHourBanner = null;
                        happyHourBannerTitleInset = null;
                        happyHourBannerRainbow = null;
                        happyHourBannerClockText = "";
                        happyHourBannerRequiredWidth = 620;
                        happyHourBannerLayoutLogged = false;
                    }
                };
                // Position BEFORE the first show to avoid a detached flash.
                // Own the popup before showing it: it stays tied to the
                // launcher's z-order and minimize state, never globally topmost.
                if (GetWindowRect(owner, out var initialOwnerBounds))
                    banner.SetBounds(initialOwnerBounds.Left, initialOwnerBounds.Top - 48,
                        Math.Max(initialOwnerBounds.Right - initialOwnerBounds.Left, 620), 46);
                banner.Show();
                SetNativeWindowOwner(banner.Handle, owner);
                // Notify Jiub only after the verified Discord-backed banner shows.
                NotifyLauncherHappyHourFace(true);
                // Initialize the visible clock on the first show as well.
                RefreshHappyHourBannerClock();
                Log("HAPPY HOUR | Banner window created for real message " +
                    lastHappyHourMessageId + "; expires=" +
                    happyHourEndsAt.ToString("O"));
            }
            // Native movement is synchronized by the launcher's WinEvent hook.
            // This call is a layout/fallback check, never the primary timer
            // that drags the banner after the launcher has already moved.
            if (happyHourBanner is { IsDisposed: false }) {
                if (IsWindowVisible(owner) && !IsIconic(owner)) {
                    PositionHappyHourBanner();
                    if (!happyHourBanner.Visible) {
                        happyHourBanner.Show();
                        // The verified banner is visible again after a launcher restore.
                        NotifyLauncherHappyHourFace(true);
                    }
                } else if (happyHourBanner.Visible) {
                    happyHourBanner.Hide();
                    // Keep Jiub's appearance in sync when the banner is hidden.
                    NotifyLauncherHappyHourFace(false);
                }
            }
        }

        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);

        // A genuine Discord activation goes directly to the docked banner.
        // There is intentionally no separate large WinForms notification.
        void ShowHappyHourBannerForMessage(ulong activationId)
        {
            if (activationId == 0 || closingChat || IsDisposed) return;
            var ends = DiscordTimestamp(activationId).AddHours(1);
            if (activationId <= lastHappyHourMessageId ||
                (!ShowExpiredHappyHourForAlphaTest && ends <= DateTimeOffset.UtcNow)) return;

            lastHappyHourMessageId = activationId;
            happyHourEndsAt = ends;

            happyHourTicker?.Stop();
            happyHourTicker?.Dispose();
            happyHourTicker = null;
            if (happyHourBanner is { IsDisposed: false }) happyHourBanner.Close();
            happyHourBanner = null;

            var ticker = new System.Windows.Forms.Timer { Interval = 1000 };
            ticker.Tick += (_, _) => {
                if (!ShowExpiredHappyHourForAlphaTest &&
                    happyHourEndsAt <= DateTimeOffset.UtcNow) {
                    ticker.Stop();
                    if (happyHourBanner is { IsDisposed: false }) happyHourBanner.Close();
                    return;
                }
                RefreshHappyHourBanner();
            };
            happyHourTicker = ticker;
            ticker.Start();
            RefreshHappyHourBanner();
            Log("HAPPY HOUR | Banner-only announcement from real Discord message " +
                activationId + " | " + DiscordTimestamp(activationId).ToString("O"));
        }

        // Search genuine archived Discord messages. Expired ones may show
        // during this alpha test without generating fake messages or timestamps.
        static bool IsHappyHourAnnouncement(string body)
        {
            if (string.IsNullOrWhiteSpace(body)) return false;
            // Discord's colored per-letter spans and invisible separators can
            // insert punctuation or whitespace INSIDE words, not just between
            // them. Match the complete activation phrase after normalizing the
            // rendered letters; never generate a message or timestamp.
            string normalized = System.Text.RegularExpressions.Regex.Replace(
                body.Normalize(System.Text.NormalizationForm.FormKC),
                @"[^\p{L}\p{Nd}]", "");
            return normalized.Contains("happyhourhasbeenactivated",
                StringComparison.OrdinalIgnoreCase);
        }

        ulong LatestArchivedHappyHourId()
        {
            // SortedDictionary keys are Discord snowflakes, ordered by time.
            // Verified image posts carry their original Discord message ID,
            // just like text announcements. Never manufacture an activation.
            ulong latest = 0;
            foreach (ulong imageId in verifiedHappyHourImageIds)
                if (imageId > latest) latest = imageId;
            foreach (var entry in archivedChat.Reverse()) {
                if (entry.Key <= latest) break;
                // A player repeating these words is not a bot activation.
                // The image detector also requires an actual Yagrum post.
                if (entry.Value.User.Contains("Yagrum", StringComparison.OrdinalIgnoreCase) &&
                    IsHappyHourAnnouncement(entry.Value.Body)) {
                    latest = entry.Key;
                    break;
                }
            }
            // The native chat can already display a message before its batch
            // is written to disk. Always inspect that same in-memory history.
            foreach (var entry in history.Reverse()) {
                if (entry.Key <= latest) break;
                if (entry.Value.User.Contains("Yagrum", StringComparison.OrdinalIgnoreCase) &&
                    IsHappyHourAnnouncement(entry.Value.Body)) {
                    latest = entry.Key;
                    break;
                }
            }
            return latest;
        }

        void DetectLatestHappyHour()
        {
            if (closingChat || IsDisposed) return;
            try
            {
                EnsureChatLogLoaded();
                ulong latest = LatestArchivedHappyHourId();
                if (latest > lastHappyHourMessageId &&
                    (ShowExpiredHappyHourForAlphaTest ||
                     DiscordTimestamp(latest).AddHours(1) > DateTimeOffset.UtcNow)) {
                    Log("HAPPY HOUR | Verified latest Discord announcement " + latest +
                        " at " + DiscordTimestamp(latest).ToString("O") +
                        (DiscordTimestamp(latest).AddHours(1) <= DateTimeOffset.UtcNow
                            ? " (expired; alpha display at 0m 0s)" : " (active)"));
                    ShowHappyHourBannerForMessage(latest);
                }
            }
            catch (Exception ex) { Log("HAPPY HOUR | Scan failed: " + ex.GetType().Name); }
        }

        void BeginHappyHourDiscovery()
        {
            if (closingChat || IsDisposed) return;
            try
            {
                // Genuine archived Discord messages (text or pixel-verified
                // bot images) are sufficient evidence without login. Only
                // live discovery and historical paging require authentication.
                EnsureChatLogLoaded();
                ulong candidate = LatestArchivedHappyHourId();
                bool valid = candidate > 0 &&
                    (ShowExpiredHappyHourForAlphaTest ||
                     DiscordTimestamp(candidate).AddHours(1) > DateTimeOffset.UtcNow);
                // A valid cached announcement is evidence for that event,
                // NOT proof it is the most recent one. The Discord source may
                // currently show only newer messages (or have resumed at an
                // old read position). Skipping pagination here can hide a new
                // Happy Hour while the game is already counting it down.
                // Display the cached event if still active, then independently
                // cover the live channel back through that timestamp or the
                // one-hour active window. Do not depend on the chat being open.
                initialBackfillComplete = false;
                initialBackfillStarted = DateTime.MinValue;
                initialBackfillAttempts = 0;
                if (valid)
                {
                    Log("HAPPY HOUR | Verified cached activation: " +
                        "messageId=" + candidate +
                        "; sent=" + DiscordTimestamp(candidate).ToString("O") +
                        "; archivedRows=" + archivedChat.Count +
                        "; checking for a newer Discord activation");
                    DetectLatestHappyHour();
                }
                else
                {
                    Log("HAPPY HOUR | No verified announcement in saved chat archive; " +
                        "archivedRows=" + archivedChat.Count +
                        "; live search will begin if the Discord channel becomes available");
                }
            }
            catch (Exception ex)
            {
                Log("HAPPY HOUR | Startup log check failed; will page Discord: " + ex.GetType().Name);
            }
        }

        async Task RefreshNativeMessages()
        {
            if (closingChat || IsDisposed || web.CoreWebView2 == null ||
                discordLoginVisible || !discordChannelReady) return;
            try
            {
                string raw = await web.CoreWebView2.ExecuteScriptAsync(ExtractFeed);
                if (closingChat || IsDisposed || !discordChannelReady) return;
                string json = System.Text.Json.JsonSerializer.Deserialize<string>(raw) ?? "[]";
                if (waitingForLiveFeedAfterHistory &&
                    string.Equals(web.CoreWebView2.Source?.TrimEnd('/'), Channel,
                        StringComparison.OrdinalIgnoreCase) && json != "[]") {
                    // Wait until the latest channel view produces a stable
                    // message snapshot before re-enabling live notifications.
                    // This also covers a slow Discord React mount after navigation.
                    if (json == lastRestoredFeed) restoredFeedStableTicks++;
                    else { lastRestoredFeed = json; restoredFeedStableTicks = 0; }
                    if (restoredFeedStableTicks >= 2) {
                        waitingForLiveFeedAfterHistory = false;
                        Log("CHAT | Hidden source ready for live notifications after history search");
                    }
                }
                if (json == lastFeed && !imagesNeedRedraw && nativeMode) {
                    DetectLatestHappyHour();
                    return;
                }
                bool redrawImages = imagesNeedRedraw;
                imagesNeedRedraw = false;
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                if (doc.RootElement.GetArrayLength() == 0) {
                    DetectLatestHappyHour();
                    return;
                }
                string newestId = doc.RootElement[doc.RootElement.GetArrayLength() - 1]
                    .GetProperty("id").GetString() ?? "";
                // Discord's virtual history replaces the last visible row
                // as we page backward or reanchor. That is NOT a new message:
                // only a snowflake newer than the newest previously observed
                // live message is eligible for an automatic notification.
                var newestMatch = System.Text.RegularExpressions.Regex.Match(
                    newestId, @"^chat-messages-\d+-(\d+)$");
                ulong newestSnowflake = newestMatch.Success &&
                    ulong.TryParse(newestMatch.Groups[1].Value, out ulong parsedNewest)
                        ? parsedNewest : 0;
                bool newMessage = feedInitialized && newestSnowflake > latestMessageId;
                if (newestSnowflake > latestMessageId)
                    latestMessageId = newestSnowflake;
                feedInitialized = true;
                // Unattended history navigation must never force the chat
                // open or reset the user's auto-hide timer.
                if (newMessage && initialBackfillComplete &&
                    !waitingForLiveFeedAfterHistory &&
                    chatDisplayMode == "Automatic")
                {
                    lastChatActivity = DateTime.Now;
                    SetChatOpen(true);
                }
                lastFeed = json;
                // Merge the entire virtualized Discord window before detecting
                // Happy Hour. This also works when the local archive is empty.
                EnsureChatLogLoaded();
                ulong previousFirst = history.Count > 0 ? history.First().Key : ulong.MaxValue;
                bool changed = false;
                int newlyArchived = 0;
                foreach (var msg in doc.RootElement.EnumerateArray())
                {
                    string id = msg.GetProperty("id").GetString() ?? "";
                    var match = System.Text.RegularExpressions.Regex.Match(id, @"^chat-messages-\d+-(\d+)$");
                    if (!match.Success || !ulong.TryParse(match.Groups[1].Value, out ulong key)) continue;
                    string user = msg.GetProperty("user").GetString() ?? "";
                    string sourceAuthor = msg.TryGetProperty("sourceAuthor", out var actualAuthor)
                        ? actualAuthor.GetString() ?? user : user;
                    string body = msg.GetProperty("body").GetString() ?? "";
                    string matchText = msg.TryGetProperty("matchText", out var detectionText) &&
                        detectionText.ValueKind == System.Text.Json.JsonValueKind.String
                        ? detectionText.GetString() ?? "" : "";
                    bool isHappyHour = sourceAuthor.Contains("Yagrum", StringComparison.OrdinalIgnoreCase) &&
                        (IsHappyHourAnnouncement(body) || IsHappyHourAnnouncement(matchText));
                    // Preserve the rendered chat wording unless only the
                    // Discord textContent contains the full styled announcement.
                    string archivalBody = isHappyHour && !IsHappyHourAnnouncement(body)
                        ? matchText : body;
                    string color = msg.TryGetProperty("color", out var cv) ? cv.GetString() ?? "" : "";
                    string[] images = msg.TryGetProperty("images", out var imageValues) &&
                        imageValues.ValueKind == System.Text.Json.JsonValueKind.Array
                        ? imageValues.EnumerateArray().Select(x => x.GetString() ?? "").Where(x => x.Length > 0).ToArray()
                        : Array.Empty<string>();
                    // Save image-only posts, not just those with a nonempty
                    // text body. Yagrum's colored HH announcement is a bitmap.
                    if ((archivalBody.Length > 0 || images.Length > 0) &&
                        (!archivedChat.TryGetValue(key, out var cached) ||
                         (isHappyHour && (!IsHappyHourAnnouncement(cached.Body) ||
                            !cached.User.Contains("Yagrum", StringComparison.OrdinalIgnoreCase))))) {
                        // Store the verified Discord author for bot text alerts
                        // even when Discord grouped this message under an
                        // earlier author's heading. Display history is unchanged.
                        archivedChat[key] = (isHappyHour ? sourceAuthor : user, archivalBody);
                        newlyArchived++;
                    }
                    if (images.Length > 0 && !archivedImageUrls.ContainsKey(key)) {
                        archivedImageUrls[key] = images;
                        newlyArchived++;
                    }
                    // Register Yagrum's genuine bot message BEFORE requesting
                    // its image. A late image download must still recognize
                    // this original snowflake after Discord pages farther back.
                    if (images.Length > 0 &&
                        sourceAuthor.Contains("Yagrum", StringComparison.OrdinalIgnoreCase))
                    {
                        foreach (string imageUrl in images)
                        {
                            if (!happyHourImageMessageIds.TryGetValue(imageUrl, out var ids))
                            {
                                ids = new System.Collections.Generic.HashSet<ulong>();
                                happyHourImageMessageIds[imageUrl] = ids;
                            }
                            ids.Add(key);
                            if (imageCache.ContainsKey(imageUrl))
                                RecognizePendingHappyHourImage(imageUrl);
                        }
                    }
                    if (images.Length > 0 &&
                        sourceAuthor.Contains("Yagrum", StringComparison.OrdinalIgnoreCase))
                    {
                        if (loggedHappyHourImageCandidates.Add(key))
                            Log("HAPPY HOUR | Examining image posted by Yagrum " +
                                "messageId=" + key + "; imageHosts=" +
                                string.Join(",", images.Select(url =>
                                    Uri.TryCreate(url, UriKind.Absolute, out var uri)
                                        ? uri.Host : "invalid")));
                        if (!verifiedHappyHourImageIds.Contains(key) &&
                            images.Any(url => imageCache.ContainsKey(url)) &&
                            loggedHappyHourImageMisses.Add(key))
                            Log("HAPPY HOUR | Yagrum image did not match rainbow signature " +
                                "messageId=" + key + "; decodedSizes=" +
                                string.Join(",", images.Where(url => imageCache.ContainsKey(url))
                                    .Select(url => imageCache[url].Width + "x" + imageCache[url].Height)));
                    }
                    foreach (string imageUrl in images)
                        if (!imageCache.ContainsKey(imageUrl) &&
                            (!failedImages.TryGetValue(imageUrl, out var retryTime) ||
                             DateTime.UtcNow >= retryTime))
                            _ = FetchChatImage(imageUrl);
                    if (!history.TryGetValue(key, out var existing) ||
                        existing.User != user || existing.Body != body || existing.Color != color ||
                        !existing.Images.SequenceEqual(images))
                    {
                        history[key] = (user, body, color, images);
                        changed = true;
                    }
                }
                if (newlyArchived > 0) {
                    try {
                        SaveChatArchive();
                        Log("CHAT | Saved " + newlyArchived + " chat archive updates; " +
                            archivedChat.Count + " total, oldest=" +
                            DiscordTimestamp(archivedChat.First().Key).ToString("O"));
                    } catch (Exception ex) {
                        Log("CHAT | Could not persist newly loaded history: " + ex.GetType().Name);
                    }
                }
                // Match only genuine archived Discord messages; the snowflake
                // timestamp supplies the real one-hour remaining time.
                DetectLatestHappyHour();
                if (!changed && !redrawImages && nativeMode) return;
                bool prepended = history.Count > 0 && history.First().Key < previousFirst;
                if (!messageBrowserReady || messageBrowser.CoreWebView2 == null) return;
                // A hidden WebView2 reports stale/zero scroll metrics. Give the
                // first authenticated renderer a real-sized parent before DOM
                // reconciliation, keeping the native loading text in front
                // until the message script succeeds.
                bool enteringNativeMode = !nativeMode;
                if (enteringNativeMode)
                {
                    messageClip.Visible = true;
                    messageBrowser.Visible = true;
                    messageBrowser.BringToFront();
                    nativeMessages.Visible = true;
                    nativeMessages.BringToFront();
                    messageClip.PerformLayout();
                }
                var browserMessages = history.Select(entry => new
                {
                    id = entry.Key.ToString(),
                    timestamp = DiscordTimestamp(entry.Key).ToString("O"),
                    user = entry.Value.User,
                    body = entry.Value.Body,
                    color = ParseHtmlColor(entry.Value.Color),
                    images = entry.Value.Images
                }).ToArray();
                string payload = System.Text.Json.JsonSerializer.Serialize(browserMessages);
                await messageBrowser.CoreWebView2.ExecuteScriptAsync("window.setMessages(" + payload + "," + (prepended ? "true" : "false") + ")");
                if (closingChat || IsDisposed || discordLoginVisible || !discordChannelReady) return;
                if (enteringNativeMode)
                {
                    nativeMode = true;
                    connectingChat = false;
                    web.Visible = false;
                    chatViewport.Visible = false;
                    // Sign-in hides the renderer's parent AND the real scrollbar.
                    // Show the correctly sized WebView and textured scrollbar
                    // together only after the first successful message update.
                    messageClip.Visible = true;
                    messageBrowser.Visible = true;
                    nativeMessages.Visible = false;
                    messageBrowser.BringToFront();
                    messageClip.BringToFront();
                    goldScrollbar.Visible = true;
                    goldScrollbar.BringToFront();
                    frameSurface.Visible = true;
                    FitWebView();
                    messageClip.PerformLayout();
                    frameSurface.Invalidate();
                    goldScrollbar.Invalidate();
                    goldScrollbar.Update();
                    Log("Native message view activated");
                }
                else goldScrollbar.Invalidate();
            }
            catch (Exception ex) { Log("Native feed error: " + ex.GetType().Name); }
        }
        readonly System.Windows.Forms.Timer watch = new() { Interval = 250 };
        // History requests must not depend on changes to Discord messages or launcher UI.
        readonly System.Windows.Forms.Timer historyWatch = new() { Interval = 200 };
        bool closingChat;
        bool refreshingChat;
        [DllImport("gdi32.dll")] static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
        [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr hwnd, IntPtr region, bool redraw);
        void RaiseFrame()
        {
            // Frame is rendered inside the browser DOM; native rails are not used.
        }
        void EnforceChatClip()
        {
            if (discordLoginVisible || !web.IsHandleCreated || chatViewport.ClientSize.Width < 1) return;
            // Native clipping remains effective when WebView2 recreates its
            // composition surface after Discord finishes loading.
            var region = CreateRectRgn(0, HeaderCrop, web.Width, web.Height);
            if (SetWindowRgn(web.Handle, region, true) == 0)
                Log("Unable to set WebView clip region");
            // Frame is now a browser overlay, not a competing native HWND.
        }
        // Clip the Discord header outside the visible child window.
        const int HeaderCrop = 48;
        void FitWebView()
        {
            if (discordLoginVisible)
            {
                // The sign-in browser is sized by its dedicated popup panel.
                return;
            }
            frameSurface.SetBounds(0, 0, ClientSize.Width, ClientSize.Height);
            messageClip.SetBounds(23, 60, Math.Max(1, ClientSize.Width - 60), Math.Max(1, ClientSize.Height - 78));
            nativeMessages.SetBounds(0, 0, messageClip.Width, messageClip.Height);
            messageBrowser.SetBounds(0, 0, messageClip.Width, messageClip.Height);
            goldScrollbar.SetBounds(Math.Max(0, ClientSize.Width - 37), 56, 20, Math.Max(1, ClientSize.Height - 74));
            chatViewport.SetBounds(14, 49, Math.Max(1, ClientSize.Width - 28), Math.Max(1, ClientSize.Height - 63));
            railTop.SetBounds(0, 0, ClientSize.Width, 10);
            railLeft.SetBounds(0, 10, 13, Math.Max(1, ClientSize.Height - 10));
            railRight.SetBounds(Math.Max(0, ClientSize.Width - 13), 10, 13, Math.Max(1, ClientSize.Height - 10));
            railBottom.SetBounds(0, Math.Max(0, ClientSize.Height - 13), ClientSize.Width, 13);
            titleBar.SetBounds(9, 9, Math.Max(1, ClientSize.Width - 18), 42);
            titleText.SetBounds(Math.Max(0, (ClientSize.Width - 92) / 2), 8, 92, 31);

            frameSurface.Invalidate();
            Log("Header visibility: frame=" + frameSurface.Visible + ", titleBar=" + titleBar.Visible + ", titleText=" + titleText.Visible + ", native=" + nativeMode);
            chatViewport.SendToBack();
            if (nativeMessages.Visible) messageClip.BringToFront();
            goldScrollbar.BringToFront();
            railTop.Visible = false; railLeft.Visible = false; railRight.Visible = false; railBottom.Visible = false;
            titleBar.Visible = false; titleText.Visible = false;
            // During first-feed loading the hidden Discord source continues
            // fetching, while only the native status panel is presented.
            chatViewport.Visible = !nativeMode && !connectingChat;

            web.SetBounds(0, -HeaderCrop, chatViewport.ClientSize.Width, chatViewport.ClientSize.Height + HeaderCrop);
            EnforceChatClip();
        }
        // Companion window stays visible when the chat panel is tucked away.
        readonly Form chatToggleWindow = new()
        {
            FormBorderStyle = FormBorderStyle.None,
            ShowInTaskbar = false,
            StartPosition = FormStartPosition.Manual,
            BackColor = System.Drawing.Color.FromArgb(145, 104, 48),
            TopMost = false,
            Size = new System.Drawing.Size(68, 168)
        };
        readonly Button chatToggleButton = new()
        {
            Dock = DockStyle.Fill,
            FlatStyle = FlatStyle.Flat,
            BackColor = System.Drawing.Color.FromArgb(167, 124, 58),
            ForeColor = System.Drawing.Color.White,
            Font = new System.Drawing.Font("Segoe UI", 17, System.Drawing.FontStyle.Bold),
            Cursor = Cursors.Hand,
            Text = "",
            TabStop = false
        };
        readonly ContextMenuStrip chatModeMenu = new();
        readonly string chatModeFile = Path.Combine(ChatDataRoot, "chat-display-mode.txt");
        string chatDisplayMode = "Automatic";
        bool chatOpen, feedInitialized;
        DateTime lastChatActivity = DateTime.MinValue;
        ulong latestMessageId;
        WinEventCallback? launcherLocationCallback;
        IntPtr launcherLocationHook;
        bool repositionQueued;
        void WatchLauncherMovement()
        {
            if (launcherLocationHook != IntPtr.Zero || !IsWindow(owner)) return;
            uint threadId = GetWindowThreadProcessId(owner, out uint processId);
            launcherLocationCallback = (hook, eventType, hwnd, objectId, childId, eventThread, eventTime) =>
            {
                if (hwnd != owner || objectId != 0 || childId != 0 ||
                    closingChat || IsDisposed || !IsHandleCreated) return;
                // Keep the Happy Hour banner aligned on EVERY owner movement
                // event, even if a chat reposition is already queued.
                // Native SetWindowPos runs immediately; BeginInvoke below is
                // retained only for the more expensive Game Chat layout.
                PositionHappyHourBanner();
                if (repositionQueued) return;
                repositionQueued = true;
                try
                {
                    BeginInvoke((Action)(() =>
                    {
                        repositionQueued = false;
                        if (!closingChat && !IsDisposed) PositionChatWindows();
                    }));
                }
                catch (InvalidOperationException) { repositionQueued = false; }
            };
            // Observe the launcher's native movement, rather than waiting for the
            // 500ms Discord polling timer. Hook only the launcher's UI thread.
            launcherLocationHook = SetWinEventHook(0x800B, 0x800B, IntPtr.Zero,
                launcherLocationCallback, processId, threadId, 0);
            if (launcherLocationHook == IntPtr.Zero)
                Log("Launcher movement hook unavailable; using polling fallback.");
        }
        bool docked;
        bool signInExpanded;
        readonly string cssFile = Path.Combine(AppContext.BaseDirectory, "chat.css");
        readonly string layoutFile = Path.Combine(AppContext.BaseDirectory, "chat.ini");
        DateTime cssStamp = DateTime.MinValue, layoutStamp = DateTime.MinValue;
        int chatX = 94, chatY = 420, chatWidth = 390, chatHeight = 498;
        byte chatOpacity = 255;
        string userCss = Css;
        static int ReadInt(string line, string key, int fallback) =>
            line.StartsWith(key + "=", StringComparison.OrdinalIgnoreCase)
            && int.TryParse(line[(key.Length + 1)..].Trim(), out var v) ? v : fallback;
        void LoadLayout()
        {
            if (!File.Exists(layoutFile)) return;
            var stamp = File.GetLastWriteTimeUtc(layoutFile);
            if (stamp == layoutStamp) return;
            layoutStamp = stamp;
            foreach (var raw in File.ReadAllLines(layoutFile))
            {
                var line = raw.Trim();
                if (line.StartsWith(";") || line.StartsWith("[") || line.Length == 0) continue;
                chatX = ReadInt(line, "X", chatX);
                chatY = ReadInt(line, "Y", chatY);
                chatWidth = Math.Clamp(ReadInt(line, "Width", chatWidth), 160, 700);
                chatHeight = Math.Clamp(ReadInt(line, "Height", chatHeight), 140, 700);
                chatOpacity = (byte)Math.Clamp(ReadInt(line, "Opacity", chatOpacity), 120, 255);
            }
            if (docked) { PositionChatWindows(); ApplyWindowOpacity(); }
            Log("Layout reloaded");
        }
        void ApplyWindowOpacity()
        {
            if (!IsHandleCreated) return;
            var ex = GetWindowLongEx(Handle, GWL_EXSTYLE);
            if (chatOpacity == 255) { SetWindowLongEx(Handle, GWL_EXSTYLE, ex & ~WS_EX_LAYERED); return; }
            SetWindowLongEx(Handle, GWL_EXSTYLE, ex | WS_EX_LAYERED);
            if (!SetLayeredWindowAttributes(Handle, 0, chatOpacity, LWA_ALPHA))
                Log("Layered alpha failed: " + Marshal.GetLastWin32Error());
        }
        async Task LoadCss()
        {
            if (!File.Exists(cssFile)) return;
            var stamp = File.GetLastWriteTimeUtc(cssFile);
            if (stamp == cssStamp) return;
            cssStamp = stamp;
            userCss = File.ReadAllText(cssFile);
            await ApplyCss();
            Log("CSS reloaded");
        }

        readonly Label version = new() { Text = "TES3NP CHAT • " + ChatBuild, Dock = DockStyle.Top, Height = 24, ForeColor = System.Drawing.Color.FromArgb(225, 191, 125), BackColor = System.Drawing.Color.FromArgb(35, 26, 18), TextAlign = System.Drawing.ContentAlignment.MiddleCenter, Font = new System.Drawing.Font("Georgia", 9f, System.Drawing.FontStyle.Bold) };
        readonly string logPath = Path.Combine(ChatDataRoot, "chat-host.log");
        void Log(string message)
        {
            try
            {
                // Keep useful event details without leaving privacy placeholder fields.
                // The private Discord chat archive has a separate writer and is unchanged.
                string safe = System.Text.RegularExpressions.Regex.Replace(message,
                    @"(?i)\[(?:credential|user|identity|secret|url|path|network path|email|IP|identifier|Discord ID) omitted\]", "");
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"(?i)\b(?:Account|User|Windows\s+User(?:name)?|Password|Token|Secret|Authorization|Cookie|Api[-_]?Key)\s*[:=][^|\r\n]*", "");
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"(?i)%(?:LOCALAPPDATA|APPDATA|USERPROFILE)%(?:[/\\][^\r\n|]*)?", "");
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"(?i)\b(?:https?|wss?)://[^\s|]+", "");
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"(?i)\b[A-Z]:[/\\][^\r\n|]*", "");
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"\\\\[^\r\n|]*", "");
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "");
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"\b(?:\d{1,3}\.){3}\d{1,3}\b", "");
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"\b\d{16,21}\b", "");
                string windowsUser = Environment.UserName;
                if (windowsUser.Length >= 3)
                    safe = System.Text.RegularExpressions.Regex.Replace(safe,
                        @"(?i)(?<![\p{L}\p{N}_])" + System.Text.RegularExpressions.Regex.Escape(windowsUser) + @"(?![\p{L}\p{N}_])", "");
                var parts = new System.Collections.Generic.List<string>();
                foreach (string piece in safe.Replace('\r', ' ').Replace('\n', ' ').Split('|'))
                {
                    string item = System.Text.RegularExpressions.Regex.Replace(piece,
                        @"(?i)\b(?:Executable(?:\s+path)?|Source\s+path|Destination|Install|Stage|Path|Folder|File|URL|Mail|Email)\s*[:=]\s*$", "");
                    item = item.Trim(' ', '\t', ':', '=');
                    if (item.Length > 0) parts.Add(item);
                }
                safe = string.Join(" | ", parts);
                if (safe.Length == 0) return;
                Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
                File.AppendAllText(logPath, DateTime.Now.ToString("s") + " | " +
                    ChatBuild + " | " + safe + Environment.NewLine);
            }
            catch { }
        }
        public ChatHost(IntPtr owner)
        {
            this.owner = owner;
            Text = "tes3np Chat Host";
            try
            {
                if (File.Exists(chatModeFile))
                {
                    string saved = File.ReadAllText(chatModeFile).Trim();
                    if (saved is "Automatic" or "Always Shown" or "Always Hidden")
                        chatDisplayMode = saved;
                }
            }
            catch { }
            chatToggleButton.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(237, 199, 120);
            chatToggleButton.FlatAppearance.BorderSize = 2;
            chatToggleButton.Paint += (_, e) =>
            {
                var g = e.Graphics;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                using var arrowPen = new System.Drawing.Pen(System.Drawing.Color.White, 5)
                {
                    StartCap = System.Drawing.Drawing2D.LineCap.Round,
                    EndCap = System.Drawing.Drawing2D.LineCap.Round,
                    LineJoin = System.Drawing.Drawing2D.LineJoin.Round
                };
                // Side-by-side layout: bold arrow at left, vertical label at right.
                // Both are centered as one group within the tall gold tab.
                int direction = chatOpen ? -1 : 1;
                int arrowCenterX = 22;
                int arrowY = chatToggleButton.ClientSize.Height / 2;
                int tipX = arrowCenterX + direction * 13;
                int tailX = arrowCenterX - direction * 13;
                g.DrawLine(arrowPen, tailX, arrowY, tipX, arrowY);
                g.DrawLine(arrowPen, tipX - direction * 10, arrowY - 10, tipX, arrowY);
                g.DrawLine(arrowPen, tipX - direction * 10, arrowY + 10, tipX, arrowY);
                using var labelFont = new System.Drawing.Font("Segoe UI", 11,
                    System.Drawing.FontStyle.Bold);
                using var labelBrush = new System.Drawing.SolidBrush(System.Drawing.Color.White);
                var state = g.Save();
                g.TranslateTransform(52, chatToggleButton.ClientSize.Height / 2);
                g.RotateTransform(-90);
                using var alignment = new System.Drawing.StringFormat
                {
                    Alignment = System.Drawing.StringAlignment.Center,
                    LineAlignment = System.Drawing.StringAlignment.Center
                };
                g.DrawString("Game Chat", labelFont, labelBrush,
                    new System.Drawing.RectangleF(-65, -12, 130, 24), alignment);
                g.Restore(state);
            };
            // The toggle is now an actual launcher GUI control.
            foreach (string mode in new[] { "Automatic", "Always Shown", "Always Hidden" })
            {
                string selectedMode = mode;
                chatModeMenu.Items.Add(mode, null, (_, _) =>
                {
                    chatDisplayMode = selectedMode;
                    try
                    {
                        Directory.CreateDirectory(Path.GetDirectoryName(chatModeFile)!);
                        File.WriteAllText(chatModeFile, chatDisplayMode);
                    }
                    catch { }
                    SetChatOpen(chatDisplayMode == "Always Shown");
                });
            }
            chatModeMenu.Opening += (_, _) =>
            {
                foreach (ToolStripMenuItem item in chatModeMenu.Items)
                    item.Checked = item.Text == chatDisplayMode;
            };
            chatToggleButton.MouseUp += (_, e) =>
            {
                if (e.Button == MouseButtons.Right)
                    chatModeMenu.Show(chatToggleButton, e.Location);
            };
            chatToggleButton.Click += (_, _) =>
            {
                if (!discordChannelReady) discordSignInRequested = true;
                if (discordLoginVisible) {
                    ToggleGameChatDiscordSignIn();
                    return;
                }
                // A manual toggle overrides automatic popups until the next message.
                SetChatOpen(!chatOpen);
                if (chatDisplayMode == "Automatic" && chatOpen)
                    lastChatActivity = DateTime.Now;
            };
            chatToggleWindow.FormClosing += (_, e) =>
            {
                if (!closingChat) { e.Cancel = true; chatToggleWindow.Hide(); }
            };
            FormBorderStyle = FormBorderStyle.None;
            DoubleBuffered = true;
            Paint += (_, e) =>
            {
                var g = e.Graphics;
                int w = ClientSize.Width, h = ClientSize.Height;
                g.Clear(System.Drawing.Color.FromArgb(9, 8, 7));
                // Layered weathered-metal rim, dark recess, and engraved highlight.
                using var rim = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(91, 65, 31));
                using var metal = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(168, 131, 70));
                using var highlight = new System.Drawing.Pen(System.Drawing.Color.FromArgb(219, 185, 113), 2);
                using var shadow = new System.Drawing.Pen(System.Drawing.Color.FromArgb(37, 26, 15), 3);
                using var titleFill = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(16, 12, 9));
                using var gold = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(216, 182, 112));
                using var titleFont = new System.Drawing.Font("Georgia", 14, System.Drawing.FontStyle.Bold);
                g.FillRectangle(rim, 0, 0, w, h);
                // Recreate the reference's densely mottled bronze stone rather
                // than overlaying speckles on the old horizontal wood texture.
                using (var baseGold = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(145, 112, 62)))
                    g.FillRectangle(baseGold, 4, 4, w - 8, 43);
                var grainRandom = new Random(31337);
                using (var darkGrain = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(93, 67, 34)))
                using (var midGrain = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(177, 143, 84)))
                using (var lightGrain = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(207, 177, 112)))
                {
                    for (int i = 0; i < w * 35; i++)
                    {
                        int px = grainRandom.Next(5, Math.Max(6, w - 5));
                        int py = grainRandom.Next(5, 46);
                        int grain = grainRandom.Next(1, 4);
                        g.FillRectangle(i % 5 == 0 ? lightGrain : (i % 3 == 0 ? midGrain : darkGrain),
                            px, py, grain, grainRandom.Next(1, 3));
                    }
                }
                using (var edge = new System.Drawing.Pen(System.Drawing.Color.FromArgb(209, 172, 100)))
                {
                    g.DrawLine(edge, 5, 5, w - 6, 5);
                    g.DrawLine(edge, 5, 42, w - 6, 42);
                }
                using (var inset = new System.Drawing.Pen(System.Drawing.Color.FromArgb(49, 35, 18)))
                    g.DrawLine(inset, 6, 45, w - 7, 45);
                g.FillRectangle(titleFill, 15, 53, w - 30, h - 69);
                g.DrawRectangle(shadow, 5, 5, w - 11, h - 11);
                g.DrawRectangle(highlight, 2, 2, w - 5, h - 5);
                g.DrawLine(shadow, 6, 50, w - 7, 50);
                var size = g.MeasureString("Chat", titleFont);
                g.FillRectangle(titleFill, (w - size.Width) / 2 - 14, 3, size.Width + 28, 30);
                g.DrawString("Chat", titleFont, gold, (w - size.Width) / 2, 8);
            };
            Log("Header diagnostics: texture=" + (headerTexture == null ? "MISSING" : headerTexture.Width + "x" + headerTexture.Height) +
                ", border=" + (borderTexture == null ? "MISSING" : borderTexture.Width + "x" + borderTexture.Height) +
                ", baseDir=" + AppContext.BaseDirectory);
            titleBar.Paint += (_, e) =>
            {
                if (headerTexture != null)
                {
                    e.Graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    e.Graphics.DrawImage(headerTexture, titleBar.ClientRectangle);
                }
            };
            ShowInTaskbar = false;
            BackColor = System.Drawing.Color.Black;
            // Native child window alpha lets launcher artwork show through opaque Discord layers.
            chatViewport.Controls.Add(web);
            frameSurface.Paint += (_, e) =>
            {
                var g = e.Graphics;
                int w = frameSurface.Width, h = frameSurface.Height;
                if (w < 80 || h < 100) return;
                g.Clear(System.Drawing.Color.FromArgb(13, 11, 9));
                using var bronze = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(151, 113, 58));
                using var bright = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(211, 177, 110));
                using var dark = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(57, 39, 21));
                using var black = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(10, 9, 8));
                g.FillRectangle(bronze, 0, 0, w, h);
                if (borderTexture != null)
                {
                    using var texture = new System.Drawing.TextureBrush(borderTexture, System.Drawing.Drawing2D.WrapMode.Tile);
                    g.FillRectangle(texture, 0, 0, w, 13);
                    g.FillRectangle(texture, 0, h - 13, w, 13);
                    using var vertical = (System.Drawing.Bitmap)borderTexture.Clone();
                    vertical.RotateFlip(System.Drawing.RotateFlipType.Rotate90FlipNone);
                    using var sideTexture = new System.Drawing.TextureBrush(vertical, System.Drawing.Drawing2D.WrapMode.Tile);
                    g.FillRectangle(sideTexture, 0, 0, 13, h);
                    g.FillRectangle(sideTexture, w - 13, 0, 13, h);
                }
                // Header: use a continuous weathered bronze surface, not the
                // border/header bitmaps. Those contain horizontal trim lines
                // which repeat as broken stripes when tiled vertically.
                using (var headerBase = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(143, 109, 60)))
                    g.FillRectangle(headerBase, 13, 13, w - 26, 39);
                var headerNoise = new Random(4108);
                using (var darkMottle = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(112, 83, 45)))
                using (var lightMottle = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(184, 151, 92)))
                using (var midMottle = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(165, 129, 72)))
                {
                    for (int n = 0; n < w * 10; n++)
                    {
                        int x = headerNoise.Next(13, Math.Max(14, w - 13));
                        int y = headerNoise.Next(13, 52);
                        g.FillRectangle(n % 5 == 0 ? lightMottle : (n % 3 == 0 ? midMottle : darkMottle),
                            x, y, headerNoise.Next(1, 4), headerNoise.Next(1, 3));
                    }
                }
                using (var headerGold = new System.Drawing.Pen(System.Drawing.Color.FromArgb(207, 169, 98)))
                using (var headerShade = new System.Drawing.Pen(System.Drawing.Color.FromArgb(56, 39, 20)))
                {
                    g.DrawLine(headerGold, 13, 14, w - 14, 14);
                    g.DrawLine(headerShade, 13, 48, w - 14, 48);
                    g.DrawLine(headerGold, 13, 51, w - 14, 51);
                }
                // Preserve the actual Morrowind border artwork across the Chat header.
                // The old full-frame random flecks obscured the texture with flat colors.
                // Keep the weathering below the header without painting over its artwork.
                var random = new Random(4108);
                for (int n = 0; n < w * 9; n++)
                {
                    int x = random.Next(w), y = random.Next(h);
                    if (y < 53) continue;
                    g.FillRectangle(n % 3 == 0 ? bright : dark, x, y, random.Next(1, 4), 1);
                }
                using var goldPen = new System.Drawing.Pen(System.Drawing.Color.FromArgb(224, 190, 119), 2);
                using var darkPen = new System.Drawing.Pen(System.Drawing.Color.FromArgb(45, 29, 14), 3);
                g.DrawRectangle(goldPen, 2, 2, w - 5, h - 5);
                g.DrawRectangle(darkPen, 8, 8, w - 17, h - 17);
                g.FillRectangle(black, 13, 52, w - 26, h - 65);
                g.DrawLine(goldPen, 12, 51, w - 13, 51);
                using var headingFont = new System.Drawing.Font("Georgia", 13, System.Drawing.FontStyle.Regular);
                var titleSize = g.MeasureString("Live Game Chat", headingFont);
                g.FillRectangle(black, (w - titleSize.Width) / 2 - 14, 8, titleSize.Width + 28, 43);
                using var centeredTitle = new System.Drawing.StringFormat
                {
                    Alignment = System.Drawing.StringAlignment.Center,
                    LineAlignment = System.Drawing.StringAlignment.Center
                };
                g.DrawString("Live Game Chat", headingFont, bright,
                    new System.Drawing.RectangleF((w - titleSize.Width) / 2 - 14, 8,
                        titleSize.Width + 28, 43), centeredTitle);
                // The real goldScrollbar is the only scrollbar. Drawing a
                // second fake track and thumb on this background left stale
                // artwork visible while the control was hidden during sign-in.
            };
            // The frame and text are painted on one surface; no child can obscure its edges.
            frameSurface.Controls.Add(chatViewport);
            messageClip.Controls.Add(nativeMessages);
            messageClip.Controls.Add(messageBrowser);
            nativeMessages.BringToFront();
            frameSurface.Controls.Add(messageClip);
            frameSurface.Controls.Add(goldScrollbar);
            frameSurface.Controls.Add(railTop);
            frameSurface.Controls.Add(railLeft);
            frameSurface.Controls.Add(railRight);
            frameSurface.Controls.Add(railBottom);
            frameSurface.Controls.Add(titleBar);
            frameSurface.Controls.Add(titleText);
            int lastThumbY = -1, lastThumbHeight = -1;
            goldScrollbar.Paint += (_, e) =>
            {
                var g = e.Graphics;
                int h = goldScrollbar.ClientSize.Height, w = 20;
                g.FillRectangle(System.Drawing.Brushes.Black, 0, 0, goldScrollbar.Width, h);
                g.TranslateTransform(goldScrollbar.Width - w, 0);
                if (h < 65 || scrollbarTexture == null) return;
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
                var image = scrollbarTexture;
                // Keep the Morrowind arrow caps, but draw one continuous recessed
                // track and a clean, flat parchment thumb (no stretched sprite).
                g.DrawImage(image, new System.Drawing.Rectangle(0, 0, w, 27),
                    new System.Drawing.Rectangle(0, 0, image.Width, 27), System.Drawing.GraphicsUnit.Pixel);
                g.DrawImage(image, new System.Drawing.Rectangle(0, h - 27, w, 27),
                    new System.Drawing.Rectangle(0, image.Height - 27, image.Width, 27), System.Drawing.GraphicsUnit.Pixel);
                int trackHeight = h - 54;
                using (var trackDark = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(12, 10, 7)))
                    g.FillRectangle(trackDark, 2, 27, 16, trackHeight);
                using (var goldEdge = new System.Drawing.Pen(System.Drawing.Color.FromArgb(128, 101, 54)))
                    g.DrawRectangle(goldEdge, 2, 27, 15, trackHeight - 1);
                using (var innerShadow = new System.Drawing.Pen(System.Drawing.Color.FromArgb(53, 42, 25)))
                    g.DrawRectangle(innerShadow, 4, 29, 11, Math.Max(1, trackHeight - 5));
                int thumbY = ChatThumbY(h, out int thumbHeight);
                lastThumbY = thumbY;
                lastThumbHeight = thumbHeight;
                // A narrow, square-edged thumb matching the reference image.
                using (var thumbFill = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(188, 166, 111)))
                    g.FillRectangle(thumbFill, 5, thumbY, 10, thumbHeight);
                using (var thumbHighlight = new System.Drawing.Pen(System.Drawing.Color.FromArgb(223, 203, 151)))
                {
                    g.DrawLine(thumbHighlight, 5, thumbY, 14, thumbY);
                    g.DrawLine(thumbHighlight, 5, thumbY, 5, thumbY + thumbHeight - 1);
                }
                using (var thumbShadow = new System.Drawing.Pen(System.Drawing.Color.FromArgb(87, 69, 40)))
                {
                    g.DrawLine(thumbShadow, 14, thumbY + 1, 14, thumbY + thumbHeight - 1);
                    g.DrawLine(thumbShadow, 6, thumbY + thumbHeight - 1, 14, thumbY + thumbHeight - 1);
                }
            };
            // With WS_VSCROLL disabled the RichEdit control does not reliably
            // perform its default wheel scrolling. Scroll its text explicitly.
            void ScrollWheelMessages(MouseEventArgs e)
            {
                if (!messageBrowserReady || e.Delta == 0) return;
                int notches = Math.Max(1, Math.Abs(e.Delta) / 120);
                int lines = 3 * notches * (e.Delta > 0 ? -1 : 1);
                if (e.Delta < 0) historyCatchupActive = false;
                ScrollHtml(lines * 22);
                goldScrollbar.Invalidate();
                if (e.Delta > 0) RequestOlderMessages();
            }
            goldScrollbar.MouseWheel += (_, e) => ScrollWheelMessages(e);
            nativeMessages.MouseWheel += (_, e) => ScrollWheelMessages(e);
            messageClip.MouseWheel += (_, e) => ScrollWheelMessages(e);
            int dragOffset = -1;
            goldScrollbar.MouseDown += (_, e) =>
            {
                if (!messageBrowserReady || e.X < goldScrollbar.Width - 20) return;
                if (e.Y < 27 || e.Y >= goldScrollbar.Height - 27)
                {
                    ScrollHtml(e.Y < 27 ? -66 : 66);
                }
                else
                {
                    int thumbY = ChatThumbY(goldScrollbar.Height, out int thumbHeight);
                    dragOffset = e.Y >= thumbY && e.Y < thumbY + thumbHeight
                        ? e.Y - thumbY : thumbHeight / 2;
                    goldScrollbar.Capture = true;
                    ScrollChatToThumb(e.Y, dragOffset);
                }
                goldScrollbar.Invalidate();
                RequestOlderMessages();
            };
            goldScrollbar.MouseMove += (_, e) =>
            {
                if (dragOffset < 0 || e.Button != MouseButtons.Left) return;
                ScrollChatToThumb(e.Y, dragOffset);
            };
            goldScrollbar.MouseUp += (_, _) =>
            {
                dragOffset = -1;
                goldScrollbar.Capture = false;
                // HTML scrolling ends when mouse capture is released.
                goldScrollbar.Invalidate();
            };
            foreach (var rail in new[] { railTop, railLeft, railRight, railBottom })
            {
                rail.BackColor = System.Drawing.Color.FromArgb(153, 118, 64);
                rail.Paint += (_, e) =>
                {
                    var g = e.Graphics;
                    var r = new Random(812 + rail.Width * 3 + rail.Height);
                    using var dark = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(75, 53, 27));
                    using var light = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(204, 173, 108));
                    for (int n = 0; n < rail.Width * rail.Height / 5; n++)
                        g.FillRectangle(n % 3 == 0 ? light : dark, r.Next(Math.Max(1, rail.Width)), r.Next(Math.Max(1, rail.Height)), 2, 1);
                    using var edge = new System.Drawing.Pen(System.Drawing.Color.FromArgb(224, 193, 125));
                    g.DrawRectangle(edge, 1, 1, Math.Max(1, rail.Width - 3), Math.Max(1, rail.Height - 3));
                };
            }
            messageClip.SetBounds(23, 60, Math.Max(1, frameSurface.Width - 60), Math.Max(1, frameSurface.Height - 78));
            nativeMessages.SetBounds(0, 0, messageClip.Width, messageClip.Height);
            goldScrollbar.SetBounds(Math.Max(0, frameSurface.Width - 37), 56, 20, Math.Max(1, frameSurface.Height - 74));
            // Keep the native scrollbar hidden until the first actual feed.
            goldScrollbar.Visible = false;
            nativeMessages.Visible = true;
            nativeMessages.Text = "Connecting to live chat...";
            nativeMessages.Font = new System.Drawing.Font("Georgia", 10, System.Drawing.FontStyle.Regular);
            messageClip.BringToFront();
            goldScrollbar.BringToFront();
            railTop.BringToFront(); railLeft.BringToFront(); railRight.BringToFront(); railBottom.BringToFront();
            titleBar.BringToFront(); titleText.BringToFront();
            Controls.Add(frameSurface);
            // Browser is inset; native host draws its own border outside the browser rectangle.
            Resize += (_, _) => FitWebView();
            FitWebView();
            // The diagnostic version label is no longer part of the chat UI.
            Log("Host launched; owner=" + owner);
            Width = 266; Height = 342;
            LoadLayout();

            Shown += async (_, _) =>
            {
                // Let WinForms finish showing the top-level host before parenting it.
                Log("STARTUP | WinForms shown; queuing dock");
                BeginInvoke((Action)(() => DockToLauncher()));
                // The saved Discord archive is our only offline evidence.
                // Load it immediately, whether this browser is signed in or not.
                DetectLatestHappyHour();
                try
                {
                    string data = Path.Combine(ChatDataRoot, "chat-webview2");
                    freshDiscordProfile = !Directory.Exists(data) || !Directory.EnumerateFileSystemEntries(data).Any();
                    Directory.CreateDirectory(data);
                    var env = await CoreWebView2Environment.CreateAsync(null, data);
                    discordEnvironment = env;
                    if (expansionDownloadsWindow is { IsDisposed: false })
                        _ = InitializeExpansionDownloadsBrowser();
                    await web.EnsureCoreWebView2Async(env);
                    EnforceChatClip();
                    web.DefaultBackgroundColor = System.Drawing.Color.Transparent;
                    await LoadCss();
                    Log("WebView2 initialized");
                    web.CoreWebView2.Settings.AreDevToolsEnabled = false;
                    web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                    // Install styling before Discord's SPA renders, and keep
                    // it in place as React replaces DOM nodes.
                    await web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(
                        "(() => { const css = " + System.Text.Json.JsonSerializer.Serialize(userCss) +
                        "; const install=()=>{if(!document.head)return;let s=document.getElementById('tes3np-chat-style');if(!s){s=document.createElement('style');s.id='tes3np-chat-style';document.head.appendChild(s)}s.textContent=css;if(document.body&&!document.getElementById('tes3np-frame')){const f=document.createElement('div');f.id='tes3np-frame';document.body.appendChild(f)}};install();document.addEventListener('DOMContentLoaded',install);new MutationObserver(()=>{if(!document.getElementById('tes3np-chat-style')||(document.body&&!document.getElementById('tes3np-frame')))install()}).observe(document,{childList:true,subtree:true});})()");
                    // The Not Now control lives inside Discord's own scrolling form,
                    // but its click is handled by the existing native Chat Host.
                    web.CoreWebView2.WebMessageReceived += (_, args) =>
                    {
                        try
                        {
                            if (discordLoginVisible &&
                                args.Source.StartsWith("https://discord.com/login", StringComparison.OrdinalIgnoreCase) &&
                                args.TryGetWebMessageAsString() == "tes3np-sign-in-later")
                                DismissDiscordSignIn();
                        }
                        catch (Exception ex) { Log("Discord cancellation: " + ex.GetType().Name); }
                    };
                    web.CoreWebView2.NavigationCompleted += async (_, _) => await UpdateViewMode();
                    web.CoreWebView2.SourceChanged += async (_, _) => await UpdateViewMode();
                    web.CoreWebView2.NewWindowRequested += (_, e) =>
                    {
                        e.Handled = true;
                        if (e.Uri.StartsWith("https://discord.com/", StringComparison.OrdinalIgnoreCase))
                            web.CoreWebView2.Navigate(e.Uri);
                    };
                    // Initialize the local HTML renderer while its WinForms
                    // parent is still visible. Hiding it for Discord sign-in
                    // before initialization could leave the native chat blank
                    // until the entire launcher was restarted.
                    await InitMessageBrowser(env);
                    if (closingChat || IsDisposed) return;
                    if (freshDiscordProfile) ShowDiscordSignIn();
                    else ShowConnectingChat();
                    web.CoreWebView2.Navigate(freshDiscordProfile ? "https://discord.com/login" : Channel);
                    Log(freshDiscordProfile ? "Fresh Discord profile: opening sign-in" : "Navigating to channel");
                }
                catch (Exception ex)
                {
                    Log("ERROR " + ex.GetType().Name);
                    MessageBox.Show("WebView2 chat unavailable: " + ex.Message + "\nInstall Microsoft Edge WebView2 Runtime.", "tes3np Chat");
                }
            };
            FormClosing += (_, _) =>
            {
                CancelPendingExpansionPrompt();
                closingChat = true;
                watch.Stop();
                historyWatch.Stop();
                if (launcherLocationHook != IntPtr.Zero)
                {
                    UnhookWinEvent(launcherLocationHook);
                    launcherLocationHook = IntPtr.Zero;
                }
                chatToggleWindow.Dispose();
                CloseEmbeddedExpansionDownloads();
            };
            watch.Tick += async (_, _) =>
            {
                if (closingChat || refreshingChat || IsDisposed) return;
                if (!IsWindow(owner)) { Close(); return; }
                refreshingChat = true;
                try
                {
                try { LoadLayout(); await LoadCss(); } catch (Exception ex) { Log("Reload error: " + ex.GetType().Name); }
                if (!docked && !signInExpanded) DockToLauncher();
                if (docked && !nativeMode) { EnforceChatClip(); RaiseFrame(); }
                await CheckDiscordAuthentication();
                await RefreshNativeMessages();
                PositionChatWindows();
                if (pendingExpansionPrompt == 0 && !discordLoginVisible && chatDisplayMode == "Automatic" && chatOpen &&
                    DateTime.Now - lastChatActivity > TimeSpan.FromSeconds(10) &&
                    !Bounds.Contains(Cursor.Position))
                    SetChatOpen(false);
                if (nativeMode && goldScrollbar.Visible)
                {
                    int thumbY = ChatThumbY(goldScrollbar.Height, out int thumbHeight);
                    if (thumbY != lastThumbY || thumbHeight != lastThumbHeight)
                        goldScrollbar.Invalidate();
                }
                }
                catch (ObjectDisposedException) { }
                catch (Exception ex) { if (!closingChat) Log("Chat timer error: " + ex.GetType().Name); }
                finally { refreshingChat = false; }
            };
            historyWatch.Tick += (_, _) =>
            {
                // The scan runs in the hidden source regardless of the
                // visible chat's open/closed state or manual scroll position.
                if (!closingChat && !IsDisposed && nativeMode) {
                    if (!initialBackfillComplete)
                        BackfillUntilHappyHour();
                    else
                        RequestOlderMessages();
                }
            };
            historyWatch.Start();
            watch.Start();
            // Cache-first discovery is deferred until the embedded Discord
            // channel is authenticated and its chat DOM is ready. Expired
            // archived announcements cannot trigger a production banner.
        }
        // Discord changes its hashed CSS classes frequently. Remove the actual
        // channel heading (including the two action icons) by DOM structure.
        const string HideChannelHeaderScript = """
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
            """;
        async Task HideChannelHeader()
        {
            if (web.CoreWebView2 == null) return;
            try { await web.CoreWebView2.ExecuteScriptAsync(HideChannelHeaderScript); }
            catch (Exception ex) { Log("Header removal error: " + ex.GetType().Name); }
        }
        async Task ApplyCss()
        {
            if (web.CoreWebView2 == null) return;
            var js = "(() => { const css = " + System.Text.Json.JsonSerializer.Serialize(userCss) +
                "; let style=document.getElementById('tes3np-chat-style'); if(!style){style=document.createElement('style');style.id='tes3np-chat-style';document.head.appendChild(style);} style.textContent=css; if(document.body&&!document.getElementById('tes3np-frame')){const f=document.createElement('div');f.id='tes3np-frame';document.body.appendChild(f);} })()";
            try { await web.CoreWebView2.ExecuteScriptAsync(js); await HideChannelHeader(); } catch (Exception ex) { Log("CSS error: " + ex.GetType().Name); }
        }
        void SuspendHappyHourUntilDiscordReturns(string reason)
        {
            if (!discordChannelReady) return;
            discordChannelReady = false;
            Log("CHAT | Discord channel unavailable (" + reason +
                "); pausing live feed and history paging. Verified Happy Hour banner remains independent.");
            // Recheck the live channel on the next authenticated session.
            // Neither an expired nor a missing archive can show a banner.
            // Keep the existing genuine activation, its absolute expiry,
            // dismissal state and timer unchanged across sign-out.
            initialBackfillComplete = false;
            initialBackfillStarted = DateTime.MinValue;
            initialBackfillAttempts = 0;
            waitingForLiveFeedAfterHistory = false;
        }

        async Task CheckDiscordAuthentication()
        {
            if (web.CoreWebView2 == null || closingChat) return;
            try
            {
                string url = web.CoreWebView2.Source ?? "";
                bool onLogin = url.StartsWith("https://discord.com/login", StringComparison.OrdinalIgnoreCase)
                    || url.StartsWith("https://discord.com/register", StringComparison.OrdinalIgnoreCase);
                // A login URL is definitive, even while the login page's
                // JavaScript/DOM is still mounting.
                if (onLogin) {
                    SuspendHappyHourUntilDiscordReturns("sign-in URL");
                    ShowDiscordSignIn();
                    await StyleDiscordLogin();
                    return;
                }
                string state = await web.CoreWebView2.ExecuteScriptAsync(
                    "(() => { if (document.readyState === 'loading') return 'loading'; " +
                    "if (document.querySelector('[data-list-id=chat-messages]')) return 'chat'; " +
                    "if (document.querySelector('input[type=password]')) return 'login'; " +
                    "const t = document.body?.innerText || ''; " +
                    "if (/Discord App Detected|Discord App Launched/i.test(t)) return 'app-prompt'; " +
                    "return 'pending'; })()");
                if (closingChat || IsDisposed || web.CoreWebView2 == null ||
                    !string.Equals(url, web.CoreWebView2.Source,
                        StringComparison.OrdinalIgnoreCase)) return;
                if (state == "\"chat\"" &&
                    url.StartsWith(Channel, StringComparison.OrdinalIgnoreCase))
                {
                    if (discordLoginVisible)
                    {
                        RestoreGameChatAfterSignIn();
                        if (channelReloadAfterSignInPending)
                        {
                            // Initial OAuth/login route can expose a partial
                            // Discord channel DOM. One authenticated reload
                            // completes the SPA handoff without relaunching
                            // TES3NP or discarding its WebView2 session.
                            channelReloadAfterSignInPending = false;
                            Log("CHAT | First sign-in complete; reloading channel once to finish feed initialization");
                            web.CoreWebView2.Reload();
                            return;
                        }
                    }
                    if (!discordChannelReady) {
                        discordChannelReady = true;
                        Log("CHAT | Authenticated Discord Game Chat ready; " +
                            "starting live history discovery");
                        BeginHappyHourDiscovery();
                    }
                    CompletePendingExpansionPrompt();
                    return;
                }
                if (state == "\"login\"") {
                    SuspendHappyHourUntilDiscordReturns("Discord login form");
                    ShowDiscordSignIn();
                    return;
                }
                if (state == "\"app-prompt\"") {
                    SuspendHappyHourUntilDiscordReturns("Discord desktop-app prompt");
                    ShowDiscordSignIn();
                    Log("Discord desktop-app prompt detected; navigating to browser sign-in");
                    web.CoreWebView2.Navigate("https://discord.com/login");
                    return;
                }
                if (discordChannelReady &&
                    !url.StartsWith(Channel, StringComparison.OrdinalIgnoreCase))
                    SuspendHappyHourUntilDiscordReturns("navigated away from Game Chat");
                // After authentication Discord may land on its home page,
                // not the server channel. Redirect once to the configured feed.
                if (discordLoginVisible &&
                    url.StartsWith("https://discord.com/channels/", StringComparison.OrdinalIgnoreCase) &&
                    !url.StartsWith(Channel, StringComparison.OrdinalIgnoreCase) &&
                    state != "\"loading\"")
                {
                    Log("Discord signed in; opening Game Chat channel");
                    web.CoreWebView2.Navigate(Channel);
                }
            }
            catch (Exception ex) { Log("Discord auth check: " + ex.GetType().Name); }
        }
        // Keep Discord's own inputs and authentication handlers intact.
        async Task StyleDiscordLogin()
        {
            if (web.CoreWebView2 == null || closingChat) return;
            try
            {
                // The release includes this image beside the published Chat Host.
                // Reuse its data URL across 500ms login checks, and inject once
                // per document; Discord's SPA can replace the form at any time.
                string logoFile = Path.Combine(AppContext.BaseDirectory, "assets", "DiscordInt.png");
                if (File.Exists(logoFile))
                {
                    discordIntegrationLogoDataUrl ??= "data:image/png;base64," +
                        Convert.ToBase64String(File.ReadAllBytes(logoFile));
                    if (await web.CoreWebView2.ExecuteScriptAsync(
                        "Boolean(window.__tes3npIntegrationLogo)") != "true")
                    {
                        await web.CoreWebView2.ExecuteScriptAsync(
                            "window.__tes3npIntegrationLogo = " +
                            System.Text.Json.JsonSerializer.Serialize(discordIntegrationLogoDataUrl) + ";");
                    }
                }
                await web.CoreWebView2.ExecuteScriptAsync("""
                    (() => {
                      if (location.pathname !== '/login') return;
                      const password = document.querySelector('input[type=password]');
                      const form = password?.closest('form');
                      if (!form) return;
                      const firstPresentation = !form.hasAttribute('data-tes3np-login');
                      form.setAttribute('data-tes3np-login', '');
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
                        benefit.textContent = "The feature you're trying to access requires Discord integration to function. Connecting to Discord unlocks realtime in-game chat, offline happy hour notifications, automatic expansion pack installation, and more!";
                      }
                      const title = form.querySelector('[data-tes3np-login-heading]');
                      if (title) {
                        title.textContent = 'Discord Integration!';
                        title.insertAdjacentElement('afterend', benefit);
                      }
                      benefit.textContent = "The feature you're trying to access requires Discord integration to function. Connecting to Discord unlocks realtime in-game chat, offline happy hour notifications, automatic expansion pack installation, and more!";
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
                        html,body,#app-mount { background:#090807 !important; }
                        html,body { margin:0 !important; padding:0 !important;
                          overflow:hidden !important; height:100% !important; }
                        #app-mount { overflow:hidden !important; height:100% !important; }
                        [data-tes3np-login] > * { margin-top:0 !important; margin-bottom:0 !important; }
                        [data-tes3np-login] div:empty { display:none !important; }
                        [data-tes3np-login] {
                          position:fixed !important; top:10px !important;
                          left:0 !important; right:0 !important;
                          width:100% !important; max-width:none !important;
                          margin:0 !important; padding:6px 12px 20px !important;
                          max-height:calc(100vh - 16px) !important;
                          overflow-y:auto !important; overflow-x:hidden !important;
                          scrollbar-width:none !important;
                          background:#090807 !important; border:0 !important;
                          box-shadow:none !important; z-index:1000 !important;
                          display:flex !important; flex-direction:column !important;
                          gap:2px !important; box-sizing:border-box !important;
                          font-family:Georgia,'Times New Roman',serif !important;
                        }
                        [data-tes3np-login] * { box-sizing:border-box !important; }
                        [data-tes3np-integration-logo] {
                          display:block !important; width:175px !important;
                          height:135px !important; object-fit:contain !important;
                          margin:8px auto 4px !important; padding:0 !important;
                        }
                        [data-tes3np-login-benefit] {
                          display:block !important;
                          margin:3px 4px 8px !important;
                          padding:5px 4px 0 !important;
                          border-top:none !important;
                          color:#ddc99d !important;
                          font:13px/1.4 Georgia,'Times New Roman',serif !important;
                          text-align:center !important;
                          white-space:normal !important;
                        }
                        [data-tes3np-login]::-webkit-scrollbar { display:none !important; }
                        [data-tes3np-login] > div { min-height:0 !important; }
                        [data-tes3np-login] > div:empty { display:none !important; }
                        [data-tes3np-login] [class*="marginBottom"],
                        [data-tes3np-login] [class*="marginTop"] {
                          margin-top:0 !important; margin-bottom:0 !important;
                        }
                        [data-tes3np-login-heading] {
                          text-align:center !important; color:#d9b469 !important;
                          font:20px Georgia,serif !important;
                          padding:8px 0 7px !important; margin:0 0 4px !important;
                          border:0 !important; box-shadow:none !important;
                          text-decoration:none !important;
                        }
                        [data-tes3np-login] label {
                          color:#ddc99d !important; font:15px Georgia,serif !important;
                          text-transform:none !important;
                        }
                        [data-tes3np-login] input {
                          background:#100d09 !important; color:#f3e6c5 !important;
                          border:1px solid #997644 !important; border-radius:0 !important;
                          min-height:34px !important; height:34px !important;
                          padding:5px 8px !important; width:100% !important;
                          font:16px Georgia,serif !important;
                        }
                        [data-tes3np-login] button[type=submit] {
                          background:#9b7439 !important; color:#fff0cb !important;
                          border:1px solid #dfbb75 !important; border-radius:0 !important;
                          min-height:35px !important; font:17px Georgia,serif !important;
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
                          font:16px/1.4 Georgia,'Times New Roman',serif !important;
                          text-align:center !important; cursor:pointer !important;
                        }
                        [data-tes3np-not-now]:hover {
                          background:#b33030 !important;
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
                    })()
                    """);
            }
            catch (Exception ex) { Log("Discord login theme: " + ex.GetType().Name); }
        }
        void ShowConnectingChat()
        {
            if (closingChat || IsDisposed || discordLoginVisible) return;
            connectingChat = true;
            nativeMode = false;
            // Make the loading state visible on the existing custom frame.
            // Do not display the old mock scrollbar while the real HTML feed
            // is still mounting after the Discord OAuth handoff.
            nativeMessages.Text = "Connecting to live chat...";
            frameSurface.Visible = true;
            messageClip.Visible = true;
            messageBrowser.Visible = false;
            nativeMessages.Visible = true;
            nativeMessages.BringToFront();
            goldScrollbar.Visible = false;
            chatViewport.Visible = false;
            FitWebView();
            messageClip.BringToFront();
            frameSurface.Invalidate();
            Log("CHAT | Waiting for authenticated message feed");
        }
        // Only the Game Chat-triggered sign-in follows the normal dock.
        // Expansion and all other authentication requests remain centered.
        void PositionGameChatDiscordSignIn()
        {
            if (!discordSignInRequested || pendingExpansionPrompt != 0 ||
                !IsWindow(owner) || discordSignInWindow is not { IsDisposed: false } popup ||
                !GetWindowRect(owner, out var bounds)) return;
            var work = Screen.FromHandle(owner).WorkingArea;
            int popupWidth = popup.Width, popupHeight = popup.Height;
            int normalChatWidth = Math.Min(chatWidth, work.Width);
            int leftX = bounds.Left - normalChatWidth;
            int rightX = bounds.Right;
            int x;
            if (leftX >= work.Left)
                x = bounds.Left - popupWidth;
            else if (rightX + normalChatWidth <= work.Right)
                x = rightX;
            else
                x = bounds.Left - work.Left >= work.Right - bounds.Right
                    ? bounds.Left - popupWidth : rightX;
            x = Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - popupWidth));
            int y = bounds.Top + (bounds.Bottom - bounds.Top - popupHeight) / 2;
            y = Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - popupHeight));
            var target = new System.Drawing.Point(x, y);
            if (popup.Location != target) popup.Location = target;
        }
        void DismissDiscordSignIn()
        {
            if (discordSignInWindow is { IsDisposed: false } popup)
                popup.Hide();
            discordSignInRequested = false;
            CancelPendingExpansionPrompt();
        }
        void ToggleGameChatDiscordSignIn()
        {
            // Game Chat toggles its own login; Expansion authentication remains
            // a distinct user flow with its own cancellation behavior.
            if (pendingExpansionPrompt == 0 &&
                discordSignInWindow is { IsDisposed: false, Visible: true })
            {
                DismissDiscordSignIn();
                return;
            }
            RevealDiscordSignInWindow();
        }
        void RevealDiscordSignInWindow()
        {
            discordSignInRequested = true;
            if (discordSignInWindow is not { IsDisposed: false } popup) return;
            PositionGameChatDiscordSignIn();
            if (!popup.Visible) popup.Show();
            if (web.CoreWebView2 != null)
                _ = web.CoreWebView2.ExecuteScriptAsync(
                    "(() => { const f = document.querySelector('[data-tes3np-login]'); " +
                    "if (f) f.scrollTop = 0; " +
                    "if (document.scrollingElement) document.scrollingElement.scrollTop = 0; })()");
            popup.BringToFront();
            popup.Activate();
        }
        void ShowDiscordSignIn()
        {
            // One browser, one Discord profile: move the existing WebView2 into
            // a clearly named native window, never create another login session.
            if (discordLoginVisible) return;
            connectingChat = false;
            channelReloadAfterSignInPending = true;
            showChatAfterDiscordSignIn = chatOpen || chatDisplayMode == "Always Shown" || freshDiscordProfile;
            discordLoginVisible = true;
            signInExpanded = false;
            nativeMode = false;
            nativeMessages.Visible = false;
            messageBrowser.Visible = false;
            messageClip.Visible = false;
            goldScrollbar.Visible = false;
            frameSurface.Visible = false;
            chatViewport.Visible = false;
            if (web.IsHandleCreated) SetWindowRgn(web.Handle, IntPtr.Zero, true);
            SetChatOpen(false);

            var area = Screen.FromHandle(owner).WorkingArea;
            int width = Math.Max(360, Math.Min(520, area.Width - 24));
            int height = Math.Max(440, Math.Min(750, area.Height - 24));
            var popup = new Form
            {
                Text = "tes3np - Sign In Required",
                // Titlebar-free, gold-bordered native card like the launcher
                // changelog panels. Keep explicit close controls below.
                FormBorderStyle = FormBorderStyle.None,
                Padding = new Padding(2),
                StartPosition = FormStartPosition.Manual,
                Location = new System.Drawing.Point(
                    area.Left + (area.Width - width) / 2,
                    area.Top + (area.Height - height) / 2),
                ClientSize = new System.Drawing.Size(width, height),
                BackColor = System.Drawing.Color.FromArgb(197, 164, 92),
                ForeColor = System.Drawing.Color.FromArgb(237, 225, 201),
                MaximizeBox = false,
                MinimizeBox = false,
                ShowInTaskbar = false
            };
            var shell = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3,
                Padding = new Padding(12),
                BackColor = System.Drawing.Color.FromArgb(27, 20, 11) };
            shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 45));
            shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 50));
            shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            var heading = new Label { Text = "Sign In Required", Dock = DockStyle.Fill,
                TextAlign = System.Drawing.ContentAlignment.MiddleCenter,
                ForeColor = System.Drawing.Color.FromArgb(226, 191, 119),
                Font = new System.Drawing.Font("Georgia", 16, System.Drawing.FontStyle.Bold) };
            var help = new Label { Text = "Connect your Discord account to access this feature.",
                Dock = DockStyle.Fill, TextAlign = System.Drawing.ContentAlignment.MiddleCenter,
                ForeColor = System.Drawing.Color.FromArgb(237, 225, 201) };
            var browserPanel = new Panel { Dock = DockStyle.Fill, BackColor = System.Drawing.Color.Black };
            popup.FormClosing += (_, e) => {
                if (!closingChat) {
                    e.Cancel = true;
                    DismissDiscordSignIn();
                }
            };
            shell.Controls.Add(heading, 0, 0);
            shell.Controls.Add(help, 0, 1);
            shell.Controls.Add(browserPanel, 0, 2);
            popup.Controls.Add(shell);
            // Without a Windows caption there must still be an obvious,
            // accessible way to close the sign-in before authenticating.
            // The Game Chat tab and in-page Not Now control remain alternatives.
            var closeButton = new Button {
                Text = "×",
                Location = new System.Drawing.Point(width - 39, 6),
                Size = new System.Drawing.Size(29, 29),
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                FlatStyle = FlatStyle.Flat,
                BackColor = System.Drawing.Color.FromArgb(27, 20, 11),
                ForeColor = System.Drawing.Color.FromArgb(226, 191, 119),
                Font = new System.Drawing.Font("Segoe UI", 14, System.Drawing.FontStyle.Bold),
                Cursor = Cursors.Hand,
                TabStop = false
            };
            closeButton.FlatAppearance.BorderSize = 0;
            closeButton.Click += (_, _) => DismissDiscordSignIn();
            popup.Controls.Add(closeButton);
            closeButton.BringToFront();
            discordSignInWindow = popup;
            PositionGameChatDiscordSignIn();
            web.Dock = DockStyle.Fill;
            web.Parent = browserPanel;
            web.Visible = true;
            // Keep the authentication WebView2 alive for background channel /
            // Happy Hour discovery without interrupting a clean first launch.
            // The same popup becomes visible on a user-initiated action.
            if (discordSignInRequested) popup.Show();
            SetNativeWindowOwner(popup.Handle, owner);
            Log(discordSignInRequested
                ? "Discord login: user-requested sign-in window opened"
                : "Discord login: ready but deferred until requested");
        }
        void RestoreGameChatAfterSignIn()
        {
            if (!discordLoginVisible) return;
            Log("Discord chat detected: restoring custom Game Chat");
            // DockToLauncher() reapplies the saved display mode and normally
            // hides Automatic chat; preserve the panel the user opened to
            // complete this sign-in instead of making it disappear.
            bool keepChatVisible = discordSignInRequested && showChatAfterDiscordSignIn &&
                chatDisplayMode != "Always Hidden";
            discordSignInRequested = false;
            discordLoginVisible = false;
            signInExpanded = false;
            web.Dock = DockStyle.None;
            web.Parent = chatViewport;
            if (discordSignInWindow is { IsDisposed: false } popup)
            {
                popup.Hide();
                discordSignInWindow = null;
                popup.Dispose();
            }
            // Keep the panel open with a fresh "Connecting..." state while
            // Discord finishes its one authenticated channel reload.
            ShowConnectingChat();
            Text = "tes3np Chat Host";
            DockToLauncher();
            if (keepChatVisible) {
                lastChatActivity = DateTime.Now;
                SetChatOpen(true);
            }
            PositionChatWindows();
            // The post-auth channel reload is performed by
            // CheckDiscordAuthentication exactly once. Its normal polling
            // path will populate the now-initialized native renderer.
        }
        async Task UpdateViewMode()
        {
            if (web.CoreWebView2 == null) return;
            var url = web.CoreWebView2.Source;
            Log("Navigation completed (Discord page changed).");
            bool login = url.StartsWith("https://discord.com/login", StringComparison.OrdinalIgnoreCase)
                || url.StartsWith("https://discord.com/register", StringComparison.OrdinalIgnoreCase);
            await CheckDiscordAuthentication();
            if (discordLoginVisible) return;
            EnforceChatClip();
            await ApplyCss();
            await RefreshNativeMessages();
        }
        // Launcher command 12 retries a pending authenticated Expansion
        // request; a lost launcher acknowledgement cannot strand the menu.
        void RetryAuthenticatedExpansionPrompt(int mode)
        {
            if ((mode != 1 && mode != 2) || closingChat || !IsWindow(owner)) return;
            if (pendingExpansionPrompt == 0)
            {
                RequestAuthenticatedExpansionPrompt(mode);
                return;
            }
            if (discordLoginVisible) RevealDiscordSignInWindow();
            _ = ResolvePendingExpansionPromptAsync();
        }

        // Launcher command 10 requests an Expansion Pack download dialog.
        // Only confirmed Game Chat channel authentication allows the dialog.
        // Signed-out users see the already-established branded login screen.
        void RequestAuthenticatedExpansionPrompt(int mode)
        {
            if ((mode != 1 && mode != 2) || closingChat || !IsWindow(owner)) return;
            if (pendingExpansionPrompt != 0) return;
            pendingExpansionPrompt = mode;
            restoreChatAfterExpansionPrompt = !chatOpen;
            // Keep the existing centered behavior for Expansion Pack auth
            // even if Game Chat previously positioned this reusable popup.
            if (discordSignInWindow is { IsDisposed: false } popup)
            {
                var area = Screen.FromHandle(owner).WorkingArea;
                popup.Location = new System.Drawing.Point(
                    area.Left + (area.Width - popup.Width) / 2,
                    area.Top + (area.Height - popup.Height) / 2);
            }
            if (!discordChannelReady) discordSignInRequested = true;
            if (discordLoginVisible) RevealDiscordSignInWindow();
            // The previous channelReady flag may be stale after a sign-out.
            // Independently probe the live Discord DOM before revealing any
            // Discord-backed popup, even for previously signed-in users.
            _ = ResolvePendingExpansionPromptAsync();
        }
        async Task ResolvePendingExpansionPromptAsync()
        {
            if (pendingExpansionPrompt == 0 || closingChat || IsDisposed) return;
            if (discordChannelReady && !discordLoginVisible && web.CoreWebView2 != null)
            {
                var core = web.CoreWebView2;
                try
                {
                    string before = core.Source ?? "";
                    if (string.Equals(before.TrimEnd('/'), Channel,
                        StringComparison.OrdinalIgnoreCase))
                    {
                        string live = await core.ExecuteScriptAsync(
                            "(() => !!document.querySelector('[data-list-id=chat-messages]'))()");
                        if (pendingExpansionPrompt == 0 || closingChat || IsDisposed) return;
                        if (live == "true" &&
                            string.Equals(core.Source, before, StringComparison.OrdinalIgnoreCase))
                        {
                            CompletePendingExpansionPrompt();
                            return;
                        }
                    }
                }
                catch (Exception ex)
                {
                    Log("EXPANSION | Live Discord authorization check: " + ex.GetType().Name);
                }
                // Never trust a ready flag if the live channel DOM disappeared.
                SuspendHappyHourUntilDiscordReturns("live expansion authentication check");
            }
            if (pendingExpansionPrompt == 0 || closingChat || IsDisposed) return;
            lastChatActivity = DateTime.Now;
            SetChatOpen(true);
            Log("EXPANSION | Waiting for existing Discord Game Chat authentication.");
            // Normal navigation/polling reveals the established branded
            // Discord login; do not reset the profile or open a new browser.
        }
        void CancelPendingExpansionPrompt(bool notifyLauncher = true)
        {
            if (pendingExpansionPrompt == 0) return;
            pendingExpansionPrompt = 0;
            restoreChatAfterExpansionPrompt = false;
            // A launcher-initiated close already cleared its own pending state.
            // Don't send a stale zero acknowledgement into a rapidly reopened
            // dialog; user-initiated login cancellation still informs launcher.
            if (notifyLauncher && IsWindow(owner))
                PostMessage(owner, 0x8336, IntPtr.Zero, Handle);
        }
        void CompletePendingExpansionPrompt()
        {
            if (pendingExpansionPrompt == 0 || !discordChannelReady ||
                discordLoginVisible || closingChat || !IsWindow(owner)) return;
            int mode = pendingExpansionPrompt;
            pendingExpansionPrompt = 0;
            PostMessage(owner, 0x8336, new IntPtr(mode), Handle);
            if (restoreChatAfterExpansionPrompt && chatDisplayMode != "Always Shown")
                SetChatOpen(false);
            restoreChatAfterExpansionPrompt = false;
            Log("EXPANSION | Authenticated download prompt approved.");
        }
        // Launcher-owned toggle commands (WM_APP + 0x331).
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x8331)
            {
                switch (m.WParam.ToInt64())
                {
                    case 1:
                        // An early manual click before WebView2 completes startup
                        // must still reveal login when the browser becomes ready.
                        if (!discordChannelReady) discordSignInRequested = true;
                        if (discordLoginVisible)
                        {
                            ToggleGameChatDiscordSignIn();
                            break;
                        }
                        if (chatOpen && pendingExpansionPrompt != 0)
                        {
                            CancelPendingExpansionPrompt();
                            Log("EXPANSION | Pending download cancelled using Game Chat tab.");
                        }
                        SetChatOpen(!chatOpen);
                        if (chatDisplayMode == "Automatic" && chatOpen) lastChatActivity = DateTime.Now;
                        break;
                    case 2: SetChatDisplayMode("Automatic"); break;
                    case 3: SetChatDisplayMode("Always Shown"); break;
                    case 4: SetChatDisplayMode("Always Hidden"); break;
                    case 6: ShowEmbeddedExpansionDownloads(m.LParam); break;
                    case 7: CloseEmbeddedExpansionDownloads(m.LParam); break;
                    case 9: HideEmbeddedExpansionDownloads(m.LParam); break;
                    case 10: RequestAuthenticatedExpansionPrompt((int)m.LParam.ToInt64()); break;
                    case 11: CancelPendingExpansionPrompt(false); break;
                    case 12: RetryAuthenticatedExpansionPrompt((int)m.LParam.ToInt64()); break;
                    case 13: StartExpansionAutoDownload(m.LParam); break;
                }
                return;
            }
            base.WndProc(ref m);
        }
        void SetChatDisplayMode(string mode)
        {
            if (mode == "Always Hidden") CancelPendingExpansionPrompt();
            chatDisplayMode = mode;
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(chatModeFile)!);
                File.WriteAllText(chatModeFile, mode);
            }
            catch { }
            SetChatOpen(mode == "Always Shown");
        }
        // WM_APP + 0x334: Jiub follows the genuine Discord-backed banner.
        void NotifyLauncherHappyHourFace(bool active)
        {
            if (IsWindow(owner))
                PostMessage(owner, 0x8334, active ? new IntPtr(1) : IntPtr.Zero, IntPtr.Zero);
        }
        // WM_APP + 0x332 tells the launcher the authoritative chat visibility.
        void NotifyLauncherChatState()
        {
            if (IsWindow(owner))
                PostMessage(owner, 0x8332, chatOpen ? new IntPtr(1) : IntPtr.Zero, IntPtr.Zero);
        }
        void SetChatOpen(bool show)
        {
            if (discordLoginVisible)
            {
                // Never display a stretched/empty chat pane behind login.
                chatOpen = false;
                if (IsHandleCreated) ShowWindow(Handle, 0);
                NotifyLauncherChatState();
                return;
            }
            chatOpen = show;
            if (!signInExpanded && IsHandleCreated)
            {
                // SW_SHOW (5) activates this owned popup and steals foreground
                // focus from parchment menus and native dialogs. Automatic
                // message notifications must only reveal chat, never activate it.
                if (show) ShowWindow(Handle, 4); // SW_SHOWNOACTIVATE
                else ShowWindow(Handle, 0);
            }
            PositionChatWindows();
            NotifyLauncherChatState();
        }
        void PositionChatWindows()
        {
            // The existing chat polling is a safety net for missed native
            // movement events, regardless of whether the hook installed.
            // The native helper is a no-op if the banner is already aligned.
            PositionHappyHourBanner();
            if (discordLoginVisible && discordSignInRequested && pendingExpansionPrompt == 0)
                PositionGameChatDiscordSignIn();
            if (!IsWindow(owner) || signInExpanded || !GetWindowRect(owner, out var bounds)) return;
            // Discord authentication has its own window; the docked Game Chat
            // always retains its normal height, even when signed out.
            int windowHeight = chatHeight;
            var work = Screen.FromHandle(owner).WorkingArea;
            windowHeight = Math.Min(windowHeight, work.Height);
            int y = bounds.Top + (bounds.Bottom - bounds.Top - windowHeight) / 2;
            y = Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - windowHeight));
            // The approved dock is to the left of TES3NP when space permits.
            // If the launcher is near a monitor edge, the old negative X
            // left Game Chat clipped/offscreen. Choose the right when it fits,
            // otherwise clamp the complete panel to the monitor working area.
            int panelWidth = Math.Min(chatWidth, work.Width);
            int leftX = bounds.Left - panelWidth;
            int rightX = bounds.Right;
            int x;
            if (leftX >= work.Left)
                x = leftX;
            else if (rightX + panelWidth <= work.Right)
                x = rightX;
            else
            {
                // A maximized or very wide launcher leaves no full-width
                // outside dock: favor the side with more visible space.
                int leftSpace = Math.Max(0, bounds.Left - work.Left);
                int rightSpace = Math.Max(0, work.Right - bounds.Right);
                x = leftSpace >= rightSpace ? work.Left : work.Right - panelWidth;
            }
            x = Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - panelWidth));
            if (chatOpen)
                MoveWindow(Handle, x, y, panelWidth, windowHeight, true);
        }
        void DockToLauncher()
        {
            if (!IsWindow(owner) || signInExpanded) return;
            var dockClock = System.Diagnostics.Stopwatch.StartNew();
            Log("STARTUP | Dock begin");
            var hwnd = Handle;
            SetParent(hwnd, IntPtr.Zero);
            Log("STARTUP | SetParent completed in " + dockClock.ElapsedMilliseconds + "ms");
            int style = GetWindowLong(hwnd, GWL_STYLE);
            SetWindowLong(hwnd, GWL_STYLE, (style | WS_POPUP) & ~WS_CHILD);
            ShowInTaskbar = false;
            // Native owner relationship keeps the chat above the launcher and
            // prevents it from becoming an independent Alt+Tab application.
            Log("STARTUP | Setting native owner");
            SetNativeWindowOwner(hwnd, owner);
            Log("STARTUP | Native owner set in " + dockClock.ElapsedMilliseconds + "ms");
            int chatExStyle = GetWindowLongEx(hwnd, GWL_EXSTYLE);
            SetWindowLongEx(hwnd, GWL_EXSTYLE,
                (chatExStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
            ApplyWindowOpacity();
            docked = true;
            WatchLauncherMovement();
            Log("STARTUP | Movement hook ready in " + dockClock.ElapsedMilliseconds + "ms");
            PositionChatWindows();
            SetChatOpen(chatDisplayMode == "Always Shown");
            // The owner, layout and saved visibility are now authoritative.
            // A first-run Automatic/Hidden panel is already SW_HIDE; an
            // Always Shown panel is now correctly docked before its first paint.
            if (startupPresentationPending)
            {
                startupPresentationPending = false;
                SetStartupWindowCloak(false);
            }
            Log("STARTUP | Chat position and visibility ready in " + dockClock.ElapsedMilliseconds + "ms");
            // Actual launcher movement repairs the missing frame pixels on layered AHK windows.
            // Reproduce that exact compositor event once, then restore its original position.
            if (GetWindowRect(owner, out var bounds))
            {
                const uint SWP_NOSIZE_NOZORDER_NOACTIVATE = 0x0001 | 0x0004 | 0x0010;
                Log("STARTUP | Owner compositor refresh begin");
                SetWindowPos(owner, IntPtr.Zero, bounds.Left + 1, bounds.Top, 0, 0, SWP_NOSIZE_NOZORDER_NOACTIVATE);
                Log("STARTUP | Owner compositor refresh first step in " + dockClock.ElapsedMilliseconds + "ms");
                SetWindowPos(owner, IntPtr.Zero, bounds.Left, bounds.Top, 0, 0, SWP_NOSIZE_NOZORDER_NOACTIVATE);
                Log("STARTUP | Owner compositor refresh completed in " + dockClock.ElapsedMilliseconds + "ms");
            }
            Log($"Docked {chatX},{chatY} {chatWidth}x{chatHeight}");
        }
    }
}
