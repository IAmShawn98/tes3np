using Microsoft.Web.WebView2.WinForms;

internal sealed partial class GameChatWindow
{
    DateTime lastHistoryRequest = DateTime.MinValue;

    bool loadingHistory;

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

    async Task LoadOlderMessages()
    {
        if (loadingHistory || !discordChannelReady || discordLoginVisible || discordNavigationInProgress ||
            web.CoreWebView2 == null ||
            DateTime.UtcNow - lastHistoryRequest < TimeSpan.FromMilliseconds(300) ||
            DateTime.UtcNow < historyBackoffUntil ||
            (historyAwaitingNavigation && DateTime.UtcNow - historyNavigationStarted < TimeSpan.FromMilliseconds(900))) return;
        loadingHistory = true;
        lastHistoryRequest = DateTime.UtcNow;
        try
        {
            ulong oldest = history.Count > 0 ? history.First().Key : ulong.MaxValue;
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
            if (history.Count > 0 && history.First().Key < oldest)
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

    // Restoring Discord's hidden source from historical paging can load
    // previously unseen (but old) rows. Do not turn them into chat alerts.
    bool waitingForLiveFeedAfterHistory;

    string lastRestoredFeed = "";

    int restoredFeedStableTicks;

    void BackfillUntilHappyHour()
    {
        if (!discordChannelReady || initialBackfillComplete || !nativeMode || discordLoginVisible ||
            loadingHistory || web.CoreWebView2 == null || !messageBrowserReady ||
            history.Count == 0) return;
        if (initialBackfillStarted == DateTime.MinValue) {
            initialBackfillStarted = DateTime.UtcNow;
            Log("HAPPY HOUR | Searching Discord history backward for latest real activation");
        }
        ulong candidateId = LatestArchivedHappyHourId();
        DateTimeOffset oldestLoaded = DiscordTimestamp(history.First().Key);
        // The archive may already contain an older event from a previous
        // session. Don't stop until the current live history has paged back
        // through that event: newer activations could still be unseen.
        bool verifiedLatest = candidateId > 0 &&
            oldestLoaded <= DiscordTimestamp(candidateId);
        bool pastActiveWindow = oldestLoaded <= DateTimeOffset.UtcNow.AddHours(-1);
        bool complete = verifiedLatest || pastActiveWindow;
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
        _ = LoadOlderMessages();
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
                RequestOlderMessages();
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
