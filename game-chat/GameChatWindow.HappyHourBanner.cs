using System.Drawing;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
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
        if (happyHourEndsAt <= DateTimeOffset.UtcNow || !IsWindow(owner))
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

    // A genuine Discord activation goes directly to the docked banner.
    // There is intentionally no separate large WinForms notification.
    void ShowHappyHourBannerForMessage(ulong activationId)
    {
        if (activationId == 0 || closingChat || IsDisposed) return;
        var ends = DiscordTimestamp(activationId).AddHours(1);
        if (activationId <= lastHappyHourMessageId ||
            ends <= DateTimeOffset.UtcNow) return;

        lastHappyHourMessageId = activationId;
        happyHourEndsAt = ends;

        happyHourTicker?.Stop();
        happyHourTicker?.Dispose();
        happyHourTicker = null;
        if (happyHourBanner is { IsDisposed: false }) happyHourBanner.Close();
        happyHourBanner = null;

        var ticker = new System.Windows.Forms.Timer { Interval = 1000 };
        ticker.Tick += (_, _) => {
            if (happyHourEndsAt <= DateTimeOffset.UtcNow) {
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
}
