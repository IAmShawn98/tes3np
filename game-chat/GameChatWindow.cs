using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow : Form
{
    // WinForms shows its main Form before the Shown callback can dock it.
    // Cloak the very first HWND before that native show. Unlike hiding the
    // Form or moving it off-screen, this leaves the normal WinForms/WebView2
    // initialization lifecycle intact without painting an undocked window.
    bool startupPresentationPending = true;

    // Cloaking suppresses pixels, not activation. The initial framework show
    // must not take foreground focus before the launcher owns this popup.
    // After docking, ordinary user-driven focus remains available.
    protected override bool ShowWithoutActivation => startupPresentationPending;

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        if (startupPresentationPending)
            SetStartupWindowCloak(true);
    }

    void SetStartupWindowCloak(bool cloak)
    {
        if (!IsHandleCreated) return;
        int value = cloak ? 1 : 0;
        int hr = DwmSetWindowAttribute(Handle, DWMWA_CLOAK, ref value, sizeof(int));
        if (hr != 0)
            Log($"STARTUP | Window cloak {(cloak ? "enable" : "disable")} failed (0x{hr:X8})");
    }

    readonly IntPtr owner;

    readonly int launcherBaseWidth;

    // Discord snowflakes encode their original creation time in UTC.
    static DateTimeOffset DiscordTimestamp(ulong id) =>
        DateTimeOffset.FromUnixTimeMilliseconds((long)(id >> 22) + 1420070400000L);

    // Shared TES3NP data root, matching src/state.ahk::AppDataDirectory.
    // The chat companion runs in a separate process but must not invent
    // an independent persistent-data directory.
    static readonly string ChatDataRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "tes3np");

    readonly System.Windows.Forms.Timer watch = new() { Interval = 250 };

    // History requests must not depend on changes to Discord messages or launcher UI.
    readonly System.Windows.Forms.Timer historyWatch = new() { Interval = 200 };

    bool closingChat;

    bool refreshingChat;

    internal GameChatWindow(IntPtr owner, int launcherBaseWidth)
    {
        this.owner = owner;
        this.launcherBaseWidth = launcherBaseWidth;
        AutoScaleMode = AutoScaleMode.None;
        Text = "tes3np Chat Host";
        try
        {
            if (File.Exists(chatModeFile))
            {
                string saved = File.ReadAllText(chatModeFile).Trim();
                if (saved is "Automatic" or "Always Shown" or "Always Hidden")
                    chatDisplayMode = saved;
            }
        }
        catch { }
        FormBorderStyle = FormBorderStyle.None;
        DoubleBuffered = true;
        InitializeChatSurface();
        UpdateChatScale(1);
        Log("Host launched; owner=" + owner);
        Width = 266; Height = 342;
        LoadLayout();
        Shown += (_, _) => PositionServerUpdatesPanel();
        Shown += StartDiscordAsync;
        FormClosing += CloseGameChat;
        // Status continues to poll even while a chat refresh awaits authentication or messages.
        watch.Tick += (_, _) => _ = RefreshServerStatus();
        watch.Tick += RefreshChatAsync;
        historyWatch.Tick += MaintainHistory;
        historyWatch.Start();
        watch.Start();
    }

    void CloseGameChat(object? sender, FormClosingEventArgs e)
    {
        CancelPendingExpansionPrompt();
        closingChat = true;
        watch.Dispose();
        historyWatch.Dispose();
        QueueFinalChatArchiveSave();
        happyHourTicker?.Dispose();
        if (happyHourBanner is { IsDisposed: false }) happyHourBanner.Close();
        foreach (var image in imageCache.Values) image.Dispose();
        imageCache.Clear();
        if (launcherLocationHook != IntPtr.Zero)
        {
            UnhookWinEvent(launcherLocationHook);
            launcherLocationHook = IntPtr.Zero;
        }
        if (launcherForegroundHook != IntPtr.Zero)
        {
            UnhookWinEvent(launcherForegroundHook);
            launcherForegroundHook = IntPtr.Zero;
        }
        CloseEmbeddedExpansionDownloads();
        CloseDiscordAccountBrowser();
        CloseChatComposer();
        ResetServerUpdates();
        ResetServerStatus();
        discordSignInWindow?.Dispose();
        borderTexture?.Dispose();
        scrollbarTexture?.Dispose();
        loadingFont?.Dispose();
    }

    async void RefreshChatAsync(object? sender, EventArgs e)
    {
        if (closingChat || refreshingChat || IsDisposed) return;
        if (!IsWindow(owner)) { Close(); return; }
        refreshingChat = true;
        try
        {
            PositionServerUpdatesPanel();
            try { LoadLayout(); await LoadCss(); } catch (Exception ex) { Log("Reload error: " + ex.GetType().Name); }
            if (!docked) DockToLauncher();
            if (docked && !nativeMode) EnforceChatClip();
            await CheckDiscordAuthentication();
            PublishDiscordAccount();
            _ = RefreshServerUpdates();
            RetryDueHappyHourImages();
            await RefreshNativeMessages();
            if (closingChat || IsDisposed) return;
            PositionChatWindows();
            _ = EnsureChatComposer();
            if (pendingExpansionPrompt == 0 && !discordLoginVisible && !connectingChat &&
                chatDisplayMode == "Automatic" && chatOpen &&
                DateTime.Now - lastChatActivity > TimeSpan.FromSeconds(10) &&
                !goldScrollbar.Capture && !ChatComposerHasFocus &&
                !Bounds.Contains(Cursor.Position))
                SetChatOpen(false);
            if (nativeMode && goldScrollbar.Visible)
            {
                int thumbY = ChatThumbY(ChatUnits(goldScrollbar.Height), out int thumbHeight);
                if (thumbY != lastThumbY || thumbHeight != lastThumbHeight)
                    goldScrollbar.Invalidate();
            }
        }
        catch (ObjectDisposedException) { }
        catch (Exception ex) { if (!closingChat) Log("Chat timer error: " + ex.GetType().Name); }
        finally { refreshingChat = false; }
    }
}
