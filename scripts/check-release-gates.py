"""Release gate for TES3NP.

This is intentionally distinct from the normal developer build. A successful
ZIP integrity check does not demonstrate redistribution rights or test coverage.
Run: python scripts/check-release-gates.py
"""
from pathlib import Path
import sys

from game_chat_source import read_game_chat_sources

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    # The retired testing mode must never return in a public build.
    # Current events are authenticated by their original Discord timestamp,
    # and expiration must be enforced at detection, display, and timer ticks.
    chat_source = read_game_chat_sources(ROOT)
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

    review = ROOT / "docs" / "RELEASE-REVIEW.md"
    if not review.is_file():
        print(f"BLOCKED: release review is missing: {review.relative_to(ROOT)}")
        return 1

    lines = review.read_text(encoding="utf-8-sig").splitlines()
    for label, markers in (
        ("TES3MP source", ("VERIFIED_SOURCE_AND_BUILD",)),
        ("Asset distribution", ("ASSET_RIGHTS_REVIEWED", "MAINTAINER_APPROVED")),
        ("Windows testing", ("CLEAN_MACHINE_TESTED",)),
    ):
        prefix = f"- {label}: "
        statuses = [line[len(prefix):].strip() for line in lines if line.startswith(prefix)]
        if len(statuses) != 1 or statuses[0] not in markers:
            expected = " or ".join(markers)
            print(f"BLOCKED: {label} in {review.name} must be marked {expected}.")
            return 1
    print("Release review is complete; owner must still approve the release.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
