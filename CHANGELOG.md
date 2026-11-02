# Changelog

## v0.1.21-alpha — unreleased

### Added

- Replaced the mismatch recovery flow's separate ZIP/folder choice popup with one native Windows Explorer-style chooser. **Open ZIP** returns an official ZIP; **Use This Folder** returns the highlighted/current extracted folder from the same browser. A small native COM helper runs in a separate STA Windows PowerShell process, returns only the selected local path, and uses an owned window; existing staging, game-client checks, SHA-256 verification, backup and rollback remain unchanged. A noninteractive COM smoke test now runs during Windows build preflight; manual native-dialog and live import verification are still pending.


- Added a source chooser to the Expansion Pack mismatch recovery flow: **Select ZIP (Recommended)** or **Select Extracted Folder**. Folder imports locate an extracted `Data Files` tree (including when the chosen folder itself is `Data Files`) and use the existing PowerShell worker's staging, allowed extensions, path and link checks, file limits, SHA-256 verification, backups, and rollback. A disposable Windows fixture exercises ZIP imports, both folder layouts, and rejection of unsafe/unapproved files before packaging. The exact current Discord ZIP's complete file layout has not yet been independently inspected; unexpected `Data Files` entries fail closed rather than being skipped. Windows test/build and live import remain pending.

- Fixed a Windows build-preflight crash in `scripts/check-chat-architecture.py` after the upgraded mismatch renderer changed its function signature. The checker now handles missing or renamed source sections as ordinary contract failures rather than raising `IndexError`, and validates the new delayed-rejection capture, privacy-safe slot summary, and CNG fingerprint paths. The code remains unverified by a Windows build until the next local run.

- Improved the Expansion Pack mismatch popup's **Copy Diagnostic Info**: the existing login watchdog now gives TES3MP two ticks to flush its detailed discrepancy lines, classifies checksum differences, mismatched plugin-name slots and extra-client/server slots, and copies fixed counts and a bounded per-slot category summary (never arbitrary plugin names, log text, paths or credentials). The installed Expansion Pack ESP is fingerprinted by streaming SHA-256 plus file size; the report explicitly does **not** equate that hash with a verified server version. Added isolated parser, de-duplication, redaction and SHA-256 known-vector tests in the Windows build. Windows compile and live login/popup verification remain pending.

- Bundled standalone TES3MP 0.8.1 Windows runtime and self-contained Game Chat host, removing the requirement for a separately installed TES3MP client.
- Optional custom TES3MP executable and dependency overrides without replacing the bundled client.
- Restored the original main-page **Expansion Pack: Enabled/Disabled** button (also available from the tray).
- Moved Discord Expansion Downloads into the **Plugins Don't Match the Server** dialog. The existing Chat Host attaches a small native WebView2 child directly to the dialog. The download card now searches the newest end of the channel and uses Discord message snowflake ordering to select new ZIP uploads, with bounded history search and live signed-link refresh; selecting OK still runs the unchanged manual ZIP importer. The standalone Discord popup remains removed. Clicking a ZIP now opens the official signed download URL in the default browser via a validated, nonblocking native handoff, avoiding the embedded WebView2 freezing on large downloads. Added always-active **Download ZIP / Retry** button to the plugin-mismatch dialog, backed by a per-dialog, in-memory current signed URL and independent browser handoff on every click. A cancelled or incomplete download no longer depends on the embedded Discord card repainting before another request. Main ZIP button fix: hide the native Discord placeholder HWND as well as its embedded WebView, bring the overlapping filename button to the front and redraw it, and route it to the exact same request handler as Retry with diagnostic click-origin logging. Further freeze isolation: after discovering the current Discord ZIP, hide (do not destroy) the embedded WebView and display a native AutoHotkey clickable filename. Both it and Download ZIP / Retry now launch the signed URL with a separate Windows URL-handler subprocess instead of blocking AutoHotkey's UI thread with `Run(url)`. No prompt recreation, repeated WebView2 teardown, or download busy lock. The plugin-mismatch prompt now uses expanded user guidance and adds **Copy Diagnostic Info** to the action row. It produces a privacy-first structured report using only fixed issue indicators and counts from the configuration and latest client log, never raw logs, arbitrary mod filenames, personal paths or tokens. The misleading persistent **Starting Download...** text is removed from both the launcher and embedded card. Windows feedback showed the new Copy Diagnostic Info button failing; the follow-up removes the unnecessary post-assignment ClipWait, adds a safe minimal report fallback for diagnostic collection errors, and retries temporarily unavailable clipboard access while logging only safe error type/line metadata. Windows repeated-download verification is pending.
- Source, package integrity, updater transaction, and rollback validation checks.

- Detect server plugin/load-order rejections in new TES3MP client logs and show an Expansion Pack recovery dialog instead of retrying the failed launch.
- Add **Upload Expansion** to choose a manually downloaded NP ZIP/ESP, backed up and installed by a separate transactional worker. Server compatibility must still be confirmed in-game.
- Preserve existing characters, launcher settings, other mods and the bundled TES3MP client during the import; no automatic download is attempted.

- Expanded **Copy Diagnostic Info** into an actionable, privacy-filtered plugin-rejection report. It now differentiates Expansion Pack presence/position from duplicate or missing other plugins, identifies base masters and context-specific error indicators, and reports unavailable checks explicitly. It never includes raw logs, personal paths, arbitrary mod filenames or signed URLs. The confirmation says only **Diagnostic Info Copied!**, and the copied heading no longer includes SAFE or an unnecessary privacy disclaimer. Generic server rejection wording no longer counts as evidence of a separate load-order problem. Isolated AutoHotkey fixture checks now run in the Windows build; complete GUI/clipboard testing still requires Windows. Corrected reported `#Warn` issues: the diagnostic renderer no longer has an early multiline `Return` that made later fields unreachable, and the isolated fixture has inert stubs for normal launcher-only dependencies such as `PatchConfigurationPath`. The fixture now asserts that the last report fields exist, and its Windows build step fails on emitted warnings as well as a nonzero exit code.

- **Live mismatch evidence capture:** After a rejected login, the launcher now classifies the original client-log rejection before terminating the game, retaining only safe fixed indicator fields. **Copy Diagnostic Info** uses that captured evidence instead of attempting to reopen a potentially locked client log; if live evidence is absent, bounded file inspection remains a fallback. Each new game session clears prior evidence. This addresses a Windows report in which the configuration checked out but client-log inspection returned Read error. Exact cause of the secondary log-read error remains unverified; live-capture runtime checks remain pending.

### Fixed

- Fixed a Windows build failure in the new Expansion Pack lock-retry wrapper: nested PowerShell scriptblocks ran without their caller's local file path variables, leading to `The path is not of a legal form` and a failed rollback in the synthetic ZIP importer fixture. `InvokeLockRetry` now receives explicit path arguments and splats them into each hash/copy/replace/move/ZIP-open action. Copy retries also refuse preexisting destination files before any disposable cleanup. Fixed rollback bookkeeping to record only successfully committed atomic replacements, so a persistently locked target that was never changed is not unnecessarily restored (and falsely reported as an incomplete rollback). Added a regression assertion for this behavior. Updated fixture/architecture guards to protect these parameter bindings, including existing lock-exhaustion, rollback and successful re-import checks. Changes are committed and statically reviewed; Windows fixture and live v0.2 import remain unverified.

- Hardened official Expansion Pack v0.2 installation against transient Windows file sharing and byte-range locks (`ERROR_SHARING_VIOLATION`/`ERROR_LOCK_VIOLATION`, Win32 32/33), after a live import reported that another process locked part of a file and rolled back. Source-file hashing, staged asset copies, backup copies, and atomic game-file replacement now make up to six bounded retries only for those two OS errors; all other failures still stop immediately. Removed redundant per-replacement scratch backups because the persistent journal backup is already verified. Failure messages report the operation and file ordinal without exposing local paths. Added a synthetic Windows byte-range-lock regression that checks safe exhaustion without modifying game files, releases the lock, then verifies successful import and rollback backups. Existing archive path checks, streaming hashes and transaction rollback remain intact; live v0.2 re-test is pending.

- Fixed the legitimate NP Expansion Pack v0.2 ZIP being rejected as `Unpacked Expansion Pack exceeds the 1 GB limit.` The importer had hard-coded 1 GiB total and 128 MiB per-asset limits unrelated to TES3MP. Removed both artificial caps from ZIP, extracted-folder, and legacy ESP import paths while preserving filename/path validation, streamed bounded-memory extraction, size consistency and SHA-256 checks, file-count controls, pre-copy available-space checks on staging/backup/game volumes, and backup/rollback. Temporary staging is cleaned after success or failure; backups/journals remain. Updated synthetic Windows fixtures and architecture guards against reintroducing the limits. Actual v0.2 import still requires Windows runtime verification.


- Fixed the unified ZIP/folder Explorer picker failing at runtime with `The Expansion Pack browser is unavailable. Rebuild TES3NP.` The new `select-expansion-package.ps1` script had been created in source but omitted from `generate-bundled-resources.py`'s explicit embedded worker list. Added it to the generated FileInstall payload and therefore its content-addressed resource version, plus a Windows packaging gate that verifies both the extracted picker and existing import worker against their source SHA-256 hashes. This fixes the confirmed missing-resource root cause; rebuilt Windows EXE and actual picker UI remain to be tested.

- Fixed compiled launcher error after the unified Expansion Pack chooser introduced a reference to nonexistent AutoHotkey variable `A_Pid`. Its temporary selection filename now uses `DllCall("GetCurrentProcessId", "UInt")` (the Windows process ID). Added a pre-embedding `AutoHotkey64.exe /ErrorStdOut tes3np.ahk --check` build preflight to surface line-specific `#Warn` problems before Ahk2Exe emits a generic compilation failure. Windows rebuild and interactive ZIP/folder picker validation are pending.

- Fixed Windows PowerShell 5.1 ZIP fixture startup: the portable-ZIP test now explicitly loads both `System.IO.Compression` (defines `ZipArchiveMode`) and `System.IO.Compression.FileSystem` (provides `ZipFile` and its extension helpers) before constructing the fixture. Kept ZIP path validation and actual import logic untouched; Windows build rerun remains pending.

- Repaired the Windows ZIP/folder import regression fixture after a reported `The ZIP contains an unsafe file path` failure. On some Windows PowerShell/.NET Framework targets, `ZipFile.CreateFromDirectory` writes backslash-separated archive entries. The fixture now uses `ZipFileExtensions.CreateEntryFromFile` with explicit forward-slash names and independently verifies all ZIP entries; it also creates a deliberately unsafe backslash ZIP to confirm the production importer still rejects it and checks that other unsupported files fail for the intended reason. The production ZIP path safety validation is unchanged. Windows rerun and live import remain pending.

- Corrected the synthetic ZIP/folder build test: a live TES3MP/OpenMW process could trigger the production importer's game-running safety check even though the test uses disposable files. The fixture now clones the import script into a temporary sandbox, substitutes only that process guard in the disposable copy, and checks the destination remains inside its synthetic game directory. The real importer's safety check is unchanged. On future fixture failures, the build now prints the worker's `result.ini` error instead of an empty `output=`. Windows rerun remains pending.

- Corrected the Expansion Pack worker's existing ZIP extraction length check (and the matching new folder staging check): `System.IO.File.GetLength` is not a .NET API, so the importer now reads the staged `FileInfo.Length` before proceeding. All staged content still receives hash verification and the existing transactional backup/rollback.

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
