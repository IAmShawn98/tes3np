"""Source-level guard for private diagnostic sinks. No user logs are read."""
from pathlib import Path

from game_chat_source import read_game_chat_sources

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
chat = read_game_chat_sources(ROOT)
patcher = read("src/ui/patcher.ahk")
loading = read("src/ui/loading.ahk")
updater = read("scripts/tes3np-updater.ps1")
importer = read("scripts/import-expansion-pack.ps1")
toggle = read("scripts/toggle-expansion-pack.ps1")
picker = read("scripts/select-expansion-package.ps1")
upload = read("src/ui/expansion-upload.ahk")
fixture = read("scripts/test-diagnostic-privacy.ahk")
macros = read("src/ui/macros.ahk")
characters = read("src/ui/characters.ahk")
happyhour = read("src/ui/happy-hour.ahk")

expect(not any(line.lstrip().startswith("//") for line in diag.splitlines()),
       "C-style comments in AutoHotkey diagnostic source would break Ahk2Exe")
expect('SanitizeDiagnosticText(message)' in diag,
       "launcher logger must sanitize before appending")
expect('StrReplace(text, profile.Password' in diag,
       "saved passwords must be excluded from diagnostics")
expect('StrReplace(text, profile.Name' not in diag,
       "public character names must remain in logs")
expect('RegExReplace(item' in diag and 'StrSplit(line, "|")' in diag
       and 'Password|Token|Secret' in diag and 'item := Trim(item' in diag,
       "AHK diagnostics must remove private fields and compact pipe separators")
expect('PrivacyScrubVersion", "") = "4"' in diag and 'IniWrite("4"' in diag,
       "historical diagnostic logs must be rescrubbed under version 4")
expect('static firstWriteChecked := false' in diag and 'previous.Pos := previous.Length - 1' in diag,
       "first new event must detect and separate unterminated historical logs")
expect('safe := RTrim(safe, "`r`n") "`n"' in diag,
       "migrated diagnostic files must end with a newline")
expect('RegExReplace(text, "\\.(?=' in diag and 'Launcher startup beginning.`n2026-11-04' in fixture,
       "old timestamp joins must be repaired during migration and covered by fixture")
expect('windowsUser := EnvGet("USERNAME")' in diag
       and '\\Q" windowsUser "\\E' in diag
       and '!RegExMatch(item, "i)^Character\\s*:")' in diag,
       "standalone Windows usernames must be filtered but public characters kept")
expect('"[path omitted]"' not in diag and '"[secret omitted]"' not in diag,
       "AHK diagnostics must not introduce privacy placeholders")
expect('SanitizeExistingDiagnosticLogs()' in diag,
       "legacy diagnostic files must be cleaned on launch")
expect('"game-chat.log"' not in diag and '"game-chat-index.json"' not in diag,
       "private Discord archive must not be modified by log cleanup")
start = bootstrap.find("    LoadProfiles()")
scrub = bootstrap.find("    SanitizeExistingDiagnosticLogs()", start)
chatstart = bootstrap.find("    SetTimer(StartEmbeddedInGameChat", scrub)
expect(0 <= start < scrub < chatstart,
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
expect('Regex.Escape(windowsUser)' in chat and 'Environment.UserName' in chat,
       "Chat Host must clean standalone Windows account names")
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
expect('SanitizeDiagnosticText(err.Message)' in patcher
       and 'SanitizeDiagnosticText(message)' in patcher,
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
expect('[Environment]::UserName' in updater and "Write-Error $message" not in updater,
       "updater logs and console must not reveal Windows usernames or raw errors")
expect("function CleanImportMessage([string]$Message)" in importer
       and "$clean = CleanImportMessage $Message" in importer
       and "'Backup=' + $backupStatus" in importer
       and "[IO.File]::Exists((Join-Path $Backup 'journal.json'))" in importer
       and "'Backup=' + $Backup" not in importer
       and "WriteJobIni 'result.ini' $body" in importer,
       "import result must retain atomic publishing but omit raw errors and backup paths")
expect("function CleanToggleError([string]$Message)" in toggle
       and "(CleanToggleError $_.Exception.Message)" in toggle
       and "WriteAllText($ResultFile,$_.Exception.Message" not in toggle,
       "Expansion toggle result must not contain raw exceptions")
expect("$diagnostic = 'Native Expansion Pack picker failed (" in picker
       and ".GetBaseException().Message" not in picker
       and "Write-Host $diagnostic" in picker,
       "picker error file and console must use safe category and HRESULT")
expect('reason := SanitizeDiagnosticText(err.Message)' in upload
       and 'details := FileExist(output) ? SanitizeDiagnosticText(' in patcher
       and 'message := SanitizeDiagnosticText(message)' in patcher,
       "Expansion Pack dialogs must clean incoming worker errors")
expect('EnvSet("USERNAME", "ExamplePerson")' in fixture
       and 'PrivacyScrubVersion", "") = "4"' in fixture,
       "disposable runtime fixture must cover account names and migration")
expect('sameName = "GAME | Character: ExamplePerson"' in fixture,
       "test must preserve public names even if they equal Windows account")
expect('detail := SanitizeDiagnosticText(err.Message)' in macros
       and '"[path omitted]"' not in macros,
       "macro import errors must be private and free of placeholders")
expect('reason := SanitizeDiagnosticText(err.Message)' in characters,
       "custom portrait errors must not display raw machine paths")
expect('missing: " asset' not in happyhour,
       "Happy Hour missing-artwork logs must not include private install paths")

print("PASS | TES3NP diagnostic privacy source contracts (clean fields)")
