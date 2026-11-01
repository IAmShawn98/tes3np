# Changelog

## v0.1.21-alpha — unreleased

### Added

- Bundled standalone TES3MP 0.8.1 Windows runtime and self-contained Game Chat host, removing the requirement for a separately installed TES3MP client.
- Optional custom TES3MP executable and dependency overrides without replacing the bundled client.
- Restored the original main-page **Expansion Pack: Enabled/Disabled** button (also available from the tray).
- Moved Discord Expansion Downloads into the **Plugins Don't Match the Server** dialog. The existing Chat Host attaches a small native WebView2 child directly to that dialog and shows the latest genuine ZIP attachment as a clickable card; selecting OK runs the unchanged manual ZIP import worker. The previous standalone Discord popup is removed. Windows integration testing is pending. No expansion files are auto-installed.
- Source, package integrity, updater transaction, and rollback validation checks.

- Detect server plugin/load-order rejections in new TES3MP client logs and show an Expansion Pack recovery dialog instead of retrying the failed launch.
- Add **Upload Expansion** to choose a manually downloaded NP ZIP/ESP, backed up and installed by a separate transactional worker. Server compatibility must still be confirmed in-game.
- Preserve existing characters, launcher settings, other mods and the bundled TES3MP client during the import; no automatic download is attempted.

### Fixed

- Fixed the character backup import error caused by an absent legacy executable input control.
- Fixed recurring desktop-shortcut prompts by preserving the decision when importing backups or when shortcut creation fails.
- Fixed the updater parser to accept the nested package metadata produced by the public release generator.
- Removed four chat-host compiler warnings; a dependency-related WindowsBase warning remains.
- Strengthened update staging validation and preservation of unrelated files and user-customized chat settings.

### Validation pending

- Final Windows regression run against this exact revision.
- Upgrade verification from the actual published v0.1.20-alpha ZIP.
- Clean Windows 10/11 testing and completion of redistribution/source evidence.

## v0.1.20-alpha — 2026-10-07

### Fixed

- Fixed the main launcher layout scaling inconsistently across different display sizes and Windows scaling settings.

## v0.1.19-alpha — 2026-10-07

### Fixed

- Fixed launcher controls such as **Launcher Settings** being positioned incorrectly after startup on scaled displays.
- Fixed the main launcher scrollbar becoming misaligned on scaled displays.

## v0.1.18-alpha — 2026-10-07

### Added

- Replaced Daily Login with **Scheduled Events**, allowing you to create and manage multiple one-time or recurring events using either **Specific Time (IRL)** or **Countdown** timing. Scheduled Events will not interrupt an active TES3MP session.
- Added customizable hotkey support for starting Scheduled Events at the exact moment you need while in-game.
- Added Scheduled Event reminders with the option to automatically log in using your selected character when an event is due.
- Added missed-event notifications when returning to the launcher.

### Changed

- Streamlined the launcher flow by removing the old startup quick-launch screen and redundant **Launch All & Close** option.
- Improved the **Manage Characters** page with clearer descriptions, better spacing, and a more polished layout.
- Improved the **Launch Settings** area of Manage Characters.
- Improved **Launcher Settings** layout, spacing, controls, and readability.
- Updated launcher typography with a more consistent Morrowind-inspired appearance.
- Improved the main **Game Launcher** layout and presentation.
- Improved the **Update Available** notification so it appears on the main launcher only when a new tes3np update is available.

### Fixed

- Fixed manually closing TES3MP potentially causing an unwanted automatic relaunch.

## v0.1.17-alpha — 2026-10-05

### What's New

- Added safe automatic launcher updates with package validation and rollback protection.
- Added automatic launcher scaling for smaller and high-DPI displays.
- Redesigned Launcher Settings with interface text sizing, Enhanced Readability, and change previews.
- Added Daily Login scheduling to Manage Characters.
- Redesigned AppData tools with direct access to the AppData folder and individual log-copy actions.

### Fixes & Improvements

- Improved themed-button rendering and click reliability.
- Improved character management layout, action-button sizing, spacing, and Launch Settings visibility while adding or editing characters.
- Reordered the main launcher so Our Wiki appears above Macros.
- Various launcher UI and reliability improvements.

## v0.1.0-alpha — 2026-10-03

- Split entry wiring, lifecycle, renderer and window helpers into focused modules.
- Replace obsolete template/demo identifiers with launcher names.
- Centralize state, paths, endpoints, profile defaults and controller timings.
- Handle malformed saved character counts and enforce the ten-character load limit.
- Add collaboration documentation, issue/PR templates, formatting rules, CI and
  repeatable packaging. Retain the required payload EXE in Git.
- Preserve installer fixes and friendly setup-needed behavior from earlier development.
- Add a compiled Windows launcher with the custom tes3np icon and automatic GitHub Actions builds.

Validation: static source, payload hashes, package integrity, PowerShell parsing and
compiled-launcher validation. Full Windows GUI/TES3MP runtime testing is still required.
