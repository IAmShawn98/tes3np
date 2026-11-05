"""Source-level guard for private diagnostic sinks. No user logs are read."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8-sig")


def expect(condition, message):
    if not condition:
        raise SystemExit("Diagnostic privacy check failed: " + message)


diag = read("src/app/diagnostics.ahk")
bootstrap = read("src/app/bootstrap.ahk")
session = read("src/game/session.ahk")
settings = read("src/ui/v016-refinements.ahk")
chat = read("chat-host/Program.cs")
patcher = read("src/ui/patcher.ahk")
loading = read("src/ui/loading.ahk")
updater = read("scripts/tes3np-updater.ps1")

expect(not any(line.lstrip().startswith("//") for line in diag.splitlines()),
       "C-style comments in AutoHotkey diagnostic source would break Ahk2Exe")
expect('SanitizeDiagnosticText(message)' in diag,
       "launcher logger must sanitize before appending")
expect('LogLauncherEvent("PATCH | " SanitizeDiagnosticText(line))' in diag,
       "patch mirror must sanitize lines")
expect('StrReplace(text, profile.Password' in diag,
       "saved passwords must be excluded from diagnostics")
expect('StrReplace(text, profile.Name' not in diag,
       "public character names must remain in logs")
expect('RegExReplace(item' in diag and 'StrSplit(line, "|")' in diag
       and 'Password|Token|Secret' in diag and 'item := Trim(item' in diag,
       "AHK diagnostics must remove private fields and compact pipe separators")
expect('PrivacyScrubVersion", "") = "2"' in diag and 'IniWrite("2"' in diag,
       "historical diagnostic logs must be rescrubbed under version 2")
expect('"[path omitted]"' not in diag and '"[secret omitted]"' not in diag,
       "AHK diagnostics must not introduce privacy placeholders")
expect('SanitizeExistingDiagnosticLogs()' in diag,
       "legacy diagnostic files must be cleaned on launch")
expect('"game-chat.log"' not in diag and '"game-chat-index.json"' not in diag,
       "private Discord archive must not be modified by log cleanup")
start = bootstrap.index("    LoadProfiles()")
scrub = bootstrap.index("    SanitizeExistingDiagnosticLogs()", start)
mirror = bootstrap.index("    InitializePatchLogMirror()", scrub)
chatstart = bootstrap.index("    SetTimer(StartEmbeddedInGameChat", mirror)
expect(start < scrub < mirror < chatstart,
       "privacy scrub must follow profile loading and precede ChatHost")
expect('content := SanitizeDiagnosticText(FileRead(path, "UTF-8"))' in settings
       and 'report .= SanitizeDiagnosticText(content)' in settings
       and 'A_Clipboard := SanitizeDiagnosticText(report)' in settings,
       "clipboard diagnostics must pass through the common sanitizer")
expect("'Source: ' + $match.ProviderName, $match.Message" not in settings,
       "raw Windows crash descriptions must not be exported")
expect('Sanitized diagnostic log copied' not in settings
       and 'description omitted for privacy' not in settings,
       "diagnostic UI must not contain privacy placeholder notices")
expect('void Log(string message)' in chat and 'File.AppendAllText(logPath' in chat
       and 'string.Join(" | ", parts)' in chat
       and 'ChatBuild + " | " + safe +' in chat
       and '"[path omitted]"' not in chat,
       "Chat Host must remove private fields and retain compact event text")
expect('Log("Navigation completed: " + url)' not in chat
       and 'Log("ERROR " + ex);' not in chat,
       "Chat Host must not log raw URLs or exceptions")
expect('string GameChatIndexFile' in chat and 'WriteChatArchiveAtomically' in chat,
       "private game chat archive must remain intact")
expect('"GAME | CLIENT | Mode: "' in session
       and 'Executable path omitted.' not in session
       and 'Password value not logged.' not in session,
       "game log must preserve useful state without privacy notices")
expect('LogLauncherEvent("GAME | SUCCESS | Login completed | Character: "' in session,
       "public in-game character names must remain")
expect('LogLauncherEvent("GAME | ERROR | Client launch/login exception: " err.Message' not in session,
       "raw session exception details must not be logged")
expect('return SanitizeDiagnosticText(text)' in patcher,
       "patch diagnostics must reuse common cleaner")
expect('detail := "Error type: " Type(err)' in loading,
       "renderer error log must not record raw exception paths")
expect("function Write-UpdaterLog([string]$Message)" in updater
       and "[regex]::Replace($Message" in updater
       and "$safe -split" in updater
       and "'[path omitted]'" not in updater
       and "Add-Content -LiteralPath $LogFile" in updater
       and "' | UPDATE WORKER | ' + $safe" in updater,
       "standalone updater must clean private fields without placeholders")

print("PASS | TES3NP diagnostic privacy source contracts (clean fields)")
