"""Guard TES3NP's Chat Host against recurring persistence/auth regressions.

These checks enforce cross-process architectural contracts, not C# syntax.
The Windows CI job also builds the Chat Host to catch compiler errors.
"""
from pathlib import Path
import re
import sys

from game_chat_source import read_game_chat_sources

ROOT = Path(__file__).resolve().parents[1]
chat_root = ROOT / "game-chat"
chat_web = chat_root / "web"
source = read_game_chat_sources(ROOT)
feed_extractor = (chat_web / "extract-feed.js").read_text(encoding="utf-8-sig")
discord_sign_in = (chat_web / "discord-sign-in.js").read_text(encoding="utf-8-sig")
expansion_browser = (chat_web / "expansion-downloads.js").read_text(encoding="utf-8-sig")
sign_in_card = (chat_root / "DiscordSignInCard.cs").read_text(encoding="utf-8-sig")
chat_renderer = (chat_root / "GameChatWindow.Renderer.cs").read_text(encoding="utf-8-sig")
chat_window = (chat_root / "GameChatWindow.cs").read_text(encoding="utf-8-sig")
server_updates = (chat_root / "GameChatWindow.ServerUpdates.cs").read_text(encoding="utf-8-sig")
updates_panel = (chat_root / "GameChatWindow.ServerUpdatesPanel.cs").read_text(encoding="utf-8-sig")
chat_history = (chat_root / "GameChatWindow.History.cs").read_text(encoding="utf-8-sig")
chat_expansion = (chat_root / "GameChatWindow.Expansion.cs").read_text(encoding="utf-8-sig")
happy_hour = (chat_root / "GameChatWindow.HappyHour.cs").read_text(encoding="utf-8-sig")
happy_hour_banner = (chat_root / "GameChatWindow.HappyHourBanner.cs").read_text(encoding="utf-8-sig")
message_page = (chat_web / "message-feed.html").read_text(encoding="utf-8-sig")
app_state = (ROOT / "src" / "state.ahk").read_text(encoding="utf-8-sig")
bootstrap = (ROOT / "src" / "app" / "bootstrap.ahk").read_text(encoding="utf-8-sig")
controls = (ROOT / "src" / "ui" / "controls.ahk").read_text(encoding="utf-8-sig")
jiub_ui = (ROOT / "src" / "ui" / "happy-hour.ahk").read_text(encoding="utf-8-sig")
settings_ui = (ROOT / "src" / "ui" / "v016-refinements.ahk").read_text(encoding="utf-8-sig")
patcher = (ROOT / "src" / "ui" / "patcher.ahk").read_text(encoding="utf-8-sig")
session = (ROOT / "src" / "game" / "session.ahk").read_text(encoding="utf-8-sig")
resource_generator = (ROOT / "scripts" / "generate-bundled-resources.py").read_text(encoding="utf-8-sig")
expansion_upload = (ROOT / "src" / "ui" / "expansion-upload.ahk").read_text(encoding="utf-8-sig")
loading_ui = (ROOT / "src" / "ui" / "loading.ahk").read_text(encoding="utf-8-sig")
native_renderer = (ROOT / "src" / "ui" / "renderer.ahk").read_text(encoding="utf-8-sig")
windows_build = (ROOT / "scripts" / "build-windows.ps1").read_text(encoding="utf-8-sig")
diagnostic_fixture = (ROOT / "scripts" / "test-expansion-diagnostics.ahk").read_text(encoding="utf-8-sig")
front_layout = (ROOT / "src" / "ui" / "front-page.ahk").read_text(encoding="utf-8-sig")
embedded_chat = (ROOT / "src" / "ui" / "embedded-chat.ahk").read_text(encoding="utf-8-sig")
entry_script = (ROOT / "tes3np.ahk").read_text(encoding="utf-8-sig")
launcher_smoke_tests = (ROOT / "scripts" / "launcher-smoke-tests.ahk").read_text(encoding="utf-8-sig")
display_settings = (ROOT / "src" / "ui" / "launcher-settings.ahk").read_text(encoding="utf-8-sig")
launcher_layout = (ROOT / "src" / "ui" / "launcher-layout.ahk").read_text(encoding="utf-8-sig")
update_check = (ROOT / "src" / "app" / "update-check.ahk").read_text(encoding="utf-8-sig")
chat_project = (chat_root / "tes3np.GameChat.csproj").read_text(encoding="utf-8-sig")
errors = []


def expect(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


def section_between(text: str, start: str, end: str) -> str:
    """Return the guarded function section, or empty text if it was removed.

    Missing/renamed source must cause an explicit contract failure rather
    than crashing the entire build preflight.
    """
    start_at = text.find(start)
    if start_at == -1:
        return ""
    end_at = text.find(end, start_at + len(start))
    if end_at == -1:
        return ""
    return text[start_at:end_at]


def in_order(text: str, *fragments: str) -> bool:
    """Check first occurrences and fail cleanly if any fragment is absent."""
    previous = -1
    for fragment in fragments:
        position = text.find(fragment)
        if position <= previous:
            return False
        previous = position
    return True


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
    "Game Updates shares its gold scrollbar with the native fallback",
    'scrollTotal = Math.Max(1, message.GetProperty("height").GetInt32());' in updates_panel
    and 'ScrollBy("to", (int)Math.Round(metrics.Maximum * fraction));' in updates_panel
    and 'ReadFallbackScroll();' in updates_panel and 'ShowScrollBar' not in source,
)
expect(
    "Obsolete browser message-feed variable must remain removed",
    "lastState" not in source,
)
expect(
    "Live message feed scrolling remains wired to custom scrollbar",
    "void ScrollChatToThumb(int y, int dragOffset)" in source
    and "readonly BufferedScrollbar goldScrollbar = new()" in source
    and "new ResizeObserver(metrics).observe(feed);" in message_page
    and "feed.addEventListener('scroll',metrics);" in message_page,
)
expect(
    "Game Chat can reopen from older-message anchors and keeps scrolling activity from expiring the panel",
    'bool onChannel = IsGameChatRoute(url);' in source
    and 'if (IsGameChatRoute(before))' in source
    and 'path.StartsWith(Channel + "/", StringComparison.OrdinalIgnoreCase)' in source
    and 'ulong.TryParse(path.AsSpan(Channel.Length + 1), System.Globalization.NumberStyles.None,' in source
    and 'if (!discordChannelReady && !connectingChat && !nativeMode)' in source
    and "noteScroll(e.deltaY>0)" in message_page
    and "{type:'interaction',stopHistory}" in message_page
    and 'if (chatOpen) lastChatActivity = DateTime.Now;' in source
    and '!goldScrollbar.Capture &&' in source
    and 'goldScrollbar.MouseCaptureChanged +=' in source
    and 'if (!chatOpen || !initialBackfillComplete || (!userScrolledChat && !forceTop)) return;' in source
    and in_order(section_between(source, 'void SetChatOpen(bool show)', 'static double OwnerLayoutScale'),
                 'goldScrollbar.Capture = false;', 'historyCatchupActive = false;',
                 'else if (!chatOpen) lastChatActivity = DateTime.Now;', 'chatOpen = show;',
                 'else ShowWindow(Handle, 0);'),
)
expect(
    "History and Expansion callbacks ignore stale navigation or a replaced download request",
    in_order(chat_history, "ulong navigationId = discordNavigationId;",
             "await web.CoreWebView2.ExecuteScriptAsync(script).WaitAsync(TimeSpan.FromSeconds(5));",
             "navigationId != discordNavigationId) return;", 'if (result.Contains("no-message-list")')
    and in_order(chat_expansion, "ulong requestGeneration = expansionPromptGeneration;",
                 "await core.ExecuteScriptAsync(", "if (!IsCurrentExpansionPrompt(requestGeneration, navigationId)) return;",
                 "CompletePendingExpansionPrompt();")
    and "requestGeneration == expansionPromptGeneration" in chat_expansion
    and "navigationId == discordNavigationId && !discordNavigationInProgress" in chat_expansion,
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
    'bool isHappyHour = IsHappyHourAuthor(sourceAuthor) &&' in source
    and 'if (IsHappyHourAuthor(entry.Value.User) &&' in happy_hour
    and 'user.Contains("Yagrum", StringComparison.OrdinalIgnoreCase)' in happy_hour,
)
expect(
    "A newer verified image must not be superseded by older text",
    "foreach (ulong imageId in verifiedHappyHourImageIds)" in source
    and "foreach (var entry in archivedChat.Reverse()) {\n            if (entry.Key <= latest) break;" in source,
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
    happy_hour_banner, "void RefreshHappyHourBanner()", "void ShowHappyHourBannerForMessage("
)
happy_hour_clock = section_between(
    happy_hour_banner, "void RefreshHappyHourBannerClock()", "void RefreshHappyHourBanner()"
)
expect(
    "Happy Hour countdown updates during any open launcher menu without stealing focus",
    in_order(happy_hour_refresh, "RefreshHappyHourBannerClock();", "if (OtherLauncherDialogOpen())")
    and "RefreshHappyHourBannerClock();" in section_between(
        happy_hour_refresh, "banner.Show();", "Banner window created",
    )
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
    and "void RefreshHappyHourBanner()\n    {\n        if (happyHourEndsAt <= DateTimeOffset.UtcNow || !IsWindow(owner))" in source
    and "void DetectLatestHappyHour()\n    {\n        if (closingChat || IsDisposed) return;" in source,
)
expect(
    "Only authenticated Discord can fetch or page new messages",
    "if (!discordChannelReady || initialBackfillComplete" in source
    and "discordLoginVisible || !discordChannelReady) return;" in source
    and "void SuspendHappyHourUntilDiscordReturns(string reason)" in source,
)
expect(
    "Offline startup consults real archived messages, not login or marker state",
    "// Load it immediately, whether this browser is signed in or not.\n        DetectLatestHappyHour();" in source
    and "ulong latest = LatestArchivedHappyHourId();" in source
    and "LegacyHappyHourSeenFile" not in source,
)
expect(
    "Logging out must preserve a valid banner and its expiry timer",
    "Verified Happy Hour banner remains independent." in source
    and "Keep the existing genuine activation, its absolute expiry," in source
    and "if (happyHourEndsAt <= DateTimeOffset.UtcNow) {" in source,
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
    "Happy Hour discovery and display reject expired announcements",
    "ShowExpiredHappyHourForAlphaTest" not in source
    and "DiscordTimestamp(latest).AddHours(1) > DateTimeOffset.UtcNow" in source
    and "DiscordTimestamp(candidate).AddHours(1) > DateTimeOffset.UtcNow" in source
    and "ends <= DateTimeOffset.UtcNow) return;" in source
    and "HappyHourBannerTime(happyHourEndsAt)" in source
    and "Math.Max(0, Math.Ceiling((end - DateTimeOffset.UtcNow).TotalSeconds))" in source,
)
expect(
    "Recent cached Happy Hour does not suppress searches for newer activations",
    'checking for a newer Discord activation' in source
    and 'initialBackfillComplete = false;\n            initialBackfillStarted = DateTime.MinValue;\n            initialBackfillAttempts = 0;' in source
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
    "bool pastActiveWindow = oldestLoaded <= DateTimeOffset.UtcNow.AddHours(-1);" in source
    and "initialBackfillAttempts >= 500" in source
    and "TimeSpan.FromMinutes(6)" in source,
)

expect(
    "Archive must be written with replace-on-complete semantics",
    "WriteChatArchiveAtomically(indexPath," in source
    and "WriteChatArchiveAtomically(textPath," in source
    and "File.Move(temporary, path, true);" in source,
)
expect(
    "Archive writes use a single background snapshot and retry independently of the feed",
    "Task<string?>? chatArchiveSave;" in source
    and "chatLogLoaded = indexArchiveRead && textArchiveRead;" in source
    and "if (!pending.IsCompleted) return;" in source
    and "chatArchiveDirty = true;\n                nextChatArchiveSave = DateTimeOffset.UtcNow.AddSeconds(5);" in source
    and "historyWatch.Tick += MaintainHistory;" in source
    and "if (chatArchiveDirty && !chatLogLoaded) EnsureChatLogLoaded();\n        FlushPendingChatArchive();" in source
    and in_order(source, "Task<string?> QueueChatArchiveSave(", "}).ToArray();",
                 "return Task.Run(async () =>", "SaveChatArchive(records, indexPath, textPath);")
    and "finally { refreshingNativeFeed = false; }" in source,
)
expect(
    "The final archive write follows an active write and drains after the UI loop",
    "chatArchiveSave = QueueChatArchiveSave(chatArchiveSave);" in source
    and "await previous.ConfigureAwait(false)" in source
    and "QueueFinalChatArchiveSave();" in source
    and in_order(source, "Application.Run(chat);", "chat.WaitForChatArchiveOnExit();")
    and "pending.Wait(TimeSpan.FromSeconds(3))" in source
    and in_order(embedded_chat, "SendLauncherChatCommand(14)", "ProcessWaitClose(pid, 5)", "ProcessClose(pid)"),
)
expect(
    "Fresh authentication starts the native renderer with a bounded navigation wait",
    "await InitMessageBrowser(env);" in source
    and "rendererNavigation.Task.WaitAsync(TimeSpan.FromSeconds(8))" in source
    and "messageBrowserReady = e.IsSuccess;" in source
    and "e.NavigationId != messagePageNavigationId" in source,
)
discord_auth = section_between(source, "async Task CheckDiscordAuthentication()", "static readonly Lazy<string> DiscordSignInScript")
discord_recovery = section_between(source, "void RetryStalledDiscordChannel(", "async Task CheckDiscordAuthentication()")
expect(
    "First login waits for actual message rows and only retries a stalled channel once",
    "channelRetryAt = DateTime.UtcNow.AddSeconds(8);" in source
    and "web.CoreWebView2.DOMContentLoaded +=" in source
    and ".some(row => /^chat-messages-[0-9]+-[0-9]+$/.test(row.id))" in discord_auth
    and in_order(discord_recovery, "DateTime.UtcNow < retryAt", "channelRetryAt = null;",
                 "core.Stop();", "core.Navigate(Channel);")
    and "bool keepChatVisible = discordSignInRequested &&" in source
    and 'path is "/quest-home" or "/quests" or "/shop" or "/store"' in source
    and in_order(
        discord_auth,
        "IsDiscordAppRoute(url)",
        "RestoreGameChatAfterSignIn();",
        "core.Navigate(Channel);",
        'if (!onChannel || state != "\\"chat\\"")',
        "discordChannelReady = true;",
    )
    and in_order(
        section_between(source, "void RestoreGameChatAfterSignIn()", "async Task UpdateViewMode()"),
        "discordLoginVisible = false;",
        "popup.Park(owner);",
        "ShowConnectingChat();",
    ),
)
expect(
    "The authenticated Discord browser keeps its original window after sign-in",
    "protected override bool ShowWithoutActivation => parked;" in sign_in_card
    and "desktop.Right + 32" in sign_in_card
    and "if (popup.UpdateParkedLayout()) return;" in source
    and "popup.PrepareSignIn();" in source
    and "if (web.Parent != chatViewport) return;" in source
    and "if (web.Parent == chatViewport) web.Visible = false;" in chat_renderer
    and "web.Parent = chatViewport;" not in source,
)

discord_sign_in_handler = section_between(
    source, "void HandleDiscordSignInMessage(", "void RetryStalledDiscordChannel("
)
expect(
    "Discord credential submission updates the launcher using profile-checking state",
    'AddScriptToExecuteOnDocumentCreatedAsync(DiscordSignInProgressScript.Value)' in source
    and in_order(discord_sign_in_handler, 'case "tes3np-sign-in-started":',
                 "SetDiscordAccountStatus(DiscordAccountStatus.Checking);", "PublishDiscordAccount();",
                 'case "tes3np-sign-in-rejected":', "SetDiscordAccountStatus(DiscordAccountStatus.SignedOut);")
    and 'status = 0 ? "Loading Profile..." : "Log In"' in embedded_chat
    and 'status != 2 && (nameSize || imageSize)' in embedded_chat,
)
expect(
    "Server Updates uses the launcher Discord session and clears on sign-out",
    "discordAccountStatus == DiscordAccountStatus.SignedIn" in server_updates
    and "EnsureCoreWebView2Async(environment)" in server_updates
    and "510245417657827363" in server_updates
    and "source != serverUpdatesWindow" in server_updates
    and "GetParent(target) != owner" in source
    and "CloseServerUpdatesPanel();" in server_updates
    and "host.PaintGoldScrollbar(e.Graphics, height, PanelScale, top, thumb);" in source
    and "host.PaintGameChatFrame(e.Graphics," in updates_panel
    and "recent.TakeLast(8)" in server_updates
    and 'GameChatWeb.Page("server-updates.html")' in updates_panel
    and in_order(section_between(source, "async Task SignOutDiscord()", "\n}"),
                 "PublishDiscordAccount();", "ResetServerUpdates();", "ClearBrowsingDataAsync("),
)
expect(
    "Game Updates keeps its header visible and opens the feed for a newer post or a signed-in request",
    "toggle.Click += (_, _) => host.ToggleServerUpdatesBody();" in updates_panel
    and "ServerUpdatesBodyExpanded => ServerUpdatesAuthenticated &&" in server_updates
    and "(serverUpdatesManuallyOpened || serverUpdatesDisplay.Open)" in server_updates
    and "serverUpdatesDisplay = ReadServerUpdatesDisplay();" in server_updates
    and in_order(section_between(server_updates, "void ToggleServerUpdatesBody()", "async Task RefreshServerUpdates()"),
                 "if (!ServerUpdatesAuthenticated)", "RequestDiscordSignIn(fromHeader: false);", "return;",
                 "serverUpdatesManuallyOpened = !hide;",
                 "SaveServerUpdatesDisplay(false, Math.Max(serverUpdatesDisplay.LastReadyId, latestServerUpdateId));",
                 "PositionServerUpdatesPanel();")
    and "WriteChatArchiveAtomically(ServerUpdatesDismissalPath, open ? \"open:\" + id : id);" in server_updates
    and in_order(section_between(server_updates, "async Task RefreshServerUpdates()", "static void ConfigureServerUpdatesBrowser("),
                 "latestServerUpdateId = newestId;", "if (newestId > serverUpdatesDisplay.LastReadyId)",
                 "SaveServerUpdatesDisplay(true, newestId);", "UpdateServerUpdatesDocument(text, revealNewest);",
                 "if (revealNewest) PositionServerUpdatesPanel();")
    and in_order(section_between(server_updates, "void ResetServerUpdates()", "\n}"),
                 "serverUpdatesManuallyOpened = false;", "PositionServerUpdatesPanel();", "serverUpdatesPanel?.ResetDocument();")
    and in_order(chat_window, "PositionServerUpdatesPanel();", "await CheckDiscordAuthentication();")
    and "PostMessage(owner, 0x833B, IntPtr.Zero, Handle)" in updates_panel
    and "OnMessage(0x833B, ReceiveLauncherServerUpdatesHostMessage)" in embedded_chat
    and in_order(section_between(updates_panel, "internal void SetLauncherBounds(", "protected override void OnResize("),
                 "viewport.Hide();", "scrollbar.Hide();", "FrameHeaderBottom(HeaderScale) + FrameFooterHeight",
                 "Bounds = bounds;", "viewport.Show();", "scrollbar.Show();"),
)
expect(
    "Game Updates paints with the launcher's first frame independently of Discord sign-in",
    "ShowLauncherWithGameUpdates()" in bootstrap
    and in_order(section_between(embedded_chat, "ShowLauncherWithGameUpdates()", "StartEmbeddedInGameChat()\n{"),
                 "SetPageCompositorCloak(LauncherGui, true)", "StartEmbeddedInGameChat()",
                 "while !LauncherUpdatesFirstPaintReady", "A_TickCount - start < 800",
                 "finally RevealPaintedPage(LauncherGui)")
    and in_order(chat_window, "Shown += (_, _) => PositionServerUpdatesPanel();", "Shown += StartDiscordAsync;")
    and in_order(section_between(updates_panel, "var panel = serverUpdatesPanel = new LatestUpdatesPanel(this);", "catch (Exception ex)"),
                 "panel.SetDocument(", "PositionServerUpdatesPanel();")
    and in_order(section_between(updates_panel, "void PositionServerUpdatesPanel()", "void UpdateServerUpdatesDocument("),
                 "panel.SetLauncherBounds(bounds, ServerUpdatesShellExpanded);", "panel.Show();", "panel.Update();",
                 "PostMessage(owner, 0x833B, new IntPtr(1), Handle);")
    and "(discordAccountStatus == DiscordAccountStatus.Checking && serverUpdatesDisplay.Open)" in server_updates,
)
expect(
    "Game Updates tracks its launcher anchor as an owned top-level window",
    'LauncherGui.OnEvent("Size", LauncherServerUpdatesResized)' in bootstrap
    and "SetTimer(RepaintLauncherServerUpdates, -50)" in embedded_chat
    and "GetWindowRect(serverUpdatesAnchor, out var rect)" in updates_panel
    and in_order(section_between(updates_panel, "protected override void CreateHandle()", "protected override void WndProc("),
                 "base.CreateHandle();", "SetNativeWindowOwner(Handle, host.owner);")
    and in_order(section_between(updates_panel, "void PositionServerUpdatesPanel()", "void UpdateServerUpdatesDocument("),
                 "_ = panel.Handle;", "panel.Show();", "KeepServerUpdatesInLauncherStack();")
    and "if (IsIconic(owner)) return;" in updates_panel
    and "GetForegroundWindow()" not in updates_panel
    and "SetParent(" not in updates_panel
    and "landing = measureLatest(posts.at(-1));" in (chat_web / "server-updates.html").read_text(encoding="utf-8")
    and "dateBand" not in updates_panel,
)
updates_stack = section_between(updates_panel, "void KeepServerUpdatesInLauncherStack()", "void UpdateServerUpdatesDocument(")
expect(
    "Game Updates lowers itself below windows between it and the launcher without activation",
    "SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND" in source
    and "UnhookWinEvent(launcherForegroundHook);" in chat_window
    and "SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER" in updates_stack
    and in_order(updates_stack, "GetWindow(window, GW_OWNER)", "SetNativeWindowOwner(window, owner);",
                 "GetWindow(owner, GW_HWNDPREV)", "GetWindow(window, GW_HWNDNEXT)",
                 "if (below != insertAfter) continue;", "SetWindowPos(window, insertAfter,")
    and "SetForegroundWindow(" not in updates_panel,
)
expect(
    "Game Updates sends only post-scoped reaction actions to the signed-in Discord source",
    'if (!bodyExpanded || !feedVisible || type is not ("toggle" or "picker")) return;' in updates_panel
    and 'args.Source != ServerUpdatesPageUri' in updates_panel
    and 'post.Reactions?.Any(reaction => reaction.Key == request.Key)' in source
    and 'await host.ShowServerUpdatePicker(this, request.Id)' in updates_panel
    and '!IsServerUpdatesRoute(e.Uri) && !IsServerUpdatesMessageRoute(e.Uri)' in server_updates,
)
expect(
    "Game Updates opens Discord's own picker in a separate process with the same sign-in profile",
    'GameChatWindow.TryRunDiscordReactionPicker(args)' in source
    and 'Process.Start(start)' in source
    and 'RedirectStandardInput = true' in source
    and 'picker.StandardInput.Close();' in source
    and 'await picker.WaitForExitAsync();' in source
    and 'StopServerUpdatePicker();' in server_updates
    and 'parameters.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;' in updates_panel
    and 'Application.Run(picker);' in source
    and 'CoreWebView2Environment.CreateAsync(null, DiscordUserDataFolder, options)' in source
    and 'discordUsesCacheOptions ? "cache" : "default"' in source,
)
expect(
    "Discord renders and manages the reaction picker for the selected update",
    'core.Navigate(target);' in source
    and 'RunServerUpdateAction(core, new("picker-target", postId))' in source
    and 'RunServerUpdateAction(core, new("picker", postId))' in source
    and not (chat_root / 'web/discord-emoji-shortcodes.json').exists()
    and not (chat_root / 'web/emojibase-license.txt').exists()
    and 'BundledEmojiCatalog' not in source,
)
expect(
    "The Discord reaction window reveals only the measured native picker and restores it after focus changes",
    'GameChatWeb.Page("discord-reaction-picker.js")' in source
    and 'core.AddScriptToExecuteOnDocumentCreatedAsync(PickerPresentationScript.Value)' in source
    and in_order(section_between(source, 'bool PresentPicker(PickerViewport view)', 'async void WatchPicker('),
                 'ReactionPickerCrop(view, browserSize)', 'SetWindowRgn(browser.Handle, region, true)',
                 'browser.Location = new Point(-crop.Left, -crop.Top);', 'status.Hide();')
    and 'Deactivate += (_, _) => { if (shownPicker || openingPicker) lostFocus = true; };' in source
    and 'window.tes3npPrepareReactionPicker?.() ?? false' in source
    and 'PickerOpenResult.NeedsFocus' in source,
)
expect(
    "Game Updates keeps native posts visible until the embedded reaction view renders",
    'core.Navigate(ServerUpdatesPageUri);' in updates_panel
    and 'e.Cancel = e.Uri != ServerUpdatesPageUri' in updates_panel
    and 'environment.CreateWebResourceResponse(new MemoryStream(html, false)' in updates_panel
    and 'type == "rendered" && feedLoad?.TrySetResult(true) == true' in updates_panel
    and 'fallbackFeed.Rtf = FormatUpdatesFallback(host.displayedServerUpdates, status);' in source,
)
expect(
    "Game Updates preserves posts during reconnects and reads back reaction removals",
    'if (displayedServerUpdates.Length == 0)\n            UpdateServerUpdatesDocument' in server_updates
    and 'if (activeServerUpdatesRead is { } activeRead) await activeRead.Task;' in source
    and 'await ReadBackServerUpdateReaction(source, core, request);' in source
    and 'post with { Reactions = reactions }' in source,
)
quest_body = re.search(r'AddInfoCard\(\d+, (\d+), \d+, \d+, "Quest", "[^"]*", (\d+)\)', front_layout)
updates_bounds = re.search(r'LauncherUpdatesSlot := LauncherGui.Add\("Text",\s*"x\d+ y(\d+)', embedded_chat)
expect(
    "Launcher info cards keep their original paint style and the Quest copy clears Game Updates",
    'control := LauncherGui.Add("Custom", "ClassStatic x" x' in front_layout
    and "BodyBottom: bodyBottom" in front_layout
    and "Round(face.BodyBottom * scale)" in native_renderer
    and quest_body is not None and updates_bounds is not None
    and all((int(quest_body[1]) * percent + 50) // 100 + (int(quest_body[2]) * percent + 50) // 100 + 1
            < (int(updates_bounds[1]) * percent + 50) // 100 for percent in range(50, 101)),
)

show_sign_in = section_between(source, "void ShowDiscordSignIn()", "void RestoreGameChatAfterSignIn()")
sign_in_layout = section_between(source, "static Size GetDiscordSignInSize(", "void DismissDiscordSignIn()")
chat_layout = section_between(source, "void PositionChatWindows()", "void DockToLauncher()")
dock_bounds = section_between(source, "static Rectangle DockBounds(", "void PositionChatWindows()")
expect(
    "Discord login uses an owned dedicated window and keeps Game Chat at its normal proportions",
    "DiscordSignInCard? discordSignInWindow;" in source
    and "void RevealDiscordSignInWindow()" in source
    and in_order(show_sign_in, "web.Parent = popup.BrowserPanel;", "PositionChatWindows();",
                 "SetNativeWindowOwner(popup.Handle, owner);", "popup.Show();")
    and "chatViewport.Controls.Add(web);" in source
    and "FitPopupScale(launcherScale, chatWidth, dockHeight, work)" in chat_layout
    and "discordLoginVisible ? Math.Max(chatHeight, 780)" not in source
    and "web.Parent = this;" not in source,
)

composer = (chat_root / "GameChatWindow.ChatComposer.cs").read_text(encoding="utf-8-sig")
composer_page = (chat_web / "discord-chat-composer.js").read_text(encoding="utf-8-sig")
expect(
    "Live Game Chat uses Discord's own signed-in, channel-scoped composer",
    'GameChatWeb.Page("discord-chat-composer.js")' in composer
    and 'discordAccountStatus != DiscordAccountStatus.SignedIn' in composer
    and 'browser.EnsureCoreWebView2Async(environment)' in composer
    and 'e.Cancel = !IsComposerRoute(e.Uri);' in composer
    and 'IsComposerRoute(e.Source)' in composer
    and 'core.Navigate(Channel);' in composer
    and 'SetWindowRgn(browser.Handle, region, true)' in composer
    and 'CloseChatComposer();' in show_sign_in
    and 'if (status != DiscordAccountStatus.SignedIn) CloseChatComposer();' in source
    and 'contenteditable="true"' in composer_page
    and 'channelTextArea_' in composer_page
    and not any(token in composer_page for token in ('fetch(', 'dispatchEvent(', '.click(', 'requestSubmit(')),
)
# Chat Host has a separate real WebView2 renderer, its parent, a native
# loading-text control and a textured custom scrollbar. All four must change
# state together on the first successful Discord feed.
loading = section_between(chat_renderer, "void ShowConnectingChat()", "\n    }")
feed_transition = section_between(
    chat_renderer,
    "bool enteringNativeMode = !nativeMode;",
    'Log("Native message view activated");',
)
expect(
    "Game Chat remains fully on its monitor when the launcher is near an edge",
    "leftSpace >= dockWidth" in dock_bounds
    and "rightSpace < dockWidth && leftSpace >= rightSpace" in dock_bounds
    and "Math.Clamp(x, work.Left, work.Right - size.Width)" in dock_bounds
    and "Math.Clamp(y, work.Top, work.Bottom - size.Height)" in dock_bounds
    and in_order(chat_layout, "Screen.FromHandle(owner).WorkingArea",
                 "FitPopupScale(launcherScale, chatWidth, dockHeight, work)",
                 "DockBounds(bounds, work, size, size.Width)",
                 "MoveWindow(Handle, target.X, target.Y, target.Width, target.Height, true);")
    and "MoveWindow(Handle, bounds.Left - chatWidth, y, chatWidth, windowHeight, true);" not in source,
)
expect(
    "Chat geometry fits the available space while visible browser text keeps its normal zoom",
    "OwnerLayoutScale(bounds.Right - bounds.Left, launcherBaseWidth, GetDpiForWindow(owner))" in chat_layout
    and "sideWidth / (double)chatWidth" in chat_layout
    and "SetBrowserScale(messageBrowser" not in source
    and "BaseWidth = 520, BaseHeight = 750" in sign_in_card
    and "Math.Min(width, Math.Max(1, work.Width - 24))" in sign_in_layout
    and "Math.Min(height, Math.Max(1, work.Height - 24))" in sign_in_layout
    and in_order(show_sign_in, "web.Parent = popup.BrowserPanel;", "web.ZoomFactor = 1;", "PositionChatWindows();")
    and "[data-tes3np-login-shell]:has([data-tes3np-login])" in discord_sign_in
    and "position:fixed !important; inset:10px 0 6px !important;" in discord_sign_in
    and "@media (max-height:480px)" in discord_sign_in
    and "overflow-y:auto !important;" in discord_sign_in,
)
expect(
    "First login exposes native Connecting status, not a stale scrollbar",
    'nativeMessages.Text = "Connecting to live chat...";' in loading
    and 'frameSurface.Visible = true;' in loading
    and 'messageClip.Visible = true;' in loading
    and 'nativeMessages.Visible = true;' in loading
    and 'nativeMessages.BringToFront();' in loading
    and 'messageBrowser.Visible = true;' in loading
    and 'goldScrollbar.Visible = false;' in loading
    and 'ShowConnectingChat();' in source
    and 'else ShowConnectingChat();' in source
    and 'chatViewport.Visible = web.Parent == chatViewport && !nativeMode && !connectingChat;' in source,
)
expect(
    "First authenticated feed keeps its loading state until the current renderer confirms visible message rows",
    'messageClip.Visible = true;' in feed_transition
    and 'messageBrowser.Visible = true;' in feed_transition
    and in_order(
        feed_transition,
        'nativeMessages.BringToFront();',
        'messageClip.PerformLayout();',
        'await messageBrowser.CoreWebView2.ExecuteScriptAsync(script)',
        'pageNavigationId != messagePageNavigationId || feedNavigationId != discordNavigationId',
        'if (chatOpen && !requireViewport)',
        'if (rendered != "true")',
        'nativeMode = true;',
        'nativeMessages.Visible = false;',
        'frameSurface.Invalidate(true);',
        'frameSurface.Update();',
        'goldScrollbar.Update();',
    )
    and '.WaitAsync(TimeSpan.FromSeconds(4))' in feed_transition
    and "(!feed.clientWidth || !feed.clientHeight)" in message_page
    and "return feed.querySelectorAll('.msg').length===messages.length;" in message_page,
)
renderer_recovery = section_between(source, "void NavigateMessagePage()", "void ScrollHtml(")
expect(
    "Game Chat retains Discord author colors and keeps the Yagrum relay styling",
    '.user{color:inherit;' in message_page
    and '.user.yagrum{color:#dbb243}' in message_page
    and "user.toLowerCase() === 'yagrum'" in feed_extractor
    and "?.querySelector('[class*=\"botTag_\"]')" in feed_extractor
    and 'isYagrum = entry.Value.IsYagrum' in source
    and 'authorColor = entry.Value.AuthorColor' in source
    and 'existing.AuthorColor != message.AuthorColor' in source
    and "name.className=m.isYagrum?'user yagrum':'user'" in message_page
    and "if(!m.isYagrum && m.authorColor && CSS.supports('color',m.authorColor))" in message_page
    and in_order(feed_extractor, "const theme = document.getElementById('tes3np-chat-style')?.sheet;",
                 "if (restoreTheme) theme.disabled = true;", "const style = getComputedStyle(author);",
                 "if (restoreTheme) theme.disabled = false;", "contentNode?.innerText?.trim()"),
)
expect(
    "Stalled native rendering retries the local document without restarting Discord or redocking the chat",
    "nextMessagePageReload = DateTime.UtcNow.AddSeconds(8);" in renderer_recovery
    and "DateTime.UtcNow < nextMessagePageReload" in renderer_recovery
    and "NavigateToString(MessagePage.Value);" in renderer_recovery
    and 'GameChatWeb.Page("message-feed.html")' in chat_renderer
    and 'GetManifestResourceStream(resourceName)' in source
    and 'tes3np.GameChat.Web.%(Filename)%(Extension)' in chat_project
    and '<AssemblyName>tes3np.ChatHost</AssemblyName>' in chat_project
    and 'RecoverMessagePage("page unavailable");' in source
    and 'RecoverMessagePage("page did not confirm message rows");' in source
    and "if (!docked) DockToLauncher();" in section_between(
        source, "void RestoreGameChatAfterSignIn()", "async Task UpdateViewMode()"),
)
expect(
    "Real textured scrollbar is the only scrollbar, with no stale frame-painted duplicate",
    'goldScrollbar.Paint += PaintChatScrollbar;' in source
    and 'g.DrawString("▲"' not in source
    and 'g.DrawString("▼"' not in source
    and 'int sx = w - 35;' not in source,
)

expect(
    "Happy Hour banner must track launcher movement without a timer delay",
    "void PositionHappyHourBanner()" in source
    and "SetWindowPos(banner.Handle, IntPtr.Zero, x, y, width, height," in source
    and "PositionHappyHourBanner();\n            if (repositionQueued) return;" in source
    and "SetWinEventHook(0x800B, 0x800B" in source,
)
mismatch = (ROOT / "src" / "game" / "expansion-mismatch.ahk").read_text(encoding="utf-8-sig")
expansion_toggle = (ROOT / "scripts" / "toggle-expansion-pack.ps1").read_text(encoding="utf-8-sig")
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
    'dialog.Show(mode = "Preflight" ? "NA" : "")' in mismatch_dialog
    and 'RequestDiscordExpansionPrompt(installing ? 1 : 2)' in mismatch_dialog
    and in_order(
        mismatch_dialog,
        'TES3MPExpansionCallNativeUi("GetOwnedMenuFitScale", LauncherGui,',
        'TES3MPExpansionCallNativeUi("ScaleOwnedMenuContent", dialog, scale)',
        'dialog.Show("Hide w" Round(660 * scale) " h" Round(627 * scale))',
        'TES3MPExpansionCallNativeUi("PositionOwnedMenuAtParent", dialog, LauncherGui)',
        'dialog.Show(mode = "Preflight" ? "NA" : "")',
        'RequestDiscordExpansionPrompt(installing ? 1 : 2)',
    )
    and 'ExpansionMismatchDialog.Show()' in mismatch_dialog
    and 'try WinActivate("ahk_id " dialog.Hwnd)' in mismatch_dialog
    and 'nativeStatus := dialog.Add("Text", "x25 y508 w610 h44 cD8C38C BackgroundTrans +Wrap",' in mismatch_dialog
    and 'AddStyledButton(dialog, 300, 580, 180, 38,' in mismatch_dialog
    and '"Repair / Install ZIP"' in mismatch_dialog
    and 'Open Expansion Pack Downloads' in bootstrap,
)
expect(
    "Expansion dialog layout and cleanup resolve launcher UI helpers only at runtime",
    'TES3MPExpansionCallNativeUi("DestroyScaledMenu", dialog)' in mismatch
    and not any(f"{helper}(" in mismatch for helper in (
        "GetOwnedMenuFitScale", "ScaleOwnedMenuContent", "PositionOwnedMenuAtParent", "DestroyScaledMenu"
    )),
)
expect(
    "Discord-backed Expansion Pack ZIP remains authenticated and retryable",
    'RequestDiscordExpansionPrompt(mode := 2)' in mismatch
    and 'if authConfirmed\n    {\n        if !SendLauncherChatCommand(6, downloadSlot.Hwnd)' in mismatch_dialog
    and 'ShowTES3MPExpansionMismatchDialog(mode = 1 ? "Install" : "Mismatch", true)' in mismatch
    and 'WinGetPID("ahk_id " lParam) != EmbeddedChatPid' in mismatch
    and 'OnMessage(0x8336, DiscordExpansionPromptReady)' in embedded_chat
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
    and '.rglob(' not in resource_generator
    and '"assets", "patches"' not in resource_generator,
)

expect(
    "Original Expansion Pack enable/disable switch is restored",
    'LauncherExpansionToggle := AddStyledButton(LauncherGui, 0, 0, 190, 27, "Expansion Pack: Disabled", ToggleExpansionPack)' in bootstrap
    and 'RefreshExpansionPackToggle()' in bootstrap
    and '"Expansion Downloads", ToggleLauncherExpansionDownloads' not in bootstrap,
)
expansion_toggle_action = section_between(patcher, "ApplyExpansionPackToggle(checked := false, disableUnverified := false)", "\nShowExpansionInstallPrompt(")
unverified_disable = section_between(
    expansion_toggle_action, "if !enable && !ExpansionPackInstalled(morrowind, cfg)\n    {",
    "\n    if enable && !checked",
)
expect(
    "Normal Expansion Pack toggles skip confirmation and show one success message after verifying the change",
    expansion_toggle_action.count("YesNo") == unverified_disable.count("YesNo") == 1
    and "Disable this load-order entry?" in unverified_disable
    and in_order(
        expansion_toggle_action,
        "exitCode := RunWait(command,",
        "actualEnabled := ExpansionPackInLoadOrder(cfg)",
        'MsgBox("Expansion Pack " (enable ? "enabled" : "disabled") " successfully."',
    )
    and 'if TES3MPExpansionBeginNativeProgress()\n        TES3MPExpansionUpdateNativeProgress("Checking for an Expansion Pack update...", 0)' in mismatch,
)
expect(
    "Mismatch dialog requests a child download view and disposes it on exit",
    'SendLauncherChatCommand(6, downloadSlot.Hwnd)' in mismatch
    and 'SendLauncherChatCommand(7, slotHwnd)' in mismatch
    and 'UploadExpansionFromFile()' in mismatch
    and 'Gui("+Owner" LauncherGui.Hwnd' in mismatch
    and 'SendLauncherChatCommand(command, targetHwnd := 0)' in embedded_chat,
)
expect(
    "An enabled pack can update on login rejection using the authenticated ZIP transfer",
    '&& TES3MPExpansionCallNativeUi("ExpansionPackIsEnabled")' in mismatch
    and 'mode := "Update"' in mismatch
    and 'ShowTES3MPExpansionMismatchDialog(mode)' in mismatch
    and 'installing := mode = "Install" || mode = "Browse"' in mismatch_dialog
    and 'if !ExpansionAutoDownloadAttempted && (ExpansionMismatchMode = "Update"' in mismatch
    and 'attachment == ExpansionLastAutomaticUpdateAttachment' in mismatch
    and 'ExpansionLastAutomaticUpdateAttachment := attachment' in mismatch
    and 'ExpansionMismatchMode != "Install" && ExpansionMismatchMode != "Update" && ExpansionMismatchMode != "Preflight"' in mismatch,
)
expansion_update_offer = section_between(
    mismatch,
    'TES3MPExpansionStartDiscoveredZip(slot, status)\n{',
    '\nTES3MPExpansionDecideUpdate(',
)
expansion_update_decision = section_between(
    mismatch,
    'TES3MPExpansionDecideUpdate(dialog, slot, attachment, action)\n{',
    '\nTES3MPExpansionAttachmentPath(',
)
expect(
    "An Expansion Pack update offers download, local upload, or dismissal",
    in_order(
        expansion_update_offer,
        'ExpansionAutoDownloadAttempted := true',
        'TES3MPExpansionCallNativeUi("ShowExpansionInstallPrompt"',
        'TES3MPExpansionDecideUpdate.Bind(dialog, slot, attachment)',
    )
    and in_order(
        expansion_update_decision,
        'if action != "Download"',
        'CloseTES3MPExpansionMismatchDialog(dialog, slot, action = "Upload")',
        'if attachment != TES3MPExpansionAttachmentPath(ExpansionMismatchZipUrl)',
        'TES3MPExpansionRevealRepair("The official ZIP changed. Try again to check the latest version.")',
        'ExpansionLastAutomaticUpdateAttachment := attachment',
        'TES3MPExpansionRequestAutoInstall(slot, ExpansionMismatchStatus)',
    )
    and in_order(
        patcher,
        'AddStyledButton(prompt, 30, 189 + extra, 165, 38, "Yes",',
        'AddStyledButton(prompt, 210, 189 + extra, 165, 38, "No",',
        'AddStyledButton(prompt, 390, 189 + extra, 260, 38, "Manual Install",',
    )
    and 'CloseExpansionInstallPrompt.Bind(prompt, "Upload")' in patcher
    and 'onDecision.Call(action)' in patcher
    and 'if !ExpansionAutoCloaked && !IsObject(ExpansionAutoProgressFrame)' in mismatch_dialog
    and 'TES3MPExpansionRevealRepair("Discord sign-in was closed.' in mismatch
    and 'TES3MPExpansionRevealRepair("Official ZIP discovery timed out.' in mismatch,
)

expect(
    "Known outdated Expansion Packs are offered before login or re-enable",
    in_order(session, "TES3MPCheckExpansionBeforeAction(config", "Client := session")
    and 'TES3MPCheckExpansionBeforeAction(cfg, (*) => ApplyExpansionPackToggle(true))' in patcher
    and in_order(expansion_update_offer, 'if packMatches', 'TES3MPExpansionContinuePreflight(dialog, recoveredExisting)')
    and 'TES3MPExpansionPackMatches(installedChecksum, checksum)' in expansion_update_offer
    and 'TES3MPExpansionPreflightUnavailable.Bind(dialog,' in mismatch
    and 'SetTimer(TES3MPExpansionAuthenticatePreflight.Bind(ExpansionMismatchDialog), -10)' in mismatch
    and in_order(
        section_between(mismatch, 'TES3MPExpansionAuthenticatePreflight(dialog)\n{',
                        'TES3MPExpansionPreflightUnavailable(dialog, reason)\n{'),
        'SetTimer(ExpansionPackPreflight.Deadline, 0)',
        'TES3MPExpansionEndNativeProgress()',
        'RequestDiscordExpansionPrompt(2)',
    )
    and 'TES3MPExpansionStartPreflightDiscovery(ExpansionMismatchDialog, 6)' in mismatch
    and 'Sign into Discord through Game Chat to check the official download.' not in mismatch
    and 'SetTimer(TES3MPExpansionContinuePreflight.Bind' not in mismatch
    and 'history:recent.map(item=>item.url)' in expansion_browser
    and 'ExpansionZipChecksum.ReadDownloaded(partial)' in source
    and 'if !packCurrent && TES3MPAllowsExpansionAutoUpdate(' in mismatch
    and 'case 15: CheckExpansionDownloadSilently(m.LParam); break;' in source
    and 'ExpansionZipChecksum.ReadAsync(uri)' in source
    and '"Installed: " installedVersion' in patcher
    and '"Available: " updateVersion' in patcher,
)

expect(
    "Existing Expansion Pack recovery requires a fresh official checksum and preserves disable fallback",
    'ExpansionPackNeedsOfficialVerification", config' in mismatch
    and 'NeedsRecovery: needsRecovery' in mismatch
    and 'if ExpansionMismatchZipChecksum = ""' in mismatch
    and '"RestoreExistingExpansionPackVerification", ExpansionPackPreflight.Config' in mismatch
    and 'TES3MPExpansionContinuePreflight(dialog, recoveredExisting)' in mismatch
    and 'ShowExistingExpansionPackFoundPrompt' in mismatch
    and 'RestoreExistingExpansionPackVerification(config, officialChecksum, officialVersion' in patcher
    and 'InstalledExpansionPackChecksum(config) != checksum' in patcher
    and 'SHA256File(esp)' in patcher
    and 'RememberExpansionPackVersion(checksum, officialVersion, attachment)' in patcher
    and 'ShowUnverifiedExistingExpansionPackPrompt(cfg)' in patcher
    and '"Verify Existing"' in patcher and '"Disable Entry"' in patcher
    and 'SetTimer(() => ApplyExpansionPackToggle(false, true), -1)' in patcher
    and 'CreateGoldNativePrompt(LauncherGui, "Existing Expansion Pack Verified", 680, 328)' in patcher
    and 'RestoreExistingExpansionPackVerification(config, crc, "v0.2c")' in launcher_smoke_tests,
)

found_pack_dialog = section_between(
    patcher,
    "ShowExistingExpansionPackFoundPrompt(onContinue, alreadyEnabled := false, reviewOnly := false)\n{",
    "\nCloseExistingExpansionPackFoundPrompt(prompt, proceed := false, *)\n{",
)
expect(
    "Verified existing Expansion Pack dialog has neutral copy, safe controls and bottom padding",
    'CreateGoldNativePrompt(LauncherGui, "Existing Expansion Pack Verified", 680, 328)' in found_pack_dialog
    and '"The installed Expansion Pack matches the latest official version. No download or reinstallation is necessary."' in found_pack_dialog
    and '"Your Expansion Pack is already enabled."' in found_pack_dialog
    and '"Would you like to enable it now?"' in found_pack_dialog
    and 'if alreadyEnabled\n    {' in found_pack_dialog
    and 'AddStyledButton(prompt, 240, 256 + extra, 200, 40, "OK",' in found_pack_dialog
    and 'AddStyledButton(prompt, 88, 256 + extra, 303, 40, "Enable Expansion Pack",' in found_pack_dialog
    and 'AddStyledButton(prompt, 409, 256 + extra, 183, 40, "Not Now",' in found_pack_dialog
    and found_pack_dialog.count('"Not Now"') == 1
    and 'GrowGoldNativePrompt(prompt, extra)' in found_pack_dialog
    and 256 + 40 + 24 <= 328,
)

expect(
    "User-approved first enable offers an automatic official ZIP and local repair fallback",
    'ShowExpansionInstallPrompt()' in patcher
    and 'CreateGoldNativePrompt(LauncherGui, "Install Expansion Pack", 680, 256)' in patcher
    and '"Download and Install"' in patcher
    and '"Choose ZIP or Folder"' in patcher
    and in_order(expansion_toggle_action, "ShowExpansionInstallPrompt()", "PrepareExpansionOpenMWConfiguration(cfg, morrowind)")
    and in_order(
        expansion_upload,
        "PrepareExpansionOpenMWConfiguration(config, morrowind)",
        "StartExpansionImportWorker(package, morrowind, config, package)",
    )
    and 'CloseExpansionInstallPrompt.Bind(prompt, "Download")' in patcher
    and 'CloseExpansionInstallPrompt.Bind(prompt, "Cancel")' in patcher
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
    and 'IsOfficialExpansionDownloadUrl(expansionPublishedZipUrl)' in source,
)
first_install_prompt = section_between(patcher, "extra += AddGoldPromptCopy(prompt, 30, 89 + extra", '    prompt.OnEvent("Close", CloseExpansionInstallPrompt')
expect(
    "First-enable download uses a gold card with automatic and local install options",
    'CreateGoldNativePrompt(LauncherGui, "Install Expansion Pack", 680, 256)' in patcher
    and 'ShowGoldNativePrompt(prompt)' in patcher
    and in_order(
        first_install_prompt,
        '"Download and Install"',
        'CloseExpansionInstallPrompt.Bind(prompt, "Download")',
        '"Choose ZIP or Folder"',
        'CloseExpansionInstallPrompt.Bind(prompt, "Upload")',
        '"Cancel"',
        'CloseExpansionInstallPrompt.Bind(prompt, "Cancel")',
    )
    and 'YesNoCancel Icon?' not in patcher
    and 'choice := MsgBox("NP Expansion Pack is not installed."' not in patcher,
)
expect(
    "All automatic download failures offer a native gold recovery card",
    'CreateGoldNativePrompt(LauncherGui, title, 700, 318)' in patcher
    and 'ShowExpansionAutoFailureDialog(reason := "", stage := "Download", retry := 0)' in patcher
    and 'AddStyledButton(prompt, 30, 254 + extra, 185, 38, "Try Again",' in patcher
    and 'AddStyledButton(prompt, 230, 254 + extra, 270, 38, "Choose ZIP or Folder",' in patcher
    and 'AddStyledButton(prompt, 515, 254 + extra, 155, 38, "Cancel",' in patcher
    and 'CloseGoldNativePrompt(prompt)' in patcher
    and 'if action = "Retry"' in patcher
    and 'else if action = "Local"' in patcher
    and 'UploadExpansionFromFile()' in patcher
    and 'RequestDiscordExpansionPrompt(1)' in patcher
    and 'SetTimer((*) => TES3MPExpansionCallNativeUi("ShowExpansionAutoFailureDialog", reason), -70)' in mismatch
    and 'SetTimer((*) => ExpansionMismatchDialog = dialog && TES3MPExpansionRevealRepair(' in mismatch
    and 'if !SendLauncherChatCommand(10, mode)' in mismatch
    and 'else if mode = 1' in mismatch,
)
expect(
    "Auto ZIP never exposes signed CDN URLs on command lines or downloads before approval",
    'string url=expansionPublishedZipUrl!;' in source
    and 'AllowAutoRedirect=false,UseCookies=false' in source
    and 'ResponseHeadersRead,cancellation.Token' in source
    and 'string stem="tes3np-"+Guid.NewGuid().ToString("N");' in source
    and 'SendCopyDataTimeout(owner,0x004A,sender,' in source
    and 'dwData=new IntPtr(0x8337)' in source
    and 'OnMessage(0x8338, TES3MPExpansionDownloadProgress)' in embedded_chat
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
    and 'ShowExpansionAutoFailureDialog(message, "Install")' in patcher
    and 'TES3MPExpansionCallNativeUi("ShowExpansionAutoFailureDialog", reason)' in mismatch
    and 'CloseTES3MPExpansionMismatchDialog(dialog, slot)' in mismatch
    and 'CloseExpansionAutoFailureDialog.Bind(prompt, "Retry")' in patcher
    and 'CloseExpansionAutoFailureDialog.Bind(prompt, "Local")' in patcher,
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
    "Automatic discovery is compositor-cloaked before show and manual browse/mismatch stays visible",
    'cloaked := (mode = "Install" || mode = "Update" || mode = "Preflight") && TES3MPExpansionCloakDialog(dialog, true)' in auto_install_view
    and in_order(
        auto_install_view,
        'TES3MPExpansionCloakDialog(dialog, true)',
        'dialog.Show(mode = "Preflight" ? "NA" : "")',
    )
    and 'if cloaked' in auto_install_view
    and 'if mode = "Update" || TES3MPExpansionBeginNativeProgress()' in auto_install_view
    and 'SetTimer((*) => TES3MPExpansionRetryNativeProgress(dialog), -300)' in auto_install_view
    and 'TES3MPExpansionRevealRepair("Native download window could not initialize.' in auto_progress_helpers
    and 'installing := mode = "Install" || mode = "Browse"' in auto_install_view
    and 'TES3MPExpansionCloakDialog(ExpansionMismatchDialog, false)' in auto_progress_helpers
    and 'DllCall("dwmapi\\DwmSetWindowAttribute"' in auto_progress_helpers
    and 'if IsObject(ExpansionAutoCloaked)' not in auto_progress_helpers,
)
expect(
    "Initial native progress failure gets one deferred retry without prematurely revealing repair",
    'TES3MPExpansionRetryNativeProgress(dialog)' in auto_progress_helpers
    and 'if !TES3MPExpansionBeginNativeProgress()' in auto_progress_helpers
    and 'SetTimer((*) => TES3MPExpansionDiscoveryDeadline(dialog), -60000)' in auto_progress_helpers
    and 'SetTimer((*) => TES3MPExpansionStartDiscoveredZip(slot, status), -80)' in auto_progress_helpers
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
    and in_order(
        auto_progress_helpers,
        'frame.Card.Show("NA h" (ch + extra))',
        'frame.Panel.Move(0, 0, cw, ch + extra)',
        'ExpansionAutoCancelButton := TES3MPExpansionCallNativeUi(',
        'TES3MPExpansionCallNativeUi("ProtectExpansionLoadingCancel", frame, ExpansionAutoCancelButton)',
    )
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
    and 'TES3MPExpansionRemoveDownloadCancel()' in auto_progress_helpers
    and 'try ExpansionAutoCancelButton.Visible := false' in auto_progress_helpers
    and 'TES3MPExpansionCallNativeUi("DestroyBookControl", ExpansionAutoCancelButton)' in auto_progress_helpers
    and 'if ExpansionAutoInstallLocked\n        return' in auto_download_cancel
    and 'ExpansionAutoInstallLocked := true' in auto_download_ready
    and 'ExpansionAutoDownloadActive := false' in auto_download_ready
    and 'TES3MPExpansionRemoveDownloadCancel()' in auto_download_ready
    and in_order(
        auto_download_ready,
        'ExpansionAutoInstallLocked := true',
        'TES3MPExpansionRemoveDownloadCancel()',
        'SetTimer((*) => TES3MPExpansionBeginAutoImport(',
    )
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
progress_painter = section_between(
    loading_ui,
    'UpdateExpansionLoadingProgress(frame, label, percent)\\n{'.replace('\\n', '\n'),
    '\\nSetInterfaceLoadingText('.replace('\\n', '\n'),
)
install_progress = section_between(patcher, "UpdatePatchProgress(label, percent)\n{", "\nCheckPatchWorker()")
expect(
    "Expansion download and install update buffered progress only when the label or percentage changes",
    'TES3MPExpansionCallNativeUi("UpdateExpansionLoadingProgress", frame, label, percent)' in mismatch
    and 'return UpdateExpansionLoadingProgress(PatchFrame, label " (" percent "%)", percent)' in install_progress
    and 'global ButtonFaces' not in auto_progress_helpers
    and 'global ButtonFaces' in progress_painter
    and 'ButtonFaces[panelHwnd].ProgressText := frame.Panel.Text' in loading_ui
    and in_order(
        progress_painter,
        'face.ProgressText == label && face.Progress = progress\n        return false',
        'face.ProgressText := label',
        'face.Progress := progress',
        'face.ProgressHeaderOnly := face.HasOwnProp("ProtectedButtonHwnd")',
        'PaintButtonNow(hwnd)',
        'finally face.ProgressHeaderOnly := false',
    )
    and "Panel.Text :=" not in install_progress + progress_painter
    and 'PaintButtonNow(protectedButton)' not in progress_painter
    and '|| UpdatePatchProgress("Installing", 37)' in launcher_smoke_tests
    and '|| probePanel.Text != "Initial caption"' in launcher_smoke_tests,
)
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
    and in_order(
        protected_loading_paint,
        'DllCall("ExcludeClipRect", "Ptr", target,',
        'try DllCall("BitBlt", "Ptr", target,',
        'DllCall("RestoreDC", "Ptr", target,',
    ),
)
expect(
    "Protected download progress blits only header pixels while ordinary loading cards still repaint fully",
    'paintFace.HasOwnProp("ProgressText") ? paintFace.ProgressText : paintFace.Control.Text' in protected_loading_paint
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
    and source.count("new GameChatWindow(") == 1
    and in_order(source, "new GameChatWindow(new IntPtr(owner), baseWidth)", "Application.Run(chat);")
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
    'GameChatWeb.Page("expansion-downloads.js")' in source
    and "document.querySelector('[data-list-id=\"chat-messages\"]')" in expansion_browser
    and r"cdn\.discordapp\.com" in expansion_browser
    and r"media\.discordapp\.net" in expansion_browser
    and r"location.pathname.replace(/\/+$/,'')" in expansion_browser
    and "link.href=file.url;" in expansion_browser
    and "link.textContent=file.filename;" in expansion_browser
    and "new MutationObserver(changes=>{" in expansion_browser
    and "await browser.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(" in source
    and "grid-template-columns: minmax(0, 1fr) !important" not in expansion_browser,
)

expect(
    "Future expansion ZIP selection is ordered by Discord message snowflakes",
    "const channel='/channels/509601787901116437/1555049936800718928';" in expansion_browser
    and "function snowflake(message)" in expansion_browser
    and r"chat-messages-\d+-(\d{15,22})" in expansion_browser
    and "BigInt(row[1])" in expansion_browser
    and "BigInt(single[1])" in expansion_browser
    and "item.id>best.id" in expansion_browser
    and "item.id===best.id && item.order>=best.order" in expansion_browser
    and "const files=readCandidates(feed);" in expansion_browser
    and "remember(files);" in expansion_browser
    and "link.href=file.url;" in expansion_browser
    and "phase='present'" in expansion_browser
    and "goToPresent(scroller)" in expansion_browser
    and "const maxBackfills=12, maxLoadingRetries=30, maxPresentRetries=18;" in expansion_browser
    and "presentRetries<=maxPresentRetries" in expansion_browser
    and "attributes:true,attributeFilter:['href']" in expansion_browser
    and "new MutationObserver(changes=>{" in expansion_browser
    and "lastFileKey===key" in expansion_browser
    and "grid-template-columns:" not in expansion_browser,
)

expect(
    "ZIP click is handed to default Windows browser without navigating embedded Discord",
    "link.addEventListener('click',event=>" in expansion_browser
    and "event.preventDefault();" in expansion_browser
    and "event.stopPropagation();" in expansion_browser
    and "chrome.webview.postMessage({type:'expansion-download',url});" in expansion_browser
    and "status.textContent='';" in expansion_browser
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
    and 'OnMessage(0x004A, TES3MPExpansionZipAvailable)' in embedded_chat
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
    and 'setTimeout(()=>{scheduled=false;refresh();},150);' in expansion_browser,
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
    and "status.textContent='';" in expansion_browser
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
    "test-expansion-diagnostics.ahk" in windows_build
    and "Plugin-mismatch diagnostic fixture tests failed" in windows_build,
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
    and 'PatchConfigurationPath()' in diagnostic_fixture
    and 'MismatchFixtureDisallow("configuration path")' in diagnostic_fixture
    and all(marker in diagnostic_fixture for marker in (
        "global Client :=",
        "global LauncherGui := 0",
        "global EmbeddedChatPid := 0",
        'global DataFile := ""',
    ))
    and 'InStr(report, "Load-order wording near rejection: No")' in diagnostic_fixture
    and 'TES3MPLastMismatchEvidence := TES3MPAnalyzeMismatchLogText(currentText)' in mismatch
    and 'TES3MPSelectMismatchLogEvidence(captured)' in mismatch
    and 'markers := TES3MPSelectMismatchLogEvidence(TES3MPLastMismatchEvidence)' in mismatch
    and 'Client evidence source: ' in mismatch
    and 'TES3MPLastMismatchEvidence := 0' in session
    and 'chosen.Source = "Captured during failed login"' in diagnostic_fixture
    and 'AutoHotkey fixture warnings detected; packaging stopped.' in windows_build,
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
    and 'TES3MPLastMismatchEvidence := 0' in session,
)
expect(
    "Expansion fingerprint uses Windows CNG and does not claim server version verification",
    'TES3MPFileSHA256(path)' in mismatch
    and 'bcrypt\\BCryptHashData' in mismatch
    and 'block := Buffer(1048576, 0)' in mismatch
    and 'Expansion ESP SHA-256: ' in mismatch
    and 'Expansion ESP size (bytes): ' in mismatch
    and 'Expansion Pack version verified: No (not checked)' in mismatch
    and 'known SHA-256 test vector' in diagnostic_fixture
    and 'private comparison detail leaked' in diagnostic_fixture,
)

expansion_picker = (ROOT / "scripts" / "select-expansion-package.ps1").read_text(encoding="utf-8-sig")
expansion_worker = (ROOT / "scripts" / "import-expansion-pack.ps1").read_text(encoding="utf-8-sig")
expansion_fixture = (ROOT / "scripts" / "test-import-expansion-folder.ps1").read_text(encoding="utf-8-sig")
expect(
    "Official Ahk2Exe asset download and local reuse require SHA-256",
    "if ($compilerAsset.url -notmatch '^https://api\\.github\\.com/repos/AutoHotkey/Ahk2Exe/releases/assets/[0-9]+$')" in windows_build
    and "'Official Ahk2Exe release SHA-256 digest is unavailable" in windows_build
    and "'Accept'] = 'application/octet-stream'" in windows_build
    and "SaveOfficialDownload $compilerAsset.browser_download_url $compilerZip $headers 'Ahk2Exe' $compilerAsset.url $expectedCompilerHash $apiHeaders" in windows_build
    and "if ((GetTes3npSha256 $candidate) -ieq $expectedCompilerHash)" in windows_build
    and "if ((GetTes3npSha256 $compilerZip) -ine $expectedCompilerHash)" in windows_build
    and "CheckOfficialZip $compilerZip 'Ahk2Exe'" in windows_build
    and "Using verified local official Ahk2Exe ZIP" in windows_build,
)
expect(
    "AutoHotkey mirror and persistent cache require GitHub release SHA-256",
    "'https://docs.autohotkey.com/download/2.0/' + $ahkAsset.name" in windows_build
    and "'^AutoHotkey_2\\.0\\.\\d+\\.zip$'" in windows_build
    and "'Official AutoHotkey release SHA-256 digest is unavailable" in windows_build
    and "SaveOfficialDownload $ahkAsset.browser_download_url $ahkZip $headers 'AutoHotkey' $ahkMirror $expectedAhkHash" in windows_build
    and "if ($ExpectedSha256 -and (GetTes3npSha256 $Destination) -ine $ExpectedSha256)" in windows_build
    and "Using cached official AutoHotkey ZIP (SHA-256 verified)" in windows_build
    and "CheckOfficialZip $ahkZip 'AutoHotkey'" in windows_build
    and "if ((GetTes3npSha256 $ahkZip) -ine $expectedAhkHash)" in windows_build,
)
expect(
    "Windows build retries official GitHub downloads and retains dist on upstream failure",
    "function GetOfficialRelease(" in windows_build
    and "function SaveOfficialDownload(" in windows_build
    and "for ($attempt = 1; $attempt -le 3; $attempt++)" in windows_build
    and "CheckOfficialZip $ahkZip 'AutoHotkey'" in windows_build
    and "CheckOfficialZip $compilerZip 'Ahk2Exe'" in windows_build
    and "CheckOfficialZip $tes3mpArchive 'TES3MP 0.8.1'" in windows_build
    and "SaveOfficialDownload $upstreamFontLicense" in windows_build
    and in_order(
        windows_build,
        "check-windows-package.py",
        "Installing the verified distribution into dist",
    )
    and "Remove-Item (Join-Path $projectRoot 'dist') -Recurse" not in windows_build,
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
    and "Preflighting full AutoHotkey launcher source and warning diagnostics" in windows_build
    and '$launcherOutput = @(& $base /ErrorStdOut $launcherSource' in windows_build
    and "'AutoHotkey launcher source warnings detected before packaging.'" in windows_build
    and "Preflighting generated standalone AutoHotkey source and warning diagnostics" in windows_build
    and "$stageOutput = @(& $base /ErrorStdOut $stageEntry '--check' 2>&1)" in windows_build
    and "'Staged AutoHotkey launcher warnings detected before compilation.'" in windows_build
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
    and 'select-expansion-package.ps1' in windows_build
    and 'Native Expansion Pack picker COM smoke test failed' in windows_build
    and '"scripts/select-expansion-package.ps1"' in resource_generator
    and '"scripts/import-expansion-pack.ps1"' in resource_generator
    and "Missing extracted Expansion Pack helper:" in windows_build
    and "Bundled Expansion Pack helper differs from source:" in windows_build
    and "Verified both extracted Expansion Pack helpers and source SHA-256 hashes" in windows_build,
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
    and 'function InvokeFileOperation([string]$Kind, [string]$Source, [string]$Destination, [string]$Operation, [string]$PreviousHash' in expansion_worker
    and 'if ($attempt -gt 1 -and $PreviousHash) { AssertExpectedTarget $Destination $PreviousHash }' in expansion_worker
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
    and 'ReplaceVerified $item.Source $item.Target $item.Hash $backupEntry.OriginalHash\n        $changed += $backupEntry' in expansion_worker
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
    and 'test-import-expansion-folder.ps1' in windows_build
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
    and "PositionHappyHourBanner();" in chat_layout
    and "PositionChatWindows();" in section_between(chat_window, "async void RefreshChatAsync(", "\n    }")
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
    and 'happyHourBanner.Show();\n                    // The verified banner is visible again after a launcher restore.\n                    NotifyLauncherHappyHourFace(true);' in source
    and 'happyHourBanner.Hide();\n                // Keep Jiub\'s appearance in sync when the banner is hidden.\n                NotifyLauncherHappyHourFace(false);' in source,
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
    in_order(
        front_layout,
        'LauncherGui.Add("Picture", "x0 y-4 w960 h720"',
        'CreateHappyHourDust()',
        'DragStrip := LauncherGui.Add(',
        'BuildButtonViewport()',
    ),
)

expect(
    "Vintage creatures are baked into the single launcher background",
    front_layout.count('LauncherGui.Add("Picture", "x0 y-4 w960 h720"') == 1
    and "og-creatures-overlay.png" not in front_layout
    and "og-creatures-overlay.png" not in bootstrap
    and not (ROOT / "assets" / "backgrounds" / "og-creatures-overlay.png").exists()
    and (ROOT / "assets" / "backgrounds" / "launcher.png").is_file(),
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
        embedded_chat,
)
expect(
    "Jiub coordinates and native control remain intact",
    '"x438 y84 w120 h135 Hidden BackgroundTrans"' in jiub_ui
    and '#Include src\\ui\\happy-hour.ahk'
        in entry_script
    and 'HappyHourJiubPicture.Visible := HappyHourBannerVisible' in jiub_ui,
)

expect(
    "Full AppData reset must stop ChatHost before deletion",
    in_order(settings_ui, "StopEmbeddedInGameChat()", "DirDelete(AppDataDirectory, true)"),
)
expect(
    "Full AppData reset must confirm ChatHost has exited before deleting user data",
    "chatPid := EmbeddedChatPid" in settings_ui
    and "stillRunning := ProcessWaitClose(chatPid, 5)" in settings_ui
    and "if stillRunning" in settings_ui
    and in_order(settings_ui, "ProcessWaitClose(chatPid, 5)", "DirDelete(AppDataDirectory, true)"),
)
expect(
    "Reset shutdown must not recreate Roaming logs or preferences",
    "LauncherDataResetting := true" in settings_ui
    and "if !LauncherDataResetting" in bootstrap
    and "ExitApp()" in settings_ui,
)
expect(
    "Full AppData reset rechecks recovery before removing its backups",
    in_order(settings_ui, "ProcessWaitClose(chatPid, 5)", "canReset := CanResetLauncherAppData(false)",
             "if canReset", "DirDelete(AppDataDirectory, true)")
    and "else if ExpansionRecoveryPending" in settings_ui,
)
expect(
    "Reset mode must be part of centralized launcher state",
    "global LauncherDataResetting := false" in app_state,
)

shortcut_offer = section_between(
    bootstrap, "OfferDesktopShortcutOnFirstLaunch(*)", "\n}",
)
expect(
    "Desktop shortcut is a one-time first-launch choice, never a Settings button",
    'SetTimer(OfferDesktopShortcutOnFirstLaunch, -1800)' in bootstrap
    and bootstrap.count("SetTimer(OfferDesktopShortcutOnFirstLaunch, -1800)") == 1
    and "SetTimer(CheckFirstRunMorrowind" not in bootstrap
    and 'AddStyledButton(settings, V016S(32), V016S(483) + copyExtra, V016S(448), V016S(30),' in settings_ui
    and '"Close Settings", CloseLauncherSettingsV016.Bind(settings))' in settings_ui
    and '"Create Desktop Shortcut"' not in settings_ui
    and 'AddStyledButton(settings, V016S(266), V016S(435) + copyExtra, V016S(214), V016S(30), "TES3MP Setup", OpenClientSelectionSettings)' in settings_ui
    and 'AddStyledButton(settings, V016S(32), V016S(435) + copyExtra, V016S(214), V016S(30), "Launcher Data", OpenAppDataSettingsV016.Bind(settings))' in settings_ui
    and 'if !A_IsCompiled || !FileExist(A_ScriptDir "\\client\\tes3mp.exe")' in shortcut_offer
    and 'IniRead(DataFile, "Launcher", "DesktopShortcutChoice", "") != ""' in shortcut_offer
    and 'answer := MsgBox("Would you like a desktop shortcut for Nerevarine Prophecies?"' in shortcut_offer
    and 'IniWrite(answer = "Yes" ? "Yes" : "No", DataFile, "Launcher", "DesktopShortcutChoice")' in shortcut_offer
    and in_order(shortcut_offer, 'IniWrite(answer = "Yes"', 'FileCreateShortcut(')
    and 'FileCreateShortcut(A_ScriptFullPath, A_Desktop "\\Nerevarine Prophecies.lnk"' in shortcut_offer
    and "forceAfterInstall" not in bootstrap,
)
characters_ui = (ROOT / "src" / "ui" / "characters.ahk").read_text(encoding="utf-8-sig")
expect(
    "AutoReconnect is saved from the character editor state",
    in_order(characters_ui, 'EditorFields["AutoReconnect"] := profile.AutoReconnect',
             'SetBookTick(EditorReconnectTick, EditorFields["AutoReconnect"])',
             'SaveProfileEditor.Bind(index, EditorFields)')
    and in_order(section_between(characters_ui, "\nToggleEditorReconnect(*)", "\n}"),
                 'EditorFields["AutoReconnect"] := !EditorFields["AutoReconnect"]',
                 'SetBookTick(EditorReconnectTick, EditorFields["AutoReconnect"])')
    and 'AutoReconnect: fields["AutoReconnect"]' in characters_ui,
)
settings_open = section_between(
    settings_ui,
    "OpenLauncherSettingsV016(*)",
    "\nCloseLauncherSettingsV016(settings, *)",
)
settings_close = section_between(
    settings_ui,
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
    'settings.Show("Hide w" V016S(512) " h" (V016S(590) + settings.ParchmentExtra))' in settings_open
    and in_order(
        settings_open,
        'settings.Show("Hide w"',
        'SetPageColorKey(settings, 0x010101)',
        '    settings.Show()',
    )
    and 'WinSetTransColor(' not in settings_open
    and 'if staged\n            RevealPaintedPage(settings)\n        else\n            FinishButtonDisplay()' in settings_open
    and 'DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 1)' in settings_close
    and in_order(
        settings_close,
        'DllCall("EnableWindow"',
        'try WinActivate("ahk_id " LauncherGui.Hwnd)',
        'try settings.Destroy()',
    ),
)
launcher_return = section_between(
    launcher_layout,
    "ShowLauncherWindow(reuseCached := false, *)",
    "\nGetLauncherScaleForWorkArea(",
)
expect(
    "Owned Character Book uses already-painted visible parent without global repaint before Hide",
    'placement := GetLauncherPlacement()' in launcher_return
    and 'if placement.Scale = LauncherCachedScale' in launcher_return
    and 'DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)' in launcher_return
    and 'LauncherControlLayout.Count = LauncherCachedLayoutCount' in launcher_return
    and 'if reuseCached\n            return' in launcher_return
    and in_order(
        launcher_return,
        'if reuseCached',
        'RepaintMenuButtons()',
    )
    and 'ShowLauncherWindow(true)\n    preparedMs := A_TickCount - startedAt\n    CharacterPage.Hide()' in characters_close
    and 'LogLauncherEvent("UI | Character Book close " hiddenMs "ms | Parent " preparedMs' in characters_close
    and 'HideProfileEditor()\n    CloseMacroPage()' in characters_close,
)
expect(
    "Character Book raises the prepared launcher before hiding and restoring dormant book controls",
    'ShowLauncherWindow(true)' in characters_close
    and in_order(
        characters_close,
        'ShowLauncherWindow(true)',
        'CharacterPage.Hide()',
        'HideProfileEditor()',
        'CloseMacroPage()',
    )
    and 'PrepareWindowDisplay(CharacterPage)' in characters_ui
    and 'RevealWindowDisplay(CharacterPage, true, !staged)' in characters_ui,
)
window_presenter = (ROOT / "src" / "ui" / "windows.ahk").read_text(encoding="utf-8-sig")
gold_prompts = (ROOT / "src" / "ui" / "gold-prompts.ahk").read_text(encoding="utf-8-sig")
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
    and 0 <= characters_open.find('PrepareWindowDisplay(CharacterPage)')
        < characters_open.rfind('CharacterPage.Show("Hide w" Round(960 * bookScale)')
        < characters_open.rfind('RevealWindowDisplay(CharacterPage, true, !staged)')
        < characters_open.rfind('RevealPaintedPage(CharacterPage)')
    and 'FinishButtonDisplay()\n                RevealPaintedPage(CharacterPage)' not in characters_open,
)
expect(
    "Settings first visible frame waits for composited parchment and native button paint",
    'staged := SetPageCompositorCloak(settings, true)' in settings_open
    and in_order(
        settings_open,
        'staged := SetPageCompositorCloak(settings, true)',
        'settings.Show("Hide w"',
        'SetPageColorKey(settings, 0x010101)',
        '        settings.Show()',
        'RevealPaintedPage(settings)',
    )
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
    and in_order(
        window_presenter,
        'DllCall("RedrawWindow"',
        'SetPageCompositorCloak(gui, false)',
    ),
)
expect(
    "Windows CI tests DWM staged window as a disposable visible GUI",
    'case "--check-page-compositor":' in launcher_smoke_tests
    and 'DwmGetWindowAttribute' in launcher_smoke_tests
    and 'SetPageColorKey(testWindow, 0x010101)' in launcher_smoke_tests
    and 'GetLayeredWindowAttributes' in launcher_smoke_tests
    and 'NumGet(colorKey, 0, "UInt") != 0x010101' in launcher_smoke_tests
    and 'NumGet(colorFlags, 0, "UInt") != 1' in launcher_smoke_tests
    and "NumGet(before, 0, \"Int\") = 0" in launcher_smoke_tests
    and "NumGet(after, 0, \"Int\") != 0" in launcher_smoke_tests
    and '#Include scripts\\launcher-smoke-tests.ahk' in entry_script,
)
expect(
    "Windows CI includes real owned-window test for cached Character Book return",
    'case "--check-cached-character-return":' in launcher_smoke_tests
    and 'probeBook := Gui("+Owner" LauncherGui.Hwnd' in launcher_smoke_tests
    and 'ShowLauncherWindow(true)\n    probeBook.Hide()' in launcher_smoke_tests
    and 'if !ButtonFaces.Has(probeHandle)' in launcher_smoke_tests,
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
    'return Max(0.1, Min(GetOwnedMenuScale(), fit))' in settings_ui
    and 'PositionOwnedMenuAtParent(settings, LauncherGui)' in settings_open
    and 'settings.Show("Hide w" V016S(512) " h" (V016S(590) + settings.ParchmentExtra))' in settings_open
    and 'SetPageColorKey(settings, 0x010101)' in settings_open
    and 'staged := SetPageCompositorCloak(settings, true)' in settings_open
    and 'PositionOwnedMenuAtParent(settings, LauncherGui)' in display_settings,
)
expect(
    "Launcher Settings reserves its original geometry and reflows overflowing help text",
    'label.GetPos(, , , &measuredHeight)' in settings_ui
    and 'return Max(0, measuredHeight - reserved)' in settings_ui
    and 'if extra <= settings.ParchmentExtra' in settings_ui
    and 'settings.Parchment.Value := A_ScriptDir' in settings_ui
    and 'AddV016SettingsCopy(settings, 32, V016S(196), 448, 40,' in settings_open
    and 'AddV016SettingsCopy(settings, 32, V016S(269) + copyExtra, 448, 30,' in settings_open
    and 'AddV016SettingsCopy(settings, 42, V016S(166), 428, 65,' in settings_ui,
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
    and 'ShowLauncherWindow(true)' in characters_close,
)
expect(
    "Client, dependency and Morrowind use scaled native changelog cards; remaining dialogs follow owners",
    'CreateGoldNativePrompt(ownerHwnd, "tes3np — TES3MP Setup", 680, initialHeight)' in settings_ui
    and 'initialHeight := saved ? 460 : 412' in settings_ui
    and 'ShowGoldNativePrompt(menu)' in settings_ui
    and 'options := CreateGoldNativePrompt(menu, "Set Up Your Custom EXE", ' in settings_ui
    and 'ShowGoldNativePrompt(options)' in settings_ui
    and 'CreateGoldNativePrompt(LauncherGui, "TES3NP - Morrowind Installation Not Found", 680, 350)' in patcher
    and 'ShowGoldNativePrompt(prompt)' in patcher
    and 'ScaleOwnedMenuContent(dialog, dialogScale)' in characters_ui
    and 'PositionOwnedMenuAtParent(dialog, CharacterPage)' in characters_ui
    and 'ScaleOwnedMenuContent(chooser, chooserScale)' in macro_menu_ui
    and 'PositionOwnedMenuAtParent(chooser, MacroPage)' in macro_menu_ui,
)
expect(
    "Borderless changelog native cards own their dimmers and release them on every exit",
    '#Include src\\ui\\gold-prompts.ahk' in entry_script
    and 'CreateGoldPromptBackdrop(owner := 0)' in gold_prompts
    and 'CreateGoldNativePrompt(owner, title, width, height)' in gold_prompts
    and 'Gui("-Caption -Border -DPIScale +Owner" backdrop.Hwnd, title)' in gold_prompts
    and 'ScaleOwnedMenuContent(panel, scale)' in gold_prompts
    and 'ShowCenteredGoldPrompt(panel, panel.NativePromptBackdrop,' in gold_prompts
    and 'CloseGoldNativePrompt(panel)' in gold_prompts
    and 'CloseGoldNativePrompt(menu)' in settings_ui
    and 'CloseGoldNativePrompt(options)' in settings_ui
    and settings_ui.count('options.Destroy()') == 0
    and 'CloseGoldNativePrompt(prompt)' in section_between(
        patcher, 'SelectFirstRunMorrowind(prompt, *)', '\nDismissFirstRunMorrowind(')
    and 'CloseGoldNativePrompt(prompt)' in section_between(
        patcher, 'DismissFirstRunMorrowind(prompt, *)', '\n}'),
)
expect(
    "Discord sign-in uses a borderless gold card with in-window close and original toggle",
    'FormBorderStyle = FormBorderStyle.None;' in sign_in_card
    and 'BackColor = Color.FromArgb(197, 164, 92);' in sign_in_card
    and 'Padding = new Padding(2);' in sign_in_card
    and 'close.Click += (_, _) => dismiss();' in sign_in_card
    and 'close.BringToFront();' in sign_in_card
    and 'new DiscordSignInCard(DismissDiscordSignIn)' in show_sign_in
    and 'ToggleGameChatDiscordSignIn();' in source
    and 'FormBorderStyle.FixedDialog' not in sign_in_card,
)
expect(
    "Game Client text clears buttons and available actions dictate card height",
    'details := menu.Add("Text", "x30 y" detailsY " w620 BackgroundTrans +Wrap",' in settings_ui
    and 'textOffset := FitGameClientPromptCopyV016(menu, details, detailsY, 190)' in settings_ui
    and 'customize := AddStyledButton(menu, 30, 190 + textOffset, 620, 40,' in settings_ui
    and 'textOffset := FitGameClientPromptCopyV016(options, details, detailsY, 198)' in settings_ui
    and 'skip := AddStyledButton(options, 30, 246 + textOffset, 580, 38, "Use My Custom Exe",' in settings_ui
    and 'offset := Max(0, detailsY + paddedHeight + 12 - buttonY)' in settings_ui
    and 'initialHeight := saved ? 460 : 412' in settings_ui
    and 'reactivate.Visible := saved' in settings_ui
    and 'restoreY := (saved ? 286 : 238) + textOffset' in settings_ui
    and 'statusY := (saved ? 339 : 291) + textOffset' in settings_ui
    and 'closeY := (saved ? 399 : 351) + textOffset' in settings_ui
    and 'RefreshGameClientSettingsLayoutV016(menu)' in settings_ui
    and 'menu.NativePromptBackground.Move(' in settings_ui
    and 'panel.NativePromptBackground := panel.Add("Text",' in gold_prompts,
)
expect(
    "Manage Macros empty state and Upload button do not leave blank action row",
    'MacroEmptyNotice := CharacterPage.Add("Text", "x525 y150 w355 h28' in macro_menu_ui
    and 'MacroImportButton := AddStyledButton(CharacterPage, 525, 188, 355, 29,' in macro_menu_ui
    and 'desiredUploadY := count = 0 ? 188 : 214 + (visibleCount - 1) * 70' in macro_menu_ui
    and 'MoveStyledButton(MacroImportButton, 525, desiredUploadY, 355, 29)' in macro_menu_ui
    and 'maximum := Max(0, count - MacroBookRows.Length)' in macro_menu_ui,
)
expect(
    "Manage Macros delegates shortcut configuration to each imported macro",
    'MacroBindingsButton' not in macro_menu_ui
    and 'EditSelectedMacroBindings' not in macro_menu_ui
    and 'ReadMacroBindings' not in macro_menu_ui
    and 'TES3NP_BINDINGS' not in macro_menu_ui
    and 'MoveStyledButton(MacroImportButton, 525, desiredUploadY, 355, 29)' in macro_menu_ui
    and '#Include src\\ui\\macro-bindings.ahk' not in entry_script,
)
expect(
    "Macro rows have a true line break between action buttons and next Ready status",
    'y := 140 + (position - 1) * 70' in macro_menu_ui
    and 'AddStyledButton(CharacterPage, 775, y + 42, 105, 20,' in macro_menu_ui
    and 'desiredUploadY := count = 0 ? 188 : 214 + (visibleCount - 1) * 70' in macro_menu_ui
    and '"x887 y140 w8 h272 Background704C27 +0x100 Hidden"' in macro_menu_ui
    and 'travel := 272 - thumbHeight' in macro_menu_ui
    and 'travel := Max(1, 272 - thumbHeight)' in macro_menu_ui,
)
expect(
    "Populated macro rows begin close to description with scroll and Upload aligned",
    'explanation := CharacterPage.Add("Text", "x525 y87 w355 h48 BackgroundTrans"' in macro_menu_ui
    and 'y := 140 + (position - 1) * 70' in macro_menu_ui
    and 'desiredUploadY := count = 0 ? 188 : 214 + (visibleCount - 1) * 70' in macro_menu_ui
    and '"x888 y140 w6 h40 BackgroundC69951 +0x100 Hidden"' in macro_menu_ui
    and 'thumbY := 140 + Round(MacroScrollOffset / maximum * travel)' in macro_menu_ui
    and 'ScrollMacroBook(Round((localY - 140 - MacroScrollGrab) / travel * maximum))' in macro_menu_ui,
)
expect(
    "Windows CI verifies all manual menu scales, moved owner and monitor-edge clamping",
    'case "--check-owned-menu-scaling":' in launcher_smoke_tests
    and 'for percent in [50, 60, 70, 80, 90, 100]' in launcher_smoke_tests
    and 'scale := GetOwnedMenuScale()' in launcher_smoke_tests
    and 'ScaleOwnedMenuContent(child, scale)' in launcher_smoke_tests
    and 'PositionOwnedMenuAtParent(child, LauncherGui)' in launcher_smoke_tests
    and 'if Abs(NumGet(movedRect, 0, "Int")' in launcher_smoke_tests
    and 'NumGet(edgeRect, 8, "Int") > mr' in launcher_smoke_tests,
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
    "The Discord header uses the centered sign-in card and Game Chat uses its dock",
    'PositionDiscordSignIn(bounds, work);' in chat_layout
    and in_order(sign_in_layout, 'pendingExpansionPrompt == 0 && !discordSignInFromHeader',
                 'DockBounds(ownerBounds, work, size, size.Width)',
                 'work.Left + (work.Width - size.Width) / 2')
    and "case 16: RequestDiscordSignIn(fromHeader: true);" in source
    and in_order(section_between(source, "void RequestDiscordSignIn(bool fromHeader)", "async Task SignOutDiscord()"),
                 "discordSignInFromHeader = fromHeader;", "RevealDiscordSignInWindow();")
    and 'Discord Integration!' in discord_sign_in
    and 'Sign In Required' in source
    and 'CopyToPublishDirectory="PreserveNewest"' in chat_project
    and "assets\\DiscordInt.png" in chat_project,
)

# New interactive behaviors must remain separated from the launcher's
# older authentication and installer contracts. Static evidence does not
# replace a real Windows sign-in or missing-game acceptance test.
expect(
    "Game Chat toggle can hide and reopen its own Discord login",
    'void ToggleGameChatDiscordSignIn()' in source
    and 'if (pendingExpansionPrompt == 0 &&' in source
    and source.count('ToggleGameChatDiscordSignIn();') == 1
    and 'void DismissDiscordSignIn()' in source
    and 'if (discordLoginVisible) RevealDiscordSignInWindow();' in source,
)
expect(
    "Only the current Expansion browser can complete initialization or publish ZIP messages",
    "ReferenceEquals(initializingExpansionBrowser, browser)" in source
    and "ReferenceEquals(browser, expansionDownloadsBrowser)" in source
    and "source.GetLeftPart(UriPartial.Path).TrimEnd('/')" in source,
)
expect(
    "Discord login cancellation follows actual passkey row without overlapping password",
    "anchor.insertAdjacentElement('afterend', later);" in discord_sign_in
    and "form.appendChild(later);" not in discord_sign_in
    and "/sign in with a passkey/i.test(el.textContent || '')" in discord_sign_in
    and "parent.querySelector('input,button[type=submit]')" in discord_sign_in
    and "later.type = 'button';" in discord_sign_in
    and "chrome.webview.postMessage('tes3np-sign-in-later');" in discord_sign_in
    and in_order(discord_sign_in_handler, "switch (args.TryGetWebMessageAsString())",
                 'case "tes3np-sign-in-later":', "DismissDiscordSignIn();")
    and 'requestAnimationFrame(resetIfUntouched);' in discord_sign_in
    and "position:static !important;" in discord_sign_in
    and "min-height:44px !important" in discord_sign_in
    and 'RowCount = 3,' in source
    and 'shell.Controls.Add(later, 0, 3);' not in source,
)
expect(
    "Discord Integration heading has no line or underline",
    "border:0 !important; box-shadow:none !important;" in discord_sign_in
    and "text-decoration:none !important;" in discord_sign_in
    and "border-bottom:1px solid #70532c !important;" not in source,
)
expect(
    "Approved ZIP survives only while missing-Morrowind setup owns it",
    'DeferExpansionInstallForMissingMorrowind(package, autoApproved)' in expansion_upload
    and 'PendingExpansionPackage := package' in expansion_upload
    and 'SetTimer(InstallSelectedExpansionPackage.Bind(pendingPackage, pendingApproved), -50)' in patcher
    and 'MorrowindPromptGui.PendingExpansionPackage = package' in mismatch
    and 'if !deferred' in mismatch
    and 'if prompt.HasOwnProp("PendingExpansionApproved")' in patcher,
)
expect(
    "Client identity and clickable controls use TES3MP and Windows pointer",
    '"Using the included TES3MP setup"' in settings_ui
    and '"Use Included TES3MP"' in settings_ui
    and 'Original TES3NP runtime' not in settings_ui
    and 'SetLauncherHandCursor()' in native_renderer
    and 'OnMessage(0x0020, HandleNativeClickableCursor)' in native_renderer
    and in_order(section_between(native_renderer, 'HandleNativeClickableCursor(wParam,', 'InitButtonPainter()'),
                 'DllCall("IsWindowEnabled", "Ptr", wParam)', 'DllCall("IsWindowVisible", "Ptr", wParam)',
                 'className = "Button" || className = "SysLink"',
                 'SetLauncherHandCursor()'),
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
    and in_order(
        session,
        "if !EnsureMorrowindForGameLaunch()",
        "StartProfileSession(profile, executable)",
    )
    and "FindMorrowindFolder(PatchConfigurationPath())" in patcher
    and "EnsureOpenMWConfiguration(DefaultOpenMWConfigurationPath(), found)" in patcher
    and "CheckFirstRunOpenMWConfiguration()" in launcher_smoke_tests,
)
expect(
    "Expansion Pack Enabled requires real nonempty ESP and current load-order entry",
    in_order(section_between(patcher, "ExpansionPackIsEnabled(", "RefreshExpansionPackToggle()"),
             "ExpansionPackInLoadOrder(config)",
             "ExpansionPackInstalled(FindMorrowindFolder(config), config)")
    and 'ExpansionPackIsEnabled(config) ? "Enabled" : "Unverified"' in patcher
    and "enable := !ExpansionPackInLoadOrder(cfg)" in patcher
    and "FileGetSize(esp) > 0" in patcher
    and "SHA256File(esp) = verifiedHash" in patcher
    and "CheckExpansionPackToggleState()" in launcher_smoke_tests,
)
expect(
    "Unfinished Discord recovery never suppresses a new game login",
    "ResetPendingExpansionPromptForNewLaunch()" in session
    and "SendLauncherChatCommand(11)" in mismatch
    and "case 11: CancelPendingExpansionPrompt(false); break;" in source,
)
expect(
    "Game client count tracks processes from launch and cancelled login discards its credentials",
    in_order(session, "TES3NPActiveGameHandles.Push(handle)", 'Client.Phase := "window"')
    and 'if Client != session || !Client.Enabled || Client.HWND != hwnd' in session
    and 'Client.Profile := 0' in section_between(session, "StopClient(*)", "\nFindGameWindow(")
    and 'ReleaseTES3NPGameClients()' in bootstrap,
)
login_progress = (ROOT / "src" / "ui" / "login-progress.ahk").read_text(encoding="utf-8-sig")
login_cleanup = section_between(login_progress, "UpdateGameLoginProgress(*)", "\n}")
session_stop = section_between(session, "StopClient(*)", "\nFindGameWindow(")
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
expect(
    "Login overlay has a bounded presentation lifetime and independent completion dismiss",
    'LoginProgressGeneration += 1' in login_progress
    and 'LoginProgressHardDeadline := A_TickCount + Max(60000, expectedMs)' in login_progress
    and 'SetTimer(DismissCompletedLoginProgress.Bind(LoginProgressGeneration), -3100)' in login_progress
    and 'if generation != LoginProgressGeneration || LoginProgressMode != "complete"' in login_progress
    and 'DismissGameLoginProgress()' in section_between(
        login_progress, "DismissCompletedLoginProgress(generation)", "\n}")
    and 'A_TickCount >= LoginProgressHardDeadline' in login_cleanup
    and 'LogLauncherEvent("UI | Login progress exceeded its display deadline; game session unchanged.")' in login_cleanup
    and 'DllCall("RedrawWindow", "Ptr", LoginProgressGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)' in login_progress
    and 'ProcessClose(' not in login_cleanup,
)
login_card_fit = section_between(login_progress, "FitGameLoginProgress(area,", "GetGameLoginProgressWindow(hwnd)")
login_card_layout = section_between(login_progress, "GetGameLoginProgressLayout(hwnd, gameWindow)", "TranslateGameLoginProgress(layout, gameWindow)")
login_card_move = section_between(login_progress, "OnGameLoginProgressLocationChange(hook,", "GameLoginProgressFontSize(")
login_card_present = section_between(login_progress, "PresentGameLoginProgress(gameHwnd, layout)", "UpdateGameLoginProgress(*)")
login_card_position = section_between(login_progress, "PositionGameLoginProgress(cardHwnd,", "PresentGameLoginProgress(gameHwnd, layout)")
expect(
    "Game login progress retains its normal DPI layout when it fits and follows the visible TES3MP client",
    "Min(normalScale, area.Width / 420, area.Height / 481)" in login_card_fit
    and "anchor := scale < normalScale ? area : gameWindow" in login_card_fit
    and 'WinGetClientPos(&x, &y, &width, &height, "ahk_id " hwnd)' in login_card_layout
    and 'DllCall("GetMonitorInfoW"' in login_card_layout
    and "A_ScreenDPI / 96)" in login_card_layout
    and "layout := GetGameLoginProgressLayout(hwnd, gameWindow)" in login_cleanup
    and "PresentGameLoginProgress(hwnd, layout)" in login_cleanup
    and "previous.ProgressScale != layout.Scale" in login_card_present
    and "DismissGameLoginProgress(" not in login_card_present
    and 'window.Show("Hide x" layout.X' in login_progress
    and in_order(login_card_present, "CreateGameLoginProgress(layout)", "RenderGameLoginProgress()",
                 'PositionGameLoginProgress(LoginProgressGui.Hwnd, gameHwnd, layout', "try previous.Destroy()")
    and 'row.Symbol.SetFont("s" GameLoginProgressFontSize(14, scale)' in login_progress
    and 'marker.Symbol.SetFont("s" GameLoginProgressFontSize(17, scale)' in login_progress
    and "CheckGameLoginProgressFit()" in launcher_smoke_tests,
)
expect(
    "The login card follows the visible TES3MP window in Z-order without depending on focus",
    in_order(login_card_position, 'DllCall("GetWindow", "Ptr", gameHwnd, "UInt", 3, "Ptr")',
             "flags := 0x0010 ; SWP_NOACTIVATE", "if above = cardHwnd && cardTopmost = gameTopmost",
             'DllCall("SetWindowPos", "Ptr", cardHwnd, "Ptr", above')
    and in_order(login_cleanup, 'DllCall("IsWindowVisible", "Ptr", hwnd)', 'DwmGetWindowAttribute',
                 "WinGetMinMax(target) = -1 || cloaked", "layout := GetGameLoginProgressLayout(hwnd, gameWindow)",
                 "PresentGameLoginProgress(hwnd, layout)")
    and "GetForegroundWindow" not in login_progress
    and "WinActive(" not in login_progress
    and "WinActivate(" not in login_progress,
)
expect(
    "The painted login card translates in response to its game's window movement and releases the event hook on dismissal",
    'DllCall("SetWinEventHook", "UInt", locationChange, "UInt", locationChange,' in login_progress
    and '"UInt", pid, "UInt", threadId, "UInt", 0, "Ptr") ; WINEVENT_OUTOFCONTEXT' in login_progress
    and "tracking.Hwnd != hwnd || objectId || childId" in login_card_move
    and "TranslateGameLoginProgress(previous, GetGameLoginProgressWindow(hwnd))" in login_card_move
    and "PositionGameLoginProgress(LoginProgressGui.Hwnd, hwnd, layout, false, true)" in login_card_move
    and "CreateGameLoginProgress(" not in login_card_move
    and "GameLoginProgressIsDragging(LoginProgressTracking, hwnd)" in login_cleanup
    and 'DllCall("UnhookWinEvent", "Ptr", tracking.Hook, "Int")' in login_progress
    and "StopGameLoginProgressTracking()" in section_between(login_progress, "\nDismissGameLoginProgress()", "\n}")
    and "CheckGameLoginCardMoveTracking(game, card, layout)" in launcher_smoke_tests,
)
font_update = section_between(
    display_settings, "\nApplyAccessibilityTextSize(suspendRedraw := true)\n{", "\nApplyEnhancedReadability()\n{"
)
launcher_button_font = section_between(
    display_settings, "\nApplyLauncherButtonFont(face, scale)\n{", "\nApplyAccessibilityTextSize("
)
expect(
    "The first menu button leaves the original Game Launcher heading outside its paint surface",
    'y414 w300 h34 Center BackgroundTrans", "Game Launcher"' in front_layout
    and 'AddLauncherButton(447 + (A_Index - 1) * 40, "", OpenCharacters, A_Index = 1 ? 10 : 0)' in front_layout
    and '(y - 11 + topPadding)' in controls
    and 'paintTop := height - visibleHeight' in native_renderer
    and '"Int", visibleHeight, "Ptr", dc, "Int", 0, "Int", paintTop' in native_renderer,
)
expect(
    "Display text changes never restore unscaled themed-button geometry",
    "size := AccessibilityFontSize(10)" in launcher_button_font
    and "scale := LauncherScale / 100" in font_update
    and 'Max(5, Round(size * scale))' in launcher_button_font
    and "ApplyLauncherButtonFont(face, scale)" in font_update
    and "ApplyLauncherButtonFont(face, scale)" in launcher_layout
    and "face.Control.Move(" not in font_update,
)
launcher_scale_apply = section_between(
    launcher_layout, "ApplyLauncherScaleToWindow(suspendRedraw := true, placement := unset)\n{", "\n}",
)
expect(
    "Declined display previews restore saved state and visible settings controls",
    "ApplyLauncherScaleToWindow(false)" in display_settings
    and "ApplyAccessibilityTextSize(false)" in display_settings
    and "ApplyEnhancedReadability()" in display_settings
    and 'scaleList.Choose(oldMode = "Auto" ? 1 : ScaleChoiceIndex(oldRequestedScale) + 1)' in display_settings
    and 'textList.Choose(oldText = "Large" ? 2' in display_settings
    and "V016ReadabilityState := readability.Value" in display_settings
    and "V016FollowWindowsState := followWindows.Value" in display_settings
    and "UpdateV016ReadabilityLabel(settings.ReadabilityControl, V016ReadabilityState)" in display_settings
    and "CloseLauncherSettingsV016(settings)" in display_settings
    and in_order(
        launcher_scale_apply,
        "ApplyLauncherControlScale(suspendRedraw)",
        "LauncherCachedScale := LauncherScale",
        "LauncherCachedLayoutCount := LauncherControlLayout.Count",
    ),
)
display_refresh = section_between(display_settings, "\nRefreshLauncherDisplay(message, settings)", "\nSaveLauncherDisplaySettings(")
expect(
    "Display previews use live loading feedback before and throughout resize",
    in_order(display_refresh, "CreateLoadingCard(LauncherGui,", "SetLoadingCardProgress(loading.Panel, message,",
             'DllCall("EnableWindow", "Ptr", launcherHwnd, "Int", 1)', 'WinActivate("ahk_id " launcherHwnd)',
             "settings.Hide()", "ApplyLauncherScaleToWindow(false)", "PositionOwnedMenuAtParent(loading.Card, LauncherGui)",
             '"Updating interface text..."', "ApplyAccessibilityTextSize(false)",
             '"Updating readability..."', "finally DestroyLoadingCard(loading)")
    and 'RefreshLauncherDisplay("Restoring display settings...", settings)' in display_settings
    and '"Resetting display settings..."' in display_settings
    and "SetPageCompositorCloak(" not in display_refresh
    and "CaptureInterfaceFrame(" not in display_refresh
    and "WinGetPos(" not in launcher_scale_apply
    and "WinMove(" not in launcher_scale_apply,
)
control_scale = section_between(launcher_layout, "ApplyLauncherControlScale(suspendRedraw", "ShowLauncherWindow(")
expect(
    "Preview and revert keep the main window visible and return focus to Settings only after repaint",
    in_order(display_refresh, 'DllCall("IsIconic", "Ptr", launcherHwnd, "Int")',
             'DllCall("ShowWindow", "Ptr", launcherHwnd, "Int", 9)', 'DllCall("GetWindowRect", "Ptr", launcherHwnd,')
    and 'if suspendRedraw\n        DllCall("SendMessageW"' in control_scale
    and 'if suspendRedraw\n        DllCall("SendMessageW"' in font_update
    and in_order(display_settings, 'RefreshLauncherDisplay("Restoring display settings...", settings)',
                 'PositionOwnedMenuAtParent(settings, LauncherGui)', "settings.Show()",
                 'DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 0)')
    and 'DllCall("IsIconic", "Ptr", LauncherGui.Hwnd, "Int")' in launcher_smoke_tests
    and '"Restoring display settings..."' in launcher_smoke_tests,
)
update_dialogs = (ROOT / "src" / "ui" / "update-dialogs.ahk").read_text(encoding="utf-8-sig")
update_notes = (ROOT / "src" / "ui" / "update-notes.ahk").read_text(encoding="utf-8-sig")
expect(
    "Update cards scale their native controls, scrollable notes and thumb travel together",
    update_dialogs.count("CreateGoldNativePrompt(0,") == 3
    and update_dialogs.count("ShowGoldNativePrompt(") == 3
    and "ScaleOwnedMenuContent(panel, scale)" in update_dialogs
    and "AddUpdateNotesViewport(panel, releaseNotes, scale)" in update_dialogs
    and "scale := GetUpdatePromptFitScale(panel)" in update_dialogs
    and "(width - 32) / panel.NativePromptWidth" in update_dialogs
    and "(height - 32) / panel.NativePromptHeight" in update_dialogs
    and "BuildStyledReleaseNoteRows(notes, sample, width - Max(2, px(10)), premium, compactLayout, scale)" in update_notes
    and 'return kind = "heading" ? "s12 Bold cE7BE70" : "s11 Norm cF4E9D6"' in update_notes
    and "ReleaseNoteLineHeight(sample)" in update_notes
    and "GetTextMetricsW" in update_notes
    and "if y + rowHeight > bottomY" in update_notes
    and "sectionGap := compactLayout ? Max(1, px(2)) : Max(1, px(4))" in update_notes
    and 'Kind: "space"' not in update_notes
    and "96 / A_ScreenDPI" not in update_notes
    and "thumb.Move(thumbX, thumbY, thumbWidth, thumbHeight)" in update_notes,
)
expect(
    "Update footer shows circular unread badge counts at all scales and clears when viewed",
    'CreateLauncherUpdateBadge()' in bootstrap
    and 'global LauncherUpdateBadge := 0' in update_check
    and 'LauncherVersionLabel.Visible := true' in update_check
    and 'LauncherUpdateBadge := LauncherGui.Add("Picture",' in update_check
    and 'update-unread-circle.png' in update_check
    and 'LauncherUpdateNumber.OnEvent("Click", CheckForUpdates)' in update_check
    and 'LauncherUpdateBadge.Value := "*w" bitmapPixels " *h" bitmapPixels' in update_check
    and 'LauncherUpdateNumber.SetFont("s" size " Bold cFFFFFF", "Segoe UI")' in update_check
    and 'ShapeCircularUpdateBadge(LauncherUpdateBadge)' in update_check
    and 'CreateEllipticRgn' in update_check
    and 'size := Max(5, Round(9 * scale / GetLauncherBadgeDpiScale()))' in update_check
    and 'if !HasSeenUpdateAutoPreview(manifest.version)' in update_check
    and 'LauncherUpdateBadge.Visible := false' in update_check
    and 'if !wasVisible' in update_check
    and 'LauncherVersionLabel.GetPos(&labelX, , &labelWidth)' in update_check
    and 'x := labelX + labelWidth + 4' in update_check
    and 'RedrawLauncherUpdateBadge()' in update_check
    and 'LauncherUpdateBadge.OnEvent("Click", CheckForUpdates)' in update_check
    and 'IniWrite("1", path, "ReadPublishedVersions", version)' in update_check
    and 'SetLauncherUnreadBadgeNumber(unreadCount)' in update_check
    and 'LauncherUnreadBadgeDiameter(count, scale)' in update_check
    and 'GetDpiForWindow' in update_check
    and 'x" x " y689 w22 h22 +0x40 BackgroundTrans' in update_check
    and 'if width > 26' in launcher_smoke_tests
    and 'badge := panel.Add("Picture"' in launcher_smoke_tests
    and 'physical := Max(16, Round((18 + 5 * (digits - 1)) * scale))' in update_check
    and 'LauncherUpdateBadge.Move(x, centeredY, diameter, diameter)' in update_check
    and 'region := DllCall("gdi32\\CreateEllipticRgn"' in update_check
    and 'CreateRoundRectRgn' not in update_check
    and 'StartLauncherUnreadReleaseCount(AppConfig.Version, manifest.version)' in update_check
    and 'CountUnseenPublishedUpdateRecords(records, job.Installed)' in update_check
    and 'CheckUnreadPublishedReleaseCounts()' in launcher_smoke_tests
    and 'MarkPublishedVersionRead("0.1.21-alpha.4", true, fixture)' in launcher_smoke_tests
    and 'IsPublishedVersionRead("0.1.21-alpha.3", fixture)' in launcher_smoke_tests
    and 'LauncherUpdateButton' not in update_check
    and 'LauncherUpdateDismissedVersion' not in update_check
    and 'Chr(0x25CF)' not in update_check
    and 'E0C27F' not in update_check,
)
expect(
    "Published previews categorize missed changes while installed history groups hotfix versions without a redundant Hotfixes category",
    'ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion, true)' in update_dialogs
    and 'ReadInstalledCumulativeNotes(notesVersion)' in update_dialogs
    and 'ReadPublishedUpdateHistory(installedVersion, latestVersion)' in update_notes
    and 'AddPublishedNoteRecords(history.Release, records)' in update_notes
    and 'AddPublishedNoteRecords(history.Hotfix, records)' in update_notes
    and 'return BuildCategorizedUpdateNotes(records)' in update_notes
    and 'return BuildInstalledVersionNotes(records)' in update_notes
    and 'details := BuildCategorizedUpdateNotes([record], false)' in update_notes
    and 'title := "Latest Hotfix"' in update_notes
    and 'title := "Base Release"' in update_notes
    and 'NoteCategoryName(heading)' in update_notes
    and 'case "Bug Fixes", "Fixed", "Hotfixes":' in update_notes
    and 'return "Bug Fixes"' in update_notes
    and 'order := ["New Features", "Improvements", "Bug Fixes",' in update_notes
    and '"Changes in This Update"' in update_dialogs
    and 'AddUpdateNotesViewport(panel, releaseNotes, scale)' in update_dialogs
    and 'BuildPublishedPreviewSections(records)' in update_notes
    and '"Updates You Missed"' in update_dialogs
    and 'missedVersions := notes.HasOwnProp("MissedVersions") ? notes.MissedVersions : []' in update_dialogs
    and 'AddMissedUpdateLinks(preview, missedVersions, scale,' in update_dialogs
    and 'heading.GetPos(, &headingY, , &headingHeight)' in update_dialogs
    and 'rowTop := Max(rowTop, headingY + headingHeight + Max(2, px(4)))' in update_dialogs
    and 'observer.Viewport := viewport' in update_dialogs
    and 'link.OnEvent("Click", OpenMissedUpdateVersion.Bind(page, slot))' in update_dialogs
    and 'badge.OnEvent("Click", OpenMissedUpdateVersion.Bind(page, slot))' in update_dialogs
    and 'badges.Push(badge)' in update_dialogs
    and 'preview.Add("Text", "x40 y" (354 + rowExtra + notesSpace)' in update_dialogs
    and 'Prefix: "DEMO " Format("{:02}", A_Index) " — "' in bootstrap
    and 'DisplayVersion: "v" demoVersion' in bootstrap
    and 'prefix.Text := prefixText' in update_dialogs
    and 'Underline cFFF0DC' in update_dialogs
    and 'Total: versions.Length, MaxOffset: 1' in update_dialogs
    and 'clearButton := AddStyledButton(panel, px(34), markReadY, px(118), px(26),' in update_dialogs
    and 'markReadY := px(528 + topExtra + bottomExtra)' in update_dialogs
    and '"Mark Read", ClearMissedUpdateBadges.Bind(page)' in update_dialogs
    and 'observer.Clear.Visible || scrolledClearY != originalClearY' in launcher_smoke_tests
    and 'ClearMissedUpdateBadges(page, *)' in update_dialogs
    and 'MarkMissedUpdateItemRead(page, item)' in update_dialogs
    and 'MarkPublishedVersionRead(latestVersion, true)' in update_dialogs
    and 'SetLauncherDemoUnreadCount(count)' in update_dialogs
    and 'IsPublishedVersionRead(version)' in update_check
    and 'IniRead(path, "ReadPublishedVersions", version, "")' in update_check
    and 'LauncherUpdateNumber.Visible := false' in update_check
    and 'for slot in [1, 2, 3, 4]' in update_dialogs
    and 'up := AddStyledButton(panel, arrowX, arrowTop, px(20), px(22),' in update_dialogs
    and 'down := AddStyledButton(panel, arrowX, arrowBottom, px(20), px(22),' in update_dialogs
    and 'badge := panel.Add("Picture", "Hidden x0 y0 w" px(20) " h" px(20)' in update_dialogs
    and 'MeasureMissedUpdateTextWidth(row, caption)' in update_dialogs
    and 'for count in [1, 3, 7, 24]' in launcher_smoke_tests
    and 'scrolling := page.MaxOffset > 1' in update_dialogs
    and 'MissedVersions: missedVersions' in update_notes
    and 'Url: "https://github.com/IAmShawn98/tes3np/releases/tag/v" record.Version' in update_notes
    and 'metadataBorder.Move(, , , 40 + rowExtra)' in update_dialogs
    and 'A_ScriptDir "\\assets\\controls\\update-badge.png"' in update_dialogs
    and 'fullWidth := installedWidth + latestWidth + channelWidth + 2 * gap' in update_dialogs
    and 'for fontSize in [9, 8, 7, 6]' in update_dialogs
    and 'gap := 24' in update_dialogs
    and 'AddCompactUpdatePreviewMetadata(panel, installedVersion, latestVersion, channel)' in update_dialogs
    and 'PositionCompactMetadataPair(pair, x, y)' in update_dialogs
    and 'panel.SetFont("s" compactFontSize " Bold cE7BE70", "Segoe UI")' in update_dialogs
    and 'panel.SetFont("s" compactFontSize " Norm cFFF0DC", "Segoe UI")' in update_dialogs
    and '{Label: "Installed:", Value: "v" installedVersion}' in update_dialogs
    and '{Label: "Latest:", Value: "v" latestVersion}' in update_dialogs
    and '{Label: "Channel:", Value: channelName}' in update_dialogs
    and 'AddUpdateNoteTabs(' not in update_dialogs
    and 'Loop capacity - 1' in update_notes,
)
expect(
    "Production updater contains no temporary injection mode and retains confirmation guards",
    'ShowUpdatePreview(installedVersion, latestVersion, channel, kind, reviewNotes := 0)' in update_dialogs
    and 'ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion, true)' in update_dialogs
    and 'AddUpdatePreviewMetadata(preview, installedVersion, latestVersion, channel, true)' in update_dialogs
    and 'installed.GetPos(, , &installedWidth)' in update_dialogs
    and 'latest.GetPos(, , &latestWidth)' in update_dialogs
    and 'channelText.GetPos(, , &channelWidth)' in update_dialogs
    and 'if channelX + channelWidth <= rightEdge' in update_dialogs
    and 'GrowGoldNativePrompt(preview, rowExtra)' in update_dialogs
    and 'preview.Add("Text", "x21 y" (96 + rowExtra) " w558 h30 BackgroundTrans", "Changes in This Update")' in update_dialogs
    and 'AddUpdateNotesViewport(preview, notes.Latest, scale,' in update_dialogs
    and '0, rowExtra, notesSpace, true, true, hasMissed)' in update_dialogs
    and 'hasMissed := missedVersions.Length > 0' in update_dialogs
    and 'draftSections.MissedVersions := demoRows' in bootstrap
    and 'Loop 24' in bootstrap
    and 'demoVersion := Mod(A_Index, 2) ? "0.1.21-alpha" : "0.1.20-alpha"' in bootstrap
    and 'Url: GetTes3npReleasePage(demoVersion)' in bootstrap
    and 'ShowDevelopmentUnreadBadgeSample(25)' in bootstrap
    and 'draftSections.DemoMode := true' in bootstrap
    and 'CheckMissedUpdateLinkViewport()' in launcher_smoke_tests
    and 'actionY := 511 + rowExtra + notesSpace + missedSpace' in update_dialogs
    and 'missedSpace := hasMissed ? 64 : 0' in update_dialogs
    and 'bottomLimit := px(522 + topExtra + bottomExtra)' in update_dialogs
    and 'observer.RowHeight := rowHeight' in update_dialogs
    and 'AddStyledButton(preview, 109, actionY, 181, 34, "Update Now"' in update_dialogs
    and 'AddStyledButton(preview, 313, actionY, 181, 34, "Not Now"' in update_dialogs
    and 'response.Download := true, DestroyScaledMenu(preview)' in update_dialogs
    and 'CheckUpdatePreviewMetadataLayout()' in launcher_smoke_tests
    and 'Update preview metadata overlaps at this version length.' in launcher_smoke_tests
    and 'SetTimer(CheckForUpdateAvailability, -250)' in bootstrap
    and 'CanShowDevelopmentReleaseReview()' in bootstrap
    and 'ShowDevelopmentReleaseReview(*)' in bootstrap
    and 'if A_Args.Length || !RegExMatch(AppConfig.Version,' in bootstrap
    and 'FileExist(checkoutRoot "\\.git")' in bootstrap
    and 'ReadBundledVersionNotes(version)' in bootstrap
    and 'BuildPublishedPreviewSections([record])' in bootstrap
    and 'if !HasSeenUpdateAutoPreview(manifest.version)' in update_check
    and '--test-update-badge' not in launcher_smoke_tests
    and 'LauncherBadgeTest' not in update_check
    and 'LauncherBadgeTest' not in bootstrap
    and 'HandleLauncherHistoryTestMessage' not in update_check
    and '0x8041' not in bootstrap
    and '0x8042' not in bootstrap
    and 'testHistory' not in update_dialogs
    and 'synthetic' not in update_dialogs,
)
display_save = section_between(display_settings, "\nSaveLauncherDisplaySettings(", "\nAccessibilityFontSize(")
expect(
    "Display settings stage all five values before replacing the live INI",
    'FileCopy(DataFile, temporary)' in display_save
    and 'FileMove(temporary, DataFile, true)' in display_save
    and display_save.count('IniWrite(') == 5
    and display_save.rfind('IniWrite(') < display_save.find('FileMove(temporary, DataFile, true)')
    and 'IniWrite(value, DataFile' not in display_settings,
)
expect(
    "Settings match launcher scale, fit owner monitor and keep accessibility controls",
    "V016SettingsScale := GetV016SettingsFitScale()" in settings_ui
    and "fit := Min(1.0, (right - left - 24) / (512 * dpi)," in settings_ui
    and "return Max(0.1, Min(GetOwnedMenuScale(), fit))" in settings_ui
    and "return Max(7, Round(value * V016SettingsScale))" in settings_ui
    and "settings.ReadabilityControl := readability" in settings_ui
    and "reduceMotionBox := {Value: settings.SavedReduceMotion}" in settings_ui,
)
expect(
    "Manual launcher scale scrolling accounts for current UI scale",
    front_layout.count("((A_ScreenDPI / 96) * LauncherScale / 100)") >= 2
    and "scale := (A_ScreenDPI / 96) * LauncherScale / 100" in front_layout,
)
expect(
    "Game Chat uses the same upright artwork and hover renderer as other buttons",
    '#Include src\\ui\\embedded-chat.ahk' in entry_script
    and "CreateLauncherChatToggle()" in bootstrap
    and 'AddStyledButton(LauncherGui, 0, 294, 45, 112, "Game Chat", ToggleLauncherChat)' in embedded_chat
    and 'ButtonFaces[LauncherChatToggle.Hwnd].IsChatTab := true' in embedded_chat
    and 'UpdateLauncherChatHover' not in controls
    and 'PaintButtonArtwork(graphics, face, height, width, shift)' not in native_renderer
    and in_order(section_between(native_renderer, 'PaintButton(wParam,', '\nPaintButtonArtwork('),
                 'PaintButtonArtwork(graphics, face, width, height, shift)',
                 'PaintLauncherChatTab(dc, width, height, labelText, textColor, shift)')
    and section_between(embedded_chat, '\nPaintLauncherChatTab(', '\nToggleLauncherChat(').count(
        'DllCall("user32\\FrameRect"') == 2
    and 'SetLauncherHandCursor()' in section_between(native_renderer, 'ButtonWindowProc(handle,', '\nSetLauncherHandCursor()')
    and "fontHeight := -Max(9, Round(21 * paintScale))" in embedded_chat
    and "arrowHalf := Max(4, Round(9 * paintScale))" in embedded_chat
    and "arrowHeight := Max(4, Round(10 * paintScale))" in embedded_chat,
)
host_freshness = section_between(embedded_chat, "EnsureEmbeddedChatHostCurrent(host)", "\nWebView2RuntimeAvailable()")
expect(
    "Opening the source launcher never compiles ChatHost on the UI thread",
    "EnsureEmbeddedChatHostCurrent(host)" in embedded_chat
    and "RunWait(" not in host_freshness
    and "dotnet publish" not in host_freshness.replace("RunWait(dotnet publish)", "")
    and 'for pattern in ["\\*.cs", "\\tes3np.GameChat.csproj", "\\web\\*.*"]' in host_freshness
    and 'hostTime < A_LoopFileTimeModified' in host_freshness
    and 'sourceDir := A_ScriptDir "\\game-chat"' in host_freshness
    and "$hostProject = Join-Path $projectRoot 'game-chat\\tes3np.GameChat.csproj'" in windows_build
    and "$hostOutput = Join-Path $package 'chat-host'" in windows_build
    and "startup will not block on compilation" in host_freshness,
)
expect(
    "Loading transitions avoid compositor waits and restore prior critical state",
    "DwmFlush" not in loading_ui.replace("DwmFlush synchronously", "")
    and "previousCritical := A_IsCritical" in loading_ui
    and "finally Critical(previousCritical)" in loading_ui
    and "finally DestroyLoadingCard(loading)" in display_refresh,
)
expect(
    "Launcher initial sizing is hidden and subsequent displays reuse cached layout",
    '#Include src\\ui\\launcher-layout.ahk' in entry_script
    and 'LauncherGui.Show("Hide w960 h716")' in launcher_return
    and "if placement.Scale = LauncherCachedScale && DllCall" in launcher_return
    and "LauncherCachedScale := LauncherScale" in launcher_scale_apply,
)
expect(
    "Themed click recovery verifies the child under the actual pointer",
    "MouseGetPos(, , &pointerWindow, &pointerControl, 2)" in controls
    and "pointerWindow = ButtonFaces[pointerControl].Window" in controls,
)

automatic_update = section_between(
    update_check, "CheckForUpdateAvailability(*)", "\nHasSeenUpdateAutoPreview(version)"
)
expect(
    "Automatic update check must never synchronously block the launcher UI",
    'request.Open("GET", GetUpdateManifestUrl(AppConfig.Version), true)' in automatic_update
    and "request.WaitForResponse(0)" in automatic_update
    and "SetTimer(PollStartupUpdateAvailability, 100)" in automatic_update
    and "UpdateStartupRequest := request" in automatic_update
    and "request.Abort()" in automatic_update
    and "DownloadUpdateText(" not in automatic_update
    and "ParseAndValidateUpdateManifest(request.ResponseText, AppConfig.Version)" in automatic_update
    and 'request.SetTimeouts(5000, 5000, 10000, 10000)' in automatic_update
    and 'SetTimer(CheckForUpdateAvailability, -250)' in bootstrap
    and 'CanShowDevelopmentReleaseReview()' in bootstrap
    and 'ShowDevelopmentReleaseReview(*)' in bootstrap
    and 'if A_Args.Length || !RegExMatch(AppConfig.Version,' in bootstrap
    and 'FileExist(checkoutRoot "\\.git")' in bootstrap
    and 'ReadBundledVersionNotes(version)' in bootstrap
    and 'BuildPublishedPreviewSections([record])' in bootstrap,
)
expect(
    "WinForms first show stays compositor-cloaked until initial dock and saved visibility are ready",
    'const int DWMWA_CLOAK = 13;' in source
    and 'protected override void OnHandleCreated(EventArgs e)' in source
    and 'if (startupPresentationPending)\n            SetStartupWindowCloak(true);' in source
    and 'DwmSetWindowAttribute(Handle, DWMWA_CLOAK, ref value, sizeof(int))' in source
    and 'SetChatOpen(chatDisplayMode == "Always Shown");\n        // The owner, layout and saved visibility are now authoritative.' in source
    and 'startupPresentationPending = false;\n            SetStartupWindowCloak(false);' in source
    and in_order(
        source, 'SetChatOpen(chatDisplayMode == "Always Shown");', 'SetStartupWindowCloak(false);',
    ),
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
