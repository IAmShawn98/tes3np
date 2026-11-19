using System.Drawing;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const string Channel = "https://discord.com/channels/509601787901116437/1384271857842130994";

    static readonly Lazy<string> Css = GameChatWeb.Page("discord-source.css");

    readonly WebView2 web = new() { Dock = DockStyle.None };

    // The download browser lives in the EXISTING ChatHost but is a native
    // child of the AutoHotkey mismatch dialog, not another owned popup.
    CoreWebView2Environment? discordEnvironment;

    // Keep the established bronze frame and a native "Connecting..." label
    // visible during the first authenticated Discord feed transition.
    bool connectingChat;

    bool freshDiscordProfile;

    bool discordLoginVisible;

    bool discordSignInRequested;
    bool discordSignInFromHeader;
    bool useHeaderSignInPrompt => discordSignInFromHeader && pendingExpansionPrompt == 0;

    DateTime discordSignInAttemptExpires;

    bool checkingDiscordAuthentication;

    ulong discordNavigationId;

    bool discordNavigationInProgress;

    DiscordSignInCard? discordSignInWindow;

    bool showChatAfterDiscordSignIn;

    string? discordIntegrationLogoDataUrl;

    // Authentication gates live Discord fetching/paging ONLY. A genuine
    // unexpired message already in the local chat archive is sufficient
    // to display Happy Hour, even if Discord is signed out.
    bool discordChannelReady;

    // Retry the first authenticated channel load once if its feed stalls.
    DateTime? channelRetryAt;

    readonly string cssFile = Path.Combine(AppContext.BaseDirectory, "chat.css");

    DateTime cssStamp;

    string userCss = Css.Value;

    async Task LoadCss()
    {
        if (!File.Exists(cssFile)) return;
        var stamp = File.GetLastWriteTimeUtc(cssFile);
        if (stamp == cssStamp) return;
        userCss = File.ReadAllText(cssFile);
        cssStamp = stamp;
        await ApplyCss();
        Log("CSS reloaded");
    }

    static string DiscordUserDataFolder => Path.Combine(ChatDataRoot, "chat-webview2");
    const string DiscordCacheArguments = "--disk-cache-size=134217728";
    bool discordUsesCacheOptions = true;

    async void StartDiscordAsync(object? sender, EventArgs e)
    {
        // Let WinForms finish showing the top-level host before parenting it.
        Log("STARTUP | WinForms shown; queuing dock");
        BeginInvoke((Action)(() => DockToLauncher()));
        // The saved Discord archive is our only offline evidence.
        // Load it immediately, whether this browser is signed in or not.
        DetectLatestHappyHour();
        try
        {
            string data = DiscordUserDataFolder;
            freshDiscordProfile = !Directory.Exists(data) || !Directory.EnumerateFileSystemEntries(data).Any();
            Directory.CreateDirectory(data);
            // Limit the HTTP disk cache without clearing the Discord profile.
            var options = new CoreWebView2EnvironmentOptions(DiscordCacheArguments);
            CoreWebView2Environment env;
            try
            {
                env = await CoreWebView2Environment.CreateAsync(null, data, options);
                await web.EnsureCoreWebView2Async(env);
            }
            catch (Exception ex) when (ex.HResult == unchecked((int)0x8007139F))
            {
                // An earlier host may still be closing a browser opened
                // with the default options. Reuse that profile.
                env = await CoreWebView2Environment.CreateAsync(null, data);
                await web.EnsureCoreWebView2Async(env);
                discordUsesCacheOptions = false;
            }
            discordEnvironment = env;
            if (expansionDownloadsWindow is { IsDisposed: false })
                _ = InitializeExpansionDownloadsBrowser();
            EnforceChatClip();
            web.DefaultBackgroundColor = System.Drawing.Color.Transparent;
            await LoadCss();
            Log("WebView2 initialized");
            web.CoreWebView2.Settings.AreDevToolsEnabled = false;
            web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
            // Install styling before Discord's SPA renders, and keep
            // it in place as React replaces DOM nodes.
            await web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(
                "(() => { const css = " + System.Text.Json.JsonSerializer.Serialize(userCss) +
                "; const install=()=>{if(!document.head)return;let s=document.getElementById('tes3np-chat-style');if(!s){s=document.createElement('style');s.id='tes3np-chat-style';document.head.appendChild(s)}s.textContent=css;if(document.body&&!document.getElementById('tes3np-frame')){const f=document.createElement('div');f.id='tes3np-frame';document.body.appendChild(f)}};install();document.addEventListener('DOMContentLoaded',install);new MutationObserver(()=>{if(!document.getElementById('tes3np-chat-style')||(document.body&&!document.getElementById('tes3np-frame')))install()}).observe(document,{childList:true,subtree:true});})()");
            await web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(DiscordSignInProgressScript.Value);
            web.CoreWebView2.WebMessageReceived += (_, args) => HandleDiscordSignInMessage(args);
            web.CoreWebView2.NavigationStarting += (_, e) =>
            {
                discordNavigationId = e.NavigationId;
                discordNavigationInProgress = true;
            };
            web.CoreWebView2.DOMContentLoaded += async (_, e) =>
            {
                if (e.NavigationId != discordNavigationId) return;
                discordNavigationInProgress = false;
                await CheckDiscordAuthentication();
            };
            web.CoreWebView2.NavigationCompleted += async (_, e) =>
            {
                if (e.NavigationId != discordNavigationId) return;
                discordNavigationInProgress = false;
                await UpdateViewMode();
            };
            web.CoreWebView2.SourceChanged += async (_, _) => await UpdateViewMode();
            web.CoreWebView2.NewWindowRequested += (_, e) =>
            {
                e.Handled = true;
                if (e.Uri.StartsWith("https://discord.com/", StringComparison.OrdinalIgnoreCase))
                    web.CoreWebView2.Navigate(e.Uri);
            };
            // Give the local document a head start. Its readiness is
            // confirmed separately after sign-in and after resizing.
            await InitMessageBrowser(env);
            if (closingChat || IsDisposed) return;
            if (freshDiscordProfile) ShowDiscordSignIn();
            else ShowConnectingChat();
            web.CoreWebView2.Navigate(freshDiscordProfile ? "https://discord.com/login" : Channel);
            Log(freshDiscordProfile ? "Fresh Discord profile: opening sign-in" : "Navigating to channel");
        }
        catch (Exception ex)
        {
            Log("ERROR " + ex.GetType().Name);
            MessageBox.Show("WebView2 chat unavailable: " + ex.Message + "\nInstall Microsoft Edge WebView2 Runtime.", "tes3np Chat");
        }
    }

    // Discord changes its hashed CSS classes frequently. Remove the actual
    // channel heading (including the two action icons) by DOM structure.
    static readonly Lazy<string> HideChannelHeaderScript = GameChatWeb.Page("hide-channel-header.js");

    async Task HideChannelHeader()
    {
        if (web.CoreWebView2 == null) return;
        try { await web.CoreWebView2.ExecuteScriptAsync(HideChannelHeaderScript.Value); }
        catch (Exception ex) { Log("Header removal error: " + ex.GetType().Name); }
    }

    async Task ApplyCss()
    {
        if (web.CoreWebView2 == null) return;
        var js = "(() => { const css = " + System.Text.Json.JsonSerializer.Serialize(userCss) +
            "; let style=document.getElementById('tes3np-chat-style'); if(!style){style=document.createElement('style');style.id='tes3np-chat-style';document.head.appendChild(style);} style.textContent=css; if(document.body&&!document.getElementById('tes3np-frame')){const f=document.createElement('div');f.id='tes3np-frame';document.body.appendChild(f);} })()";
        try { await web.CoreWebView2.ExecuteScriptAsync(js); await HideChannelHeader(); } catch (Exception ex) { Log("CSS error: " + ex.GetType().Name); }
    }

    void SuspendHappyHourUntilDiscordReturns(string reason)
    {
        if (!discordChannelReady) return;
        discordChannelReady = false;
        Log("CHAT | Discord channel unavailable (" + reason +
            "); pausing live feed and history paging. Verified Happy Hour banner remains independent.");
        // Recheck the live channel on the next authenticated session.
        // Neither an expired nor a missing archive can show a banner.
        // Keep the existing genuine activation, its absolute expiry,
        // dismissal state and timer unchanged across sign-out.
        initialBackfillComplete = false;
        initialBackfillStarted = DateTime.MinValue;
        initialBackfillAttempts = 0;
        waitingForLiveFeedAfterHistory = false;
    }

    static bool IsGameChatRoute(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
        string path = uri.GetLeftPart(UriPartial.Path).TrimEnd('/');
        if (string.Equals(path, Channel, StringComparison.OrdinalIgnoreCase)) return true;
        // Older-message paging can anchor the same channel at a message ID.
        return path.StartsWith(Channel + "/", StringComparison.OrdinalIgnoreCase) &&
            ulong.TryParse(path.AsSpan(Channel.Length + 1), System.Globalization.NumberStyles.None,
                System.Globalization.CultureInfo.InvariantCulture, out ulong id) && id != 0;
    }

    static bool IsDiscordAppRoute(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || uri.Host != "discord.com") return false;
        string path = uri.AbsolutePath.TrimEnd('/');
        return path.StartsWith("/channels/", StringComparison.OrdinalIgnoreCase) ||
            path is "/quest-home" or "/quests" or "/shop" or "/store";
    }

    static bool IsDiscordSignInRoute(string url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps &&
        uri.Host == "discord.com" && uri.IsDefaultPort && uri.UserInfo.Length == 0 &&
        uri.AbsolutePath.TrimEnd('/') is "/login" or "/register";

    void HandleDiscordSignInMessage(CoreWebView2WebMessageReceivedEventArgs args)
    {
        var core = web.CoreWebView2;
        if (closingChat || !discordLoginVisible || signingOutDiscord || core == null ||
            !IsDiscordSignInRoute(args.Source) || !IsDiscordSignInRoute(core.Source)) return;
        try
        {
            switch (args.TryGetWebMessageAsString())
            {
                case "tes3np-sign-in-started":
                    discordSignInRequested = true;
                    discordSignInAttemptExpires = DateTime.UtcNow.AddSeconds(30);
                    SetDiscordAccountStatus(DiscordAccountStatus.Checking);
                    Log("CHAT | Discord sign-in submitted");
                    PublishDiscordAccount();
                    break;
                case "tes3np-sign-in-rejected":
                    if (discordSignInAttemptExpires == default) break;
                    SetDiscordAccountStatus(DiscordAccountStatus.SignedOut);
                    PublishDiscordAccount();
                    break;
                case "tes3np-sign-in-later":
                    DismissDiscordSignIn();
                    break;
            }
        }
        catch (Exception ex) { Log("Discord sign-in event: " + ex.GetType().Name); }
    }

    void RetryStalledDiscordChannel(CoreWebView2 core)
    {
        if (channelRetryAt is not { } retryAt || DateTime.UtcNow < retryAt) return;
        channelRetryAt = null;
        Log("CHAT | First Discord feed stalled; retrying the channel");
        try
        {
            core.Stop();
            core.Navigate(Channel);
        }
        catch (Exception ex) { Log("Discord channel retry: " + ex.GetType().Name); }
    }

    async Task CheckDiscordAuthentication()
    {
        if (web.CoreWebView2 == null || closingChat || signingOutDiscord || checkingDiscordAuthentication) return;
        checkingDiscordAuthentication = true;
        try
        {
            var core = web.CoreWebView2;
            string url = core.Source ?? "";
            ulong navigationId = discordNavigationId;
            if (IsDiscordSignInRoute(url)) {
                if (DateTime.UtcNow >= discordSignInAttemptExpires)
                    SetDiscordAccountStatus(DiscordAccountStatus.SignedOut);
                SuspendHappyHourUntilDiscordReturns("sign-in URL");
                ShowDiscordSignIn();
                await StyleDiscordLogin();
                return;
            }
            if (discordNavigationInProgress)
            {
                RetryStalledDiscordChannel(core);
                return;
            }
            string state = await core.ExecuteScriptAsync(
                "(() => { if (document.readyState === 'loading') return 'loading'; " +
                "if ([...document.querySelectorAll('[data-list-id=chat-messages] [id^=chat-messages-]')]" +
                ".some(row => /^chat-messages-[0-9]+-[0-9]+$/.test(row.id))) return 'chat'; " +
                "if (document.querySelector('input[type=password]')) return 'login'; " +
                "const t = document.body?.innerText || ''; " +
                "if (/Discord App Detected|Discord App Launched/i.test(t)) return 'app-prompt'; " +
                "return 'pending'; })()").WaitAsync(TimeSpan.FromSeconds(4));
            if (closingChat || IsDisposed || signingOutDiscord || web.CoreWebView2 == null ||
                navigationId != discordNavigationId || discordNavigationInProgress ||
                !string.Equals(url, core.Source, StringComparison.OrdinalIgnoreCase)) return;
            if (state == "\"login\"") {
                SetDiscordAccountStatus(DiscordAccountStatus.SignedOut);
                SuspendHappyHourUntilDiscordReturns("Discord login form");
                ShowDiscordSignIn();
                return;
            }
            if (state == "\"app-prompt\"") {
                SetDiscordAccountStatus(DiscordAccountStatus.SignedOut);
                SuspendHappyHourUntilDiscordReturns("Discord desktop-app prompt");
                ShowDiscordSignIn();
                Log("Discord desktop-app prompt detected; navigating to browser sign-in");
                core.Navigate("https://discord.com/login");
                return;
            }
            bool onChannel = IsGameChatRoute(url);
            if (!onChannel)
                SuspendHappyHourUntilDiscordReturns("navigated away from Game Chat");
            // Discord can return the login browser to Home, Quests or Shop.
            // Move it out of the sign-in card before opening the chat route.
            if (discordLoginVisible && state != "\"loading\"" && IsDiscordAppRoute(url))
            {
                RestoreGameChatAfterSignIn();
                if (!onChannel)
                {
                    Log("Discord sign-in returned to the app; opening Game Chat channel");
                    core.Navigate(Channel);
                    return;
                }
            }
            if (state != "\"loading\"")
                _ = RefreshDiscordAccount(core, navigationId, url);
            if (!onChannel || state != "\"chat\"")
            {
                RetryStalledDiscordChannel(core);
                return;
            }
            channelRetryAt = null;
            SetDiscordAccountStatus(DiscordAccountStatus.SignedIn);
            if (!discordChannelReady) {
                discordChannelReady = true;
                Log("CHAT | Authenticated Discord Game Chat ready; starting live history discovery");
                BeginHappyHourDiscovery();
                if (discordSignInRequested && pendingExpansionPrompt == 0)
                {
                    discordSignInRequested = false;
                    if (chatDisplayMode != "Always Hidden") SetChatOpen(true);
                }
            }
            CompletePendingExpansionPrompt();
        }
        catch (Exception ex)
        {
            Log("Discord auth check: " + ex.GetType().Name);
            if (!closingChat && !IsDisposed && !signingOutDiscord && web.CoreWebView2 is { } core &&
                !IsDiscordSignInRoute(core.Source ?? ""))
                RetryStalledDiscordChannel(core);
        }
        finally { checkingDiscordAuthentication = false; }
    }

    static readonly Lazy<string> DiscordSignInScript = GameChatWeb.Page("discord-sign-in.js");
    static readonly Lazy<string> DiscordSignInProgressScript = GameChatWeb.Page("discord-sign-in-progress.js");

    // Keep Discord's own inputs and authentication handlers intact.
    async Task StyleDiscordLogin()
    {
        if (web.CoreWebView2 == null || closingChat) return;
        try
        {
            // The release includes this image beside the published Chat Host.
            // Reuse its data URL across 500ms login checks, and inject once
            // per document; Discord's SPA can replace the form at any time.
            string logoFile = Path.Combine(AppContext.BaseDirectory, "assets", "DiscordInt.png");
            if (File.Exists(logoFile))
            {
                discordIntegrationLogoDataUrl ??= "data:image/png;base64," +
                    Convert.ToBase64String(File.ReadAllBytes(logoFile));
                if (await web.CoreWebView2.ExecuteScriptAsync(
                    "Boolean(window.__tes3npIntegrationLogo)").WaitAsync(TimeSpan.FromSeconds(2)) != "true")
                {
                    await web.CoreWebView2.ExecuteScriptAsync(
                        "window.__tes3npIntegrationLogo = " +
                        System.Text.Json.JsonSerializer.Serialize(discordIntegrationLogoDataUrl) + ";")
                        .WaitAsync(TimeSpan.FromSeconds(2));
                }
            }
            string prompt = useHeaderSignInPrompt ? "true" : "false";
            await web.CoreWebView2.ExecuteScriptAsync($"{DiscordSignInScript.Value}({prompt})")
                .WaitAsync(TimeSpan.FromSeconds(2));
        }
        catch (Exception ex) { Log("Discord login theme: " + ex.GetType().Name); }
    }

    // Use the dock for Game Chat and a centered card for the launcher
    // header and Expansion Pack authentication.
    static Size GetDiscordSignInSize(Rectangle work, double ownerFit)
    {
        // Full-size sign-in uses its original bounds. Honor compact
        // launcher presets and actual monitor limits through reflow.
        int width = Math.Max(DiscordSignInCard.MinimumWidth, Pixels(DiscordSignInCard.BaseWidth, ownerFit));
        int height = Math.Max(DiscordSignInCard.MinimumHeight, Pixels(DiscordSignInCard.BaseHeight, ownerFit));
        return new Size(Math.Min(width, Math.Max(1, work.Width - 24)),
            Math.Min(height, Math.Max(1, work.Height - 24)));
    }

    void PositionDiscordSignIn(RECT ownerBounds, Rectangle work)
    {
        if (discordSignInWindow is not { IsDisposed: false } popup) return;
        if (popup.UpdateParkedLayout()) return;
        popup.SetSignInPrompt(useHeaderSignInPrompt);
        // The card's original size is in screen pixels. Windows scaling
        // can leave room for it even when the launcher is below 100%.
        double ownerFit = Math.Min(1, (ownerBounds.Right - ownerBounds.Left) / (double)launcherBaseWidth);
        var size = GetDiscordSignInSize(work, ownerFit);
        Rectangle target = pendingExpansionPrompt == 0 && !discordSignInFromHeader
            ? DockBounds(ownerBounds, work, size, size.Width)
            : new Rectangle(work.Left + (work.Width - size.Width) / 2,
                work.Top + (work.Height - size.Height) / 2, size.Width, size.Height);
        popup.ApplyLayout(target);
    }

    void DismissDiscordSignIn()
    {
        if (discordSignInWindow is { IsDisposed: false } popup)
            popup.Hide();
        discordSignInRequested = false;
        discordSignInFromHeader = false;
        if (discordAccountStatus == DiscordAccountStatus.Checking && discordSignInAttemptExpires != default)
        {
            SetDiscordAccountStatus(DiscordAccountStatus.SignedOut);
            PublishDiscordAccount();
        }
        CancelPendingExpansionPrompt();
    }

    void ToggleGameChatDiscordSignIn()
    {
        // Game Chat toggles its own login; Expansion authentication remains
        // a distinct user flow with its own cancellation behavior.
        if (pendingExpansionPrompt == 0 && !discordSignInFromHeader &&
            discordSignInWindow is { IsDisposed: false, Visible: true })
        {
            DismissDiscordSignIn();
            return;
        }
        discordSignInFromHeader = false;
        RevealDiscordSignInWindow();
    }

    void RevealDiscordSignInWindow()
    {
        discordSignInRequested = true;
        if (discordSignInWindow is not { IsDisposed: false } popup) return;
        PositionChatWindows();
        _ = StyleDiscordLogin();
        if (!popup.Visible) popup.Show();
        if (web.CoreWebView2 != null)
            _ = web.CoreWebView2.ExecuteScriptAsync(
                "(() => { const f = document.querySelector('[data-tes3np-login]'); " +
                "if (f) f.scrollTop = 0; " +
                "if (document.scrollingElement) document.scrollingElement.scrollTop = 0; })()");
        popup.BringToFront();
        popup.Activate();
    }

    void ShowDiscordSignIn()
    {
        // One browser, one Discord profile: move the existing WebView2 into
        // a clearly named native window, never create another login session.
        if (discordLoginVisible) return;
        connectingChat = false;
        showChatAfterDiscordSignIn = chatOpen || chatDisplayMode == "Always Shown" || freshDiscordProfile;
        discordLoginVisible = true;
        nativeMode = false;
        nativeMessages.Visible = false;
        messageBrowser.Visible = false;
        messageClip.Visible = false;
        goldScrollbar.Visible = false;
        frameSurface.Visible = false;
        chatViewport.Visible = false;
        if (web.IsHandleCreated) SetWindowRgn(web.Handle, IntPtr.Zero, true);
        SetChatOpen(false);

        var popup = discordSignInWindow;
        if (popup is null || popup.IsDisposed)
        {
            popup = new DiscordSignInCard(DismissDiscordSignIn);
            popup.FormClosing += (_, e) =>
            {
                if (!closingChat)
                {
                    e.Cancel = true;
                    DismissDiscordSignIn();
                }
            };
            discordSignInWindow = popup;
        }
        popup.PrepareSignIn();
        web.Dock = DockStyle.Fill;
        if (web.Parent != popup.BrowserPanel) web.Parent = popup.BrowserPanel;
        // Restore the sign-in form's normal browser text sizing.
        web.ZoomFactor = 1;
        PositionChatWindows();
        web.Visible = true;
        // Keep the authentication WebView2 alive for background channel /
        // Happy Hour discovery without interrupting a clean first launch.
        // The same popup becomes visible on a user-initiated action.
        SetNativeWindowOwner(popup.Handle, owner);
        if (discordSignInRequested) popup.Show();
        Log(discordSignInRequested
            ? "Discord login: user-requested sign-in window opened"
            : "Discord login: ready but deferred until requested");
    }

    void RestoreGameChatAfterSignIn()
    {
        if (!discordLoginVisible) return;
        Log("Discord chat detected: restoring custom Game Chat");
        discordSignInAttemptExpires = default;
        if (discordAccountStatus == DiscordAccountStatus.SignedOut)
        {
            SetDiscordAccountStatus(DiscordAccountStatus.Checking);
            PublishDiscordAccount();
        }
        channelRetryAt = DateTime.UtcNow.AddSeconds(8);
        // Preserve the open request made while signing in. The existing
        // Game Chat window remains owned by the launcher throughout.
        bool keepChatVisible = discordSignInRequested &&
            (pendingExpansionPrompt == 0 || showChatAfterDiscordSignIn) &&
            chatDisplayMode != "Always Hidden";
        discordSignInRequested = false;
        discordSignInFromHeader = false;
        discordLoginVisible = false;
        // Reparenting and hiding WebView2 during the OAuth handoff can leave
        // its renderer unresponsive. Keep the same browser and HWND alive.
        if (discordSignInWindow is { IsDisposed: false } popup)
        {
            popup.Park(owner);
            Log("CHAT | Discord browser retained after sign-in");
        }
        // Keep the panel open while the authenticated feed mounts.
        ShowConnectingChat();
        Text = "tes3np Chat Host";
        if (!docked) DockToLauncher();
        if (keepChatVisible || chatDisplayMode == "Always Shown") {
            lastChatActivity = DateTime.Now;
            SetChatOpen(true);
        }
        PositionChatWindows();
    }

    async Task UpdateViewMode()
    {
        if (web.CoreWebView2 == null) return;
        Log("Navigation completed (Discord page changed).");
        await CheckDiscordAuthentication();
        if (discordLoginVisible || !discordChannelReady) return;
        EnforceChatClip();
        await ApplyCss();
        await RefreshNativeMessages();
    }
}
