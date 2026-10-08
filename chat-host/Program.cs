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
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr hwnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetWindowLongEx(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] static extern int SetWindowLongEx(IntPtr hwnd, int index, int value);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint colorKey, byte alpha, uint flags);
    const int GWL_EXSTYLE = -20, WS_EX_LAYERED = 0x80000;
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
    int ChatFirstLine() => nativeMessages.IsHandleCreated
        ? SendMessage(nativeMessages.Handle, 0x00CE, IntPtr.Zero, IntPtr.Zero).ToInt32() : 0;
    int ChatLineCount() => nativeMessages.IsHandleCreated
        ? Math.Max(1, SendMessage(nativeMessages.Handle, 0x00BA, IntPtr.Zero, IntPtr.Zero).ToInt32()) : 1;
    int ChatVisibleLines()
    {
        if (nativeMessages.Height < 1) return 1;
        int first = nativeMessages.GetLineFromCharIndex(nativeMessages.GetCharIndexFromPosition(new System.Drawing.Point(2, 2)));
        int last = nativeMessages.GetLineFromCharIndex(nativeMessages.GetCharIndexFromPosition(
            new System.Drawing.Point(2, Math.Max(2, nativeMessages.Height - 4))));
        return Math.Max(1, last - first + 1);
    }
    int ChatThumbY(int height, out int thumbHeight)
    {
        int track = Math.Max(1, height - 54);
        int total = ChatLineCount();
        int visible = ChatVisibleLines();
        thumbHeight = Math.Clamp((int)((long)track * visible / Math.Max(1, total)), Math.Min(20, track), track);
        int maxFirst = Math.Max(0, total - visible);
        // RichEdit can stop before the estimated final first line when wrapping
        // or partial lines are present. Detect the real bottom from the last
        // character's on-screen position, rather than the estimate alone.
        bool atBottom = nativeMessages.TextLength > 0 &&
            nativeMessages.GetPositionFromCharIndex(nativeMessages.TextLength - 1).Y
                + nativeMessages.Font.Height <= nativeMessages.ClientSize.Height + 2;
        if (atBottom) return 27 + track - thumbHeight;
        return 27 + (int)((long)Math.Clamp(ChatFirstLine(), 0, maxFirst)
            * (track - thumbHeight) / Math.Max(1, maxFirst));
    }
    void ScrollChatToThumb(int y, int dragOffset)
    {
        if (!nativeMessages.IsHandleCreated) return;
        int track = Math.Max(1, goldScrollbar.Height - 54);
        ChatThumbY(goldScrollbar.Height, out int thumbHeight);
        int maxFirst = Math.Max(0, ChatLineCount() - ChatVisibleLines());
        int travel = Math.Max(1, track - thumbHeight);
        int relative = Math.Clamp(y - dragOffset - 27, 0, travel);
        int target = (int)((long)relative * maxFirst / travel);
        int delta = target - ChatFirstLine();
        if (delta != 0)
            SendMessage(nativeMessages.Handle, 0x00B6, IntPtr.Zero, new IntPtr(delta));
        goldScrollbar.Invalidate();
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
        string lastFeed = "";
        readonly System.Collections.Generic.List<(string User, string Body)> renderedMessages = new();
        bool nativeMode;
        const string ExtractFeed = """
            (() => {
              const list = document.querySelector('[data-list-id="chat-messages"]');
              if (!list) return '[]';
              const rows = [...list.querySelectorAll('[id^="chat-messages-"]')]
                .filter(el => /^chat-messages-[0-9]+-[0-9]+$/.test(el.id));
              return JSON.stringify(rows.slice(-75).map(el => {
                const usernameEl = el.querySelector('[class*="username_"]');
                const user = usernameEl?.textContent?.trim() || '';
                const color = usernameEl ? getComputedStyle(usernameEl).color : '';
                const body = el.querySelector('[class*="messageContent_"]')?.innerText?.trim() ||
                             el.querySelector('[class*="markup_"]')?.innerText?.trim() || '';
                return {id:el.id,user,body,color};
              }).filter(x => x.body));
            })();
            """;
        async Task RefreshNativeMessages()
        {
            if (closingChat || IsDisposed || web.CoreWebView2 == null || signInExpanded) return;
            try
            {
                string raw = await web.CoreWebView2.ExecuteScriptAsync(ExtractFeed);
                if (closingChat || IsDisposed) return;
                string json = System.Text.Json.JsonSerializer.Deserialize<string>(raw) ?? "[]";
                if (json == lastFeed) return;
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                if (doc.RootElement.GetArrayLength() == 0) return;
                string newestId = doc.RootElement[doc.RootElement.GetArrayLength() - 1]
                    .GetProperty("id").GetString() ?? "";
                bool newMessage = feedInitialized && newestId.Length > 0 &&
                    newestId != latestMessageId;
                latestMessageId = newestId;
                feedInitialized = true;
                if (newMessage && chatDisplayMode == "Automatic")
                {
                    lastChatActivity = DateTime.Now;
                    SetChatOpen(true);
                }
                lastFeed = json;
                renderedMessages.Clear();
                nativeMessages.SuspendLayout();
                nativeMessages.Clear();
                foreach (var msg in doc.RootElement.EnumerateArray())
                {
                    string user = msg.GetProperty("user").GetString() ?? "";
                    string body = msg.GetProperty("body").GetString() ?? "";
                    renderedMessages.Add((user, body));
                    if (user.Length > 0)
                    {
                        var usernameColor = System.Drawing.Color.FromArgb(219, 178, 67);
                        if (msg.TryGetProperty("color", out var colorValue))
                        {
                            var cssColor = colorValue.GetString() ?? "";
                            var components = System.Text.RegularExpressions.Regex.Matches(cssColor, @"\d+");
                            if ((cssColor.StartsWith("rgb(", StringComparison.OrdinalIgnoreCase) ||
                                 cssColor.StartsWith("rgba(", StringComparison.OrdinalIgnoreCase)) &&
                                components.Count >= 3 &&
                                byte.TryParse(components[0].Value, out var red) &&
                                byte.TryParse(components[1].Value, out var green) &&
                                byte.TryParse(components[2].Value, out var blue))
                                usernameColor = System.Drawing.Color.FromArgb(red, green, blue);
                        }
                        nativeMessages.SelectionColor = usernameColor;
                        nativeMessages.AppendText(user + ": ");
                    }
                    nativeMessages.SelectionColor = System.Drawing.Color.FromArgb(241, 238, 232);
                    nativeMessages.AppendText(body);
                    if (renderedMessages.Count < doc.RootElement.GetArrayLength())
                        nativeMessages.AppendText(Environment.NewLine);
                }
                nativeMessages.SelectionStart = nativeMessages.TextLength;
                nativeMessages.ScrollToCaret();
                nativeMessages.ResumeLayout();
                // ScrollToCaret only ensures the last line is visible; it can leave
                // a large unused area below it. Explicitly scroll RichEdit to the
                // real bottom after text layout has completed.
                if (nativeMessages.IsHandleCreated)
                    SendMessage(nativeMessages.Handle, 0x00B5, new IntPtr(7), IntPtr.Zero); // EM_SCROLL, SB_BOTTOM
                goldScrollbar.Invalidate();
                if (!nativeMode)
                {
                    nativeMode = true;
                    web.Visible = false;
                    chatViewport.Visible = false;
                    nativeMessages.Visible = true;
                    messageClip.BringToFront();
                    goldScrollbar.BringToFront();
                    frameSurface.Visible = true;
                    frameSurface.Invalidate();
                    Log("Native message view activated");
                }
            }
            catch (Exception ex) { Log("Native feed error: " + ex.Message); }
        }
        readonly System.Windows.Forms.Timer watch = new() { Interval = 500 };
        bool closingChat;
        bool refreshingChat;
        [DllImport("gdi32.dll")] static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
        [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr hwnd, IntPtr region, bool redraw);
        void RaiseFrame()
        {
            // Frame is rendered inside the browser DOM, so no native rails are needed.
            return;
            // WebView2 has its own native HWND. Managed BringToFront alone
            // does not reliably win when the browser surface is recreated.
            frame.BringToFront();
            const uint SWP_NOMOVE = 0x0002, SWP_NOSIZE = 0x0001,
                       SWP_NOACTIVATE = 0x0010, SWP_SHOWWINDOW = 0x0040;
            SetWindowPos(frame.Handle, IntPtr.Zero, 0, 0, 0, 0,
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
        }
        void EnforceChatClip()
        {
            if (!web.IsHandleCreated || chatViewport.ClientSize.Width < 1) return;
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
            frameSurface.SetBounds(0, 0, ClientSize.Width, ClientSize.Height);
            messageClip.SetBounds(23, 60, Math.Max(1, ClientSize.Width - 60), Math.Max(1, ClientSize.Height - 78));
            nativeMessages.SetBounds(0, 0, messageClip.Width, messageClip.Height);
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
        string latestMessageId = "";
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
            chatToggleWindow.Controls.Add(chatToggleButton);
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
                if (!nativeMessages.IsHandleCreated || e.Delta == 0) return;
                int notches = Math.Max(1, Math.Abs(e.Delta) / 120);
                int lines = 3 * notches * (e.Delta > 0 ? -1 : 1);
                SendMessage(nativeMessages.Handle, 0x00B6, IntPtr.Zero, new IntPtr(lines)); // EM_LINESCROLL
                goldScrollbar.Invalidate();
            }
            goldScrollbar.MouseWheel += (_, e) => ScrollWheelMessages(e);
            nativeMessages.MouseWheel += (_, e) => ScrollWheelMessages(e);
            messageClip.MouseWheel += (_, e) => ScrollWheelMessages(e);
            int dragOffset = -1;
            goldScrollbar.MouseDown += (_, e) =>
            {
                if (!nativeMessages.IsHandleCreated || e.X < goldScrollbar.Width - 20) return;
                if (e.Y < 27 || e.Y >= goldScrollbar.Height - 27)
                {
                    SendMessage(nativeMessages.Handle, 0x0115, new IntPtr(e.Y < 27 ? 0 : 1), IntPtr.Zero);
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
                if (nativeMessages.IsHandleCreated)
                    SendMessage(nativeMessages.Handle, 0x0115, new IntPtr(8), IntPtr.Zero);
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
                    web.CoreWebView2.NewWindowRequested += (_, e) =>
                    {
                        e.Handled = true;
                        if (e.Uri.StartsWith("https://discord.com/", StringComparison.OrdinalIgnoreCase))
                            web.CoreWebView2.Navigate(e.Uri);
                    };
                    web.CoreWebView2.Navigate(Channel);
                    Log("Navigating to channel");
                }
                catch (Exception ex)
                {
                    Log("ERROR " + ex);
                    MessageBox.Show("WebView2 chat unavailable: " + ex.Message + "\nInstall Microsoft Edge WebView2 Runtime.", "tes3np Chat");
                }
            };
            FormClosing += (_, _) => { closingChat = true; watch.Stop(); chatToggleWindow.Dispose(); };
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
                await RefreshNativeMessages();
                PositionChatWindows();
                if (chatDisplayMode == "Automatic" && chatOpen &&
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
            watch.Start();
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
        async Task UpdateViewMode()
        {
            if (web.CoreWebView2 == null) return;
            var url = web.CoreWebView2.Source;
            Log("Navigation completed: " + url);
            EnforceChatClip();
            bool login = url.StartsWith("https://discord.com/login", StringComparison.OrdinalIgnoreCase)
                || url.StartsWith("https://discord.com/register", StringComparison.OrdinalIgnoreCase);
            if (login && !signInExpanded)
            {
                signInExpanded = true;
                nativeMode = false;
                nativeMessages.Visible = false;
                web.Visible = true;
                docked = false;
                SetParent(Handle, IntPtr.Zero);
                int style = GetWindowLong(Handle, GWL_STYLE);
                SetWindowLong(Handle, GWL_STYLE, (style | WS_POPUP) & ~WS_CHILD);
                MoveWindow(Handle, 180, 100, 900, 720, true);
                ShowInTaskbar = true;
                Text = "tes3np — Discord Sign In";
                return;
            }
            if (!login && signInExpanded)
            {
                signInExpanded = false;
                DockToLauncher();
            }
            if (!login)
            {
                await ApplyCss();
                await RefreshNativeMessages();
            }
        }
        void SetChatOpen(bool show)
        {
            chatOpen = show;
            chatToggleButton.Invalidate();
            if (!signInExpanded && IsHandleCreated)
            {
                if (show) ShowWindow(Handle, 5);
                else ShowWindow(Handle, 0);
            }
            PositionChatWindows();
        }
        void PositionChatWindows()
        {
            if (!IsWindow(owner) || signInExpanded || !GetWindowRect(owner, out var bounds)) return;
            const int buttonWidth = 68, buttonHeight = 168;
            int y = bounds.Top + Math.Max(0, (bounds.Bottom - bounds.Top - chatHeight) / 2);
            // Tall gold toggle centered vertically along the launcher's left edge,
            // matching the marked area in the reference screenshot.
            chatToggleWindow.SetBounds(bounds.Left + 3,
                bounds.Top + Math.Max(0, (bounds.Bottom - bounds.Top - buttonHeight) / 2),
                buttonWidth, buttonHeight);
            if (!chatToggleWindow.Visible) chatToggleWindow.Show();
            if (chatOpen)
                MoveWindow(Handle, bounds.Left - chatWidth, y, chatWidth, chatHeight, true);
        }
        void DockToLauncher()
        {
            if (!IsWindow(owner) || signInExpanded) return;
            var hwnd = Handle;
            SetParent(hwnd, IntPtr.Zero);
            int style = GetWindowLong(hwnd, GWL_STYLE);
            SetWindowLong(hwnd, GWL_STYLE, (style | WS_POPUP) & ~WS_CHILD);
            ShowInTaskbar = false;
            ApplyWindowOpacity();
            docked = true;
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
