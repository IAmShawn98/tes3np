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
        "favorite message replaces previous copy without layout changes": (
            'descriptionText := "This is a list of all your characters.' in character_ui
            and 'does not impact them in-game!"' in character_ui
            and 'CharacterDescription.Move(70, 80, 390, 95)' in character_ui
            and 'y := 180 + (index - 1) * 24' in character_ui
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
    bindings = (ROOT / "src/ui/macro-bindings.ahk").read_text(encoding="utf-8-sig")
    macro_checks = {
        "macros are embedded in the Character Book":
            'MacroPage := CharacterPage' in macro
            and 'BuildMacroBookPanel()' in characters
            and 'MacroPage := Gui(' not in macro,
        "book-painted macro rows replace visible native table":
            '"Installed Macros"' in macro
            and '"you havent installed any macros."' in macro
            and 'AddStyledButton(CharacterPage, 525, y, 207, 29' in macro
            and 'AddBookLabel(CharacterPage, 741, y + 2' in macro
            and 'MacroList.Visible := false' in macro
            and 'MacroListPage := Min(Max(1, Ceil(MacroItems.Length / 5))' in macro,
        "compact controls follow item count":
            'MoveStyledButton(MacroImportButton, 525, actionY, 164, 30)' in macro
            and 'MoveStyledButton(MacroStatus, 525, actionY + 76' in macro,
        "selected row highlight uses existing painter":
            'MacroSelected := selected' in macro
            and 'selectedMacro := face.HasOwnProp("MacroSelected")' in
                (ROOT / "src/ui/renderer.ahk").read_text(encoding="utf-8-sig"),
        "editor restores macros without overlaying the character fields":
            'HideMacroBookPanel()' in characters
            and 'ShowMacroBookPanel()' in characters,
        "macro controls initialized before editor restoration":
            characters.index("    BuildMacroBookPanel()\n    HideProfileEditor()")
            > characters.index("    CreateProfileEditor()\n")
            and 'if !IsObject(MacroList)\n        return' in macro,
        "uninitialized macro selection cannot call GetNext":
            'if !IsObject(MacroList) || !MacroBookRows.Length' in macro
            and 'MacroList.Visible := false' in macro,
        "launcher no longer has a separate Macros button":
            '["Macros", OpenMacros]' not in frontend,
        "script, ZIP and application imports coexist":
            'ImportMacroScript(archive)' in macro
            and 'ImportMacroApplication(archive)' in macro
            and 'SetTimer(CheckMacroImport, 200)' in macro,
        "registered applications are not removed from disk or killed at exit":
            'IniWrite(source, manifest, "Macro", "Target")' in macro
            and 'macro.Kind != "App" && macro.PID' in macro
            and 'if macro.HasOwnProp("Kind") && macro.Kind = "App"' in bindings,
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
