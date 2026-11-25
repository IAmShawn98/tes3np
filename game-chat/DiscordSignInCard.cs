using System.Drawing;
using static GameChatNative;

internal sealed class DiscordSignInCard : Form
{
    public const int BaseWidth = 520, BaseHeight = 750;
    public const int MinimumWidth = 360, MinimumHeight = 440;
    readonly TableLayoutPanel shell = new()
    {
        Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3,
        Padding = new Padding(12), BackColor = Color.FromArgb(27, 20, 11)
    };
    readonly Label heading = new()
    {
        Text = "Sign In Required", Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleCenter,
        ForeColor = Color.FromArgb(226, 191, 119)
    };
    readonly Label help = new()
    {
        Text = "Connect your Discord account to access this feature.",
        Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter,
        ForeColor = Color.FromArgb(237, 225, 201)
    };
    readonly Button close = new()
    {
        Text = "×", FlatStyle = FlatStyle.Flat,
        BackColor = Color.FromArgb(27, 20, 11),
        ForeColor = Color.FromArgb(226, 191, 119),
        Cursor = Cursors.Hand, TabStop = false
    };
    public Panel BrowserPanel { get; } = new() { Dock = DockStyle.Fill, BackColor = Color.Black };
    readonly Font headingFont = GameChatTypography.ThemeFont(16, FontStyle.Bold);
    readonly Font closeFont = new("Segoe UI", 14, FontStyle.Bold);
    bool layoutApplied;
    bool parked;
    bool headerPrompt;

    protected override bool ShowWithoutActivation => parked;

    public DiscordSignInCard(Action dismiss)
    {
        Text = "tes3np - Sign In Required";
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.FromArgb(197, 164, 92);
        ForeColor = Color.FromArgb(237, 225, 201);
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        Padding = new Padding(2);
        heading.Font = headingFont;
        heading.UseCompatibleTextRendering = true;
        close.Font = closeFont;
        shell.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 45));
        shell.RowStyles.Add(new RowStyle(SizeType.Absolute, 50));
        shell.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        shell.Controls.Add(heading, 0, 0);
        shell.Controls.Add(help, 0, 1);
        shell.Controls.Add(BrowserPanel, 0, 2);
        Controls.Add(shell);
        close.FlatAppearance.BorderSize = 0;
        close.Click += (_, _) => dismiss();
        Controls.Add(close);
        close.BringToFront();
    }

    public void Park(IntPtr launcher)
    {
        bool returnFocus = GetForegroundWindow() == Handle;
        parked = true;
        UpdateParkedLayout();
        if (!Visible) Show();
        if (returnFocus) SetForegroundWindow(launcher);
    }

    public bool UpdateParkedLayout()
    {
        if (!parked) return false;
        var desktop = SystemInformation.VirtualScreen;
        int dpi = Math.Max(96, DeviceDpi);
        // Keep a desktop-size Discord viewport alive in its original HWND.
        // Outside the virtual screen it cannot cover the launcher or take input.
        ApplyLayout(new Rectangle(desktop.Right + 32, desktop.Top, 1280 * dpi / 96, 900 * dpi / 96));
        return true;
    }

    public void PrepareSignIn()
    {
        if (!parked) return;
        Hide();
        parked = false;
    }

    public void SetSignInPrompt(bool fromHeader)
    {
        if (headerPrompt == fromHeader) return;
        headerPrompt = fromHeader;
        heading.Text = fromHeader ? "Sign In to Discord" : "Sign In Required";
        help.Text = fromHeader ? "Connect your Discord account to the TES3NP launcher."
            : "Connect your Discord account to access this feature.";
        Text = "tes3np - " + heading.Text;
        layoutApplied = false;
    }

    public void ApplyLayout(Rectangle bounds)
    {
        if (layoutApplied && Bounds == bounds) return;
        if (layoutApplied && Size == bounds.Size)
        {
            Location = bounds.Location;
            return;
        }
        SuspendLayout();
        shell.SuspendLayout();
        try
        {
            // Preserve the default header rows. Add height when the
            // Windows-sized help text needs to wrap in a narrow card.
            int textWidth = Math.Max(1, bounds.Width -
                Padding.Horizontal - shell.Padding.Horizontal - help.Margin.Horizontal);
            var promptSize = TextRenderer.MeasureText(help.Text, help.Font,
                new Size(textWidth, bounds.Height), TextFormatFlags.WordBreak);
            shell.RowStyles[0].Height = Math.Max(45, heading.Font.Height + heading.Margin.Vertical);
            shell.RowStyles[1].Height = Math.Max(50, promptSize.Height + help.Margin.Vertical);
            Bounds = bounds;
            int closeSize = Math.Max(29, close.Font.Height);
            close.SetBounds(bounds.Width - closeSize - 10, 6, closeSize, closeSize);
            layoutApplied = true;
        }
        finally
        {
            shell.ResumeLayout(true);
            ResumeLayout(true);
        }
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (!disposing) return;
        headingFont.Dispose();
        closeFont.Dispose();
    }
}
