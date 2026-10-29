"""Validate the exact user-facing TES3NP Windows ZIP without extracting it.

Usage: python scripts/check-windows-package.py dist/tes3np-windows.zip
This check never runs game code or modifies the installation.
"""
from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path, PurePosixPath

REQUIRED_FILES = (
    "tes3np.exe",
    "client/tes3mp.exe",
    "client/tes3mp-client-default.cfg",
    "client/defaults.bin",
    "client/openmw.cfg",
    "chat-host/tes3np.ChatHost.exe",
    "chat-host/chat.ini",
    "chat-host/chat.css",
    "licenses/TES3MP/LICENSE",
    "licenses/TES3MP/REDISTRIBUTION-NOTICE.txt",
)
MINIMUM_SIZE = {
    "tes3np.exe": 100_000,
    "client/tes3mp.exe": 100_000,
    "chat-host/tes3np.ChatHost.exe": 100_000,
}


def check_package(path: Path) -> None:
    if not path.is_file():
        raise ValueError(f"Package does not exist: {path}")
    with zipfile.ZipFile(path) as archive:
        names: set[str] = set()
        for entry in archive.infolist():
            name = entry.filename.replace("\\", "/")
            parts = PurePosixPath(name).parts
            if not name or name.startswith("/") or ".." in parts or ":" in parts[0]:
                raise ValueError(f"Unsafe path inside package: {name!r}")
            normalized = name.rstrip("/")
            if normalized.casefold() in names:
                raise ValueError(f"Duplicate or case-conflicting package entry: {name!r}")
            names.add(normalized.casefold())
            if entry.file_size < 0:
                raise ValueError(f"Invalid entry size: {name!r}")

        missing = [item for item in REQUIRED_FILES if item.casefold() not in names]
        if missing:
            raise ValueError("Windows package is missing: " + ", ".join(missing))
        for name, minimum in MINIMUM_SIZE.items():
            if archive.getinfo(name).file_size < minimum:
                raise ValueError(f"Packaged executable is suspiciously small: {name}")

        # Compare the packaged markerless executable with the source manifest.
        manifest_path = Path(__file__).resolve().parents[1] / "patches" / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
        entry = next(
            (f for f in manifest["Files"] if f["Path"] == "markerless/tes3mp.exe"), None
        )
        if not entry:
            raise ValueError("Markerless executable missing from source manifest")
        digest = hashlib.sha256(archive.read("client/tes3mp.exe")).hexdigest()
        if digest.casefold() != entry["SHA256"].casefold():
            raise ValueError("Packaged TES3MP executable SHA-256 differs from manifest")

        bad_entry = archive.testzip()
        if bad_entry is not None:
            raise ValueError(f"Corrupted compressed package member: {bad_entry}")

    print(f"PASS: packaged ZIP structure, integrity and markerless checksum: {path}")


if __name__ == "__main__":
    try:
        check_package(Path(sys.argv[1] if len(sys.argv) > 1 else "dist/tes3np-windows.zip"))
    except (OSError, KeyError, ValueError, zipfile.BadZipFile) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
