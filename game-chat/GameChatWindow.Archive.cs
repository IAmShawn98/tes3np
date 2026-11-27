using System.Drawing;

internal sealed partial class GameChatWindow
{
    readonly System.Collections.Generic.SortedDictionary<ulong, (string User, string Body)> archivedChat = new();

    // Image-only Discord posts must be indexed too: the rainbow Happy Hour
    // announcement is a picture, not searchable message text.
    readonly System.Collections.Generic.Dictionary<ulong, string[]> archivedImageUrls = new();

    readonly System.Collections.Generic.HashSet<ulong> verifiedHappyHourImageIds = new();

    readonly System.Collections.Generic.HashSet<ulong> loggedHappyHourImageCandidates = new();

    readonly System.Collections.Generic.HashSet<ulong> loggedHappyHourImageMisses = new();

    readonly string gameChatLogDirectory = Path.Combine(ChatDataRoot, "Logs");

    string GameChatLogFile => Path.Combine(gameChatLogDirectory, "game-chat.log");

    string GameChatIndexFile => Path.Combine(gameChatLogDirectory, "game-chat-index.json");

    bool chatLogLoaded;

    bool chatArchiveDirty;

    Task<string?>? chatArchiveSave;

    DateTimeOffset nextChatArchiveLoad;

    DateTimeOffset nextChatArchiveSave;

    void EnsureChatLogLoaded()
    {
        if (chatLogLoaded || DateTimeOffset.UtcNow < nextChatArchiveLoad) return;
        nextChatArchiveLoad = DateTimeOffset.UtcNow.AddSeconds(5);
        bool indexArchiveRead = true;
        if (File.Exists(GameChatIndexFile))
        {
            try
            {
                var records = System.Text.Json.JsonSerializer.Deserialize<System.Collections.Generic.List<ChatArchiveEntry>>(
                    File.ReadAllText(GameChatIndexFile)) ?? new();
                foreach (var entry in records)
                {
                    if (entry == null || entry.Id == 0) continue;
                    archivedChat.TryAdd(entry.Id, (entry.User ?? "", entry.Body ?? ""));
                    if (entry.Images is { Length: > 0 })
                        archivedImageUrls.TryAdd(entry.Id, entry.Images);
                    // This flag is persisted only after real image pixels
                    // pass the announcement's visual signature.
                    if (entry.VerifiedHappyHourImage && entry.Images is { Length: > 0 })
                        verifiedHappyHourImageIds.Add(entry.Id);
                    if (entry.VerifiedRestartEvent && TryParseRestartNotice(entry.Body ?? "", out _))
                        verifiedRestartEventIds.Add(entry.Id);
                }
            }
            catch (Exception ex)
            {
                // A temporarily inaccessible index may contain unique image evidence.
                // A malformed index can be rebuilt from the readable log.
                indexArchiveRead = ex is System.Text.Json.JsonException;
                Log("CHAT | Saved message index unreadable: " + ex.GetType().Name);
            }
        }
        bool recoveredFromText = false;
        bool textArchiveRead = true;
        if (File.Exists(GameChatLogFile))
        {
            // Recover only log entries containing original Discord IDs.
            // Human-readable timestamps without IDs cannot provide exact
            // activation times and must never be guessed.
            try
            {
                foreach (string line in File.ReadLines(GameChatLogFile))
                {
                    var idMatch = System.Text.RegularExpressions.Regex.Match(
                        line, @"\[discord:(\d+)\]\s*$");
                    if (!idMatch.Success ||
                        !ulong.TryParse(idMatch.Groups[1].Value, out ulong id) ||
                        id == 0 || archivedChat.ContainsKey(id)) continue;
                    string content = line.Substring(0, idMatch.Index).TrimEnd();
                    int stampEnd = content.IndexOf(']');
                    if (stampEnd >= 0) content = content.Substring(stampEnd + 1).TrimStart();
                    int split = content.IndexOf(": ", StringComparison.Ordinal);
                    archivedChat[id] = split >= 0
                        ? (content.Substring(0, split), content.Substring(split + 2))
                        : ("", content);
                    recoveredFromText = true;
                }
            }
            catch (Exception ex)
            {
                textArchiveRead = false;
                Log("CHAT | Saved text archive unreadable: " + ex.GetType().Name);
            }
        }
        chatLogLoaded = indexArchiveRead && textArchiveRead;
        chatArchiveDirty |= recoveredFromText;
    }

    void FlushPendingChatArchive()
    {
        if (chatArchiveSave is { } pending)
        {
            if (!pending.IsCompleted) return;
            chatArchiveSave = null;
            if (pending.GetAwaiter().GetResult() is { } failure)
            {
                chatArchiveDirty = true;
                nextChatArchiveSave = DateTimeOffset.UtcNow.AddSeconds(5);
                Log("CHAT | Could not persist chat archive: " + failure);
            }
        }
        if (!chatArchiveDirty || !chatLogLoaded ||
            DateTimeOffset.UtcNow < nextChatArchiveSave) return;
        chatArchiveSave = QueueChatArchiveSave();
        chatArchiveDirty = false;
        nextChatArchiveSave = DateTimeOffset.UtcNow.AddSeconds(2);
    }

    void QueueFinalChatArchiveSave()
    {
        if (chatArchiveSave?.IsCompletedSuccessfully == true && chatArchiveSave.Result == null)
            chatArchiveSave = null;
        if (chatLogLoaded && (chatArchiveDirty || chatArchiveSave != null))
            chatArchiveSave = QueueChatArchiveSave(chatArchiveSave);
    }

    public void WaitForChatArchiveOnExit()
    {
        if (chatArchiveSave is not { } pending) return;
        // The message loop has ended. Give the last snapshot a bounded flush.
        if (!pending.Wait(TimeSpan.FromSeconds(3)))
            Log("CHAT | Timed out saving the chat archive during shutdown.");
        else if (pending.GetAwaiter().GetResult() is { } failure)
            Log("CHAT | Could not persist chat archive: " + failure);
    }

    Task<string?> QueueChatArchiveSave(Task<string?>? previous = null)
    {
        // Copy the UI-owned index before handing it to the writer. Image
        // URL arrays are never mutated after their entries are added.
        var records = archivedChat.Select(e => new ChatArchiveEntry {
            Id = e.Key, User = e.Value.User, Body = e.Value.Body,
            Images = archivedImageUrls.TryGetValue(e.Key, out var imageUrls) ? imageUrls : Array.Empty<string>(),
            VerifiedHappyHourImage = verifiedHappyHourImageIds.Contains(e.Key),
            VerifiedRestartEvent = verifiedRestartEventIds.Contains(e.Key)
        }).ToArray();
        bool changed = chatArchiveDirty;
        string indexPath = GameChatIndexFile, textPath = GameChatLogFile;
        return WriteChatArchiveSnapshot(records, indexPath, textPath, changed, previous);
    }

    static Task<string?> WriteChatArchiveSnapshot(ChatArchiveEntry[] records, string indexPath,
        string textPath, bool changed, Task<string?>? previous = null)
    {
        return Task.Run(async () =>
        {
            // Shutdown queues behind any write already in progress.
            var previousFailure = previous == null ? null : await previous.ConfigureAwait(false);
            if (!changed && previousFailure == null) return null;
            try
            {
                SaveChatArchive(records, indexPath, textPath);
                return null;
            }
            catch (Exception ex) { return ex.GetType().Name; }
        });
    }

    public sealed class ChatArchiveEntry
    {
        public ulong Id { get; set; }
        public string User { get; set; } = "";
        public string Body { get; set; } = "";
        public string[] Images { get; set; } = Array.Empty<string>();
        public bool VerifiedHappyHourImage { get; set; }
        public bool VerifiedRestartEvent { get; set; }
    }

    public static int CheckChatArchivePersistence()
    {
        string root = Path.Combine(Path.GetTempPath(), "tes3np-chat-check-" + Guid.NewGuid().ToString("N"));
        string indexPath = Path.Combine(root, "game-chat-index.json");
        string textPath = Path.Combine(root, "game-chat.log");
        var first = new ChatArchiveEntry { Id = 1, User = "Tester", Body = "Tester: hello\r\nworld" };
        var image = new ChatArchiveEntry { Id = 2, User = "Yagrum", Images = ["fixture image"], VerifiedHappyHourImage = true };
        try
        {
            var blockedWriter = new TaskCompletionSource<string?>();
            var initial = WriteChatArchiveSnapshot([first], indexPath, textPath, true, blockedWriter.Task);
            var final = WriteChatArchiveSnapshot([first, image], indexPath, textPath, true, initial);
            blockedWriter.SetResult(null);
            if (final.GetAwaiter().GetResult() != null) return 1;
            var records = System.Text.Json.JsonSerializer.Deserialize<ChatArchiveEntry[]>(File.ReadAllText(indexPath));
            string text = File.ReadAllText(textPath);
            if (records == null || records.Length != 2 || records[0].Body != first.Body ||
                !records[1].VerifiedHappyHourImage || records[1].Images.Single() != "fixture image" ||
                !text.Contains("Tester: hello\\nworld [discord:1]") ||
                !text.Contains("Yagrum: [image attachment] [discord:2]")) return 2;
            var latest = new ChatArchiveEntry { Id = 3, User = "Yagrum",
                Body = "[SERVER]: -- Server is restarting in 10 seconds. --", VerifiedRestartEvent = true };
            Task<string?> failed;
            using (var held = File.Open(textPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                failed = WriteChatArchiveSnapshot([first, image, latest], indexPath, textPath, true);
                if (failed.GetAwaiter().GetResult() == null) return 3;
            }
            var retry = WriteChatArchiveSnapshot([first, image, latest], indexPath, textPath, false, failed);
            return retry.GetAwaiter().GetResult() == null &&
                File.ReadAllText(textPath).Contains(latest.Body + " [discord:3]") &&
                System.Text.Json.JsonSerializer.Deserialize<ChatArchiveEntry[]>(File.ReadAllText(indexPath)) is { } saved &&
                saved[^1].VerifiedRestartEvent &&
                !Directory.EnumerateFiles(root, "*.tmp").Any() ? 0 : 4;
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    // Windows may terminate the chat host while Discord history is being
    // indexed. Replace each archive file atomically rather than truncate
    // the only recoverable copy in place.
    static void WriteChatArchiveAtomically(string path, string contents)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, contents);
            File.Move(temporary, path, true);
        }
        finally
        {
            try { File.Delete(temporary); } catch { }
        }
    }

    static void SaveChatArchive(ChatArchiveEntry[] records, string indexPath, string textPath)
    {
        WriteChatArchiveAtomically(indexPath,
            System.Text.Json.JsonSerializer.Serialize(records));
        var output = new System.Text.StringBuilder();
        string previousDate = "";
        foreach (var entry in records)
        {
            var sent = DiscordTimestamp(entry.Id).ToLocalTime();
            string date = sent.ToString("dddd, MMMM d, yyyy");
            if (date != previousDate)
            {
                if (output.Length > 0) output.AppendLine();
                output.AppendLine("========== " + date + " ==========");
                previousDate = date;
            }
            string user = entry.User.Trim();
            string body = entry.Body.Replace("\r\n", "\n").Replace('\r', '\n').Replace("\n", "\\n").Trim();
            if (body.Length == 0 && entry.Images.Length > 0)
                body = "[image attachment]";
            // Discord groups consecutive messages under one username. Some
            // extracted bodies therefore already begin with "Player: ".
            if (string.IsNullOrWhiteSpace(user))
            {
                var prefix = System.Text.RegularExpressions.Regex.Match(body, @"^(.+? \(\d+\)): (.*)$");
                if (prefix.Success) { user = prefix.Groups[1].Value; body = prefix.Groups[2].Value; }
            }
            else if (body.StartsWith(user + ": ", StringComparison.Ordinal))
                body = body.Substring(user.Length + 2);
            if (string.IsNullOrWhiteSpace(user)) user = "System";
            // Keep the source message ID in the readable export so it
            // can rebuild an index after an interrupted/corrupt JSON save.
            output.AppendLine($"[{sent:hh:mm:ss tt}] {user}: {body} [discord:{entry.Id}]");
        }
        WriteChatArchiveAtomically(textPath, output.ToString());
    }

    void ArchiveDiscordMessage(ulong key, ChatMessage message, string sourceAuthor, string matchText)
    {
        var (user, body, _, _, images) = message;
        bool isHappyHour = IsHappyHourAuthor(sourceAuthor) &&
            (IsHappyHourAnnouncement(body) || IsHappyHourAnnouncement(matchText));
        // Preserve the rendered chat wording unless only the
        // Discord textContent contains the full styled announcement.
        string archivalBody = isHappyHour && !IsHappyHourAnnouncement(body)
            ? matchText : body;
        // Save image-only posts, not just those with a nonempty
        // text body. Yagrum's colored HH announcement is a bitmap.
        if ((archivalBody.Length > 0 || images.Length > 0) &&
            (!archivedChat.TryGetValue(key, out var cached) ||
             (isHappyHour && (!IsHappyHourAnnouncement(cached.Body) ||
                !IsHappyHourAuthor(cached.User))))) {
            // Store the verified Discord author for bot text alerts
            // even when Discord grouped this message under an
            // earlier author's heading. Display history is unchanged.
            archivedChat[key] = (isHappyHour ? sourceAuthor : user, archivalBody);
            chatArchiveDirty = true;
        }
        if (images.Length > 0 && !archivedImageUrls.ContainsKey(key)) {
            archivedImageUrls[key] = images;
            chatArchiveDirty = true;
        }
    }
}
