using System.Drawing;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    IntPtr serverUpdatesParent;
    LatestUpdatesPanel? serverUpdatesPanel;
    string? serverUpdatesDocument;
    bool serverUpdatesVisibilityPublished;
    static readonly Lazy<string> ServerUpdatesPage = GameChatWeb.Page("server-updates.html");

    void PublishServerUpdatesVisibility()
    {
        bool visible = CanShowServerUpdates;
        if (visible == serverUpdatesVisibilityPublished || !IsHandleCreated || !IsWindow(owner)) return;
        if (PostMessage(owner, 0x833B, new IntPtr(visible ? 1 : 0), Handle))
            serverUpdatesVisibilityPublished = visible;
    }

    void AttachServerUpdatesPanel(IntPtr target)
    {
        if (!CanShowServerUpdates || !IsWindow(target) || GetParent(target) != owner || IsIconic(owner)) return;
        if (target == serverUpdatesParent && serverUpdatesPanel is { IsDisposed: false, IsHandleCreated: true } attached &&
            IsWindow(attached.Handle) && GetParent(attached.Handle) == target)
        {
            PositionServerUpdatesPanel();
            RedrawServerUpdatesPanel(attached);
            return;
        }
        CloseServerUpdatesPanel();
        try
        {
            serverUpdatesParent = target;
            var panel = serverUpdatesPanel = new LatestUpdatesPanel(this);
            var handle = panel.Handle;
            const int WS_CLIPSIBLINGS = 0x04000000;
            const int WS_CLIPCHILDREN = 0x02000000;
            SetWindowLong(handle, GWL_STYLE,
                (GetWindowLong(handle, GWL_STYLE) | WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN) & ~WS_POPUP);
            SetParent(handle, target);
            if (GetParent(handle) != target)
                throw new InvalidOperationException("Game Updates could not attach to the launcher.");
            PositionServerUpdatesPanel();
            RedrawServerUpdatesPanel(panel);
            panel.SetDocument(serverUpdatesDocument ?? ServerUpdatesStatus("Loading server updates…"));
        }
        catch (Exception ex)
        {
            Log("SERVER UPDATES | Panel attachment: " + ex.GetType().Name);
            CloseServerUpdatesPanel();
        }
    }

    static void RedrawServerUpdatesPanel(LatestUpdatesPanel panel)
    {
        ShowWindow(panel.Handle, 4); // SW_SHOWNOACTIVATE
        // RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW.
        RedrawWindow(panel.Handle, IntPtr.Zero, IntPtr.Zero, 0x0185);
    }

    [DllImport("user32.dll")] static extern bool RedrawWindow(IntPtr hwnd, IntPtr rect, IntPtr region, uint flags);

    void PositionServerUpdatesPanel()
    {
        PublishServerUpdatesVisibility();
        if (serverUpdatesPanel is not { IsDisposed: false } panel) return;
        if (!IsWindow(serverUpdatesParent) || !CanShowServerUpdates)
        {
            CloseServerUpdatesPanel();
            return;
        }
        if (!GetClientRect(serverUpdatesParent, out var rect)) return;
        int width = Math.Max(1, rect.Right - rect.Left), height = Math.Max(1, rect.Bottom - rect.Top);
        if (panel.Width != width || panel.Height != height)
            MoveWindow(panel.Handle, 0, 0, width, height, true);
    }

    void UpdateServerUpdatesDocument(string document)
    {
        if (!ServerUpdatesAuthenticated || document == serverUpdatesDocument) return;
        serverUpdatesDocument = document;
        serverUpdatesPanel?.SetDocument(document);
    }

    void CloseServerUpdatesPanel()
    {
        var panel = serverUpdatesPanel;
        serverUpdatesPanel = null;
        serverUpdatesParent = IntPtr.Zero;
        panel?.Dispose();
    }

    sealed class LatestUpdatesPanel : Panel
    {
        static readonly Color FeedBackground = Color.FromArgb(10, 9, 8);
        readonly GameChatWindow host;
        readonly Panel viewport = new() { BackColor = FeedBackground };
        readonly WebView2 feed = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = FeedBackground };
        readonly Label feedStatus = new()
        {
            Dock = DockStyle.Fill, BackColor = FeedBackground, ForeColor = Color.FromArgb(217, 196, 156),
            Text = "Loading server updates…"
        };
        readonly BufferedScrollbar scrollbar = new();
        readonly Button dismiss = new()
        {
            Text = "×", AccessibleName = "Dismiss Game Updates", FlatStyle = FlatStyle.Flat,
            BackColor = FeedBackground, ForeColor = Color.FromArgb(226, 191, 119), Cursor = Cursors.Hand,
            UseVisualStyleBackColor = false
        };
        string? document;
        bool feedStarted, feedReady;
        int scrollPosition, scrollTotal = 1, scrollPage = 1;
        int dragOffset = -1;

        internal LatestUpdatesPanel(GameChatWindow host)
        {
            this.host = host;
            DoubleBuffered = true;
            ResizeRedraw = true;
            viewport.Controls.Add(feed);
            viewport.Controls.Add(feedStatus);
            feedStatus.BringToFront();
            Controls.Add(viewport);
            Controls.Add(scrollbar);
            Controls.Add(dismiss);
            dismiss.FlatAppearance.BorderColor = Color.FromArgb(151, 113, 58);
            dismiss.FlatAppearance.MouseOverBackColor = Color.FromArgb(57, 39, 21);
            dismiss.Click += (_, _) => host.DismissServerUpdates();
            scrollbar.Paint += (_, e) =>
            {
                int height = Units(scrollbar.ClientSize.Height);
                var metrics = ReadScroll();
                int top = GoldScrollbarThumbY(height, metrics.Total, metrics.Page, metrics.Position, out int thumb);
                host.PaintGoldScrollbar(e.Graphics, height, PanelScale, top, thumb);
            };
            scrollbar.MouseWheel += (_, e) =>
            {
                if (e.Delta != 0) ScrollLines(e.Delta > 0, 3 * Math.Max(1, Math.Abs(e.Delta) / 120));
            };
            scrollbar.MouseDown += (_, e) =>
            {
                if (e.Button != MouseButtons.Left) return;
                int y = Units(e.Y), height = Units(scrollbar.Height);
                if (y < 27 || y >= height - 27)
                {
                    ScrollLines(y < 27, 3);
                    return;
                }
                var metrics = ReadScroll();
                int top = GoldScrollbarThumbY(height, metrics.Total, metrics.Page, metrics.Position, out int thumb);
                dragOffset = y >= top && y < top + thumb ? y - top : thumb / 2;
                scrollbar.Capture = true;
                ScrollToThumb(y);
            };
            scrollbar.MouseMove += (_, e) =>
            {
                if (scrollbar.Capture && dragOffset >= 0 && e.Button == MouseButtons.Left)
                    ScrollToThumb(Units(e.Y));
            };
            scrollbar.MouseUp += (_, _) => scrollbar.Capture = false;
            scrollbar.MouseCaptureChanged += (_, _) =>
            {
                if (!scrollbar.Capture) dragOffset = -1;
            };
        }

        double PanelScale => Math.Max(0.25, ClientSize.Width / 220d);
        int Px(int value) => Math.Max(1, (int)Math.Round(value * PanelScale));
        int Units(int value) => (int)Math.Round(value / PanelScale);

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (feed is null || ClientSize.Width < 1 || ClientSize.Height < 1) return;
            int top = Px(56), bottom = Px(14), left = Px(18);
            dismiss.SetBounds(ClientSize.Width - Px(37), Px(18), Px(22), Px(24));
            int scrollHeight = Math.Max(1, ClientSize.Height - top - bottom);
            scrollbar.SetBounds(Math.Max(left, ClientSize.Width - Px(34)), top, Px(20), scrollHeight);
            int width = Math.Max(1, scrollbar.Left - left - Px(3));
            viewport.SetBounds(left, top, width, scrollHeight);
            SetFeedScale();
        }

        protected override void OnPaint(PaintEventArgs e) =>
            host.PaintGameChatFrame(e.Graphics, Units(ClientSize.Width), Units(ClientSize.Height),
                PanelScale, "Game Updates", headerRightPadding: Units(ClientSize.Width - dismiss.Left) + 4);

        void SetFeedScale()
        {
            if (feed.CoreWebView2 != null)
                feed.ZoomFactor = Math.Clamp(PanelScale * 96 / Math.Max(96, DeviceDpi), 0.25, 3);
        }

        internal void SetDocument(string value)
        {
            document = value;
            if (feedReady)
                PostDocument();
            else if (!feedStarted)
                _ = InitializeFeed();
        }

        async Task InitializeFeed()
        {
            if (host.discordEnvironment is not { } environment) return;
            feedStarted = true;
            try
            {
                await feed.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(8));
                if (IsDisposed) return;
                var core = feed.CoreWebView2;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.AreBrowserAcceleratorKeysEnabled = false;
                core.NavigationStarting += (_, e) => e.Cancel = e.Uri != "about:blank";
                core.NewWindowRequested += (_, e) => e.Handled = true;
                core.DownloadStarting += (_, e) => e.Cancel = true;
                core.WebMessageReceived += HandleFeedMessage;
                core.NavigationCompleted += (_, e) =>
                {
                    if (IsDisposed) return;
                    if (!e.IsSuccess)
                    {
                        feedStatus.Text = "Game Updates could not open.";
                        return;
                    }
                    feedReady = true;
                    SetFeedScale();
                    PostDocument();
                    feedStatus.Visible = false;
                };
                core.NavigateToString(ServerUpdatesPage.Value);
            }
            catch (Exception ex)
            {
                if (IsDisposed) return;
                feedStatus.Text = "Game Updates could not open.";
                host.Log("SERVER UPDATES | Feed renderer: " + ex.GetType().Name);
            }
        }

        void PostDocument()
        {
            if (document != null)
                feed.CoreWebView2.PostWebMessageAsJson(document);
        }

        async void HandleFeedMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
        {
            if (!feedReady || IsDisposed || args.Source != "about:blank") return;
            try
            {
                using var data = JsonDocument.Parse(args.WebMessageAsJson);
                var message = data.RootElement;
                if (message.GetProperty("type").GetString() is "scroll")
                {
                    scrollTotal = Math.Max(1, message.GetProperty("height").GetInt32());
                    scrollPage = Math.Clamp(message.GetProperty("page").GetInt32(), 1, scrollTotal);
                    scrollPosition = Math.Clamp(message.GetProperty("top").GetInt32(), 0, scrollTotal - scrollPage);
                    scrollbar.Invalidate();
                    return;
                }
                if (message.GetProperty("type").GetString() is not ("toggle" or "picker")) return;
                var request = new ServerUpdateAction(message.GetProperty("type").GetString()!,
                    message.GetProperty("id").GetString() ?? "",
                    message.TryGetProperty("key", out var key) ? key.GetString() : null);
                string? error = await host.ActOnServerUpdate(this, request);
                if (!IsDisposed && feedReady)
                    feed.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new
                    {
                        result = true, id = request.Id, key = request.Key, status = error
                    }));
            }
            catch (Exception ex)
            {
                if (!IsDisposed) host.Log("SERVER UPDATES | Feed action: " + ex.GetType().Name);
            }
        }

        (int Total, int Page, int Position, int Maximum) ReadScroll() =>
            (scrollTotal, scrollPage, scrollPosition, scrollTotal - scrollPage);

        void ScrollToThumb(int y)
        {
            var metrics = ReadScroll();
            int height = Units(scrollbar.Height);
            GoldScrollbarThumbY(height, metrics.Total, metrics.Page, metrics.Position, out int thumb);
            double fraction = Math.Clamp((y - dragOffset - 27d) / Math.Max(1, height - 54 - thumb), 0d, 1d);
            ScrollBy("to", (int)Math.Round(metrics.Maximum * fraction));
        }

        void ScrollLines(bool up, int lines) => ScrollBy("by", lines * (up ? -18 : 18));

        void ScrollBy(string scroll, int pixels)
        {
            if (feedReady)
                feed.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(new { scroll, pixels }));
        }
    }
}
