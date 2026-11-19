using System.Drawing;
using System.Drawing.Drawing2D;
using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    IntPtr serverUpdatesAnchor;
    LatestUpdatesPanel? serverUpdatesPanel;
    string? serverUpdatesDocument;
    DateTime nextServerUpdatesAnchorRequest;
    const string ServerUpdatesPageUri = "https://tes3np-game-updates.invalid/index.html";
    static readonly Lazy<string> ServerUpdatesPage = GameChatWeb.Page("server-updates.html");

    void AttachServerUpdatesPanel(IntPtr target)
    {
        if (closingChat || !IsWindow(target) || GetParent(target) != owner) return;
        if (target == serverUpdatesAnchor && serverUpdatesPanel is { IsDisposed: false })
        {
            PositionServerUpdatesPanel();
            return;
        }
        CloseServerUpdatesPanel();
        try
        {
            serverUpdatesAnchor = target;
            var panel = serverUpdatesPanel = new LatestUpdatesPanel(this);
            panel.SetDocument(serverUpdatesDocument ?? ServerUpdatesStatus("Loading server updates…"));
            PositionServerUpdatesPanel();
        }
        catch (Exception ex)
        {
            Log("SERVER UPDATES | Panel setup: " + ex.GetType().Name);
            CloseServerUpdatesPanel();
        }
    }

    void PositionServerUpdatesPanel()
    {
        if (closingChat || IsDisposed || !IsWindow(owner)) return;
        if (serverUpdatesPanel is not { IsDisposed: false } panel)
        {
            if (IsHandleCreated && DateTime.UtcNow >= nextServerUpdatesAnchorRequest)
            {
                nextServerUpdatesAnchorRequest = DateTime.UtcNow.AddSeconds(1);
                PostMessage(owner, 0x833B, IntPtr.Zero, Handle);
            }
            return;
        }
        if (!IsWindow(serverUpdatesAnchor))
        {
            CloseServerUpdatesPanel();
            return;
        }
        // Windows hides and restores owned windows with a minimized owner.
        if (IsIconic(owner)) return;
        if (!IsWindowVisible(owner))
        {
            if (panel.Visible) panel.Hide();
            return;
        }
        if (!GetWindowRect(serverUpdatesAnchor, out var rect)) return;
        var bounds = Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
        if (bounds.Width < 1 || bounds.Height < 1) return;
        panel.SetLauncherBounds(bounds, ServerUpdatesShellExpanded);
        if (!panel.Visible)
        {
            _ = panel.Handle; // Set the owner before the first visible frame.
            panel.Show();
            panel.Update();
            PostMessage(owner, 0x833B, new IntPtr(1), Handle);
        }
        panel.EnsureFeed();
    }

    void UpdateServerUpdatesDocument(string document, bool revealNewest = false)
    {
        if (!ServerUpdatesAuthenticated || document == serverUpdatesDocument) return;
        serverUpdatesDocument = document;
        serverUpdatesPanel?.SetDocument(document, revealNewest);
    }

    void CloseServerUpdatesPanel()
    {
        var panel = serverUpdatesPanel;
        serverUpdatesPanel = null;
        serverUpdatesAnchor = IntPtr.Zero;
        panel?.Dispose();
    }

    sealed partial class LatestUpdatesPanel : Form
    {
        static readonly Color FeedBackground = Color.FromArgb(10, 9, 8);
        readonly GameChatWindow host;
        readonly Panel viewport = new() { BackColor = FeedBackground, Visible = false };
        readonly WebView2 feed = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = FeedBackground };
        readonly BufferedScrollbar scrollbar = new() { Visible = false };
        readonly Button toggle = new()
        {
            AccessibleName = "Show Game Updates", FlatStyle = FlatStyle.Flat,
            BackColor = FeedBackground, ForeColor = Color.FromArgb(226, 191, 119), Cursor = Cursors.Hand,
            UseVisualStyleBackColor = false
        };
        string? document;
        string? initializingDocument;
        bool bodyExpanded, feedConfigured, feedInitializing, feedVisible;
        TaskCompletionSource<bool>? feedLoad;
        DateTime nextFeedRetry;
        int scrollPosition, scrollTotal = 1, scrollPage = 1;
        int dragOffset = -1;

        internal LatestUpdatesPanel(GameChatWindow host)
        {
            this.host = host;
            Text = "TES3NP Game Updates";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            ShowInTaskbar = false;
            DoubleBuffered = true;
            ResizeRedraw = true;
            viewport.Controls.Add(feed);
            viewport.Controls.Add(fallbackClip);
            fallbackClip.Controls.Add(fallbackFeed);
            fallbackClip.BringToFront();
            fallbackFeed.VScroll += (_, _) => scrollbar.Invalidate();
            Controls.Add(viewport);
            Controls.Add(scrollbar);
            Controls.Add(toggle);
            toggle.FlatAppearance.BorderColor = Color.FromArgb(194, 153, 83);
            toggle.FlatAppearance.MouseOverBackColor = Color.FromArgb(57, 39, 21);
            toggle.FlatAppearance.MouseDownBackColor = Color.FromArgb(87, 61, 30);
            toggle.Paint += PaintToggleButton;
            toggle.Click += (_, _) => host.ToggleServerUpdatesBody();
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

        protected override bool ShowWithoutActivation => true;

        protected override void CreateHandle()
        {
            base.CreateHandle();
            // WinForms sets its taskbar owner during CreateHandle. Replace it after creation.
            if (host != null && IsWindow(host.owner)) SetNativeWindowOwner(Handle, host.owner);
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0021) // WM_MOUSEACTIVATE
            {
                message.Result = new IntPtr(3); // MA_NOACTIVATE: deliver the click without activating.
                return;
            }
            base.WndProc(ref message);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                const int WS_EX_NOACTIVATE = 0x08000000;
                var parameters = base.CreateParams;
                parameters.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
                return parameters;
            }
        }

        static double ScaleForWidth(int width) => Math.Max(0.25, width / 220d);
        double PanelScale => ScaleForWidth(ClientSize.Width);
        // The launcher slot already includes desktop DPI. Use the chat header's
        // scale for the title and toggle button, independently of the feed.
        float HeaderScale => 96f / Math.Max(96, DeviceDpi);
        int Px(double value) => Math.Max(1, (int)Math.Round(value * PanelScale));
        int Units(int value) => (int)Math.Round(value / PanelScale);

        internal void SetLauncherBounds(Rectangle bounds, bool expand)
        {
            bool changed = bodyExpanded != expand;
            bodyExpanded = expand;
            if (!bodyExpanded)
            {
                if (changed)
                {
                    viewport.Hide();
                    scrollbar.Hide();
                }
                bounds.Height = Pixels(FrameHeaderBottom(HeaderScale) + FrameFooterHeight, ScaleForWidth(bounds.Width));
            }
            if (Bounds != bounds) Bounds = bounds;
            if (!changed) return;

            if (bodyExpanded)
            {
                viewport.Show();
                scrollbar.Show();
            }
            toggle.AccessibleName = bodyExpanded ? "Hide Game Updates" : "Show Game Updates";
            toggle.Invalidate();
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (feed is null || ClientSize.Width < 1 || ClientSize.Height < 1) return;
            int headerBottom = FrameHeaderBottom(HeaderScale);
            int top = Px(headerBottom + 5), bottom = Px(14), left = Px(18);
            int toggleSize = Px(24 * HeaderScale);
            int toggleTop = Px((FrameHeaderTop + headerBottom) / 2d) - toggleSize / 2;
            toggle.SetBounds(ClientSize.Width - Px(17) - toggleSize, toggleTop, toggleSize, toggleSize);
            if (!bodyExpanded) return;
            int scrollHeight = Math.Max(1, ClientSize.Height - top - bottom);
            scrollbar.SetBounds(Math.Max(left, ClientSize.Width - Px(34)), top, Px(20), scrollHeight);
            int width = Math.Max(1, scrollbar.Left - left - Px(3));
            viewport.SetBounds(left, top, width, scrollHeight);
            LayoutFallback(width, scrollHeight);
            if (feedVisible) SetFeedScale();
        }

        protected override void OnPaint(PaintEventArgs e) =>
            host.PaintGameChatFrame(e.Graphics, Units(ClientSize.Width), Units(ClientSize.Height),
                PanelScale, "Game Updates", headerSidePadding: Units(ClientSize.Width - toggle.Left) + 4,
                headerScale: HeaderScale);

        void PaintToggleButton(object? sender, PaintEventArgs e)
        {
            float size = Math.Min(toggle.ClientSize.Width, toggle.ClientSize.Height);
            float x = toggle.ClientSize.Width / 2f, y = toggle.ClientSize.Height / 2f;
            float radius = size / 4f, rise = size / 7f;
            if (bodyExpanded) rise = -rise;
            using var pen = new Pen(toggle.ForeColor, Math.Max(1.2f, size / 12f))
            {
                StartCap = LineCap.Round,
                EndCap = LineCap.Round,
                LineJoin = LineJoin.Round
            };
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.DrawLines(pen, new PointF[] { new(x - radius, y - rise), new(x, y + rise), new(x + radius, y - rise) });
        }

        void SetFeedScale()
        {
            if (feed.CoreWebView2 != null)
                feed.ZoomFactor = Math.Clamp(PanelScale * 96 / Math.Max(96, DeviceDpi), 0.25, 3);
        }

        internal void SetDocument(string value, bool revealNewest = false)
        {
            document = value;
            if (feedVisible)
                SendFeed(value);
            else
                UpdateFallback(value, revealNewest);
            if (revealNewest && feedVisible)
                SendFeed("""{"scroll":"newest"}""");
            EnsureFeed();
        }

        internal void ResetDocument()
        {
            feedLoad?.TrySetResult(false);
            feedVisible = false;
            nextFeedRetry = DateTime.MinValue;
            fallbackClip.Visible = true;
            SetDocument(ServerUpdatesStatus("Loading server updates…"));
        }

        internal void EnsureFeed()
        {
            if (bodyExpanded && Visible && document != null && !feedVisible && !feedInitializing &&
                DateTime.UtcNow >= nextFeedRetry)
                _ = InitializeFeed();
        }

        async Task InitializeFeed()
        {
            if (host.discordEnvironment is not { } environment) return;
            feedInitializing = true;
            var load = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            feedLoad = load;
            try
            {
                await feed.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(8));
                if (IsDisposed || load.Task.IsCompleted) return;
                var core = feed.CoreWebView2;
                if (!feedConfigured)
                {
                    byte[] html = Encoding.UTF8.GetBytes(ServerUpdatesPage.Value);
                    core.AddWebResourceRequestedFilter(ServerUpdatesPageUri, CoreWebView2WebResourceContext.Document,
                        CoreWebView2WebResourceRequestSourceKinds.Document);
                    core.WebResourceRequested += (_, e) =>
                    {
                        if (e.Request.Uri == ServerUpdatesPageUri)
                            e.Response = environment.CreateWebResourceResponse(new MemoryStream(html, false), 200,
                                "OK", "Content-Type: text/html; charset=utf-8\r\nCache-Control: no-store");
                    };
                    core.Settings.AreDefaultContextMenusEnabled = false;
                    core.Settings.AreDevToolsEnabled = false;
                    core.NavigationStarting += (_, e) => e.Cancel = e.Uri != ServerUpdatesPageUri;
                    core.NewWindowRequested += (_, e) => e.Handled = true;
                    core.DownloadStarting += (_, e) => e.Cancel = true;
                    core.WebMessageReceived += HandleFeedMessage;
                    core.NavigationCompleted += (_, e) =>
                    {
                        if (IsDisposed || e.IsSuccess) return;
                        FallBack("navigation " + e.WebErrorStatus);
                    };
                    core.ProcessFailed += (_, e) => FallBack("WebView2 " + e.ProcessFailedKind);
                    feedConfigured = true;
                }
                SetFeedScale();
                core.Navigate(ServerUpdatesPageUri);
                await load.Task.WaitAsync(TimeSpan.FromSeconds(8));
            }
            catch (Exception ex)
            {
                if (!IsDisposed) FallBack(ex.GetType().Name + " 0x" + ex.HResult.ToString("X8"));
            }
            finally
            {
                feedLoad = null;
                initializingDocument = null;
                feedInitializing = false;
            }
        }

        void FallBack(string reason)
        {
            if (IsDisposed) return;
            feedVisible = false;
            if (host.serverUpdatesPanel == this) host.StopServerUpdatePicker();
            feedLoad?.TrySetResult(false);
            nextFeedRetry = DateTime.UtcNow.AddSeconds(15);
            fallbackClip.Visible = true;
            LayoutFallback(viewport.Width, viewport.Height);
            if (document != null) UpdateFallback(document);
            scrollbar.Invalidate();
            host.Log("SERVER UPDATES | Reaction view: " + reason);
        }

        void SendFeed(string message)
        {
            try { feed.CoreWebView2.PostWebMessageAsJson(message); }
            catch (Exception ex)
            {
                feedLoad?.TrySetResult(false);
                FallBack(ex.GetType().Name + " 0x" + ex.HResult.ToString("X8"));
            }
        }

        async void HandleFeedMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
        {
            if (IsDisposed || args.Source != ServerUpdatesPageUri) return;
            try
            {
                using var data = JsonDocument.Parse(args.WebMessageAsJson);
                var message = data.RootElement;
                string? type = message.GetProperty("type").GetString();
                if (type == "ready")
                {
                    if (document != null && (feedLoad != null || feedVisible))
                    {
                        initializingDocument = document;
                        SendFeed(document);
                    }
                    return;
                }
                if (type is "scroll" or "rendered")
                {
                    scrollTotal = Math.Max(1, message.GetProperty("height").GetInt32());
                    scrollPage = Math.Clamp(message.GetProperty("page").GetInt32(), 1, scrollTotal);
                    scrollPosition = Math.Clamp(message.GetProperty("top").GetInt32(), 0, scrollTotal - scrollPage);
                    if (type == "rendered" && feedLoad?.TrySetResult(true) == true)
                    {
                        feedVisible = true;
                        fallbackClip.Visible = false;
                        if (document != null && document != initializingDocument) SendFeed(document);
                    }
                    scrollbar.Invalidate();
                    return;
                }
                if (!bodyExpanded || !feedVisible || type is not ("toggle" or "picker")) return;
                var request = new ServerUpdateAction(type,
                    message.GetProperty("id").GetString() ?? "",
                    message.TryGetProperty("key", out var key) ? key.GetString() : null,
                    message.TryGetProperty("mine", out var mine) && mine.ValueKind is JsonValueKind.True or JsonValueKind.False
                        ? mine.GetBoolean() : null);
                string? error = type == "picker" ? await host.ShowServerUpdatePicker(this, request.Id)
                    : await host.ActOnServerUpdate(this, request);
                if (!IsDisposed && feedVisible)
                    SendFeed(JsonSerializer.Serialize(new
                    {
                        result = true, id = request.Id, key = request.Key, status = error
                    }));
            }
            catch (Exception ex)
            {
                if (!IsDisposed) host.Log("SERVER UPDATES | Feed action: " + ex.GetType().Name);
            }
        }

        (int Total, int Page, int Position, int Maximum) ReadScroll() => feedVisible
            ? (scrollTotal, scrollPage, scrollPosition, scrollTotal - scrollPage)
            : ReadFallbackScroll();

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
            if (feedVisible)
                SendFeed(JsonSerializer.Serialize(new { scroll, pixels }));
            else
                ScrollFallback(scroll, pixels);
        }
    }
}
