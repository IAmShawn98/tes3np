using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    readonly string chatModeFile = Path.Combine(ChatDataRoot, "chat-display-mode.txt");

    string chatDisplayMode = "Automatic";

    bool chatOpen;

    DateTime lastChatActivity = DateTime.MinValue;

    // Launcher-owned toggle commands (WM_APP + 0x331).
    protected override void WndProc(ref Message m)
    {
        if (m.Msg == 0x8331)
        {
            switch (m.WParam.ToInt64())
            {
                case 1:
                    // An early manual click before WebView2 completes startup
                    // must still reveal login when the browser becomes ready.
                    if (discordLoginVisible)
                    {
                        ToggleGameChatDiscordSignIn();
                        break;
                    }
                    if (!discordChannelReady && !connectingChat && !nativeMode)
                    {
                        discordSignInRequested = !discordSignInRequested;
                        break;
                    }
                    if (chatOpen && pendingExpansionPrompt != 0)
                    {
                        CancelPendingExpansionPrompt();
                        Log("EXPANSION | Pending download cancelled using Game Chat tab.");
                    }
                    SetChatOpen(!chatOpen);
                    break;
                case 2: SetChatDisplayMode("Automatic"); break;
                case 3: SetChatDisplayMode("Always Shown"); break;
                case 4: SetChatDisplayMode("Always Hidden"); break;
                case 6: ShowEmbeddedExpansionDownloads(m.LParam); break;
                case 7: CloseEmbeddedExpansionDownloads(m.LParam); break;
                case 9: HideEmbeddedExpansionDownloads(m.LParam); break;
                case 10: RequestAuthenticatedExpansionPrompt((int)m.LParam.ToInt64()); break;
                case 11: CancelPendingExpansionPrompt(false); break;
                case 12: RetryAuthenticatedExpansionPrompt((int)m.LParam.ToInt64()); break;
                case 13: StartExpansionAutoDownload(m.LParam); break;
                case 14: Close(); break;
                case 15: CheckExpansionDownloadSilently(m.LParam); break;
                case 16: OpenDiscordAccountSignIn(); break;
                case 17: _ = SignOutDiscord(); break;
            }
            return;
        }
        base.WndProc(ref m);
    }

    void SetChatDisplayMode(string mode)
    {
        if (mode == "Always Hidden") CancelPendingExpansionPrompt();
        chatDisplayMode = mode;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(chatModeFile)!);
            File.WriteAllText(chatModeFile, mode);
        }
        catch { }
        SetChatOpen(mode == "Always Shown");
    }

    // WM_APP + 0x332 tells the launcher the authoritative chat visibility.
    void NotifyLauncherChatState()
    {
        if (IsWindow(owner))
            PostMessage(owner, 0x8332, chatOpen ? new IntPtr(1) : IntPtr.Zero, IntPtr.Zero);
    }

    void SetChatOpen(bool show)
    {
        if (discordLoginVisible)
        {
            // Never display a stretched/empty chat pane behind login.
            show = false;
        }
        if (!show)
        {
            goldScrollbar.Capture = false;
            historyCatchupActive = false;
        }
        else if (!chatOpen) lastChatActivity = DateTime.Now;
        chatOpen = show;
        if (!discordLoginVisible) PositionChatWindows();
        if (IsHandleCreated)
        {
            // SW_SHOW (5) activates this owned popup and steals foreground
            // focus from parchment menus and native dialogs. Automatic
            // message notifications must only reveal chat, never activate it.
            if (show)
            {
                ShowWindow(Handle, 4); // SW_SHOWNOACTIVATE
                FitWebView();
                messageClip.PerformLayout();
                frameSurface.Invalidate(true);
                frameSurface.Update();
            }
            else ShowWindow(Handle, 0);
        }
        NotifyLauncherChatState();
    }
}
