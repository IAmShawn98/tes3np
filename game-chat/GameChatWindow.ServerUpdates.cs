using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const string ServerUpdatesChannel = "https://discord.com/channels/509601787901116437/510245417657827363";
    const uint ServerUpdatesData = 0x833B;
    const int ServerUpdateBodyLimit = 3800;
    static readonly Lazy<string> ExtractServerUpdates = GameChatWeb.Page("extract-server-updates.js");

    sealed class ServerUpdatesWindow : Form
    {
        internal WebView2 Browser { get; } = new() { Dock = DockStyle.Fill, TabStop = false };

        internal ServerUpdatesWindow()
        {
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            FormBorderStyle = FormBorderStyle.None;
            Controls.Add(Browser);
            PositionOffScreen();
        }

        protected override bool ShowWithoutActivation => true;

        internal void PositionOffScreen()
        {
            var desktop = SystemInformation.VirtualScreen;
            int dpi = Math.Max(96, DeviceDpi);
            var placement = new Rectangle(desktop.Right + 32, desktop.Top, 1200 * dpi / 96, 960 * dpi / 96);
            if (Bounds != placement) Bounds = placement;
        }
    }

    sealed record ServerUpdate(string Id, string Body);

    ServerUpdatesWindow? serverUpdatesWindow;
    DateTime nextServerUpdatesCheck;
    DateTime serverUpdatesReadyBy;
    bool readingServerUpdates;
    string? publishedServerUpdates;

    bool ServerUpdatesAuthenticated => !closingChat && !IsDisposed && discordAccountStatus == DiscordAccountStatus.SignedIn;

    async Task RefreshServerUpdates()
    {
        if (!ServerUpdatesAuthenticated || discordAccountDirty || readingServerUpdates || DateTime.UtcNow < nextServerUpdatesCheck ||
            discordEnvironment is not { } environment) return;
        readingServerUpdates = true;
        nextServerUpdatesCheck = DateTime.UtcNow.AddSeconds(1);
        ServerUpdatesWindow? source = serverUpdatesWindow;
        try
        {
            if (source == null)
            {
                // Keep the updates channel in the same launcher-only profile, separate
                // from the live chat DOM and from the chat dock's visibility.
                source = serverUpdatesWindow = new ServerUpdatesWindow();
                SetNativeWindowOwner(source.Handle, owner);
                source.Show();
                await source.Browser.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(8));
                if (!ServerUpdatesAuthenticated || source != serverUpdatesWindow || source.IsDisposed) return;
                var core = source.Browser.CoreWebView2;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.IsWebMessageEnabled = false;
                core.NewWindowRequested += (_, e) => e.Handled = true;
                core.DownloadStarting += (_, e) => e.Cancel = true;
                core.NavigationStarting += (_, e) =>
                {
                    e.Cancel = !Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) ||
                        uri.Scheme != Uri.UriSchemeHttps || uri.Host != "discord.com" ||
                        !uri.IsDefaultPort || uri.UserInfo.Length != 0;
                };
                serverUpdatesReadyBy = DateTime.UtcNow.AddSeconds(15);
                core.Navigate(ServerUpdatesChannel);
                return;
            }
            source.PositionOffScreen();
            var channel = source.Browser.CoreWebView2;
            if (IsServerUpdatesRoute(channel.Source))
            {
                string result = await channel.ExecuteScriptAsync(ExtractServerUpdates.Value).WaitAsync(TimeSpan.FromSeconds(3));
                if (!ServerUpdatesAuthenticated || source != serverUpdatesWindow || source.IsDisposed ||
                    !IsServerUpdatesRoute(channel.Source)) return;
                var updates = JsonSerializer.Deserialize<ServerUpdate[]>(result);
                if (updates != null)
                {
                    string text = FormatServerUpdates(updates);
                    PublishServerUpdates(text);
                    serverUpdatesReadyBy = DateTime.UtcNow.AddSeconds(15);
                    nextServerUpdatesCheck = DateTime.UtcNow.AddSeconds(publishedServerUpdates == text ? 5 : 1);
                    return;
                }
            }
            if (DateTime.UtcNow >= serverUpdatesReadyBy)
                RecoverServerUpdates("channel unavailable");
        }
        catch (Exception ex)
        {
            if (ServerUpdatesAuthenticated && source == serverUpdatesWindow)
                RecoverServerUpdates(ex.GetType().Name);
        }
        finally { readingServerUpdates = false; }
    }

    static bool IsServerUpdatesRoute(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.UserInfo.Length == 0 && uri.IsDefaultPort &&
        string.Equals(uri.GetLeftPart(UriPartial.Path).TrimEnd('/'), ServerUpdatesChannel, StringComparison.OrdinalIgnoreCase);

    static string FormatServerUpdates(ServerUpdate[] updates)
    {
        var recent = new SortedDictionary<ulong, string>();
        foreach (var update in updates)
        {
            if (update == null || !ulong.TryParse(update.Id, out ulong id) || id == 0 || string.IsNullOrWhiteSpace(update.Body))
                continue;
            string body = Regex.Replace(update.Body.Replace("\r\n", "\n").Replace('\r', '\n'),
                @"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]", "").Trim().Replace("\n", "\r\n");
            if (body.Length > ServerUpdateBodyLimit)
                body = body[..ServerUpdateBodyLimit].TrimEnd() + "…";
            if (body.Length != 0) recent[id] = body;
        }
        if (recent.Count == 0) return "No server updates to display.";
        return string.Join("\r\n\r\n", recent.Reverse().Take(8).Select(update =>
            $"{DiscordTimestamp(update.Key).ToLocalTime():MMM d, yyyy • h:mm tt}\r\n{update.Value}"));
    }

    void PublishServerUpdates(string text)
    {
        if (!ServerUpdatesAuthenticated || !IsHandleCreated || !IsWindow(owner) || text == publishedServerUpdates)
            return;
        byte[] bytes = Encoding.Unicode.GetBytes(text);
        var pin = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            var data = new COPYDATASTRUCT
            {
                dwData = new IntPtr(ServerUpdatesData), cbData = bytes.Length, lpData = pin.AddrOfPinnedObject()
            };
            var sent = SendCopyDataTimeout(owner, 0x004A, Handle, ref data, 0x0003, 200, out var result);
            if (sent != IntPtr.Zero && result != IntPtr.Zero) publishedServerUpdates = text;
        }
        finally { pin.Free(); }
    }

    void RecoverServerUpdates(string reason)
    {
        Log("SERVER UPDATES | " + reason);
        var previous = serverUpdatesWindow;
        serverUpdatesWindow = null;
        previous?.Dispose();
        PublishServerUpdates("Server updates are unavailable.");
        nextServerUpdatesCheck = DateTime.UtcNow.AddSeconds(30);
    }

    void ResetServerUpdates()
    {
        var previous = serverUpdatesWindow;
        serverUpdatesWindow = null;
        nextServerUpdatesCheck = DateTime.MinValue;
        publishedServerUpdates = null;
        previous?.Dispose();
    }
}
