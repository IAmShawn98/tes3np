"""Guard TES3NP's Chat Host against recurring persistence/auth regressions.

These checks enforce cross-process architectural contracts, not C# syntax.
The Windows CI job also builds the Chat Host to catch compiler errors.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "chat-host" / "Program.cs").read_text(encoding="utf-8-sig")
app_state = (ROOT / "src" / "state.ahk").read_text(encoding="utf-8-sig")
reset_ui = (ROOT / "src" / "ui" / "v016-refinements.ahk").read_text(encoding="utf-8-sig")
bootstrap = (ROOT / "src" / "app" / "bootstrap.ahk").read_text(encoding="utf-8-sig")
patcher = (ROOT / "src" / "ui" / "patcher.ahk").read_text(encoding="utf-8-sig")
session = (ROOT / "src" / "game" / "session.ahk").read_text(encoding="utf-8-sig")
controls = (ROOT / "src" / "ui" / "controls.ahk").read_text(encoding="utf-8-sig")
jiub_ui = (ROOT / "src" / "ui" / "happy-hour.ahk").read_text(encoding="utf-8-sig")
errors = []


def expect(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


def section_between(text: str, start: str, end: str) -> str:
    """Return the guarded function section, or empty text if it was removed.

    Missing/renamed source must cause an explicit contract failure rather
    than crashing the entire build preflight with IndexError.
    """
    start_at = text.find(start)
    if start_at == -1:
        return ""
    end_at = text.find(end, start_at + len(start))
    if end_at == -1:
        return ""
    return text[start_at:end_at]


expect(
    "Unused backfill reanchor tracking flag must remain removed (CS0414)",
    "initialBackfillReanchored" not in source,
)

expect(
    "Retired no-op native scrollbar helper must remain removed",
    "HideNativeChatScrollbar" not in source,
)
expect(
    "Unreachable clipboard-based RichEdit image paste must remain removed",
    "AppendChatImage" not in source,
)

expect(
    "Unused Win32 native scrollbar declarations must remain removed",
    all(name not in source for name in ("GetScrollInfo", "ShowScrollBar", "SCROLLINFO")),
)
expect(
    "Obsolete browser message-feed variable must remain removed",
    "lastState" not in source,
)
expect(
    "Live message feed scrolling remains wired to custom scrollbar",
    "void ScrollChatToThumb(int y, int dragOffset)" in source
    and "readonly BufferedScrollbar goldScrollbar = new()" in source
    and "new ResizeObserver(metrics).observe(feed);" in source
    and "feed.addEventListener('scroll',metrics);" in source,
)

expect(
    "AHK must establish the Roaming AppData root",
    'AppDataDirectory := A_AppData "\\tes3np"' in app_state,
)
expect(
    "Chat Host must establish exactly one Roaming AppData root",
    source.count("SpecialFolder.ApplicationData") == 1
    and 'SpecialFolder.ApplicationData), "tes3np"' in source,
)
expect(
    "Chat Host must not read or write obsolete Local AppData Happy Hour markers",
    "SpecialFolder.LocalApplicationData" not in source
    and "LegacyHappyHourSeenFile" not in source
    and "happyHourSeenFile" not in source,
)
for name, expected in {
    "gameChatLogDirectory": 'Path.Combine(ChatDataRoot, "Logs")',
    "chatModeFile": 'Path.Combine(ChatDataRoot, "chat-display-mode.txt")',
    "logPath": 'Path.Combine(ChatDataRoot, "chat-host.log")',
}.items():
    expect(f"{name} must use canonical Roaming AppData", expected in source)
expect(
    "WebView2 profile must be under the canonical data root",
    'Path.Combine(ChatDataRoot, "chat-webview2")' in source,
)
expect(
    "No dead marker migration or popup-only state remains",
    "hadSavedChatArchiveAtStartup" not in source
    and "GetLastSeenHappyHour" not in source
    and "SaveLastSeenHappyHour" not in source,
)
expect(
    "Only indexed real Discord messages may create an event",
    "ulong candidate = LatestArchivedHappyHourId();" in source
    and "Math.Max(archivedId, previouslyVerifiedId)" not in source,
)
expect(
    "Activation text must belong to the Discord bot, not quoted player chat",
    'sourceAuthor.Contains("Yagrum", StringComparison.OrdinalIgnoreCase)' in source
    and 'entry.Value.User.Contains("Yagrum", StringComparison.OrdinalIgnoreCase)' in source,
)
expect(
    "A newer verified image must not be superseded by older text",
    "foreach (ulong imageId in verifiedHappyHourImageIds)" in source
    and "foreach (var entry in archivedChat.Reverse()) {\n                if (entry.Key <= latest) break;" in source,
)
expect(
    "Only the authentic Discord-backed Happy Hour banner remains",
    "ShowHappyHourBannerForMessage(ulong activationId)" in source
    and "ShowHappyHourBannerForMessage(latest);" in source
    and "ShowHappyHourAlert(" not in source
    and "happyHourAlert" not in source
    and "GoldText(" not in source
    and "CloseHappyHourPopup(" not in source
    and "happyHourDemoSeenFile" not in source
    and "GoldHappyHourWindow(480" not in source
    and "Form? happyHourAlert" not in source,
)
happy_hour_refresh = section_between(
    source,
    "void RefreshHappyHourBanner()",
    "\n        [DllImport(\"user32.dll\")] static extern bool IsWindowVisible",
)
happy_hour_clock = section_between(
    source,
    "void RefreshHappyHourBannerClock()",
    "\n        void RefreshHappyHourBanner()",
)
expect(
    "Happy Hour countdown updates during any open launcher menu without stealing focus",
    "RefreshHappyHourBannerClock();" in happy_hour_refresh
    and "if (OtherLauncherDialogOpen())" in happy_hour_refresh
    and happy_hour_refresh.index("RefreshHappyHourBannerClock();")
        < happy_hour_refresh.index("if (OtherLauncherDialogOpen())")
    and "RefreshHappyHourBannerClock();" in happy_hour_refresh[
        happy_hour_refresh.index("Banner window created") - 250:
    ]
    and "HappyHourBannerTime(happyHourEndsAt)" in happy_hour_clock
    and "DateTimeOffset.UtcNow" in happy_hour_clock
    and "LayoutHappyHourBannerContents();" in happy_hour_clock
    and "SetNativeWindowOwner(banner.Handle, owner);" in happy_hour_refresh
    and "if (!happyHourBanner.Visible)" in happy_hour_refresh
    and "else if (happyHourBanner.Visible)" in happy_hour_refresh
    and "new System.Windows.Forms.Timer { Interval = 1000 }" in source
    and "DiscordTimestamp(activationId).AddHours(1)" in source,
)
expect(
    "Banner presentation is independent of Discord authentication",
    "if (activationId == 0 || closingChat || IsDisposed) return;" in source
    and "void RefreshHappyHourBanner()\n        {\n            if ((!ShowExpiredHappyHourForAlphaTest &&" in source
    and "void DetectLatestHappyHour()\n        {\n            if (closingChat || IsDisposed) return;" in source,
)
expect(
    "Only authenticated Discord can fetch or page new messages",
    "if (!discordChannelReady || initialBackfillComplete" in source
    and "discordLoginVisible || !discordChannelReady) return;" in source
    and "void SuspendHappyHourUntilDiscordReturns(string reason)" in source,
)
expect(
    "Offline startup consults real archived messages, not login or marker state",
    "// Load it immediately, whether this browser is signed in or not.\n                DetectLatestHappyHour();" in source
    and "ulong latest = LatestArchivedHappyHourId();" in source
    and "LegacyHappyHourSeenFile" not in source,
)
expect(
    "Logging out must preserve a valid banner and its expiry timer",
    "Verified Happy Hour banner remains independent." in source
    and "Keep the existing genuine activation, its absolute expiry," in source
    and "ShowExpiredHappyHourForAlphaTest &&" in source,
)
expect(
    "Only real Discord snowflake IDs may determine expiry",
    "DiscordTimestamp(activationId).AddHours(1)" in source,
)
expect(
    "Legacy unguarded Happy Hour test mode must remain removed",
    "PreviewExpiredHappyHourForTesting" not in source
    and "activeHappyHourCutoff" not in source,
)
expect(
    "Expired Happy Hour alpha override stays disabled in production",
    "const bool ShowExpiredHappyHourForAlphaTest = false;" in source
    and "const bool ShowExpiredHappyHourForAlphaTest = true;" not in source
    and "if (latest > lastHappyHourMessageId &&" in source
    and "(ShowExpiredHappyHourForAlphaTest ||" in source
    and "(!ShowExpiredHappyHourForAlphaTest && ends <= DateTimeOffset.UtcNow)" in source
    and "HappyHourBannerTime(happyHourEndsAt)" in source
    and "Math.Max(0, Math.Ceiling((end - DateTimeOffset.UtcNow).TotalSeconds))" in source,
)
expect(
    "Recent cached Happy Hour does not suppress searches for newer activations",
    'checking for a newer Discord activation' in source
    and 'initialBackfillComplete = false;\n                initialBackfillStarted = DateTime.MinValue;\n                initialBackfillAttempts = 0;' in source
    and 'initialBackfillComplete = true;\n                    Log("HAPPY HOUR | Verified cached activation:' not in source
    and 'skipping historical Discord pagination' not in source
    and 'bool verifiedLatest = candidateId > 0 &&' in source
    and 'oldestLoaded <= DiscordTimestamp(candidateId);' in source
    and 'bool pastActiveWindow = oldestLoaded <=' in source
    and 'void BackfillUntilHappyHour()' in source
    and 'initialBackfillComplete = true;' in source,
)
expect(
    "Historical Happy Hour search retains its bounded production one-hour window",
    "DateTimeOffset.UtcNow.AddDays(-7)" in source
    and "DateTimeOffset.UtcNow.AddHours(-1)" in source
    and "initialBackfillAttempts >= 500" in source
    and "TimeSpan.FromMinutes(6)" in source,
)

expect(
    "Archive must be written with replace-on-complete semantics",
    "WriteChatArchiveAtomically(GameChatIndexFile," in source
    and "WriteChatArchiveAtomically(GameChatLogFile," in source
    and "File.Move(temporary, path, true);" in source,
)
expect(
    "Fresh authentication initializes the native renderer before hiding it",
    "await InitMessageBrowser(env);" in source
    and "rendererNavigation.Task.WaitAsync(TimeSpan.FromSeconds(8))" in source
    and "messageBrowserReady = true;" in source,
)
expect(
    "First login reloads Discord channel once without launcher restart",
    "channelReloadAfterSignInPending = true;" in source
    and "channelReloadAfterSignInPending = false;" in source
    and "web.CoreWebView2.Reload();" in source
    and "bool keepChatVisible = discordSignInRequested && showChatAfterDiscordSignIn" in source,
)

expect(
    "Discord login uses an owned dedicated window and keeps Game Chat at its normal size",
    "Form? discordSignInWindow;" in source
    and "void RevealDiscordSignInWindow()" in source
    and "web.Parent = browserPanel;" in source
    and "SetNativeWindowOwner(popup.Handle, owner);" in source
    and "web.Parent = chatViewport;" in source
    and "int windowHeight = chatHeight;" in source
    and "discordLoginVisible ? Math.Max(chatHeight, 780)" not in source
    and "web.Parent = this;" not in source,
)

# Chat Host has a separate real WebView2 renderer, its parent, a native
# loading-text control and a textured custom scrollbar. All four must change
# state together on the first successful Discord feed.
loading_start = source.index("        void ShowConnectingChat()")
loading_end = source.index("        void ShowDiscordSignIn()", loading_start)
loading = source[loading_start:loading_end]
feed_start = source.index("                bool enteringNativeMode = !nativeMode;")
feed_end = source.index('                    Log("Native message view activated");', feed_start)
feed_transition = source[feed_start:feed_end]
expect(
    "Game Chat remains fully on its monitor when the launcher is near an edge",
    "int leftX = bounds.Left - panelWidth;" in source
    and "int rightX = bounds.Right;" in source
    and "if (leftX >= work.Left)" in source
    and "else if (rightX + panelWidth <= work.Right)" in source
    and "x = Math.Clamp(x, work.Left, Math.Max(work.Left, work.Right - panelWidth));" in source
    and "MoveWindow(Handle, x, y, panelWidth, windowHeight, true);" in source
    and "MoveWindow(Handle, bounds.Left - chatWidth, y, chatWidth, windowHeight, true);" not in source,
)
expect(
    "First login exposes native Connecting status, not a stale scrollbar",
    'nativeMessages.Text = "Connecting to live chat...";' in loading
    and 'frameSurface.Visible = true;' in loading
    and 'messageClip.Visible = true;' in loading
    and 'nativeMessages.Visible = true;' in loading
    and 'nativeMessages.BringToFront();' in loading
    and 'messageBrowser.Visible = false;' in loading
    and 'goldScrollbar.Visible = false;' in loading
    and 'ShowConnectingChat();' in source
    and 'else ShowConnectingChat();' in source
    and 'chatViewport.Visible = !nativeMode && !connectingChat;' in source,
)
expect(
    "First authenticated feed renders into a real-sized parent before swapping views",
    'messageClip.Visible = true;' in feed_transition
    and 'messageBrowser.Visible = true;' in feed_transition
    and 'nativeMessages.BringToFront();' in feed_transition
    and feed_transition.index('nativeMessages.BringToFront();')
        < feed_transition.index('await messageBrowser.CoreWebView2.ExecuteScriptAsync("window.setMessages(')
    and 'nativeMode = true;\n                    connectingChat = false;' in feed_transition
    and 'nativeMessages.Visible = false;' in feed_transition
    and 'goldScrollbar.Visible = true;' in feed_transition
    and 'FitWebView();' in feed_transition
    and 'goldScrollbar.Update();' in feed_transition,
)
expect(
    "Real textured scrollbar is the only scrollbar, with no stale frame-painted duplicate",
    'goldScrollbar.Paint += (_, e) =>' in source
    and 'g.DrawString("▲"' not in source
    and 'g.DrawString("▼"' not in source
    and 'int sx = w - 35;' not in source,
)

expect(
    "Happy Hour banner must track launcher movement without a timer delay",
    "void PositionHappyHourBanner()" in source
    and "SetWindowPos(banner.Handle, IntPtr.Zero, x, y, width, height," in source
    and "PositionHappyHourBanner();\n                if (repositionQueued) return;" in source
    and "SetWinEventHook(0x800B, 0x800B" in source,
)
mismatch = (ROOT / "src" / "game" / "expansion-mismatch.ahk").read_text(encoding="utf-8-sig")
patcher = (ROOT / "src" / "ui" / "patcher.ahk").read_text(encoding="utf-8-sig")
expansion_toggle = (ROOT / "scripts" / "toggle-expansion-pack.ps1").read_text(encoding="utf-8-sig")
resource_generator = (ROOT / "scripts" / "generate-bundled-resources.py").read_text(encoding="utf-8-sig")
# The mismatch explanation must appear even when Discord is signed out.
# Only the optional Discord ZIP browser is gated by live authentication.
# Retain sender-PID checking, pending-request cleanup, and retry support.
mismatch_dialog = section_between(
    mismatch,
    'ShowTES3MPExpansionMismatchDialog(mode := "Mismatch", authConfirmed := false)',
    '\nCloseTES3MPExpansionMismatchDialog(',
)
expect(
    "Expansion Pack mismatch dialog opens without waiting for Discord",
    'dialog.Show("w660 h627")' in mismatch_dialog
    and 'RequestDiscordExpansionPrompt(installing ? 1 : 2)' in mismatch_dialog
    and mismatch_dialog.index('dialog.Show("w660 h627")')
        < mismatch_dialog.index('RequestDiscordExpansionPrompt(installing ? 1 : 2)')
    and 'ExpansionMismatchDialog.Show()' in mismatch_dialog
    and 'try WinActivate("ahk_id " dialog.Hwnd)' in mismatch_dialog
    and 'AddStyledButton(dialog, 300, 574, 180, 38,' in mismatch_dialog
    and '"Repair / Install ZIP"' in mismatch_dialog
    and 'Open Expansion Pack Downloads' in bootstrap,
)
expect(
    "Discord-backed Expansion Pack ZIP remains authenticated and retryable",
    'RequestDiscordExpansionPrompt(mode := 2)' in mismatch
    and 'if authConfirmed\n    {\n        if !SendLauncherChatCommand(6, downloadSlot.Hwnd)' in mismatch_dialog
    and 'ShowTES3MPExpansionMismatchDialog(mode = 1 ? "Install" : "Mismatch", true)' in mismatch
    and 'WinGetPID("ahk_id " lParam) != EmbeddedChatPid' in mismatch
    and 'OnMessage(0x8336, DiscordExpansionPromptReady)' in bootstrap
    and 'case 10: RequestAuthenticatedExpansionPrompt((int)m.LParam.ToInt64()); break;' in source
    and 'case 12: RetryAuthenticatedExpansionPrompt((int)m.LParam.ToInt64()); break;' in source
    and 'void RequestAuthenticatedExpansionPrompt(int mode)' in source
    and 'void RetryAuthenticatedExpansionPrompt(int mode)' in source
    and 'async Task ResolvePendingExpansionPromptAsync()' in source
    and 'if (live == "true"' in source
    and 'void CompletePendingExpansionPrompt()' in source
    and 'PostMessage(owner, 0x8336, new IntPtr(mode), Handle);' in source
    and 'CompletePendingExpansionPrompt();' in source
    and 'if (!discordChannelReady || discordLoginVisible || closingChat)' in source
    and 'ShowDiscordSignIn();' in source
    and 'SendLauncherChatCommand(11)' in mismatch
    and 'case 11: CancelPendingExpansionPrompt(false); break;' in source,
)
expect(
    "Enabling a locally installed pack never deploys legacy bundled assets",
    'RequestDiscordExpansionPrompt(1)' in patcher
    and 'ExpansionPackInstalled(morrowind, config)' in patcher
    and 'if enable && !ExpansionPackInstalled(morrowind, cfg)' in patcher
    and 'FileGetSize(esp) > 0' in patcher
    and '$candidateFolders += $configured' in expansion_toggle
    and ' -PayloadFolder ' not in patcher
    and '$PayloadFolder' not in expansion_toggle
    and "Join-Path $folder 'NP Expansion Pack.esp'" in expansion_toggle
    and 'Get-Item -LiteralPath $esp' in expansion_toggle
    and 'manifest.json' not in expansion_toggle
    and 'for directory in ("assets",):' in resource_generator
    and '"assets", "patches"' not in resource_generator,
)

expect(
    "Original Expansion Pack enable/disable switch is restored",
    'LauncherExpansionToggle := AddStyledButton(LauncherGui, 0, 0, 190, 27, "Expansion Pack: Disabled", ToggleExpansionPack)' in bootstrap
    and 'RefreshExpansionPackToggle()' in bootstrap
    and '"Expansion Downloads", ToggleLauncherExpansionDownloads' not in bootstrap,
)
expect(
    "Mismatch dialog requests a child download view and disposes it on exit",
    'SendLauncherChatCommand(6, downloadSlot.Hwnd)' in mismatch
    and 'SendLauncherChatCommand(7, slotHwnd)' in mismatch
    and 'UploadExpansionFromFile()' in mismatch
    and 'Gui("+Owner" LauncherGui.Hwnd' in mismatch
    and 'SendLauncherChatCommand(command, targetHwnd := 0)' in bootstrap,
)
expansion_upload = (ROOT / "src" / "ui" / "expansion-upload.ahk").read_text(encoding="utf-8-sig")

expect(
    "User-approved first enable offers an automatic official ZIP and local repair fallback",
    'choice := MsgBox("NP Expansion Pack is not installed."' in patcher
    and 'RequestDiscordExpansionPrompt(1)' in patcher
    and 'UploadExpansionFromFile()' in patcher
    and 'TES3MPExpansionRequestAutoInstall(slotHwnd, statusControl)' in mismatch
    and 'ExpansionAutoDownloadAttempted := true' in mismatch
    and 'SetTimer((*) => TES3MPExpansionStartDiscoveredZip(slot, status), -100)' in mismatch
    and 'ExpansionAutoDownloadAttempted := true\n    TES3MPExpansionRequestAutoInstall(slot, status)' in mismatch
    and 'IsObject(ExpansionAutoProgressFrame) && !ExpansionAutoDownloadAttempted' in mismatch
    and 'SendLauncherChatCommand(13, slotHwnd)' in mismatch
    and 'case 13: StartExpansionAutoDownload(m.LParam); break;' in source
    and 'slot != expansionDownloadsParent' in source
    and '!discordChannelReady || discordLoginVisible' in source
    and 'IsOfficialExpansionDownloadUrl(expansionLatestZipUrl)' in source,
)
expect(
    "Auto ZIP never exposes signed CDN URLs on command lines or downloads before approval",
    'string url=expansionLatestZipUrl!;' in source
    and 'AllowAutoRedirect=false,UseCookies=false' in source
    and 'ResponseHeadersRead,cancellation.Token' in source
    and 'string stem="tes3np-"+Guid.NewGuid().ToString("N");' in source
    and 'SendCopyDataTimeout(owner,0x004A,sender,' in source
    and 'dwData=new IntPtr(0x8337)' in source
    and 'OnMessage(0x8338, TES3MPExpansionDownloadProgress)' in bootstrap
    and 'TES3MPExpansionAutoDownloadReady(lParam)' in mismatch
    and 'WinGetPID("ahk_id " wParam) = EmbeddedChatPid' in mismatch
    and 'SetTimer((*) => TES3MPExpansionBeginAutoImport(dialog, slot, package), -80)' in mismatch
    and 'UploadExpansionFromFile(package, true)' in mismatch,
)
expect(
    "Failed or cancelled auto ZIP never installs and preserves manual rollback repair",
    'expansionAutoDownloadCancellation?.Cancel();' in source
    and 'File.Delete(partial)' in source
    and 'if (!accepted && completed!=null) try { File.Delete(completed); }' in source
    and 'TES3MPExpansionDownloadProgress(wParam, lParam, msg, hwnd)' in mismatch
    and 'TES3MPExpansionRevealRepair("Automatic download unavailable. Choose Repair / Install ZIP.")' in mismatch
    and 'Repair / Install ZIP' in mismatch
    and 'if !autoApproved && MsgBox(' in expansion_upload
    and 'StartExpansionImportWorker(package, morrowind, config, package)' in expansion_upload
    and 'AutoDownloadedZip: autoDownloadedZip' in expansion_upload
    and 'if state = "error" && autoImport' in patcher
    and 'Would you like to repair it using your own ZIP or extracted folder?' in patcher,
)
auto_zip_callback = section_between(
    mismatch,
    "TES3MPExpansionAutoDownloadReady(lParam)",
    "\nTES3MPExpansionBeginAutoImport(",
)
expect(
    "Auto-download completion validates the private ZIP path without an uninitialized global",
    'StrLower(A_AppData "\\tes3np\\expansion-downloads")' in auto_zip_callback
    and 'AppDataDirectory' not in auto_zip_callback
    and 'StrLower(folder)' in auto_zip_callback
    and 'WinGetPID("ahk_id " wParam) = EmbeddedChatPid' in mismatch,
)
auto_import_callback = section_between(
    mismatch,
    "TES3MPExpansionBeginAutoImport(dialog, slot, package)\n{",
    "\nTES3MPExpansionRequestDownload(",
)
expect(
    "Deferred auto-import uses canonical initialized PatchJob rather than an unresolved helper",
    'global ExpansionMismatchDialog, ExpansionMismatchSlot, PatchJob' in auto_import_callback
    and '(IsSet(PatchJob) && IsObject(PatchJob))' in auto_import_callback
    and 'if !(IsSet(PatchJob) && IsObject(PatchJob))' in auto_import_callback
    and '|| PatchInProgress()' not in auto_import_callback
    and 'if !PatchInProgress()' not in auto_import_callback
    and 'UploadExpansionFromFile(package, true)' in auto_import_callback
    and 'InstallSelectedExpansionPackage(' not in auto_import_callback,
)
expect(
    "Automatic ZIP passes through the existing upload entrypoint without an illicit global function declaration",
    'UploadExpansionFromFile(args*)' in expansion_upload
    and 'if args.Length = 2 && Type(args[1]) = "String" && args[2] = true' in expansion_upload
    and 'StrLower(A_AppData "\\tes3np\\expansion-downloads")' in expansion_upload
    and 'InstallSelectedExpansionPackage(package, true)' in expansion_upload
    and 'UploadExpansionFromFile(package, true)' in auto_import_callback
    and 'InstallSelectedExpansionPackage(' not in auto_import_callback
    and 'global InstallSelectedExpansionPackage' not in mismatch,
)
auto_install_view = section_between(
    mismatch,
    'ShowTES3MPExpansionMismatchDialog(mode := "Mismatch", authConfirmed := false)',
    '\nCloseTES3MPExpansionMismatchDialog(',
)
auto_progress_helpers = section_between(
    mismatch,
    'TES3MPExpansionCloakDialog(dialog, cloak)',
    '\n; The native explanation opens immediately.',
)
expect(
    "First-enable discovery UI is compositor-cloaked BEFORE show; manual browse/mismatch stays visible",
    'cloaked := mode = "Install" && TES3MPExpansionCloakDialog(dialog, true)' in auto_install_view
    and auto_install_view.index('TES3MPExpansionCloakDialog(dialog, true)')
        < auto_install_view.index('dialog.Show("w660 h627")')
    and 'if cloaked' in auto_install_view
    and 'if TES3MPExpansionBeginNativeProgress()' in auto_install_view
    and 'SetTimer((*) => TES3MPExpansionRetryNativeProgress(dialog), -300)' in auto_install_view
    and 'TES3MPExpansionRevealRepair("Native download window could not initialize.' in auto_progress_helpers
    and 'mode != "Mismatch"' in auto_install_view
    and 'TES3MPExpansionCloakDialog(ExpansionMismatchDialog, false)' in auto_progress_helpers
    and 'DllCall("dwmapi\\DwmSetWindowAttribute"' in auto_progress_helpers
    and 'if IsObject(ExpansionAutoCloaked)' not in auto_progress_helpers,
)
expect(
    "Initial native progress failure gets one deferred retry without prematurely revealing repair",
    'TES3MPExpansionRetryNativeProgress(dialog)' in auto_progress_helpers
    and 'if !TES3MPExpansionBeginNativeProgress()' in auto_progress_helpers
    and 'SetTimer((*) => TES3MPExpansionDiscoveryDeadline(dialog), -60000)' in auto_progress_helpers
    and 'SetTimer((*) => TES3MPExpansionStartDiscoveredZip(ExpansionMismatchSlot, ExpansionMismatchStatus), -80)' in auto_progress_helpers
    and 'if ExpansionAutoCloaked' in auto_install_view + mismatch
    and 'if ExpansionMismatchMode = "Install" && IsObject(ExpansionAutoProgressFrame)' in mismatch
    and 'TES3MPExpansionRevealRepair("Automatic download failed.' in mismatch,
)
expect(
    "Native first-enable progress reuses the trusted import loader and offers safe cancel",
    'TES3MPExpansionCallNativeUi("CaptureInterfaceFrame", LauncherGui, true)' in auto_progress_helpers
    and 'ExpansionAutoCancelButton := TES3MPExpansionCallNativeUi("AddStyledButton", frame.Card,' in auto_progress_helpers
    and 'frame.Card.BackColor := "161007"' not in auto_progress_helpers
    and 'frame.Panel.Move(0, 0, cw, ch + extra)' in auto_progress_helpers
    and 'TES3MPExpansionCallNativeUi("ProtectExpansionLoadingCancel", frame, ExpansionAutoCancelButton)' in auto_progress_helpers
    and auto_progress_helpers.index('frame.Card.Show("NA h" (ch + extra))')
        < auto_progress_helpers.index('frame.Panel.Move(0, 0, cw, ch + extra)')
        < auto_progress_helpers.index('ExpansionAutoCancelButton := TES3MPExpansionCallNativeUi(')
        < auto_progress_helpers.index('TES3MPExpansionCallNativeUi("ProtectExpansionLoadingCancel", frame, ExpansionAutoCancelButton)')
    and 'LauncherGui.Opt("+Disabled")' in auto_progress_helpers
    and 'TES3MPExpansionCallNativeUi("UpdateExpansionLoadingProgress", frame, label, percent)' in auto_progress_helpers
    and 'global ExpansionAutoProgressFrame, ButtonFaces' not in auto_progress_helpers
    and 'ButtonFaces[' not in auto_progress_helpers
    and 'TES3MPExpansionCallNativeUi("DestroyBookControl", ExpansionAutoCancelButton)' in auto_progress_helpers
    and 'TES3MPExpansionCallNativeUi("ReleaseCapturedInterfaceFrame", frame)' in auto_progress_helpers
    and 'SetTimer((*) => TES3MPExpansionDiscoveryDeadline(dialog), -60000)' in auto_install_view
    and 'TES3MPExpansionRevealRepair("Automatic download failed.' in mismatch
    and 'TES3MPExpansionUpdateNativeProgress(label, wParam)' in mismatch
    and 'TES3MPExpansionEndNativeProgress()\n    ExpansionAutoInstallLocked := false\n    ExpansionMismatchFileButton := 0' in mismatch
    and 'UploadExpansionFromFile(package, true)' in mismatch,
)
auto_download_ready = section_between(
    mismatch,
    'TES3MPExpansionAutoDownloadReady(lParam)\n{',
    '\nTES3MPExpansionBeginAutoImport(',
)
auto_download_cancel = section_between(
    mismatch,
    'TES3MPExpansionCancelNativeDownload()\n{',
    '\nTES3MPExpansionDiscoveryDeadline(',
)
auto_download_close = section_between(
    mismatch,
    'CloseTES3MPExpansionMismatchDialog(dialog, slotHwnd, import := false)\n{',
    '\nTES3MPExpansionZipAvailable(',
)
expect(
    "Cancel Download shares one full-height native panel with protected blit and cannot run after handoff",
    'frame.Card.BackColor := "161007"' not in auto_progress_helpers
    and 'frame.Panel.Move(0, 0, cw, ch + extra)' in auto_progress_helpers
    and 'frame.Panel.Opt("+0x04000000")' not in auto_progress_helpers
    and 'TES3MPExpansionCallNativeUi("ProtectExpansionLoadingCancel", frame, ExpansionAutoCancelButton)' in auto_progress_helpers
    and 'ch + Max(2, (extra - 31) // 2), buttonWidth, 31, "Cancel Download",' in auto_progress_helpers
    and auto_progress_helpers.index('frame.Card.Show("NA h" (ch + extra))')
        < auto_progress_helpers.index('ExpansionAutoCancelButton := TES3MPExpansionCallNativeUi(')
    and 'TES3MPExpansionRemoveDownloadCancel()' in auto_progress_helpers
    and 'try ExpansionAutoCancelButton.Visible := false' in auto_progress_helpers
    and 'TES3MPExpansionCallNativeUi("DestroyBookControl", ExpansionAutoCancelButton)' in auto_progress_helpers
    and 'if ExpansionAutoInstallLocked\n        return' in auto_download_cancel
    and 'ExpansionAutoInstallLocked := true' in auto_download_ready
    and 'ExpansionAutoDownloadActive := false' in auto_download_ready
    and 'TES3MPExpansionRemoveDownloadCancel()' in auto_download_ready
    and auto_download_ready.index('ExpansionAutoInstallLocked := true')
        < auto_download_ready.index('TES3MPExpansionRemoveDownloadCancel()')
        < auto_download_ready.index('SetTimer((*) => TES3MPExpansionBeginAutoImport(')
    and 'TES3MPExpansionEndNativeProgress()\n    ExpansionAutoInstallLocked := false' in auto_download_close
    and 'UploadExpansionFromFile(package, true)' in mismatch,
)
expect(
    "All new native progress UI dependencies use explicit AHK function-object resolution",
    'TES3MPExpansionCallNativeUi(name, args*)' in auto_progress_helpers
    and 'callback := %name%' in auto_progress_helpers
    and 'return callback.Call(args*)' in auto_progress_helpers
    and 'CaptureInterfaceFrame(LauncherGui, true)' not in auto_progress_helpers.replace(
        'TES3MPExpansionCallNativeUi("CaptureInterfaceFrame", LauncherGui, true)', '')
    and 'ExpansionAutoCancelButton := AddStyledButton(' not in auto_progress_helpers
    and 'PaintButtonNow(frame.Panel.Hwnd)' not in auto_progress_helpers
    and 'try DestroyBookControl(' not in auto_progress_helpers
    and 'try ReleaseCapturedInterfaceFrame(' not in auto_progress_helpers,
)
loading_ui = (ROOT / "src" / "ui" / "loading.ahk").read_text(encoding="utf-8-sig")
progress_painter = section_between(
    loading_ui,
    'UpdateExpansionLoadingProgress(frame, label, percent)\\n{'.replace('\\n', '\n'),
    '\\nSetInterfaceLoadingText('.replace('\\n', '\n'),
)
expect(
    "Expansion download progress avoids full native caption invalidation and never repaints Cancel",
    'TES3MPExpansionCallNativeUi("UpdateExpansionLoadingProgress", frame, label, percent)' in mismatch
    and 'global ButtonFaces' not in auto_progress_helpers
    and 'global ButtonFaces' in progress_painter
    and 'ButtonFaces[panelHwnd].DownloadText := frame.Panel.Text' in loading_ui
    and 'face.DownloadText := label' in progress_painter
    and 'face.ProgressHeaderOnly := true' in progress_painter
    and 'finally face.ProgressHeaderOnly := false' in progress_painter
    and 'PaintButtonNow(hwnd)' in progress_painter
    and 'PaintButtonNow(protectedButton)' not in progress_painter
    and progress_painter.index('face.ProgressHeaderOnly := true')
        < progress_painter.index('PaintButtonNow(hwnd)')
        < progress_painter.index('finally face.ProgressHeaderOnly := false')
    and 'frame.Panel.Text := label' in progress_painter.split('else')[-1],
)
native_renderer = (ROOT / "src" / "ui" / "renderer.ahk").read_text(encoding="utf-8-sig")
protected_loading_paint = section_between(
    native_renderer,
    "PaintLoadingPanel(handle, target, width, height)\\n{".replace("\\n", "\n"),
    "\\nFillLoadingRect(".replace("\\n", "\n"),
)
protected_loading_registration = section_between(
    loading_ui,
    "ProtectExpansionLoadingCancel(frame, cancelButton)\\n{".replace("\\n", "\n"),
    "\\nUpdateExpansionLoadingProgress(".replace("\\n", "\n"),
)
expect(
    "Native download Cancel is excluded from each full-height panel blit without changing other loading cards",
    'ProtectedButtonHwnd := cancelButton.Hwnd' in protected_loading_registration
    and 'PaintButtonNow(panelHwnd)' in protected_loading_registration
    and 'PaintButtonNow(cancelButton.Hwnd)' in protected_loading_registration
    and 'ButtonFaces[handle].HasOwnProp("ProtectedButtonHwnd")' in protected_loading_paint
    and 'DllCall("GetWindowRect", "Ptr", protectedButton,' in protected_loading_paint
    and 'DllCall("MapWindowPoints", "Ptr", 0, "Ptr", handle,' in protected_loading_paint
    and 'DllCall("SaveDC", "Ptr", target,' in protected_loading_paint
    and 'DllCall("ExcludeClipRect", "Ptr", target,' in protected_loading_paint
    and 'DllCall("RestoreDC", "Ptr", target,' in protected_loading_paint
    and protected_loading_paint.index('DllCall("ExcludeClipRect", "Ptr", target,')
        < protected_loading_paint.index('try DllCall("BitBlt", "Ptr", target,')
        < protected_loading_paint.index('DllCall("RestoreDC", "Ptr", target,'),
)
expect(
    "Protected download progress blits only header pixels while ordinary loading cards still repaint fully",
    'paintFace.HasOwnProp("DownloadText") ? paintFace.DownloadText : paintFace.Control.Text' in protected_loading_paint
    and 'paintFace.HasOwnProp("ProgressHeaderOnly") && paintFace.ProgressHeaderOnly' in protected_loading_paint
    and 'Min(height, Round(68 * scale)) : height' in protected_loading_paint
    and 'width, "Int", blitHeight' in protected_loading_paint
    and 'DllCall("ExcludeClipRect", "Ptr", target,' in protected_loading_paint
    and 'DllCall("RestoreDC", "Ptr", target,' in protected_loading_paint,
)
expect(
    "Native Expansion BitBlt has both mandatory source coordinates before raster-operation type",
    'try DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", blitHeight, "Ptr", dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)' in protected_loading_paint
    and 'try DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", blitHeight, "Ptr", dc, "Int", 0, "Int", "UInt", 0xCC0020)' not in protected_loading_paint,
)
expect(
    "Same ChatHost process and existing Discord profile serve the popup",
    'const string ExpansionChannel = "https://discord.com/channels/509601787901116437/1555049936800718928";' in source
    and 'discordEnvironment = env;' in source
    and 'await browser.EnsureCoreWebView2Async(env);' in source
    and 'case 6: ShowEmbeddedExpansionDownloads(m.LParam); break;' in source
    and 'case 7: CloseEmbeddedExpansionDownloads(m.LParam); break;' in source
    and source.count("Application.Run(new ChatHost(") == 1
    and source.count('Path.Combine(ChatDataRoot, "chat-webview2")') == 1,
)
expect(
    "WebView is a native child of mismatch placeholder, not floating Discord window",
    "SetParent(handle,placeholder);" in source
    and "GetParent(handle)!=placeholder" in source
    and "PositionEmbeddedExpansionDownloads();" in source
    and "CloseEmbeddedExpansionDownloads();" in source
    and "ToggleExpansionDownloads()" not in source,
)
expect(
    "Only genuine ZIP attachment URL is presented without Discord grid changes",
    'const string ExpansionDownloadsFocusScript = """' in source
    and "document.querySelector('[data-list-id=\"chat-messages\"]')" in source
    and r"cdn\.discordapp\.com" in source
    and r"media\.discordapp\.net" in source
    and r"location.pathname.replace(/\/+$/,'')" in source
    and "link.href=file.url;" in source
    and "link.textContent=file.filename;" in source
    and "new MutationObserver(changes=>{" in source
    and "await browser.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(" in source
    and "grid-template-columns: minmax(0, 1fr) !important" not in source,
)

expect(
    "Future expansion ZIP selection is ordered by Discord message snowflakes",
    "const channel='/channels/509601787901116437/1555049936800718928';" in source
    and "function snowflake(message)" in source
    and r"chat-messages-\d+-(\d{15,22})" in source
    and "BigInt(row[1])" in source
    and "BigInt(single[1])" in source
    and "item.id>best.id" in source
    and "item.id===best.id && item.order>=best.order" in source
    and "const files=readCandidates(feed);" in source
    and "remember(files);" in source
    and "link.href=file.url;" in source
    and "phase='present'" in source
    and "goToPresent(scroller)" in source
    and "const maxBackfills=12, maxLoadingRetries=30, maxPresentRetries=18;" in source
    and "presentRetries<=maxPresentRetries" in source
    and "attributes:true,attributeFilter:['href']" in source
    and "new MutationObserver(changes=>{" in source
    and "lastFileKey===key" in source
    and "grid-template-columns:" not in source,
)

expect(
    "ZIP click is handed to default Windows browser without navigating embedded Discord",
    "link.addEventListener('click',event=>" in source
    and "event.preventDefault();" in source
    and "event.stopPropagation();" in source
    and "chrome.webview.postMessage({type:'expansion-download',url});" in source
    and "status.textContent='';" in source
    and "type==\"expansion-download\"" in source
    and "IsOfficialExpansionDownloadUrl(link)" in source
    and "Uri.TryCreate(value, UriKind.Absolute, out var uri)" in source
    and "Uri.UriSchemeHttps" in source
    and 'uri.Host != "cdn.discordapp.com"' in source
    and 'uri.Host != "media.discordapp.net"' in source
    and 'uri.AbsolutePath.StartsWith("/attachments/"' in source
    and 'filename.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)' in source
    and "UseShellExecute=true" in source
    and "Task.Run(()=>{" in source
    and "e.Cancel=true;" in source
    and "link.target='_self'" not in source,
)

expect(
    "Repeated ZIP downloads isolate launcher from WebView2 and ShellExecute",
    'TES3MPExpansionRequestDownload(downloadSlot.Hwnd, nativeStatus, "main-button")' in mismatch
    and 'TES3MPExpansionRequestDownload(downloadSlot.Hwnd, nativeStatus, "retry-button")' in mismatch
    and 'TES3MPExpansionRequestDownload(slotHwnd, statusControl, origin := "download")' in mismatch
    and 'global ExpansionMismatchFileButton := 0' in mismatch
    and 'global ExpansionMismatchDownloadSlot := 0' in mismatch
    and 'ExpansionMismatchDownloadSlot := downloadSlot' in mismatch
    and 'ExpansionMismatchDownloadSlot.Visible := false' in mismatch
    and 'ExpansionMismatchFileButton.Visible := true' in mismatch
    and 'SetTimer((*) => TES3MPExpansionActivateDownloadButton(slot), -30)' in mismatch
    and 'void HideEmbeddedExpansionDownloads(IntPtr placeholder)' in source
    and 'SendLauncherChatCommand(9, slotHwnd)' in mismatch
    and 'DllCall("SetWindowPos", "Ptr", ExpansionMismatchFileButton.Hwnd,' in mismatch
    and 'case 9: HideEmbeddedExpansionDownloads(m.LParam); break;' in source
    and 'void HideEmbeddedExpansionDownloads(IntPtr placeholder)' in source
    and 'ShowWindow(window.Handle,0);' in source
    and 'var browser=new WebView2 { Dock=DockStyle.Fill };' in source
    and "Run('rundll32.exe url.dll,FileProtocolHandler" in mismatch
    and 'Run(url)' not in mismatch
    and 'statusControl.Text := ""' in mismatch
    and 'OnMessage(0x004A, TES3MPExpansionZipAvailable)' in bootstrap
    and 'TES3MPExpansionZipAvailable(wParam, lParam, msg, hwnd)' in mismatch
    and 'ExpansionMismatchZipUrl := url' in mismatch
    and 'ExpansionMismatchZipUrl := ""' in mismatch
    and 'SendCopyDataTimeout(owner,0x004A,sender,' in source
    and 'ref data,0x0002,1500,out var result' in source
    and 'Marshal.StringToHGlobalUni(payload)' in source
    and 'Marshal.FreeHGlobal(utf16)' in source
    and '(WinGetPID("ahk_id " wParam) = EmbeddedChatPid)' in mismatch
    and 'PostMessage(owner,0x8335,popupSlot,IntPtr.Zero)' not in source
    and 'ExpansionMismatchRefreshPending' not in mismatch
    and 'ShowNativeExpansionDownloadCard(' not in source
    and 'setTimeout(()=>{scheduled=false;refresh();},150);' in source,
)

expect(
    "Plugin mismatch report identifies Expansion Pack versus other-plugin evidence without private fields",
    '"Your Plugins Don\'t Match the Server"' in mismatch
    and '"Copy Diagnostic Info"' in mismatch
    and 'TES3MPCopyMismatchDiagnostics(nativeStatus)' in mismatch
    and 'report := TES3MPBuildMismatchDiagnostics()' in mismatch
    and 'TES3MPTryCopyMismatchReport(report, statusControl, limited)' in mismatch
    and 'A_Clipboard := report' in mismatch
    and '"Diagnostic Info Copied!"' in mismatch
    and 'if attempt < 3' in mismatch
    and 'TES3MPBuildMinimumMismatchDiagnostics()' in mismatch
    and 'TES3MPAnalyzeMismatchConfig(configText)' in mismatch
    and 'TES3MPAnalyzeMismatchLogText(raw)' in mismatch
    and 'TES3MPMismatchAssessment(info, markers, installed)' in mismatch
    and 'TES3MPRenderMismatchDiagnostics(info, markers, installed, version, stamp, fingerprint := 0)' in mismatch
    and 'result.MissingExpansion := true' in mismatch
    and 'result.MissingOther := true' in mismatch
    and 'result.MissingBaseMaster := true' in mismatch
    and 'info.OtherDuplicates += 1' in mismatch
    and 'info.ExpansionIndex != info.Total' in mismatch
    and 'if currentIndex = lastRejection\n            continue' in mismatch
    and 'markers.Status = "Read" && markers.Rejected' in mismatch
    and 'Other missing plugin specifically indicated:' in mismatch
    and 'Missing Expansion Pack specifically named:' in mismatch
    and 'Expansion Pack version verified: No (not checked)' in mismatch
    and 'OpenMW config check:' in mismatch
    and 'TES3MPReadSafeMismatchLogMarkers()' in mismatch
    and 'FileGetSize(config) > 1048576' in mismatch
    and 'file.Length - 65536' in mismatch
    and 'statusControl.Text := ""' in mismatch
    and "status.textContent='';" in source
    and 'Starting Download...' not in mismatch
    and 'Starting Download...' not in source
    and 'SAFE PLUGIN MISMATCH' not in mismatch
    and 'Privacy: No raw log' not in mismatch
    and 'Basic diagnostic info copied' not in mismatch
    and 'BuildLauncherDiagnostics()' not in mismatch
    and 'A_Clipboard := raw' not in mismatch
    and 'A_Clipboard := FileRead(' not in mismatch,
)
expect(
    "Windows build executes synthetic parser and report privacy fixtures",
    (ROOT / "scripts" / "test-expansion-diagnostics.ahk").is_file()
    and "test-expansion-diagnostics.ahk" in (
        ROOT / "scripts" / "build-windows.ps1"
    ).read_text(encoding="utf-8-sig")
    and "Plugin-mismatch diagnostic fixture tests failed" in (
        ROOT / "scripts" / "build-windows.ps1"
    ).read_text(encoding="utf-8-sig"),
)

expect(
    "Diagnostic reports are complete and standalone fixtures cannot emit unresolved-symbol warnings",
    'report := "TES3NP - Plugin Mismatch Diagnostics' in mismatch
    and 'report .= "Repeated additional content entries: "' in mismatch
    and 'report .= "Load-order wording near rejection: "' in mismatch
    and '    return report\n}' in mismatch
    and bool(section_between(
        mismatch,
        'TES3MPRenderMismatchDiagnostics(info, markers, installed, version, stamp, fingerprint := 0)\n{',
        'TES3MPNewExpansionFingerprintResult(status := "Not checked")\n{',
    ))
    and '    return "TES3NP - Plugin Mismatch Diagnostics' not in section_between(
        mismatch,
        'TES3MPRenderMismatchDiagnostics(info, markers, installed, version, stamp, fingerprint := 0)\n{',
        'TES3MPNewExpansionFingerprintResult(status := "Not checked")\n{',
    )
    and 'PatchConfigurationPath()' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'MismatchFixtureDisallow("configuration path")' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and all(marker in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig") for marker in (
        "global Client :=",
        "global LauncherGui := 0",
        "global EmbeddedChatPid := 0",
        'global DataFile := ""',
    ))
    and 'InStr(report, "Load-order wording near rejection: No")' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'TES3MPLastMismatchEvidence := TES3MPAnalyzeMismatchLogText(currentText)' in mismatch
    and 'TES3MPSelectMismatchLogEvidence(captured)' in mismatch
    and 'markers := TES3MPSelectMismatchLogEvidence(TES3MPLastMismatchEvidence)' in mismatch
    and 'Client evidence source: ' in mismatch
    and 'TES3MPLastMismatchEvidence := 0' in (
        ROOT / "src" / "game" / "session.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'chosen.Source = "Captured during failed login"' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'AutoHotkey fixture warnings detected; packaging stopped.' in (
        ROOT / "scripts" / "build-windows.ps1"
    ).read_text(encoding="utf-8-sig"),
)

expect(
    "Mismatch capture remains bounded to the current failed login and reports safe comparison categories",
    'Client.MismatchPending := true' in mismatch
    and 'Client.MismatchLogKey := key' in mismatch
    and 'key != Client.MismatchLogKey' in mismatch
    and 'Client.MismatchCaptureUntil := A_TickCount + 1500' in mismatch
    and 'TES3MPAccumulateMismatchDetailText(TES3MPLastMismatchEvidence, chunk)' in mismatch
    and 'TES3MPAccumulateMismatchLine(result, line)' in mismatch
    and 'Slot details (zero-based): ' in mismatch
    and 'if shown >= 12' in mismatch
    and 'result.SlotFlags[slot] := oldBits | newBits' in mismatch
    and 'TES3MPLastMismatchEvidence := 0' in (
        ROOT / "src" / "game" / "session.ahk"
    ).read_text(encoding="utf-8-sig"),
)
expect(
    "Expansion fingerprint uses Windows CNG and does not claim server version verification",
    'TES3MPFileSHA256(path)' in mismatch
    and 'bcrypt\\BCryptHashData' in mismatch
    and 'block := Buffer(1048576, 0)' in mismatch
    and 'Expansion ESP SHA-256: ' in mismatch
    and 'Expansion ESP size (bytes): ' in mismatch
    and 'Expansion Pack version verified: No (not checked)' in mismatch
    and 'known SHA-256 test vector' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'private comparison detail leaked' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig"),
)

resource_generator = (ROOT / "scripts" / "generate-bundled-resources.py").read_text(encoding="utf-8-sig")
expansion_picker = (ROOT / "scripts" / "select-expansion-package.ps1").read_text(encoding="utf-8-sig")
expansion_worker = (ROOT / "scripts" / "import-expansion-pack.ps1").read_text(encoding="utf-8-sig")
expansion_build = (ROOT / "scripts" / "build-windows.ps1").read_text(encoding="utf-8-sig")
expansion_fixture = (ROOT / "scripts" / "test-import-expansion-folder.ps1").read_text(encoding="utf-8-sig")
expect(
    "Official Ahk2Exe asset download and local reuse require SHA-256",
    "if ($compilerAsset.url -notmatch '^https://api\\.github\\.com/repos/AutoHotkey/Ahk2Exe/releases/assets/[0-9]+$')" in expansion_build
    and "'Official Ahk2Exe release SHA-256 digest is unavailable" in expansion_build
    and "'Accept'] = 'application/octet-stream'" in expansion_build
    and "SaveOfficialDownload $compilerAsset.browser_download_url $compilerZip $headers 'Ahk2Exe' $compilerAsset.url $expectedCompilerHash $apiHeaders" in expansion_build
    and "if ((GetTes3npSha256 $candidate) -ieq $expectedCompilerHash)" in expansion_build
    and "if ((GetTes3npSha256 $compilerZip) -ine $expectedCompilerHash)" in expansion_build
    and "CheckOfficialZip $compilerZip 'Ahk2Exe'" in expansion_build
    and "Using verified local official Ahk2Exe ZIP" in expansion_build,
)
expect(
    "AutoHotkey mirror and persistent cache require GitHub release SHA-256",
    "'https://docs.autohotkey.com/download/2.0/' + $ahkAsset.name" in expansion_build
    and "'^AutoHotkey_2\\.0\\.\\d+\\.zip$'" in expansion_build
    and "'Official AutoHotkey release SHA-256 digest is unavailable" in expansion_build
    and "SaveOfficialDownload $ahkAsset.browser_download_url $ahkZip $headers 'AutoHotkey' $ahkMirror $expectedAhkHash" in expansion_build
    and "if ($ExpectedSha256 -and (GetTes3npSha256 $Destination) -ine $ExpectedSha256)" in expansion_build
    and "Using cached official AutoHotkey ZIP (SHA-256 verified)" in expansion_build
    and "CheckOfficialZip $ahkZip 'AutoHotkey'" in expansion_build
    and "if ((GetTes3npSha256 $ahkZip) -ine $expectedAhkHash)" in expansion_build,
)
expect(
    "Windows build retries official GitHub downloads and retains dist on upstream failure",
    "function GetOfficialRelease(" in expansion_build
    and "function SaveOfficialDownload(" in expansion_build
    and "for ($attempt = 1; $attempt -le 3; $attempt++)" in expansion_build
    and "CheckOfficialZip $ahkZip 'AutoHotkey'" in expansion_build
    and "CheckOfficialZip $compilerZip 'Ahk2Exe'" in expansion_build
    and "CheckOfficialZip $tes3mpArchive 'TES3MP 0.8.1'" in expansion_build
    and "SaveOfficialDownload $upstreamFontLicense" in expansion_build
    and expansion_build.index("SaveOfficialDownload $upstreamFontLicense")
        < expansion_build.index("if (Test-Path (Join-Path $projectRoot 'dist'))"),
)
expect(
    "One native Windows Explorer-style source browser picks ZIP or extracted folder",
    'package := SelectExpansionPackagePath()' in expansion_upload
    and 'InstallSelectedExpansionPackage(package)' in expansion_upload
    and 'StartExpansionImportWorker(package, morrowind, config)' in expansion_upload
    and 'select-expansion-package.ps1' in expansion_upload
    and 'RunWait(command, , "Hide")' in expansion_upload
    and 'DllCall("GetCurrentProcessId", "UInt")' in expansion_upload
    and 'A_Pid' not in expansion_upload
    and "Preflighting full AutoHotkey launcher source and warning diagnostics" in expansion_build
    and '$launcherOutput = @(& $base /ErrorStdOut $launcherSource' in expansion_build
    and "'AutoHotkey launcher source warnings detected before packaging.'" in expansion_build
    and "Preflighting generated standalone AutoHotkey source and warning diagnostics" in expansion_build
    and "$stageOutput = @(& $base /ErrorStdOut $stageEntry '--check' 2>&1)" in expansion_build
    and "'Staged AutoHotkey launcher warnings detected before compilation.'" in expansion_build
    and 'DirExist(package)' in expansion_upload
    and 'StrLower(extension) = "zip"' in expansion_upload
    and 'ChooseExpansionPackageSource' not in expansion_upload
    and 'Select ZIP (Recommended)' not in expansion_upload
    and 'System.IO.Compression' not in expansion_picker
    and '[TES3NP.Expansion.NativePicker]::Select($OwnerHwnd)' in expansion_picker
    and 'AddPushButton(ChooseFolderButton, "Use This Folder")' in expansion_picker
    and 'fileDialog.Close(0);' in expansion_picker
    and 'fileDialog.GetCurrentSelection(out selection)' in expansion_picker
    and 'fileDialog.GetFolder(out folder)' in expansion_picker
    and 'Directory.Exists(folderPath)' in expansion_picker
    and 'File.Exists(path)' in expansion_picker
    and '[TES3NP.Expansion.NativePicker]::SmokeTest()' in expansion_picker
    and 'select-expansion-package.ps1' in expansion_build
    and 'Native Expansion Pack picker COM smoke test failed' in expansion_build
    and '"select-expansion-package.ps1"' in resource_generator
    and '"import-expansion-pack.ps1"' in resource_generator
    and "Missing extracted Expansion Pack helper:" in expansion_build
    and "Bundled Expansion Pack helper differs from source:" in expansion_build
    and "Verified both extracted Expansion Pack helpers and source SHA-256 hashes" in expansion_build,
)
expect(
    "Folder imports use ZIP-equivalent allowlist, limits and unchanged rollback",
    'if ([IO.Directory]::Exists($Package)) {' in expansion_worker
    and "$folderIsDataFiles = $root.Name -ieq 'Data Files'" in expansion_worker
    and "elseif ($raw -match '(?i)(^|/)Data Files/(.+)$')" in expansion_worker
    and 'Get-ChildItem -LiteralPath $root.FullName -Recurse -Force -ErrorAction Stop' in expansion_worker
    and '[IO.FileAttributes]::ReparsePoint' in expansion_worker
    and 'AllowedAsset $relative' in expansion_worker
    and "'^Sound/tes3mp_np/[^:]+$'" in expansion_worker
    and "return $extension -in @('.wav','.ogg','.mp3')" in expansion_worker
    and "CheckWorker $packageRoot 'reject-foreign-sound'" in expansion_fixture
    and "CheckWorker $packageRoot 'reject-non-audio-sound'" in expansion_fixture
    and '$seen.Add($relative)' in expansion_worker
    and '$entryCount -gt 10000' in expansion_worker
    and 'AssertSpace $staged ([long]$entry.Length)' in expansion_worker
    and 'AssertSpace $staged ([long]$item.Length)' in expansion_worker
    and 'AssertSpace $item.Target' in expansion_worker
    and 'AssertSpace $JobFolder' in expansion_worker
    and 'function InvokeFileOperation([string]$Kind, [string]$Source, [string]$Destination, [string]$Operation)' in expansion_worker
    and 'InvokeLockRetry' not in expansion_worker
    and "'hash' {" in expansion_worker
    and "'copy' {" in expansion_worker
    and "'replace' {" in expansion_worker
    and "'move' {" in expansion_worker
    and "'zipopen' {" in expansion_worker
    and "InvokeFileOperation 'hash' $Path" in expansion_worker
    and "InvokeFileOperation 'copy' $Source $Target $Operation" in expansion_worker
    and "InvokeFileOperation 'replace' $temp $Target" in expansion_worker
    and "InvokeFileOperation 'move' $temp $Target" in expansion_worker
    and "InvokeFileOperation 'zipopen' $Package" in expansion_worker
    and 'function WriteJobIni([string]$Name, [string]$Body)' in expansion_worker
    and "WriteJobIni 'progress.ini' $body" in expansion_worker
    and "WriteJobIni 'result.ini' $body" in expansion_worker
    and "InvokeFileOperation 'replace' $temp $target ('publishing import ' + $Name)" in expansion_worker
    and "InvokeFileOperation 'move' $temp $target ('publishing import ' + $Name)" in expansion_worker
    and "[IO.File]::WriteAllText((Join-Path $JobFolder 'progress.ini')" not in expansion_worker
    and "[IO.File]::WriteAllText((Join-Path $JobFolder 'result.ini')" not in expansion_worker
    and "CheckWorker $zip 'zip-progress-reader-lock' $true '' $true" in expansion_fixture
    and "did not exercise the locked progress.ini publisher" in expansion_fixture
    and "Start-Process -FilePath $windowsPowerShell -ArgumentList $childArgs -PassThru" in expansion_fixture
    and 'progress.ini' in expansion_fixture
    and '$code -notin @(32,33)' in expansion_worker
    and 'for ($attempt = 1; $attempt -le 6; $attempt++)' in expansion_worker
    and '[IO.File]::Replace($Source, $Destination, [NullString]::Value)' in expansion_worker
    and '[IO.File]::Replace($Source, $Destination, $null)' not in expansion_worker
    and '[IO.File]::Replace($Source, $Destination, [NullString]::Value)' in expansion_fixture
    and '[IO.File]::Replace($replaceNew, $replaceOld, [NullString]::Value)' in expansion_fixture
    and 'CLR null File.Replace cannot update an existing config' in expansion_fixture
    and 'File.Replace left a staging file after replacing configuration' in expansion_fixture
    and 'Start-Sleep -Milliseconds' in expansion_worker
    and 'function CopyWithRetry(' in expansion_worker
    and 'CopyWithRetry $item.Target $backup' in expansion_worker
    and 'CopyWithRetry $Source $temp' in expansion_worker
    and 'Temporary import copy destination already exists.' in expansion_worker
    and "[step: " in expansion_worker
    and "failed without a sanitized diagnostic stage" in expansion_fixture
    and 'Rollback was incomplete' in expansion_fixture
    and "CheckWorker $zip 'recover-after-lock' $true" in expansion_fixture
    and "CheckWorker $zip 'reject-persistent-win32-lock' $false" in expansion_fixture
    and 'ReplaceVerified $item.Source $item.Target $item.Hash\n        $changed += $backups[$i]' in expansion_worker
    and 'function InvokeFileOperation(' in expansion_fixture
    and "Unpacked Expansion Pack exceeds the 1 GB limit." not in expansion_worker
    and "Extracted Expansion Pack exceeds the 1 GB limit." not in expansion_worker
    and "134217728" not in expansion_worker
    and "if ($staged -and [IO.Directory]::Exists($staged))" in expansion_worker
    and "stage-cleanup-warning.txt" in expansion_worker
    and "left a full duplicate of the pack in staging" in expansion_fixture
    and 'Sha256 $target' in expansion_worker
    and 'if ($rollbackReady) {' in expansion_worker
    and 'CheckWorker $zip' in expansion_fixture
    and 'CheckWorker $packageRoot' in expansion_fixture
    and 'CheckWorker $payload' in expansion_fixture
    and 'CheckWorker $packageRoot ' in expansion_fixture
    and 'Add-Type -AssemblyName System.IO.Compression\n' in expansion_fixture
    and 'Add-Type -AssemblyName System.IO.Compression.FileSystem\n' in expansion_fixture
    and '[IO.Compression.ZipArchiveMode]::Create' in expansion_fixture
    and '[IO.Compression.ZipFileExtensions]::CreateEntryFromFile(' in expansion_fixture
    and ".Replace('\\', '/')" in expansion_fixture
    and "CheckWorker $badZip 'reject-backslash-entry' $false 'unsafe file path'" in expansion_fixture
    and "CheckWorker $packageRoot 'reject-unknown-asset' $false 'Unexpected file in Expansion Pack Data Files'" in expansion_fixture
    and "AssertFixture (!$entry.FullName.Contains('\\'))" in expansion_fixture
    and 'test-import-expansion-folder.ps1' in expansion_build
    and '$productionWorker = Join-Path $PSScriptRoot' in expansion_fixture
    and '$worker = Join-Path $root' in expansion_fixture
    and 'AssertFixture ($workerText.Contains($productionGuard))' in expansion_fixture
    and '$env:TES3NP_IMPORT_FIXTURE_ROOT = $root' in expansion_fixture
    and 'Fixture refused a target outside its disposable game folder.' in expansion_fixture
    and 'detail=$workerMessage' in expansion_fixture
    and 'Remove-Item Env:\\TES3NP_IMPORT_FIXTURE_ROOT' in expansion_fixture
    and "if (Get-Process -Name 'tes3mp','openmw','openmw-launcher'" in expansion_worker,
)

expect(
    "Banner must stay owned by launcher and retain movement polling fallback",
    "SetNativeWindowOwner(banner.Handle, owner);" in source
    and "void PositionChatWindows()\n        {\n            // The existing chat polling is a safety net" in source
    and "bounds.Top - 48" in source,
)

expect(
    "Jiub Happy Hour face must use only the existing verified banner signal",
    "OnMessage(0x8334, LauncherHappyHourFaceStateChanged)" in jiub_ui
    and "PostMessage(owner, 0x8334, active ? new IntPtr(1) : IntPtr.Zero" in source
    and "NotifyLauncherHappyHourFace(true);" in source
    and "NotifyLauncherHappyHourFace(false);" in source
    and "HappyHourBannerVisible := visible" in jiub_ui,
)
expect(
    "Jiub Happy Hour face must follow banner close, hide and restore",
    'banner.FormClosed += (_, _) => {' in source
    and 'if (!happyHourBanner.Visible) {' in source
    and 'happyHourBanner.Show();\n                        // The verified banner is visible again after a launcher restore.\n                        NotifyLauncherHappyHourFace(true);' in source
    and 'happyHourBanner.Hide();\n                    // Keep Jiub\'s appearance in sync when the banner is hidden.\n                    NotifyLauncherHappyHourFace(false);' in source,
)
expect(
    "Jiub picture must be a bundled native launcher control, without a floating window",
    'asset := A_ScriptDir "\\assets\\happy-hour\\jiub-happy-hour.png"' in jiub_ui
    and (ROOT / "assets" / "happy-hour" / "jiub-happy-hour.png").is_file()
    and 'LauncherGui.Add("Picture"' in jiub_ui
    and ':= Gui(' not in jiub_ui
    and 'CreateHappyHourJiub()\n    CaptureLauncherControlLayout()' in bootstrap
    and 'HappyHourJiubPicture.Visible := HappyHourBannerVisible' in jiub_ui,
)




expect(
    "Static Happy Hour RGB pixie dust must be bundled and use the same banner state",
    (ROOT / "assets" / "happy-hour" / "pixie-dust.png").is_file()
    and 'asset := A_ScriptDir "\\assets\\happy-hour\\pixie-dust.png"' in jiub_ui
    and 'CreateHappyHourDust()' in jiub_ui
    and 'for offset in [[0, 0], [1, 0], [0, 1], [1, 1]]' in jiub_ui
    and 'w960 h720 Hidden Disabled BackgroundTrans +E0x20' in jiub_ui
    and 'for dust in HappyHourDustPictures' in jiub_ui
    and 'dust.Visible := HappyHourBannerVisible' in jiub_ui
    and 'HappyHourJiubPicture.Visible := HappyHourBannerVisible' in jiub_ui
    and 'SetTimer(AnimateHappyHour' not in jiub_ui,
)
expect(
    "Pixie dust must sit over background but under interactive launcher controls",
    (lambda front:
        front.index('LauncherGui.Add("Picture", "x0 y-4 w960 h720"')
        < front.index('CreateHappyHourDust()')
        < front.index('DragStrip := LauncherGui.Add(')
        < front.index('BuildButtonViewport()')
    )((ROOT / "src" / "ui" / "front-page.ahk").read_text(encoding="utf-8-sig")),
)

expect(
    "Vintage creatures are baked into the single launcher background",
    (lambda front, bootstrap:
        front.count('LauncherGui.Add("Picture", "x0 y-4 w960 h720"') == 1
        and "og-creatures-overlay.png" not in front
        and "og-creatures-overlay.png" not in bootstrap
        and not (ROOT / "assets" / "backgrounds" / "og-creatures-overlay.png").exists()
        and (ROOT / "assets" / "backgrounds" / "launcher.png").is_file()
        and front.index('LauncherGui.Add("Picture", "x0 y-4 w960 h720"')
            < front.index('CreateHappyHourDust()')
    )(
        (ROOT / "src" / "ui" / "front-page.ahk").read_text(encoding="utf-8-sig"),
        bootstrap,
    ),
)

expect(
    "Happy Hour banner has no dismiss button or dismissal state",
    'GoldButton("×"' not in source
    and 'dismissedHappyHourBannerId' not in source
    and 'happyHourBannerTitleInset.SetBounds(12, 7, width, 32)' in source,
)
expect(
    "Remove extra developer replay, special banner text and tray options",
    "--happy-hour-dev" not in source
    and "happyHourDevMode" not in source
    and "happyHourDevTicker" not in source
    and "HAPPY HOUR DEV PREVIEW" not in source
    and "Archived event - No live bonus" not in source
    and "HappyHourDevModeEnabled" not in jiub_ui
    and "A_TrayMenu.Add" not in jiub_ui
    and "--happy-hour-dev" not in
        (ROOT / "src" / "ui" / "embedded-chat.ahk").read_text(encoding="utf-8-sig"),
)
expect(
    "Jiub coordinates and native control remain intact",
    '"x438 y84 w120 h135 Hidden BackgroundTrans"' in jiub_ui
    and '#Include src\\ui\\happy-hour.ahk'
        in (ROOT / "tes3np.ahk").read_text(encoding="utf-8-sig")
    and 'HappyHourJiubPicture.Visible := HappyHourBannerVisible' in jiub_ui,
)

expect(
    "Full AppData reset must stop ChatHost before deletion",
    reset_ui.index("StopEmbeddedInGameChat()") >= 0
    and reset_ui.index("StopEmbeddedInGameChat()") < reset_ui.index("DirDelete(AppDataDirectory, true)"),
)
expect(
    "Full AppData reset must confirm ChatHost has exited before deleting user data",
    "chatPid := EmbeddedChatPid" in reset_ui
    and "stillRunning := ProcessWaitClose(chatPid, 5)" in reset_ui
    and "if stillRunning" in reset_ui
    and reset_ui.index("ProcessWaitClose(chatPid, 5)") < reset_ui.index("DirDelete(AppDataDirectory, true)"),
)
expect(
    "Reset shutdown must not recreate Roaming logs or preferences",
    "LauncherDataResetting := true" in reset_ui
    and "if !LauncherDataResetting" in bootstrap
    and "ExitApp()" in reset_ui,
)
expect(
    "Reset mode must be part of centralized launcher state",
    "global LauncherDataResetting := false" in app_state,
)

settings_layout = (ROOT / "src" / "ui" / "v016-refinements.ahk").read_text(encoding="utf-8-sig")
shortcut_offer = section_between(
    bootstrap, "OfferDesktopShortcutOnFirstLaunch(*)", "\n}",
)
expect(
    "Desktop shortcut is a one-time first-launch choice, never a Settings button",
    'SetTimer(OfferDesktopShortcutOnFirstLaunch, -1800)' in bootstrap
    and bootstrap.count("SetTimer(OfferDesktopShortcutOnFirstLaunch, -1800)") == 1
    and "SetTimer(CheckFirstRunMorrowind" not in bootstrap
    and 'AddStyledButton(settings, V016S(32), V016S(483), V016S(448), V016S(30),' in settings_layout
    and '"Close Settings", CloseLauncherSettingsV016.Bind(settings))' in settings_layout
    and '"Create Desktop Shortcut"' not in settings_layout
    and 'AddStyledButton(settings, V016S(266), V016S(435), V016S(214), V016S(30), "Game Client Settings", OpenClientSelectionSettings)' in settings_layout
    and 'AddStyledButton(settings, V016S(32), V016S(435), V016S(214), V016S(30), "Launcher Data", OpenAppDataSettingsV016.Bind(settings))' in settings_layout
    and 'if !A_IsCompiled || !FileExist(A_ScriptDir "\\client\\tes3mp.exe")' in shortcut_offer
    and 'IniRead(DataFile, "Launcher", "DesktopShortcutChoice", "") != ""' in shortcut_offer
    and 'answer := MsgBox("Would you like a desktop shortcut for Nerevarine Prophecies?"' in shortcut_offer
    and 'IniWrite(answer = "Yes" ? "Yes" : "No", DataFile, "Launcher", "DesktopShortcutChoice")' in shortcut_offer
    and shortcut_offer.index('IniWrite(answer = "Yes"') < shortcut_offer.index('FileCreateShortcut(')
    and 'FileCreateShortcut(A_ScriptFullPath, A_Desktop "\\Nerevarine Prophecies.lnk"' in shortcut_offer
    and "forceAfterInstall" not in bootstrap,
)
characters_ui = (ROOT / "src" / "ui" / "characters.ahk").read_text(encoding="utf-8-sig")
settings_open = section_between(
    settings_layout,
    "OpenLauncherSettingsV016(*)",
    "\nCloseLauncherSettingsV016(settings, *)",
)
settings_close = section_between(
    settings_layout,
    "CloseLauncherSettingsV016(settings, *)",
    "\nV016CheckLabel(state, label)",
)
characters_close = section_between(
    characters_ui,
    "CloseCharacterPage(*)",
    "\nEditProfile(index, *)",
)
expect(
    "Settings transparency is applied while hidden and launcher owns foreground before close",
    'settings.Show("Hide w" V016S(512) " h" V016S(590))' in settings_open
    and settings_open.index('settings.Show("Hide w"')
        < settings_open.index('SetPageColorKey(settings, 0x010101)')
        < settings_open.index('    settings.Show()')
    and 'WinSetTransColor(' not in settings_open
    and 'if staged\n            RevealPaintedPage(settings)\n        else\n            FinishButtonDisplay()' in settings_open
    and 'DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 1)' in settings_close
    and settings_close.index('DllCall("EnableWindow"')
        < settings_close.index('try WinActivate("ahk_id " LauncherGui.Hwnd)')
        < settings_close.index('try settings.Destroy()'),
)
launcher_return = section_between(
    bootstrap,
    "ShowLauncherWindow(reuseCached := false, *)",
    "\nSetWindowIcons()",
)
expect(
    "Owned Character Book uses already-painted visible parent without global repaint before Hide",
    'if reuseCached && LauncherCachedScale > 0' in launcher_return
    and 'DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)' in launcher_return
    and 'LauncherControlLayout.Count = LauncherCachedLayoutCount' in launcher_return
    and 'desiredCachedScale := LauncherScaleMode = "Auto" ? GetAutomaticLauncherScale() : LauncherScale' in launcher_return
    and 'if desiredCachedScale = LauncherCachedScale\n            return' in launcher_return
    and launcher_return.index('if reuseCached && LauncherCachedScale > 0')
        < launcher_return.index('RepaintMenuButtons()')
    and 'ShowLauncherWindow(true)\n    preparedMs := A_TickCount - startedAt\n    CharacterPage.Hide()' in characters_close
    and 'LogLauncherEvent("UI | Character Book close " hiddenMs "ms | Parent " preparedMs' in characters_close
    and 'HideProfileEditor()\n    CloseMacroPage()' in characters_close,
)
expect(
    "Character Book raises the prepared launcher before hiding and restoring dormant book controls",
    'ShowLauncherWindow(true)' in characters_close
    and characters_close.index('ShowLauncherWindow(true)')
        < characters_close.index('CharacterPage.Hide()')
        < characters_close.index('HideProfileEditor()')
        < characters_close.index('CloseMacroPage()')
    and 'PrepareWindowDisplay(CharacterPage)' in characters_ui
    and 'RevealWindowDisplay(CharacterPage, true, !staged)' in characters_ui,
)
window_presenter = (ROOT / "src" / "ui" / "windows.ahk").read_text(encoding="utf-8-sig")
characters_open = section_between(
    characters_ui,
    "OpenCharacterPage(*)",
    "\nRefreshProfiles()",
)
expect(
    "Fresh and cached Character Book are staged until their controls paint",
    'SetPageCompositorCloak(CharacterPage, true)' in characters_open
    and characters_open.count('SetPageCompositorCloak(CharacterPage, true)') == 2
    and characters_open.count('RevealPaintedPage(CharacterPage)') == 2
    and characters_open.count('SetPageCompositorCloak(CharacterPage, false)') == 2
    and characters_open.index('PrepareWindowDisplay(CharacterPage)')
        < characters_open.rindex('CharacterPage.Show("Hide w" Round(960 * bookScale)')
        < characters_open.rindex('RevealWindowDisplay(CharacterPage, true, !staged)')
        < characters_open.rindex('RevealPaintedPage(CharacterPage)')
    and 'FinishButtonDisplay()\n                RevealPaintedPage(CharacterPage)' not in characters_open,
)
expect(
    "Settings first visible frame waits for composited parchment and native button paint",
    'staged := SetPageCompositorCloak(settings, true)' in settings_open
    and settings_open.index('staged := SetPageCompositorCloak(settings, true)')
        < settings_open.index('settings.Show("Hide w"')
        < settings_open.index('SetPageColorKey(settings, 0x010101)')
        < settings_open.index('        settings.Show()')
        < settings_open.index('RevealPaintedPage(settings)')
    and 'if staged\n            RevealPaintedPage(settings)\n        else\n            FinishButtonDisplay()' in settings_open
    and 'SetPageCompositorCloak(settings, false)' in settings_open,
)
expect(
    "Only page presentation uses DWM cloak and forces child paints before uncloak",
    'SetPageCompositorCloak(gui, cloak)' in window_presenter
    and 'DllCall("dwmapi\\DwmSetWindowAttribute"' in window_presenter
    and '"UInt", 13' in window_presenter
    and 'RevealPaintedPage(gui)' in window_presenter
    and 'SetPageColorKey(gui, colorRef)' in window_presenter
    and 'gui.Opt("+E0x80000")' in window_presenter
    and 'DllCall("SetLayeredWindowAttributes", "Ptr", gui.Hwnd,' in window_presenter
    and '"UInt", colorRef, "UChar", 255, "UInt", 1, "Int")' in window_presenter
    and 'RevealWindowDisplay(gui, book := false, paintButtons := true)' in window_presenter
    and 'if paintButtons\n        FinishButtonDisplay()' in window_presenter
    and 'DllCall("RedrawWindow", "Ptr", gui.Hwnd' in window_presenter
    and '"UInt", 0x0181' in window_presenter
    and '"UInt", 0x0185' not in window_presenter
    and 'DllCall("UpdateWindow", "Ptr", gui.Hwnd)' not in window_presenter
    and window_presenter.index('DllCall("RedrawWindow"')
        < window_presenter.index('SetPageCompositorCloak(gui, false)'),
)
entry_script = (ROOT / "tes3np.ahk").read_text(encoding="utf-8-sig")
expect(
    "Windows CI tests DWM staged window as a disposable visible GUI",
    'A_Args[1] = "--check-page-compositor"' in entry_script
    and 'DwmGetWindowAttribute' in entry_script
    and 'SetPageColorKey(testWindow, 0x010101)' in entry_script
    and 'GetLayeredWindowAttributes' in entry_script
    and 'NumGet(colorKey, 0, "UInt") != 0x010101' in entry_script
    and 'NumGet(colorFlags, 0, "UInt") != 1' in entry_script
    and "NumGet(before, 0, \"Int\") = 0" in entry_script
    and "NumGet(after, 0, \"Int\") != 0" in entry_script,
)
expect(
    "Windows CI includes real owned-window test for cached Character Book return",
    'A_Args[1] = "--check-cached-character-return"' in entry_script
    and 'probeBook := Gui("+Owner" LauncherGui.Hwnd' in entry_script
    and 'ShowLauncherWindow(true)\n    probeBook.Hide()' in entry_script
    and 'if !ButtonFaces.Has(probeHandle)' in entry_script,
)
macro_menu_ui = (ROOT / "src" / "ui" / "macros.ahk").read_text(encoding="utf-8-sig")
expect(
    "Parent-relative menus derive position from current owner HWND with monitor clamping",
    'PositionOwnedMenuAtParent(menu, owner)' in window_presenter
    and 'DllCall("GetWindowRect", "Ptr", ownerHwnd, "Ptr", ownerRect)' in window_presenter
    and 'DllCall("GetWindowRect", "Ptr", menu.Hwnd, "Ptr", menuRect)' in window_presenter
    and 'MonitorFromPoint(ox + ow // 2, oy + oh // 2)' in window_presenter
    and 'MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)' in window_presenter
    and 'DllCall("SetWindowPos", "Ptr", menu.Hwnd,' in window_presenter
    and '"UInt", 0x0015' in window_presenter,
)
expect(
    "Child controls and fonts scale with effective launcher percentage",
    'GetOwnedMenuScale()' in window_presenter
    and 'LauncherScale / 100' in window_presenter
    and 'ScaleOwnedMenuContent(gui, scale)' in window_presenter
    and 'control.Move(Round(cx * ratio), Round(cy * ratio),' in window_presenter
    and 'DllCall("gdi32\\CreateFontIndirectW"' in window_presenter
    and 'DllCall("SendMessageW", "Ptr", control.Hwnd, "UInt", 0x0030,' in window_presenter
    and 'gui.OwnedContentScale := scale' in window_presenter,
)
expect(
    "Launcher Settings follows moved owner and current scale without losing parchment",
    'return Max(0.45, Min(GetOwnedMenuScale(), fit))' in settings_layout
    and 'PositionOwnedMenuAtParent(settings, LauncherGui)' in settings_open
    and 'settings.Show("Hide w" V016S(512) " h" V016S(590))' in settings_open
    and 'SetPageColorKey(settings, 0x010101)' in settings_open
    and 'staged := SetPageCompositorCloak(settings, true)' in settings_open
    and 'PositionOwnedMenuAtParent(settings, LauncherGui)' in (
        ROOT / "src" / "ui" / "launcher-settings.ahk"
    ).read_text(encoding="utf-8-sig"),
)
expect(
    "Fresh and cached Character Book resize and position without rebuilding book state",
    characters_open.count('ApplyCharacterBookScale(bookScale)') == 2
    and characters_open.count('PositionOwnedMenuAtParent(CharacterPage, LauncherGui)') == 2
    and characters_open.count('CharacterPage.Show("Hide w" Round(960 * bookScale)') == 2
    and 'CharacterPage.BookBackground.Value := A_ScriptDir' in characters_ui
    and 'MoveStyledButton(control, x, y, width, height)' in characters_ui
    and 'x := BookS(x), y := BookS(y)' in characters_ui
    and 'CharacterDescription.Move(BookS(70), BookS(80), BookS(390), BookS(81))' in characters_ui
    and 'y := 164 + (index - 1) * 24' in characters_ui
    and 'GetCharacterBookScale()' in characters_ui
    and 'BookS(value)' in characters_ui
    and 'GetCharacterBookScale()' in macro_menu_ui
    and 'MacroScrollThumb.Move(BookS(888)' in macro_menu_ui
    and 'if oldUploadY != BookS(desiredUploadY)' in macro_menu_ui
    and 'BookS(890)' in characters_ui
    and 'ShowLauncherWindow(true)' in characters_close,
)
expect(
    "Client, dependency and Morrowind use scaled native changelog cards; remaining dialogs follow owners",
    'CreateGoldNativePrompt(ownerHwnd, "tes3np — Game Client Settings", 680, 458)' in settings_layout
    and 'ShowGoldNativePrompt(menu)' in settings_layout
    and 'CreateGoldNativePrompt(menu, "Optional Client Dependencies", 640, 350)' in settings_layout
    and 'ShowGoldNativePrompt(options)' in settings_layout
    and 'CreateGoldNativePrompt(LauncherGui, "TES3NP - Morrowind Installation Not Found", 680, 350)' in patcher
    and 'ShowGoldNativePrompt(prompt)' in patcher
    and 'ScaleOwnedMenuContent(dialog, dialogScale)' in characters_ui
    and 'PositionOwnedMenuAtParent(dialog, CharacterPage)' in characters_ui
    and 'ScaleOwnedMenuContent(chooser, chooserScale)' in macro_menu_ui
    and 'PositionOwnedMenuAtParent(chooser, MacroPage)' in macro_menu_ui,
)
native_card_ui = (ROOT / "src" / "app" / "update-check.ahk").read_text(encoding="utf-8-sig")
expect(
    "Borderless changelog native cards own their dimmers and release them on every exit",
    'CreateUpdateBackdrop(owner := 0)' in native_card_ui
    and 'CreateGoldNativePrompt(owner, title, width, height)' in native_card_ui
    and 'Gui("-Caption -Border -DPIScale +Owner" backdrop.Hwnd, title)' in native_card_ui
    and 'ScaleOwnedMenuContent(panel, scale)' in native_card_ui
    and 'ShowCenteredUpdateCard(panel, panel.NativePromptBackdrop,' in native_card_ui
    and 'CloseGoldNativePrompt(panel)' in native_card_ui
    and 'CloseGoldNativePrompt(menu)' in settings_layout
    and 'CloseGoldNativePrompt(options)' in settings_layout
    and settings_layout.count('options.Destroy()') == 0
    and patcher.count('CloseGoldNativePrompt(prompt)') == 2,
)
expect(
    "Discord sign-in uses a borderless gold card with in-window close and original toggle",
    'FormBorderStyle = FormBorderStyle.None,' in source
    and 'Padding = new Padding(2),' in source
    and 'closeButton.Click += (_, _) => DismissDiscordSignIn();' in source
    and 'closeButton.BringToFront();' in source
    and 'ToggleGameChatDiscordSignIn();' in source
    and 'FormBorderStyle = FormBorderStyle.FixedDialog,' not in source,
)
expect(
    "Windows CI verifies all manual menu scales, moved owner and monitor-edge clamping",
    'A_Args[1] = "--check-owned-menu-scaling"' in entry_script
    and 'for percent in [50, 60, 70, 80, 90, 100]' in entry_script
    and 'scale := GetOwnedMenuScale()' in entry_script
    and 'ScaleOwnedMenuContent(child, scale)' in entry_script
    and 'PositionOwnedMenuAtParent(child, LauncherGui)' in entry_script
    and 'if Abs(NumGet(movedRect, 0, "Int")' in entry_script
    and 'NumGet(edgeRect, 8, "Int") > mr' in entry_script,
)
expect(
    "One-time shortcut prompt never stacks optional GOTY or background Discord sign-in",
    "SetTimer(CheckFirstRunMorrowind" not in bootstrap
    and "bool discordSignInRequested;" in source
    and "if (discordSignInRequested) popup.Show();" in source
    and "discordSignInRequested = true;" in source
    and "if (!discordChannelReady) discordSignInRequested = true;" in source
    and "if (discordLoginVisible) RevealDiscordSignInWindow();" in source,
)

# Verify the approved text and image/onboarding behavior before compiling.
# These checks supplement (not replace) the live Windows acceptance tests.
expect(
    "Missing Morrowind onboarding gates the expansion toggle and resumes after selection",
    'CheckFirstRunMorrowind(true)' in patcher
    and 'if enable && morrowind = ""' in patcher
    and 'SetTimer(ToggleExpansionPack, -50)' in patcher
    and 'Morrowind Installation Not Found' in patcher
    and 'legally purchased copy of Morrowind' in patcher,
)
expect(
    "Discord sign-in emblem is published and Game Chat positioning remains separate",
    'PositionGameChatDiscordSignIn()' in source
    and 'pendingExpansionPrompt != 0' in source
    and 'Discord Integration!' in source
    and 'Sign In Required' in source
    and 'CopyToPublishDirectory="PreserveNewest"' in (
        ROOT / "chat-host" / "tes3np.ChatHost.csproj"
    ).read_text(encoding="utf-8-sig")
    and "assets\\DiscordInt.png" in (
        ROOT / "chat-host" / "tes3np.ChatHost.csproj"
    ).read_text(encoding="utf-8-sig"),
)

# New interactive behaviors must remain separated from the launcher's
# older authentication and installer contracts. Static evidence does not
# replace a real Windows sign-in or missing-game acceptance test.
expect(
    "Game Chat toggle can hide and reopen its own Discord login",
    'void ToggleGameChatDiscordSignIn()' in source
    and 'if (pendingExpansionPrompt == 0 &&' in source
    and source.count('ToggleGameChatDiscordSignIn();') == 2
    and 'void DismissDiscordSignIn()' in source
    and 'if (discordLoginVisible) RevealDiscordSignInWindow();' in source,
)
expect(
    "Discord login cancellation follows actual passkey row without overlapping password",
    "anchor.insertAdjacentElement('afterend', later);" in source
    and "form.appendChild(later);" not in source
    and "/sign in with a passkey/i.test(el.textContent || '')" in source
    and "parent.querySelector('input,button[type=submit]')" in source
    and "later.type = 'button';" in source
    and "chrome.webview.postMessage('tes3np-sign-in-later');" in source
    and 'args.TryGetWebMessageAsString() == "tes3np-sign-in-later"' in source
    and 'requestAnimationFrame(resetIfUntouched);' in source
    and "position:static !important;" in source
    and "min-height:44px !important" in source
    and 'RowCount = 3,' in source
    and 'shell.Controls.Add(later, 0, 3);' not in source,
)
expect(
    "Discord Integration heading has no line or underline",
    "border:0 !important; box-shadow:none !important;" in source
    and "text-decoration:none !important;" in source
    and "border-bottom:1px solid #70532c !important;" not in source,
)
expect(
    "Approved ZIP survives only while missing-Morrowind setup owns it",
    'DeferExpansionInstallForMissingMorrowind(package, autoApproved)' in (
        ROOT / "src" / "ui" / "expansion-upload.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'PendingExpansionPackage := package' in (
        ROOT / "src" / "ui" / "expansion-upload.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'SetTimer(InstallSelectedExpansionPackage.Bind(pendingPackage, pendingApproved), -50)' in patcher
    and 'MorrowindPromptGui.PendingExpansionPackage = package' in mismatch
    and 'if !deferred' in mismatch
    and 'if prompt.HasOwnProp("PendingExpansionApproved")' in patcher,
)
expect(
    "Client identity and clickable controls use TES3MP and Windows pointer",
    '"Original TES3MP runtime"' in settings_layout
    and '"Use Original TES3MP Client"' in settings_layout
    and 'Original TES3NP runtime' not in settings_layout
    and 'SetLauncherHandCursor()' in (
        ROOT / "src" / "ui" / "renderer.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'OnMessage(0x0020, HandleNativeClickableCursor)' in (
        ROOT / "src" / "ui" / "renderer.ahk"
    ).read_text(encoding="utf-8-sig"),
)

# The seven second-PC regression reports must have explicit source-side
# guards. These do not replace a Windows build or live interactive testing.
expect(
    "Missing GOTY prompts recur after Not Now and are guarded against duplicates",
    "global MorrowindPromptGui := 0" in patcher
    and "CheckFirstRunMorrowind(resumeExpansion := false, *)" in patcher
    and "EnsureMorrowindForGameLaunch()" in patcher
    and "MorrowindPromptGui := prompt" in patcher
    and 'IniWrite("1", DataFile, "Install", "MorrowindPromptDismissed")' not in section_between(
        patcher, "DismissFirstRunMorrowind(prompt, *)", "\n}"),
)
expect(
    "Saved characters and new adventures require GOTY data before spawning TES3MP",
    session.count("if !EnsureMorrowindForGameLaunch()") == 3
    and session.index("if !EnsureMorrowindForGameLaunch()")
        < session.index("StartProfileSession(Profiles[index], executable)")
    and "FindMorrowindFolder(PatchConfigurationPath())" in patcher,
)
expect(
    "Expansion Pack Enabled requires real nonempty ESP and current load-order entry",
    "if !ExpansionPackInstalled(morrowind, config)" in section_between(
        patcher, "ExpansionPackIsEnabled()", "\n}")
    and "FileGetSize(esp) > 0" in patcher,
)
expect(
    "Unfinished Discord recovery never suppresses a new game login",
    "ResetPendingExpansionPromptForNewLaunch()" in session
    and "SendLauncherChatCommand(11)" in mismatch
    and "case 11: CancelPendingExpansionPrompt(false); break;" in source,
)
login_progress = (ROOT / "src" / "ui" / "login-progress.ahk").read_text(encoding="utf-8-sig")
login_cleanup = section_between(login_progress, "UpdateGameLoginProgress(*)", "\n}")
session_stop = section_between(session, "StopClient(*)", "\nSetClientStatus(")
expect(
    "Aborted TES3MP login destroys its native overlay even if the visibility flag is stale",
    "DisposeGameLoginProgress()" in session_stop
    and "if !keepProgress" in session_stop
    and "LoginProgressMode = \"complete\" && A_TickCount < LoginProgressCloseAt" in session_stop
    and "if IsObject(LoginProgressGui)" in section_between(
        login_progress, "\nHideGameLoginProgress()\n{", "\n}")
    and 'DllCall("IsWindowVisible", "Ptr", hwnd)' in login_progress
    and 'DllCall("ShowWindow", "Ptr", hwnd, "Int", 0)' in login_progress
    and "if abandoned" in login_cleanup
    and "Client.PID && !ProcessExist(Client.PID)" in login_cleanup
    and "LoginProgressPid && !ProcessExist(LoginProgressPid)" in login_cleanup
    and "SetTimer(UpdateGameLoginProgress, 0)" in login_cleanup
    and "DisposeGameLoginProgress()" in login_cleanup,
)
display_settings = (ROOT / "src" / "ui" / "launcher-settings.ahk").read_text(encoding="utf-8-sig")
settings_ui = (ROOT / "src" / "ui" / "v016-refinements.ahk").read_text(encoding="utf-8-sig")
front_layout = (ROOT / "src" / "ui" / "front-page.ahk").read_text(encoding="utf-8-sig")
font_update = section_between(
    display_settings, "\nApplyAccessibilityTextSize()\n{", "\nApplyEnhancedReadability()\n{"
)
expect(
    "Display text changes never restore unscaled themed-button geometry",
    "size := AccessibilityFontSize(10)" in font_update
    and "scale := LauncherScale / 100" in font_update
    and 'Max(7, Round(size * scale))' in font_update
    and "face.Control.Move(" not in font_update,
)
expect(
    "Declined display previews restore saved state and visible settings controls",
    "ApplyLauncherScaleToWindow(true)" in display_settings
    and "ApplyAccessibilityTextSize()" in display_settings
    and "ApplyEnhancedReadability()" in display_settings
    and 'scaleList.Choose(oldMode = "Auto" ? 1 : ScaleChoiceIndex(oldScale) + 1)' in display_settings
    and 'textList.Choose(oldText = "Large" ? 2' in display_settings
    and "V016ReadabilityState := readability.Value" in display_settings
    and "V016FollowWindowsState := followWindows.Value" in display_settings
    and "UpdateV016ReadabilityLabel(settings.ReadabilityControl, V016ReadabilityState)" in display_settings
    and "CloseLauncherSettingsV016(settings)" in display_settings
    and "LauncherCachedScale := LauncherScale" in display_settings,
)
expect(
    "Settings match launcher scale, fit owner monitor and keep accessibility controls",
    "V016SettingsScale := GetV016SettingsFitScale()" in settings_ui
    and "fit := Min(1.0, (right - left - 24) / (512 * dpi)," in settings_ui
    and "return Max(0.45, Min(GetOwnedMenuScale(), fit))" in settings_ui
    and "return Max(7, Round(value * V016SettingsScale))" in settings_ui
    and "settings.ReadabilityControl := readability" in settings_ui
    and "reduceMotionBox := {Value: ReduceMotion ? 1 : 0}" in settings_ui,
)
expect(
    "Manual launcher scale scrolling accounts for current UI scale",
    front_layout.count("((A_ScreenDPI / 96) * LauncherScale / 100)") >= 2
    and "scale := (A_ScreenDPI / 96) * LauncherScale / 100" in front_layout,
)
expect(
    "Game Chat toggle caption and arrow shrink with launcher tab",
    "fontHeight := -Max(9, Round(21 * paintScale))" in bootstrap
    and "arrowHalf := Max(4, Round(9 * paintScale))" in bootstrap
    and "arrowHeight := Max(4, Round(10 * paintScale))" in bootstrap,
)
chat_startup = (ROOT / "src" / "ui" / "embedded-chat.ahk").read_text(encoding="utf-8-sig")
ui_loading = (ROOT / "src" / "ui" / "loading.ahk").read_text(encoding="utf-8-sig")
host_freshness = section_between(chat_startup, "EnsureEmbeddedChatHostCurrent(host)", "\nWebView2RuntimeAvailable()")
expect(
    "Opening the source launcher never compiles ChatHost on the UI thread",
    "EnsureEmbeddedChatHostCurrent(host)" in chat_startup
    and "RunWait(" not in host_freshness
    and "dotnet publish" not in host_freshness.replace("RunWait(dotnet publish)", "")
    and "startup will not block on compilation" in host_freshness,
)
expect(
    "Loading transitions avoid compositor waits and restore prior critical state",
    "DwmFlush" not in ui_loading.replace("DwmFlush synchronously", "")
    and "previousCritical := A_IsCritical" in ui_loading
    and "finally Critical(previousCritical)" in ui_loading
    and "finally EndInterfaceUpdate()" in display_settings,
)
expect(
    "Launcher initial sizing is hidden and subsequent displays reuse cached layout",
    'LauncherGui.Show("Hide w960 h716")' in bootstrap
    and "if LauncherCachedScale > 0 && DllCall" in bootstrap
    and "LauncherCachedScale := LauncherScale" in bootstrap,
)
expect(
    "Themed click recovery verifies the child under the actual pointer",
    "MouseGetPos(, , &pointerWindow, &pointerControl, 2)" in controls
    and "pointerWindow = ButtonFaces[pointerControl].Window" in controls,
)

update_startup = (ROOT / "src" / "app" / "update-check.ahk").read_text(encoding="utf-8-sig")
automatic_update = section_between(
    update_startup, "CheckForUpdateAvailability(*)", "\nHasSeenUpdateAutoPreview(version)"
)
expect(
    "Automatic update check must never synchronously block the launcher UI",
    'request.Open("GET", UpdateManifestUrl, true)' in automatic_update
    and "request.WaitForResponse(0)" in automatic_update
    and "SetTimer(PollStartupUpdateAvailability, 100)" in automatic_update
    and "UpdateStartupRequest := request" in automatic_update
    and "request.Abort()" in automatic_update
    and "DownloadUpdateText(UpdateManifestUrl)" not in automatic_update
    and "ParseAndValidateUpdateManifest(request.ResponseText)" in automatic_update
    and 'request.SetTimeouts(5000, 5000, 10000, 10000)' in automatic_update
    and 'SetTimer(CheckForUpdateAvailability, -250)' in bootstrap,
)
expect(
    "WinForms first show stays compositor-cloaked until initial dock and saved visibility are ready",
    'const int DWMWA_CLOAK = 13;' in source
    and 'protected override void OnHandleCreated(EventArgs e)' in source
    and 'if (startupPresentationPending)\n                SetStartupWindowCloak(true);' in source
    and 'DwmSetWindowAttribute(Handle, DWMWA_CLOAK, ref value, sizeof(int))' in source
    and 'SetChatOpen(chatDisplayMode == "Always Shown");\n            // The owner, layout and saved visibility are now authoritative.' in source
    and 'startupPresentationPending = false;\n                SetStartupWindowCloak(false);' in source
    and source.index('SetStartupWindowCloak(false);') > source.index('SetChatOpen(chatDisplayMode == "Always Shown");'),
)
expect(
    "Chat Host docking preserves positioning while recording blocking phases",
    'Log("STARTUP | Dock begin");' in source
    and 'Log("STARTUP | Setting native owner");' in source
    and 'Log("STARTUP | Owner compositor refresh begin");' in source
    and 'PositionChatWindows();' in source
    and 'WatchLauncherMovement();' in source,
)

if errors:
    print("Chat Host architectural contract violations:")
    for error in errors:
        print(" - " + error)
    sys.exit(1)

print("Chat Host contracts verified: Roaming AppData, verified offline Happy "
      "Hour cache, authenticated live fetching, first-login chat, native "
      "movement and atomic history writes.")
