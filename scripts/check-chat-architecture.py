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
errors = []


def expect(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


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
expect(
    "Happy Hour display must require an authenticated Discord channel",
    "if (!discordChannelReady || activationId == 0) return;" in source
    and "if (!discordChannelReady) return;" in source
    and "SuspendHappyHourUntilDiscordReturns" in source,
)
expect(
    "Only real Discord snowflake IDs may determine expiry",
    "DiscordTimestamp(activationId).AddHours(1)" in source,
)
expect(
    "Archive must be written with replace-on-complete semantics",
    "WriteChatArchiveAtomically(GameChatIndexFile," in source
    and "WriteChatArchiveAtomically(GameChatLogFile," in source
    and "File.Move(temporary, path, true);" in source,
)
expect(
    "Happy Hour banner must track launcher movement without a timer delay",
    "void PositionHappyHourBanner()" in source
    and "SetWindowPos(banner.Handle, IntPtr.Zero, x, y, width, height," in source
    and "PositionHappyHourBanner();\n                if (repositionQueued) return;" in source
    and "SetWinEventHook(0x800B, 0x800B" in source,
)
expect(
    "Banner must stay owned by launcher and retain movement polling fallback",
    "SetNativeWindowOwner(banner.Handle, owner);" in source
    and "void PositionChatWindows()\n        {\n            // The existing chat polling is a safety net" in source
    and "bounds.Top - 48" in source,
)



expect(
    "Full AppData reset must stop ChatHost before deletion",
    reset_ui.index("StopEmbeddedInGameChat()") >= 0
    and reset_ui.index("StopEmbeddedInGameChat()") < reset_ui.index("DirDelete(AppDataDirectory, true)"),
)
expect(
    "Reset shutdown must not recreate Roaming logs or scheduler settings",
    "LauncherDataResetting := true" in reset_ui
    and "if !LauncherDataResetting" in bootstrap
    and "ExitApp()" in reset_ui,
)
expect(
    "Reset mode must be part of centralized launcher state",
    "global LauncherDataResetting := false" in app_state,
)

if errors:
    print("Chat Host architectural contract violations:")
    for error in errors:
        print(" - " + error)
    sys.exit(1)

print("Chat Host contracts verified: Roaming AppData, authenticated real-only "
      "Happy Hour banner, native movement, and atomic chat archive writes.")
