using System.Drawing;

internal sealed partial class GameChatWindow
{
    void InitializeChatSurface()
    {
        Paint += PaintChatWindow;
        ShowInTaskbar = false;
        BackColor = System.Drawing.Color.Black;
        // Native child window alpha lets launcher artwork show through opaque Discord layers.
        chatViewport.Controls.Add(web);
        frameSurface.Paint += PaintChatFrame;
        // The frame and text are painted on one surface; no child can obscure its edges.
        frameSurface.Controls.Add(chatViewport);
        messageClip.Controls.Add(nativeMessages);
        messageClip.Controls.Add(messageBrowser);
        nativeMessages.BringToFront();
        frameSurface.Controls.Add(messageClip);
        frameSurface.Controls.Add(goldScrollbar);
        goldScrollbar.Paint += PaintChatScrollbar;
        AttachScrollbarInput();
        // Keep the native scrollbar hidden until the first actual feed.
        goldScrollbar.Visible = false;
        nativeMessages.Visible = true;
        nativeMessages.Text = "Connecting to live chat...";
        messageClip.BringToFront();
        goldScrollbar.BringToFront();
        Controls.Add(frameSurface);
        // Browser is inset; native host draws its own border outside the browser rectangle.
        Resize += (_, _) => FitWebView();
    }

    void PaintChatWindow(object? sender, PaintEventArgs e)
    {
        var g = e.Graphics;
        int w = ChatUnits(ClientSize.Width), h = ChatUnits(ClientSize.Height);
        g.Clear(System.Drawing.Color.FromArgb(9, 8, 7));
        g.ScaleTransform((float)chatScale, (float)chatScale);
        // Layered weathered-metal rim, dark recess, and engraved highlight.
        using var rim = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(91, 65, 31));
        using var metal = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(168, 131, 70));
        using var highlight = new System.Drawing.Pen(System.Drawing.Color.FromArgb(219, 185, 113), 2);
        using var shadow = new System.Drawing.Pen(System.Drawing.Color.FromArgb(37, 26, 15), 3);
        using var titleFill = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(16, 12, 9));
        using var gold = new System.Drawing.SolidBrush(System.Drawing.Color.FromArgb(216, 182, 112));
        using var titleFont = new Font("Georgia", 14, FontStyle.Bold);
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
    }

    void PaintChatFrame(object? sender, PaintEventArgs e)
    {
        PaintGameChatFrame(e.Graphics, ChatUnits(frameSurface.Width), ChatUnits(frameSurface.Height),
            chatScale, "Live Game Chat");
    }

    void PaintGameChatFrame(Graphics g, int w, int h, double scale, string title)
    {
        if (w < 80 || h < 100) return;
        g.Clear(System.Drawing.Color.FromArgb(13, 11, 9));
        g.ScaleTransform((float)scale, (float)scale);
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
        using var headingFont = new Font("Georgia", 13, FontStyle.Regular);
        var titleSize = g.MeasureString(title, headingFont);
        g.FillRectangle(black, (w - titleSize.Width) / 2 - 14, 8, titleSize.Width + 28, 43);
        using var centeredTitle = new System.Drawing.StringFormat
        {
            Alignment = System.Drawing.StringAlignment.Center,
            LineAlignment = System.Drawing.StringAlignment.Center
        };
        g.DrawString(title, headingFont, bright,
            new System.Drawing.RectangleF((w - titleSize.Width) / 2 - 14, 8,
                titleSize.Width + 28, 43), centeredTitle);
        // The real goldScrollbar is the only scrollbar. Drawing a
        // second fake track and thumb on this background left stale
        // artwork visible while the control was hidden during sign-in.
    }

    int lastThumbY = -1, lastThumbHeight = -1;

    void PaintChatScrollbar(object? sender, PaintEventArgs e)
    {
        int height = ChatUnits(goldScrollbar.ClientSize.Height);
        lastThumbY = ChatThumbY(height, out lastThumbHeight);
        PaintGoldScrollbar(e.Graphics, height, chatScale, lastThumbY, lastThumbHeight);
    }

    void PaintGoldScrollbar(Graphics g, int h, double scale, int thumbY, int thumbHeight)
    {
        const int w = 20;
        g.Clear(Color.Black);
        if (h < 65 || scrollbarTexture == null) return;
        g.ScaleTransform((float)scale, (float)scale);
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
    }

    void AttachScrollbarInput()
    {
        // With WS_VSCROLL disabled the RichEdit control does not reliably
        // perform its default wheel scrolling. Scroll its text explicitly.
        void ScrollWheelMessages(MouseEventArgs e)
        {
            if (!chatOpen || !messageBrowserReady || e.Delta == 0) return;
            lastChatActivity = DateTime.Now;
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
            if (!chatOpen || !messageBrowserReady || e.Button != MouseButtons.Left) return;
            lastChatActivity = DateTime.Now;
            int y = ChatUnits(e.Y);
            int height = ChatUnits(goldScrollbar.Height);
            if (y < 27 || y >= height - 27)
            {
                ScrollHtml(y < 27 ? -66 : 66);
            }
            else
            {
                int thumbY = ChatThumbY(height, out int thumbHeight);
                dragOffset = y >= thumbY && y < thumbY + thumbHeight
                    ? y - thumbY : thumbHeight / 2;
                goldScrollbar.Capture = true;
                ScrollChatToThumb(y, dragOffset);
            }
            goldScrollbar.Invalidate();
            RequestOlderMessages();
        };
        goldScrollbar.MouseMove += (_, e) =>
        {
            if (!chatOpen || !goldScrollbar.Capture || dragOffset < 0 || e.Button != MouseButtons.Left) return;
            lastChatActivity = DateTime.Now;
            ScrollChatToThumb(ChatUnits(e.Y), dragOffset);
        };
        goldScrollbar.MouseCaptureChanged += (_, _) =>
        {
            if (!goldScrollbar.Capture) dragOffset = -1;
        };
        goldScrollbar.MouseUp += (_, _) =>
        {
            dragOffset = -1;
            goldScrollbar.Capture = false;
            // HTML scrolling ends when mouse capture is released.
            goldScrollbar.Invalidate();
        };
    }
}
