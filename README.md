# tes3np — Nerevarine Prophecies Launcher

A Windows launcher for the Nerevarine Prophecies TES3MP server, written in AutoHotkey v2.

## Getting started

1. Install AutoHotkey **v2** on Windows.
2. Extract the entire `tes3np` folder into your TES3MP 0.8.1 Win64 folder. Keep `src`, `assets`, `scripts` and `patches` beside `tes3np.ahk`.
3. Run `tes3np.ahk`. Startup checks the installed patch files and EP configuration.
4. If setup is needed, click **Patch Tes3mp**. Confirm the detected TES3MP folder, Morrowind GOTY folder and active OpenMW user configuration. Read the EP license and click **Install / Repair**.
5. Once verification succeeds, open **Returning Fetcher** (or **Manage Characters**), add your username and password, review the login delays, and save.

Before setup is verified, the main menu contains only **Patch Tes3mp**, **Our Wiki** and **Quit Launcher**. The normal menu and character startup choice become available afterward. An already matching installation skips file changes. Patching remains available through the tray menu.

The supplied markerless `tes3mp.exe` replaces the client executable. EP files are merged into Morrowind's existing `Data Files`; unrelated files are retained. `NP Expansion Pack.esp` is enabled exactly once at the bottom of the selected `openmw.cfg` load order. A fresh user configuration receives the three official masters and the Morrowind data path. Existing load orders missing those masters must be configured first. Direct connect already uses the NP server address when launching through tes3np; no separate BAT file is required.

This package bundles the supplied patches, not the full TES3MP client or Bethesda's base game files. See [Patching and recovery](docs/PATCHING.md) for backups, configuration scope and testing.

## Launching characters

- **Play** beside a character launches it without changing your saved default.
- Tick one character to make it your default. **Launch <character>** uses that choice.
- **Launch All & Close** appears with two or more saved characters. It launches them in list order, waits 10 seconds after each configured loading delay, closes that game client, and moves to the next. The launcher stays open afterward. Its explanation includes a saved **Don't show me this again** option.
- **Auto reconnect on close or crash** is saved separately for each character under Edit. It defaults to on and applies on the next launch. Turn it off if you want to close the game without it restarting. In a batch, a failed character with reconnect off is skipped.
- **Start New Adventure** launches once without saved login input or automatic recovery.

**Wipe Character Data** appears when at least one character exists. It asks for confirmation before removing all saved character credentials and the favorite selection, and stops active automation. It does not delete in-game characters or the executable setting. Export first if you need a backup. With no characters, Add character moves beneath the introductory description and Import Data becomes available.

Up to 10 characters can be saved. Remove asks for confirmation. Adding a character does not change your ticked default.

With no saved characters, startup opens the launcher. After setup is verified and a character exists, startup offers **Launch <character>**, **Manage Characters**, or **Open Launcher**, preferring the ticked character and otherwise using the first saved character.

Closing the character page returns to the main launcher, including after opening it from the startup choice.

Use the tray menu to **Open Launcher** or **Stop game recovery**. Quitting the launcher stops automation and leaves any running game open.

## Moving to another computer

**Export Data** at the lower-right of the character book saves a portable INI backup containing characters, passwords, login delays, reconnect choices, the ticked default, executable path and launch-all explanation preference. Export warns that passwords are readable in this file. Keep it private; do not share or commit it.

With an empty character list, this button becomes **Import Data**. Select a backup created by Export Data. Import validates it before replacing settings and encrypts passwords for the destination Windows account. An executable path that does not exist there is cleared; use Browse to select TES3MP again. Copying the normal encrypted `settings.ini` is not a portable password backup.

## Login and recovery

Login uses foreground keyboard input and each character's configured delays. Avoid typing during credential entry. These delays do not verify the contents of login screens or prove that the server accepted the login or awarded daily points.

Status tooltips appear inside the active TES3MP game window during login. They show countdowns and current steps, disappear when the configured character-loading wait finishes, hide when you switch away, and never attach to the terminal. Crash monitoring continues without a tooltip.

The controller checks its tracked process and visible SDL game window every second. A terminal window does not qualify. Game-window startup allows 30 seconds; enabled recovery waits 5 seconds before retrying. Only the launched process is managed.

**Our Wiki** opens https://wiki.nerevarineprophecies.com/Main_Page. **Macros** opens the local ZIP macro manager. Import `.ahk` files directly or ZIP packages, choose their main `.ahk` script, then run, stop or remove them. See [Macro packages](docs/MACRO-PACKAGES.md) for the ZIP format and requirements. Imported scripts can execute code; only run packages you trust.

## Saved data

Settings are stored in `%APPDATA%\tes3np\settings.ini`, separate from the extracted application. Passwords are encrypted with Windows DPAPI under the current Windows account. Do not commit or share your settings file.

Loading-overlay failures are recorded in `%APPDATA%\tes3np\render-errors.log`. Patching activity is recorded in `patch-all.log` and patch failures in `patch-errors.log` in the same folder. Logs omit personal paths and credentials. Patch backups are stored separately under `patch-jobs`.

## Contributing and releases

- [Contributor guide](CONTRIBUTING.md): branches, review and code conventions.
- [Architecture](docs/ARCHITECTURE.md): module ownership and runtime contracts.
- [Development](docs/DEVELOPMENT.md): source map and Windows validation checklist.
- [Releases](docs/RELEASING.md): GitHub setup and packaging.
- [Changelog](CHANGELOG.md): build history.

From the repository root, run `python scripts/project.py check`. On Windows,
run `powershell -NoProfile -File scripts/check-powershell.ps1` to parse helpers
without executing them. `python scripts/project.py package` creates a complete
ZIP in `dist/`. GitHub CI runs source/payload checks and the Windows PowerShell
parser. GUI and game behavior still require manual Windows testing.

Source-only downloads include code and artwork but omit the large patch payload.
Copy `patches/` from a complete build before running the installer. Place this
folder's contents at the GitHub repository root so its workflow is recognized.
No repository connection, branch protection or publication has been performed.

Compatible macros support saved key bindings through an import-time prompt and
**Edit Bindings**. See [Macro packages](docs/MACRO-PACKAGES.md) and the runnable
`examples/key-bindings-demo.ahk`. Existing scripts must explicitly support this
feature to use the chosen keys.
