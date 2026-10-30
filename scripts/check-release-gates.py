"""Release gate for TES3NP.

This is intentionally distinct from the normal developer build. A successful
ZIP integrity check does not demonstrate redistribution rights or test coverage.
Run: python scripts/check-release-gates.py
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    # A working development preview intentionally shows expired archived
    # announcements. It must never leak into a public production build.
    chat_source = (ROOT / "chat-host" / "Program.cs").read_text(encoding="utf-8-sig")
    if "const bool PreviewExpiredHappyHourForTesting = true;" in chat_source:
        print("BLOCKED: development-only expired Happy Hour preview is enabled.")
        print("Disable it and re-test authenticated current-event behavior before release.")
        return 1

    files = [
        ROOT / "docs" / "MODIFIED-TES3MP-SOURCE-PROVENANCE.md",
        ROOT / "docs" / "ASSET-DISTRIBUTION-APPROVAL.md",
        ROOT / "docs" / "CLEAN-WINDOWS-TEST-RESULTS.md",
    ]
    missing = [str(path.relative_to(ROOT)) for path in files if not path.is_file()]
    if missing:
        print("BLOCKED: release evidence is missing:")
        for path in missing:
            print(" - " + path)
        print("Do not publish the modified client based on a passing build alone.")
        return 1
    required = ("VERIFIED_SOURCE_AND_BUILD", "ASSET_RIGHTS_REVIEWED", "CLEAN_MACHINE_TESTED")
    for path, marker in zip(files, required):
        text = path.read_text(encoding="utf-8-sig")
        if f"Status: {marker}" not in text:
            print(f"BLOCKED: {path.name} does not contain verified release evidence.")
            return 1
    print("Evidence files indicate review complete; owner must still approve the release.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
