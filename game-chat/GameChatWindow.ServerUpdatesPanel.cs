using System.Drawing;
using System.Runtime.InteropServices;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    IntPtr serverUpdatesParent;
    LatestUpdatesPanel? serverUpdatesPanel;
    string? serverUpdatesDocument;
    bool serverUpdatesVisibilityPublished;

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
        readonly BufferedScrollbar dateBand = new() { BackColor = FeedBackground, TabStop = false };
        readonly RichTextBox feed = new()
        {
            BackColor = FeedBackground, ForeColor = Color.FromArgb(241, 238, 232),
            ReadOnly = true, BorderStyle = BorderStyle.None, DetectUrls = false,
            ScrollBars = RichTextBoxScrollBars.ForcedVertical, TabStop = true
        };
        readonly BufferedScrollbar scrollbar = new();
        readonly Button dismiss = new()
        {
            Text = "×", AccessibleName = "Dismiss Game Updates", FlatStyle = FlatStyle.Flat,
            BackColor = FeedBackground, ForeColor = Color.FromArgb(226, 191, 119), Cursor = Cursors.Hand,
            UseVisualStyleBackColor = false
        };
        List<(int Offset, string Label)> dateDividers = [];
        string? visibleDate;
        int? newestLandingPosition;
        int dragOffset = -1;

        internal LatestUpdatesPanel(GameChatWindow host)
        {
            this.host = host;
            DoubleBuffered = true;
            ResizeRedraw = true;
            viewport.Controls.Add(feed);
            Controls.Add(viewport);
            Controls.Add(scrollbar);
            Controls.Add(dateBand);
            Controls.Add(dismiss);
            dismiss.FlatAppearance.BorderColor = Color.FromArgb(151, 113, 58);
            dismiss.FlatAppearance.MouseOverBackColor = Color.FromArgb(57, 39, 21);
            dismiss.Click += (_, _) => host.DismissServerUpdates();
            dateBand.Paint += PaintVisibleDate;
            feed.VScroll += (_, _) => RefreshScrollDisplay();
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
            var previous = ReadScroll();
            int top = Px(56), bottom = Px(14), left = Px(18), dateHeight = Px(16);
            dismiss.SetBounds(ClientSize.Width - Px(37), Px(18), Px(22), Px(24));
            int scrollHeight = Math.Max(1, ClientSize.Height - top - bottom);
            scrollbar.SetBounds(Math.Max(left, ClientSize.Width - Px(34)), top, Px(20), scrollHeight);
            int width = Math.Max(1, scrollbar.Left - left - Px(3));
            dateBand.SetBounds(left, top, width, dateHeight);
            int height = Math.Max(1, scrollHeight - dateHeight);
            viewport.SetBounds(left, top + dateHeight, width, height);
            // Keep RichEdit's scrollbar range, with its native scroller outside the clipped viewport.
            uint dpi = GetDpiForWindow(feed.Handle);
            int nativeBar = GetSystemMetricsForDpi(2, dpi == 0 ? 96 : dpi);
            feed.SetBounds(0, 0, width + nativeBar, height);
            feed.ZoomFactor = (float)Math.Clamp(PanelScale * 96 / (dpi == 0 ? 96 : dpi), 0.25, 3);
            if (ShouldFollowNewest(previous.Position, previous.Maximum))
                ScrollToNewestUpdate();
            else
                ScrollToPixel(previous.Position);
        }

        protected override void OnPaint(PaintEventArgs e) =>
            host.PaintGameChatFrame(e.Graphics, Units(ClientSize.Width), Units(ClientSize.Height),
                PanelScale, "Game Updates");

        void PaintVisibleDate(object? sender, PaintEventArgs e)
        {
            e.Graphics.Clear(FeedBackground);
            if (visibleDate == null) return;
            using var font = new Font("Georgia", Px(13), FontStyle.Regular, GraphicsUnit.Pixel);
            const TextFormatFlags flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;
            int textWidth = TextRenderer.MeasureText(e.Graphics, visibleDate, font, Size.Empty, flags).Width;
            int side = Math.Max(0, (dateBand.Width - textWidth) / 2 - Px(7));
            int y = dateBand.Height / 2;
            using var divider = new Pen(Color.FromArgb(101, 82, 55));
            e.Graphics.DrawLine(divider, 0, y, side, y);
            e.Graphics.DrawLine(divider, dateBand.Width - side, y, dateBand.Width, y);
            TextRenderer.DrawText(e.Graphics, visibleDate, font, dateBand.ClientRectangle,
                Color.FromArgb(217, 196, 156), flags);
        }

        void RefreshScrollDisplay()
        {
            scrollbar.Invalidate();
            string? date = null;
            int first = feed.GetCharIndexFromPosition(new Point(2, 2));
            for (int i = dateDividers.Count - 1; i >= 0; i--)
            {
                var marker = dateDividers[i];
                if (marker.Offset > first) continue;
                // An inline date above the viewport should still label the entry being read.
                if (marker.Offset < first || feed.GetPositionFromCharIndex(marker.Offset).Y < 0)
                    date = marker.Label;
                break;
            }
            if (date == visibleDate) return;
            visibleDate = date;
            dateBand.Invalidate();
        }

        internal void SetDocument(string document)
        {
            var before = ReadScroll();
            bool follow = ShouldFollowNewest(before.Position, before.Maximum);
            feed.Rtf = document;
            dateDividers = FindServerUpdatesDateDividers(feed.Text);
            if (follow)
                ScrollToNewestUpdate();
            else
            {
                newestLandingPosition = null;
                ScrollToPixel(before.Position);
            }
        }

        bool ShouldFollowNewest(int position, int maximum) =>
            position == newestLandingPosition || position >= maximum - Px(12);

        void ScrollToNewestUpdate()
        {
            var handle = feed.Handle;
            if (dateDividers.Count == 0)
                SendMessageW(handle, 0x0115, new IntPtr(7), IntPtr.Zero); // SB_BOTTOM
            else
            {
                int start = dateDividers[^1].Offset;
                // Bring the date into view, then align to its rendered position so the
                // opening lines remain below it even when the entry wraps.
                feed.Select(start, 0);
                feed.ScrollToCaret();
                var scroll = new POINT();
                SendMessageW(handle, 0x04DD, IntPtr.Zero, ref scroll); // EM_GETSCROLLPOS
                int dateTop = feed.GetPositionFromCharIndex(start).Y;
                ScrollToPixel(Math.Max(0, scroll.Y + dateTop - Px(2)));
            }
            newestLandingPosition = ReadScroll().Position;
            RefreshScrollDisplay();
        }

        (int Total, int Page, int Position, int Maximum) ReadScroll()
        {
            var info = new SCROLLINFO { Size = 28, Mask = 7 };
            if (!GetScrollInfo(feed.Handle, 1, ref info)) return (1, 1, 0, 0);
            int total = Math.Max(1, info.Max - info.Min + 1);
            int page = Math.Clamp((int)info.Page, 1, total);
            return (total, page, Math.Max(0, info.Pos - info.Min), total - page);
        }

        void ScrollToThumb(int y)
        {
            var metrics = ReadScroll();
            int height = Units(scrollbar.Height);
            GoldScrollbarThumbY(height, metrics.Total, metrics.Page, metrics.Position, out int thumb);
            double fraction = Math.Clamp((y - dragOffset - 27d) / Math.Max(1, height - 54 - thumb), 0d, 1d);
            ScrollToPixel((int)Math.Round(metrics.Maximum * fraction));
        }

        void ScrollLines(bool up, int lines)
        {
            for (int i = 0; i < lines; i++)
                SendMessageW(feed.Handle, 0x0115, new IntPtr(up ? 0 : 1), IntPtr.Zero);
            RefreshScrollDisplay();
        }

        void ScrollToPixel(int y)
        {
            var point = new POINT { Y = y };
            SendMessageW(feed.Handle, 0x04DE, IntPtr.Zero, ref point);
            RefreshScrollDisplay();
        }

        [StructLayout(LayoutKind.Sequential)]
        struct SCROLLINFO { internal uint Size, Mask; internal int Min, Max; internal uint Page; internal int Pos, TrackPos; }

        [StructLayout(LayoutKind.Sequential)]
        struct POINT { internal int X, Y; }

        [DllImport("user32.dll")] static extern bool GetScrollInfo(IntPtr hwnd, int bar, ref SCROLLINFO info);
        [DllImport("user32.dll")] static extern int GetSystemMetricsForDpi(int index, uint dpi);
        [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr hwnd, uint message, IntPtr wParam, ref POINT lParam);
    }
}
