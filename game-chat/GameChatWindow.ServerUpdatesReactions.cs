using System.Globalization;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;

internal sealed partial class GameChatWindow
{
    sealed record ServerUpdateAction(string Kind, string Id, string? Key);

    ServerUpdate[] displayedServerUpdates = [];
    bool workingServerUpdateReaction;
    bool serverUpdatePickerSeen;

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
        if (panel != serverUpdatesPanel || !CanShowServerUpdates ||
            serverUpdatesWindow is not { IsDisposed: false } source || source.Browser.CoreWebView2 is not { } core)
            return "Discord is still loading.";
        var post = displayedServerUpdates.FirstOrDefault(post => post.Id == request.Id);
        if (post == null || !ulong.TryParse(request.Id, NumberStyles.None, CultureInfo.InvariantCulture, out _) ||
            (request.Kind == "toggle" && post.Reactions?.Any(reaction => reaction.Key == request.Key) != true))
            return "This reaction has changed. Try again after the update refreshes.";
        if (workingServerUpdateReaction || source.PickerOpen) return "Finish the open reaction first.";

        workingServerUpdateReaction = true;
        string target = ServerUpdatesChannel + "/" + request.Id;
        try
        {
            string result = IsServerUpdatesRoute(core.Source) ? await RunServerUpdateAction(core, request) : "null";
            if (!IsCurrentServerUpdatesSource(source)) return null;
            if (result is "null" or "\"missing\"")
            {
                core.Navigate(target);
                for (int attempt = 0; attempt < 24 && (result is "null" or "\"missing\""); attempt++)
                {
                    await Task.Delay(250);
                    if (!IsCurrentServerUpdatesSource(source)) return null;
                    if (IsServerUpdatesRoute(core.Source) || IsServerUpdatesMessageRoute(core.Source))
                        result = await RunServerUpdateAction(core, request);
                }
            }
            if (!IsCurrentServerUpdatesSource(source)) return null;

            if (request.Kind == "picker" && result == "\"unavailable\"")
            {
                await Task.Delay(200);
                if (!IsCurrentServerUpdatesSource(source)) return null;
                if (IsServerUpdatesRoute(core.Source) || IsServerUpdatesMessageRoute(core.Source))
                    result = await RunServerUpdateAction(core, request);
            }
            if (request.Kind == "picker" && (result is "\"clicked\"" or "\"unavailable\""))
            {
                // If Discord only exposes the control on hover, the focused post is open
                // and the user can use its native Add Reaction button there.
                source.ShowReactionPicker(owner, panel.RectangleToScreen(panel.ClientRectangle));
                serverUpdatePickerSeen = false;
                return result == "\"unavailable\"" ? "Use Add Reaction on the opened Discord post." : null;
            }

            if (result != "\"clicked\"") return "Discord could not apply this reaction.";
            if (IsServerUpdatesMessageRoute(core.Source)) await Task.Delay(350);
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
            if (IsCurrentServerUpdatesSource(source) && !source.PickerOpen)
                RestoreServerUpdatesChannel(source);
            else if (IsCurrentServerUpdatesSource(source))
                nextServerUpdatesCheck = DateTime.MinValue;
        }
    }

    async Task TrackServerUpdatePicker(ServerUpdatesWindow source)
    {
        var core = source.Browser.CoreWebView2;
        if (core == null || (!IsServerUpdatesRoute(core.Source) && !IsServerUpdatesMessageRoute(core.Source)))
        {
            source.CloseReactionPicker();
            return;
        }
        string state = await RunServerUpdateAction(core, new("picker-state", "", null));
        if (!IsCurrentServerUpdatesSource(source) || !source.PickerOpen) return;
        if (state == "true") serverUpdatePickerSeen = true;
        else if (state == "false" && serverUpdatePickerSeen) source.CloseReactionPicker();
    }

    void RestoreServerUpdatesChannel(ServerUpdatesWindow source)
    {
        if (source != serverUpdatesWindow || source.IsDisposed || !ServerUpdatesAuthenticated) return;
        serverUpdatePickerSeen = false;
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
