using System.Text.Json;
using System.Text.RegularExpressions;

internal sealed record ChatMessage(string User, string Body, bool IsYagrum, string AuthorColor, string[] Images);

internal readonly record struct DiscordFeedRow(ulong Id, ChatMessage Message, string SourceAuthor, string MatchText);

internal static partial class DiscordFeedReader
{
    [GeneratedRegex(@"^chat-messages-\d+-(\d+)$", RegexOptions.CultureInvariant)]
    private static partial Regex MessageId();

    internal static IReadOnlyList<DiscordFeedRow> Read(string json)
    {
        using var document = JsonDocument.Parse(json);
        var rows = new List<DiscordFeedRow>();
        if (document.RootElement.ValueKind != JsonValueKind.Array) return rows;
        foreach (var element in document.RootElement.EnumerateArray())
        {
            if (element.ValueKind != JsonValueKind.Object) continue;
            var match = MessageId().Match(ReadString(element, "id") ?? "");
            if (!match.Success || !ulong.TryParse(match.Groups[1].Value, out ulong id)) continue;

            string user = ReadString(element, "user") ?? "";
            string body = ReadString(element, "body") ?? "";
            string authorColor = ReadString(element, "authorColor") ?? "";
            bool isYagrum = element.TryGetProperty("isYagrum", out var botFlag) &&
                botFlag.ValueKind == JsonValueKind.True;
            string[] images = element.TryGetProperty("images", out var imageValues) &&
                imageValues.ValueKind == JsonValueKind.Array
                ? imageValues.EnumerateArray().Where(value => value.ValueKind == JsonValueKind.String)
                    .Select(value => value.GetString()!).Where(url => url.Length > 0).ToArray()
                : Array.Empty<string>();

            var message = new ChatMessage(user, body, isYagrum, authorColor, images);
            rows.Add(new DiscordFeedRow(id, message, ReadString(element, "sourceAuthor") ?? user,
                ReadString(element, "matchText") ?? ""));
        }

        return rows;
    }

    static string? ReadString(JsonElement row, string property) =>
        row.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() : null;
}
