using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
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
    PointF serverUpdatesOffset = ReadServerUpdatesOffset();
    static string ServerUpdatesPositionPath => Path.Combine(ChatDataRoot, "game-updates-position.txt");

    static PointF ReadServerUpdatesOffset()
    {
        try
        {
            string[] coordinates = File.ReadAllText(ServerUpdatesPositionPath).Split(',');
            if (coordinates.Length == 2 &&
                float.TryParse(coordinates[0], NumberStyles.Float, CultureInfo.InvariantCulture, out float x) &&
                float.TryParse(coordinates[1], NumberStyles.Float, CultureInfo.InvariantCulture, out float y) &&
                float.IsFinite(x) && float.IsFinite(y))
                return new PointF(x, y);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        return PointF.Empty;
    }

    void SaveServerUpdatesOffset(PointF offset)
    {
        if (serverUpdatesOffset == offset) return;
        serverUpdatesOffset = offset;
        try
        {
            WriteChatArchiveAtomically(ServerUpdatesPositionPath, FormattableString.Invariant($"{offset.X:R},{offset.Y:R}"));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log("SERVER UPDATES | Save position: " + ex.GetType().Name);
        }
    }
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
        bool showing = !panel.Visible;
        if (showing)
        {
            _ = panel.Handle; // Set the owner before the first visible frame.
            panel.Show();
        }
        KeepServerUpdatesInLauncherStack();
        if (showing)
        {
            panel.Update();
            PostMessage(owner, 0x833B, new IntPtr(1), Handle);
        }
        panel.EnsureFeed();
    }

    void KeepServerUpdatesInLauncherStack()
    {
        if (closingChat || serverUpdatesPanel is not { IsHandleCreated: true, IsDisposed: false, Visible: true } panel ||
            !IsWindow(owner) || !IsWindowVisible(owner) || IsIconic(owner)) return;

        const uint GW_HWNDNEXT = 2, GW_HWNDPREV = 3, GW_OWNER = 4;
        const int WS_EX_TOPMOST = 0x0008;
        const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOACTIVATE = 0x0010, SWP_NOOWNERZORDER = 0x0200;
        const uint stackOnly = SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER;
        IntPtr window = panel.Handle;
        if (GetWindow(window, GW_OWNER) != owner)
            SetNativeWindowOwner(window, owner);
        if ((GetWindowLongEx(window, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0 &&
            (GetWindowLongEx(owner, GWL_EXSTYLE) & WS_EX_TOPMOST) == 0)
            SetWindowPos(window, new IntPtr(-2), 0, 0, 0, 0, stackOnly); // HWND_NOTOPMOST

        // Ownership permits other windows between the launcher and its popup.
        // Only lower the popup when the window above the launcher is actually
        // below the popup. Never raise the launcher or promote the popup.
        IntPtr insertAfter = GetWindow(owner, GW_HWNDPREV);
        if (insertAfter == IntPtr.Zero || insertAfter == window ||
            (GetWindowLongEx(insertAfter, GWL_EXSTYLE) & WS_EX_TOPMOST) != 0) return;

        var visited = new HashSet<IntPtr>();
        for (IntPtr below = GetWindow(window, GW_HWNDNEXT);
             below != IntPtr.Zero && below != owner && visited.Add(below); below = GetWindow(below, GW_HWNDNEXT))
        {
            if (below != insertAfter) continue;
            if (IsWindow(insertAfter))
                SetWindowPos(window, insertAfter, 0, 0, 0, 0, stackOnly);
            return;
        }
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
        readonly Panel viewport = new() { BackColor = FeedBackground, Visible = false, Cursor = Cursors.Default };
        readonly WebView2 feed = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = FeedBackground };
        readonly BufferedScrollbar scrollbar = new() { Visible = false, Cursor = Cursors.Default };
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
        readonly System.Windows.Forms.Timer headerDragTimer = new() { Interval = 16 };
        Rectangle launcherAnchor;
        Point headerPressPosition, headerGrabOffset;
        bool headerMoved;

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
            headerDragTimer.Tick += TrackHeaderDrag;
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
            launcherAnchor = bounds;
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
            PointF offset = host.serverUpdatesOffset;
            if (headerDragTimer.Enabled)
                bounds.Location = Location;
            else if (!offset.IsEmpty)
            {
                double scale = ScaleForWidth(bounds.Width);
                bounds.X = OffsetCoordinate(bounds.X, offset.X, scale, bounds.Width);
                bounds.Y = OffsetCoordinate(bounds.Y, offset.Y, scale, bounds.Height);
                bounds.Location = ClampToWorkArea(bounds, Screen.FromRectangle(bounds).WorkingArea);
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

        static int OffsetCoordinate(int origin, float offset, double scale, int extent) =>
            (int)Math.Clamp(Math.Round(origin + offset * scale), int.MinValue, int.MaxValue - extent);

        static Point ClampToWorkArea(Rectangle bounds, Rectangle work) => new(
            Math.Clamp(bounds.Left, work.Left, Math.Max(work.Left, work.Right - bounds.Width)),
            Math.Clamp(bounds.Top, work.Top, Math.Max(work.Top, work.Bottom - bounds.Height)));

        bool IsDraggableHeader(Point point) => ClientRectangle.Contains(point) &&
            point.Y < Px(FrameHeaderBottom(HeaderScale)) && !toggle.Bounds.Contains(point);

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left || launcherAnchor.IsEmpty || !IsDraggableHeader(e.Location))
                return;

            headerPressPosition = PointToScreen(e.Location);
            headerGrabOffset = e.Location;
            headerMoved = false;
            Capture = true;
            headerDragTimer.Start();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            Cursor cursor = headerDragTimer.Enabled || IsDraggableHeader(e.Location) ? Cursors.SizeAll : Cursors.Default;
            if (Cursor != cursor) Cursor = cursor;
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (!headerDragTimer.Enabled) Cursor = Cursors.Default;
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left && headerDragTimer.Enabled)
            {
                MoveHeaderDrag(PointToScreen(e.Location));
                FinishHeaderDrag();
            }
            base.OnMouseUp(e);
        }

        protected override void OnMouseCaptureChanged(EventArgs e)
        {
            base.OnMouseCaptureChanged(e);
            if (!Capture) FinishHeaderDrag();
        }

        void TrackHeaderDrag(object? sender, EventArgs e)
        {
            if (!Visible || IsIconic(host.owner))
            {
                FinishHeaderDrag();
                return;
            }

            // The no-activation window may stop receiving mouse messages when
            // a fast drag takes the pointer outside its current bounds.
            MoveHeaderDrag(Cursor.Position);
            int primaryButton = SystemInformation.MouseButtonsSwapped ? 0x02 : 0x01;
            if ((GetAsyncKeyState(primaryButton) & 0x8000) == 0) FinishHeaderDrag();
        }

        void MoveHeaderDrag(Point cursor)
        {
            if (!headerMoved)
            {
                Size threshold = SystemInformation.DragSize;
                var clickArea = new Rectangle(headerPressPosition.X - threshold.Width / 2,
                    headerPressPosition.Y - threshold.Height / 2, threshold.Width, threshold.Height);
                if (clickArea.Contains(cursor)) return;
                headerMoved = true;
            }

            var requested = new Rectangle(cursor.X - headerGrabOffset.X, cursor.Y - headerGrabOffset.Y, Width, Height);
            Point location = ClampToWorkArea(requested, Screen.FromPoint(cursor).WorkingArea);
            if (Location != location) Location = location;
        }

        void FinishHeaderDrag()
        {
            if (!headerDragTimer.Enabled) return;
            headerDragTimer.Stop();
            if (Capture) Capture = false;
            Cursor = Cursors.Default;
            if (!headerMoved) return;

            double scale = ScaleForWidth(launcherAnchor.Width);
            host.SaveServerUpdatesOffset(new PointF(
                (float)((Left - launcherAnchor.Left) / scale), (float)((Top - launcherAnchor.Top) / scale)));
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                FinishHeaderDrag();
                headerDragTimer.Dispose();
            }
            base.Dispose(disposing);
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
