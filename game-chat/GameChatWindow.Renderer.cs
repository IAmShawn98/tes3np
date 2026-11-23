using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;

internal sealed partial class GameChatWindow
{
    readonly ScrollbarFreeRichTextBox nativeMessages = new()
    {
        ReadOnly = true, BorderStyle = BorderStyle.None, ScrollBars = RichTextBoxScrollBars.None,
        BackColor = System.Drawing.Color.FromArgb(10, 9, 8),
        ForeColor = System.Drawing.Color.FromArgb(237, 231, 220),
        DetectUrls = false, TabStop = false, ShortcutsEnabled = false
    };

    readonly WebView2 messageBrowser = new() { Dock = DockStyle.Fill, Visible = true };

    bool messageBrowserReady, messageViewportReady;

    ulong messagePageNavigationId;

    DateTime nextMessagePageReload;

    int browserScrollTop, browserScrollHeight = 1, browserClientHeight = 1;

    static readonly Lazy<string> MessagePage = GameChatWeb.Page("message-feed.html");

    async Task InitMessageBrowser(CoreWebView2Environment env)
    {
        try
        {
            await messageBrowser.EnsureCoreWebView2Async(env);
            messageBrowser.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            messageBrowser.CoreWebView2.Settings.AreDevToolsEnabled = false;
            messageBrowser.CoreWebView2.WebMessageReceived += (_, args) =>
            {
                try
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(args.WebMessageAsJson);
                    var root = doc.RootElement;
                    var type = root.GetProperty("type").GetString();
                    if (type == "interaction")
                    {
                        if (chatOpen) lastChatActivity = DateTime.Now;
                        if (root.TryGetProperty("stopHistory", out var stop) && stop.ValueKind == System.Text.Json.JsonValueKind.True)
                            historyCatchupActive = false;
                        return;
                    }
                    if (type != "scroll") return;
                    browserScrollTop = (int)Math.Round(root.GetProperty("top").GetDouble());
                    browserScrollHeight = (int)Math.Round(root.GetProperty("height").GetDouble());
                    browserClientHeight = (int)Math.Round(root.GetProperty("client").GetDouble());
                    userScrolledChat = root.TryGetProperty("userScrolled", out var interacted) && interacted.GetBoolean();
                    // Returning to the live end stops old-history catchup
                    // even when the user scrolls instead of clicking the button.
                    if (browserScrollHeight - browserClientHeight - browserScrollTop <= 96)
                        historyCatchupActive = false;
                    goldScrollbar.Invalidate();
                    if (userScrolledChat && browserScrollTop < Math.Max(900, browserClientHeight * 3)) RequestOlderMessages();
                }
                catch (Exception ex) { Log("HTML scroll telemetry error: " + ex.GetType().Name); }
            };
            // Start the local message document before the Discord login.
            // A hidden host may defer WebView2 work until its dock is shown,
            // so startup waits only briefly and the live feed can retry.
            var rendererNavigation = new TaskCompletionSource<bool>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            messageBrowser.NavigationStarting += (_, e) =>
            {
                messagePageNavigationId = e.NavigationId;
                messageBrowserReady = messageViewportReady = false;
            };
            messageBrowser.NavigationCompleted += (_, e) =>
            {
                if (e.NavigationId != messagePageNavigationId) return;
                messageBrowserReady = e.IsSuccess;
                if (e.IsSuccess) Log("HTML message renderer ready");
                else Log("HTML message renderer navigation failed: " + e.WebErrorStatus);
                rendererNavigation.TrySetResult(e.IsSuccess);
            };
            NavigateMessagePage();
            try
            {
                if (!await rendererNavigation.Task.WaitAsync(TimeSpan.FromSeconds(8)))
                    Log("CHAT | Native renderer navigation failed; continuing Discord login");
            }
            catch (TimeoutException)
            {
                // Do not trap the user on a loading screen: the renderer
                // completion callback can still mark itself ready later.
                Log("CHAT | Native renderer still loading; continuing Discord login");
            }
        }
        catch (Exception ex) { Log("HTML renderer initialization failed: " + ex.GetType().Name); }
    }

    void NavigateMessagePage()
    {
        nextMessagePageReload = DateTime.UtcNow.AddSeconds(8);
        messageBrowserReady = messageViewportReady = false;
        messageBrowser.NavigateToString(MessagePage.Value);
    }

    void RecoverMessagePage(string reason)
    {
        if (closingChat || IsDisposed || discordLoginVisible || !discordChannelReady ||
            messageBrowser.CoreWebView2 == null || DateTime.UtcNow < nextMessagePageReload) return;
        Log("CHAT | Reloading local message renderer (" + reason + ")");
        ShowConnectingChat();
        try { NavigateMessagePage(); }
        catch (Exception ex) { Log("CHAT | Local renderer reload failed: " + ex.GetType().Name); }
    }

    void ScrollHtml(int pixels)
    {
        if (messageBrowserReady && messageBrowser.CoreWebView2 != null)
            _ = messageBrowser.CoreWebView2.ExecuteScriptAsync("window.scrollChat(" + pixels + ")");
    }

    bool nativeMode;

    void ShowConnectingChat()
    {
        if (closingChat || IsDisposed || discordLoginVisible) return;
        connectingChat = true;
        nativeMode = messageViewportReady = false;
        // Make the loading state visible on the existing custom frame.
        // Do not display the old mock scrollbar while the real HTML feed
        // is still mounting after the Discord OAuth handoff.
        nativeMessages.Text = "Connecting to live chat...";
        frameSurface.Visible = true;
        messageClip.Visible = true;
        // Keep the WebView2 sized and visible behind the native status so
        // its compositor can start when the chat dock is shown.
        messageBrowser.Visible = true;
        nativeMessages.Visible = true;
        nativeMessages.BringToFront();
        goldScrollbar.Visible = false;
        chatViewport.Visible = false;
        FitWebView();
        messageClip.BringToFront();
        frameSurface.Invalidate();
        Log("CHAT | Waiting for authenticated message feed");
    }

    async Task RenderNativeMessagesAsync(ulong feedNavigationId, bool prepended)
    {
        if (!messageBrowserReady || messageBrowser.CoreWebView2 == null)
        {
            RecoverMessagePage("page unavailable");
            return;
        }
        // A hidden WebView2 reports stale/zero scroll metrics. Give the
        // first authenticated renderer a real-sized parent before DOM
        // reconciliation, keeping the native loading text in front
        // until the message script succeeds.
        bool enteringNativeMode = !nativeMode;
        if (enteringNativeMode)
        {
            messageClip.Visible = true;
            messageBrowser.Visible = true;
            messageBrowser.BringToFront();
            nativeMessages.Visible = true;
            nativeMessages.BringToFront();
            messageClip.PerformLayout();
        }
        var browserMessages = history.Select(entry => new
        {
            id = entry.Key.ToString(),
            timestamp = DiscordTimestamp(entry.Key).ToString("O"),
            user = entry.Value.User,
            body = entry.Value.Body,
            isYagrum = entry.Value.IsYagrum,
            authorColor = entry.Value.AuthorColor,
            images = entry.Value.Images
        }).ToArray();
        string payload = System.Text.Json.JsonSerializer.Serialize(browserMessages);
        bool requireViewport = chatOpen;
        ulong pageNavigationId = messagePageNavigationId;
        string script = "typeof window.setMessages === 'function' && window.setMessages(" +
            payload + "," + (prepended ? "true" : "false") + "," + (requireViewport ? "true" : "false") + ")";
        string rendered;
        try
        {
            rendered = await messageBrowser.CoreWebView2.ExecuteScriptAsync(script)
                .WaitAsync(TimeSpan.FromSeconds(4));
        }
        catch (Exception ex)
        {
            imagesNeedRedraw = true;
            if (pageNavigationId == messagePageNavigationId && feedNavigationId == discordNavigationId)
                RecoverMessagePage("render attempt failed: " + ex.GetType().Name);
            return;
        }
        if (closingChat || IsDisposed || discordLoginVisible || !discordChannelReady) return;
        if (pageNavigationId != messagePageNavigationId || feedNavigationId != discordNavigationId ||
            discordNavigationInProgress)
        {
            imagesNeedRedraw = true;
            return;
        }
        if (chatOpen && !requireViewport)
        {
            // The dock was opened while the hidden renderer was busy.
            // Check its actual visible viewport on the next pass.
            imagesNeedRedraw = true;
            return;
        }
        if (rendered != "true")
        {
            imagesNeedRedraw = true;
            RecoverMessagePage("page did not confirm message rows");
            return;
        }
        messageViewportReady = requireViewport && chatOpen;
        if (enteringNativeMode)
        {
            nativeMode = true;
            connectingChat = false;
            if (chatOpen) lastChatActivity = DateTime.Now;
            if (web.Parent == chatViewport) web.Visible = false;
            chatViewport.Visible = false;
            // Sign-in hides the renderer's parent AND the real scrollbar.
            // Show the correctly sized WebView and textured scrollbar
            // together only after the first successful message update.
            messageClip.Visible = true;
            messageBrowser.Visible = true;
            goldScrollbar.Visible = true;
            frameSurface.Visible = true;
            FitWebView();
            messageClip.PerformLayout();
            messageBrowser.BringToFront();
            nativeMessages.Visible = false;
            messageClip.BringToFront();
            goldScrollbar.BringToFront();
            frameSurface.Invalidate(true);
            frameSurface.Update();
            goldScrollbar.Update();
            Log("Native message view activated");
        }
        else goldScrollbar.Invalidate();
    }
}
