using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

// A public map session uses the packaged browser engine, but never starts
// the authenticated chat window or shares its browser data directory.
internal static class ServerMapHost
{
    internal const string MapUrl = "https://map.nerevarineprophecies.com/";

    internal static bool IsMapUri(string? value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
        uri.Scheme == Uri.UriSchemeHttps && uri.IsDefaultPort &&
        uri.UserInfo.Length == 0 &&
        string.Equals(uri.IdnHost, "map.nerevarineprophecies.com", StringComparison.OrdinalIgnoreCase);

    internal static int CheckPolicy()
    {
        string[] allowed = { MapUrl, MapUrl + "?zoom=3#marker", MapUrl + "tiles/1",
            "https://map.nerevarineprophecies.com:443/" };
        string[] denied = { "", "about:blank", "file:///C:/map.html", "http://map.nerevarineprophecies.com/",
            "https://map.nerevarineprophecies.com:444/", "https://map.nerevarineprophecies.com.example.org/",
            "https://map.nerevarineprophecies.com@example.org/", "https://someone@map.nerevarineprophecies.com/",
            "https://discord.com/", "javascript:alert(1)" };
        return allowed.All(IsMapUri) && denied.All(uri => !IsMapUri(uri)) ? 0 : 1;
    }

    static bool IsViewport(IntPtr viewport, uint ownerPid) =>
        viewport != IntPtr.Zero && IsWindow(viewport) &&
        GetWindowThreadProcessId(viewport, out uint actualPid) != 0 && actualPid == ownerPid;

    internal static int Run(string[] args)
    {
        if (args.Length != 3 || !long.TryParse(args[1], out long rawViewport) ||
            !uint.TryParse(args[2], out uint ownerPid) || ownerPid == 0)
            return 2;
        var viewport = new IntPtr(rawViewport);
        if (!IsViewport(viewport, ownerPid)) return 2;

        try
        {
            ApplicationConfiguration.Initialize();
            Application.SetDefaultFont(GameChatTypography.ThemeFont(9, FontStyle.Regular));
            using var window = new Form
            {
                Text = "Server Map",
                FormBorderStyle = FormBorderStyle.None,
                ShowInTaskbar = false,
                StartPosition = FormStartPosition.Manual,
                AutoScaleMode = AutoScaleMode.None,
                BackColor = Color.FromArgb(19, 39, 37)
            };
            using var context = new ApplicationContext();
            using var watch = new System.Windows.Forms.Timer { Interval = 250 };
            var status = new Button
            {
                Dock = DockStyle.Fill, FlatStyle = FlatStyle.Flat,
                BackColor = window.BackColor, ForeColor = Color.FromArgb(225, 189, 121),
                Text = "Loading map...", TabStop = false, UseVisualStyleBackColor = false
            };
            status.FlatAppearance.BorderSize = 0;
            window.Controls.Add(status);
            WebView2? browser = null;
            bool loading = false, failed = false, stopping = false, initialized = false;
            DateTime? navigationDeadline = null;
            IntPtr handle = window.Handle;
            int style = GetWindowLong(handle, GWL_STYLE);
            const int WS_CLIPSIBLINGS = 0x04000000;
            const int WS_CLIPCHILDREN = 0x02000000;
            SetWindowLong(handle, GWL_STYLE, (style | WS_CHILD | WS_CLIPSIBLINGS | WS_CLIPCHILDREN) & ~WS_POPUP);
            SetParent(handle, viewport);
            if (GetParent(handle) != viewport) return 3;

            int previousWidth = -1, previousHeight = -1;
            bool Position()
            {
                if (!IsViewport(viewport, ownerPid) || !IsWindow(handle) || GetParent(handle) != viewport ||
                    !GetClientRect(viewport, out var rect)) return false;
                int width = Math.Max(1, rect.Right - rect.Left), height = Math.Max(1, rect.Bottom - rect.Top);
                if (width == previousWidth && height == previousHeight) return true;
                if (!MoveWindow(handle, 0, 0, width, height, true)) return false;
                previousWidth = width;
                previousHeight = height;
                return true;
            }

            void ShowFailure(WebView2? candidate)
            {
                if (stopping || window.IsDisposed || !ReferenceEquals(browser, candidate)) return;
                failed = true;
                navigationDeadline = null;
                status.Text = "Map unavailable. Click to retry.";
                status.TabStop = true;
                status.BringToFront();
            }

            async Task LoadMap()
            {
                if (loading || stopping || !IsViewport(viewport, ownerPid)) return;
                loading = true;
                failed = false;
                status.Text = "Loading map...";
                status.TabStop = false;
                status.BringToFront();
                navigationDeadline = null;
                WebView2? attempted = null;
                try
                {
                    var previous = browser;
                    browser = null;
                    if (previous != null)
                    {
                        window.Controls.Remove(previous);
                        previous.Dispose();
                    }
                    var candidate = new WebView2
                    {
                        Dock = DockStyle.Fill,
                        DefaultBackgroundColor = window.BackColor
                    };
                    attempted = browser = candidate;
                    window.Controls.Add(candidate);
                    status.BringToFront();
                    var environment = await CoreWebView2Environment.CreateAsync(null,
                        Path.Combine(GameChatWindow.ChatDataRoot, "map-webview2")).WaitAsync(TimeSpan.FromSeconds(20));
                    if (stopping || candidate.IsDisposed || !IsViewport(viewport, ownerPid)) return;
                    await candidate.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(20));
                    if (stopping || candidate.IsDisposed || !IsViewport(viewport, ownerPid)) return;
                    var core = candidate.CoreWebView2;
                    core.Settings.AreDevToolsEnabled = false;
                    core.Settings.AreDefaultContextMenusEnabled = false;
                    core.Settings.IsStatusBarEnabled = false;
                    core.Settings.IsWebMessageEnabled = false;
                    core.Settings.AreHostObjectsAllowed = false;
                    core.Settings.IsPasswordAutosaveEnabled = false;
                    core.Settings.IsGeneralAutofillEnabled = false;
                    core.NavigationStarting += (_, e) => e.Cancel = !IsMapUri(e.Uri);
                    core.NewWindowRequested += (_, e) => e.Handled = true;
                    core.DownloadStarting += (_, e) => e.Cancel = true;
                    core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
                    core.NavigationCompleted += (_, e) =>
                    {
                        if (stopping || candidate.IsDisposed || !ReferenceEquals(browser, candidate)) return;
                        if (e.IsSuccess && IsMapUri(core.Source))
                        {
                            failed = false;
                            navigationDeadline = null;
                            status.TabStop = false;
                            candidate.BringToFront();
                        }
                        else if (e.WebErrorStatus != CoreWebView2WebErrorStatus.OperationCanceled)
                            ShowFailure(candidate);
                    };
                    core.ProcessFailed += (_, _) => ShowFailure(candidate);
                    navigationDeadline = DateTime.UtcNow.AddSeconds(30);
                    core.Navigate(MapUrl);
                }
                catch (Exception)
                {
                    ShowFailure(attempted);
                }
                finally { loading = false; }
            }

            status.Click += async (_, _) => { if (failed) await LoadMap(); };
            window.FormClosed += (_, _) => { stopping = true; context.ExitThread(); };
            watch.Tick += async (_, _) =>
            {
                if (!Position())
                {
                    stopping = true;
                    watch.Stop();
                    context.ExitThread();
                    return;
                }
                if (navigationDeadline is DateTime deadline && DateTime.UtcNow >= deadline)
                    ShowFailure(browser);
                if (!initialized)
                {
                    initialized = true;
                    await LoadMap();
                }
            };
            if (!Position()) return 3;
            // Mount only inside the existing native viewport; never display
            // an independent top-level browser or activate the launcher.
            ShowWindow(handle, 4); // SW_SHOWNOACTIVATE
            watch.Start();
            Application.Run(context);
            stopping = true;
            watch.Stop();
            return 0;
        }
        catch (Exception) { return 4; }
    }
}
