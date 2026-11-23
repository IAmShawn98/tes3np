#!/usr/bin/env python3
"""Read-only TES3NP UI source inventory; never edits launcher files.

python scripts/audit-ui-layout.py --format markdown --output docs/ui-layout-inventory.md
python scripts/audit-ui-layout.py --format json --output ui-layout-inventory.json

Findings are places for human review, not proven bugs or visual validation.
"""
from __future__ import annotations
import argparse
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = ("src", "game-chat")
SUFFIXES = frozenset((".ahk", ".cs", ".css", ".html", ".htm", ".xaml"))
RULES = (
    ("control-construction", "control", r'\.Add\(|\bAddStyledButton\(|\bAddBookLabel\(|\bAddBookTick\(|\bAddV016SettingsCopy\('),
    ("fixed-native-rectangle", "geometry", r'\bx-?\d+\s+y-?\d+\s+w\d+\s+h\d+'),
    ("fixed-axis-or-size", "geometry", r'\b[xywh]-?\d+\b|\b(?:Width|Height|Left|Top|Location|Size)\s*=\s*(?:new\s+)?(?:\d+|new\s*\()'),
    ("manual-control-move", "geometry", r'\.Move\(|\bMoveStyledButton\('),
    ("font-change", "font", r'\bSetAccessibleTextFont\(|\.SetFont\(|\bApplyLauncherButtonFont\('),
    ("possible-font-shrinking", "font-risk", r'\bFitButtonLabelFont\(|\bFitWrappedLabelFont\(|\bsize\s*:=\s*Min\(|\bfontSize\s*:=\s*Min\('),
    ("custom-text-painter", "renderer", r'\b(?:DrawTextW|GetTextExtentPoint32W|TextOutW|TextRenderer|PaintLauncherChatTab)\b'),
    ("layout-or-scaling", "layout", r'\b(?:ScaleOwnedMenuContent|RefreshCachedBookTextPreference|ApplyLauncherControlScale|ApplyAccessibilityTextSize|GetOwnedMenuScale|ApplyV016CharacterLayout)\s*\('),
    ("overflow-policy", "overflow", r'\b(?:Scroll|AutoScroll|overflow|text-overflow|word-wrap|WrapReleaseNoteLines)\b'),
    ("dotnet-or-css-sizing", "geometry", r'\b(?:MinimumSize|MaximumSize|AutoSize|Dock|Anchor|FontSize|font-size|line-height|min-width|max-height)\b'),
)
COMPILED = [(name, kind, re.compile(pattern, re.I)) for name, kind, pattern in RULES]
ROUTES = (
    ("main-launcher", ("launcher-layout", "front-page", "bootstrap", "controls", "renderer", "embedded-chat")),
    ("character-and-macro-book", ("characters", "macros", "windows", "v016-refinements")),
    ("settings-and-setup", ("launcher-settings", "v016-refinements", "bug-report")),
    ("updates-and-release-notes", ("update-dialogs", "update-notes", "patcher")),
    ("loading-and-login", ("loading", "login-progress")),
    ("separate-chat-host", ("game-chat/",)),
)

def inventory():
    files = []
    for dirname in DIRECTORIES:
        folder = ROOT / dirname
        if not folder.is_dir():
            continue
        for path in sorted(folder.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in SUFFIXES:
                continue
            relative = path.relative_to(ROOT).as_posix()
            if any(part in ("bin", "obj", "node_modules", ".git") for part in path.parts):
                continue
            try:
                lines = path.read_text(encoding="utf-8-sig").splitlines()
            except (OSError, UnicodeError) as exc:
                files.append({"path": relative, "error": str(exc), "findings": []})
                continue
            findings = []
            for number, line in enumerate(lines, 1):
                stripped = line.strip()
                if not stripped or stripped.startswith((";", "//", "#", "/*", "*", "<!--")):
                    continue
                for name, category, regex in COMPILED:
                    if regex.search(line):
                        findings.append({"line": number, "rule": name,
                                         "category": category, "source": stripped[:180]})
            if findings:
                files.append({"path": relative, "findings": findings})
    return files

def summarize(files):
    totals = Counter(f["category"] for entry in files for f in entry["findings"])
    result = []
    for entry in files:
        path = entry["path"].lower()
        views = [name for name, hints in ROUTES if any(h in path for h in hints)]
        result.append({**entry, "views": views or ["other-ui"],
                       "counts": dict(sorted(Counter(f["category"] for f in entry["findings"]).items()))})
    return {"scope": list(DIRECTORIES), "flagged_files": len(files),
            "finding_counts": dict(sorted(totals.items())),
            "note": "Diagnostic source locations only; no visual acceptance implied.",
            "files": result}

def as_markdown(report):
    lines = ["# TES3NP launcher-wide UI inventory", "",
             "Read-only static scan. A location is NOT necessarily a defect.", "",
             "## Categories", "", "| Category | Occurrences |", "|---|---:|"]
    for name, number in report["finding_counts"].items():
        lines.append(f"| {name} | {number} |")
    lines.extend(("", "## Source paths and line numbers", ""))
    for entry in report["files"]:
        lines.extend((f"### {entry['path']}", "",
                      f"Views: {', '.join(entry['views'])}", ""))
        if "error" in entry:
            lines.extend((f"Unreadable: {entry['error']}", ""))
            continue
        lines.extend(("| Line | Review category | Source excerpt |", "|---:|---|---|"))
        for finding in entry["findings"]:
            excerpt = finding["source"].replace("|", "/").replace("\n", " ")
            lines.append(f"| {finding['line']} | {finding['rule']} | {excerpt} |")
        lines.append("")
    lines.extend(("## Validation boundary", "",
                  "Artwork anchors may remain fixed. Text box sizes and dependent positions",
                  "need rendered native/CSS font measurements and on-screen validation.",
                  "This inventory changes no source files and does not prove accessibility.", ""))
    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--output", type=Path, help="Write report here, relative to repository root")
    options = parser.parse_args()
    report = summarize(inventory())
    if not report["files"]:
        parser.error("No production UI source files were inventoried.")
    output = (json.dumps(report, indent=2, ensure_ascii=False) + "\n"
              if options.format == "json" else as_markdown(report))
    if options.output:
        destination = options.output if options.output.is_absolute() else ROOT / options.output
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(output, encoding="utf-8")
        print(f"UI source inventory saved to {destination}")
    else:
        print(output, end="")

if __name__ == "__main__":
    main()
