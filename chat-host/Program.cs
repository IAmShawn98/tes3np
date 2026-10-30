using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;

internal static class Program
{
    const string ChatBuild = "chat-inset-native-frame-20261008";
    const string Channel = "https://discord.com/channels/509601787901116437/1384271857842130994";
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)]
    struct SCROLLINFO { public uint cbSize, fMask; public int nMin, nMax; public uint nPage; public int nPos, nTrackPos; }
    [DllImport("user32.dll")] static extern bool GetScrollInfo(IntPtr hwnd, int bar, ref SCROLLINFO info);
    [DllImport("user32.dll")] static extern bool ShowScrollBar(IntPtr hwnd, int bar, bool show);
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
    [DllImport("user32.dll", EntryPoint = "PostMessageW")] static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);
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
    void HideNativeChatScrollbar() { /* No native scrollbar is created. */ }


        readonly IntPtr owner;
        readonly WebView2 web = new() { Dock = DockStyle.None };
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
let lastState='';
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
                    catch (Exception ex) { Log("HTML scroll telemetry error: " + ex.Message); }
                };
                messageBrowser.NavigationCompleted += (_, _) => { messageBrowserReady = true; Log("HTML message renderer ready"); };
                Log("HTML message renderer navigating");
                messageBrowser.NavigateToString(MessagePage);
            }
            catch (Exception ex) { Log("HTML renderer initialization failed: " + ex.Message); }
        }
        void ScrollHtml(int pixels)
        {
            if (messageBrowserReady && messageBrowser.CoreWebView2 != null)
                _ = messageBrowser.CoreWebView2.ExecuteScriptAsync("window.scrollChat(" + pixels + ")");
        }
        string lastFeed = "";
        readonly System.Collections.Generic.List<(string User, string Body)> renderedMessages = new();
        bool nativeMode;
        bool freshDiscordProfile;
        bool discordLoginVisible;
        const string ExtractFeed = """
            (() => {
              const list = document.querySelector('[data-list-id="chat-messages"]');
              if (!list) return '[]';
              const rows = [...list.querySelectorAll('[id^="chat-messages-"]')]
                .filter(el => /^chat-messages-[0-9]+-[0-9]+$/.test(el.id));
              return JSON.stringify(rows.map(el => {
                const usernameEl = el.querySelector('[class*="username_"]');
                const user = usernameEl?.textContent?.trim() || '';
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
                return {id:el.id,user,body,matchText,color,images:[...uniqueImages.values()].slice(0,4)};
              }).filter(x => x.body || x.images.length));
            })();
            """;
        readonly System.Collections.Generic.SortedDictionary<ulong, (string User, string Body, string Color, string[] Images)> history = new();
        // Discord snowflakes encode their original creation time in UTC.
        static DateTimeOffset DiscordTimestamp(ulong id) =>
            DateTimeOffset.FromUnixTimeMilliseconds((long)(id >> 22) + 1420070400000L);
        readonly System.Collections.Generic.SortedDictionary<ulong, (string User, string Body)> archivedChat = new();
        readonly string gameChatLogDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TES3NP", "Logs");
        string GameChatLogFile => Path.Combine(gameChatLogDirectory, "game-chat.log");
        string GameChatIndexFile => Path.Combine(gameChatLogDirectory, "game-chat-index.json");
        bool chatLogLoaded;
        void EnsureChatLogLoaded()
        {
            if (chatLogLoaded) return;
            Directory.CreateDirectory(gameChatLogDirectory);
            if (File.Exists(GameChatIndexFile))
            {
                var records = System.Text.Json.JsonSerializer.Deserialize<System.Collections.Generic.List<ChatArchiveEntry>>(
                    File.ReadAllText(GameChatIndexFile)) ?? new();
                foreach (var entry in records)
                    archivedChat[entry.Id] = (entry.User ?? "", entry.Body ?? "");
            }
            else if (File.Exists(GameChatLogFile))
            {
                // One-time migration of the previous plain-text log format.
                foreach (string line in File.ReadLines(GameChatLogFile))
                {
                    var match = System.Text.RegularExpressions.Regex.Match(line,
                        @"^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] (.*?) \[discord:(\d+)\]$");
                    if (!match.Success || !ulong.TryParse(match.Groups[2].Value, out ulong id)) continue;
                    string content = match.Groups[1].Value;
                    int split = content.IndexOf(": ", StringComparison.Ordinal);
                    archivedChat[id] = split >= 0
                        ? (content.Substring(0, split), content.Substring(split + 2))
                        : ("", content);
                }
                if (archivedChat.Count > 0) SaveChatArchive();
            }
            chatLogLoaded = true;
        }
        public sealed class ChatArchiveEntry
        {
            public ulong Id { get; set; }
            public string User { get; set; } = "";
            public string Body { get; set; } = "";
        }
        void SaveChatArchive()
        {
            var records = archivedChat.Select(e => new ChatArchiveEntry {
                Id = e.Key, User = e.Value.User, Body = e.Value.Body
            }).ToArray();
            File.WriteAllText(GameChatIndexFile, System.Text.Json.JsonSerializer.Serialize(records));
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
                output.AppendLine($"[{sent:hh:mm:ss tt}] {user}: {body}");
            }
            File.WriteAllText(GameChatLogFile, output.ToString());
        }
        void LogChatMessage(ulong id, string user, string body)
        {
            if (string.IsNullOrWhiteSpace(body)) return;
            try
            {
                EnsureChatLogLoaded();
                if (archivedChat.ContainsKey(id)) return;
                archivedChat[id] = (user, body);
                SaveChatArchive();
            }
            catch (Exception ex) { Log("Game chat log write failed: " + ex.Message); }
        }

        readonly System.Collections.Generic.Dictionary<string, System.Drawing.Image> imageCache = new();
        readonly System.Collections.Generic.HashSet<string> pendingImages = new();
        readonly System.Collections.Generic.Dictionary<string, DateTime> failedImages = new();
        static readonly System.Net.Http.HttpClient imageHttp = new() { Timeout = TimeSpan.FromSeconds(12) };
        bool imagesNeedRedraw;
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
                Log("Chat image decoded: " + original.Width + "x" + original.Height +
                    " (" + (response.Content.Headers.ContentType?.MediaType ?? "unknown type") + ")");
                imagesNeedRedraw = true;
            }
            catch (Exception ex)
            {
                Log("Chat image unavailable (" + (Uri.TryCreate(url, UriKind.Absolute, out var failedUri)
                    ? failedUri.Host : "invalid URL") + "): " + ex.Message);
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
        void AppendChatImage(System.Drawing.Image image)
        {
            nativeMessages.SelectionStart = nativeMessages.TextLength;
            nativeMessages.SelectionLength = 0;

            // Prefer native RichEdit OLE image insertion via Paste rather than PNG RTF.
            // Some Windows RichEdit versions silently discard \\pict\\pngblip runs.
            // Preserve the user's clipboard, including non-text formats.
            System.Windows.Forms.IDataObject? previousClipboard = null;
            bool clipboardCaptured = false;
            try
            {
                try
                {
                    previousClipboard = System.Windows.Forms.Clipboard.GetDataObject();
                    clipboardCaptured = true;
                }
                catch (Exception ex)
                {
                    Log("Chat image clipboard snapshot unavailable: " + ex.Message);
                    throw;
                }

                using var bitmap = new System.Drawing.Bitmap(image);
                System.Windows.Forms.Clipboard.SetImage(bitmap);
                // Let RichEdit choose the best clipboard format. Explicitly forcing CF_BITMAP
                // can fail even when its OLE paste path supports the bitmap.
                int beforeLength = (nativeMessages.Rtf ?? string.Empty).Length;
                nativeMessages.Paste();
                string resultingRtf = nativeMessages.Rtf ?? string.Empty;
                bool hasPicture = resultingRtf.Contains(@"\\pict", StringComparison.OrdinalIgnoreCase) ||
                                  resultingRtf.Contains(@"\\object", StringComparison.OrdinalIgnoreCase);
                if (!hasPicture)
                    throw new InvalidOperationException("RichEdit paste produced no picture/object (RTF length " +
                        beforeLength + " -> " + resultingRtf.Length + ")");
                Log("Chat image pasted: " + image.Width + "x" + image.Height);
            }
            finally
            {
                if (clipboardCaptured)
                {
                    try
                    {
                        if (previousClipboard != null)
                            System.Windows.Forms.Clipboard.SetDataObject(previousClipboard, true);
                        else
                            System.Windows.Forms.Clipboard.Clear();
                    }
                    catch (Exception ex) { Log("Chat image clipboard restore error: " + ex.Message); }
                }
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
                    initialBackfillReanchored = true;
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
            catch (Exception ex) { Log("History load error: " + ex.Message); }
            finally { loadingHistory = false; }
        }
        DateTime lastHistoryGateLog = DateTime.MinValue;
        bool userScrolledChat;
        bool historyCatchupActive;
        // Scan Discord backwards from its newest message until the most recent
        // genuine Happy Hour is confirmed. A previously saved hit is only a
        // candidate until live pagination has reached its timestamp.
        // Production only needs to search the past hour for an active event.
        readonly DateTimeOffset activeHappyHourCutoff = DateTimeOffset.UtcNow.AddHours(-1);
        DateTime initialBackfillStarted = DateTime.MinValue;
        int initialBackfillAttempts;
        bool initialBackfillComplete;
        bool initialBackfillReanchored;
        // Restoring Discord's hidden source from historical paging can load
        // previously unseen (but old) rows. Do not turn them into chat alerts.
        bool waitingForLiveFeedAfterHistory;
        string lastRestoredFeed = "";
        int restoredFeedStableTicks;
        void BackfillUntilHappyHour()
        {
            if (initialBackfillComplete || !nativeMode || signInExpanded ||
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
            // In production, expired events are irrelevant. One hour of
            // coverage rules out a currently active event without scanning
            // days of Discord messages.
            bool pastActiveWindow = !PreviewExpiredHappyHourForTesting &&
                oldestLoaded <= activeHappyHourCutoff;
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
        // Discord IDs contain the real UTC send time, so late-loaded messages
        // display only their remaining time rather than restarting a full hour.
        // TEMPORARY QA MODE: preview the latest real announcement even after expiry.
        // Turn this off before publishing a release.
        const bool PreviewExpiredHappyHourForTesting = true;
        ulong lastHappyHourAlertId;
        ulong dismissedHappyHourBannerId = ulong.MaxValue;
        bool happyHourDemo;

        [DllImport("user32.dll")] static extern IntPtr GetLastActivePopup(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr hwnd);

        bool OtherLauncherDialogOpen()
        {
            if (!IsWindow(owner) || !IsWindowEnabled(owner)) return true;
            // Update/status dialogs are owned by the main launcher. Win32
            // identifies the current active popup even when it is not modal.
            IntPtr active = GetLastActivePopup(owner);
            if (active == IntPtr.Zero || active == owner || active == Handle ||
                (happyHourBanner != null && active == happyHourBanner.Handle) ||
                (happyHourAlert != null && active == happyHourAlert.Handle))
                return false;
            return IsWindowVisible(active);
        }

        Form? happyHourAlert;
        Form? happyHourBanner;
        Label? happyHourBannerCountdown;
        System.Windows.Forms.Timer? happyHourTicker;
        DateTimeOffset happyHourEndsAt;
        readonly string happyHourSeenFile = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "tes3np", "happy-hour-last-seen.txt");

        // The no-announcement UI fallback has no Discord message ID. Remember it
        // separately so it does not interfere with real Happy Hour alerts.
        readonly string happyHourDemoSeenFile = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "tes3np", "happy-hour-demo-seen.txt");

        bool HasSeenHappyHourDemo()
        {
            try { return File.Exists(happyHourDemoSeenFile); }
            catch { return false; }
        }

        void MarkHappyHourDemoSeen()
        {
            try {
                Directory.CreateDirectory(Path.GetDirectoryName(happyHourDemoSeenFile)!);
                File.WriteAllText(happyHourDemoSeenFile, "1");
            } catch (Exception ex) { Log("Happy Hour UI test state not saved: " + ex.Message); }
        }

        ulong GetLastSeenHappyHour()
        {
            try {
                return ulong.TryParse(File.ReadAllText(happyHourSeenFile).Trim(), out var id) ? id : 0UL;
            } catch { return 0; }
        }

        void SaveLastSeenHappyHour(ulong id)
        {
            try {
                Directory.CreateDirectory(Path.GetDirectoryName(happyHourSeenFile)!);
                File.WriteAllText(happyHourSeenFile, id.ToString());
            } catch (Exception ex) { Log("Happy Hour alert state not saved: " + ex.Message); }
        }

        static Label GoldText(string text, int x, int y, int w, int h, float size, bool bold = false)
        {
            var label = new Label {
                Text = text,
                Font = new System.Drawing.Font("Georgia", size,
                    bold ? System.Drawing.FontStyle.Bold : System.Drawing.FontStyle.Regular),
                ForeColor = System.Drawing.Color.FromArgb(215, 170, 77),
                BackColor = System.Drawing.Color.Transparent,
                TextAlign = System.Drawing.ContentAlignment.MiddleCenter
            };
            label.SetBounds(x, y, w, h);
            return label;
        }

        static Button GoldButton(string text, int x, int y, int w, int h)
        {
            var button = new Button {
                Text = text, FlatStyle = FlatStyle.Flat,
                BackColor = System.Drawing.Color.FromArgb(112, 76, 39),
                ForeColor = System.Drawing.Color.FromArgb(255, 234, 188),
                Font = new System.Drawing.Font("Segoe UI", 10, System.Drawing.FontStyle.Bold)
            };
            button.FlatAppearance.BorderColor = System.Drawing.Color.FromArgb(197, 164, 92);
            button.SetBounds(x, y, w, h);
            return button;
        }

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

        // Use actual Discord snowflake time: reconnects and history never
        // restart a Happy Hour's 60-minute period.
        static string HappyHourRemaining(DateTimeOffset ends)
        {
            var remain = ends - DateTimeOffset.UtcNow;
            if (remain <= TimeSpan.Zero) return "0m 00s";
            int seconds = (int)Math.Ceiling(remain.TotalSeconds);
            return (seconds / 60).ToString() + "m " + (seconds % 60).ToString("00") + "s";
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

        void CloseHappyHourPopup()
        {
            if (happyHourAlert is { IsDisposed: false }) happyHourAlert.Close();
            happyHourAlert = null;
            // Dismissing the large popup leaves the smaller launcher alert.
            RefreshHappyHourBanner();
        }

        void RefreshHappyHourBanner()
        {
            if ((!PreviewExpiredHappyHourForTesting && happyHourEndsAt <= DateTimeOffset.UtcNow) ||
                dismissedHappyHourBannerId == lastHappyHourAlertId ||
                !IsWindow(owner))
            {
                if (happyHourBanner is { IsDisposed: false }) happyHourBanner.Close();
                happyHourBanner = null;
                return;
            }
            if (happyHourAlert is { IsDisposed: false } || OtherLauncherDialogOpen()) return;
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
                var dismiss = GoldButton("×", 10, 10, 26, 26);
                dismiss.Click += (_, _) => {
                    dismissedHappyHourBannerId = lastHappyHourAlertId;
                    banner.Close();
                };
                banner.Controls.Add(dismiss);
                // The black title plate hugs the actual content, not the window.
                var titleInset = new Panel {
                    BackColor = System.Drawing.Color.FromArgb(10, 9, 8)
                };
                titleInset.SetBounds(44, 7, Math.Min(805, Math.Max(210, banner.ClientSize.Width - 54)), 32);
                banner.Controls.Add(titleInset);
                var rainbow = new Panel {
                    BackColor = System.Drawing.Color.FromArgb(10, 9, 8)
                };
                rainbow.SetBounds(6, 0, 318, 32);
                titleInset.Controls.Add(rainbow);
                rainbow.Paint += (_, e) => {
                    // Historical HH previews use the same heading. The real
                    // Discord timestamp (not the heading) conveys expiry via 0m 00s.
                    string heading = happyHourDemo ? "HAPPY HOUR" : "HAPPY HOUR ACTIVE";
                    string[] colors = { "#FF0000", "#FF7F00", "#FFFF00", "#7FFF00",
                        "#00FF7F", "#00FFFF", "#007FFF", "#7F00FF", "#FF00FF", "#00FF00" };
                    using var font = new System.Drawing.Font("Georgia", 13,
                        System.Drawing.FontStyle.Bold);
                    var flags = System.Windows.Forms.TextFormatFlags.NoPadding |
                        System.Windows.Forms.TextFormatFlags.VerticalCenter |
                        System.Windows.Forms.TextFormatFlags.NoPrefix;
                    int[] widths = heading.Select(c => System.Windows.Forms.TextRenderer.MeasureText(
                        c.ToString(), font, new System.Drawing.Size(100, 32), flags).Width).ToArray();
                    float scale = Math.Min(1f, (rainbow.Width - 4f) / Math.Max(1, widths.Sum()));
                    int x = 0;
                    for (int i = 0; i < heading.Length; i++) {
                        int width = Math.Max(1, (int)Math.Round(widths[i] * scale));
                        System.Windows.Forms.TextRenderer.DrawText(e.Graphics,
                            heading[i].ToString(), font, new System.Drawing.Rectangle(x, 0, width + 1, 32),
                            System.Drawing.ColorTranslator.FromHtml(colors[i % colors.Length]), flags);
                        x += width;
                    }
                };
                // Give the three text regions their own measured breathing room:
                // rainbow title, full green bonus sentence, then countdown.
                var separator = GoldText("-", 325, 1, 18, 30, 12, true);
                separator.BackColor = System.Drawing.Color.FromArgb(10, 9, 8);
                titleInset.Controls.Add(separator);
                var activated = GoldText("", 343, 1, 296, 30, 12, true);
                activated.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
                activated.ForeColor = System.Drawing.Color.FromArgb(55, 216, 70);
                activated.BackColor = System.Drawing.Color.FromArgb(10, 9, 8);
                titleInset.Controls.Add(activated);
                var left = GoldText("", 639, 1, 158, 30, 11, true);
                left.TextAlign = System.Drawing.ContentAlignment.MiddleLeft;
                left.BackColor = System.Drawing.Color.FromArgb(10, 9, 8);
                titleInset.Controls.Add(left);
                happyHourBannerCountdown = left;
                banner.Resize += (_, _) => {
                    titleInset.Width = Math.Min(805, Math.Max(210, banner.ClientSize.Width - 54));
                    banner.Invalidate();
                };
                happyHourBanner = banner;
                banner.FormClosed += (_, _) => {
                    if (ReferenceEquals(happyHourBanner, banner)) happyHourBanner = null;
                };
                // Keep the card associated with the launcher, without making
                // it topmost over unrelated desktop applications.
                banner.Show();
                SetNativeWindowOwner(banner.Handle, owner);
            }
            if (happyHourBannerCountdown != null) {
                bool active = !happyHourDemo && happyHourEndsAt > DateTimeOffset.UtcNow;
                // The real Discord snowflake remains authoritative even in
                // development preview mode. Never invent remaining time.
                happyHourBannerCountdown.Text = happyHourDemo ? "" :
                    "(" + HappyHourRemaining(happyHourEndsAt) + " left)";
                foreach (Control control in happyHourBannerCountdown.Parent!.Controls) {
                    if (control is not Label bannerLabel ||
                        ReferenceEquals(bannerLabel, happyHourBannerCountdown)) continue;
                    if (bannerLabel.Text == "-")
                        bannerLabel.Visible = !happyHourDemo;
                    else
                        bannerLabel.Text = "Mastery Points Are Doubled!";
                }
                happyHourBannerCountdown.ForeColor = active
                    ? HappyHourTimerColor(happyHourEndsAt)
                    : System.Drawing.Color.FromArgb(215, 170, 77);
                // The inset width is calculated from the actual launcher width
                // by the resize handler, not truncated to a 640px title plate.
            }
            // Place the gold card directly above the actual launcher window.
            RECT rect;
            if (GetWindowRect(owner, out rect) && happyHourBanner is { IsDisposed: false })
            {
                bool visible = IsWindowVisible(owner) && !IsIconic(owner);
                if (visible) {
                    happyHourBanner.SetBounds(rect.Left, rect.Top - 48,
                        rect.Right - rect.Left, 46);
                    if (!happyHourBanner.Visible) happyHourBanner.Show();
                } else if (happyHourBanner.Visible) happyHourBanner.Hide();
            }
        }

        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);

        void ShowHappyHourAlert(ulong activationId, bool demo = false)
        {
            var ends = demo ? DateTimeOffset.UtcNow.AddMinutes(-1)
                : DiscordTimestamp(activationId).AddHours(1);
            if ((!demo && activationId <= lastHappyHourAlertId) ||
                (!demo && !PreviewExpiredHappyHourForTesting && ends <= DateTimeOffset.UtcNow)) return;
            bool expired = ends <= DateTimeOffset.UtcNow;
            // A competing launcher dialog takes precedence: skip the large
            // popup and show only the compact banner when it can be displayed.
            bool bannerOnly = OtherLauncherDialogOpen();
            lastHappyHourAlertId = activationId;
            happyHourDemo = demo;
            happyHourEndsAt = ends;
            if (PreviewExpiredHappyHourForTesting && expired)
                Log("HAPPY HOUR | Expired historical announcement; remaining time is 0m 00s (not active).");
            // Each new activation resets the banner, including after a restart.
            dismissedHappyHourBannerId = ulong.MaxValue;
            happyHourTicker?.Stop();
            happyHourTicker?.Dispose();
            happyHourAlert?.Close();
            happyHourBanner?.Close();
            happyHourAlert = null;
            happyHourBanner = null;

            // Remember this announcement across launches, including expired
            // announcements shown in development preview mode. The UI-only
            // fallback is tracked independently because its message ID is zero.
            bool previouslySeen = demo ? HasSeenHappyHourDemo()
                : activationId <= GetLastSeenHappyHour();
            if (!previouslySeen) {
                if (demo) MarkHappyHourDemoSeen();
                else SaveLastSeenHappyHour(activationId);
            }
            // Historical preview is for banner verification only. Do not
            // interrupt startup with an expired event's large activation popup.
            if (!previouslySeen && !bannerOnly && !expired)
            {
                var alert = GoldHappyHourWindow(480, 264, "tes3np - Happy Hour");
                alert.FormBorderStyle = FormBorderStyle.None;
                alert.BackColor = System.Drawing.Color.FromArgb(197, 164, 92);
                var content = new Panel { BackColor = System.Drawing.Color.FromArgb(23, 16, 8) };
                content.SetBounds(3, 3, 474, 258);
                alert.Controls.Add(content);
                // Use a single centered rainbow heading, with sufficient width
                // for every letter including the space (no FlowLayout wrapping).
                var heading = new Panel { BackColor = System.Drawing.Color.Transparent };
                heading.SetBounds(50, 22, 380, 46);
                content.Controls.Add(heading);
                string wording = "HAPPY HOUR";
                string[] colors = { "#FF0000", "#FF7F00", "#FFFF00", "#7FFF00",
                    "#00FF7F", "#00FFFF", "#007FFF", "#7F00FF", "#FF00FF", "#00FF00" };
                using (var font = new System.Drawing.Font("Georgia", 24,
                    System.Drawing.FontStyle.Bold))
                {
                    var widths = wording.Select(c => System.Windows.Forms.TextRenderer.MeasureText(
                        c.ToString(), font, new System.Drawing.Size(200, 60),
                        System.Windows.Forms.TextFormatFlags.NoPadding).Width).ToArray();
                    int headingWidth = widths.Sum();
                    int left = Math.Max(0, (heading.Width - headingWidth) / 2);
                    for (int i = 0; i < wording.Length; i++)
                    {
                        var letter = new Label {
                            Text = wording[i].ToString(), AutoSize = false,
                            Font = new System.Drawing.Font("Georgia", 24,
                                System.Drawing.FontStyle.Bold),
                            TextAlign = System.Drawing.ContentAlignment.MiddleCenter,
                            BackColor = System.Drawing.Color.Transparent,
                            ForeColor = System.Drawing.ColorTranslator.FromHtml(colors[i])
                        };
                        letter.SetBounds(left, 0, widths[i] + 1, 44);
                        heading.Controls.Add(letter);
                        left += widths[i];
                    }
                }
                var activation = GoldText("Happy hour has been activated!",
                    30, 73, 414, 34, 14, true);
                activation.ForeColor = System.Drawing.Color.FromArgb(55, 216, 70);
                content.Controls.Add(activation);
                var timerText = GoldText("", 30, 112, 414, 42, 21, true);
                timerText.ForeColor = HappyHourTimerColor(ends);
                content.Controls.Add(timerText);
                content.Controls.Add(GoldText("Mastery XP gain is currently doubled!",
                    20, 167, 434, 34, 13));
                var close = GoldButton("Close", 167, 213, 140, 32);
                content.Controls.Add(close);
                close.Click += (_, _) => CloseHappyHourPopup();
                alert.FormClosed += (_, _) => {
                    if (ReferenceEquals(happyHourAlert, alert)) {
                        happyHourAlert = null;
                        RefreshHappyHourBanner();
                    }
                };
                happyHourAlert = alert;
                timerText.Text = HappyHourRemaining(ends);
                alert.Show();
                SetNativeWindowOwner(alert.Handle, owner);
            }
            var ticker = new System.Windows.Forms.Timer { Interval = 1000 };
            ticker.Tick += (_, _) => {
                if (!PreviewExpiredHappyHourForTesting && happyHourEndsAt <= DateTimeOffset.UtcNow) {
                    ticker.Stop();
                    if (happyHourAlert is { IsDisposed: false }) happyHourAlert.Close();
                    if (happyHourBanner is { IsDisposed: false }) happyHourBanner.Close();
                    return;
                }
                if (happyHourAlert is { IsDisposed: false })
                    foreach (Control c in happyHourAlert.Controls)
                        foreach (Control inner in c.Controls)
                            if (inner is Label label && label.Font.Size >= 20 && label.Width >= 400) {
                                label.Text = HappyHourRemaining(happyHourEndsAt);
                                label.ForeColor = HappyHourTimerColor(happyHourEndsAt);
                            }
                RefreshHappyHourBanner();
            };
            happyHourTicker = ticker;
            ticker.Start();
            RefreshHappyHourBanner();
            Log("HAPPY HOUR | " + (demo ? "UI-only fallback" : previouslySeen ? "Previously seen" : "New activation") +
                " | " + DiscordTimestamp(activationId).ToString("O"));
        }

        // Check the persistent Discord chat archive as well as freshly loaded rows.
        // This allows an expired announcement to be previewed even if it is no
        // longer inside Discord's limited current viewport.
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
            // The newest matching *real* Discord message wins, whether its
            // one-hour activation window is still open or already expired.
            ulong latest = 0;
            foreach (var entry in archivedChat.Reverse()) {
                if (IsHappyHourAnnouncement(entry.Value.Body)) {
                    latest = entry.Key;
                    break;
                }
            }
            // The native chat can already display a message before its batch
            // is written to disk. Always inspect that same in-memory history.
            foreach (var entry in history.Reverse()) {
                if (entry.Key <= latest) break;
                if (IsHappyHourAnnouncement(entry.Value.Body)) {
                    latest = entry.Key;
                    break;
                }
            }
            return latest;
        }

        void DetectLatestHappyHour()
        {
            try
            {
                EnsureChatLogLoaded();
                ulong latest = LatestArchivedHappyHourId();
                if (latest > lastHappyHourAlertId) {
                    Log("HAPPY HOUR | Matched genuine Discord message " + latest +
                        " at " + DiscordTimestamp(latest).ToString("O") +
                        "; expired=" + (DiscordTimestamp(latest).AddHours(1) <= DateTimeOffset.UtcNow));
                    ShowHappyHourAlert(latest);
                }
                // No synthetic event: a missing archive hit simply keeps the
                // bounded historical loader searching in development mode.
            }
            catch (Exception ex) { Log("HAPPY HOUR | Scan failed: " + ex.Message); }
        }

        void BeginHappyHourDiscovery()
        {
            try
            {
                // FIRST inspect persistent logs, before paging Discord. The
                // indexed archive preserves exact message snowflakes; the
                // last-seen marker is only written after a genuine detection.
                EnsureChatLogLoaded();
                ulong archivedId = LatestArchivedHappyHourId();
                ulong previouslyVerifiedId = GetLastSeenHappyHour();
                ulong candidate = Math.Max(archivedId, previouslyVerifiedId);
                bool valid = candidate > 0 &&
                    (PreviewExpiredHappyHourForTesting ||
                     DiscordTimestamp(candidate).AddHours(1) > DateTimeOffset.UtcNow);
                if (valid)
                {
                    initialBackfillComplete = true;
                    Log("HAPPY HOUR | Startup cache shortcut: " +
                        (archivedId >= previouslyVerifiedId ? "chat archive" : "previous verified activation") +
                        "; messageId=" + candidate +
                        "; sent=" + DiscordTimestamp(candidate).ToString("O") +
                        "; archivedRows=" + archivedChat.Count +
                        "; skipping historical Discord pagination");
                    if (archivedId == candidate)
                        DetectLatestHappyHour();
                    else
                        ShowHappyHourAlert(candidate);
                }
                else
                {
                    Log("HAPPY HOUR | Startup cache has no qualifying real announcement; " +
                        "archivedRows=" + archivedChat.Count +
                        "; will page Discord when the source chat is ready");
                }
            }
            catch (Exception ex)
            {
                Log("HAPPY HOUR | Startup log check failed; will page Discord: " + ex.Message);
            }
        }

        async Task RefreshNativeMessages()
        {
            if (closingChat || IsDisposed || web.CoreWebView2 == null || discordLoginVisible) return;
            try
            {
                string raw = await web.CoreWebView2.ExecuteScriptAsync(ExtractFeed);
                if (closingChat || IsDisposed) return;
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
                    string body = msg.GetProperty("body").GetString() ?? "";
                    string matchText = msg.TryGetProperty("matchText", out var detectionText) &&
                        detectionText.ValueKind == System.Text.Json.JsonValueKind.String
                        ? detectionText.GetString() ?? "" : "";
                    bool isHappyHour = IsHappyHourAnnouncement(body) ||
                        IsHappyHourAnnouncement(matchText);
                    // Preserve the rendered chat wording unless only the
                    // Discord textContent contains the full styled announcement.
                    string archivalBody = isHappyHour && !IsHappyHourAnnouncement(body)
                        ? matchText : body;
                    string color = msg.TryGetProperty("color", out var cv) ? cv.GetString() ?? "";
                    string[] images = msg.TryGetProperty("images", out var imageValues) &&
                        imageValues.ValueKind == System.Text.Json.JsonValueKind.Array
                        ? imageValues.EnumerateArray().Select(x => x.GetString() ?? "").Where(x => x.Length > 0).ToArray()
                        : Array.Empty<string>();
                    // Collect from Discord itself, even on a fresh installation.
                    // Persist the whole extracted batch once, not the entire
                    // accumulated archive once per individual message.
                    if (!string.IsNullOrWhiteSpace(archivalBody) &&
                        (!archivedChat.TryGetValue(key, out var cached) ||
                         (isHappyHour && !IsHappyHourAnnouncement(cached.Body)))) {
                        // Repair previously indexed rows that missed styled
                        // announcement text as well as recording new messages.
                        archivedChat[key] = (user, archivalBody);
                        newlyArchived++;
                    }
                    foreach (string imageUrl in images)
                        if (!imageCache.ContainsKey(imageUrl) && (!failedImages.TryGetValue(imageUrl, out var retryTime) || DateTime.UtcNow >= retryTime)) _ = FetchChatImage(imageUrl);
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
                        Log("CHAT | Saved " + newlyArchived + " newly loaded Discord messages; " +
                            archivedChat.Count + " total, oldest=" +
                            DiscordTimestamp(archivedChat.First().Key).ToString("O"));
                    } catch (Exception ex) {
                        Log("CHAT | Could not persist newly loaded history: " + ex.Message);
                    }
                }
                // Match only genuine archived Discord messages; the snowflake
                // timestamp supplies the real one-hour remaining time.
                DetectLatestHappyHour();
                if (!changed && !redrawImages && nativeMode) return;
                bool prepended = history.Count > 0 && history.First().Key < previousFirst;
                if (!messageBrowserReady || messageBrowser.CoreWebView2 == null) return;
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
                goldScrollbar.Invalidate();
                if (!nativeMode)
                {
                    nativeMode = true;
                    web.Visible = false;
                    chatViewport.Visible = false;
                    nativeMessages.Visible = false;
                    messageBrowser.Visible = true;
                    messageBrowser.BringToFront();
                    messageClip.BringToFront();
                    goldScrollbar.BringToFront();
                    frameSurface.Visible = true;
                    frameSurface.Invalidate();
                    Log("Native message view activated");
                }
            }
            catch (Exception ex) { Log("Native feed error: " + ex.Message); }
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
                web.SetBounds(0, 0, ClientSize.Width, ClientSize.Height);
                web.BringToFront();
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
            chatViewport.Visible = !nativeMode;

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
        readonly string chatModeFile = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "tes3np", "chat-display-mode.txt");
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
                    closingChat || IsDisposed || !IsHandleCreated || repositionQueued) return;
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
        readonly string logPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "tes3np", "chat-host.log");
        void Log(string message) { try { Directory.CreateDirectory(Path.GetDirectoryName(logPath)!); File.AppendAllText(logPath, DateTime.Now.ToString("s") + " | " + ChatBuild + " | " + message + Environment.NewLine); } catch { } }
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
                int centerX = chatToggleButton.ClientSize.Width / 2;
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
                int sx = w - 35;
                g.DrawRectangle(goldPen, sx, 74, 19, 19);
                g.DrawRectangle(goldPen, sx, h - 55, 19, 19);
                g.DrawRectangle(goldPen, sx, 99, 19, h - 160);
                g.FillRectangle(bronze, sx + 3, Math.Max(102, h - 125), 14, 54);
                g.DrawString("▲", new System.Drawing.Font("Arial", 10), bright, sx + 2, 75);
                g.DrawString("▼", new System.Drawing.Font("Arial", 10), bright, sx + 2, h - 54);
                // Messages are rendered exclusively by the scrollable RichTextBox child.
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
                BeginInvoke((Action)(() => DockToLauncher()));
                try
                {
                    string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "tes3np", "chat-webview2");
                    freshDiscordProfile = !Directory.Exists(data) || !Directory.EnumerateFileSystemEntries(data).Any();
                    Directory.CreateDirectory(data);
                    var env = await CoreWebView2Environment.CreateAsync(null, data);
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
                    web.CoreWebView2.NavigationCompleted += async (_, _) => await UpdateViewMode();
                    web.CoreWebView2.SourceChanged += async (_, _) => await UpdateViewMode();
                    web.CoreWebView2.NewWindowRequested += (_, e) =>
                    {
                        e.Handled = true;
                        if (e.Uri.StartsWith("https://discord.com/", StringComparison.OrdinalIgnoreCase))
                            web.CoreWebView2.Navigate(e.Uri);
                    };
                    if (freshDiscordProfile) ShowDiscordSignIn();
                    web.CoreWebView2.Navigate(freshDiscordProfile ? "https://discord.com/login" : Channel);
                    Log(freshDiscordProfile ? "Fresh Discord profile: opening sign-in" : "Navigating to channel");
                    _ = InitMessageBrowser(env);
                }
                catch (Exception ex)
                {
                    Log("ERROR " + ex);
                    MessageBox.Show("WebView2 chat unavailable: " + ex.Message + "\nInstall Microsoft Edge WebView2 Runtime.", "tes3np Chat");
                }
            };
            FormClosing += (_, _) =>
            {
                closingChat = true;
                watch.Stop();
                historyWatch.Stop();
                if (launcherLocationHook != IntPtr.Zero)
                {
                    UnhookWinEvent(launcherLocationHook);
                    launcherLocationHook = IntPtr.Zero;
                }
                chatToggleWindow.Dispose();
            };
            watch.Tick += async (_, _) =>
            {
                if (closingChat || refreshingChat || IsDisposed) return;
                if (!IsWindow(owner)) { Close(); return; }
                refreshingChat = true;
                try
                {
                try { LoadLayout(); await LoadCss(); } catch (Exception ex) { Log("Reload error: " + ex.Message); }
                if (!docked && !signInExpanded) DockToLauncher();
                if (docked && !nativeMode) { EnforceChatClip(); RaiseFrame(); }
                await CheckDiscordAuthentication();
                await RefreshNativeMessages();
                PositionChatWindows();
                if (!discordLoginVisible && chatDisplayMode == "Automatic" && chatOpen &&
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
                catch (Exception ex) { if (!closingChat) Log("Chat timer error: " + ex.Message); }
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
            // Cache-first discovery works in both QA and production. No
            // synthetic banner is ever created for an empty archive.
            BeginHappyHourDiscovery();
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
            catch (Exception ex) { Log("Header removal error: " + ex.Message); }
        }
        async Task ApplyCss()
        {
            if (web.CoreWebView2 == null) return;
            var js = "(() => { const css = " + System.Text.Json.JsonSerializer.Serialize(userCss) +
                "; let style=document.getElementById('tes3np-chat-style'); if(!style){style=document.createElement('style');style.id='tes3np-chat-style';document.head.appendChild(style);} style.textContent=css; if(document.body&&!document.getElementById('tes3np-frame')){const f=document.createElement('div');f.id='tes3np-frame';document.body.appendChild(f);} })()";
            try { await web.CoreWebView2.ExecuteScriptAsync(js); await HideChannelHeader(); } catch (Exception ex) { Log("CSS error: " + ex.Message); }
        }
        async Task CheckDiscordAuthentication()
        {
            if (web.CoreWebView2 == null || closingChat) return;
            try
            {
                string url = web.CoreWebView2.Source ?? "";
                bool onLogin = url.StartsWith("https://discord.com/login", StringComparison.OrdinalIgnoreCase)
                    || url.StartsWith("https://discord.com/register", StringComparison.OrdinalIgnoreCase);
                string state = await web.CoreWebView2.ExecuteScriptAsync(
                    "(() => { if (document.readyState === 'loading') return 'loading'; " +
                    "if (document.querySelector('[data-list-id=chat-messages]')) return 'chat'; " +
                    "if (document.querySelector('input[type=password]')) return 'login'; " +
                    "const t = document.body?.innerText || ''; " +
                    "if (/Discord App Detected|Discord App Launched/i.test(t)) return 'app-prompt'; " +
                    "return 'pending'; })()");
                if (state == "\"chat\"")
                {
                    if (discordLoginVisible) RestoreGameChatAfterSignIn();
                    return;
                }
                // After authentication Discord may land on its home page,
                // not the server channel. Redirect once to the configured feed.
                if (discordLoginVisible && !onLogin &&
                    url.StartsWith("https://discord.com/channels/", StringComparison.OrdinalIgnoreCase) &&
                    !url.StartsWith(Channel, StringComparison.OrdinalIgnoreCase) &&
                    state != "\"loading\"" && state != "\"app-prompt\"")
                {
                    Log("Discord signed in; opening Game Chat channel");
                    web.CoreWebView2.Navigate(Channel);
                    return;
                }
                if (onLogin || state == "\"login\"")
                {
                    ShowDiscordSignIn();
                    if (onLogin) await StyleDiscordLogin();
                    return;
                }
                if (state == "\"app-prompt\"")
                {
                    ShowDiscordSignIn();
                    Log("Discord desktop-app prompt detected; navigating to browser sign-in");
                    web.CoreWebView2.Navigate("https://discord.com/login");
                }
            }
            catch (Exception ex) { Log("Discord auth check: " + ex.Message); }
        }
        // Keep Discord's own inputs and authentication handlers intact.
        async Task StyleDiscordLogin()
        {
            if (web.CoreWebView2 == null || closingChat) return;
            try
            {
                // Read the bundled emblem beside the chat-host executable.
                // Embed as a data URL so Discord's CSP does not block local files.
                string logoFile = Path.Combine(AppContext.BaseDirectory, "assets", "DiscordInt.png");
                if (File.Exists(logoFile))
                {
                    string logoUrl = "data:image/png;base64," + Convert.ToBase64String(File.ReadAllBytes(logoFile));
                    await web.CoreWebView2.ExecuteScriptAsync(
                        "window.__tes3npIntegrationLogo = " + System.Text.Json.JsonSerializer.Serialize(logoUrl) + ";");
                }
                await web.CoreWebView2.ExecuteScriptAsync("""
                    (() => {
                      if (location.pathname !== '/login') return;
                      const password = document.querySelector('input[type=password]');
                      const form = password?.closest('form');
                      if (!form) return;
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
                        title.textContent = 'Sign in to Discord';
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
                        benefit.textContent = 'Connect Discord for launcher chat and out-of-game alerts for happy hours, world bosses, and player mentions.';
                      }
                      const title = form.querySelector('[data-tes3np-login-heading]');
                      if (title) title.insertAdjacentElement('afterend', benefit);
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
                          margin:0 !important; padding:6px 12px !important;
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
                          margin:4px 4px 14px !important;
                          padding:8px 4px 0 !important;
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
                          border-bottom:1px solid #70532c !important;
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
                      `;
                    })()
                    """);
            }
            catch (Exception ex) { Log("Discord login theme: " + ex.Message); }
        }
        void ShowDiscordSignIn()
        {
            if (discordLoginVisible) return;
            Log("Discord login: revealing the existing browser in Game Chat");
            discordLoginVisible = true;
            // Login is shown inside the normal docked chat panel, not in a
            // separate sign-in window. Keep the toggle and positioning active.
            signInExpanded = false;
            nativeMode = false;
            nativeMessages.Visible = false;
            messageBrowser.Visible = false;
            messageClip.Visible = false;
            goldScrollbar.Visible = false;
            // The Discord browser already exists underneath the black renderer.
            // Remove the overlay and native clipping so its login is usable.
            web.Dock = DockStyle.None;
            web.Parent = this;
            frameSurface.Visible = false;
            if (web.IsHandleCreated) SetWindowRgn(web.Handle, IntPtr.Zero, true);
            web.SetBounds(0, 0, ClientSize.Width, ClientSize.Height);
            web.Visible = true;
            web.BringToFront();
            chatViewport.Visible = false;
            // Keep the title stable: the launcher locates this window by its title.
            Text = "tes3np Chat Host";
            PositionChatWindows();
            Log("Discord login browser exposed");
        }
        void RestoreGameChatAfterSignIn()
        {
            if (!discordLoginVisible) return;
            Log("Discord chat detected: restoring custom Game Chat");
            discordLoginVisible = false;
            signInExpanded = false;
            web.Parent = chatViewport;
            web.Dock = DockStyle.None;
            // Keep the native frame hidden until the message renderer has content.
            frameSurface.Visible = nativeMode;
            chatViewport.Visible = !nativeMode;
            messageClip.Visible = nativeMode;
            goldScrollbar.Visible = nativeMode;
            messageBrowser.Visible = nativeMode;
            nativeMessages.Visible = false;
            web.Visible = !nativeMode;
            Text = "tes3np Chat Host";
            FitWebView();
            DockToLauncher();
            PositionChatWindows();
            _ = RefreshNativeMessages();
        }
        async Task UpdateViewMode()
        {
            if (web.CoreWebView2 == null) return;
            var url = web.CoreWebView2.Source;
            Log("Navigation completed: " + url);
            bool login = url.StartsWith("https://discord.com/login", StringComparison.OrdinalIgnoreCase)
                || url.StartsWith("https://discord.com/register", StringComparison.OrdinalIgnoreCase);
            await CheckDiscordAuthentication();
            if (discordLoginVisible) return;
            EnforceChatClip();
            await ApplyCss();
            await RefreshNativeMessages();
        }
        // Launcher-owned toggle commands (WM_APP + 0x331).
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x8331)
            {
                switch (m.WParam.ToInt64())
                {
                    case 1:
                        SetChatOpen(!chatOpen);
                        if (chatDisplayMode == "Automatic" && chatOpen) lastChatActivity = DateTime.Now;
                        break;
                    case 2: SetChatDisplayMode("Automatic"); break;
                    case 3: SetChatDisplayMode("Always Shown"); break;
                    case 4: SetChatDisplayMode("Always Hidden"); break;
                }
                return;
            }
            base.WndProc(ref m);
        }
        void SetChatDisplayMode(string mode)
        {
            chatDisplayMode = mode;
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(chatModeFile)!);
                File.WriteAllText(chatModeFile, mode);
            }
            catch { }
            SetChatOpen(mode == "Always Shown");
        }
        // WM_APP + 0x332 tells the launcher the authoritative chat visibility.
        void NotifyLauncherChatState()
        {
            if (IsWindow(owner))
                PostMessage(owner, 0x8332, chatOpen ? new IntPtr(1) : IntPtr.Zero, IntPtr.Zero);
        }
        void SetChatOpen(bool show)
        {
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
            if (!IsWindow(owner) || signInExpanded || !GetWindowRect(owner, out var bounds)) return;
            // Only the sign-in view needs extra height for its explanation.
            // Keep the established Game Chat dimensions unchanged.
            int windowHeight = discordLoginVisible ? Math.Max(chatHeight, 780) : chatHeight;
            var work = Screen.FromHandle(owner).WorkingArea;
            windowHeight = Math.Min(windowHeight, work.Height);
            int y = bounds.Top + (bounds.Bottom - bounds.Top - windowHeight) / 2;
            y = Math.Clamp(y, work.Top, Math.Max(work.Top, work.Bottom - windowHeight));
            // Tall gold toggle centered vertically along the launcher's left edge,
            // matching the marked area in the reference screenshot.
            if (chatOpen)
                MoveWindow(Handle, bounds.Left - chatWidth, y, chatWidth, windowHeight, true);
        }
        void DockToLauncher()
        {
            if (!IsWindow(owner) || signInExpanded) return;
            var hwnd = Handle;
            SetParent(hwnd, IntPtr.Zero);
            int style = GetWindowLong(hwnd, GWL_STYLE);
            SetWindowLong(hwnd, GWL_STYLE, (style | WS_POPUP) & ~WS_CHILD);
            ShowInTaskbar = false;
            // Native owner relationship keeps the chat above the launcher and
            // prevents it from becoming an independent Alt+Tab application.
            SetNativeWindowOwner(hwnd, owner);
            int chatExStyle = GetWindowLongEx(hwnd, GWL_EXSTYLE);
            SetWindowLongEx(hwnd, GWL_EXSTYLE,
                (chatExStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
            ApplyWindowOpacity();
            docked = true;
            WatchLauncherMovement();
            PositionChatWindows();
            SetChatOpen(chatDisplayMode == "Always Shown");
            // Actual launcher movement repairs the missing frame pixels on layered AHK windows.
            // Reproduce that exact compositor event once, then restore its original position.
            if (GetWindowRect(owner, out var bounds))
            {
                const uint SWP_NOSIZE_NOZORDER_NOACTIVATE = 0x0001 | 0x0004 | 0x0010;
                SetWindowPos(owner, IntPtr.Zero, bounds.Left + 1, bounds.Top, 0, 0, SWP_NOSIZE_NOZORDER_NOACTIVATE);
                SetWindowPos(owner, IntPtr.Zero, bounds.Left, bounds.Top, 0, 0, SWP_NOSIZE_NOZORDER_NOACTIVATE);
            }
            Log($"Docked {chatX},{chatY} {chatWidth}x{chatHeight}");
        }
    }
}
