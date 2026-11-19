using System.Globalization;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;

internal sealed partial class GameChatWindow
{
    sealed record ServerUpdateAction(string Kind, string Id, string? Key = null, bool? Mine = null);

    ServerUpdate[] displayedServerUpdates = [];
    bool workingServerUpdateReaction;

    static bool IsServerUpdatesMessageRoute(string? url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.UserInfo.Length != 0 || !uri.IsDefaultPort)
            return false;
        string path = uri.GetLeftPart(UriPartial.Path).TrimEnd('/');
        return path.StartsWith(ServerUpdatesChannel + "/", StringComparison.OrdinalIgnoreCase) &&
            ulong.TryParse(path.AsSpan(ServerUpdatesChannel.Length + 1), NumberStyles.None,
                CultureInfo.InvariantCulture, out ulong id) && id != 0;
    }

    bool IsCurrentServerUpdatesSource(ServerUpdatesWindow source) =>
        CanShowServerUpdates && source == serverUpdatesWindow && !source.IsDisposed;

    static Task<string> RunServerUpdateAction(CoreWebView2 core, ServerUpdateAction request) =>
        core.ExecuteScriptAsync(ExtractServerUpdates.Value + "(" + JsonSerializer.Serialize(request) + ")")
            .WaitAsync(TimeSpan.FromSeconds(3));

    async Task<string?> ActOnServerUpdate(LatestUpdatesPanel panel, ServerUpdateAction request)
    {
        if (panel != serverUpdatesPanel || !CanShowServerUpdates)
            return "Discord is still loading.";
        var post = displayedServerUpdates.FirstOrDefault(post => post.Id == request.Id);
        if (post == null || !ulong.TryParse(request.Id, NumberStyles.None, CultureInfo.InvariantCulture, out _) ||
            (request.Kind == "toggle" && (request.Mine == null ||
                post.Reactions?.Any(reaction => reaction.Key == request.Key) != true)))
            return "This reaction has changed. Try again after the update refreshes.";
        if (request.Kind != "toggle" || serverUpdatesWindow is not { IsDisposed: false } source ||
            source.Browser.CoreWebView2 is not { } core) return "Discord is still loading.";
        if (workingServerUpdateReaction) return "Finish the open reaction first.";

        workingServerUpdateReaction = true;
        try
        {
            if (activeServerUpdatesRead is { } activeRead) await activeRead.Task;
            string result = await RunServerUpdateOnPost(source, core, request);
            if (!IsCurrentServerUpdatesSource(source)) return null;

            if (result is not ("\"clicked\"" or "\"already\"")) return "Discord could not apply this reaction.";
            await ReadBackServerUpdateReaction(source, core, request);
            return null;
        }
        catch (Exception ex)
        {
            if (IsCurrentServerUpdatesSource(source)) Log("SERVER UPDATES | Reaction: " + ex.GetType().Name);
            return "Discord could not apply this reaction.";
        }
        finally
        {
            workingServerUpdateReaction = false;
            RestoreServerUpdatesChannel(source);
        }
    }

    async Task<string> RunServerUpdateOnPost(ServerUpdatesWindow source, CoreWebView2 core, ServerUpdateAction request)
    {
        if (!IsCurrentServerUpdatesSource(source)) return "null";
        string result = IsServerUpdatesRoute(core.Source) || IsServerUpdatesMessageRoute(core.Source)
            ? await RunServerUpdateAction(core, request) : "null";
        if (!IsCurrentServerUpdatesSource(source) || result is not ("null" or "\"missing\"")) return result;

        core.Navigate(ServerUpdatesChannel + "/" + request.Id);
        for (int attempt = 0; attempt < 24 && (result is "null" or "\"missing\""); attempt++)
        {
            await Task.Delay(250);
            if (!IsCurrentServerUpdatesSource(source)) return "null";
            if (IsServerUpdatesRoute(core.Source) || IsServerUpdatesMessageRoute(core.Source))
                result = await RunServerUpdateAction(core, request);
        }
        return result;
    }

    async Task ReadBackServerUpdateReaction(ServerUpdatesWindow source, CoreWebView2 core, ServerUpdateAction request)
    {
        try
        {
            var read = request with { Kind = "read-reactions" };
            for (int attempt = 0; attempt < 5; attempt++)
            {
                await Task.Delay(150);
                if (!IsCurrentServerUpdatesSource(source) ||
                    (!IsServerUpdatesRoute(core.Source) && !IsServerUpdatesMessageRoute(core.Source))) return;
                string result = await RunServerUpdateAction(core, read);
                if (!IsCurrentServerUpdatesSource(source)) return;
                if (result.Length == 0 || result[0] != '[') continue;
                var reactions = JsonSerializer.Deserialize<ServerUpdateReaction[]>(result);
                var updated = reactions?.FirstOrDefault(reaction => reaction.Key == request.Key);
                if (reactions == null || (updated?.Mine ?? false) != request.Mine) continue;

                // An empty reaction list is valid when the last person removes their emoji.
                var posts = displayedServerUpdates.Select(post => post.Id == request.Id ? post with { Reactions = reactions } : post);
                string text = FormatServerUpdates(posts.ToArray(), out _, out var displayed);
                displayedServerUpdates = displayed;
                UpdateServerUpdatesDocument(text);
                return;
            }
        }
        catch (Exception ex)
        {
            // The regular channel refresh can still confirm an action already sent to Discord.
            if (IsCurrentServerUpdatesSource(source)) Log("SERVER UPDATES | Reaction refresh: " + ex.GetType().Name);
        }
    }

    void RestoreServerUpdatesChannel(ServerUpdatesWindow source)
    {
        if (source != serverUpdatesWindow || source.IsDisposed || !ServerUpdatesAuthenticated) return;
        nextServerUpdatesCheck = DateTime.UtcNow.AddMilliseconds(500);
        serverUpdatesReadyBy = DateTime.UtcNow.AddSeconds(15);
        try
        {
            if (source.Browser.CoreWebView2 is { } core && IsServerUpdatesMessageRoute(core.Source))
                core.Navigate(ServerUpdatesChannel);
        }
        catch (Exception ex) { Log("SERVER UPDATES | Return to channel: " + ex.GetType().Name); }
    }
}
