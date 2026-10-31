"""Dependency-free source checks and release packaging; never execute game code."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
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
                name = match[1].lower()
                if name in declarations:
                    errors.append(f"{relative}: duplicate function {match[1]} ({declarations[name]})")
                declarations[name] = relative
            for match in re.finditer(r"(?i)\b(buffer|gui|map|array)\s*:=\s*\1\s*\(", tokens):
                errors.append(f"{relative}: local name shadows {match[1]} constructor")
            for match in re.finditer(r"(?m)^#Include\s+(.+)$", text):
                include = ROOT / match[1].strip().replace("\\", "/")
                if not include.is_file():
                    errors.append(f"{relative}: missing include {match[1]}")
        except ValueError as error:
            errors.append(f"{relative}: {error}")
    # Favorite-selection source contract: ensure the first saved character is
    # checked, an attempted switch is confirmed before any persisted mutation,
    # and legacy loads/imports cannot strand a nonempty list without a favorite.
    character_ui = (ROOT / "src/ui/characters.ahk").read_text(encoding="utf-8-sig")
    settings_ui = (ROOT / "src/data/settings.ahk").read_text(encoding="utf-8-sig")
    backup_ui = (ROOT / "src/data/backup.ahk").read_text(encoding="utf-8-sig")
    favorite_checks = {
        "first character auto-favorite": (
            "if Profiles.Length = 1 || SelectedProfile < 1" in character_ui
            and "SelectedProfile := 1" in character_ui
        ),
        "favorite switch asks before saving": (
            'if MsgBox(prompt, "Favorite character", 0x124) != "Yes"' in character_ui
            and character_ui.index('if MsgBox(prompt, "Favorite character", 0x124) != "Yes"')
            < character_ui.index("    SelectedProfile := index\n    SaveDefaultProfile()")
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


def package(source_only: bool) -> Path:
    check(allow_missing_payload=source_only)
    state = (ROOT / "src/state.ahk").read_text(encoding="utf-8-sig")
    build = re.search(r"AppConfig\s*:=\s*\{Build:\s*(\d+)", state)
    if not build:
        raise ValueError("Build number not found in src/state.ahk")
    destination = ROOT / "dist" / f"tes3np-build-{build[1]}{'-source' if source_only else ''}.zip"
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in project_files():
            relative = path.relative_to(ROOT)
            if source_only and relative.parts[0] == "patches" and relative.as_posix() not in {
                "patches/manifest.json", "patches/expansion-pack/LICENSE.txt",
            }:
                continue
            archive.write(path, "tes3np/" + relative.as_posix())
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError("Generated ZIP failed its integrity check")
    print(f"Created {destination.name}: {destination.stat().st_size:,} bytes")
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    checks = commands.add_parser("check", help="Static source and payload checks")
    checks.add_argument("--allow-missing-payload", action="store_true")
    packages = commands.add_parser("package", help="Create a validated distribution ZIP")
    packages.add_argument("--source-only", action="store_true")
    arguments = parser.parse_args()
    try:
        if arguments.command == "check":
            check(arguments.allow_missing_payload)
        else:
            package(arguments.source_only)
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
