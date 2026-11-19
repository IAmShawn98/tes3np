# Macro packages

## Importing and using a package

Open **Manage Characters** and click **Upload Macro**. Select a single `.ahk` script, a ZIP of scripts and assets, or an installed `.exe` to link it. ZIPs can have any folder layout and need no manifest, provided they contain an `.ahk` script. Include supporting assets and include files in a ZIP; direct script import copies only the selected script. RAR and 7z are not supported by this built-in importer.

The launcher extracts the ZIP asynchronously and installs it under `%APPDATA%\tes3np\macros`. It does not execute imported files. Select the installed macro and click **Run**; a trust confirmation appears before running its script. **Stop** ends that tracked macro process. **Remove** deletes its installed copy, with confirmation, and retains the original ZIP.

Closing Manage Characters leaves macros running. Quitting TES3NP stops its tracked script macros. Linked applications remain open. Child processes spawned by a macro are outside the launcher’s process tracking. Macros retain their own hotkeys, user interfaces and configuration behavior; the launcher does not rewrite them or ensure compatibility with server rules. Avoid running macros with conflicting hotkeys together.

This is a local package manager. It does not publish uploads to a server or download a public catalog.

## ZIP contents

Include the main `.ahk` script and any supporting files it needs. Folder structure is preserved. One script is selected automatically. If several `.ahk` files exist, the user chooses the entry script during import.

Optionally put `macro.ini` at the ZIP root to identify the package:

```ini
[Macro]
Name=My Fishing Macro
Description=Fishing controls for TES3MP.
Entry=src\main.ahk
```

Entry must point to an existing `.ahk` file inside the ZIP. Use `#Requires AutoHotkey v2.0` for v2 scripts. The packaged launcher runs scripts with its bundled AutoHotkey v2 interpreter. Running TES3NP from source uses the interpreter that launched it.

The importer accepts ZIPs up to 25 MiB and 500 entries. Expanded contents can total up to 50 MiB, with a 25 MiB limit per entry. It rejects absolute paths, parent traversal, duplicate paths, file and folder name conflicts, Windows device names, and symbolic links. Import requires Windows PowerShell and uses the bundled `scripts/import-macro.ps1` helper.

The launcher reserves `.tes3np-package.ini`, `.import-success`, and `.import-error` at the ZIP root for its own records. Installed scripts may write their own settings inside their package folder. Removing a package also removes those local files.

## Macro-owned hotkeys

TES3NP does not configure or interpret hotkeys inside imported macros. The **Run** button executes the selected .ahk script or linked app; **Stop** ends the process started by TES3NP. Any keyboard shortcuts, hotkey menus, pause/resume controls, and persistent key settings must be implemented by the author of each macro.

Macro authors can use AutoHotkey v2's `Hotkey()` function and a local settings file (for example, `fishing.ini`). A macro can provide its own temporary key picker or use hardcoded shortcuts; TES3NP imposes no special manifest declarations or integration API. Previously installed macro packages remain installed and executable, but any legacy `[Bindings]` declarations are ignored and existing per-package `.tes3np-bindings.ini` files are not modified by this change.
