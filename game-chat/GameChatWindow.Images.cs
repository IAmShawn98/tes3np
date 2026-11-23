internal sealed partial class GameChatWindow
{
    readonly System.Collections.Generic.Dictionary<string, System.Drawing.Image> imageCache = new();

    readonly System.Collections.Generic.HashSet<string> pendingImages = new();

    readonly System.Collections.Generic.Dictionary<string, DateTime> failedImages = new();

    readonly System.Collections.Generic.Dictionary<string, int> failedImageAttempts = new();

    DateTime nextHappyHourImageRetry = DateTime.MinValue;

    // A quiet Discord feed must not starve a failed image-only Happy Hour.
    // Retry only still-active, Yagrum-attributed image candidates, on a
    // bounded backoff independent of whether the feed JSON changes.
    void RetryDueHappyHourImages()
    {
        DateTime now = DateTime.UtcNow;
        if (closingChat || IsDisposed || now < nextHappyHourImageRetry) return;
        nextHappyHourImageRetry = now.AddSeconds(2);
        foreach (var failed in failedImages.ToArray())
        {
            if (failed.Value > now || pendingImages.Contains(failed.Key) ||
                !happyHourImageMessageIds.TryGetValue(failed.Key, out var ids) ||
                !ids.Any(id => DiscordTimestamp(id).AddHours(1) > DateTimeOffset.UtcNow))
                continue;
            _ = FetchChatImage(failed.Key);
        }
    }

    static readonly System.Net.Http.HttpClient imageHttp = new() { Timeout = TimeSpan.FromSeconds(12) };

    bool imagesNeedRedraw;

    async Task FetchChatImage(string url)
    {
        if (imageCache.ContainsKey(url) || (failedImages.TryGetValue(url, out var retryAt) && DateTime.UtcNow < retryAt) || !pendingImages.Add(url)) return;
        try
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
                uri.Scheme != Uri.UriSchemeHttps ||
                !(uri.Host.EndsWith(".discordapp.com", StringComparison.OrdinalIgnoreCase) ||
                  uri.Host.EndsWith(".discordapp.net", StringComparison.OrdinalIgnoreCase) ||
                  uri.Host.Equals("cdn.discordapp.com", StringComparison.OrdinalIgnoreCase))) return;
            // Discord's image proxy may serve WebP/AVIF, which System.Drawing/GDI+ cannot decode.
            // Ask the proxy for PNG so the native RichEdit preview can load reliably.
            if (uri.Host.Equals("media.discordapp.net", StringComparison.OrdinalIgnoreCase))
            {
                var builder = new UriBuilder(uri);
                var queryParts = builder.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
                    .Where(part => !part.StartsWith("format=", StringComparison.OrdinalIgnoreCase) &&
                                   !part.StartsWith("fm=", StringComparison.OrdinalIgnoreCase))
                    .ToList();
                queryParts.Add("format=png");
                builder.Query = string.Join("&", queryParts);
                uri = builder.Uri;
            }
            using var request = new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, uri);
            request.Headers.Referrer = new Uri("https://discord.com/");
            request.Headers.Accept.ParseAdd("image/png");
            using var response = await imageHttp.SendAsync(request, System.Net.Http.HttpCompletionOption.ResponseHeadersRead);
            if (!response.IsSuccessStatusCode)
                throw new System.Net.Http.HttpRequestException("HTTP " + (int)response.StatusCode +
                    " from " + uri.Host);
            if (response.Content.Headers.ContentLength > 8_000_000) return;
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(12));
            using var responseStream = await response.Content.ReadAsStreamAsync(timeout.Token);
            using var stream = new System.IO.MemoryStream();
            byte[] buffer = new byte[32_768];
            int read;
            while ((read = await responseStream.ReadAsync(buffer.AsMemory(), timeout.Token)) > 0)
            {
                if (stream.Length + read > 8_000_000) return;
                stream.Write(buffer, 0, read);
            }
            stream.Position = 0;
            using var original = System.Drawing.Image.FromStream(stream);
            if ((long)original.Width * original.Height > 32_000_000) return;
            int width = Math.Min(250, original.Width);
            int height = Math.Max(1, (int)Math.Round((double)original.Height * width / original.Width));
            if (height > 400) { width = Math.Max(1, width * 400 / height); height = 400; }
            var preview = new System.Drawing.Bitmap(width, height);
            using (var graphics = System.Drawing.Graphics.FromImage(preview))
            {
                graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                graphics.DrawImage(original, 0, 0, width, height);
            }
            if (IsDisposed || closingChat) { preview.Dispose(); return; }
            imageCache[url] = preview;
            RecognizePendingHappyHourImage(url);
            Log("Chat image decoded: " + original.Width + "x" + original.Height +
                " (" + (response.Content.Headers.ContentType?.MediaType ?? "unknown type") + ")");
            imagesNeedRedraw = true;
        }
        catch (Exception ex)
        {
            Log("Chat image unavailable (" + (Uri.TryCreate(url, UriKind.Absolute, out var failedUri)
                ? failedUri.Host : "invalid URL") + "): " + ex.GetType().Name);
        }
        finally
        {
            if (imageCache.ContainsKey(url))
            {
                failedImages.Remove(url);
                failedImageAttempts.Remove(url);
            }
            else if (!closingChat && !IsDisposed)
            {
                int attempts = failedImageAttempts.TryGetValue(url, out int previous)
                    ? previous + 1 : 1;
                failedImageAttempts[url] = attempts;
                bool activeCandidate = happyHourImageMessageIds.TryGetValue(url, out var ids) &&
                    ids.Any(id => DiscordTimestamp(id).AddHours(1) > DateTimeOffset.UtcNow);
                int delaySeconds = activeCandidate
                    ? Math.Min(120, 15 * (1 << Math.Min(attempts - 1, 3)))
                    : 120;
                failedImages[url] = DateTime.UtcNow.AddSeconds(delaySeconds);
            }
            pendingImages.Remove(url);
            imagesNeedRedraw = true;
        }
    }

    void LoadChatImages(string[] images)
    {
        foreach (string imageUrl in images)
            _ = FetchChatImage(imageUrl);
    }
}
