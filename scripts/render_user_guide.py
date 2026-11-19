"""Render the player guide as self-contained HTML for the Windows package."""
from __future__ import annotations

import argparse
import re
from html import escape
from pathlib import Path

GUIDE_FILE = "User Guide.html"
DOCS_URL = "https://github.com/IAmShawn98/tes3np/blob/main/docs/"
INLINE = re.compile(r'`([^`]+)`|\*\*([^*]+)\*\*|\[([^\]]+)\]\(([^)]+)\)')


def inline(text: str) -> str:
    parts = []
    end = 0
    for match in INLINE.finditer(text):
        parts.append(escape(text[end:match.start()]))
        code, bold, label, target = match.groups()
        if code is not None:
            parts.append(f"<code>{escape(code)}</code>")
        elif bold is not None:
            parts.append(f"<strong>{escape(bold)}</strong>")
        else:
            # Links to companion repository documents are optional online references.
            if re.fullmatch(r"[\w-]+\.md", target):
                target = DOCS_URL + target
            if target.startswith(("https://", "http://")):
                parts.append(f'<a href="{escape(target, quote=True)}">{escape(label)}</a>')
            else:
                parts.append(escape(label))
        end = match.end()
    parts.append(escape(text[end:]))
    return "".join(parts)


def render_block(lines: list[str]) -> str:
    heading = re.fullmatch(r"(#{1,6}) (.+)", lines[0])
    if heading and len(lines) == 1:
        tag = f"h{len(heading[1])}"
        return f"<{tag}>{inline(heading[2])}</{tag}>"

    if len(lines) >= 2 and re.fullmatch(r"\|(?:\s*:?-+:?\s*\|)+", lines[1]):
        def row(line: str, cell: str) -> str:
            cells = (inline(value.strip()) for value in line.strip().strip("|").split("|"))
            scope = ' scope="col"' if cell == "th" else ""
            return "<tr>" + "".join(f"<{cell}{scope}>{value}</{cell}>" for value in cells) + "</tr>"

        header = row(lines[0], "th")
        body = "\n".join(row(line, "td") for line in lines[2:])
        return f'<div class="table"><table><thead>{header}</thead><tbody>{body}</tbody></table></div>'

    for tag, pattern in (("ul", r"- (.+)"), ("ol", r"\d+\. (.+)")):
        entries = [re.fullmatch(pattern, line) for line in lines]
        if all(entries):
            items = "\n".join(f"<li>{inline(entry[1])}</li>" for entry in entries)
            return f"<{tag}>\n{items}\n</{tag}>"
    return f"<p>{inline(' '.join(line.strip() for line in lines))}</p>"


def render_user_guide(markdown: str) -> str:
    blocks = re.split(r"\n[ \t]*\n+", markdown.strip())
    content = "\n".join(render_block(block.splitlines()) for block in blocks)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TES3NP User Guide</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ margin: 0; background: Canvas; color: CanvasText; font: 1rem/1.6 system-ui, sans-serif; }}
  main {{ max-width: 48rem; margin: auto; padding: 2rem 1.25rem 3rem; }}
  h1, h2 {{ line-height: 1.25; }}
  h2 {{ margin-top: 2rem; border-bottom: 1px solid GrayText; padding-bottom: .3rem; }}
  li + li {{ margin-top: .35rem; }}
  code {{ font-size: .93em; overflow-wrap: anywhere; }}
  a {{ color: LinkText; }}
  .table {{ overflow-x: auto; }}
  table {{ width: 100%; border-collapse: collapse; }}
  th, td {{ padding: .55rem .7rem; border: 1px solid GrayText; text-align: left; vertical-align: top; }}
</style>
</head>
<body>
<main>
{content}
</main>
</body>
</html>
"""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    source = args.source.read_text(encoding="utf-8-sig")
    args.output.write_bytes(render_user_guide(source).encode("utf-8"))
