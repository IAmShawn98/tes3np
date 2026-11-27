using System.Text.Json;

internal sealed partial class GameChatWindow
{
    static readonly Lazy<string> ExtractFeed = GameChatWeb.Page("extract-feed.js");
    readonly SortedDictionary<ulong, ChatMessage> history = new();

    string lastFeed = "";
    bool refreshingNativeFeed;
    bool feedInitialized;
    ulong latestMessageId;

    DateTime nextHappyHourSourceImageLog = DateTime.MinValue;

    void LogHappyHourSourceImageCoverage(IReadOnlyList<DiscordFeedRow> rows)
    {
        if (DateTime.UtcNow < nextHappyHourSourceImageLog) return;
        var imageRows = rows.Where(row => row.Message.Images.Length > 0).ToArray();
        if (imageRows.Length == 0) return;
        int named = imageRows.Count(row => IsHappyHourAuthor(row.SourceAuthor));
        int unknown = imageRows.Count(row => string.IsNullOrWhiteSpace(row.SourceAuthor));
        nextHappyHourSourceImageLog = DateTime.UtcNow.AddSeconds(30);
        // Count-only diagnostics: no messages, IDs, URLs or private authors.
        Log("HAPPY HOUR | Source attachment rows=" + imageRows.Length +
            "; Yagrum-name attributed=" + named +
            "; unknown author=" + unknown);
    }

    async Task RefreshNativeMessages()
    {
        if (refreshingNativeFeed || closingChat || IsDisposed || web.CoreWebView2 == null ||
            discordLoginVisible || !discordChannelReady) return;

        refreshingNativeFeed = true;
        try
        {
            ulong feedNavigationId = discordNavigationId;
            string raw = await web.CoreWebView2.ExecuteScriptAsync(ExtractFeed.Value)
                .WaitAsync(TimeSpan.FromSeconds(4));
            if (closingChat || IsDisposed || discordLoginVisible || !discordChannelReady ||
                discordNavigationInProgress || feedNavigationId != discordNavigationId) return;
            bool needsVisibleUpdate = chatOpen && !messageViewportReady;
            string json = JsonSerializer.Deserialize<string>(raw) ?? "[]";
            ObserveLiveFeedReturn(json);
            if (json == lastFeed && !imagesNeedRedraw && nativeMode && !needsVisibleUpdate) {
                // Seeking the source tail may leave the JSON unchanged.
                // Still observe that fresh source page before claiming coverage.
                if (!initialBackfillComplete && (happyHourTailCandidateId != 0 ||
                    happyHourTailConfirmed))
                    ObserveHappyHourSourcePage(DiscordFeedReader.Read(json), feedNavigationId);
                DetectLatestHappyHour();
                return;
            }
            bool redrawImages = imagesNeedRedraw;
            imagesNeedRedraw = false;
            var messages = DiscordFeedReader.Read(json);
            if (messages.Count == 0)
            {
                DetectLatestHappyHour();
                return;
            }

            ObserveHappyHourSourcePage(messages, feedNavigationId);
            LogHappyHourSourceImageCoverage(messages);
            NotifyForNewMessage(messages[^1].Id);
            EnsureChatLogLoaded();
            ulong previousFirst = history.Count > 0 ? history.First().Key : ulong.MaxValue;
            bool changed = MergeDiscordMessages(messages);
            lastFeed = json;
            // Match only genuine archived Discord messages; the snowflake
            // timestamp supplies the real one-hour remaining time.
            DetectLatestHappyHour();
            if (!changed && !redrawImages && nativeMode && !needsVisibleUpdate) return;
            bool prepended = history.Count > 0 && history.First().Key < previousFirst;
            await RenderNativeMessagesAsync(feedNavigationId, prepended);
        }
        catch (Exception ex)
        {
            imagesNeedRedraw = true;
            Log("Native feed error: " + ex.GetType().Name);
        }
        finally { refreshingNativeFeed = false; }
    }

    void NotifyForNewMessage(ulong newestSnowflake)
    {
        // Discord's virtual history replaces the last visible row
        // as we page backward or reanchor. That is NOT a new message:
        // only a snowflake newer than the newest previously observed
        // live message is eligible for an automatic notification.
        bool newMessage = feedInitialized && newestSnowflake > latestMessageId;
        if (newestSnowflake > latestMessageId)
            latestMessageId = newestSnowflake;
        feedInitialized = true;
        // Unattended history navigation must never force the chat
        // open or reset the user's auto-hide timer.
        if (newMessage && initialBackfillComplete &&
            !waitingForLiveFeedAfterHistory &&
            chatDisplayMode == "Automatic" && docked && IsHandleCreated &&
            GameChatNative.CanPresentOwnedChat(owner, Handle))
        {
            lastChatActivity = DateTime.Now;
            SetChatOpen(true);
        }
    }

    bool MergeDiscordMessages(IReadOnlyList<DiscordFeedRow> messages)
    {
        bool changed = false;
        foreach (var row in messages)
        {
            var (key, message, sourceAuthor, matchText) = row;
            ArchiveDiscordMessage(key, message, sourceAuthor, matchText);
            RegisterHappyHourImages(key, sourceAuthor, message.Images);
            LoadChatImages(message.Images);
            if (!history.TryGetValue(key, out var existing) ||
                existing.User != message.User || existing.Body != message.Body ||
                existing.IsYagrum != message.IsYagrum || existing.AuthorColor != message.AuthorColor ||
                !existing.Images.SequenceEqual(message.Images))
            {
                history[key] = message;
                changed = true;
            }
        }

        return changed;
    }
}
