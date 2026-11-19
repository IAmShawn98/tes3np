using static GameChatNative;

internal sealed partial class GameChatWindow
{
    readonly System.Collections.Generic.Dictionary<string, bool> happyHourImageClassification = new();

    // Discord can virtualize an image-only message out of the DOM while
    // its image is downloading. Retain the original bot message IDs.
    readonly System.Collections.Generic.Dictionary<string, System.Collections.Generic.HashSet<ulong>> happyHourImageMessageIds = new();

    // The real Yagrum activation is a small rainbow-on-black image:
    // red/yellow at the left, cyan/violet in the middle and sustained
    // green lettering on the right. Compare decoded pixels, not body text
    // or attachment filenames. The original Discord snowflake still
    // supplies the ONLY event timestamp.
    static bool LooksLikeHappyHourImage(System.Drawing.Image source)
    {
        if (source is not System.Drawing.Bitmap bitmap) return false;
        int w = bitmap.Width, h = bitmap.Height;
        if (w < 120 || h < 8 || w < h * 5) return false;
        int red = 0, yellow = 0, cyan = 0, violet = 0, green = 0;
        for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++)
        {
            var pixel = bitmap.GetPixel(x, y);
            if (pixel.A < 70) continue;
            int r = pixel.R, g = pixel.G, b = pixel.B;
            double position = (double)x / w;
            if (position < .19 && r > 110 && r > g * 1.45 && r > b * 1.4) red++;
            if (position > .05 && position < .30 && r > 140 && g > 100 && b < 100 &&
                r > b * 1.6 && g > b * 1.4) yellow++;
            if (position > .07 && position < .38 && b > 120 && g > 105 && r < 120) cyan++;
            if (position > .20 && position < .58 && r > 75 && b > 95 &&
                g < Math.Max(r, b) * .8) violet++;
            if (position > .50 && g > 110 && g > r * 1.5 && g > b * 1.3) green++;
        }
        return red >= 10 && yellow >= 8 && cyan >= 6 &&
               violet >= 10 && green >= 30;
    }

    bool IsVerifiedHappyHourImageUrl(string url)
    {
        if (happyHourImageClassification.TryGetValue(url, out bool verified))
            return verified;
        if (!imageCache.TryGetValue(url, out var image)) return false;
        verified = LooksLikeHappyHourImage(image);
        happyHourImageClassification[url] = verified;
        if (verified)
            Log("HAPPY HOUR | Matched rainbow announcement image pixels from Discord attachment");
        return verified;
    }

    void RecognizePendingHappyHourImage(string url)
    {
        if (!happyHourImageMessageIds.TryGetValue(url, out var messageIds) ||
            !IsVerifiedHappyHourImageUrl(url)) return;
        bool newlyVerified = false;
        foreach (ulong messageId in messageIds)
        {
            if (!verifiedHappyHourImageIds.Add(messageId)) continue;
            newlyVerified = true;
            Log("HAPPY HOUR | Verified real rainbow-image announcement " +
                "messageId=" + messageId + "; sent=" +
                DiscordTimestamp(messageId).ToString("O"));
        }
        if (!newlyVerified) return;
        // Save even if Discord has already replaced this virtualized
        // message in its source viewport. The next restart can shortcut.
        chatArchiveDirty = true;
        DetectLatestHappyHour();
    }

    // A Happy Hour exists only within one hour of its authentic Discord
    // activation message. Expired announcements are never displayed.
    ulong lastHappyHourMessageId;

    static bool IsHappyHourAnnouncement(string body)
    {
        if (string.IsNullOrWhiteSpace(body)) return false;
        // Discord's colored per-letter spans and invisible separators can
        // insert punctuation or whitespace INSIDE words, not just between
        // them. Match the complete activation phrase after normalizing the
        // rendered letters; never generate a message or timestamp.
        string normalized = System.Text.RegularExpressions.Regex.Replace(
            body.Normalize(System.Text.NormalizationForm.FormKC),
            @"[^\p{L}\p{Nd}]", "");
        return normalized.Contains("happyhourhasbeenactivated",
            StringComparison.OrdinalIgnoreCase);
    }

    ulong LatestArchivedHappyHourId()
    {
        // SortedDictionary keys are Discord snowflakes, ordered by time.
        // Verified image posts carry their original Discord message ID,
        // just like text announcements. Never manufacture an activation.
        ulong latest = 0;
        foreach (ulong imageId in verifiedHappyHourImageIds)
            if (imageId > latest) latest = imageId;
        foreach (var entry in archivedChat.Reverse()) {
            if (entry.Key <= latest) break;
            // A player repeating these words is not a bot activation.
            // The image detector also requires an actual Yagrum post.
            if (IsHappyHourAuthor(entry.Value.User) &&
                IsHappyHourAnnouncement(entry.Value.Body)) {
                latest = entry.Key;
                break;
            }
        }
        // The native chat can already display a message before its batch
        // is written to disk. Always inspect that same in-memory history.
        foreach (var entry in history.Reverse()) {
            if (entry.Key <= latest) break;
            if (IsHappyHourAuthor(entry.Value.User) &&
                IsHappyHourAnnouncement(entry.Value.Body)) {
                latest = entry.Key;
                break;
            }
        }
        return latest;
    }

    void DetectLatestHappyHour()
    {
        if (closingChat || IsDisposed) return;
        try
        {
            EnsureChatLogLoaded();
            ulong latest = LatestArchivedHappyHourId();
            if (latest > lastHappyHourMessageId &&
                DiscordTimestamp(latest).AddHours(1) > DateTimeOffset.UtcNow) {
                Log("HAPPY HOUR | Verified latest Discord announcement " + latest +
                    " at " + DiscordTimestamp(latest).ToString("O") + " (active)");
                ShowHappyHourBannerForMessage(latest);
            }
        }
        catch (Exception ex) { Log("HAPPY HOUR | Scan failed: " + ex.GetType().Name); }
    }

    void BeginHappyHourDiscovery()
    {
        if (closingChat || IsDisposed) return;
        try
        {
            // Genuine archived Discord messages (text or pixel-verified
            // bot images) are sufficient evidence without login. Only
            // live discovery and historical paging require authentication.
            EnsureChatLogLoaded();
            ulong candidate = LatestArchivedHappyHourId();
            bool valid = candidate > 0 &&
                DiscordTimestamp(candidate).AddHours(1) > DateTimeOffset.UtcNow;
            // A valid cached announcement is evidence for that event,
            // NOT proof it is the most recent one. The Discord source may
            // currently show only newer messages (or have resumed at an
            // old read position). Skipping pagination here can hide a new
            // Happy Hour while the game is already counting it down.
            // Display the cached event if still active, then independently
            // cover the live channel back through that timestamp or the
            // one-hour active window. Do not depend on the chat being open.
            initialBackfillComplete = false;
            initialBackfillStarted = DateTime.MinValue;
            initialBackfillAttempts = 0;
            if (valid)
            {
                Log("HAPPY HOUR | Verified cached activation: " +
                    "messageId=" + candidate +
                    "; sent=" + DiscordTimestamp(candidate).ToString("O") +
                    "; archivedRows=" + archivedChat.Count +
                    "; checking for a newer Discord activation");
                DetectLatestHappyHour();
            }
            else
            {
                Log("HAPPY HOUR | No verified announcement in saved chat archive; " +
                    "archivedRows=" + archivedChat.Count +
                    "; live search will begin if the Discord channel becomes available");
            }
        }
        catch (Exception ex)
        {
            Log("HAPPY HOUR | Startup log check failed; will page Discord: " + ex.GetType().Name);
        }
    }

    // WM_APP + 0x334: Jiub follows the genuine Discord-backed banner.
    void NotifyLauncherHappyHourFace(bool active)
    {
        if (IsWindow(owner))
            PostMessage(owner, 0x8334, active ? new IntPtr(1) : IntPtr.Zero, IntPtr.Zero);
    }

    void RegisterHappyHourImages(ulong key, string sourceAuthor, string[] images)
    {
        if (images.Length == 0 || !IsHappyHourAuthor(sourceAuthor)) return;

        // Register Yagrum's genuine bot message BEFORE requesting
        // its image. A late image download must still recognize
        // this original snowflake after Discord pages farther back.
        foreach (string imageUrl in images)
        {
            if (!happyHourImageMessageIds.TryGetValue(imageUrl, out var ids))
            {
                ids = new System.Collections.Generic.HashSet<ulong>();
                happyHourImageMessageIds[imageUrl] = ids;
            }
            ids.Add(key);
            if (imageCache.ContainsKey(imageUrl))
                RecognizePendingHappyHourImage(imageUrl);
        }

        if (loggedHappyHourImageCandidates.Add(key))
            Log("HAPPY HOUR | Examining image posted by Yagrum " +
                "messageId=" + key + "; imageHosts=" +
                string.Join(",", images.Select(url =>
                    Uri.TryCreate(url, UriKind.Absolute, out var uri)
                        ? uri.Host : "invalid")));
        if (!verifiedHappyHourImageIds.Contains(key) &&
            images.Any(url => imageCache.ContainsKey(url)) &&
            loggedHappyHourImageMisses.Add(key))
            Log("HAPPY HOUR | Yagrum image did not match rainbow signature " +
                "messageId=" + key + "; decodedSizes=" +
                string.Join(",", images.Where(url => imageCache.ContainsKey(url))
                    .Select(url => imageCache[url].Width + "x" + imageCache[url].Height)));
    }

    static bool IsHappyHourAuthor(string user) =>
        user.Contains("Yagrum", StringComparison.OrdinalIgnoreCase);
}
