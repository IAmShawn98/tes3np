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
# Editable raster masters belong in source control, not in the runtime EXE.
# The login overlay loads matching .ico files; neither these PNG originals nor
# the 1.6 MB branding PNG are requested by any live AHK/ChatHost component.
for directory in ("assets", "patches"):
    for path in (root / directory).rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if relative == "assets/icons/tes3np.png" or (
            relative.startswith("assets/icons/species/") and path.suffix.lower() == ".png"
        ):
            continue
        resources.append(path)
for name in ("import-macro.ps1", "patch-tes3mp.ps1", "toggle-expansion-pack.ps1", "import-expansion-pack.ps1", "select-expansion-package.ps1", "tes3np-updater.ps1", "fetch-release-notes.ps1"):
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
    relative = path.relative_to(root).as_posix().replace("/", "\\")
    if '"' in relative:
        raise SystemExit(f"Unsupported resource name: {relative}")
    parent = str(Path(relative).parent).replace("/", "\\")
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
