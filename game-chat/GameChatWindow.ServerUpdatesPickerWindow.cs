using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.Text.Json;
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
        if (panel != serverUpdatesPanel || !ServerUpdatesBodyExpanded || !CanShowServerUpdates || discordEnvironment == null ||
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

    async Task ObserveServerUpdatePickerExit(Process picker)
    {
        int result = 0;
        try { await picker.WaitForExitAsync(); result = picker.ExitCode; }
        catch (InvalidOperationException) { }
        finally
        {
            if (serverUpdatePickerProcess == picker)
            {
                serverUpdatePickerProcess = null;
                nextServerUpdatesCheck = DateTime.MinValue;
                if (!closingChat) Log("SERVER UPDATES | Picker closed" + (result == 0 ? "" : " with status " + result));
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

    sealed record PickerViewport(double Left, double Top, double Right, double Bottom, double ViewWidth, double ViewHeight);
    sealed record PickerViewState(PickerViewport? Picker, bool Dismissed);
    enum PickerOpenResult { Opened = 0, NeedsFocus = 1, PageUnavailable = 31, PreparationFailed, TriggerMissing, MenuMissing, InvalidCrop }

    static Rectangle ReactionPickerCrop(PickerViewport view, Size browserSize)
    {
        if (!double.IsFinite(view.ViewWidth) || !double.IsFinite(view.ViewHeight) ||
            view.ViewWidth <= 0 || view.ViewHeight <= 0 ||
            !double.IsFinite(view.Left) || !double.IsFinite(view.Top) ||
            !double.IsFinite(view.Right) || !double.IsFinite(view.Bottom) ||
            browserSize.Width <= 0 || browserSize.Height <= 0) return Rectangle.Empty;

        int left = (int)Math.Floor(Math.Clamp(view.Left / view.ViewWidth, 0, 1) * browserSize.Width);
        int top = (int)Math.Floor(Math.Clamp(view.Top / view.ViewHeight, 0, 1) * browserSize.Height);
        int right = (int)Math.Ceiling(Math.Clamp(view.Right / view.ViewWidth, 0, 1) * browserSize.Width);
        int bottom = (int)Math.Ceiling(Math.Clamp(view.Bottom / view.ViewHeight, 0, 1) * browserSize.Height);
        return right > left && bottom > top ? Rectangle.FromLTRB(left, top, right, bottom) : Rectangle.Empty;
    }

    sealed class DiscordReactionPickerForm : Form
    {
        static readonly Lazy<string> PickerPresentationScript = GameChatWeb.Page("discord-reaction-picker.js");
        static readonly Color PickerBackground = Color.FromArgb(35, 36, 40);
        readonly Panel viewport = new() { Dock = DockStyle.Fill, BackColor = PickerBackground };
        readonly WebView2 browser = new() { DefaultBackgroundColor = PickerBackground };
        readonly Label status = new()
        {
            Dock = DockStyle.Fill, BackColor = PickerBackground, ForeColor = Color.WhiteSmoke,
            TextAlign = ContentAlignment.MiddleCenter, Text = "Opening Discord emoji picker…"
        };
        readonly System.Windows.Forms.Timer pickerWatch = new() { Interval = 275 };
        readonly string postId;
        readonly bool useCacheOptions;
        readonly Rectangle anchor;
        Size browserSize;
        Rectangle lastCrop;
        DateTime focusedAt;
        bool checkingPicker, shownPicker, openingPicker, lostFocus;
        int missingChecks;

        internal DiscordReactionPickerForm(string postId, bool useCacheOptions, Rectangle anchor)
        {
            this.postId = postId;
            this.useCacheOptions = useCacheOptions;
            this.anchor = anchor;
            Text = "Add a reaction - Discord";
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            viewport.Controls.Add(browser);
            Controls.Add(viewport);
            Controls.Add(status);
            status.BringToFront();

            int dpi = Math.Max(96, DeviceDpi);
            PlacePicker(new Size(340 * dpi / 96, 115 * dpi / 96), true);
            Shown += LoadPicker;
            Deactivate += (_, _) => { if (shownPicker || openingPicker) lostFocus = true; };
            Activated += (_, _) => focusedAt = DateTime.UtcNow;
            pickerWatch.Tick += WatchPicker;
            FormClosed += (_, _) => pickerWatch.Dispose();
        }

        void PlacePicker(Size client, bool besidePanel)
        {
            var workArea = Screen.FromRectangle(besidePanel ? anchor : Bounds).WorkingArea;
            var outer = SizeFromClientSize(client);
            outer.Width = Math.Min(outer.Width, workArea.Width);
            outer.Height = Math.Min(outer.Height, workArea.Height);
            int x = besidePanel
                ? (anchor.Right + outer.Width <= workArea.Right ? anchor.Right : anchor.Left - outer.Width)
                : Left;
            int y = besidePanel ? anchor.Top : Top;
            var bounds = new Rectangle(Math.Clamp(x, workArea.Left, workArea.Right - outer.Width),
                Math.Clamp(y, workArea.Top, workArea.Bottom - outer.Height), outer.Width, outer.Height);
            if (Bounds != bounds) Bounds = bounds;
        }

        async void LoadPicker(object? sender, EventArgs args)
        {
            _ = WatchLauncherLifetime(Handle);
            try
            {
                // The native menu needs a normal Discord viewport for its internal layout.
                // That viewport stays the same size when the visible form shrinks to the menu.
                var workArea = Screen.FromRectangle(anchor).WorkingArea;
                int dpi = Math.Max(96, DeviceDpi);
                var chrome = SizeFromClientSize(Size.Empty);
                browserSize = new Size(Math.Min(920 * dpi / 96, Math.Max(1, workArea.Width - chrome.Width)),
                    Math.Min(720 * dpi / 96, Math.Max(1, workArea.Height - chrome.Height)));
                browser.Size = browserSize;

                var options = useCacheOptions ? new CoreWebView2EnvironmentOptions(DiscordCacheArguments) : null;
                var environment = await CoreWebView2Environment.CreateAsync(null, DiscordUserDataFolder, options)
                    .WaitAsync(TimeSpan.FromSeconds(10));
                if (IsDisposed) return;
                await browser.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(10));
                if (IsDisposed) return;

                var core = browser.CoreWebView2;
                ConfigureServerUpdatesBrowser(core);
                await core.AddScriptToExecuteOnDocumentCreatedAsync(PickerPresentationScript.Value);
                if (IsDisposed) return;
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

                    PickerOpenResult result = await OpenAndPresent(core);
                    if (IsDisposed) return;
                    if (result == PickerOpenResult.Opened) pickerWatch.Start();
                    else if (result == PickerOpenResult.NeedsFocus)
                    {
                        lostFocus = true;
                        SetPickerStatus("Click this window to open Discord’s emoji menu.");
                        pickerWatch.Start();
                    }
                    else ShowPickerFailure(result);
                    return;
                }
                ShowPickerFailure(PickerOpenResult.PageUnavailable);
            }
            catch (Exception ex)
            {
                if (!IsDisposed) SetPickerStatus($"Discord could not open the reaction picker (0x{ex.HResult:X8}).");
            }
        }

        static async Task<PickerViewState?> ReadPickerView(CoreWebView2 core)
        {
            string result = await core.ExecuteScriptAsync("window.tes3npReactionPickerView?.()")
                .WaitAsync(TimeSpan.FromSeconds(3));
            return JsonSerializer.Deserialize<PickerViewState>(result);
        }

        async Task<PickerOpenResult> OpenAndPresent(CoreWebView2 core)
        {
            if (IsDisposed || !IsPickerWindowActive()) return PickerOpenResult.NeedsFocus;
            if (!IsServerUpdatesRoute(core.Source) && !IsServerUpdatesMessageRoute(core.Source))
                return PickerOpenResult.PageUnavailable;
            openingPicker = true;
            try
            {
                var existing = await ReadPickerView(core);
                if (IsDisposed || !IsPickerWindowActive()) return PickerOpenResult.NeedsFocus;
                if (existing?.Picker is { } ready && PresentPicker(ready)) return PickerOpenResult.Opened;

                string prepared = await core.ExecuteScriptAsync("window.tes3npPrepareReactionPicker?.() ?? false")
                    .WaitAsync(TimeSpan.FromSeconds(3));
                if (IsDisposed || !IsPickerWindowActive()) return PickerOpenResult.NeedsFocus;
                if (prepared != "true") return PickerOpenResult.PreparationFailed;

                // Let Discord receive focus only after its channel has an opaque cover.
                status.Hide();
                browser.Focus();
                for (int attempt = 0; attempt < 5; attempt++)
                {
                    if (IsDisposed || !IsPickerWindowActive()) return PickerOpenResult.NeedsFocus;
                    if (await RunServerUpdateAction(core, new("picker", postId)) == "\"clicked\"") break;
                    if (attempt == 4) return PickerOpenResult.TriggerMissing;
                    await Task.Delay(200);
                }
                bool measured = false;
                for (int attempt = 0; attempt < 24; attempt++)
                {
                    if (IsDisposed || !IsPickerWindowActive()) return PickerOpenResult.NeedsFocus;
                    var state = await ReadPickerView(core);
                    if (IsDisposed || !IsPickerWindowActive()) return PickerOpenResult.NeedsFocus;
                    if (state?.Picker is { } view)
                    {
                        measured = true;
                        if (PresentPicker(view)) return PickerOpenResult.Opened;
                    }
                    await Task.Delay(150);
                }
                return measured ? PickerOpenResult.InvalidCrop : PickerOpenResult.MenuMissing;
            }
            finally { openingPicker = false; }
        }

        bool PresentPicker(PickerViewport view)
        {
            Rectangle crop = ReactionPickerCrop(view, browserSize);
            if (crop.IsEmpty) return false;
            if (crop != lastCrop)
            {
                // Clip the browser host HWND as well as its parent panel. The full
                // channel is never revealed while the native menu is being cropped.
                var region = CreateRectRgn(crop.Left, crop.Top, crop.Right, crop.Bottom);
                if (region != IntPtr.Zero && SetWindowRgn(browser.Handle, region, true) == 0) DeleteObject(region);
                browser.Location = new Point(-crop.Left, -crop.Top);
                PlacePicker(crop.Size, !shownPicker);
                lastCrop = crop;
            }
            shownPicker = true;
            missingChecks = 0;
            status.Hide();
            return true;
        }

        async void WatchPicker(object? sender, EventArgs args)
        {
            if (IsDisposed || checkingPicker || !IsPickerWindowActive() || browser.CoreWebView2 is not { } core) return;
            checkingPicker = true;
            try
            {
                var state = await ReadPickerView(core);
                if (IsDisposed) return;
                if (state?.Picker is { } view && PresentPicker(view))
                {
                    // Give Discord time to finish its focus transition before
                    // treating a later disappearance as an intentional close.
                    if (IsPickerWindowActive() && DateTime.UtcNow - focusedAt > TimeSpan.FromMilliseconds(750))
                        lostFocus = false;
                    return;
                }
                if (state?.Dismissed == true) { Close(); return; }
                if (++missingChecks < 2) return;
                if (!IsPickerWindowActive())
                {
                    lostFocus = true;
                    SetPickerStatus("The emoji picker will reopen when you return.");
                    return;
                }
                if (!lostFocus) { Close(); return; }

                lostFocus = false;
                SetPickerStatus("Reopening Discord emoji picker…");
                PickerOpenResult result = await OpenAndPresent(core);
                if (IsDisposed || result == PickerOpenResult.Opened) return;
                if (result == PickerOpenResult.NeedsFocus)
                {
                    lostFocus = true;
                    SetPickerStatus("Click this window to reopen Discord’s emoji menu.");
                    return;
                }
                pickerWatch.Stop();
                ShowPickerFailure(result);
            }
            catch (Exception ex)
            {
                if (IsDisposed || !IsPickerWindowActive()) return;
                pickerWatch.Stop();
                SetPickerStatus($"Discord could not display the emoji picker (0x{ex.HResult:X8}).");
            }
            finally { checkingPicker = false; }
        }

        bool IsPickerWindowActive() => IsHandleCreated && GetForegroundWindow() == Handle;

        void ShowPickerFailure(PickerOpenResult result)
        {
            Environment.ExitCode = (int)result;
            SetPickerStatus(result switch
            {
                PickerOpenResult.PageUnavailable => "Discord could not locate this update.",
                PickerOpenResult.PreparationFailed => "The Discord emoji window could not be prepared.",
                PickerOpenResult.TriggerMissing => "Discord did not offer Add Reaction for this update.",
                PickerOpenResult.InvalidCrop => "Discord opened the emoji menu, but its bounds could not be displayed.",
                _ => "Discord’s Add Reaction button was found, but the emoji menu did not appear."
            });
        }

        void SetPickerStatus(string text)
        {
            status.Text = text;
            status.Show();
            status.BringToFront();
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
