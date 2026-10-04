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

## Configurable key bindings

Compatible macros prompt for their keys after import. **Edit Bindings** changes them later while the macro is stopped. Cancelling the import-time prompt keeps the macro installed; Run prompts again until valid bindings have been saved. Choices persist per installed package, across launcher restarts. Up to 12 single keys are supported; key combinations are not supported yet. The launcher does not infer the meaning of hardcoded keys in arbitrary scripts or rewrite their source.

For a ZIP, add declarations to the root `macro.ini`:

```ini
[Bindings]
Fish=C
ReadyWeapon=F
Potion1=2
Potion2=3
Potion3=4

[BindingLabels]
Fish=Sneak / Fish
ReadyWeapon=Ready weapon
Potion1=First fishing potion slot
Potion2=Second fishing potion slot
Potion3=Third fishing potion slot
```

For a directly imported `.ahk` file, declare the same information in comments instead:

```autohotkey
; @tes3np-key Fish|Sneak / Fish|C
; @tes3np-key ReadyWeapon|Ready weapon|F
```

Declarations alone are not enough: the macro must read the saved values and use them for its actions. The launcher supplies the INI path in the child process environment variable `TES3NP_BINDINGS`. An AutoHotkey v2 macro reads it like this:

```autohotkey
bindingsFile := EnvGet("TES3NP_BINDINGS")
fishKey := bindingsFile != "" ? IniRead(bindingsFile, "Bindings", "Fish", "C") : "C"
; At the appropriate point in the macro:
Send("{" fishKey "}")
```

Use matching IDs (`Fish`, for example) in declarations and code. Store defaults in the script so it can also run independently. Launcher settings live in `.tes3np-bindings.ini` in the installed package folder; removing the package removes its bindings. The launcher restores its own environment immediately after starting the macro. Packages without declarations have Edit Bindings disabled and continue to run normally.

Import `examples/key-bindings-demo.ahk` to try the complete flow. This small v2 example shows its loaded bindings and sends one action with F8 or F7 only when an SDL game window is active. F9 exits. It is a binding demonstration, not an automatic fishing macro.

On Windows, also verify import-time Save/Cancel, invalid keys, persisted choices after restart, Edit Bindings, disabled editing while running, and that the child script receives the chosen keys.
