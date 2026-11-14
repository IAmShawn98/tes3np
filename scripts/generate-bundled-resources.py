"""Generate AutoHotkey v2 FileInstall statements for the standalone Windows build.

Run from the repository root after copying the project to a staging directory.
The generated include is build-only and is not required for source execution.
"""
from pathlib import Path
import hashlib
import sys

root = Path(sys.argv[1]).resolve()
output = root / "src" / "app" / "bundled-resources.generated.ahk"
# List runtime artwork, the font and its license, and the launcher workers.
# Keep editable PNG masters and checkout-only files out of the executable.
required = (
    "assets/backgrounds/launcher.png", "assets/backgrounds/character-book.png",
    "assets/controls/button.png", "assets/controls/scroll-panel.png",
    "assets/fonts/MysticCards.ttf", "assets/fonts/MysticCardsFontLicense.txt",
    "assets/happy-hour/jiub-happy-hour.png", "assets/happy-hour/pixie-dust.png",
    "assets/headings/quest.png", "assets/headings/together.png", "assets/icons/tes3np.ico",
    "scripts/import-macro.ps1", "scripts/toggle-expansion-pack.ps1",
    "scripts/import-expansion-pack.ps1", "scripts/select-expansion-package.ps1",
    "scripts/tes3np-updater.ps1", "scripts/fetch-release-notes.ps1",
)
resources = []
for name in required:
    path = root / name
    if not path.is_file():
        raise SystemExit(f"Missing bundled resource: {path}")
    resources.append(path)
for species in ("argonian", "breton", "dark-elf", "high-elf", "imperial",
                "khajiit", "nord", "orc", "redguard", "wood-elf"):
    icon = root / "assets/icons/species" / f"{species}.ico"
    if icon.is_file():
        resources.append(icon)

digest = hashlib.sha256()
for path in sorted(resources):
    digest.update(path.relative_to(root).as_posix().encode("utf-8"))
    digest.update(hashlib.sha256(path.read_bytes()).digest())
version = digest.hexdigest()
# Content-addressed extraction prevents a new launcher overwriting files
# currently in use by an older running executable.
resource_id = "v-" + version[:20]
(root / "bundled-resource-id.txt").write_text(resource_id + "\n", encoding="ascii")

lines = [
    "; Generated at build time. Do not edit.",
    "PrepareBundledResources()",
    "{",
    "    global BundledResourceRoot",
    f'    BundledResourceRoot := A_AppData "\\tes3np\\resources\\{resource_id}"',
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
    source = path.relative_to(root)
    relative = source.as_posix().replace("/", "\\")
    if '"' in relative:
        raise SystemExit(f"Unsupported resource name: {relative}")
    parent = source.parent.as_posix().replace("/", "\\")
    lines.append(f'    DirCreate(BundledResourceRoot "\\{parent}")')
    # Source of FileInstall must be literal for Ahk2Exe. Bounded retries
    # tolerate transient scanner/indexer locks without hiding real failures.
    lines.extend([
        "    Loop 3",
        "    {",
        "        try",
        "        {",
        f'            FileInstall("{relative}", BundledResourceRoot "\\{relative}", 1)',
        "            break",
        "        }",
        "        catch as err",
        "        {",
        "            if A_Index = 3",
        f'                throw Error("Cannot extract bundled asset: {relative}. " err.Message)',
        "            Sleep(350)",
        "        }",
        "    }",
    ])
lines.extend(['    try FileDelete(versionFile)', f'    FileAppend("{version}", versionFile, "UTF-8")', "}", ""])
output.write_text("\n".join(lines), encoding="utf-8")
print(f"Generated {len(resources)} embedded resources")
