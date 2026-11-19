using System.Drawing;
using System.Globalization;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal sealed partial class GameChatWindow
{
    const string ServerUpdatesChannel = "https://discord.com/channels/509601787901116437/510245417657827363";
    const string ServerUpdatesDateFormat = "MMMM d, yyyy";
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

    sealed record ServerUpdate(string Id, ServerUpdateBlock[]? Blocks, ServerUpdateReaction[]? Reactions);
    sealed record ServerUpdateReaction(string Key, string Name, string? Image, int Count, bool Mine);
    sealed record ServerUpdateBlock(string? Style, int Number, ServerUpdateRun[]? Runs);
    sealed record ServerUpdateRun(string? Text, bool Bold);

    ServerUpdatesWindow? serverUpdatesWindow;
    DateTime nextServerUpdatesCheck;
    DateTime serverUpdatesReadyBy;
    TaskCompletionSource? activeServerUpdatesRead;
    ulong latestServerUpdateId;
    ulong dismissedServerUpdateId = ReadServerUpdatesDismissal();

    bool ServerUpdatesAuthenticated => !closingChat && !IsDisposed && discordAccountStatus == DiscordAccountStatus.SignedIn;
    bool CanShowServerUpdates => ServerUpdatesAuthenticated && latestServerUpdateId > dismissedServerUpdateId;
    static string ServerUpdatesDismissalPath => Path.Combine(ChatDataRoot, "game-updates-dismissed.txt");

    static ulong ReadServerUpdatesDismissal()
    {
        try
        {
            return ulong.TryParse(File.ReadAllText(ServerUpdatesDismissalPath), NumberStyles.None,
                CultureInfo.InvariantCulture, out ulong id) ? id : 0;
        }
        catch (IOException) { return 0; }
        catch (UnauthorizedAccessException) { return 0; }
    }

    void DismissServerUpdates()
    {
        if (!CanShowServerUpdates) return;
        dismissedServerUpdateId = latestServerUpdateId;
        try
        {
            WriteChatArchiveAtomically(ServerUpdatesDismissalPath,
                dismissedServerUpdateId.ToString(CultureInfo.InvariantCulture));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log("SERVER UPDATES | Save dismissal: " + ex.GetType().Name);
        }
        CloseServerUpdatePicker();
        CloseServerUpdatesPanel();
        PublishServerUpdatesVisibility();
    }

    async Task RefreshServerUpdates()
    {
        if (!ServerUpdatesAuthenticated || discordAccountDirty || activeServerUpdatesRead != null || workingServerUpdateReaction ||
            serverUpdatePicker != null ||
            DateTime.UtcNow < nextServerUpdatesCheck ||
            discordEnvironment is not { } environment) return;
        var read = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        activeServerUpdatesRead = read;
        nextServerUpdatesCheck = DateTime.UtcNow.AddSeconds(1);
        ServerUpdatesWindow? source = serverUpdatesWindow;
        try
        {
            if (source == null)
            {
                // Keep the updates channel in the same launcher-only profile, separate
                // from the live chat DOM and from the chat dock's visibility.
                source = serverUpdatesWindow = new ServerUpdatesWindow();
                source.Show();
                serverUpdatesReadyBy = DateTime.UtcNow.AddSeconds(15);
                await source.Browser.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(8));
                if (!ServerUpdatesAuthenticated || source != serverUpdatesWindow || source.IsDisposed) return;
                var core = source.Browser.CoreWebView2;
                ConfigureServerUpdatesBrowser(core);
                serverUpdatesReadyBy = DateTime.UtcNow.AddSeconds(15);
                core.Navigate(ServerUpdatesChannel);
                return;
            }
            source.PositionOffScreen();
            var channel = source.Browser.CoreWebView2;
            if (IsServerUpdatesRoute(channel.Source))
            {
                string result = await channel.ExecuteScriptAsync(ExtractServerUpdates.Value + "(null)").WaitAsync(TimeSpan.FromSeconds(3));
                if (!ServerUpdatesAuthenticated || source != serverUpdatesWindow || source.IsDisposed || workingServerUpdateReaction ||
                    !IsServerUpdatesRoute(channel.Source)) return;
                var updates = JsonSerializer.Deserialize<ServerUpdate[]>(result);
                if (updates != null)
                {
                    string text = FormatServerUpdates(updates, out ulong newestId, out var displayed);
                    if (newestId >= latestServerUpdateId)
                    {
                        latestServerUpdateId = newestId;
                        displayedServerUpdates = displayed;
                        UpdateServerUpdatesDocument(text);
                        PublishServerUpdatesVisibility();
                    }
                    serverUpdatesReadyBy = DateTime.UtcNow.AddSeconds(15);
                    nextServerUpdatesCheck = DateTime.UtcNow.AddSeconds(5);
                    return;
                }
            }
            if (!workingServerUpdateReaction && DateTime.UtcNow >= serverUpdatesReadyBy)
                RecoverServerUpdates("channel unavailable");
        }
        catch (Exception ex)
        {
            if (ServerUpdatesAuthenticated && source == serverUpdatesWindow && !workingServerUpdateReaction &&
                DateTime.UtcNow >= serverUpdatesReadyBy)
                RecoverServerUpdates(ex.GetType().Name);
        }
        finally
        {
            activeServerUpdatesRead = null;
            read.TrySetResult();
        }
    }

    static void ConfigureServerUpdatesBrowser(CoreWebView2 core)
    {
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = false;
        core.Settings.IsWebMessageEnabled = false;
        core.NewWindowRequested += (_, e) => e.Handled = true;
        core.DownloadStarting += (_, e) => e.Cancel = true;
        core.NavigationStarting += (_, e) =>
        {
            e.Cancel = !IsServerUpdatesRoute(e.Uri) && !IsServerUpdatesMessageRoute(e.Uri);
        };
    }

    static bool IsServerUpdatesRoute(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.UserInfo.Length == 0 && uri.IsDefaultPort &&
        string.Equals(uri.GetLeftPart(UriPartial.Path).TrimEnd('/'), ServerUpdatesChannel, StringComparison.OrdinalIgnoreCase);

    static string FormatServerUpdates(ServerUpdate[] updates, out ulong newestId, out ServerUpdate[] displayed)
    {
        var recent = new SortedDictionary<ulong, ServerUpdate>();
        foreach (var update in updates)
        {
            if (update?.Blocks is not { Length: > 0 } || !ulong.TryParse(update.Id, out ulong id) || id == 0)
                continue;
            recent[id] = update;
        }
        newestId = recent.Count == 0 ? 0 : recent.Last().Key;
        displayed = recent.TakeLast(8).Select(entry => entry.Value).ToArray();
        if (displayed.Length == 0) return ServerUpdatesStatus("No server updates to display.");

        return JsonSerializer.Serialize(new
        {
            posts = displayed.Select(post => new
            {
                id = post.Id,
                date = DiscordTimestamp(ulong.Parse(post.Id, CultureInfo.InvariantCulture)).ToLocalTime()
                    .ToString(ServerUpdatesDateFormat),
                blocks = post.Blocks!.Take(120),
                reactions = post.Reactions?.Take(25)
            })
        });
    }

    static string ServerUpdatesStatus(string text) => JsonSerializer.Serialize(new { status = text });

    void RecoverServerUpdates(string reason)
    {
        Log("SERVER UPDATES | " + reason);
        var previous = serverUpdatesWindow;
        serverUpdatesWindow = null;
        previous?.Dispose();
        // Keep the known posts and the reader's scroll position through a reconnect.
        if (displayedServerUpdates.Length == 0)
            UpdateServerUpdatesDocument(ServerUpdatesStatus("Server updates are unavailable."));
        nextServerUpdatesCheck = DateTime.UtcNow.AddSeconds(displayedServerUpdates.Length == 0 ? 30 : 5);
    }

    void ResetServerUpdates()
    {
        CloseServerUpdatePicker(resume: false);
        var previous = serverUpdatesWindow;
        serverUpdatesWindow = null;
        nextServerUpdatesCheck = DateTime.MinValue;
        latestServerUpdateId = 0;
        serverUpdatesDocument = null;
        displayedServerUpdates = [];
        CloseServerUpdatesPanel();
        PublishServerUpdatesVisibility();
        previous?.Dispose();
    }
}
