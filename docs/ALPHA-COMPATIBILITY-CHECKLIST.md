# TES3NP alpha compatibility and recovery test matrix

Status: **not yet release-approved**. Run these checks against a packaged Windows artifact, not just the source-tree development launcher. Preserve test logs and record OS version, edition, CPU architecture, install path, and whether WebView2 exists. Never publish character passwords.

## Verified on an existing Windows development machine

The following were reported as passed by the project tester on October 29,
2026; they are **not** substitutes for clean-machine testing:
- Complete local Windows build: PowerShell parser, source linter, AHK compile,
  launcher `--check`, 143 embedded payload hashes, and final ZIP integrity.
- Disposable updater transaction tests: six passed, including incomplete
  package rejection and rollback after simulated failures.
- Extracted standalone ZIP: character import (after the integer-control fix),
  character editing and launching, data export, Game Chat,
  and Expansion Pack enable/disable.
- C# warnings reduced from five to one `WindowsBase` dependency conflict.
- The shortcut-prompt persistence fix has **not** been re-verified after commit
  `12b942d`; keep it open.

## Work remaining for a tester

Test on a separate Windows user profile or VM with an isolated `%APPDATA%`
directory. **Do not delete a real user's launcher data or Morrowind directory.**
The most valuable remaining checks are Windows 10/11 without SDKs installed,
first-run discovery, WebView2 absence, update confirmation on a packaged build,
permissions errors, and shortcut prompt persistence after backup import.

## Clean installation
- [ ] Fresh Windows 11 x64 standard user, no AutoHotkey/.NET SDK/TES3MP installed: extract packaged ZIP to a normal user-writable directory; launcher opens.
- [ ] Windows 10 x64 standard user: same test, including a machine without WebView2. Missing chat must not prevent game launching.
- [ ] Install into a path with spaces and Unicode characters; verify resources and client paths.
- [ ] Move the extracted package to a different directory without deleting AppData; characters and settings remain available.
- [ ] Attempt startup from an incomplete ZIP extract: actionable missing-file error instead of silent exit.

## Morrowind detection and optional content
- [ ] Steam default library and Steam secondary library on D: or E:.
- [ ] GOG and manually chosen game folders; confirm all three GOTY masters are required.
- [ ] Select Data Files itself in the picker: the parent Morrowind directory is stored.
- [ ] Reject an incorrect folder without changing stored paths.
- [ ] New installation without Morrowind: first-run prompt offers selection or Not Now; optional pack remains disabled.
- [ ] Existing modded openmw.cfg: toggle Enabled/Disabled/Enabled, verify unrelated data/content entries untouched.
- [ ] Close clients required before toggle; failures produce a specific message.
- [ ] Read-only / Program Files game directory: no partial changes; user receives a permissions error.
- [ ] Intentionally interrupt an Expansion Pack operation in a disposable test copy; compare files and backups before reattempting.

## Client safety and updates
- [ ] Default bundled client and login work.
- [ ] Custom executable + dependency folder work; switching back to bundled preserves overrides.
- [ ] Replace custom exe with **same size and modification time** but different contents; cache must invalidate.
- [ ] Interrupt a custom-client override replacement between moving old overrides and installing new overrides; next startup restores previous overrides.
- [ ] Update launcher package without deleting %APPDATA%\\tes3np: saved profiles, login delays, custom overrides and preferences persist.
- [ ] Two simultaneous launcher instances and an active game during update: no corruption.
- [ ] Low disk space or antivirus-locked custom asset: operation fails safely with logs and leaves previous configuration intact.

## Chat, UI, diagnostics
- [ ] WebView2 installed vs missing; missing chat does not block launching game.
- [ ] Automatic new-message chat expansion while a modal dialog is open: no focus theft or hidden prompt.
- [ ] High DPI (100%, 125%, 150%) and two monitors; chat remains on-screen where possible.
- [x] November 5 Copy Launcher Logs export: 2,713 timestamped lines, useful event details, no visible passwords, personal paths, URL/email/IP/long IDs, privacy placeholders, duplicate timestamps or empty pipes. (Applies to this supplied Launcher Log only.)
- [ ] After rebuilding, verify fresh `launcher.log`, `chat-host.log`, updater events and copied Expansion Pack/render logs remove Windows usernames, absolute paths, email addresses, tokens and passwords **without** `REDACTED`, `[path omitted]`, empty labels or extra `|` separators. Useful event details and public character names must remain.
- [ ] On first startup, confirm historical diagnostics (including `PrivacyScrubVersion=1` placeholders) are cleaned under version 4 without touching `Logs/game-chat.log`, `Logs/game-chat-index.json`, settings, saved profiles, macros, portraits or private WebView2 data. Never attach the raw Game Chat archive to a bug report.
- [ ] Confirm the disposable AutoHotkey diagnostic privacy fixture passes as part of the normal Windows build, and exercise Game Chat, Happy Hour, macros and login afterward.
- [x] Source-side privacy review covers the AHK launcher, Chat Host, updater, import/toggle/picker result files, macro worker, clipboard and user-facing error boundaries. Source changes and regression guards are committed; see [diagnostic privacy audit](DIAGNOSTIC-PRIVACY-AUDIT-2026-11-04.md).
- [ ] Confirm `PrivacyScrubVersion=4` processes pre-existing v2 logs, preserves public character names, and removes placeholder fields without touching the private journal, backups, settings or Discord archive.
- [ ] Inspect `result.ini` for `Backup=available` rather than an absolute path, and verify private `journal.json` still supports rollback. Check toggle and picker failures still show meaningful safe messages.
- [x] November 5 full Windows build of alpha `24a2359` passed: PowerShell parse, AHK privacy/plugin-mismatch fixtures, Chat Host compile/publish, Expansion ZIP/folder fixture, picker COM, Ahk2Exe, compiled `--check`, packaged assets/hashes and final ZIP integrity. MSB3277 WindowsBase warning is nonfatal.
- [ ] Independently launch and test the freshly extracted standalone ZIP, not only the repository-root executable.
- [x] November 5 fresh Launcher Log copy shows both previously merged timestamps on separate lines; no malformed event lines in the 2,713-event export.
- [ ] Confirm the underlying on-disk migrated launcher.log ends with a newline and remains append-safe after repeated fresh launcher sessions (clipboard export alone cannot prove its terminal newline).

- [ ] Run the read-only consolidated audit `python scripts/audit-local-privacy.py` after pulling the new test utility. Review PASS/REVIEW/SKIP category counts for actual Chat Host, Expansion Pack, render, launcher and importer-result files, and updater offline fixtures. No raw logs or private Discord archive should be shared. Missing optional log files are not proof of a pass.
- [ ] If PowerShell 7 is unavailable, mark the isolated updater transaction/rollback fixture SKIPPED, not passed. It can be rerun later without touching a real installed game.
- [ ] In one live session, check character launch/login, first-favorite behavior, custom portrait, macros, Game Chat/Happy Hour, Expansion Pack toggle and optional ZIP import in a disposable game installation. Confirm stored preferences and chat remain available without opening or copying private chat archives.

## Distribution/legal
- [ ] Ship all required licenses and third-party notices.
- [ ] Publish corresponding source and build instructions for any distributed modified GPL-covered TES3MP executable.
- [ ] Validate complete build artifacts and hashes on CI, then test the actual extracted Windows ZIP.
- [ ] Confirm no public alpha/release was pushed before these checks pass.

## November 2 source-retirement regression (local Windows only)

- [ ] Confirm the legacy Install / Repair, Verify and Restore Backup controls and tray entry do not appear. Never execute a bundled v0.1 repair against a working v0.2 installation.
- [ ] Open first-run Morrowind GOTY discovery and confirm saved folder selection works; no optional expansion is installed automatically.
- [ ] Open the supported Expansion Pack toggle and switch Disabled / Enabled / Disabled with the original mod load order preserved.
- [ ] Use the existing ZIP/folder importer on a disposable Morrowind installation; verify progress, success message, saved path, journal, rollback on intentionally bad input and unaffected unrelated mods.
- [x] Run source checks and the synthetic import fixture through the normal Build tes3np.bat workflow; GitHub Actions are not needed.
- [ ] Test characters and first-character favorite, macros selection/run/stop, custom-client mode, Enhanced Readability, backup export/import, and new-adventure login.
- [ ] Check Game Chat images/history scrolling, Discord authentication and genuine Happy Hour detection; avoid relying only on static source guards.
- [x] Run the local updater transaction and update-client fixtures in an isolated disposable test tree; do not update the live installation for this test.
- [x] Record build and runtime results separately: local full build and offline updater fixtures passed; five interactive feature groups were subsequently reported PASS by the user. See docs/CODEBASE-AUDIT-2026-11-02.md for the dates, confirmed scope, and outstanding limits.

**Automated local checkpoint:** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-local-regression.ps1` combines the existing Windows build preflight, disposable Expansion Pack import fixture, updater metadata/source tests and isolated updater rollback fixture; it launches the resulting executable for the manual checks above. A green offline result cannot substitute for interactive verification. Requires local PowerShell 7 for the updater transaction fixture. No GitHub Actions are invoked.

**November 2 Windows confirmation:** The user-provided log verifies a completed source/build/ZIP check (331 functions, 143 payload hashes, compiled launcher `--check`) and a passing `-SkipBuild` updater-regression run, including metadata tamper and isolated rollback fixtures. The runner launched `tes3np.exe`. This is not evidence that any interactive feature was exercised; all interactive checkboxes above remain open. One nonfatal `WindowsBase` MSB3277 dependency warning remains. No GitHub Actions were used.

## November 2 interactive feature acceptance — user-reported PASS

- [x] Manage Characters, favorites, and character launching
- [x] Installed Macros: select, run, and stop
- [x] Game Client Settings, Enhanced Readability, and backup export/import
- [x] Game Chat, image scrolling, and Happy Hour detection
- [x] Expansion Pack toggle and current-package import

All five categories above were explicitly marked PASS by the Windows tester after the verified offline suite. The originally listed fine-grained clean-machine, rollback, auth edge-case, package-import isolation and server tests remain unchecked where the tester supplied no specific evidence. Do not infer that the import target was disposable or that a specific new server-login attempt was completed from the broad PASS alone. Public release gates remain deferred; the known nonfatal WindowsBase MSB3277 warning remains open. No GitHub Actions were used.
