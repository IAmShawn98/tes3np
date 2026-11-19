"""Source input for the Game Chat architecture, release, and privacy checks."""
from pathlib import Path


def game_chat_sources(root: Path) -> list[Path]:
    return sorted((root / "game-chat").glob("*.cs"))


def read_game_chat_sources(root: Path) -> str:
    return "\n\n".join(path.read_text(encoding="utf-8-sig") for path in game_chat_sources(root))
