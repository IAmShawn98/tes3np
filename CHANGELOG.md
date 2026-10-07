# Changelog

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
