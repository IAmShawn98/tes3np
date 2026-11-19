using System.Drawing;
using System.Runtime.InteropServices;
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
    bool serverUpdatesVisibilityPublished;
    const string ServerUpdatesPageUri = "https://tes3np-game-updates.invalid/index.html";
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
        if (!CanShowServerUpdates || !IsWindow(target) || GetParent(target) != owner) return;
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
            PositionServerUpdatesPanel();
            panel.SetDocument(serverUpdatesDocument ?? ServerUpdatesStatus("Loading server updates…"));
        }
        catch (Exception ex)
        {
            Log("SERVER UPDATES | Panel setup: " + ex.GetType().Name);
            CloseServerUpdatesPanel();
        }
    }

    void PositionServerUpdatesPanel()
    {
        PublishServerUpdatesVisibility();
        if (serverUpdatesPanel is not { IsDisposed: false } panel) return;
        if (!IsWindow(serverUpdatesAnchor) || !CanShowServerUpdates)
        {
            CloseServerUpdatesPanel();
            return;
        }
        if (IsIconic(owner) || !IsWindowVisible(owner) || !IsWindowVisible(serverUpdatesAnchor))
        {
            if (panel.Visible) panel.Hide();
            return;
        }
        if (!GetWindowRect(serverUpdatesAnchor, out var rect)) return;
        var bounds = Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
        if (bounds.Width < 1 || bounds.Height < 1) return;
        if (panel.Bounds != bounds) panel.Bounds = bounds;
        if (!panel.Visible) panel.Show();
        KeepServerUpdatesAboveLauncher(panel.Handle);
        panel.EnsureFeed();
    }

    void KeepServerUpdatesAboveLauncher(IntPtr panel)
    {
        const uint GW_HWNDPREV = 3;
        const int WS_EX_TOPMOST = 0x00000008;
        const uint flags = 0x0001 | 0x0002 | 0x0010 | 0x0200; // NOSIZE, NOMOVE, NOACTIVATE, NOOWNERZORDER
        // Match the launcher's position relative to other apps without sharing its HWND ownership.
        bool launcherTopmost = (GetWindowLongEx(owner, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
        bool panelTopmost = (GetWindowLongEx(panel, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0;
        if (launcherTopmost != panelTopmost)
            SetWindowPos(panel, new IntPtr(launcherTopmost ? -1 : -2), 0, 0, 0, 0, flags);

        IntPtr previous = GetWindow(owner, GW_HWNDPREV);
        if (previous == panel) return;
        if (previous == IntPtr.Zero || (!launcherTopmost && (GetWindowLongEx(previous, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0))
            previous = launcherTopmost ? new IntPtr(-1) : IntPtr.Zero; // HWND_TOPMOST or HWND_TOP
        SetWindowPos(panel, previous, 0, 0, 0, 0, flags);
    }

    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hwnd, uint command);

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
        serverUpdatesAnchor = IntPtr.Zero;
        panel?.Dispose();
    }

    sealed partial class LatestUpdatesPanel : Form
    {
        static readonly Color FeedBackground = Color.FromArgb(10, 9, 8);
        readonly GameChatWindow host;
        readonly Panel viewport = new() { BackColor = FeedBackground };
        readonly WebView2 feed = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = FeedBackground };
        readonly BufferedScrollbar scrollbar = new();
        readonly Button dismiss = new()
        {
            Text = "×", AccessibleName = "Dismiss Game Updates", FlatStyle = FlatStyle.Flat,
            BackColor = FeedBackground, ForeColor = Color.FromArgb(226, 191, 119), Cursor = Cursors.Hand,
            UseVisualStyleBackColor = false
        };
        string? document;
        string? initializingDocument;
        bool feedConfigured, feedInitializing, feedVisible;
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

        protected override bool ShowWithoutActivation => true;

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
            LayoutFallback(width, scrollHeight);
            if (feedVisible) SetFeedScale();
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
            if (feedVisible)
                SendFeed(value);
            else
                UpdateFallback(value);
            EnsureFeed();
        }

        internal void EnsureFeed()
        {
            if (Visible && document != null && !feedVisible && !feedInitializing && DateTime.UtcNow >= nextFeedRetry)
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
                if (IsDisposed) return;
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
                if (!feedVisible || type is not ("toggle" or "picker")) return;
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
