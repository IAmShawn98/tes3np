using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    IntPtr serverUpdatesParent;
    LatestUpdatesPanel? serverUpdatesPanel;
    string? serverUpdatesDocument;

    void AttachServerUpdatesPanel(IntPtr target)
    {
        if (!ServerUpdatesAuthenticated || !IsWindow(target) || GetParent(target) != owner) return;
        if (target == serverUpdatesParent && serverUpdatesPanel is { IsDisposed: false }) return;
        CloseServerUpdatesPanel();
        try
        {
            serverUpdatesParent = target;
            var panel = serverUpdatesPanel = new LatestUpdatesPanel(this);
            var handle = panel.Handle;
            const int WS_CLIPSIBLINGS = 0x04000000;
            SetWindowLong(handle, GWL_STYLE, (GetWindowLong(handle, GWL_STYLE) | WS_CHILD | WS_CLIPSIBLINGS) & ~WS_POPUP);
            SetParent(handle, target);
            if (GetParent(handle) != target)
                throw new InvalidOperationException("Latest Updates could not attach to the launcher.");
            PositionServerUpdatesPanel();
            panel.SetDocument(serverUpdatesDocument ?? ServerUpdatesStatus("Loading server updates…"));
            ShowWindow(handle, 4); // SW_SHOWNOACTIVATE
        }
        catch (Exception ex)
        {
            Log("SERVER UPDATES | Panel attachment: " + ex.GetType().Name);
            CloseServerUpdatesPanel();
        }
    }

    void PositionServerUpdatesPanel()
    {
        if (serverUpdatesPanel is not { IsDisposed: false } panel) return;
        if (!IsWindow(serverUpdatesParent) || !ServerUpdatesAuthenticated)
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
        readonly RichTextBox feed = new()
        {
            BackColor = FeedBackground, ForeColor = Color.FromArgb(241, 238, 232),
            ReadOnly = true, BorderStyle = BorderStyle.None, DetectUrls = false,
            ScrollBars = RichTextBoxScrollBars.ForcedVertical, TabStop = true
        };
        readonly BufferedScrollbar scrollbar = new();
        int dragOffset = -1;

        internal LatestUpdatesPanel(GameChatWindow host)
        {
            this.host = host;
            DoubleBuffered = true;
            ResizeRedraw = true;
            viewport.Controls.Add(feed);
            Controls.Add(viewport);
            Controls.Add(scrollbar);
            feed.VScroll += (_, _) => scrollbar.Invalidate();
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
            int top = Px(40), bottom = Px(8), left = Px(9);
            int height = Math.Max(1, ClientSize.Height - top - bottom);
            scrollbar.SetBounds(Math.Max(left, ClientSize.Width - Px(26)), top, Px(20), height);
            int width = Math.Max(1, scrollbar.Left - left - Px(3));
            viewport.SetBounds(left, top, width, height);
            // Keep RichEdit's scrollbar range, with its native scroller outside the clipped viewport.
            uint dpi = GetDpiForWindow(feed.Handle);
            int nativeBar = GetSystemMetricsForDpi(2, dpi == 0 ? 96 : dpi);
            feed.SetBounds(0, 0, width + nativeBar, height);
            feed.ZoomFactor = (float)Math.Clamp(PanelScale * 96 / (dpi == 0 ? 96 : dpi), 0.25, 3);
            if (previous.Position >= previous.Maximum - Px(12))
                ScrollToBottom();
            else
                ScrollToPixel(previous.Position);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var graphics = e.Graphics;
            graphics.Clear(Color.FromArgb(164, 128, 69));
            if (host.borderTexture is { } texture)
            {
                using var tiled = new TextureBrush(texture, WrapMode.Tile);
                graphics.FillRectangle(tiled, ClientRectangle);
            }
            int edge = Px(3);
            var inside = Rectangle.Inflate(ClientRectangle, -edge, -edge);
            if (inside.Width <= 0 || inside.Height <= 0) return;
            using var ink = new SolidBrush(FeedBackground);
            graphics.FillRectangle(ink, inside);
            using var trim = new Pen(Color.FromArgb(128, 101, 54));
            graphics.DrawRectangle(trim, inside.X, inside.Y, inside.Width - 1, inside.Height - 1);
            graphics.DrawLine(trim, inside.Left + 1, Px(35), inside.Right - 1, Px(35));
            using var title = new Font("Georgia", Px(18), FontStyle.Regular, GraphicsUnit.Pixel);
            TextRenderer.DrawText(graphics, "Latest Updates", title,
                new Rectangle(inside.Left + Px(6), Px(5), Math.Max(1, inside.Width - Px(12)), Px(28)),
                Color.FromArgb(226, 191, 119),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter |
                TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
        }

        internal void SetDocument(string document)
        {
            var before = ReadScroll();
            bool follow = before.Position >= before.Maximum - Px(12);
            feed.Rtf = document;
            if (follow)
                ScrollToBottom();
            else
                ScrollToPixel(before.Position);
        }

        void ScrollToBottom()
        {
            SendMessageW(feed.Handle, 0x0115, new IntPtr(7), IntPtr.Zero); // SB_BOTTOM
            scrollbar.Invalidate();
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
            scrollbar.Invalidate();
        }

        void ScrollToPixel(int y)
        {
            var point = new POINT { Y = y };
            SendMessageW(feed.Handle, 0x04DE, IntPtr.Zero, ref point);
            scrollbar.Invalidate();
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
