"""Source-level guard for diagnostic privacy. No runtime log data is read."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8-sig")


def expect(condition, message):
    if not condition:
        raise SystemExit("Diagnostic privacy check failed: " + message)


diag = read("src/app/diagnostics.ahk")
# AutoHotkey v2 accepts ';' comments, not C-style '//' comment lines.
# The AHK interpreter fixture previously passed while Ahk2Exe rejected these.
expect(not any(line.lstrip().startswith("//") for line in diag.splitlines()),
       "C-style comments in AutoHotkey diagnostic source would break Ahk2Exe")
bootstrap = read("src/app/bootstrap.ahk")
session = read("src/game/session.ahk")
settings = read("src/ui/v016-refinements.ahk")
chat = read("chat-host/Program.cs")
patcher = read("src/ui/patcher.ahk")
loading = read("src/ui/loading.ahk")
updater = read("scripts/tes3np-updater.ps1")

expect('SanitizeDiagnosticText(message)' in diag,
       "launcher logger must sanitize before appending")
expect('LogLauncherEvent("PATCH | " SanitizeDiagnosticText(line))' in diag,
       "patch mirror must sanitize lines")
expect('StrReplace(text, profile.Password' in diag,
       "saved passwords must be redacted")
expect('StrReplace(text, profile.Name' not in diag,
       "public character names must remain useful in logs")
expect('RegExReplace(text' in diag and '[path omitted]' in diag
       and '[secret omitted]' in diag and '[email omitted]' in diag,
       "path/secret/email redaction must remain")
expect('SanitizeExistingDiagnosticLogs()' in diag,
       "legacy diagnostic files must be cleaned on launch")
expect('"game-chat.log"' not in diag and '"game-chat-index.json"' not in diag,
       "private Discord archive must not be mutated by log cleaner")
start = bootstrap.index("    LoadProfiles()")
scrub = bootstrap.index("    SanitizeExistingDiagnosticLogs()", start)
mirror = bootstrap.index("    InitializePatchLogMirror()", scrub)
chatstart = bootstrap.index("    SetTimer(StartEmbeddedInGameChat", mirror)
expect(start < scrub < mirror < chatstart,
       "privacy scrub must follow profile loading and precede ChatHost")
expect('content := SanitizeDiagnosticText(FileRead(path, "UTF-8"))' in settings,
       "launcher clipboard exports must redact previously recorded logs")
expect('report .= SanitizeDiagnosticText(content)' in settings,
       "Expansion Pack clipboard exports must redact")
expect('A_Clipboard := SanitizeDiagnosticText(report)' in settings,
       "combined report must be redacted at final clipboard boundary")
expect("'Source: ' + $match.ProviderName, $match.Message" not in settings,
       "raw Windows crash event descriptions must never be copied")
expect('void Log(string message)' in chat and 'File.AppendAllText(logPath' in chat
       and 'ChatBuild + " | " + safe +' in chat,
       "C# Chat Host must write redacted diagnostic messages")
expect('Log("Navigation completed: " + url)' not in chat,
       "Chat Host must not log arbitrary navigation URLs")
expect('Log("ERROR " + ex);' not in chat,
       "Chat Host must not log full exception stacks")
expect('string GameChatIndexFile' in chat and 'WriteChatArchiveAtomically' in chat,
       "private chat archive functionality must remain intact")
expect('"GAME | CLIENT | Mode: "' in session and 'Executable path omitted.' in session,
       "client executable paths must not be exposed in game log")
expect('LogLauncherEvent("GAME | SUCCESS | Login completed | Character: "' in session,
       "public in-game character names must remain available for troubleshooting")
expect('LogLauncherEvent("GAME | ERROR | Client launch/login exception: " err.Message' not in session,
       "session exception messages must not be logged raw")
expect('SanitizeDiagnosticText(RegExReplace(text' in patcher,
       "patch error detail sink must call common redactor")
expect('detail := "Error type: " Type(err)' in loading,
       "renderer error log must not record raw exception paths")
expect("function Write-UpdaterLog([string]$Message)" in updater and
       "[regex]::Replace($Message" in updater and "'[path omitted]'" in updater
       and "Add-Content -LiteralPath $LogFile" in updater and
       "' | UPDATE WORKER | ' + $safe" in updater,
       "standalone update worker must sanitize before writing launcher.log")

print("PASS | TES3NP diagnostic privacy source contracts")
