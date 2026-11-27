using System.Text.RegularExpressions;

internal sealed partial class GameChatWindow
{
    readonly HashSet<ulong> verifiedRestartEventIds = new();
    readonly RestartNoticeTracker restartNotice = new();
    DateTimeOffset nextRestartBannerRefresh;
    DateTimeOffset nextRestartStatusHeartbeat;

    static bool TryParseRestartNotice(string body, out TimeSpan duration)
    {
        duration = TimeSpan.Zero;
        if (body == "[SERVER]: -- SERVER WAS JUST REBOOTED --") return true;
        var match = Regex.Match(body, @"^\[SERVER\]: -- Server is restarting in ([0-9]{1,2}) (minutes?|seconds?)\. --\z",
            RegexOptions.CultureInvariant);
        if (!match.Success || !int.TryParse(match.Groups[1].Value, out int amount) ||
            amount < 1 || amount > 60) return false;
        duration = match.Groups[2].Value.StartsWith("minute", StringComparison.Ordinal)
            ? TimeSpan.FromMinutes(amount) : TimeSpan.FromSeconds(amount);
        return true;
    }

    sealed class RestartNoticeTracker
    {
        public ulong LastEventId { get; private set; }
        public DateTimeOffset Deadline { get; private set; }
        public bool Active => Deadline != default;
        public bool IsOffline(DateTimeOffset now) => Active && now >= Deadline;

        public (ServerStatusState Status, string Source) ResolveStatus(
            ServerStatusState status, string source, DateTimeOffset now) =>
            IsOffline(now) ? (ServerStatusState.Offline, "Game Chat restart") : (status, source);

        public bool Observe(ulong id, string body, DateTimeOffset now, bool allowExpired, out bool recovered)
        {
            recovered = false;
            if (id == 0 || id <= LastEventId || !TryParseRestartNotice(body, out var duration)) return false;
            var sent = DiscordTimestamp(id);
            if (sent > now.AddSeconds(5)) return false;
            if (duration == TimeSpan.Zero)
            {
                recovered = Active;
                Deadline = default;
            }
            else
            {
                var deadline = sent + duration;
                // Cold starts must not resurrect old missed reboots. Recover
                // an expired countdown only with recent covered source history.
                if (!Active && deadline <= now &&
                    (!allowExpired || deadline < now.AddMinutes(-10))) return false;
                Deadline = deadline;
            }
            LastEventId = id;
            return true;
        }
    }

    void RegisterRestartEvent(DiscordFeedRow row)
    {
        if (!row.VerifiedRestartAuthor) return;
        string body = row.Message.Body;
        if (!TryParseRestartNotice(body, out _))
        {
            body = row.MatchText;
            if (!TryParseRestartNotice(body, out _)) return;
        }
        if (!verifiedRestartEventIds.Add(row.Id)) return;
        archivedChat[row.Id] = ("Yagrum", body);
        chatArchiveDirty = true;
    }

    bool RestartSourceWindowCovered(ulong oldest)
    {
        ulong latest = verifiedRestartEventIds.Count == 0 ? 0 : verifiedRestartEventIds.Max();
        return latest != 0 && oldest != 0 && oldest <= latest &&
            DiscordTimestamp(latest) >= DateTimeOffset.UtcNow.AddHours(-1);
    }

    void DetectLatestRestartNotice()
    {
        if (closingChat || IsDisposed || verifiedRestartEventIds.Count == 0) return;
        ulong id = verifiedRestartEventIds.Max();
        if (!archivedChat.TryGetValue(id, out var entry)) return;
        var now = DateTimeOffset.UtcNow;
        bool covered = initialBackfillComplete && happyHourTailConfirmed &&
            happyHourSearchOldestId != 0 && happyHourSearchOldestId <= id;
        if (!restartNotice.Observe(id, entry.Body, now, covered, out bool recovered)) return;
        nextRestartBannerRefresh = default;
        nextRestartStatusHeartbeat = default;
        if (recovered)
        {
            // In-flight probes from before the reboot cannot undo recovery.
            serverStatusRevision++;
            nextServerStatusCheck = DateTime.MinValue;
            PublishServerStatus(ServerStatusState.Online, "Game Chat reboot");
            Log("SERVER RESTART | Verified reboot confirmation; resumed status probes");
            RefreshHappyHourBanner();
        }
        else if (restartNotice.Active)
        {
            Log("SERVER RESTART | Verified countdown; deadline=" + restartNotice.Deadline.ToString("O"));
            MaintainRestartNotice();
        }
    }

    void MaintainRestartNotice()
    {
        if (closingChat || IsDisposed || !restartNotice.Active) return;
        var now = DateTimeOffset.UtcNow;
        // Keep the IPC heartbeat fresh independently of asynchronous probes.
        if (restartNotice.IsOffline(now) && now >= nextRestartStatusHeartbeat)
        {
            nextRestartStatusHeartbeat = now.AddSeconds(10);
            PublishServerStatus(ServerStatusState.Offline, "Game Chat restart");
        }
        if (now >= nextRestartBannerRefresh)
        {
            nextRestartBannerRefresh = now.AddSeconds(1);
            RefreshHappyHourBanner();
        }
    }

    public static int CheckRestartNoticeCoverage()
    {
        var now = new DateTimeOffset(2026, 11, 27, 14, 0, 0, TimeSpan.Zero);
        static ulong IdAt(DateTimeOffset t) => (ulong)(t.ToUnixTimeMilliseconds() - 1420070400000L) << 22;
        const string reboot = "[SERVER]: -- SERVER WAS JUST REBOOTED --";
        static string Warning(int amount, string units) => "[SERVER]: -- Server is restarting in " + amount + " " + units + ". --";
        var tracker = new RestartNoticeTracker();
        if (TryParseRestartNotice("Player: " + Warning(10, "seconds"), out _) ||
            TryParseRestartNotice(Warning(0, "seconds"), out _) ||
            TryParseRestartNotice(Warning(61, "minutes"), out _) ||
            TryParseRestartNotice(reboot + " extra", out _)) return 1;
        foreach (int minutes in new[] { 60, 45, 30, 15, 10, 5, 2 })
            if (!TryParseRestartNotice(Warning(minutes, "minutes"), out var parsedMinutes) ||
                parsedMinutes != TimeSpan.FromMinutes(minutes)) return 2;
        foreach (int seconds in new[] { 60, 30, 15, 10 })
            if (!TryParseRestartNotice(Warning(seconds, "seconds"), out var parsedSeconds) ||
                parsedSeconds != TimeSpan.FromSeconds(seconds)) return 3;
        ulong first = IdAt(now.AddMinutes(-60)), last = IdAt(now.AddSeconds(-10));
        if (!tracker.Observe(first, Warning(60, "minutes"), now.AddMinutes(-59), false, out _) ||
            !tracker.Observe(last, Warning(10, "seconds"), now.AddSeconds(-7), false, out _) ||
            tracker.IsOffline(now.AddSeconds(-1)) || !tracker.IsOffline(now) ||
            !tracker.IsOffline(now.AddHours(2)) ||
            tracker.Observe(first, Warning(60, "minutes"), now, true, out _)) return 4;
        foreach (var probe in Enum.GetValues<ServerStatusState>())
        {
            if (tracker.ResolveStatus(probe, "Wiki", now.AddSeconds(-1)) != (probe, "Wiki") ||
                tracker.ResolveStatus(probe, "Discord", now) != (ServerStatusState.Offline, "Game Chat restart"))
                return 9;
        }
        ulong done = IdAt(now.AddMinutes(3));
        if (!tracker.Observe(done, reboot, now.AddMinutes(3), true, out bool recovered) ||
            !recovered || tracker.Active || tracker.IsOffline(now.AddMinutes(4)) ||
            tracker.Observe(last, Warning(10, "seconds"), now.AddMinutes(4), true, out _)) return 5;
        foreach (var probe in Enum.GetValues<ServerStatusState>())
            if (tracker.ResolveStatus(probe, "Discord", now.AddMinutes(4)) != (probe, "Discord")) return 10;
        var cold = new RestartNoticeTracker();
        if (cold.Observe(last, Warning(10, "seconds"), now.AddMinutes(3), false, out _) ||
            cold.Observe(last, Warning(10, "seconds"), now.AddHours(2), true, out _) ||
            !cold.Observe(last, Warning(10, "seconds"), now.AddMinutes(2), true, out _) ||
            !cold.IsOffline(now.AddMinutes(2)) ||
            cold.Observe(IdAt(now.AddDays(1)), Warning(60, "minutes"), now, true, out _)) return 6;
        var replay = new RestartNoticeTracker();
        if (!replay.Observe(done, reboot, now.AddMinutes(4), true, out bool replayRecovered) ||
            replayRecovered || replay.Active ||
            replay.Observe(last, Warning(10, "seconds"), now.AddMinutes(4), true, out _)) return 7;
        var rows = DiscordFeedReader.Read("[{\"id\":\"chat-messages-1-123\",\"body\":\"test\",\"verifiedRestartAuthor\":true}," +
            "{\"id\":\"chat-messages-1-124\",\"body\":\"test\",\"sourceAuthor\":\"Yagrum\"}]");
        if (rows.Count != 2 || !rows[0].VerifiedRestartAuthor || rows[1].VerifiedRestartAuthor) return 8;
        return 0;
    }
}
