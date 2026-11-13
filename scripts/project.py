"""Dependency-free source checks and release packaging; never execute game code."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".ahk", ".ps1", ".py", ".md", ".yml", ".json"}
SKIP_DIRS = {".git", ".venv", ".vscode", ".idea", "__pycache__", "dist", "build", "bin", "obj"}
REQUIRED_ASSETS = (
    "backgrounds/launcher.png", "backgrounds/character-book.png",
    "controls/scroll-panel.png", "controls/button.png",
    "headings/quest.png", "headings/together.png", "icons/tes3np.ico",
)


def project_files() -> list[Path]:
    """Exclude operational data even if somebody accidentally copies it locally."""
    files = []
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if not path.is_file() or any(part in SKIP_DIRS for part in relative.parts):
            continue
        if path.suffix.lower() in {".log", ".tmp", ".bak", ".zip", ".pyc"}:
            continue
        if path.name.lower().endswith(".ini") or path.name.startswith(".env"):
            continue
        if relative.parts[0] == "client":
            continue
        if any(part in {"patch-jobs", "macros"} for part in relative.parts[:-1]):
            continue
        if path.suffix.lower() == ".exe" and relative.as_posix() != "patches/markerless/tes3mp.exe":
            continue
        files.append(path)
    return sorted(files)


def ahk_tokens(text: str) -> str:
    """Mask comments and strings for structural checks, keeping line numbers.

    This supports the source's ordinary quoted strings and comments. It is not
    an AutoHotkey parser and must not be advertised as runtime validation.
    """
    output = []
    quote = ""
    comment = False
    block = False
    index = 0
    while index < len(text):
        char = text[index]
        pair = text[index:index + 2]
        if block:
            if pair == "*/":
                output.extend("  ")
                index += 2
                block = False
                continue
            output.append("\n" if char == "\n" else " ")
        elif comment:
            output.append("\n" if char == "\n" else " ")
            if char == "\n":
                comment = False
        elif quote:
            if char == "`" and index + 1 < len(text):
                output.extend("  ")
                index += 2
                continue
            if char == quote:
                quote = ""
            output.append("\n" if char == "\n" else " ")
        elif char in {"'", '"'}:
            quote = char
            output.append(" ")
        elif pair == "/*":
            output.extend("  ")
            index += 2
            block = True
            continue
        elif char == ";":
            comment = True
            output.append(" ")
        else:
            output.append(char)
        index += 1
    if quote or block:
        raise ValueError("Unterminated string or block comment")
    return "".join(output)


def check(allow_missing_payload: bool = False) -> None:
    errors = []
    declarations = {}
    files = project_files()
    for asset in REQUIRED_ASSETS:
        if not (ROOT / "assets" / asset).is_file():
            errors.append(f"Missing required artwork: assets/{asset}")
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        if relative.startswith("patches/") or path.suffix not in TEXT_SUFFIXES:
            continue
        text = path.read_text(encoding="utf-8-sig")
        if any(line.rstrip() != line for line in text.splitlines()):
            errors.append(f"{relative}: trailing whitespace")
        if not text.endswith("\n"):
            errors.append(f"{relative}: missing final newline")
        if path.suffix != ".ahk":
            continue
        try:
            tokens = ahk_tokens(text)
            stack = []
            for position, char in enumerate(tokens):
                if char in "({[":
                    stack.append(char)
                elif char in ")}]":
                    if not stack or stack.pop() != dict(zip(")}]", "({["))[char]:
                        raise ValueError(f"Mismatched delimiter at line {tokens[:position].count(chr(10)) + 1}")
            if stack:
                raise ValueError("Unclosed delimiter")
            for match in re.finditer(r"(?m)^(\w+)\([^\n]*\)\s*\n\{", tokens):
                # The standalone fixture intentionally defines inert versions
                # of functions from the full launcher. They must not count as
                # duplicates: only the real executable's includes define its
                # production function namespace. Still check fixture syntax,
                # balance, whitespace and #Include paths above/below.
                if relative == "scripts/test-expansion-diagnostics.ahk":
                    continue
                name = match[1].lower()
                if name in declarations:
                    errors.append(f"{relative}: duplicate function {match[1]} ({declarations[name]})")
                declarations[name] = relative
            for match in re.finditer(r"(?i)\b(buffer|gui|map|array)\s*:=\s*\1\s*\(", tokens):
                errors.append(f"{relative}: local name shadows {match[1]} constructor")
            for match in re.finditer(r"(?m)^#Include\s+(.+)$", text):
                include_text = match[1].strip().replace("\\", "/")
                # Existing application includes are rooted at the repo;
                # standalone diagnostic fixture scripts may include their
                # neighbor paths relative to the file containing #Include.
                include = ROOT / include_text
                if not include.is_file():
                    include = path.parent / include_text
                if not include.is_file():
                    errors.append(f"{relative}: missing include {match[1]}")
        except ValueError as error:
            errors.append(f"{relative}: {error}")
    # Retired scheduler and unreachable launch-all feature: no live
    # compilation root, orphan callback or persisted event transfer should
    # silently reintroduce automated logins or a hidden UI control.
    retired_names = (
        "daily-login-scheduler.ahk", "LoadDailyLoginSchedule",
        "ScheduledEvents", "ScheduledEvent", "ScheduledDailyLogin",
        "ScheduledLoginAction", "ScheduledCountdown", "ShowMissedScheduledEvents",
        "GetScheduledEvent", "MarkScheduledDailyLoginComplete",
        "CancelScheduledDailyLoginForToday", "SaveScheduledEventShutdownTime",
        "OpenScheduledEvents", "CloseScheduledEventsBook",
        "V016DailyLoginControls", "OpenDailyLoginScheduleSettings",
        "LaunchAllCharacters", "ShowLaunchAllExplanation",
        "AcceptLaunchAllExplanation", "LaunchCharacterButton",
        "HideLaunchAllExplanation", "ClaimWaitMs",
        "OpenTroubleshooting", "OpenLauncherLog", "ClearLauncherLog",
        "CopyLauncherDiagnostics", "BuildLauncherDiagnostics",
        "ResetDisplayAccessibility",
        # Dead preview chat window replaced by the embedded authenticated host.
        "OpenInGameChatWindow", "ResizeInGameChatWindow",
        "OpenInGameDiscordChannel", "InGameChatGui",
        # Unreachable startup dialog / old message handler.
        "ShowStartupChoice", "LaunchFromStartup", "ManageFromStartup",
        "OpenFromStartup", "LauncherChatCommandClick",
        # Retired intermediate UI helper and checkbox toggle variants.
        "AddMagicCardsInteractiveLabel", "ToggleV016ReadabilityParts",
        "ToggleV016FollowWindows",
        # First-run scanner/status overlay superseded by CheckFirstRunMorrowind.
        "OfferFirstRunSetup", "BeginGameDetectionDisplay",
        "EndGameDetectionDisplay", "RefreshGameDetectionText",
        "GameDetectionActive", "LauncherHelpText",
        # More dynamically unreachable legacy aliases / redundant implementations.
        "CheckModifiedClientForPatch", "ShouldSkipMarkerless",
        "BundledMarkerlessHash", "ConfirmInstalledUpdate",
        "HasSavedCharacters", "OpenMacros",
        "IsTES3MPSetupComplete", "BeginStartupPatchCheck",
        # Unused proprietary bitmap-font rasterizer path replaced by
        # the bundled native Mystic Cards TrueType font.
        "FindVanillaMagicCardsFont", "ReadMagicCardsTextureName",
        "LoadMagicCardsBitmapFont", "MagicCardsMeasureText",
        "MagicCardsGlyphRun", "MagicCardsCreateGlyphAtlas",
        "MagicCardsGlyphSourceRect", "MagicCardsWrapText",
        "MagicCardsRenderText", "MagicCardsBufferToHBitmap",
        "AddMagicCardsText", "LauncherMagicCardsData",
        "LauncherMagicCardsFnt", "LauncherMagicCardsTex",
        # Removed executable textbox and its disconnected Browse/save handlers.
        "ExecutableInput", "BrowseSharedExecutable", "SaveSharedExecutable",
        # Retired bundled v0.1 Install/Repair UI and worker callbacks.
        "OpenPatcher", "ClosePatcher", "StartPatchAction", "StartPatchWorker",
        "BrowsePatchFolder", "BrowsePatchConfiguration", "PatchPage",
        "PatchStatus", "PatchTesInput", "PatchMorrowindInput",
        "PatchConfigInput", "PatchApplyButton", "PatchVerifyButton",
        "PatchRestoreButton", "ReportPatchError", "FullPatchPath",
        "QuotePatchArgument", "WindowsPatchError",
    )
    if (ROOT / "src/app/daily-login-scheduler.ahk").exists():
        errors.append("Retired scheduler module must not be restored.")
    for source in [ROOT / "tes3np.ahk", *sorted((ROOT / "src").rglob("*.ahk")), ROOT / "scripts/test-expansion-diagnostics.ahk"]:
        content = source.read_text(encoding="utf-8-sig")
        for name in retired_names:
            if name.lower() in content.lower():
                errors.append(
                    f"{source.relative_to(ROOT)}: retired feature reference {name}"
                )
        if re.search(r"\bClient\.Queue\b", content):
            errors.append(f"{source.relative_to(ROOT)}: retired batch queue reference")
    # A retired scheduler must stay removed from ALL executable sources, not
    # only the AHK include graph. The words here are forbidden identifiers,
    # not a literal search for comments about scheduler retirement.
    inactive_scheduler_identifiers = (
        "LoadDailyLoginSchedule", "ScheduledDailyLogin",
        "OpenScheduledEvents", "ScheduledLoginAction",
        "MarkScheduledDailyLoginComplete", "CancelScheduledDailyLoginForToday",
        "SaveScheduledEventShutdownTime",
    )
    executable_secondary_sources = [
        ROOT / "chat-host/Program.cs",
        *sorted((ROOT / "scripts").glob("*.ps1")),
    ]
    for secondary in executable_secondary_sources:
        secondary_text = secondary.read_text(encoding="utf-8-sig")
        for symbol in inactive_scheduler_identifiers:
            if symbol.lower() in secondary_text.lower():
                errors.append(
                    f"{secondary.relative_to(ROOT)}: retired scheduler reference {symbol}"
                )
    # The old v0.1 repair path is retired, but the shared import monitor,
    # Morrowind discovery, configuration toggling, and backup import stay live.
    if (ROOT / "scripts/patch-tes3mp.ps1").exists():
        errors.append("Legacy bundled Install/Repair worker was restored.")
    if (ROOT / "patches/expansion-pack").exists():
        errors.append("Obsolete Expansion Pack payload must not be stored in source.")
    resource_generator = (ROOT / "scripts/generate-bundled-resources.py").read_text(encoding="utf-8-sig")
    # The historical v0.1 files may remain in source history, but they are
    # no longer runtime or release dependencies.
    manifest_payload = json.loads((ROOT / "patches/manifest.json").read_text(encoding="utf-8-sig"))
    if [item["Path"] for item in manifest_payload["Files"]] != ["markerless/tes3mp.exe"]:
        errors.append("Release manifest must not require legacy Expansion Pack payload.")
    if 'for directory in ("assets",):' not in resource_generator:
        errors.append("Executable resource generator is bundling non-runtime patch payloads.")
    build_source = (ROOT / "scripts/build-windows.ps1").read_text(encoding="utf-8-sig")
    if "@('tes3np.ahk','src','assets','scripts')" not in build_source or "test-expansion-toggle.ps1" not in build_source:
        errors.append("Windows release build must omit old patch staging and test installed-only toggles.")

    patcher = (ROOT / "src/ui/patcher.ahk").read_text(encoding="utf-8-sig")
    if not all(token in patcher for token in ("VerifiedEspPath", "VerifiedEspSHA256", "SHA256File(esp) = verifiedHash")):
        errors.append("Expansion Pack state must verify imported ESP location and SHA-256.")
    upload = (ROOT / "src/ui/expansion-upload.ahk").read_text(encoding="utf-8-sig")
    bootstrap = (ROOT / "src/app/bootstrap.ahk").read_text(encoding="utf-8-sig")
    mismatch_ui = (ROOT / "src/game/expansion-mismatch.ahk").read_text(encoding="utf-8-sig")
    session_code = (ROOT / "src/game/session.ahk").read_text(encoding="utf-8-sig")
    if not all(token in mismatch_ui for token in (
        "Never hide the diagnostic behind Discord authentication",
        'AddStyledButton(dialog, 25, 475, 210, 33, "Connect / Retry"',
        'ExpansionDiscordPromptPending := 0',
        'Sign in through Game Chat to view the latest official Expansion Pack ZIP',
        'AddStyledButton(dialog, 300, 574, 180, 38,',
        '"Repair / Install ZIP"',
    )):
        errors.append("Expansion Pack dialog must always open, support retries, and clear pending authentication.")
    if 'Open Expansion Pack Downloads' not in (ROOT / "src/app/bootstrap.ahk").read_text(encoding="utf-8-sig"):
        errors.append("Expansion Pack downloads need a persistent reopen entry in the tray.")
    if 'case 12: RetryAuthenticatedExpansionPrompt' not in (ROOT / "chat-host/Program.cs").read_text(encoding="utf-8-sig"):
        errors.append("Game Chat retry command must remain available after a pending auth request.")
    if not all(token in session_code for token in ("MismatchExitGraceUntil", "MismatchWindowGraceUntil")):
        errors.append("Game exit/window loss must allow a bounded fresh-log mismatch capture.")

    expected_import = (
        '"patch-tes3mp.ps1"' not in resource_generator
        and 'UploadExpansionFromFile(args*)' in upload
        and 'StartExpansionImportWorker(package, morrowind, config)' in upload
        and 'SetTimer(CheckPatchWorker, 50)' in upload
        and 'CheckPatchWorker()' in patcher
        and 'if job.Action != "Import"' in patcher
        and 'MsgBox(message, "Upload Expansion"' in patcher
        and 'PatchInProgress()' in patcher
        and 'FindMorrowindFolder(config)' in patcher
        and 'PatchConfigurationPath()' in patcher
        and 'ToggleExpansionPack(*)' in patcher
        and 'CanUseNPLauncher()' in patcher
        and 'GuardPatchExit(*)' in patcher
        and 'A_TrayMenu.Add("Optional Expansion Pack", OpenPatcher)' not in bootstrap
    )
    if not expected_import:
        errors.append("Retiring legacy repair broke a live Expansion Pack/import or launcher dependency.")
    session = (ROOT / "src/game/session.ahk").read_text(encoding="utf-8-sig")
    root_source = (ROOT / "tes3np.ahk").read_text(encoding="utf-8-sig")
    refinements = (ROOT / "src/ui/v016-refinements.ahk").read_text(encoding="utf-8-sig")
    main_menu = (ROOT / "src/ui/front-page.ahk").read_text(encoding="utf-8-sig")
    if not (
        "StartProfileSession(profile, executable)" in session
        and "CanStartAnotherTES3NPGame()" in session
        and 'MenuEntries.Push(["Launch " Profiles[SelectedProfile].Name, LaunchProfile])' in main_menu
        and "SetBookControlVisible(control, visible)" in refinements
        and "if !LauncherDataResetting" in (ROOT / "src/app/bootstrap.ahk").read_text(encoding="utf-8-sig")
        and "#Include src\\ui\\v016-refinements.ahk" in root_source
    ):
        errors.append("Retired feature cleanup broke an active launcher/UI dependency.")

    # The retired executable textbox is gone. Selecting a game client is
    # handled by the live Game Client Settings workflow, not by a stale GUI
    # input. Protect that workflow and imported-pack persistence.
    client_ui = (ROOT / "src/ui/v016-refinements.ahk").read_text(encoding="utf-8-sig")
    client_settings = (ROOT / "src/data/settings.ahk").read_text(encoding="utf-8-sig")
    client_detection = (ROOT / "src/app/client-detection.ahk").read_text(encoding="utf-8-sig")
    portable_backup = (ROOT / "src/data/backup.ahk").read_text(encoding="utf-8-sig")
    client_contract = (
        'AddStyledButton(menu, 30, 190, 620, 40, "Set Up Custom EXE", (*) => ConfigureCustomClientV016(menu))' in client_ui
        and 'AddStyledButton(menu, 30, 238, 620, 40, "Use Saved Custom Client", (*) => ActivateSavedCustomClientV016(menu))' in client_ui
        and 'AddStyledButton(menu, 30, restoreY, 620, 40, "Use Original TES3MP Client", (*) => RestoreBundledClientV016(menu))' in client_ui
        and 'reactivate.Visible := saved' in client_ui
        and 'reactivate.Enabled := saved' in client_ui
        and 'restoreY := saved ? 286 : 238' in client_ui
        and 'initialHeight := saved ? 460 : 412' in client_ui
        and 'RefreshGameClientSettingsLayoutV016(menu)' in client_ui
        and 'IniWrite("CustomOverrides", DataFile, "Launch", "ClientMode")' in client_ui
        and 'IniWrite("Bundled", DataFile, "Launch", "ClientMode")' in client_ui
        and "InstallCustomClientOverrides(source, folder)" in client_ui
        and 'AddStyledButton(settings, V016S(266), V016S(435), V016S(214), V016S(30), "Game Client Settings", OpenClientSelectionSettings)' in client_ui
        and 'OpenClientSelectionSettings(*)' in client_ui
        and 'mode := IniRead(DataFile, "Launch", "ClientMode", "Bundled")' in client_settings
        and 'if mode = "CustomOverrides"' in client_settings
        and 'return GetMergedCustomClientExecutable()' in client_settings
        and 'return A_ScriptDir "\\client\\tes3mp.exe"' in client_settings
        and "GetSharedExecutable()" in client_settings
        and "InstallCustomClientOverrides(source, dependencies := \"\")" in client_detection
        and 'IniWrite(executable, temporary, "Launch", "Executable")' in portable_backup
        and 'FileMove(temporary, DataFile, true)' in portable_backup
        and 'An old executable path was unavailable. Use Launcher Settings > Game Client Settings' in portable_backup
    )
    if not client_contract:
        errors.append("Live Game Client Settings, client executable resolution, or backup persistence was lost.")

    # The Enhanced Readability control remains a live callback in Launcher
    # Settings. Its native label updater was incorrectly deleted in an audit;
    # protect the full control -> callback -> state -> text dependency chain.
    readability_contract = (
        'readability.OnEvent("Click", ToggleV016ReadabilityControl.Bind(readability))' in refinements
        and "ToggleV016ReadabilityControl(control, *)" in refinements
        and "UpdateV016ReadabilityLabel(control, V016ReadabilityState)" in refinements
        and "UpdateV016ReadabilityLabel(control, state)" in refinements
        and 'try control.Text := V016CheckLabel(state, "Enhanced readability")' in refinements
        and 'readability.Text := V016CheckLabel(0, "Enhanced readability")' in refinements
    )
    if not readability_contract:
        errors.append("Enhanced Readability callback or checkbox label updater is missing.")

    # Favorite-selection source contract: ensure the first saved character is
    # checked, the switch explanation appears once (regardless of answer),
    # and legacy loads/imports cannot strand a nonempty list without a favorite.
    character_ui = (ROOT / "src/ui/characters.ahk").read_text(encoding="utf-8-sig")
    settings_ui = (ROOT / "src/data/settings.ahk").read_text(encoding="utf-8-sig")
    backup_ui = (ROOT / "src/data/backup.ahk").read_text(encoding="utf-8-sig")
    favorite_checks = {
        "first character auto-favorite": (
            "if Profiles.Length = 1 || SelectedProfile < 1" in character_ui
            and "SelectedProfile := 1" in character_ui
        ),
        "favorite switch explains once and remembers either answer": (
            'IniRead(DataFile, "Launcher", "HideFavoriteSwitchExplanation", "0") != "1"' in character_ui
            and 'result := MsgBox(prompt, "Favorite character", 0x124)' in character_ui
            and 'IniWrite("1", DataFile, "Launcher", "HideFavoriteSwitchExplanation")' in character_ui
            and 'if result != "Yes"\n            return' in character_ui
            and character_ui.index('result := MsgBox(prompt, "Favorite character", 0x124)')
            < character_ui.index('IniWrite("1", DataFile, "Launcher", "HideFavoriteSwitchExplanation")')
            < character_ui.index("    SelectedProfile := index\n    SaveDefaultProfile()")
        ),
        "favorite description and newly approved compact layout stay aligned": (
            'descriptionText := "This is a list of all your characters.' in character_ui
            and 'does not impact them in-game!"' in character_ui
            and 'CharacterDescription.Move(BookS(70), BookS(80), BookS(390), BookS(81))' in character_ui
            and 'y := 164 + (index - 1) * 24' in character_ui
            and 'actionY := Profiles.Length ? 540 : 164' in character_ui
            and "Click on the tick box before one of your characters" not in character_ui
        ),
        "favorite notice included in portable backup": (
            'IniWrite(IniRead(DataFile, "Launcher", "HideFavoriteSwitchExplanation", "0"), temporary, "Launcher", "HideFavoriteSwitchExplanation")' in backup_ui
            and 'IniWrite(favoriteNotice, temporary, "Launcher", "HideFavoriteSwitchExplanation")' in backup_ui
            and 'if IniRead(DataFile, "Launcher", "HideFavoriteSwitchExplanation", "0") = "1"' in backup_ui
        ),
        "clicking selected favorite preserves it": (
            "index > Profiles.Length || SelectedProfile = index" in character_ui
        ),
        "old favorite moves when removed": (
            "? (Profiles.Length ? Min(index, Profiles.Length) : 0)" in character_ui
        ),
        "legacy saved profiles get first favorite": (
            "if Profiles.Length && !SelectedProfile" in settings_ui
            and 'IniWrite(SelectedProfile, DataFile, "Profiles", "Selected")' in settings_ui
        ),
        "legacy backup receives first favorite": (
            "if selected = 0\n            selected := 1" in backup_ui
        ),
    }
    for label, passing in favorite_checks.items():
        if not passing:
            errors.append(f"Favorite selection regression: {label}")

    macro = (ROOT / "src/ui/macros.ahk").read_text(encoding="utf-8-sig")
    characters = (ROOT / "src/ui/characters.ahk").read_text(encoding="utf-8-sig")
    frontend = (ROOT / "src/ui/front-page.ahk").read_text(encoding="utf-8-sig")
    build_script = (ROOT / "scripts/build-windows.ps1").read_text(encoding="utf-8-sig")
    cleanup_checks = {
        "temporary build cleanup is nonfatal and isolated":
            "Step 'Cleaning temporary build directory (best effort)'" in build_script
            and "[IO.Directory]::Delete($buildRoot, $true)" in build_script
            and "if (-not [IO.Directory]::Exists($buildRoot))" in build_script
            and "if ($attempt -lt 3) { Start-Sleep -Milliseconds 750 }" in build_script
            and "Write-Warning 'Some temporary build tools remain locked." in build_script
            and "Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction Stop" not in build_script
            and "Step 'Windows launcher build completed successfully'" in build_script
            and "exit 0" in build_script,
    }
    for name, passed in cleanup_checks.items():
        if not passed:
            errors.append("Build cleanup regression: " + name)

    macro_checks = {
        "macros remain embedded in the character book":
            'MacroPage := CharacterPage' in macro
            and 'BuildMacroBookPanel()' in characters
            and 'MacroPage := Gui(' not in macro,
        "four reusable viewport rows preserve unlimited macro capacity":
            'Loop 4\n    {\n        position := A_Index' in macro
            and 'y := 140 + (position - 1) * 70' in macro
            and 'maximum := Max(0, count - MacroBookRows.Length)' in macro
            and 'index := MacroScrollOffset + position' in macro
            and 'MacroScrollOffset := Max(0, row - 4)' in macro
            and 'MacroScrollOffset := Min(MacroScrollOffset, Max(0, MacroItems.Length - 4))' in macro
            and 'MacroList.Visible := false' in macro
            and 'MacroListPage' not in macro,
        "status above the name and inline rename button, actions below":
            'status := CharacterPage.Add("Text",' in macro
            and '"x551 y" y " w329 h17 BackgroundTrans c241408 +0x100", "")' in macro
            and 'AddBookTick(CharacterPage, 525, y + 20, SelectMacroBookRow.Bind(position))' in macro
            and 'AddBookLabel(CharacterPage, 551, y + 19, 125, 22, "")' in macro
            and 'rename := AddStyledButton(CharacterPage, 680, y + 19, 21, 22,' in macro
            and 'EditMacroBookRow.Bind(position)' in macro
            and 'AddStyledButton(CharacterPage, 551, y + 42, 103, 20,' in macro
            and 'AddStyledButton(CharacterPage, 663, y + 42, 103, 20,' in macro
            and 'AddStyledButton(CharacterPage, 775, y + 42, 105, 20,' in macro,
        "inline rename uses the name row and supports keyboard save":
            'MacroNameEdit := AddThemedEdit(CharacterPage,' in macro
            and 'MacroNameEdit.Move(BookS(551), BookS(row.Y),' in macro
            and 'caption := editing ? "Save" : Chr(0x270E)' in macro
            and '#HotIf MacroNameEditorFocused()\nEnter::SaveMacroName()' in root_source
            and 'InputBox(' not in macro,
        "Upload Macro follows populated rows and stays pinned on scrolling":
            'MacroDetails' not in macro
            and 'MacroBindingsButton' not in macro
            and 'EditSelectedMacroBindings' not in macro
            and 'TES3NP_BINDINGS' not in macro
            and 'MacroImportButton := AddStyledButton(CharacterPage, 525, 188, 355, 29,' in macro
            and '"Upload Macro", ImportMacroPackage)' in macro
            and 'MacroStatus := CharacterPage.Add("Text",' in macro
            and '"x525 y224 w355 h30 Hidden BackgroundTrans c241408", "Ready.")' in macro
            and 'visibleCount := Min(count, MacroBookRows.Length)' in macro
            and 'desiredUploadY := count = 0 ? 188 : 214 + (visibleCount - 1) * 70' in macro
            and 'if oldUploadY != BookS(desiredUploadY)' in macro
            and 'MoveStyledButton(MacroImportButton, 525, desiredUploadY, 355, 29)' in macro
            and 'MacroStatus.Move(BookS(525), BookS(desiredUploadY + 36), BookS(355), BookS(30))' in macro
            and 'if wasVisible' in macro
            and 'DllCall("RedrawWindow", "Ptr", CharacterPage.Hwnd,' in macro
            and 'MoveStyledButton(control, x, y, width, height)' in characters
            and '"Add Macro / App"' not in macro,
        "per-macro status and red error text":
            'MacroItemDisplayState(item)' in macro
            and 'return {Text: "Ready", Error: false}' in macro
            and 'return {Text: "Running", Error: false}' in macro
            and 'return {Text: "Application missing", Error: true}' in macro
            and 'return {Text: "Script missing", Error: true}' in macro
            and 'return {Text: item.LastError, Error: true}' in macro
            and 'macro.LastError := missingRuntime ? "Runtime missing" : "Launch failed"' in macro
            and 'macro.LastError := ""' in macro
            and 'itemRow.Status.SetFont(state.Error ? "s" Max(7, BookS(9)) " cB22222"' in macro
            and 'MacroStatus.Visible := shown && showFeedback' in macro,
        "scroll wheel and draggable thumb still attached":
            'MacroScrollTrack := CharacterPage.Add("Text"' in macro
            and 'MacroScrollThumb := CharacterPage.Add("Text"' in macro
            and 'MacroScrollThumb.Move(BookS(888), BookS(thumbY), BookS(6), BookS(thumbHeight))' in macro
            and 'ScrollMacroWheel(wParam)' in macro
            and 'PressMacroScroll(hwnd)' in macro
            and 'DragMacroScroll()' in macro
            and 'ReleaseMacroScroll()' in macro
            and 'if ScrollMacroWheel(wParam)' in frontend
            and 'DragMacroScroll()' in frontend
            and 'if PressMacroScroll(hwnd)' in (
                ROOT / "src/ui/controls.ahk"
            ).read_text(encoding="utf-8-sig")
            and 'if ReleaseMacroScroll()' in (
                ROOT / "src/ui/controls.ahk"
            ).read_text(encoding="utf-8-sig")
            and 'MacroScrollOffset := 0' in (
                ROOT / "src/state.ahk"
            ).read_text(encoding="utf-8-sig"),
        "hidden selection model delegates to tested macro handlers":
            'MacroList.Modify(index, "Select Focus")' in macro
            and 'MacroList.OnEvent("ItemSelect", RefreshMacroButtons)' in macro
            and 'RunMacroBookRow(position, *)' in macro
            and 'StopMacroBookRow(position, *)' in macro
            and 'RemoveMacroBookRow(position, *)' in macro
            and 'SelectMacroBookRow(position)\n    RunSelectedMacro()' in macro
            and 'SelectMacroBookRow(position)\n    StopSelectedMacro()' in macro
            and 'SelectMacroBookRow(position)\n    RemoveSelectedMacro()' in macro,
        "editing character still hides/restores macros":
            'HideMacroBookPanel()' in characters
            and 'ShowMacroBookPanel()' in characters,
        "macro controls exist before editor restoration":
            characters.index("    BuildMacroBookPanel()\n    HideProfileEditor()")
            > characters.index("    CreateProfileEditor()\n")
            and 'if !IsObject(MacroList)\n        return' in macro,
        "uninitialized selection cannot call hidden ListView GetNext":
            'if !IsObject(MacroList) || !MacroBookRows.Length' in macro
            and 'MacroList.Visible := false' in macro,
        "installed macros run with bundled AHK v2; no manual interpreter browse":
            'interpreter := A_IsCompiled ? A_ScriptDir "\\runtime\\AutoHotkey64.exe" : A_AhkPath' in macro
            and 'throw Error("Bundled AutoHotkey macro runtime missing")' in macro
            and 'macro.LastError := missingRuntime ? "Runtime missing" : "Launch failed"' in macro
            and 'Choose AutoHotkey executable for this macro' not in macro
            and 'Copy-Item -LiteralPath $base -Destination $macroRuntime -Force' in (
                ROOT / "scripts/build-windows.ps1"
            ).read_text(encoding="utf-8-sig")
            and "Packaged AutoHotkey macro interpreter smoke test failed" in (
                ROOT / "scripts/build-windows.ps1"
            ).read_text(encoding="utf-8-sig")
            and '"runtime/AutoHotkey64.exe"' in (
                ROOT / "scripts/check-windows-package.py"
            ).read_text(encoding="utf-8-sig")
            and 'xcopy /e /i /h /y "%PACKAGE%\\runtime\\*" "%~dp0runtime\\" >nul' in (
                ROOT / "Build tes3np.bat"
            ).read_text(encoding="utf-8-sig")
            and 'if not exist "%~dp0runtime\\AutoHotkey64.exe" goto :failed' in (
                ROOT / "Build tes3np.bat"
            ).read_text(encoding="utf-8-sig"),
        "macro imports and execution remain independent of launcher hotkey configuration":
            'ImportMacroScript(archive)' in macro
            and 'ImportMacroApplication(archive)' in macro
            and 'SetTimer(CheckMacroImport, 200)' in macro
            and 'Run(' in macro and 'interpreter' in macro
            and 'entry := macro.Folder' in macro
            and 'ReadMacroBindings' not in macro
            and 'ShowMacroBindings' not in macro
            and 'TES3NP_BINDINGS' not in macro,
        "linked application removal/exit remain non-destructive":
            'IniWrite(source, manifest, "Macro", "Target")' in macro
            and 'macro.Kind != "App" && macro.PID' in macro
            and 'DeleteSelectedMacro' not in macro,
    }
    for name, passed in macro_checks.items():
        if not passed:
            errors.append(f"Installed Macros regression: {name}")

    manifest = json.loads((ROOT / "patches/manifest.json").read_text(encoding="utf-8-sig"))
    missing = 0
    seen = set()
    for item in manifest["Files"]:
        relative = PurePosixPath(item["Path"])
        key = str(relative).lower()
        if relative.is_absolute() or ".." in relative.parts or ":" in str(relative) or key in seen:
            errors.append(f"Invalid or duplicate payload path: {relative}")
            continue
        seen.add(key)
        path = ROOT / "patches" / relative
        if not path.is_file():
            missing += 1
            if not allow_missing_payload:
                errors.append(f"Missing payload: {relative}")
        elif hashlib.sha256(path.read_bytes()).hexdigest().lower() != item["SHA256"].lower():
            errors.append(f"Payload hash mismatch: {relative}")
    if errors:
        raise ValueError("\n".join(errors))
    print(f"Static checks passed: {len(declarations)} functions; {len(manifest['Files']) - missing} payload hashes checked.")
    if missing:
        print(f"Source-only mode: {missing} payload files absent. Full release packaging requires them.")
    print("AutoHotkey runtime and Windows GUI/game testing remain separate requirements.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    checks = commands.add_parser("check", help="Static source and payload checks")
    checks.add_argument("--allow-missing-payload", action="store_true")
    arguments = parser.parse_args()
    try:
        check(arguments.allow_missing_payload)
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
