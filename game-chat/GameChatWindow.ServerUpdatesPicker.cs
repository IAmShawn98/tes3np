using System.Globalization;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;

internal sealed partial class GameChatWindow
{
    sealed record PickerEmoji(string Key, string Name, string Text, string? Image, string ReactionKey, int Offset);
    sealed record PickerPage(PickerEmoji[] Items, bool More);
    sealed record PickerReply(PickerEmoji[]? Items = null, bool More = false, string? Error = null, bool Close = false);

    sealed class ServerUpdatePicker(string messageId, ServerUpdatesWindow source)
    {
        internal string MessageId { get; } = messageId;
        internal ServerUpdatesWindow Source { get; } = source;
        internal Dictionary<string, PickerEmoji> Choices { get; } = new(StringComparer.Ordinal);
    }

    ServerUpdatePicker? serverUpdatePicker;
    ServerUpdatesWindow? pickerSourceToResume;

    bool IsCurrentServerUpdatePicker(ServerUpdatePicker picker) =>
        picker == serverUpdatePicker && IsCurrentServerUpdatesSource(picker.Source);

    async Task<PickerReply> ActOnServerUpdatePicker(LatestUpdatesPanel panel, ServerUpdateAction request)
    {
        await Task.Yield();
        if (panel != serverUpdatesPanel || !CanShowServerUpdates)
            return new(Error: "Discord is still loading.");
        if (request.Kind == "picker-leave")
        {
            if (serverUpdatePicker?.MessageId == request.Id) CloseServerUpdatePicker();
            return new();
        }
        if (workingServerUpdateReaction)
            return new(Error: "Wait for the current reaction to finish.");
        var bundled = request.Kind == "picker-local"
            ? BundledEmojiCatalog.Value.FirstOrDefault(item => item.Glyph == request.Key) : null;
        if (request.Kind == "picker-local" && bundled == null)
            return new(Error: "Choose an emoji from the picker.");
        if (request.Kind == "picker" || bundled != null)
        {
            if (!ulong.TryParse(request.Id, NumberStyles.None, CultureInfo.InvariantCulture, out _) ||
                !displayedServerUpdates.Any(post => post.Id == request.Id) ||
                serverUpdatesWindow is not { IsDisposed: false } source || source.Browser.CoreWebView2 == null)
                return new(Error: "Discord is still loading.");
            if (serverUpdatePicker != null) return new(Error: "Close the current emoji picker first.");
            serverUpdatePicker = new ServerUpdatePicker(request.Id, source);
        }

        if (serverUpdatePicker is not { } picker || picker.MessageId != request.Id ||
            !IsCurrentServerUpdatePicker(picker) || picker.Source.Browser.CoreWebView2 is not { } core)
            return new(Error: "Reopen the emoji picker to continue.");

        workingServerUpdateReaction = true;
        try
        {
            if (activeServerUpdatesRead is { } activeRead) await activeRead.Task;
            if (!IsCurrentServerUpdatePicker(picker)) return new(Close: true);
            if (request.Kind == "picker" || bundled != null)
            {
                var open = request with { Kind = "picker" };
                string opened = await RunServerUpdateOnPost(picker.Source, core, open);
                for (int attempt = 0; attempt < 2 && opened == "\"unavailable\"" && IsCurrentServerUpdatePicker(picker); attempt++)
                {
                    await Task.Delay(175);
                    if (IsCurrentServerUpdatePicker(picker)) opened = await RunServerUpdateAction(core, open);
                }
                if (opened == "\"clicked\"")
                {
                    if (bundled != null) return await SelectBundledEmoji(picker, core, request, bundled);
                    for (int attempt = 0; attempt < 16; attempt++)
                    {
                        var page = await ReadPickerPage(picker, core, request);
                        if (page != null && page.Items.Length > 0) return RememberPickerPage(picker, page);
                        if (!IsCurrentServerUpdatePicker(picker)) return new(Close: true);
                        await Task.Delay(175);
                    }
                }
                if (IsCurrentServerUpdatePicker(picker)) CloseServerUpdatePicker();
                return new(Error: bundled == null ? "Discord emoji are temporarily unavailable."
                    : "Discord could not open the reaction menu for this post.");
            }

            if (request.Kind == "picker-select")
            {
                if (request.Key == null || !picker.Choices.TryGetValue(request.Key, out var choice))
                    return new(Error: "Choose an emoji from the current results.");
                string positioned = await RunServerUpdateAction(core, request with { Kind = "picker-position", Offset = choice.Offset });
                if (positioned != "\"changed\"") return new(Error: "The emoji list closed. Reopen it to continue.");
                await Task.Delay(175);
                if (!IsCurrentServerUpdatePicker(picker)) return new(Close: true);
                if (await RunServerUpdateAction(core, request) != "\"clicked\"")
                    return new(Error: "Discord could not select that emoji. Search for it and try again.");
                await ReadBackServerUpdateReaction(picker.Source, core, request with { Key = choice.ReactionKey, Mine = true });
                if (IsCurrentServerUpdatePicker(picker)) CloseServerUpdatePicker();
                return new(Close: true);
            }

            if (request.Kind == "picker-search" && (request.Query?.Length ?? 0) > 64)
                return new(Error: "Use a shorter search.");
            if (request.Kind is not ("picker-search" or "picker-more")) return new();
            if (await RunServerUpdateAction(core, request) != "\"changed\"")
                return new(Error: "Discord could not update the emoji list.");
            await Task.Delay(request.Kind == "picker-search" ? 450 : 175);
            var updated = await ReadPickerPage(picker, core, request);
            if (updated == null) return new(Error: "Discord could not update the emoji list.");
            if (request.Kind == "picker-search") picker.Choices.Clear();
            return RememberPickerPage(picker, updated);
        }
        catch (Exception ex)
        {
            if (IsCurrentServerUpdatePicker(picker))
            {
                Log("SERVER UPDATES | Emoji picker: " + ex.GetType().Name);
                CloseServerUpdatePicker();
            }
            return new(Error: "Discord could not update the emoji list. Close this picker and try again.");
        }
        finally
        {
            workingServerUpdateReaction = false;
            if (pickerSourceToResume is { } source)
            {
                pickerSourceToResume = null;
                RestoreServerUpdatesChannel(source);
            }
        }
    }

    async Task<PickerReply> SelectBundledEmoji(ServerUpdatePicker picker, CoreWebView2 core,
        ServerUpdateAction request, BundledEmoji bundled)
    {
        // Discord can build the native search control after the reaction menu opens.
        for (int attempt = 0; attempt < 12 && IsCurrentServerUpdatePicker(picker); attempt++)
        {
            var page = await ReadPickerPage(picker, core, request);
            if (page != null) break;
            await Task.Delay(175);
        }
        foreach (string alias in bundled.Aliases.Take(4))
        {
            if (!IsCurrentServerUpdatePicker(picker)) return new(Close: true);
            string searched = await RunServerUpdateAction(core, request with { Kind = "picker-search", Query = alias });
            if (searched != "\"changed\"") continue;
            await Task.Delay(450);
            var page = await ReadPickerPage(picker, core, request);
            var choice = page?.Items.FirstOrDefault(item => MatchesBundledEmoji(item, bundled));
            if (choice == null || !IsCurrentServerUpdatePicker(picker)) continue;
            string clicked = await RunServerUpdateAction(core, request with { Kind = "picker-select", Key = choice.Key });
            if (clicked != "\"clicked\"") continue;
            await ReadBackServerUpdateReaction(picker.Source, core, request with { Key = choice.ReactionKey, Mine = true });
            if (IsCurrentServerUpdatePicker(picker)) CloseServerUpdatePicker();
            return new(Close: true);
        }
        if (IsCurrentServerUpdatePicker(picker)) CloseServerUpdatePicker();
        return new(Error: "Discord did not offer that emoji for this post.");
    }

    static bool MatchesBundledEmoji(PickerEmoji choice, BundledEmoji bundled) =>
        !ulong.TryParse(choice.Key, NumberStyles.None, CultureInfo.InvariantCulture, out _) &&
        DisplayPickerGlyph(choice).Replace("\uFE0F", "", StringComparison.Ordinal) ==
            bundled.Glyph.Replace("\uFE0F", "", StringComparison.Ordinal);

    async Task<PickerPage?> ReadPickerPage(ServerUpdatePicker picker, CoreWebView2 core, ServerUpdateAction request)
    {
        if (!IsCurrentServerUpdatePicker(picker)) return null;
        string result = await RunServerUpdateAction(core, request with { Kind = "picker-page" });
        return IsCurrentServerUpdatePicker(picker) && result.Length > 0 && result[0] == '{'
            ? JsonSerializer.Deserialize<PickerPage>(result) : null;
    }

    static PickerReply RememberPickerPage(ServerUpdatePicker picker, PickerPage page)
    {
        var newItems = page.Items.Where(item => picker.Choices.TryAdd(item.Key, item)).ToArray();
        return new(Items: newItems, More: page.More);
    }

    void CloseServerUpdatePicker(bool resume = true)
    {
        var picker = serverUpdatePicker;
        serverUpdatePicker = null;
        if (!resume) pickerSourceToResume = null;
        if (!resume || picker == null) return;
        if (workingServerUpdateReaction) pickerSourceToResume = picker.Source;
        else RestoreServerUpdatesChannel(picker.Source);
    }
}
