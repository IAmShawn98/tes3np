using System.Drawing;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const string ServerStatusChannel = "https://discord.com/channels/509601787901116437/511706884584243210";
    const string ServerStatusWiki = "https://wiki.nerevarineprophecies.com/Main_Page";
    const uint ServerStatusMessage = 0x833C;
    static readonly TimeSpan ServerStatusPollInterval = TimeSpan.FromSeconds(10);
    enum ServerStatusState { Unknown, Online, Offline }
    static readonly Lazy<string> SeekServerStatusTail = GameChatWeb.Page("seek-latest-messages.js");
    static readonly Lazy<string> ExtractServerStatusImage = GameChatWeb.Page("extract-server-status.js");
    static readonly HttpClient statusImageHttp = new(new HttpClientHandler { AllowAutoRedirect = false })
        { Timeout = TimeSpan.FromSeconds(10) };
    static readonly HttpClient statusWikiHttp = new(new HttpClientHandler
        { AllowAutoRedirect = false, UseCookies = false, AutomaticDecompression = DecompressionMethods.All })
        { Timeout = TimeSpan.FromSeconds(8) };
    ServerUpdatesWindow? serverStatusWindow;
    DateTime nextServerStatusCheck;
    bool readingServerStatus;
    int serverStatusRevision;
    DateTime serverStatusSourceDeadline;
    string? statusTail;
    ServerStatusState publishedServerStatus;
    bool serverStatusPublished;
    string? publishedServerStatusSource;

    bool ServerStatusAuthenticated => !closingChat && !IsDisposed &&
        discordAccountStatus == DiscordAccountStatus.SignedIn && !discordAccountDirty;

    static bool IsServerStatusRoute(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.UserInfo.Length == 0 && uri.IsDefaultPort &&
        string.Equals(uri.GetLeftPart(UriPartial.Path).TrimEnd('/'), ServerStatusChannel, StringComparison.OrdinalIgnoreCase);

    void PublishServerStatus(ServerStatusState status, string source)
    {
        if (closingChat || IsDisposed || !IsWindow(owner)) return;
        if (!serverStatusPublished || publishedServerStatus != status || publishedServerStatusSource != source)
            Log("SERVER STATUS | " + status + " (" + source + ")");
        serverStatusPublished = true;
        publishedServerStatus = status;
        publishedServerStatusSource = source;
        PostMessage(owner, ServerStatusMessage, new IntPtr((int)status), Handle);
    }

    void DiscardServerStatusSource()
    {
        var previous = serverStatusWindow;
        serverStatusWindow = null;
        statusTail = null;
        serverStatusSourceDeadline = default;
        previous?.Dispose();
    }

    void ResetServerStatus()
    {
        // Account changes supersede in-flight results from the old session.
        serverStatusRevision++;
        nextServerStatusCheck = DateTime.MinValue;
        DiscardServerStatusSource();
    }

    // Independent of the chat refresh/visibility/authentication loop. A
    // failed Discord read is not itself a published Unknown result.
    async Task RefreshServerStatus()
    {
        if (closingChat || IsDisposed || !IsWindow(owner) ||
            readingServerStatus || DateTime.UtcNow < nextServerStatusCheck) return;
        readingServerStatus = true;
        nextServerStatusCheck = DateTime.UtcNow + ServerStatusPollInterval;
        int revision = serverStatusRevision;
        try
        {
            bool useDiscord = ServerStatusAuthenticated && discordEnvironment != null;
            var result = await ResolveServerStatus(useDiscord, ReadDiscordServerStatus, ReadWikiServerStatus);
            if (revision == serverStatusRevision)
                PublishServerStatus(result.Status, result.Source);
        }
        catch (Exception ex)
        {
            if (!closingChat && !IsDisposed)
                Log("SERVER STATUS | Refresh unavailable: " + ex.GetType().Name);
        }
        finally
        {
            readingServerStatus = false;
        }
    }

    static async Task<(ServerStatusState Status, string Source)> ResolveServerStatus(
        bool useDiscord, Func<Task<ServerStatusState>> discord, Func<Task<ServerStatusState>> wiki)
    {
        ServerStatusState status;
        if (useDiscord)
        {
            try { status = await discord(); }
            catch { status = ServerStatusState.Unknown; }
            if (status != ServerStatusState.Unknown) return (status, "Discord");
        }
        try { status = await wiki(); }
        catch { status = ServerStatusState.Unknown; }
        return (status, status == ServerStatusState.Unknown ? "Neither" : "Wiki");
    }

    async Task<ServerStatusState> ReadDiscordServerStatus()
    {
        if (!ServerStatusAuthenticated || discordEnvironment is not { } environment)
            return ServerStatusState.Unknown;
        // Reopen a source that has not produced a confirmed image for a
        // bounded period, including a stalled initial Discord message list.
        if (serverStatusWindow != null && DateTime.UtcNow >= serverStatusSourceDeadline)
            DiscardServerStatusSource();
        var source = serverStatusWindow;
        try
        {
            if (source == null)
            {
                source = serverStatusWindow = new ServerUpdatesWindow();
                serverStatusSourceDeadline = DateTime.UtcNow.AddSeconds(45);
                source.Show();
                await source.Browser.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(8));
                if (!ServerStatusAuthenticated || source != serverStatusWindow || source.IsDisposed)
                    return ServerStatusState.Unknown;
                var core = source.Browser.CoreWebView2;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.IsWebMessageEnabled = false;
                core.NewWindowRequested += (_, e) => e.Handled = true;
                core.DownloadStarting += (_, e) => e.Cancel = true;
                core.NavigationStarting += (_, e) => e.Cancel = !IsServerStatusRoute(e.Uri);
                core.Navigate(ServerStatusChannel);
                nextServerStatusCheck = DateTime.UtcNow.AddSeconds(2);
                return ServerStatusState.Unknown;
            }
            source.PositionOffScreen();
            var channel = source.Browser.CoreWebView2;
            if (!IsServerStatusRoute(channel.Source))
            {
                if (channel.Source != "about:blank")
                    DiscardServerStatusSource();
                return ServerStatusState.Unknown;
            }
            string tailJson = await channel.ExecuteScriptAsync(SeekServerStatusTail.Value).WaitAsync(TimeSpan.FromSeconds(3));
            string? tail = JsonSerializer.Deserialize<string>(tailJson);
            if (!ServerStatusAuthenticated || source != serverStatusWindow || source.IsDisposed ||
                !IsServerStatusRoute(channel.Source)) return ServerStatusState.Unknown;
            if (tail == null || !tail.StartsWith("present:", StringComparison.Ordinal) ||
                !ulong.TryParse(tail.AsSpan(8), out _))
            {
                statusTail = null;
                return ServerStatusState.Unknown;
            }
            if (tail != statusTail)
            {
                statusTail = tail;
                nextServerStatusCheck = DateTime.UtcNow.AddSeconds(2);
                return ServerStatusState.Unknown;
            }
            string urlJson = await channel.ExecuteScriptAsync(ExtractServerStatusImage.Value +
                "(" + JsonSerializer.Serialize(tail.Substring(8)) + ")").WaitAsync(TimeSpan.FromSeconds(3));
            string? url = JsonSerializer.Deserialize<string>(urlJson);
            if (!ServerStatusAuthenticated || source != serverStatusWindow || source.IsDisposed ||
                !IsServerStatusRoute(channel.Source)) return ServerStatusState.Unknown;
            var status = await ReadServerStatusImage(url);
            if (!ServerStatusAuthenticated || source != serverStatusWindow || source.IsDisposed ||
                !IsServerStatusRoute(channel.Source)) return ServerStatusState.Unknown;
            string confirm = await channel.ExecuteScriptAsync(ExtractServerStatusImage.Value +
                "(" + JsonSerializer.Serialize(tail.Substring(8)) + ")").WaitAsync(TimeSpan.FromSeconds(3));
            var confirmed = ServerStatusAuthenticated && source == serverStatusWindow && !source.IsDisposed &&
                IsServerStatusRoute(channel.Source) && confirm == urlJson ? status : ServerStatusState.Unknown;
            if (confirmed != ServerStatusState.Unknown)
                serverStatusSourceDeadline = DateTime.UtcNow.AddSeconds(45);
            return confirmed;
        }
        catch (Exception ex)
        {
            if (source == serverStatusWindow && !closingChat && !IsDisposed)
            {
                Log("SERVER STATUS | Discord probe unavailable: " + ex.GetType().Name);
                DiscardServerStatusSource();
                nextServerStatusCheck = DateTime.UtcNow + ServerStatusPollInterval;
            }
            return ServerStatusState.Unknown;
        }
    }

    static ServerStatusState ParseWikiServerStatus(string html)
    {
        // Ignore markup, executable text and comments. Require the exact
        // server-status sentence, not unrelated mentions of online/offline.
        const RegexOptions options = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
        var timeout = TimeSpan.FromSeconds(1);
        string visible = Regex.Replace(html,
            @"<!--[\s\S]*?-->|<(script|style|template|noscript)\b[^>]*>[\s\S]*?</\1\s*>",
            " ", options, timeout);
        visible = WebUtility.HtmlDecode(Regex.Replace(visible, @"<[^>]*>", " ", options, timeout));
        var matches = Regex.Matches(visible,
            @"\bNerevarine\s+Prophecies\s+is\s+currently\s+(online|offline)\s*\.",
            options, timeout);
        var result = ServerStatusState.Unknown;
        foreach (Match match in matches)
        {
            var current = match.Groups[1].Value.Equals("online", StringComparison.OrdinalIgnoreCase)
                ? ServerStatusState.Online : ServerStatusState.Offline;
            if (result != ServerStatusState.Unknown && result != current) return ServerStatusState.Unknown;
            result = current;
        }
        return result;
    }

    async Task<ServerStatusState> ReadWikiServerStatus()
    {
        if (closingChat || IsDisposed) return ServerStatusState.Unknown;
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
            using var request = new HttpRequestMessage(HttpMethod.Get, ServerStatusWiki);
            request.Headers.UserAgent.ParseAdd("tes3np-status/1.0");
            request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true, NoStore = true };
            using var response = await statusWikiHttp.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            const int limit = 2_000_000;
            if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > limit ||
                response.Content.Headers.ContentType?.MediaType is not ("text/html" or "application/xhtml+xml"))
                return ServerStatusState.Unknown;
            using var input = await response.Content.ReadAsStreamAsync(timeout.Token);
            using var bytes = new MemoryStream();
            byte[] buffer = new byte[16384];
            int read;
            while ((read = await input.ReadAsync(buffer.AsMemory(), timeout.Token)) > 0)
            {
                if (bytes.Length + read > limit) return ServerStatusState.Unknown;
                bytes.Write(buffer, 0, read);
            }
            return ParseWikiServerStatus(System.Text.Encoding.UTF8.GetString(bytes.ToArray()));
        }
        catch (Exception ex)
        {
            if (!closingChat && !IsDisposed)
                Log("SERVER STATUS | Wiki probe unavailable: " + ex.GetType().Name);
            return ServerStatusState.Unknown;
        }
    }

    static bool IsStatusImageUri(string? url, out Uri? uri)
    {
        return Uri.TryCreate(url, UriKind.Absolute, out uri) && uri.Scheme == Uri.UriSchemeHttps &&
            uri.IsDefaultPort && uri.UserInfo.Length == 0 &&
            (uri.Host == "cdn.discordapp.com" || uri.Host == "media.discordapp.net") &&
            uri.AbsolutePath.StartsWith("/attachments/511706884584243210/", StringComparison.Ordinal);
    }

    static async Task<ServerStatusState> ReadServerStatusImage(string? url)
    {
        if (!IsStatusImageUri(url, out var uri)) return ServerStatusState.Unknown;
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
        request.Headers.Referrer = new Uri("https://discord.com/");
        using var response = await statusImageHttp.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
        if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > 2_000_000)
            return ServerStatusState.Unknown;
        using var input = await response.Content.ReadAsStreamAsync(timeout.Token);
        using var bytes = new MemoryStream();
        byte[] buffer = new byte[16384];
        int read;
        while ((read = await input.ReadAsync(buffer.AsMemory(), timeout.Token)) > 0)
        {
            if (bytes.Length + read > 2_000_000) return ServerStatusState.Unknown;
            bytes.Write(buffer, 0, read);
        }
        bytes.Position = 0;
        using var image = Image.FromStream(bytes, useEmbeddedColorManagement: false, validateImageData: true);
        if (image.Width < 80 || image.Height < 16 || image.Width > 2048 || image.Height > 1024)
            return ServerStatusState.Unknown;
        using var bitmap = new Bitmap(image);
        return ClassifyServerStatusImage(bitmap);
    }

    // Only call this for the validated attachment from the dedicated status
    // channel, which uses two images. A valid non-online image means Offline.
    static ServerStatusState ClassifyServerStatusImage(Bitmap bitmap) =>
        MatchOnlineStatusImage(bitmap) ? ServerStatusState.Online : ServerStatusState.Offline;

    // Screenshot-derived ONLINE glyph silhouette.
    static readonly string[] OnlineStatusMask =
    [
        "001111100011111111111100001111111111011011111110",
        "011111110011111010011100000111001111011011111110",
        "111001111011111010011100000111001111111011110111",
        "111000111011111110011100000111001011111011111100",
        "111000111011011110011100000111001011111011111100",
        "111000111011001110011100000111001001111011110000",
        "111000111011000110011100010111001000111011110001",
        "111100111011000110011100110111001000011011110001",
        "011111110011000010011111110111001000011011111111",
        "001111100011000111111111101111111100011011111110"
    ];

    // Offline, deterministic smoke check; no network, browser or user data.
    internal static int CheckServerStatusCoverage()
    {
        try
        {
            if (ParseWikiServerStatus("<p>Nerevarine Prophecies is currently <b>online</b>.</p>") != ServerStatusState.Online ||
                ParseWikiServerStatus("<p>Nerevarine&nbsp;Prophecies is currently <span>offline</span>.</p>") != ServerStatusState.Offline ||
                ParseWikiServerStatus("<p>Server status unavailable</p>") != ServerStatusState.Unknown ||
                ParseWikiServerStatus("Nerevarine Prophecies is currently online. Nerevarine Prophecies is currently offline.") != ServerStatusState.Unknown ||
                ParseWikiServerStatus("<script>Nerevarine Prophecies is currently online.</script><!-- Nerevarine Prophecies is currently offline. -->") != ServerStatusState.Unknown)
                return 1;
            using var bitmap = new Bitmap(230, 70);
            using (var graphics = Graphics.FromImage(bitmap))
            {
                graphics.Clear(Color.Black);
                graphics.FillRectangle(Brushes.Cyan, 5, 5, 192, 20);
                for (int y = 0; y < 10; y++)
                for (int x = 0; x < 48; x++)
                    if (OnlineStatusMask[y][x] == '1')
                        graphics.FillRectangle(Brushes.Lime, 20 + 2 * x, 35 + 2 * y, 2, 2);
            }
            if (ClassifyServerStatusImage(bitmap) != ServerStatusState.Online) return 2;
            using (var graphics = Graphics.FromImage(bitmap))
                graphics.FillRectangle(Brushes.Red, 20, 35, 96, 20);
            if (ClassifyServerStatusImage(bitmap) != ServerStatusState.Offline) return 3;
            foreach (var primary in Enum.GetValues<ServerStatusState>())
            foreach (var fallback in Enum.GetValues<ServerStatusState>())
            {
                int calls = 0;
                var result = ResolveServerStatus(true, () => Task.FromResult(primary),
                    () => { calls++; return Task.FromResult(fallback); }).GetAwaiter().GetResult();
                var expected = primary == ServerStatusState.Unknown ? fallback : primary;
                if (result.Status != expected || calls != (primary == ServerStatusState.Unknown ? 1 : 0) ||
                    result.Source != (primary != ServerStatusState.Unknown ? "Discord" :
                        fallback != ServerStatusState.Unknown ? "Wiki" : "Neither"))
                    return 4;
            }
            var signedOut = ResolveServerStatus(false,
                () => throw new InvalidOperationException("Signed-out check must not call Discord."),
                () => Task.FromResult(ServerStatusState.Online)).GetAwaiter().GetResult();
            int signedOutDiscordCalls = 0;
            var signedOutOffline = ResolveServerStatus(false,
                () => { signedOutDiscordCalls++; return Task.FromResult(ServerStatusState.Online); },
                () => Task.FromResult(ServerStatusState.Offline)).GetAwaiter().GetResult();
            if (signedOut != (ServerStatusState.Online, "Wiki") ||
                signedOutOffline != (ServerStatusState.Offline, "Wiki") || signedOutDiscordCalls != 0)
                return 7;
            var recovered = ResolveServerStatus(true,
                () => Task.FromException<ServerStatusState>(new InvalidOperationException()),
                () => Task.FromResult(ServerStatusState.Online)).GetAwaiter().GetResult();
            var failed = ResolveServerStatus(true,
                () => Task.FromResult(ServerStatusState.Unknown),
                () => Task.FromException<ServerStatusState>(new InvalidOperationException())).GetAwaiter().GetResult();
            if (recovered != (ServerStatusState.Online, "Wiki") ||
                failed != (ServerStatusState.Unknown, "Neither")) return 5;
            return 0;
        }
        catch { return 6; }
    }

    static bool IsStatusGreen(Color p) => p.A >= 64 && p.G > 55 && p.G > p.R + 18 && p.G > p.B + 18;
    static bool IsStatusBlue(Color p) => p.A >= 64 && p.B > 50 && p.B > p.R + 18 && p.G > p.R + 18;
    static bool MatchOnlineStatusImage(Bitmap bitmap)
    {
        int left = bitmap.Width, top = bitmap.Height, right = -1, bottom = -1;
        int blueLeft = bitmap.Width, blueTop = bitmap.Height, blueRight = -1, blueBottom = -1;
        for (int y = 0; y < bitmap.Height; y++)
        for (int x = 0; x < bitmap.Width; x++)
        {
            Color p = bitmap.GetPixel(x, y);
            if (IsStatusGreen(p))
            {
                left = Math.Min(left, x); top = Math.Min(top, y);
                right = Math.Max(right, x); bottom = Math.Max(bottom, y);
            }
            if (IsStatusBlue(p))
            {
                blueLeft = Math.Min(blueLeft, x); blueTop = Math.Min(blueTop, y);
                blueRight = Math.Max(blueRight, x); blueBottom = Math.Max(blueBottom, y);
            }
        }
        int w = right - left + 1, h = bottom - top + 1;
        int bw = blueRight - blueLeft + 1, bh = blueBottom - blueTop + 1;
        if (w < 30 || h < 6 || bw < 50 || bh < 6 || (double)w / h < 4.4 ||
            (double)w / h > 6.6 || blueBottom >= top || (double)bw / w < 1.6 ||
            (double)bw / w > 2.4 || left <= blueLeft) return false;
        int intersection = 0, union = 0;
        for (int gy = 0; gy < 10; gy++)
        for (int gx = 0; gx < 48; gx++)
        {
            int x0 = left + gx * w / 48, x1 = left + (gx + 1) * w / 48;
            int y0 = top + gy * h / 10, y1 = top + (gy + 1) * h / 10;
            x1 = Math.Max(x0 + 1, x1); y1 = Math.Max(y0 + 1, y1);
            int count = 0, total = 0;
            for (int y = y0; y < y1; y++)
            for (int x = x0; x < x1; x++)
            {
                total++;
                if (IsStatusGreen(bitmap.GetPixel(x, y))) count++;
            }
            bool actual = count * 100 >= total * 32;
            bool expected = OnlineStatusMask[gy][gx] == '1';
            if (actual && expected) intersection++;
            if (actual || expected) union++;
        }
        return union > 0 && (double)intersection / union >= 0.72;
    }
}
