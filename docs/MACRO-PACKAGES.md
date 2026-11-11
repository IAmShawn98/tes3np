# Macro packages

## Importing and using a package

Open Macros and choose **Import Macro**. A single `.ahk` file can be imported directly with no packaging. ZIPs can have any folder layout and need no manifest, provided they contain an `.ahk` script. Include supporting assets and include files in a ZIP; direct script import copies only the selected script. RAR and 7z are not supported by this built-in importer.

The launcher extracts the ZIP asynchronously and installs it under `%APPDATA%\tes3np\macros`. It does not execute imported files. Select the installed macro and click **Run**; a trust confirmation appears before running its script. **Stop** ends that tracked macro process. **Remove** deletes its installed copy, with confirmation, and retains the original ZIP.

Closing the Macros page leaves macros running. Quitting the launcher stops the macro processes it started. Child processes spawned by a macro are not tracked or stopped by the launcher. Macros retain their own hotkeys, user interfaces and configuration behavior; the launcher does not rewrite them or ensure compatibility with server rules. Avoid running macros with conflicting hotkeys together.

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

Entry must point to an existing `.ahk` file inside the ZIP. Put `#Requires AutoHotkey v2.0` in v2 scripts. Scripts launch with the current AutoHotkey interpreter; a compiled launcher asks the user to select an interpreter. For scripts requiring a different version, install that version and ensure its requirements are declared; the manager does not convert v1 scripts into v2.

Limits: 25 MB ZIP, 50 MB expanded, 500 archive entries. Absolute paths, parent traversal, duplicate paths and symbolic links are rejected. Import requires Windows PowerShell and uses the bundled `scripts/import-macro.ps1` helper. Import errors are shown without executing payload code.

Installed packages have a launcher-created `.tes3np-package.ini` record. Do not include this metadata or `.import-success` / `.import-error` marker files in your ZIP. Installed scripts may write their own settings inside their package folder. Removing a package also removes those local files.

## Release testing

On Windows, test a single-script ZIP, a multi-script ZIP, a manifest package with subfolders, cancellation, restart persistence, Run/Stop, missing scripts and malformed archives. Test Unicode and space-containing paths. Verify rejected traversal paths never create files outside staging. Static source checks do not establish runtime compatibility of imported macros.

## Macro-owned hotkeys

TES3NP does not configure or interpret hotkeys inside imported macros. The **Run** button executes the selected .ahk script or linked app; **Stop** ends the process started by TES3NP. Any keyboard shortcuts, hotkey menus, pause/resume controls, and persistent key settings must be implemented by the author of each macro.

Macro authors can use AutoHotkey v2's `Hotkey()` function and a local settings file (for example, `fishing.ini`). A macro can provide its own temporary key picker or use hardcoded shortcuts; TES3NP imposes no special manifest declarations or integration API. Previously installed macro packages remain installed and executable, but any legacy `[Bindings]` declarations are ignored and existing per-package `.tes3np-bindings.ini` files are not modified by this change.

When testing, confirm imported scripts can run and stop without any TES3NP binding prompts, and that the macro itself owns any hotkeys it needs.
