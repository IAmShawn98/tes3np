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

    // A normal activatable popup avoids cross-process static-control hit testing.
    sealed class MapBrowserWindow : Form
    {
        protected override bool ShowWithoutActivation => true;
    }

    sealed class MapFrameOwner(IntPtr handle) : IWin32Window
    {
        public IntPtr Handle { get; } = handle;
    }

    internal static int Run(string[] args)
    {
        if (args.Length != 3 || !long.TryParse(args[1], out long rawViewport) ||
            !uint.TryParse(args[2], out uint ownerPid) || ownerPid == 0)
            return 2;
        var viewport = new IntPtr(rawViewport);
        if (!IsViewport(viewport, ownerPid)) return 2;
        IntPtr frame = GetParent(viewport);
        if (!IsViewport(frame, ownerPid)) return 2;

        try
        {
            ApplicationConfiguration.Initialize();
            Application.SetDefaultFont(GameChatTypography.ThemeFont(9, FontStyle.Regular));
            using var window = new MapBrowserWindow
            {
                Text = "Server Map",
                FormBorderStyle = FormBorderStyle.None,
                ShowInTaskbar = false,
                StartPosition = FormStartPosition.Manual,
                AutoScaleMode = AutoScaleMode.None,
                BackColor = Color.FromArgb(19, 39, 37)
            };
            using var context = new ApplicationContext();
            using var watch = new System.Windows.Forms.Timer { Interval = 50 };
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
            SetWindowLong(handle, GWL_STYLE, (style | WS_POPUP) & ~WS_CHILD);
            const int WS_EX_NOACTIVATE = 0x08000000, WS_EX_TRANSPARENT = 0x20;
            int exStyle = GetWindowLongEx(handle, GWL_EXSTYLE);
            SetWindowLongEx(handle, GWL_EXSTYLE,
                (exStyle | WS_EX_TOOLWINDOW) & ~(WS_EX_APPWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT));
            SetNativeWindowOwner(handle, frame);
            if (GetWindow(handle, 4) != frame) return 3;
            var frameOwner = new MapFrameOwner(frame);

            bool Position()
            {
                if (!IsViewport(viewport, ownerPid) || !IsViewport(frame, ownerPid) ||
                    GetParent(viewport) != frame || !IsWindow(handle) ||
                    GetWindow(handle, 4) != frame) return false;
                if (!IsWindowVisible(viewport) || !IsWindowVisible(frame) ||
                    IsIconic(frame) || !IsWindowEnabled(frame))
                {
                    if (window.Visible) window.Hide();
                    return true;
                }
                if (!GetWindowRect(viewport, out var rect)) return false;
                int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
                if (width <= 0 || height <= 0) return true;
                if (!GetWindowRect(handle, out var current) ||
                    current.Left != rect.Left || current.Top != rect.Top ||
                    current.Right != rect.Right || current.Bottom != rect.Bottom)
                {
                    const uint SWP_NOZORDER_NOACTIVATE = 0x0004 | 0x0010;
                    if (!SetWindowPos(handle, IntPtr.Zero, rect.Left, rect.Top, width, height,
                        SWP_NOZORDER_NOACTIVATE)) return false;
                }
                // Managed visibility keeps WebView2 and WinForms input state in sync.
                if (!window.Visible || !IsWindowVisible(handle))
                {
                    // The native owner can hide an owned window before the
                    // managed Visible flag catches up. Reconcile both states.
                    if (window.Visible) window.Hide();
                    window.Show(frameOwner);
                }
                return GetWindow(handle, 4) == frame;
            }

            void ShowFailure(WebView2? candidate)
            {
                if (stopping || window.IsDisposed || !ReferenceEquals(browser, candidate)) return;
                failed = true;
                navigationDeadline = null;
                status.Text = "Map unavailable. Click to retry.";
                status.TabStop = true;
                if (candidate is { IsDisposed: false }) candidate.Hide();
                status.Show();
                status.BringToFront();
            }

            async Task LoadMap()
            {
                if (loading || stopping || !IsViewport(viewport, ownerPid)) return;
                loading = true;
                failed = false;
                status.Text = "Loading map...";
                status.TabStop = false;
                status.Show();
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
                            status.Hide();
                            candidate.Show();
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
                if (!initialized && window.Visible)
                {
                    initialized = true;
                    await LoadMap();
                }
            };
            if (!Position()) return 3;
            // Position has presented the owned browser without stealing focus.
            watch.Start();
            Application.Run(context);
            stopping = true;
            watch.Stop();
            return 0;
        }
        catch (Exception) { return 4; }
    }
}
