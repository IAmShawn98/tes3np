"""Release gate for TES3NP.

This is intentionally distinct from the normal developer build. A successful
ZIP integrity check does not demonstrate redistribution rights or test coverage.
Run: python scripts/check-release-gates.py
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    # The retired testing mode must never return in a public build.
    # Current events are authenticated by their original Discord timestamp,
    # and expiration must be enforced at detection, display, and timer ticks.
    chat_source = (ROOT / "chat-host" / "Program.cs").read_text(encoding="utf-8-sig")
    if any(name in chat_source for name in (
        "PreviewExpiredHappyHourForTesting", "ShowExpiredHappyHourForAlphaTest",
    )):
        print("BLOCKED: obsolete Happy Hour preview mode was reintroduced.")
        return 1
    if not all(fragment in chat_source for fragment in (
        "DiscordTimestamp(activationId).AddHours(1)",
        "DiscordTimestamp(latest).AddHours(1) > DateTimeOffset.UtcNow",
        "DiscordTimestamp(candidate).AddHours(1) > DateTimeOffset.UtcNow",
        "ends <= DateTimeOffset.UtcNow) return;",
        "happyHourEndsAt <= DateTimeOffset.UtcNow || !IsWindow(owner)",
        "happyHourEndsAt <= DateTimeOffset.UtcNow) {",
    )):
        print("BLOCKED: Happy Hour active-only display guard is missing.")
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
