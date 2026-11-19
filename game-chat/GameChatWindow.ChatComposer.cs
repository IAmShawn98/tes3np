using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const int ChatComposerHeight = 36, ChatComposerSpace = 41;
    static readonly Lazy<string> ChatComposerScript = GameChatWeb.Page("discord-chat-composer.js");
    readonly Panel chatComposerViewport = new() { Visible = false, BackColor = Color.FromArgb(23, 18, 14) };
    readonly Label chatComposerStatus = new()
    {
        Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter,
        ForeColor = Color.FromArgb(201, 179, 137), BackColor = Color.FromArgb(23, 18, 14),
        Text = "Opening Discord composer…"
    };
    WebView2? chatComposerBrowser;
    Size composerClip;
    bool composerNavigationReady;
    DateTime nextComposerAttempt;

    void InitializeChatComposer()
    {
        frameSurface.Controls.Add(chatComposerViewport);
        chatComposerViewport.Controls.Add(chatComposerStatus);
    }

    void FitChatComposer()
    {
        chatComposerViewport.Visible = nativeMode && !discordLoginVisible;
        if (!nativeMode || discordLoginVisible) return;
        chatComposerViewport.SetBounds(ChatPixels(15), ClientSize.Height - ChatPixels(14 + ChatComposerHeight),
            Math.Max(1, ClientSize.Width - ChatPixels(30)), ChatPixels(ChatComposerHeight));
        if (chatComposerBrowser is { IsDisposed: false } browser) SizeChatComposer(browser);
    }

    void SizeChatComposer(WebView2 browser)
    {
        var clip = chatComposerViewport.ClientSize;
        if (clip.Width < 1 || clip.Height < 1) return;
        var size = new Size(Math.Max(clip.Width, ChatPixels(940)), ChatPixels(580));
        if (browser.Size != size) browser.Size = size;
        if (browser.CoreWebView2 != null) SetBrowserScale(browser, chatScale);
        if (browser.IsHandleCreated && clip != composerClip)
        {
            IntPtr region = CreateRectRgn(0, 0, clip.Width, clip.Height);
            if (region != IntPtr.Zero)
            {
                if (SetWindowRgn(browser.Handle, region, true) != 0) composerClip = clip;
                else DeleteObject(region);
            }
        }
        if (composerNavigationReady && browser.CoreWebView2 is { } core && IsComposerRoute(core.Source))
        {
            core.PostWebMessageAsJson(JsonSerializer.Serialize(new
            {
                type = "tes3np-composer-size",
                width = clip.Width / chatScale,
                height = clip.Height / chatScale
            }));
        }
    }

    static bool IsComposerRoute(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.UserInfo.Length == 0 && uri.IsDefaultPort &&
        string.Equals(uri.GetLeftPart(UriPartial.Path).TrimEnd('/'), Channel, StringComparison.OrdinalIgnoreCase);

    async Task EnsureChatComposer()
    {
        if (!chatOpen || !nativeMode || closingChat || discordLoginVisible || !discordChannelReady ||
            discordAccountStatus != DiscordAccountStatus.SignedIn || chatComposerBrowser != null ||
            DateTime.UtcNow < nextComposerAttempt || discordEnvironment is not { } environment) return;

        var browser = chatComposerBrowser = new WebView2 { DefaultBackgroundColor = chatComposerViewport.BackColor };
        try
        {
            browser.HandleCreated += (_, _) =>
            {
                if (browser != chatComposerBrowser) return;
                composerClip = Size.Empty;
                SizeChatComposer(browser);
            };
            chatComposerViewport.Controls.Add(browser);
            SetComposerStatus("Opening Discord composer…");
            SizeChatComposer(browser);
            await browser.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(8));
            if (browser != chatComposerBrowser || closingChat) return;
            var core = browser.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.AreDevToolsEnabled = false;
            core.NewWindowRequested += (_, e) => e.Handled = true;
            core.DownloadStarting += (_, e) => e.Cancel = true;
            core.NavigationStarting += (_, e) =>
            {
                e.Cancel = !IsComposerRoute(e.Uri);
                if (!e.Cancel && browser == chatComposerBrowser)
                {
                    composerNavigationReady = false;
                    SetComposerStatus("Opening Discord composer…");
                }
            };
            core.SourceChanged += (_, _) =>
            {
                if (browser == chatComposerBrowser && !IsComposerRoute(core.Source))
                    SetComposerStatus("Discord composer unavailable.");
            };
            core.NavigationCompleted += (_, e) =>
            {
                if (browser != chatComposerBrowser) return;
                composerNavigationReady = e.IsSuccess && IsComposerRoute(core.Source);
                if (composerNavigationReady) SizeChatComposer(browser);
                else SetComposerStatus("Discord composer unavailable.");
            };
            core.ProcessFailed += (_, _) =>
            {
                if (browser != chatComposerBrowser) return;
                SetComposerStatus("Discord composer unavailable. Retrying…");
                nextComposerAttempt = DateTime.UtcNow.AddSeconds(10);
                BeginInvoke((Action)(() =>
                {
                    if (browser == chatComposerBrowser) CloseChatComposer();
                }));
            };
            core.WebMessageReceived += (_, e) =>
            {
                if (browser != chatComposerBrowser || !IsComposerRoute(e.Source) || !IsComposerRoute(core.Source) ||
                    discordAccountStatus != DiscordAccountStatus.SignedIn) return;
                try
                {
                    using var message = JsonDocument.Parse(e.WebMessageAsJson);
                    if (!message.RootElement.TryGetProperty("type", out var type) || type.GetString() != "tes3np-composer" ||
                        !message.RootElement.TryGetProperty("state", out var state)) return;
                    SetComposerStatus(state.GetString() switch
                    {
                        "ready" => null,
                        "unavailable" => "Sending unavailable in this Discord channel.",
                        _ => "Opening Discord composer…"
                    });
                }
                catch (Exception ex) when (ex is JsonException or InvalidOperationException) { }
            };
            await core.AddScriptToExecuteOnDocumentCreatedAsync(
                "(" + ChatComposerScript.Value + ")(" + JsonSerializer.Serialize(Channel) + ");");
            if (browser == chatComposerBrowser && !closingChat) core.Navigate(Channel);
        }
        catch (Exception ex)
        {
            if (browser != chatComposerBrowser || closingChat) return;
            CloseChatComposer();
            nextComposerAttempt = DateTime.UtcNow.AddSeconds(10);
            SetComposerStatus("Discord composer unavailable. Retrying…");
            Log("CHAT | Discord composer: " + ex.GetType().Name);
        }
    }

    void SetComposerStatus(string? status)
    {
        if (status != null)
        {
            chatComposerStatus.Text = status;
            chatComposerStatus.Visible = true;
            chatComposerStatus.BringToFront();
        }
        else chatComposerStatus.Visible = false;
    }

    void CloseChatComposer()
    {
        var browser = chatComposerBrowser;
        chatComposerBrowser = null;
        composerNavigationReady = false;
        composerClip = Size.Empty;
        browser?.Dispose();
        SetComposerStatus("Opening Discord composer…");
    }

    bool ChatComposerHasFocus => chatComposerBrowser?.ContainsFocus == true;
}
