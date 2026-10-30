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
    "Local AppData may only be read as a legacy Happy Hour marker",
    source.count("SpecialFolder.LocalApplicationData") == 1
    and "LegacyHappyHourSeenFile = Path.Combine(" in source
    and "File.Move(LegacyHappyHourSeenFile, happyHourSeenFile)" in source,
)
for name, expected in {
    "gameChatLogDirectory": 'Path.Combine(ChatDataRoot, "Logs")',
    "happyHourSeenFile": 'Path.Combine(\n            ChatDataRoot, "happy-hour-last-seen.txt")',
    "chatModeFile": 'Path.Combine(ChatDataRoot, "chat-display-mode.txt")',
    "logPath": 'Path.Combine(ChatDataRoot, "chat-host.log")',
}.items():
    expect(f"{name} must use canonical Roaming AppData", expected in source)
expect(
    "WebView2 profile must be under the canonical data root",
    'Path.Combine(ChatDataRoot, "chat-webview2")' in source,
)
expect(
    "Fresh profile must not reimport a stale Local AppData marker",
    "hadSavedChatArchiveAtStartup =" in source
    and "hadSavedChatArchiveAtStartup &&" in source,
)
expect(
    "Last-seen marker must never create a detected event",
    "ulong candidate = LatestArchivedHappyHourId();" in source
    and "Math.Max(archivedId, previouslyVerifiedId)" not in source,
)
expect(
    "No generated Happy Hour announcements or obsolete demo storage",
    "ShowHappyHourAlert(0" not in source
    and "happyHourDemoSeenFile" not in source
    and "bool happyHourDemo" not in source,
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

print("Chat Host contracts verified: canonical Roaming AppData, auth gate, "
      "real-only Happy Hour detection, and atomic chat archive writes.")
