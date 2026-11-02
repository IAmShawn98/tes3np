# Changelog

## v0.1.21-alpha — unreleased

### Added

- Bundled standalone TES3MP 0.8.1 Windows runtime and self-contained Game Chat host, removing the requirement for a separately installed TES3MP client.
- Optional custom TES3MP executable and dependency overrides without replacing the bundled client.
- Restored the original main-page **Expansion Pack: Enabled/Disabled** button (also available from the tray).
- Moved Discord Expansion Downloads into the **Plugins Don't Match the Server** dialog. The existing Chat Host attaches a small native WebView2 child directly to the dialog. The download card now searches the newest end of the channel and uses Discord message snowflake ordering to select new ZIP uploads, with bounded history search and live signed-link refresh; selecting OK still runs the unchanged manual ZIP importer. The standalone Discord popup remains removed. Clicking a ZIP now opens the official signed download URL in the default browser via a validated, nonblocking native handoff, avoiding the embedded WebView2 freezing on large downloads. Added always-active **Download ZIP / Retry** button to the plugin-mismatch dialog, backed by a per-dialog, in-memory current signed URL and independent browser handoff on every click. A cancelled or incomplete download no longer depends on the embedded Discord card repainting before another request. Main ZIP button fix: hide the native Discord placeholder HWND as well as its embedded WebView, bring the overlapping filename button to the front and redraw it, and route it to the exact same request handler as Retry with diagnostic click-origin logging. Further freeze isolation: after discovering the current Discord ZIP, hide (do not destroy) the embedded WebView and display a native AutoHotkey clickable filename. Both it and Download ZIP / Retry now launch the signed URL with a separate Windows URL-handler subprocess instead of blocking AutoHotkey's UI thread with `Run(url)`. No prompt recreation, repeated WebView2 teardown, or download busy lock. The plugin-mismatch prompt now uses expanded user guidance and adds **Copy Diagnostic Info** to the action row. It produces a privacy-first structured report using only fixed issue indicators and counts from the configuration and latest client log, never raw logs, arbitrary mod filenames, personal paths or tokens. The misleading persistent **Starting Download...** text is removed from both the launcher and embedded card. Windows feedback showed the new Copy Diagnostic Info button failing; the follow-up removes the unnecessary post-assignment ClipWait, adds a safe minimal report fallback for diagnostic collection errors, and retries temporarily unavailable clipboard access while logging only safe error type/line metadata. Windows repeated-download verification is pending.
- Source, package integrity, updater transaction, and rollback validation checks.

- Detect server plugin/load-order rejections in new TES3MP client logs and show an Expansion Pack recovery dialog instead of retrying the failed launch.
- Add **Upload Expansion** to choose a manually downloaded NP ZIP/ESP, backed up and installed by a separate transactional worker. Server compatibility must still be confirmed in-game.
- Preserve existing characters, launcher settings, other mods and the bundled TES3MP client during the import; no automatic download is attempted.

- Expanded **Copy Diagnostic Info** into an actionable, privacy-filtered plugin-rejection report. It now differentiates Expansion Pack presence/position from duplicate or missing other plugins, identifies base masters and context-specific error indicators, and reports unavailable checks explicitly. It never includes raw logs, personal paths, arbitrary mod filenames or signed URLs. The confirmation says only **Diagnostic Info Copied!**, and the copied heading no longer includes SAFE or an unnecessary privacy disclaimer. Generic server rejection wording no longer counts as evidence of a separate load-order problem. Isolated AutoHotkey fixture checks now run in the Windows build; complete GUI/clipboard testing still requires Windows. Corrected reported `#Warn` issues: the diagnostic renderer no longer has an early multiline `Return` that made later fields unreachable, and the isolated fixture has inert stubs for normal launcher-only dependencies such as `PatchConfigurationPath`. The fixture now asserts that the last report fields exist, and its Windows build step fails on emitted warnings as well as a nonzero exit code.

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
