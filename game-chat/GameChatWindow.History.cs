using Microsoft.Web.WebView2.WinForms;

internal sealed partial class GameChatWindow
{
    DateTime lastHistoryRequest = DateTime.MinValue;

    bool loadingHistory;

    // Manual historical scrolling shares the Discord source used for live
    // monitoring. Remember when that source was moved so we can restore it.
    bool manualHistorySourceMoved;

    ulong lastHistoryOldestId = ulong.MaxValue;

    int historyStallCount;

    int historyNoProgressCount;

    string historyLastVisibleFirst = "";

    DateTime historyBackoffUntil = DateTime.MinValue;

    DateTime historyNavigationStarted = DateTime.MinValue;

    DateTime historyLastProgress = DateTime.MinValue;

    DateTime historyLastReanchor = DateTime.MinValue;

    bool historyAwaitingNavigation;

    static readonly Lazy<string> OlderMessagesScript = GameChatWeb.Page("load-older-messages.js");
    static readonly Lazy<string> SeekLatestMessagesScript = GameChatWeb.Page("seek-latest-messages.js");

    async Task LoadOlderMessages(bool forHappyHour = false)
    {
        if (loadingHistory || !discordChannelReady || discordLoginVisible || discordNavigationInProgress ||
            web.CoreWebView2 == null ||
            DateTime.UtcNow - lastHistoryRequest < TimeSpan.FromMilliseconds(300) ||
            DateTime.UtcNow < historyBackoffUntil ||
            (historyAwaitingNavigation && DateTime.UtcNow - historyNavigationStarted < TimeSpan.FromMilliseconds(900))) return;
        loadingHistory = true;
        lastHistoryRequest = DateTime.UtcNow;
        if (!forHappyHour) manualHistorySourceMoved = true;
        try
        {
            // Happy Hour scans must page their own observed window, not the
            // cumulative native history retained from an earlier source position.
            ulong oldest = forHappyHour && happyHourSearchOldestId != 0
                ? happyHourSearchOldestId
                : history.Count > 0 ? history.First().Key : ulong.MaxValue;
            if (oldest < lastHistoryOldestId)
            {
                lastHistoryOldestId = oldest;
                historyStallCount = 0;
                historyNoProgressCount = 0;
                historyLastProgress = DateTime.UtcNow;
                Log("History advanced; oldest message: " + oldest);
            }
            // ExecuteScriptAsync waits for the JavaScript evaluation to finish.
            // Avoid the DevTools input dispatcher: it hangs in hidden WebView2.
            // Schedule the second movement asynchronously inside the page.
            int attempt = historyNoProgressCount + 1;
            // Discord can stop paging after its virtual list drops older rows.
            // Re-enter the channel at the oldest known message to let Discord
            // initialize a fresh window around that message. The native
            // renderer keeps the already-collected history across navigation.
            if (attempt >= 3 && oldest != ulong.MaxValue &&
                DateTime.UtcNow - historyLastProgress >= TimeSpan.FromMilliseconds(1500) &&
                DateTime.UtcNow - historyLastReanchor >= TimeSpan.FromSeconds(3))
            {
                historyNoProgressCount = 0;
                historyLastVisibleFirst = "";
                historyNavigationStarted = DateTime.UtcNow;
                historyLastReanchor = DateTime.UtcNow;
                historyAwaitingNavigation = true;
                historyBackoffUntil = DateTime.UtcNow.AddMilliseconds(900);
                string olderWindow = Channel + "/" + oldest;
                Log("History reanchor: navigating Discord to " + olderWindow);
                web.CoreWebView2.Navigate(olderWindow);
                return;
            }
            string scriptMode = attempt >= 4 ? "recovery" : "normal";
            ulong navigationId = discordNavigationId;
            string script = OlderMessagesScript.Value.Replace("RECOVERY_FLAG", attempt >= 4 ? "true" : "false");
            string result = await web.CoreWebView2.ExecuteScriptAsync(script).WaitAsync(TimeSpan.FromSeconds(5));
            if (closingChat || IsDisposed || !discordChannelReady || discordLoginVisible ||
                discordNavigationInProgress || navigationId != discordNavigationId) return;

            if (result.Contains("no-message-list") || result.Contains("no-scroller"))
            {
                historyBackoffUntil = DateTime.UtcNow.AddMilliseconds(300);
                Log("History waiting for Discord message list: " + result);
                return;
            }
            historyAwaitingNavigation = false;
            // A changing first Discord row is evidence of virtual-list progress,
            // even before the native extractor has merged the new messages.
            // Don't waste recovery attempts while Discord is advancing.
            var firstMatch = System.Text.RegularExpressions.Regex.Match(result, @"first=(chat-messages-[0-9]+-[0-9]+)");
            string visibleFirst = firstMatch.Success ? firstMatch.Groups[1].Value : "";
            if (visibleFirst.Length > 0 && visibleFirst != historyLastVisibleFirst)
            {
                historyLastVisibleFirst = visibleFirst;
                historyNoProgressCount = 0;
                historyStallCount = 0;
                historyLastProgress = DateTime.UtcNow;
                attempt = 1;
            }
            historyNoProgressCount = attempt;
            if (result.Contains("loading=true"))
            {
                historyNoProgressCount = Math.Max(0, historyNoProgressCount - 1);
                historyBackoffUntil = DateTime.UtcNow.AddMilliseconds(400);
                Log("History waiting for Discord pagination: " + result);
                return;
            }
            Log("History scroll (" + scriptMode + ", attempt=" + attempt + "): " + result);
            ulong observedOldest = forHappyHour && happyHourSearchOldestId != 0
                ? happyHourSearchOldestId
                : history.Count > 0 ? history.First().Key : ulong.MaxValue;
            if (observedOldest < oldest)
            {
                historyStallCount = 0;
            }
            else if (++historyStallCount >= 10)
            {
                // Slow Discord responses are not proof of end-of-history.
                // Keep retrying while the user remains near the top.
                historyStallCount = 0;
                historyBackoffUntil = DateTime.UtcNow.AddMilliseconds(900);
                Log("History pending; retrying after 900ms if still near top");
            }
        }
        catch (TimeoutException) { Log("History load timed out after 5s; retrying on next refresh"); }
        catch (Exception ex) { Log("History load error: " + ex.GetType().Name); }
        finally { loadingHistory = false; }
    }

    DateTime lastHistoryGateLog = DateTime.MinValue;

    bool userScrolledChat;

    bool historyCatchupActive;

    // Scan backward for the latest verified Happy Hour. The alpha
    // detector extends the bounded search window to seven days if the
    // existing archive contains no verified event; production uses one hour.
    DateTime initialBackfillStarted = DateTime.MinValue;

    int initialBackfillAttempts;

    bool initialBackfillComplete;

    // Current-source coverage is distinct from the cumulative native history.
    bool happyHourTailSeeking;
    ulong happyHourTailSampleId;
    ulong happyHourTailCandidateId;
    ulong happyHourTailNavigationId;
    int happyHourTailStableChecks;
    bool happyHourTailConfirmed;
    ulong happyHourSearchOldestId;
    DateTime nextHappyHourTailProbe = DateTime.MinValue;
    DateTime lastHappyHourTailWaitLog = DateTime.MinValue;

    void ResetHappyHourSourceSearch()
    {
        happyHourTailSampleId = 0;
        happyHourTailCandidateId = 0;
        happyHourTailNavigationId = 0;
        happyHourTailStableChecks = 0;
        happyHourTailConfirmed = false;
        happyHourSearchOldestId = 0;
        nextHappyHourTailProbe = DateTime.MinValue;
        historyNoProgressCount = 0;
        lastHistoryOldestId = ulong.MaxValue;
        historyLastVisibleFirst = "";
        historyAwaitingNavigation = false;
        historyBackoffUntil = DateTime.MinValue;
    }

    static bool IsRecentHappyHourTail(ulong messageId, DateTimeOffset now)
    {
        if (messageId == 0) return false;
        var sent = DiscordTimestamp(messageId);
        return sent >= now.AddHours(-1) && sent <= now.AddMinutes(5);
    }

    static bool HappyHourSourceWindowCovered(bool liveTailConfirmed,
        ulong oldestSourceMessageId, ulong candidateId, DateTimeOffset now)
    {
        if (!liveTailConfirmed || oldestSourceMessageId == 0) return false;
        var oldest = DiscordTimestamp(oldestSourceMessageId);
        return (candidateId != 0 && oldest <= DiscordTimestamp(candidateId)) ||
               oldest <= now.AddHours(-1);
    }

    // Compiled Windows regression fixture: stale archive history must never
    // satisfy coverage without observing the live channel source first.
    public static int CheckHappyHourHistoryCoverage()
    {
        var now = new DateTimeOffset(2026, 11, 22, 20, 0, 0, TimeSpan.Zero);
        static ulong IdAt(DateTimeOffset instant) =>
            (ulong)(instant.ToUnixTimeMilliseconds() - 1420070400000L) << 22;
        ulong stale = IdAt(now.AddHours(-4));
        ulong recent = IdAt(now.AddMinutes(-10));
        ulong candidate = IdAt(now.AddMinutes(-20));
        ulong beforeCandidate = IdAt(now.AddMinutes(-30));
        if (HappyHourSourceWindowCovered(false, stale, 0, now)) return 1;
        if (HappyHourSourceWindowCovered(true, 0, 0, now)) return 2;
        if (HappyHourSourceWindowCovered(true, recent, 0, now)) return 3;
        if (!HappyHourSourceWindowCovered(true, stale, 0, now)) return 4;
        if (!HappyHourSourceWindowCovered(true, beforeCandidate, candidate, now)) return 5;
        if (HappyHourSourceWindowCovered(false, beforeCandidate, candidate, now)) return 6;
        if (IsRecentHappyHourTail(stale, now)) return 7;
        if (!IsRecentHappyHourTail(recent, now)) return 8;
        if (IsRecentHappyHourTail(IdAt(now.AddMinutes(6)), now)) return 9;
        return 0;
    }

    // Discord can reopen at an old read marker. First seek the current
    // channel tail; never infer live coverage from an old archived message.
    async Task SeekHappyHourLiveTail()
    {
        if (happyHourTailSeeking || happyHourTailCandidateId != 0 ||
            closingChat || IsDisposed || !discordChannelReady ||
            discordLoginVisible || discordNavigationInProgress ||
            web.CoreWebView2 == null || DateTime.UtcNow < nextHappyHourTailProbe)
            return;
        happyHourTailSeeking = true;
        nextHappyHourTailProbe = DateTime.UtcNow.AddSeconds(1);
        try
        {
            var core = web.CoreWebView2;
            string url = core.Source?.TrimEnd('/') ?? "";
            if (!string.Equals(url, Channel, StringComparison.OrdinalIgnoreCase))
            {
                if (IsGameChatRoute(url)) core.Navigate(Channel);
                return;
            }
            ulong navigationId = discordNavigationId;
            string raw = await core.ExecuteScriptAsync(SeekLatestMessagesScript.Value)
                .WaitAsync(TimeSpan.FromSeconds(4));
            if (closingChat || IsDisposed || !discordChannelReady ||
                discordNavigationInProgress || navigationId != discordNavigationId ||
                web.CoreWebView2 != core) return;
            string response = System.Text.Json.JsonSerializer.Deserialize<string>(raw) ?? "";
            if (response.StartsWith("present:", StringComparison.Ordinal) &&
                ulong.TryParse(response.AsSpan("present:".Length), out ulong currentId) &&
                IsRecentHappyHourTail(currentId, DateTimeOffset.UtcNow))
            {
                if (currentId == happyHourTailSampleId &&
                    happyHourTailNavigationId == navigationId)
                    happyHourTailStableChecks++;
                else
                {
                    happyHourTailSampleId = currentId;
                    happyHourTailNavigationId = navigationId;
                    happyHourTailStableChecks = 1;
                }
                if (happyHourTailStableChecks >= 2)
                {
                    happyHourTailCandidateId = currentId;
                    Log("HAPPY HOUR | Stable recent Discord tail reached; awaiting source rows");
                }
                return;
            }
            happyHourTailSampleId = 0;
            happyHourTailStableChecks = 0;
            string reason = response.StartsWith("present:", StringComparison.Ordinal)
                ? "stale-source" : response;
            if (reason is not ("jump-requested" or "seeking" or "loading" or
                "no-message-list" or "no-scroller" or "no-message-id" or "stale-source"))
                reason = "unavailable";
            if (DateTime.UtcNow - lastHappyHourTailWaitLog > TimeSpan.FromSeconds(30))
            {
                lastHappyHourTailWaitLog = DateTime.UtcNow;
                Log("HAPPY HOUR | Waiting for current Discord tail: " + reason);
            }
        }
        catch (Exception ex)
        {
            if (DateTime.UtcNow - lastHappyHourTailWaitLog > TimeSpan.FromSeconds(30))
            {
                lastHappyHourTailWaitLog = DateTime.UtcNow;
                Log("HAPPY HOUR | Live tail check unavailable: " + ex.GetType().Name);
            }
        }
        finally { happyHourTailSeeking = false; }
    }

    void ObserveHappyHourSourcePage(IReadOnlyList<DiscordFeedRow> messages, ulong navigationId)
    {
        if (initialBackfillComplete || !discordChannelReady || messages.Count == 0)
            return;
        ulong observedOldest = messages.Min(row => row.Id);
        ulong observedNewest = messages.Max(row => row.Id);
        if (!happyHourTailConfirmed)
        {
            if (happyHourTailCandidateId == 0 ||
                navigationId != happyHourTailNavigationId ||
                observedNewest < happyHourTailCandidateId ||
                !string.Equals(web.CoreWebView2?.Source?.TrimEnd('/'), Channel,
                    StringComparison.OrdinalIgnoreCase)) return;
            happyHourSearchOldestId = observedOldest;
            happyHourTailConfirmed = true;
            Log("HAPPY HOUR | Live source anchored; scanning newly observed history");
        }
        else if (observedOldest < happyHourSearchOldestId)
            happyHourSearchOldestId = observedOldest;
    }

    // Restoring Discord's hidden source from historical paging can load
    // previously unseen (but old) rows. Do not turn them into chat alerts.
    bool waitingForLiveFeedAfterHistory;

    string lastRestoredFeed = "";

    int restoredFeedStableTicks;

    void BackfillUntilHappyHour()
    {
        if (!discordChannelReady || initialBackfillComplete || !nativeMode || discordLoginVisible ||
            loadingHistory || web.CoreWebView2 == null || !messageBrowserReady) return;
        if (!happyHourTailConfirmed || happyHourSearchOldestId == 0)
        {
            _ = SeekHappyHourLiveTail();
            return;
        }
        if (initialBackfillStarted == DateTime.MinValue) {
            initialBackfillStarted = DateTime.UtcNow;
            Log("HAPPY HOUR | Searching Discord history backward for latest real activation");
        }
        ulong candidateId = LatestArchivedHappyHourId();
        DateTimeOffset oldestLoaded = DiscordTimestamp(happyHourSearchOldestId);
        // The archive may already contain an older event from a previous
        // session. Don't stop until the current live history has paged back
        // through that event: newer activations could still be unseen.
        bool verifiedLatest = candidateId > 0 &&
            oldestLoaded <= DiscordTimestamp(candidateId);
        bool pastActiveWindow = oldestLoaded <= DateTimeOffset.UtcNow.AddHours(-1);
        bool complete = HappyHourSourceWindowCovered(happyHourTailConfirmed,
            happyHourSearchOldestId, candidateId, DateTimeOffset.UtcNow);
        // Discord may throttle or stop exposing history. Log partial
        // coverage rather than claiming detection succeeded.
        bool timedOut = initialBackfillAttempts >= 500 ||
            DateTime.UtcNow - initialBackfillStarted > TimeSpan.FromMinutes(6);
        if (complete || timedOut) {
            initialBackfillComplete = true;
            Log("HAPPY HOUR | History scan " +
                (verifiedLatest ? "confirmed latest activation" :
                 pastActiveWindow ? "covered active hour" : "partial (paging limit)") +
                "; detectedId=" + candidateId +
                "; pages=" + initialBackfillAttempts +
                "; " + history.Count + " messages; oldest=" +
                oldestLoaded.ToString("O"));
            // Reanchoring an old Discord message changes the hidden
            // source browser's channel position. Restore the live channel
            // afterward, without losing the collected native history.
            if (initialBackfillAttempts > 0 && !closingChat) {
                // This browser is the hidden Discord source, not the native
                // visible chat. Restore live message monitoring after scan.
                Log("CHAT | Returning hidden Discord source to newest messages");
                waitingForLiveFeedAfterHistory = true;
                lastRestoredFeed = "";
                restoredFeedStableTicks = 0;
                web.CoreWebView2.Navigate(Channel);
            }
            // In the visible chat, show the latest messages (roughly ten
            // on a typical viewport), not the oldest page we scanned.
            if (messageBrowserReady && messageBrowser.CoreWebView2 != null)
                _ = messageBrowser.CoreWebView2.ExecuteScriptAsync("window.scrollToLatest()");
            return;
        }
        if (DateTime.UtcNow < historyBackoffUntil ||
            DateTime.UtcNow - lastHistoryRequest < TimeSpan.FromMilliseconds(600)) return;
        initialBackfillAttempts++;
        _ = LoadOlderMessages(true);
    }

    void RequestOlderMessages(bool forceTop = false)
    {
        // The live Discord source has one scroll position. During the
        // targeted HH search, reserve it for unattended pagination;
        // keep user scrolling entirely within the native chat renderer.
        if (!chatOpen || !initialBackfillComplete || (!userScrolledChat && !forceTop)) return;
        bool nearTop = forceTop || ChatFirstLine() <= Math.Max(900, browserClientHeight * 3);
        if (userScrolledChat && nearTop) historyCatchupActive = true;
        bool canRequest = (nearTop || historyCatchupActive) && !loadingHistory && IsHandleCreated &&
            nativeMode && !discordLoginVisible && web.CoreWebView2 != null;
        if (!canRequest)
        {
            if (DateTime.UtcNow - lastHistoryGateLog > TimeSpan.FromSeconds(10))
            {
                lastHistoryGateLog = DateTime.UtcNow;
                Log("History gate: top=" + browserScrollTop +
                    " nearTop=" + nearTop + " loading=" + loadingHistory +
                    " handle=" + IsHandleCreated + " native=" + nativeMode +
                    " signIn=" + discordLoginVisible +
                    " webReady=" + (web.CoreWebView2 != null));
            }
            return;
        }
        _ = LoadOlderMessages();
    }

    // Unlike startup Happy Hour backfill, normal scrollback used to leave the
    // hidden WebView anchored to old messages indefinitely. Reanchor it when
    // the user closes chat or returns to the latest end, and redo the verified
    // source-tail scan before treating the source as live again.
    void RestoreLiveSourceAfterManualHistory()
    {
        if (!manualHistorySourceMoved || closingChat || IsDisposed ||
            !initialBackfillComplete || loadingHistory || discordNavigationInProgress ||
            !discordChannelReady || discordLoginVisible || web.CoreWebView2 == null)
            return;
        bool atLatest = browserScrollHeight - browserClientHeight - browserScrollTop <= 96;
        if (chatOpen && (historyCatchupActive || (userScrolledChat && !atLatest))) return;
        manualHistorySourceMoved = false;
        waitingForLiveFeedAfterHistory = true;
        lastRestoredFeed = "";
        restoredFeedStableTicks = 0;
        BeginHappyHourDiscovery();
        Log("CHAT | Restoring live Discord source after manual history browsing");
        web.CoreWebView2.Navigate(Channel);
    }

    void MaintainHistory(object? sender, EventArgs e)
    {
        if (closingChat || IsDisposed) return;
        if (chatArchiveDirty && !chatLogLoaded) EnsureChatLogLoaded();
        FlushPendingChatArchive();
        // The scan runs in the hidden source regardless of the
        // visible chat's open/closed state or manual scroll position.
        if (nativeMode) {
            if (!initialBackfillComplete)
                BackfillUntilHappyHour();
            else
            {
                RestoreLiveSourceAfterManualHistory();
                if (initialBackfillComplete) RequestOlderMessages();
            }
        }
    }

    void ObserveLiveFeedReturn(string json)
    {
        if (waitingForLiveFeedAfterHistory &&
            string.Equals(web.CoreWebView2.Source?.TrimEnd('/'), Channel,
                StringComparison.OrdinalIgnoreCase) && json != "[]") {
            // Wait until the latest channel view produces a stable
            // message snapshot before re-enabling live notifications.
            // This also covers a slow Discord React mount after navigation.
            if (json == lastRestoredFeed) restoredFeedStableTicks++;
            else { lastRestoredFeed = json; restoredFeedStableTicks = 0; }
            if (restoredFeedStableTicks >= 2) {
                waitingForLiveFeedAfterHistory = false;
                Log("CHAT | Hidden source ready for live notifications after history search");
            }
        }
    }
}
