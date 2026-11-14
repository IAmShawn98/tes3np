"""Validate the exact user-facing TES3NP Windows ZIP without extracting it.

Usage: python scripts/check-windows-package.py dist/tes3np-windows.zip
This check never runs game code or modifies the installation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import struct
import sys
import zipfile
from pathlib import Path, PurePosixPath

REQUIRED_FILES = (
    "tes3np.exe",
    "RELEASE_NOTES.md",
    "runtime/AutoHotkey64.exe",
    "licenses/AutoHotkey/REDISTRIBUTION-NOTICE.txt",
    "client/tes3mp.exe",
    "client/tes3mp-client-default.cfg",
    "client/defaults.bin",
    "client/openmw.cfg",
    "chat-host/tes3np.ChatHost.exe",
    "chat-host/chat.ini",
    "chat-host/chat.css",
    "chat-host/assets/DiscordInt.png",
    "licenses/TES3MP/LICENSE",
    "licenses/TES3MP/REDISTRIBUTION-NOTICE.txt",
)
MINIMUM_SIZE = {
    "tes3np.exe": 100_000,
    "runtime/AutoHotkey64.exe": 100_000,
    "client/tes3mp.exe": 100_000,
    "chat-host/tes3np.ChatHost.exe": 100_000,
}


def check_console_client(archive: zipfile.ZipFile, root: Path, executable: bytes,
                         members: dict[str, zipfile.ZipInfo]) -> None:
    candidate = json.loads((root / "research/markerless/console-candidate.json").read_text(encoding="utf-8"))
    if hashlib.sha256(executable).hexdigest() != candidate["executableSha256"]:
        raise ValueError("Packaged console executable does not match the playtested build")
    if len(executable) < 64 or executable[:2] != b"MZ":
        raise ValueError("Packaged console client has no Windows executable header")
    pe = struct.unpack_from("<I", executable, 0x3C)[0]
    if (pe + 94 > len(executable) or executable[pe:pe + 4] != b"PE\0\0"
            or struct.unpack_from("<H", executable, pe + 4)[0] != 0x8664
            or struct.unpack_from("<H", executable, pe + 24)[0] != 0x20B
            or struct.unpack_from("<H", executable, pe + 92)[0] != 3):
        raise ValueError("Packaged markerless client must be a Windows x64 console executable")

    source_dir = "licenses/TES3MP/markerless-source/"
    for name in ("README.md", "build-markerless.ps1", "Restore-Markerless-Console.ps1",
                 "tes3mp-0.8.1-markerless-experimental.patch", "tes3mp-release-console.patch"):
        expected = (root / "research/markerless" / name).read_bytes().replace(b"\r\n", b"\n")
        if archive.read(members[(source_dir + name).casefold()]).replace(b"\r\n", b"\n") != expected:
            raise ValueError(f"Packaged markerless source instructions or patch differ: {name}")

    manifest = json.loads(archive.read(members[(source_dir + "client-files.json").casefold()]).decode("utf-8-sig"))
    listed = set()
    for entry in manifest["files"]:
        name = entry["path"]
        relative = PurePosixPath(name)
        if (relative.is_absolute() or ".." in relative.parts or "\\" in name or ":" in name
                or name.casefold() in listed or (name != "tes3mp.exe" and relative.suffix.lower() != ".dll")):
            raise ValueError(f"Invalid or duplicate markerless manifest entry: {name}")
        listed.add(name.casefold())
        if hashlib.sha256(archive.read(members[("client/" + name).casefold()])).hexdigest() != entry["sha256"].lower():
            raise ValueError(f"Packaged markerless file checksum differs: {name}")
    if ("tes3mp.exe" not in listed or len(listed) != candidate["dllCount"] + 1
            or not all(name.casefold() in listed for name in candidate["requiredDlls"])):
        raise ValueError("Packaged markerless manifest does not contain the complete tested payload")


def check_package(path: Path, require_console_client: bool = False) -> None:
    if not path.is_file():
        raise ValueError(f"Package does not exist: {path}")
    with zipfile.ZipFile(path) as archive:
        members: dict[str, zipfile.ZipInfo] = {}
        for entry in archive.infolist():
            name = entry.filename.replace("\\", "/")
            normalized = name.rstrip("/")
            parts = normalized.split("/")
            if (not normalized or any(not part or part in {".", ".."} or ":" in part
                    or part.rstrip(" .") != part for part in parts)):
                raise ValueError(f"Unsafe path inside package: {name!r}")
            if entry.create_system == 3 and stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError(f"Linked entry inside package: {name!r}")
            if normalized.casefold() in members:
                raise ValueError(f"Duplicate or case-conflicting package entry: {name!r}")
            members[normalized.casefold()] = entry
        for name in members:
            for parent in PurePosixPath(name).parents:
                entry = members.get(parent.as_posix())
                if entry is not None and not entry.is_dir():
                    raise ValueError(f"Package file blocks a directory path: {parent}")

        # The optional Expansion Pack must never ship in the Windows ZIP.
        # The real player-selected pack is downloaded from Discord separately.
        if any(name.startswith(("patches/", "expansion-pack/")) for name in members):
            raise ValueError("Legacy Expansion Pack or patch payload was packaged")
        missing = [item for item in REQUIRED_FILES if item.casefold() not in members]
        if missing:
            raise ValueError("Windows package is missing: " + ", ".join(missing))
        for name in REQUIRED_FILES:
            if members[name.casefold()].file_size == 0:
                raise ValueError(f"Required package file is empty: {name}")
        for name, minimum in MINIMUM_SIZE.items():
            if members[name.casefold()].file_size < minimum:
                raise ValueError(f"Packaged executable is suspiciously small: {name}")

        root = Path(__file__).resolve().parents[1]
        state = (root / "src/state.ahk").read_text(encoding="utf-8-sig")
        version = re.search(r'AppConfig\s*:=\s*\{Version:\s*"([^"]+)"', state)
        notes = archive.read(members["release_notes.md"]).decode("utf-8-sig")
        if not version or not re.search(rf"^##[ \t]+v{re.escape(version[1])}(?=\s|$)", notes, re.MULTILINE):
            raise ValueError("Packaged release notes do not contain the launcher version")

        executable = archive.read(members["client/tes3mp.exe"])
        has_console_manifest = "licenses/tes3mp/markerless-source/client-files.json" in members
        if require_console_client or has_console_manifest:
            check_console_client(archive, root, executable, members)
        else:
            manifest = json.loads((root / "patches/manifest.json").read_text(encoding="utf-8-sig"))
            entry = next((f for f in manifest["Files"] if f["Path"] == "markerless/tes3mp.exe"), None)
            if not entry or hashlib.sha256(executable).hexdigest() != entry["SHA256"].casefold():
                raise ValueError("Packaged TES3MP executable SHA-256 differs from manifest")

        bad_entry = archive.testzip()
        if bad_entry is not None:
            raise ValueError(f"Corrupted compressed package member: {bad_entry}")

    print(f"PASS: packaged ZIP structure, integrity and markerless checksum: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", type=Path, default=Path("dist/tes3np-windows.zip"))
    parser.add_argument("--require-console-client", action="store_true")
    args = parser.parse_args()
    try:
        check_package(args.path, args.require_console_client)
    except (OSError, KeyError, ValueError, zipfile.BadZipFile) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
