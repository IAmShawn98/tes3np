"""Generate AutoHotkey v2 FileInstall statements for the standalone Windows build.

Run from the repository root after copying the project to a staging directory.
The generated include is build-only and is not required for source execution.
"""
from pathlib import Path
import hashlib
import sys

root = Path(sys.argv[1]).resolve()
output = root / "src" / "app" / "bundled-resources.generated.ahk"
resources = []
for directory in ("assets", "patches"):
    resources.extend(p for p in (root / directory).rglob("*") if p.is_file())
for name in ("import-macro.ps1", "patch-tes3mp.ps1", "toggle-expansion-pack.ps1", "tes3np-updater.ps1", "fetch-release-notes.ps1"):
    path = root / "scripts" / name
    if not path.is_file():
        raise SystemExit(f"Missing bundled worker: {path}")
    resources.append(path)
if not resources:
    raise SystemExit("No resources to bundle")

digest = hashlib.sha256()
for path in sorted(resources):
    digest.update(path.relative_to(root).as_posix().encode("utf-8"))
    digest.update(hashlib.sha256(path.read_bytes()).digest())
version = digest.hexdigest()

lines = [
    "; Generated at build time. Do not edit.",
    "PrepareBundledResources()",
    "{",
    "    global BundledResourceRoot",
    '    BundledResourceRoot := A_AppData "\\tes3np\\resources"',
    "    if !A_IsCompiled",
    "    {",
    "        BundledResourceRoot := A_ScriptDir",
    "        return",
    "    }",
    '    versionFile := BundledResourceRoot "\\resource-version.txt"',
    f'    if FileExist(versionFile) && Trim(FileRead(versionFile, "UTF-8")) = "{version}"',
    '        return',
]
for path in sorted(resources):
    relative = path.relative_to(root).as_posix().replace("/", "\\")
    if '"' in relative:
        raise SystemExit(f"Unsupported resource name: {relative}")
    parent = str(Path(relative).parent).replace("/", "\\")
    lines.append(f'    DirCreate(BundledResourceRoot "\\{parent}")')
    lines.append(f'    FileInstall("{relative}", BundledResourceRoot "\\{relative}", 1)')
lines.extend(['    try FileDelete(versionFile)', f'    FileAppend("{version}", versionFile, "UTF-8")', "}", ""])
output.write_text("\n".join(lines), encoding="utf-8")
print(f"Generated {len(resources)} embedded resources")
