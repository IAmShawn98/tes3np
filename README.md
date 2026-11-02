# TES3NP — Nerevarine Prophecies launcher

TES3NP is a Windows x64 launcher for the Nerevarine Prophecies TES3MP server. It supports saved characters, manual one-character-at-a-time automated login (up to four running game clients), optional custom TES3MP clients, Game Chat, and the optional NP Expansion Pack.

**Status: development alpha — not approved for public redistribution.** The packaged modified TES3MP executable still requires corresponding source/build provenance and a completed third-party licensing audit before a public release.

## Requirements

- Windows 10 or Windows 11 (64-bit).
- A legitimate installation of **Morrowind Game of the Year Edition** with Tribunal and Bloodmoon.
- WebView2 Runtime for embedded Discord Game Chat. The rest of the launcher should work without WebView2.

The **complete Windows ZIP includes TES3MP 0.8.1** and its client dependencies, plus an official AutoHotkey v2 interpreter in `runtime/AutoHotkey64.exe` for installed macros. You do **not** need to install AutoHotkey, Python, or the .NET SDK to run a finished ZIP. Keep the `runtime` folder beside `tes3np.exe`; Morrowind game files are **not** included.

## Installing a packaged build

1. Obtain an approved complete Windows ZIP or private test artifact.
2. Extract `tes3np-windows.zip` into a writable folder such as `Documents\TES3NP`. Keep `tes3np.exe`, `client`, `chat-host`, and the other packaged folders together.
3. Run `tes3np.exe` normally. If Morrowind GOTY is not found, use the folder picker.
4. Choose **Manage Characters** to add or edit characters. Optional custom clients and the Expansion Pack are configured separately.

The Expansion Pack is **optional** and controlled globally by the launcher button. Close game clients before toggling it. The launcher maintains settings, profiles, logs, and custom-client overrides under `%APPDATA%\tes3np`; do not delete this directory during upgrades.

**Export Data warning:** Exported character backup files contain readable passwords. Keep them private and never attach them to public issues.

## Building from source

See [development instructions](docs/DEVELOPMENT.md) and [release procedure](docs/RELEASING.md). The Windows source build requires Python, the Windows PowerShell environment, a .NET SDK, and downloads of AutoHotkey/Ahk2Exe and the official TES3MP runtime. Run `Build tes3np.bat` after acquiring the complete source and verified payloads.

## Documentation

[Install and troubleshoot](docs/INSTALLATION.md) · [User guide](docs/USER-GUIDE.md) · [Alpha verification](docs/ALPHA-COMPATIBILITY-CHECKLIST.md) · [Release gates](docs/RELEASING.md) · [Report an issue](../../issues)

TES3MP's upstream project identifies its license as GPLv3 with additional permitted terms. Do not publicly distribute a modified TES3MP binary without the required corresponding source and applicable notices.
