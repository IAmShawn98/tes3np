using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const string DiscordReactionPickerMode = "--discord-reaction-picker";
    Process? serverUpdatePickerProcess;

    async Task<string?> ShowServerUpdatePicker(LatestUpdatesPanel panel, string postId)
    {
        await Task.Yield();
        if (panel != serverUpdatesPanel || !CanShowServerUpdates || discordEnvironment == null ||
            !ulong.TryParse(postId, NumberStyles.None, CultureInfo.InvariantCulture, out ulong messageId) || messageId == 0 ||
            !displayedServerUpdates.Any(post => post.Id == postId))
            return "This update is no longer available.";

        StopServerUpdatePicker();
        try
        {
            // The picker reuses the installed Chat Host executable in a separate process.
            // There is no native parent, synchronous focus call, or shared UI thread.
            var start = new ProcessStartInfo(Path.Combine(AppContext.BaseDirectory, "tes3np.ChatHost.exe"))
            {
                UseShellExecute = false,
                RedirectStandardInput = true
            };
            var anchor = panel.RectangleToScreen(panel.ClientRectangle);
            start.ArgumentList.Add(DiscordReactionPickerMode);
            start.ArgumentList.Add(postId);
            start.ArgumentList.Add(discordUsesCacheOptions ? "cache" : "default");
            foreach (int value in new[] { anchor.Left, anchor.Top, anchor.Right, anchor.Bottom })
                start.ArgumentList.Add(value.ToString(CultureInfo.InvariantCulture));

            var picker = Process.Start(start) ?? throw new InvalidOperationException("Could not start the reaction picker.");
            serverUpdatePickerProcess = picker;
            _ = ObserveServerUpdatePickerExit(picker);
            Log("SERVER UPDATES | Discord picker started");
            return null;
        }
        catch (Exception ex)
        {
            Log("SERVER UPDATES | Picker startup: " + ex.GetType().Name);
            return "The Discord emoji picker could not open.";
        }
    }

    bool IsServerUpdatePickerForeground(IntPtr window) =>
        window != IntPtr.Zero && serverUpdatePickerProcess is { } picker &&
        GetWindowThreadProcessId(window, out uint processId) != 0 && processId == (uint)picker.Id;

    async Task ObserveServerUpdatePickerExit(Process picker)
    {
        try { await picker.WaitForExitAsync(); }
        catch (InvalidOperationException) { }
        finally
        {
            if (serverUpdatePickerProcess == picker)
            {
                serverUpdatePickerProcess = null;
                nextServerUpdatesCheck = DateTime.MinValue;
                if (!closingChat) Log("SERVER UPDATES | Discord picker closed");
            }
            picker.Dispose();
        }
    }

    void StopServerUpdatePicker()
    {
        var picker = serverUpdatePickerProcess;
        serverUpdatePickerProcess = null;
        if (picker == null) return;
        try { picker.StandardInput.Close(); }
        catch (InvalidOperationException) { }
        catch (IOException) { }
        nextServerUpdatesCheck = DateTime.MinValue;
    }

    internal static bool TryRunDiscordReactionPicker(string[] args)
    {
        if (args.Length == 0 || args[0] != DiscordReactionPickerMode) return false;
        if (args.Length != 7 || !ulong.TryParse(args[1], NumberStyles.None, CultureInfo.InvariantCulture, out ulong id) ||
            id == 0 || args[2] is not ("cache" or "default") || !Console.IsInputRedirected) return true;

        int[] bounds = new int[4];
        for (int i = 0; i < bounds.Length; i++)
            if (!int.TryParse(args[i + 3], NumberStyles.Integer, CultureInfo.InvariantCulture, out bounds[i])) return true;
        ApplicationConfiguration.Initialize();
        using var picker = new DiscordReactionPickerForm(args[1], args[2] == "cache",
            Rectangle.FromLTRB(bounds[0], bounds[1], bounds[2], bounds[3]));
        Application.Run(picker);
        return true;
    }

    sealed class DiscordReactionPickerForm : Form
    {
        readonly WebView2 browser = new()
        {
            Dock = DockStyle.Fill, DefaultBackgroundColor = Color.FromArgb(31, 31, 34)
        };
        readonly Label status = new()
        {
            Dock = DockStyle.Fill, BackColor = Color.FromArgb(31, 31, 34), ForeColor = Color.WhiteSmoke,
            TextAlign = ContentAlignment.MiddleCenter, Text = "Opening Discord…"
        };
        readonly string postId;
        readonly bool useCacheOptions;

        internal DiscordReactionPickerForm(string postId, bool useCacheOptions, Rectangle anchor)
        {
            this.postId = postId;
            this.useCacheOptions = useCacheOptions;
            Text = "Add a reaction - Discord";
            FormBorderStyle = FormBorderStyle.SizableToolWindow;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            Controls.Add(browser);
            Controls.Add(status);
            status.BringToFront();

            var workArea = Screen.FromRectangle(anchor).WorkingArea;
            int dpi = Math.Max(96, DeviceDpi);
            int width = Math.Min(920 * dpi / 96, workArea.Width);
            int height = Math.Min(720 * dpi / 96, workArea.Height);
            int x = anchor.Right + width <= workArea.Right ? anchor.Right : anchor.Left - width;
            Bounds = new Rectangle(Math.Clamp(x, workArea.Left, workArea.Right - width),
                Math.Clamp(anchor.Top, workArea.Top, workArea.Bottom - height), width, height);
            Shown += LoadPicker;
        }

        async void LoadPicker(object? sender, EventArgs args)
        {
            _ = WatchLauncherLifetime(Handle);
            bool postVisible = false;
            try
            {
                // Do not create a second sign-in profile. Match the running host's WebView2 options.
                var options = useCacheOptions ? new CoreWebView2EnvironmentOptions(DiscordCacheArguments) : null;
                var environment = await CoreWebView2Environment.CreateAsync(null, DiscordUserDataFolder, options)
                    .WaitAsync(TimeSpan.FromSeconds(10));
                if (IsDisposed) return;
                await browser.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(10));
                if (IsDisposed) return;

                var core = browser.CoreWebView2;
                ConfigureServerUpdatesBrowser(core);
                string target = ServerUpdatesChannel + "/" + postId;
                core.Navigate(target);
                var deadline = DateTime.UtcNow.AddSeconds(12);
                while (DateTime.UtcNow < deadline)
                {
                    await Task.Delay(250);
                    if (IsDisposed) return;
                    if (!IsServerUpdatesRoute(core.Source) && !IsServerUpdatesMessageRoute(core.Source)) continue;
                    if (await RunServerUpdateAction(core, new("picker-target", postId)) != "\"ready\"") continue;
                    if (IsDisposed) return;

                    status.Hide();
                    postVisible = true;
                    if (ContainsFocus) browser.Focus();
                    for (int attempt = 0; attempt < 3; attempt++)
                    {
                        if (await RunServerUpdateAction(core, new("picker", postId)) == "\"clicked\"") return;
                        await Task.Delay(175);
                        if (IsDisposed) return;
                    }
                    ShowManualHelp();
                    return;
                }
                status.Text = "Discord could not locate this update. Close this window and try again.";
            }
            catch (Exception ex)
            {
                if (IsDisposed) return;
                if (postVisible) { ShowManualHelp(); return; }
                status.Text = $"Discord could not open the reaction picker (0x{ex.HResult:X8}).";
                status.Show();
                status.BringToFront();
            }
        }

        void ShowManualHelp()
        {
            status.Text = "Use Add Reaction on the Discord post.";
            status.Dock = DockStyle.Bottom;
            status.Height = 30 * DeviceDpi / 96;
            status.Show();
        }

        static Task WatchLauncherLifetime(IntPtr window) => Task.Run(async () =>
        {
            // The parent writes nothing to this pipe. EOF also covers parent process termination.
            using var input = Console.OpenStandardInput();
            try { input.ReadByte(); }
            catch (IOException) { }
            PostMessage(window, 0x0010, IntPtr.Zero, IntPtr.Zero); // WM_CLOSE
            await Task.Delay(TimeSpan.FromSeconds(3)).ConfigureAwait(false);
            // Only the picker process runs this mode. A hung renderer must not leave it orphaned.
            Environment.Exit(0);
        });
    }
}
