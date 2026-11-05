"""Read-only TES3NP alpha privacy and offline updater verification.

Run from the repository checkout:
    python scripts/audit-local-privacy.py

This intentionally prints only category counts, not diagnostic lines, absolute
paths, usernames, secrets, private Discord messages, or configuration contents.
It never writes to AppData, game directories, or an installed launcher.
"""
from __future__ import annotations

import argparse
import collections
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APPDATA = Path(os.environ.get("APPDATA", "")) / "tes3np"

RULES = {
    "absolute_windows_path": re.compile(r"(?i)(?<![\w])(?:[a-z]:[\\/]|\\\\[^\s\\]+\\)"),
    "user_directory_variable": re.compile(r"(?i)%(?:USERPROFILE|APPDATA|LOCALAPPDATA)%"),
    "url": re.compile(r"(?i)\b(?:https?|wss?)://\S+"),
    "email": re.compile(r"(?i)\b[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}\b"),
    "ipv4": re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"),
    "long_identifier": re.compile(r"\b\d{16,21}\b"),
    "credential_field": re.compile(r"(?i)\b(?:password|passwd|token|secret|authorization|cookie|api[-_]?key)\s*[:=]\s*\S+"),
    "privacy_placeholder": re.compile(r"(?i)\bREDACTED\b|\[(?:credential|user|identity|secret|url|path|network path|email|ip|identifier|discord id) omitted\]|description omitted for privacy|password value not logged"),
    "empty_field": re.compile(r"\|[ \t]*\|"),
}
TIMESTAMP = re.compile(r"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}")
LAUNCHER_PREFIX = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \|")
RESULT_BACKUP = re.compile(r"(?im)^Backup\s*=\s*([^\r\n]*)")
LOG_FILES = (
    "launcher.log", "chat-host.log", "patch-all.log", "patch-errors.log",
    "render-errors.log", "tes3mp-crash-query.txt", "expansion-toggle-result.txt",
)


def scan_text(text: str, *, launcher: bool, username: str = "", result: bool = False) -> tuple[collections.Counter, int]:
    problems: collections.Counter = collections.Counter()
    event_count = 0
    username_re = (re.compile(r"(?i)(?<!\w)" + re.escape(username) + r"(?!\w)")
                   if len(username) >= 3 else None)
    for line in text.splitlines():
        if not line.strip():
            continue
        event_count += 1
        for name, regex in RULES.items():
            if regex.search(line):
                problems[name] += 1
        if username_re:
            # Character labels carry public in-game names; other fields do not.
            fields = [field.strip() for field in line.split("|")]
            for field in fields:
                if field.lower().startswith("character:"):
                    continue
                if username_re.search(field):
                    problems["windows_username"] += 1
                    break
        if launcher:
            if not LAUNCHER_PREFIX.match(line):
                problems["non_timestamped_event"] += 1
            if len(TIMESTAMP.findall(line)) != 1:
                problems["merged_or_extra_timestamp"] += 1
    if result:
        for match in RESULT_BACKUP.finditer(text):
            if match.group(1).strip().lower() not in ("", "available"):
                problems["private_backup_location_or_invalid_state"] += 1
    return problems, event_count


def read_diagnostic(path: Path) -> str:
    # The launcher uses UTF-8. Handle a legacy PowerShell UTF-16 BOM too.
    with path.open("rb") as stream:
        header = stream.read(4)
    encoding = "utf-16" if header.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    return path.read_text(encoding=encoding, errors="replace")


def public_label(name: str) -> str:
    # Never include user-selected file paths or job-folder names in reports.
    if name == "expansion-import-results":
        return "Expansion import result.ini"
    return name


def audit_files(appdata: Path) -> tuple[int, int, int]:
    issues = 0
    checked = 0
    skipped = 0
    username = os.environ.get("USERNAME", "")
    files: list[tuple[str, list[Path], bool]] = [
        (name, [appdata / name], False) for name in LOG_FILES
    ]
    imports = appdata / "expansion-imports"
    try:
        result_files = sorted(imports.glob("*/result.ini"), key=lambda p: p.stat().st_mtime, reverse=True)[:30] if imports.is_dir() else []
    except OSError:
        result_files = []
    files.append(("expansion-import-results", result_files, True))

    for name, paths, is_result in files:
        existing = [path for path in paths if path.is_file()]
        if not existing:
            skipped += 1
            print(f"SKIP | {public_label(name)}: no records")
            continue
        total = collections.Counter()
        events = 0
        unreadable = False
        for path in existing:
            try:
                if path.stat().st_size > 32 * 1024 * 1024:
                    total["file_exceeds_32mb_audit_limit"] += 1
                    continue
                findings, lines = scan_text(
                    read_diagnostic(path),
                    launcher=(name == "launcher.log"), username=username,
                    result=is_result,
                )
                total.update(findings)
                events += lines
            except (OSError, UnicodeError, ValueError):
                unreadable = True
        checked += len(existing)
        if unreadable:
            total["unreadable_diagnostic"] += 1
        if name == "launcher.log" and existing:
            try:
                with existing[0].open("rb") as stream:
                    stream.seek(-1, 2)
                    if stream.read(1) != b"\n":
                        total["missing_final_newline"] += 1
            except (OSError, ValueError):
                total["could_not_check_final_newline"] += 1
        label = public_label(name)
        if total:
            issues += 1
            categories = ", ".join(f"{key}={count}" for key, count in sorted(total.items()))
            print(f"REVIEW | {label}: {len(existing)} file(s), {events} line(s); {categories}")
        else:
            print(f"PASS | {label}: {len(existing)} file(s), {events} line(s), no flagged patterns")
    private = [appdata / "settings.ini", appdata / "Logs/game-chat.log", appdata / "Logs/game-chat-index.json"]
    present = sum(p.is_file() for p in private)
    print(f"INFO | Private settings/chat files: {present}/3 present; contents not read or modified")
    return issues, checked, skipped


def run_regression(name: str, engine: str | None, script: str) -> bool | None:
    if not engine:
        print(f"SKIP | {name}: required PowerShell runtime not installed")
        return None
    if not (ROOT / script).is_file():
        print(f"REVIEW | {name}: fixture missing")
        return False
    try:
        result = subprocess.run(
            [engine, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / script)],
            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=240, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        print(f"REVIEW | {name}: could not complete (details withheld)")
        return False
    if result.returncode:
        print(f"REVIEW | {name}: exit {result.returncode} (details withheld)")
        return False
    print(f"PASS | {name}: isolated fixture passed")
    return True


def offline_regressions() -> tuple[int, int]:
    winps = shutil.which("powershell.exe")
    if not winps:
        windir = os.environ.get("WINDIR", "")
        candidate = Path(windir) / "System32/WindowsPowerShell/v1.0/powershell.exe"
        if candidate.is_file():
            winps = str(candidate)
    pwsh = shutil.which("pwsh.exe")
    checks = (
        ("Updater source/version contracts", winps, "scripts/test-update-client.ps1"),
        ("Updater metadata/tamper", winps, "scripts/test-update-metadata.ps1"),
        ("Updater transaction/rollback", pwsh, "scripts/test-updater-transaction.ps1"),
    )
    results = [run_regression(*args) for args in checks]
    return sum(r is False for r in results), sum(r is None for r in results)


def self_test() -> bool:
    with tempfile.TemporaryDirectory(prefix="tes3np-privacy-audit-fixture-") as temp:
        root = Path(temp)
        (root / "launcher.log").write_text(
            "2026-11-05 03:00:00 | GAME | Character: TestWizard\n"
            "2026-11-05 03:00:01 | Launcher startup completed.\n",
            encoding="utf-8",
        )
        safe = read_diagnostic(root / "launcher.log")
        found, count = scan_text(safe, launcher=True)
        if found or count != 2:
            return False
        synthetic = (
            "2026-11-05 03:00:00 | Path: C:\\Users\\Private\\file.txt | "
            "Email: private@example.com | Password: abc\n"
            "2026-11-05 03:00:01 | Launcher startup.2026-11-05 03:00:02 | Bad join\n"
        )
        found, _ = scan_text(synthetic, launcher=True)
        required = {"absolute_windows_path", "email", "credential_field", "merged_or_extra_timestamp"}
        if not required.issubset(found):
            return False
        found, _ = scan_text("Backup=C:\\Private\\journal.json", launcher=False, result=True)
        if "private_backup_location_or_invalid_state" not in found:
            return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only local TES3NP diagnostic audit and isolated updater checks")
    parser.add_argument("--skip-updater", action="store_true", help="only check logs; skip existing isolated updater fixtures")
    parser.add_argument("--self-test", action="store_true", help="test scanner with disposable synthetic data only")
    args = parser.parse_args()
    if args.self_test:
        passed = self_test()
        print("PASS | Scanner synthetic self-test" if passed else "FAIL | Scanner synthetic self-test")
        return 0 if passed else 1
    print("TES3NP ALPHA PRIVACY READINESS | read-only; report contains counts only")
    print("No credentials, settings, Discord history, Morrowind files or copied logs are changed.")
    if not os.environ.get("APPDATA"):
        print("REVIEW | Windows APPDATA not available; run in normal Windows PowerShell")
        return 1
    issues, checked, skipped = audit_files(APPDATA)
    fixture_failures, fixture_skips = (0, 0) if args.skip_updater else offline_regressions()
    print(f"SUMMARY | diagnostic files={checked}; missing categories={skipped}; flagged categories={issues}; fixture failures={fixture_failures}; fixture skips={fixture_skips}")
    print("PENDING MANUAL | saved data, Game Chat/Happy Hour, character login, macros, and extracted ZIP interactive checks")
    print("Raw private logs and Discord history should NOT be uploaded.")
    return 1 if issues or fixture_failures else 0


if __name__ == "__main__":
    sys.exit(main())
