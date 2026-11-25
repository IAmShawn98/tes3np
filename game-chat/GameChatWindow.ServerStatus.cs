using System.Drawing;
using System.Net.Http;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const string ServerStatusChannel = "https://discord.com/channels/509601787901116437/511706884584243210";
    const uint ServerStatusMessage = 0x833C;
    enum ServerStatusState { Unknown, Online, Offline }
    static readonly Lazy<string> SeekServerStatusTail = GameChatWeb.Page("seek-latest-messages.js");
    static readonly Lazy<string> ExtractServerStatusImage = GameChatWeb.Page("extract-server-status.js");
    static readonly HttpClient statusImageHttp = new(new HttpClientHandler { AllowAutoRedirect = false })
        { Timeout = TimeSpan.FromSeconds(10) };
    ServerUpdatesWindow? serverStatusWindow;
    DateTime nextServerStatusCheck;
    bool readingServerStatus;
    string? statusTail;
    ServerStatusState publishedServerStatus;
    bool serverStatusPublished;

    bool ServerStatusAuthenticated => !closingChat && !IsDisposed &&
        discordAccountStatus == DiscordAccountStatus.SignedIn && !discordAccountDirty;

    static bool IsServerStatusRoute(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.UserInfo.Length == 0 && uri.IsDefaultPort &&
        string.Equals(uri.GetLeftPart(UriPartial.Path).TrimEnd('/'), ServerStatusChannel, StringComparison.OrdinalIgnoreCase);

    void PublishServerStatus(ServerStatusState status)
    {
        if (closingChat || IsDisposed || !IsWindow(owner)) return;
        if (!serverStatusPublished || publishedServerStatus != status)
            Log("SERVER STATUS | " + status);
        serverStatusPublished = true;
        publishedServerStatus = status;
        PostMessage(owner, ServerStatusMessage, new IntPtr((int)status), Handle);
    }

    void ResetServerStatus()
    {
        var previous = serverStatusWindow;
        serverStatusWindow = null;
        statusTail = null;
        nextServerStatusCheck = DateTime.MinValue;
        previous?.Dispose();
        PublishServerStatus(ServerStatusState.Unknown);
    }

    async Task RefreshServerStatus()
    {
        if (!ServerStatusAuthenticated)
        {
            if (serverStatusWindow != null || publishedServerStatus != ServerStatusState.Unknown)
                ResetServerStatus();
            return;
        }
        if (readingServerStatus || DateTime.UtcNow < nextServerStatusCheck ||
            discordEnvironment is not { } environment) return;
        readingServerStatus = true;
        nextServerStatusCheck = DateTime.UtcNow.AddSeconds(10);
        var source = serverStatusWindow;
        try
        {
            if (source == null)
            {
                source = serverStatusWindow = new ServerUpdatesWindow();
                source.Show();
                await source.Browser.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(8));
                if (!ServerStatusAuthenticated || source != serverStatusWindow || source.IsDisposed) return;
                var core = source.Browser.CoreWebView2;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.IsWebMessageEnabled = false;
                core.NewWindowRequested += (_, e) => e.Handled = true;
                core.DownloadStarting += (_, e) => e.Cancel = true;
                core.NavigationStarting += (_, e) => e.Cancel = !IsServerStatusRoute(e.Uri);
                core.Navigate(ServerStatusChannel);
                PublishServerStatus(ServerStatusState.Unknown);
                return;
            }
            source.PositionOffScreen();
            var channel = source.Browser.CoreWebView2;
            if (!IsServerStatusRoute(channel.Source))
            {
                ResetServerStatus();
                nextServerStatusCheck = DateTime.UtcNow.AddSeconds(30);
                return;
            }
            string tailJson = await channel.ExecuteScriptAsync(SeekServerStatusTail.Value).WaitAsync(TimeSpan.FromSeconds(3));
            string? tail = JsonSerializer.Deserialize<string>(tailJson);
            if (!ServerStatusAuthenticated || source != serverStatusWindow || source.IsDisposed ||
                !IsServerStatusRoute(channel.Source)) return;
            if (tail == null || !tail.StartsWith("present:", StringComparison.Ordinal) ||
                !ulong.TryParse(tail.AsSpan(8), out _))
            {
                statusTail = null;
                PublishServerStatus(ServerStatusState.Unknown);
                return;
            }
            if (tail != statusTail)
            {
                statusTail = tail;
                PublishServerStatus(ServerStatusState.Unknown);
                nextServerStatusCheck = DateTime.UtcNow.AddSeconds(2);
                return;
            }
            string urlJson = await channel.ExecuteScriptAsync(ExtractServerStatusImage.Value +
                "(" + JsonSerializer.Serialize(tail.Substring(8)) + ")").WaitAsync(TimeSpan.FromSeconds(3));
            string? url = JsonSerializer.Deserialize<string>(urlJson);
            if (!ServerStatusAuthenticated || source != serverStatusWindow || source.IsDisposed ||
                !IsServerStatusRoute(channel.Source)) return;
            var status = await ReadServerStatusImage(url);
            if (!ServerStatusAuthenticated || source != serverStatusWindow || source.IsDisposed ||
                !IsServerStatusRoute(channel.Source)) return;
            // The source can change while the image is being retrieved.
            string confirm = await channel.ExecuteScriptAsync(ExtractServerStatusImage.Value +
                "(" + JsonSerializer.Serialize(tail.Substring(8)) + ")").WaitAsync(TimeSpan.FromSeconds(3));
            if (ServerStatusAuthenticated && source == serverStatusWindow && !source.IsDisposed &&
                IsServerStatusRoute(channel.Source))
                PublishServerStatus(confirm == urlJson ? status : ServerStatusState.Unknown);
        }
        catch (Exception ex)
        {
            if (source == serverStatusWindow && !closingChat && !IsDisposed)
            {
                Log("SERVER STATUS | Probe unavailable: " + ex.GetType().Name);
                ResetServerStatus();
                nextServerStatusCheck = DateTime.UtcNow.AddSeconds(30);
            }
        }
        finally { readingServerStatus = false; }
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
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
        request.Headers.Referrer = new Uri("https://discord.com/");
        using var response = await statusImageHttp.SendAsync(request, HttpCompletionOption.ResponseHeadersRead);
        if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > 2_000_000)
            return ServerStatusState.Unknown;
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(8));
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
        using var image = Image.FromStream(bytes);
        if (image.Width < 80 || image.Height < 16 || image.Width > 2048 || image.Height > 1024)
            return ServerStatusState.Unknown;
        using var bitmap = new Bitmap(image);
        return MatchOnlineStatusImage(bitmap) ? ServerStatusState.Online : ServerStatusState.Unknown;
    }

    // Screenshot-derived ONLINE glyph silhouette. No offline reference has
    // been observed yet: unmatched images must remain Unknown, never Offline.
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
