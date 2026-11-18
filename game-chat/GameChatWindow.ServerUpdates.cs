using System.Drawing;
using System.Text;
using System.Text.Json;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const string ServerUpdatesChannel = "https://discord.com/channels/509601787901116437/510245417657827363";
    const int ServerUpdateBodyLimit = 3800;
    const string ServerUpdatesDateFormat = "MMMM d, yyyy";
    const string ServerUpdatesRtfHeader = @"{\rtf1\ansi\ansicpg1252\uc1{\fonttbl{\f0 Georgia;}}" +
        @"{\colortbl;\red241\green238\blue232;\red217\green196\blue156;\red101\green82\blue55;" +
        @"\red222\green107\blue82;\red184\green169\blue142;\red219\green178\blue67;}\f0\fs21";
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

    sealed record ServerUpdate(string Id, string? Author, ServerUpdateBlock[]? Blocks);
    sealed record ServerUpdateBlock(string? Style, int Number, ServerUpdateRun[]? Runs);
    sealed record ServerUpdateRun(string? Text, bool Bold);

    ServerUpdatesWindow? serverUpdatesWindow;
    DateTime nextServerUpdatesCheck;
    DateTime serverUpdatesReadyBy;
    bool readingServerUpdates;

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
                    UpdateServerUpdatesDocument(text);
                    serverUpdatesReadyBy = DateTime.UtcNow.AddSeconds(15);
                    nextServerUpdatesCheck = DateTime.UtcNow.AddSeconds(5);
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
        var recent = new SortedDictionary<ulong, ServerUpdate>();
        foreach (var update in updates)
        {
            if (update?.Blocks is not { Length: > 0 } || !ulong.TryParse(update.Id, out ulong id) || id == 0)
                continue;
            recent[id] = update;
        }
        if (recent.Count == 0) return ServerUpdatesStatus("No server updates to display.");

        var rtf = new StringBuilder(ServerUpdatesRtfHeader);
        foreach (var entry in recent.TakeLast(8))
        {
            var when = DiscordTimestamp(entry.Key).ToLocalTime();
            rtf.Append(@"\pard\qc\sb170\sa170\fs18\cf3 \u9472?\u9472?\u9472?  \cf2 ");
            AppendServerUpdatesRtfText(rtf, when.ToString(ServerUpdatesDateFormat).AsSpan());
            rtf.Append(@"  \cf3\u9472?\u9472?\u9472?\par ");
            if (!string.IsNullOrWhiteSpace(entry.Value.Author))
            {
                rtf.Append(@"\pard\sb55\sa55\fs21 ");
                string author = entry.Value.Author[..Math.Min(entry.Value.Author.Length, 64)];
                rtf.Append(string.Equals(author, "Jiub", StringComparison.OrdinalIgnoreCase) ? @"{\cf4\b " : @"{\cf6\b ");
                AppendServerUpdatesRtfText(rtf, author.AsSpan());
                rtf.Append(@"}\par ");
            }

            int remaining = ServerUpdateBodyLimit;
            foreach (var block in entry.Value.Blocks!.Take(120))
            {
                if (remaining == 0) break;
                if (block?.Runs is not { Length: > 0 }) continue;
                rtf.Append(@"\pard\cf1\fs21\sa70 ");
                if (block.Style == "bullet" || block.Style == "number")
                {
                    rtf.Append(@"\li230\fi-225\tx230 ");
                    if (block.Style == "bullet") rtf.Append(@"\u8226?");
                    else rtf.Append(Math.Clamp(block.Number, 1, 999)).Append('.');
                    rtf.Append(@"\tab ");
                }
                if (block.Style == "heading") rtf.Append(@"\sb55 ");
                foreach (var run in block.Runs.Take(240))
                {
                    if (remaining == 0) break;
                    if (string.IsNullOrEmpty(run?.Text)) continue;
                    bool bold = run.Bold || block.Style == "heading";
                    if (bold) rtf.Append(@"{\b ");
                    int length = Math.Min(run.Text.Length, remaining);
                    AppendServerUpdatesRtfText(rtf, run.Text.AsSpan(0, length));
                    if (bold) rtf.Append('}');
                    remaining -= length;
                }
                rtf.Append(@"\par ");
            }
            rtf.Append(@"\pard\sa100\par ");
        }
        return rtf.Append('}').ToString();
    }

    static List<(int Offset, string Label)> FindServerUpdatesDateDividers(string text)
    {
        const string strokes = "───";
        List<(int Offset, string Label)> dates = [];
        using var lines = new StringReader(text);
        int offset = 0;
        while (lines.ReadLine() is { } line)
        {
            var content = line.AsSpan().Trim();
            if (content.Length > 6 && content.StartsWith(strokes) && content.EndsWith(strokes))
            {
                var label = content[3..^3].Trim();
                if (DateTime.TryParseExact(label, ServerUpdatesDateFormat, null,
                        System.Globalization.DateTimeStyles.None, out _))
                    dates.Add((offset, label.ToString()));
            }
            // RichEdit character positions count each paragraph break once.
            offset += line.Length + 1;
        }
        return dates;
    }

    static string ServerUpdatesStatus(string text)
    {
        var rtf = new StringBuilder(ServerUpdatesRtfHeader).Append(@"\pard\cf5 ");
        AppendServerUpdatesRtfText(rtf, text.AsSpan());
        return rtf.Append('}').ToString();
    }

    static void AppendServerUpdatesRtfText(StringBuilder rtf, ReadOnlySpan<char> text)
    {
        foreach (char ch in text)
        {
            switch (ch)
            {
                case '\\':
                case '{':
                case '}': rtf.Append('\\').Append(ch); break;
                case '\n': rtf.Append(@"\line "); break;
                case '\t': rtf.Append(@"\tab "); break;
                default:
                    if (char.IsControl(ch)) break;
                    if (ch <= '\x7e') rtf.Append(ch);
                    else rtf.Append(@"\u").Append(((short)ch).ToString(System.Globalization.CultureInfo.InvariantCulture)).Append('?');
                    break;
            }
        }
    }

    void RecoverServerUpdates(string reason)
    {
        Log("SERVER UPDATES | " + reason);
        var previous = serverUpdatesWindow;
        serverUpdatesWindow = null;
        previous?.Dispose();
        UpdateServerUpdatesDocument(ServerUpdatesStatus("Server updates are unavailable."));
        nextServerUpdatesCheck = DateTime.UtcNow.AddSeconds(30);
    }

    void ResetServerUpdates()
    {
        var previous = serverUpdatesWindow;
        serverUpdatesWindow = null;
        nextServerUpdatesCheck = DateTime.MinValue;
        serverUpdatesDocument = null;
        CloseServerUpdatesPanel();
        previous?.Dispose();
    }
}
