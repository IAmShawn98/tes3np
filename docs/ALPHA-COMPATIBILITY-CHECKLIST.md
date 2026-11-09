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

## Page transition pop-in and foreground exposure — pending interactive Windows verification

- [ ] After the user-confirmed pop-in fix, opening Launcher Settings must **not** throw `Target window not found` from the cloaked transparency setup; check both fresh and repeated Settings opens.
- [ ] Confirm **Settings**, **Manage Characters**, the Character Book's cached reopen and Close actions respond without multi-second delays; no full-system blank frame or new pop-in.
- [ ] Verify Settings still uses the identical parchment key and the full-width Close Settings button, and Character Book still preserves its magenta transparency and original controls.


- [ ] With the new staging, repeatedly enter/exit cached and fresh **Character Book**; check the book's painted text, character names, macro rows and themed controls appear together rather than after the parchment image.
- [ ] Reopen **Launcher Settings** several times and confirm the complete parchment, labels, dropdowns and original full-width Close Settings button display on the first frame. No black/background rectangle or transient default native face.
- [ ] Verify neither page remains invisible after launch/reopen, including when the launcher is resized, on another display scale, or when the window is reactivated from taskbar. The compositor helper must always uncloak, even if an intermediate update fails.


- [ ] Repeatedly open/close **Launcher Settings**: no unmasked dark rectangle, unpainted parchment, or native button flash before the completed Settings page becomes visible.
- [ ] Repeatedly open/close **Manage Characters**: the completed book appears correctly, and returning to the launcher does not briefly expose the desktop or unrelated foreground windows (such as OBS) between the two TES3NP pages.
- [ ] With other applications open behind the launcher, repeat Settings/Character Book transitions, including rapid clicks and Escape/Close; TES3NP preserves the correct foreground window and remains responsive.
- [ ] Check Launcher Settings still has the original full-width **Close Settings** button with no empty slot; Character Book editor/macro state and the cached return layout remain correct.
- [ ] Verify Game Chat, Happy Hour banner, display scaling, and Expansion Pack toggle are unaffected by page navigation. Source and CI checks are not substitutes for visual test.

## One-time first-launch shortcut and quiet contextual setup — pending Windows runtime check

- [ ] Launch a complete packaged executable with clean AppData: after its first paint, exactly one **desktop shortcut** Yes/No prompt appears. No GOTY or Discord sign-in prompt stacks with it; neither is requested until its own user action.
- [ ] Choose **No**, relaunch, and verify the desktop-shortcut prompt never returns; no .lnk is created.
- [ ] On a separate disposable clean profile, choose **Yes**: verify the Desktop .lnk targets the actual packaged tes3np.exe and is not recreated or reoffered on relaunch.
- [ ] Open Launcher Settings: **Close Settings** occupies the whole bottom row at the original position, with no Create Desktop Shortcut button and no empty half-row.
- [ ] Launch source-tree / incomplete packaged candidates: shortcut prompt is skipped instead of creating a broken .lnk. Existing saved DesktopShortcutChoice values are respected.
- [ ] Click **Start New Adventure** with GOTY missing: existing folder chooser appears and game does not start. **Not Now** postpones; next game launch asks again.
- [ ] Click Game Chat while signed out: the existing dedicated sign-in popup appears. **Not Now** hides it; Game Chat opens it again without a second Discord session.
- [ ] Enable Expansion Pack with missing assets while signed out: the same popup appears only after requesting the download, and the authenticated ZIP dialog follows successful login.
- [ ] Validate existing Happy Hour archive/live discovery and chat first-login handoff; offline processing must not depend on forcing the login popup open at startup.

## November 5 second-PC runtime regression gate — pending rebuilt candidate

The tester extracted a private packaged v0.1.21-alpha RAR on a second Windows PC. The launcher opened, the bundled game client started, Discord authentication and plugin-mismatch UI appeared. Seven user-reported issues were captured in screenshots. Changes are committed in the development branch but **have not been rebuilt or retested on that PC**.

- [ ] **Window fit:** first visible frame is already at its final scale; close/relaunch several times at 100%, 125%, and 150% display scaling. The launcher should not paint at full size then shrink, or forget manually selected scale.
- [ ] **Missing GOTY defer:** in a disposable user profile with no GOTY installation, choose **Not Now**; relaunch the app and confirm the existing Locate Morrowind GOTY chooser returns. No duplicate popups.
- [ ] **Missing GOTY launch guard:** attempt Launch Character and Start New Adventure without the three GOTY masters. Confirm neither starts TES3MP or displays `Plugin doesn't exist`; each requests the GOTY folder. Select a valid installation and retest launch.
- [ ] **Buttons:** use all primary launcher buttons and modal actions repeatedly, including fast clicks after returning from Characters and dismissing prompts. Each intended click should trigger once; no 3–4-click delay.
- [ ] **Discord login popup:** signed-out Game Chat and Expansion Pack download requests show one dedicated **tes3np - Sign in to Discord** window instead of expanding the chat side panel. Check **Not Now**, close/reopen via Game Chat, successfully sign in, and verify native chat/messages, scrollbar, and Happy Hour still work. No second Discord profile.
- [ ] **Expansion Pack status:** with a disposable OpenMW config, confirm a missing, zero-length, or moved ESP does not display **Enabled**, even if `content=NP Expansion Pack.esp` remains. Confirm a nonempty installed ESP in a separate configured `data=` folder and proper load order can show Enabled. **Server/version freshness remains unverified**—a nonempty ESP cannot prove it matches the latest official pack.
- [ ] **Repeat plugin mismatch:** deliberately reproduce a real server load-order rejection, Cancel its download dialog, then retry login. The dialog must reappear on each qualifying *new* mismatch; cancel pending Discord sign-in and retry too. No duplicate dialogs, stale auth or automatic downloading.
- [ ] **Regression after fixes:** re-run ZIP/folder importer, genuine Happy Hour detection, custom game client, saved profile login, macros, read-only privacy audit, and packaging checks.
- [ ] **Final standalone artifact:** build an exact HEAD candidate, verify SHA-256 and test extracted ZIP on the second PC. The original earlier RAR is not evidence these fixes work.

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

- [ ] **November 5 authenticated Expansion Pack handoff:** Starting with a signed-out Discord browser, click Enable with no installed ESP. Verify the branded **existing Game Chat login** appears first, no download dialog/browser child is shown before login, and authenticated channel discovery opens a single **Expansion Pack Not Installed** ZIP dialog. Verify that cancelled sign-in never opens a delayed dialog, and a subsequent attempt works.
- [ ] **November 5 already-authenticated handoff:** With Discord signed in, retry missing ESP and real plugin mismatch. Verify the same shared embedded Discord ZIP browser, proper mode-specific copy, working native download button/retry and ZIP/folder importer. Repeated clicks must not create duplicate dialogs/WebViews.
- [ ] **November 5 separate OpenMW data folder:** In a disposable config, install `NP Expansion Pack.esp` only in an additional configured `data=` folder (not Morrowind's main Data Files). Enable, disable and verify preserved mod entries. The synthetic fixture covers both cases but Windows execution remains pending.
- [ ] **November 5 installed-only toggle:** Run `scripts/test-expansion-toggle.ps1` (also in `Build tes3np.bat`), then enable, disable and re-enable an actually installed pack in a disposable Morrowind/OpenMW directory. Confirm no v0.1 files are copied, no existing mod or ESP changes, and config backups survive.
- [ ] **November 5 packaging:** Confirm `tes3np.exe` has no embedded `patches/` payload, the current `patches/manifest.json` lists only markerless client, extracted ZIP still has a complete `client/`, and missing pack never prevents the base game from launching.

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
- [x] **Game Chat loading/scrollbar visual regression (November 5):** The user reported “Fixed!” after testing the source change that restores the `Connecting to live chat...` status, removes the fake scrollbar, and reveals the real scroll control with authenticated messages. Reported visible UI issue accepted; full signed-out first-login reproduction, detailed build transcript, and independent Happy Hour/scroll/auto-hide regression coverage remain pending.
- [ ] Automatic new-message chat expansion while a modal dialog is open: no focus theft or hidden prompt.
- [ ] High DPI (100%, 125%, 150%) and two monitors; chat remains on-screen where possible.
- [x] November 5 Copy Launcher Logs export: 2,713 timestamped lines, useful event details, no visible passwords, personal paths, URL/email/IP/long IDs, privacy placeholders, duplicate timestamps or empty pipes. (Applies to this supplied Launcher Log only.)
- [ ] After rebuilding, verify fresh `launcher.log`, `chat-host.log`, updater events and copied Expansion Pack/render logs remove Windows usernames, absolute paths, email addresses, tokens and passwords **without** `REDACTED`, `[path omitted]`, empty labels or extra `|` separators. Useful event details and public character names must remain.
- [ ] On first startup, confirm historical diagnostics (including `PrivacyScrubVersion=1` placeholders) are cleaned under version 4 without touching `Logs/game-chat.log`, `Logs/game-chat-index.json`, settings, saved profiles, macros, portraits or private WebView2 data. Never attach the raw Game Chat archive to a bug report.
- [ ] Confirm the disposable AutoHotkey diagnostic privacy fixture passes as part of the normal Windows build, and exercise Game Chat, Happy Hour, macros and login afterward.
- [x] Source-side privacy review covers the AHK launcher, Chat Host, updater, import/toggle/picker result files, macro worker, clipboard and user-facing error boundaries. Source changes and regression guards are committed; see [diagnostic privacy audit](DIAGNOSTIC-PRIVACY-AUDIT-2026-11-04.md).
- [ ] Confirm `PrivacyScrubVersion=4` processes pre-existing v2 logs, preserves public character names, and removes placeholder fields without touching the private journal, backups, settings or Discord archive.
- [x] November 5: `python scripts/audit-local-privacy.py --self-test` passed; synthetic legacy repair and repeat-cleanup were successful. Then opt-in repair with `--repair-legacy-import-results --skip-updater` cleaned one historical result.ini, zero errors, and rescan passed all four importer result records (16 lines) without flagged private paths, usernames or backup fields. Only historical status metadata was targeted; no raw private journal was uploaded.
- [ ] Confirm a real existing import journal and backup remain usable in an isolated test or verified interaction; the scanner deliberately checks their presence only. Toggle/picker failure dialogs still need interactive validation.
- [x] November 5 full Windows build of alpha `24a2359` passed: PowerShell parse, AHK privacy/plugin-mismatch fixtures, Chat Host compile/publish, Expansion ZIP/folder fixture, picker COM, Ahk2Exe, compiled `--check`, packaged assets/hashes and final ZIP integrity. MSB3277 WindowsBase warning is nonfatal.
- [ ] Independently launch and test the freshly extracted standalone ZIP, not only the repository-root executable.
- [x] November 5 fresh Launcher Log copy shows both previously merged timestamps on separate lines; no malformed event lines in the 2,713-event export.
- [ ] Confirm the underlying on-disk migrated launcher.log ends with a newline and remains append-safe after repeated fresh launcher sessions (clipboard export alone cannot prove its terminal newline).

- [x] November 5 local read-only audit: launcher.log (2,714 lines), chat-host.log (11,255 lines), tes3mp-crash-query.txt (one line), on-disk launcher newline and all three updater regression fixtures passed. Four optional log categories had no records (SKIP, not PASS). One of four historical Expansion import result.ini files was flagged for an absolute path, Windows username and private Backup value.
- [x] November 5 post-repair local audit: launcher.log (2,824 lines), chat-host.log (11,255 lines), crash-query file (1 line), and all four Expansion import result.ini (16 lines) passed with **zero flagged categories**. Four optional patch/render/toggle log categories absent (SKIP). Three private settings/chat files present (3/3); no content read or non-mutation verified. Updater tests passed earlier and were intentionally skipped in this post-repair pass.
- [x] PowerShell 7 updater transaction/rollback fixture passed as part of the user-supplied November 5 local audit.
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
