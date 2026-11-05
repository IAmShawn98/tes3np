# Changelog

## v0.1.21-alpha — unreleased

> Internal development history. The launcher and eventual public release use `RELEASE_NOTES.md` for concise, player-facing changes compared with v0.1.20-alpha. Preserve this detailed record for troubleshooting and development handoffs.

### Quiet first launch: contextual setup prompts — 2026-11-05

- A Facilities 4 screenshot showed three simultaneous first-run windows: desktop shortcut offer, Locate Morrowind GOTY, and Discord sign-in. Startup no longer schedules shortcut and GOTY prompts. The existing GOTY guard still requests its chooser on saved-character or New Adventure launch (and on the actual game Run path), preserving Not Now and subsequent retries.
- Replaced the automatic shortcut offer with a deliberate **Create Desktop Shortcut** action beside Close Settings in Launcher Settings. Preserves the same safe compiled-distribution check and shortcut target; manual creation reports success.
- The existing authenticated ChatHost still initializes and monitors Discord/Happy Hour in the background, but its single reused Discord login popup remains hidden until a Game Chat click or user-requested Expansion Pack download. Not Now/close resets visibility intent; the same browser/profile is reused for login and later native Game Chat.
- Manual Game Chat and authenticated Expansion Pack requests made before WebView2 finishes initializing now record the explicit sign-in intent, so the popup becomes visible when ready instead of leaving a silent pending request.
- Added startup contract checks. **Source only**; Windows C#/AHK build and clean-profile UI testing pending. Verify background WebView2 authentication does not stall while its popup is hidden, and verify both user-triggered auth entrypoints independently.

### Final missing-GOTY recovery guard — 2026-11-05

- Extended the shared GOTY preflight to the tracked game's actual Run() path, protecting auto-reconnect/recovery as well as both manual launch buttons. A missing installation stops the monitored attempt, opens the GOTY folder selector and does not enter an endless reconnect loop.
- Static source contract now requires this third guard. Windows packaged-build validation and interactive recovery testing remain pending.

### Source regression contracts for second-PC issues — 2026-11-05

- Extended the existing Python Chat Host architecture preflight with static source guards for GOTY selection and launch preflight, installed-ESP toggle status, fresh Discord recovery handshake, hidden launcher startup fit, custom-button mouse-release targeting, and the dedicated WebView2 login popup. Windows compile and UI tests remain required; source checks are not a substitute.
- Hardened the installed-pack lookup to avoid constructing a root-relative fallback path when no Morrowind directory is configured. Used explicit System.Drawing.ContentAlignment for the new WinForms labels to avoid relying on implicit namespace imports.

### Dedicated Discord sign-in popup — 2026-11-05

- Replaced the oversized docked Discord login presentation with a separate, native launcher-owned "Sign in to Discord" window. Reuses the existing ChatHost WebView2 and Roaming profile (not another Discord session), includes plain-language purpose and Not Now, and keeps the normal Game Chat panel hidden rather than stretching it.
- The Game Chat tab reopens the sign-in window after dismissal. Missing-pack download requests can bring it forward and still require authenticated live Discord; cancellation clears pending authorization. On successful channel sign-in, the original browser is reparented to Game Chat, the popup is disposed, and the native connecting state plus single channel reload remain.
- Added source contracts protecting ownership, normal chat dimensions, and the existing WebView2 reuse. Windows compilation and OAuth/first-login tests are **pending**, including popup close/reopen, cancellation, high-DPI placement and original Happy Hour/feed functionality.

### Second-PC layout and mouse-input follow-up — 2026-11-05

- First launcher show now applies its existing automatic/manual scale while hidden, then reveals the completed frame without visibly resizing a 960x716 window. Cached geometry is reused on subsequent shows rather than only via the character-book shortcut; display-settings changes still use their existing fallback relayout.
- Improved custom themed-button mouse-up recovery when Windows returns release to a parent rather than the actual button after a focus/capture transition. It uses the current hovered child and same top-level window check; regular scrollbar dragging and normal capture release remain unchanged.
- Source edits only; need Windows visual checks on the secondary PC at different DPI levels, plus repeated first-click tests and game/chat regression. The root cause of every intermittent click has not been independently reproduced here.

### Second-PC regression fixes, first source batch — 2026-11-05

- User's second-PC screenshots confirmed the launcher, bundled game client and Discord/mismatch UI operate, but documented seven runtime issues. This batch addresses missing GOTY guard/prompt persistence, a stale optional Expansion Pack Enabled indicator, and a stale Discord recovery request.
- "Not Now" now defers GOTY setup to the next launcher startup; launching any character or Start New Adventure without valid Morrowind, Tribunal and Bloodmoon data opens the existing GOTY chooser rather than starting a game that errors with "Plugin doesn't exist". Exactly one chooser is shown at a time.
- "Expansion Pack: Enabled" now requires a current OpenMW load-order entry plus a present nonempty ESP in a configured game/data folder. This is *not* proof the installed pack is current with the server; no authoritative local pack-version manifest is known.
- New launches clear unresolved prior authenticated download requests on both the AHK and C# sides, without bypassing Discord authentication for downloads.
- Source edits only. Windows build and all runtime checks remain pending. Window resize, button hit testing, and separate Discord sign-in popup are still open.

### Windows local build post-package sharing violation — 2026-11-05

- A user Windows transcript at d4e37b3 confirmed PowerShell syntax, AHK compilation and compiled --check, Chat Host publish, Expansion Pack fixture tests, resource extraction, and final ZIP integrity all passed; nevertheless Build tes3np.bat showed a sharing violation and BUILD FAILED after the completed distribution ZIP. This is post-package failure, not evidence of a broken compiled launcher. Exact locked file was not identified from the log.
- Updated build-windows.ps1 to retry cleaning only its own GUID-named scratch directory with managed .NET filesystem operations, without native cmd/rmdir status or console leakage. A cleanup lock is now explicitly nonfatal to validated packaging; earlier build/validation exceptions still fail.
- The existing Build tes3np.bat now identifies the precise local deployment stage on failure and explains how to run the validated dist/tes3np-windows candidate rather than accidentally starting a stale root executable. Existing safe publish order and exit failures remain unchanged.
- Source checks only; follow-up Windows batch completion, source-root replacement and visual changelog regression require testing. No GitHub Actions run or public update.

### Release notes readability — 2026-11-05

- Enlarged the existing version-status window from 720×520 to 800×600 and expanded its changelog viewport from 10 to 13 lines. Existing theme, buttons, mouse wheel, thumb dragging and window lifecycle remain intact.
- Draft and published changelog sections now display as gold, bold headings with a diamond marker, extra section spacing and consistent line wrapping. No changes to updater confirmations, download/install behavior or release endpoints.
- Source-level regression checks added. Windows compilation and visual/scroll interaction testing are still pending. No public update published.

### Manually installed Expansion Pack and Discord login gating — 2026-11-05

- Expansion Pack starts disabled in new OpenMW configurations; the global toggle enables only an already-installed nonempty `NP Expansion Pack.esp`, using a config-only worker with backups. A missing pack requests the **official Discord ZIP dialog**, with an Install mode distinct from actual plugin/load-order mismatch diagnostics. Retired v0.1 assets are no longer build, embedded resource, manifest or package dependencies; the separately packaged modified TES3MP client remains.
- Existing Game Chat Discord sign-in now gates every downloadable Expansion Pack dialog. Only the currently authenticated ChatHost can authorize the native popup; signed-out players get its existing login view first, and cancelled prompts clear safely. The embedded child rejects unauthenticated launch requests. No additional Discord profile/process or automatic downloads.
- Follow-up source audit: installed ESP detection also accepts separate configured OpenMW `data=` folders. Before authorizing a Discord download popup, ChatHost now rechecks the live authenticated channel DOM; cancelling or losing the ChatHost clears pending requests. Verified source regression contracts and revised mode-specific popup wording without modifying existing controls.
- Added isolated Windows enable/disable fixture and updated static architecture/release checks. **Source changes committed; actual Windows build, first-login handoff, download, and UI/runtime regression tests still pending.** Historical v0.1 art is still present as source-only material in the Git checkout; it is not shipped with the Windows launcher.

### Launcher Play Together description — 2026-11-05

- Updated the front-page **Together** information card to the user-selected concise promotion of multiplayer, the mastery system, creature camps/bosses, side activities, and events. The revised description is 298 characters versus the previous 293, preserving the card's established dimensions, font, renderer, button layout, and neighboring single-player **Quest** copy. Source change verified; Windows launcher rendering/build remain to be checked.

### First Discord login Game Chat fix — 2026-11-05 (visual fix user-confirmed)

- **User acceptance:** After the completed Chat Host loading-state and real-scrollbar changes, the user reported **“Fixed!”** on November 5. This confirms the reported stale scrollbar/loading presentation issue was resolved in their tested launcher session. No detailed build transcript or separate signed-out authentication reproduction was supplied with this confirmation; other Chat/Happy Hour/ZIP regression checks remain independently pending.
- **Complete first-login presentation follow-up:** User screenshots show that after the initial black-pane fix, chat messages do arrive without restarting, but the scrollbar stays as an old flat painted track and the `Connecting to live chat...` status is not consistently displayed during the OAuth/channel handoff. Root causes: `ShowDiscordSignIn` hides `goldScrollbar`, initial `RefreshNativeMessages` never restores its visibility, and `frameSurface.Paint` draws an outdated duplicate fake track; `RestoreGameChatAfterSignIn` also hides the parent frame and native loading label until messages are ready. The source now displays the real connecting status within the existing gold frame from post-auth handoff, hides the scrollbar until the first successful feed, ensures a correctly sized visible HTML parent before the first `setMessages`, then restores the actual textured scrollbar and refreshes its metrics and native layout. The redundant frame-painted fake scrollbar was removed. Strengthened Chat Host architecture tests. No changes to Discord credentials, source navigation rules, message archival, scrolling intent or Happy Hour processing. **Source checks passed; Windows build and live UI verification pending.**


- **Observed regression:** After the first Discord authentication, the existing Game Chat panel displayed its bronze frame and scrollbar but a black message area until restarting the launcher. Source inspection identified the exact parent-visibility mismatch: `ShowDiscordSignIn` hides `messageClip`, `RestoreGameChatAfterSignIn` leaves it hidden while native mode is false, and the first `RefreshNativeMessages` activation showed `messageBrowser` but **not its parent**. The renderer therefore remained invisible even with real messages and `nativeMode=true`. Minimal fix restores `messageClip.Visible = true` before showing the child renderer. Added a source regression guard to `scripts/check-chat-architecture.py`. Existing once-per-sign-in channel reload, Discord profile, Game Chat messages, scrolling and Happy Hour detection were not modified. **Source fix committed only; Windows build and first-login live test still required.**



### Diagnostic privacy hardening — 2026-11-04 (Windows verification pending)
- **Historical Expansion Pack status privacy verified, November 5:** User pulled `aa46fd4`, ran the disposable `--self-test` (PASS, one synthetic UTF-16 record repaired and idempotent second pass), then opted in to `--repair-legacy-import-results --skip-updater` on Windows. Exactly one older `result.ini` record was repaired with no skipped or failed records. Rescan: 2,824-line launcher.log PASS, 11,255-line chat-host.log PASS, one-line crash query PASS, **four importer result files/16 lines PASS**; `flagged categories=0`. Patch, render, and toggle logs remain ungenerated SKIPs. Private settings/chat files were present but not opened/modified by the audit; their pre/post integrity is not independently established. All three offline updater fixtures passed in the earlier November 5 run, not this skipped-updater pass. **Available diagnostic privacy findings closed; interactive feature/packaged ZIP and absent-log cases remain outstanding.** No application source changes or public release.


- **Actual privacy/updater audit and legacy status follow-up, November 5:** User ran `python scripts/audit-local-privacy.py` at commit `8c498d1`. PASS for 2,714-line launcher.log, 11,255-line chat-host.log, one-line crash query, launcher on-disk newline, plus updater source/version, metadata/tamper and complete offline transaction/rollback fixtures. Four optional diagnostic categories had no files (SKIP). One of four old importer result.ini files was flagged for a Windows path, username, and legacy absolute Backup location; the current importer already writes non-sensitive metadata. Added an **explicit opt-in**, narrowly scoped `--repair-legacy-import-results` mode that only atomically rewrites old completed result.ini status files, never rollback journals/backups, settings, game files or private Discord archives; preserved prior file encoding and added synthetic private-journal regression coverage. User must run the synthetic self-test and opt-in repair on Windows before this last historical finding is accepted. No launcher application code changed or alpha published.

- **Follow-up local acceptance tooling, November 5:** Added a standard-library, read-only `scripts/audit-local-privacy.py` command. It examines the **actual local** secondary diagnostic files and importer result metadata without printing or modifying private content, verifies launcher event line separation and terminal newline, and runs existing isolated updater/version/metadata/rollback tests when the required PowerShell runtimes are available. It reports missing optional files and missing PowerShell 7 explicitly as skips. Synthetic scanner self-test passed outside Windows; no user-machine output yet. No application/game behavior was changed and no new launcher build is necessary for this test-only commit.


- **Windows v4 acceptance checkpoint, November 5:** User supplied full `git pull --ff-only` fast-forward to `24a2359`, complete successful `Build tes3np.bat` transcript and `Start-Process .\\tes3np.exe`. PowerShell parser, privacy source/isolated AHK fixtures, Chat Host compilation/publish, ZIP/folder importer and picker fixtures, Ahk2Exe compiled launcher, compiled `--check`, runtime/hash and distribution ZIP integrity all passed. Nonfatal WindowsBase MSB3277 warning remains. Inspected fresh Copy Launcher Logs attachment: 2,720 report lines (2,713 launcher events), no merged timestamps, unsafe personal-path/contact/secret patterns, placeholders or empty pipes. Earlier joined event lines now separate; useful character/game events remain. **Launcher Log privacy + v4 formatting accepted.** Separate Chat Host, Expansion Pack and Render Log contents, standalone ZIP interactive operation, on-disk newline and game/Happy Hour/macro regressions remain pending; no alpha release published.


- **Copied-log verification, November 5:** User reported the updated PowerShell pull/build/launch finished successfully. Three uploaded Copy Launcher Logs exports were byte-identical (2,711 lines); review found no exposed absolute Windows user paths, email addresses, IP addresses, secret-key fields, long Discord IDs, privacy placeholders or empty pipes. Public character names and timestamped game/login events were preserved. Two old entries were joined after `Launcher startup beginning.` because the v3 migration removed the terminal newline before a later event was appended. Fixed the logger to insert a missing first-write delimiter, repair the two known legacy timestamp joins during copied/disk cleanup, and terminate migrated diagnostic files with a newline. Raised migration to `PrivacyScrubVersion=4` and added isolated regression tests. **This follow-up fix needs a fresh Windows rebuild and copied-log recheck; previous build success predates the fix.** This only verifies the supplied Launcher Log, not separate Chat Host/Expansion Pack logs.


- **Source-side privacy audit closed, November 4 (Windows acceptance pending):** Reviewed the remaining worker results and exception displays. Expansion Pack import `result.ini` now cleans error text and reports backup availability instead of an absolute backup path (real paths remain in the private rollback journal). Expansion toggle results, native picker `.error`/console output, macro dialogs and desktop-shortcut/portrait errors now avoid raw private paths and privacy placeholders. Windows usernames appearing outside path fields are excluded at the launcher, Chat Host and updater boundaries, while public `Character:` values remain. Historical diagnostic migration advances to v3; source guards and disposable fixtures cover new boundaries. See [diagnostic privacy audit](docs/DIAGNOSTIC-PRIVACY-AUDIT-2026-11-04.md). **No fresh full Windows build or live behavior has been verified after these changes.**


- Reviewed the live AutoHotkey launcher, C# Chat Host, game-session logging, diagnostics clipboard controls, PowerShell update worker, and their shared AppData paths before editing. New diagnostics redact private Windows paths, saved password values, URLs, emails and secret-like fields; updater-worker and Chat Host writes now have their own redaction boundaries. Public in-game character names are intentionally retained in login/session diagnostics because they help identify the character being tested.
- Copy Launcher Logs, Copy Expansion Pack Logs and Copy Render Errors sanitize old content before copying. The launcher performs a one-time in-place privacy scrub of prior diagnostic logs and Windows crash-query text after loading encrypted profiles and before launching Chat Host. It does **not** modify private settings, portable backups, WebView2 profile, or the Discord history/archive used for real Happy Hour detection. The Game Chat archive contains actual messages and is **not** a bug-report log; do not share it.
- Added `scripts/check-diagnostic-privacy.py` and disposable `scripts/test-diagnostic-privacy.ahk` to the existing Windows build gates. GitHub source inspection/checks complete; fresh Windows AHK/C#/PowerShell compilation, privacy fixture results, clipboard checks and live-game regression are still required. No public alpha/release has been published by this change.
- **Windows build feedback, November 4:** Git fast-forward and source/Chat Host/privacy gates, Expansion Pack fixture, native picker fixture and C# preflight passed (the known MSB3277 WindowsBase warning remains nonfatal). The diagnostic privacy AutoHotkey fixture ran, but Ahk2Exe failed with code 17 because three new comments in `src/app/diagnostics.ahk` mistakenly used `//`. Changed only those comments to AutoHotkey `;` syntax, added an early source regression guard, and checked all touched AHK files for the same pattern. **A new full Windows compile/package and live runtime check are required before this cleanup is release-ready.**

- **Clean diagnostic formatting follow-up, November 4:** Replaced emitted privacy placeholders with complete removal of sensitive values and their now-empty fields. Pipes and labels are compacted, public character names and useful event context remain, and the Copy Logs notices no longer announce redaction. Historical diagnostic scrubbing was advanced from `PrivacyScrubVersion=1` to `2` so previously emitted placeholder lines are cleaned at next startup. Chat Host and updater workers use matching independent write-boundary filtering. Expanded the disposable AHK fixture and source guard to reject placeholder output. This source-only follow-up still needs a fresh full Windows build, copied-log inspection and live regression; nothing has been released.


- Continued the post-audit dead-code cleanup: removed the disconnected `BrowseSharedExecutable` and `SaveSharedExecutable` helpers, the retired `ExecutableInput` textbox state, and its stale writes in patch completion, client-mode switches, and backup import. Preserved live `ClientMode` / `Launch/Executable` persistence, custom-client installation and imported data. Replaced outdated Browse guidance with Launcher Settings > Game Client Settings.
- Cross-checked shared mouse, loading, macro and theme callbacks before pruning and **retained** them because they remain reachable. Added source guards for the deleted textbox and the live client-selection/import paths. Source-only validation passed; a fresh Windows build and interactive regression test are still required for this new cleanup.

### Verified Windows checkpoint — 2026-11-02

- User confirmed **the post-audit TES3NP launcher and its tested features are all working** after restoring the Enhanced Readability callback. This supersedes the pending post-cleanup Windows regression status recorded earlier in this changelog. No detailed per-feature test log was supplied; do not treat this confirmation as a clean-machine release certification or proof of every legacy repair path. Application source remains unchanged in this checkpoint.

- Restored the **live Launcher Settings Enhanced Readability label updater** inadvertently deleted by the source cleanup. `ToggleV016ReadabilityControl` still invokes `UpdateV016ReadabilityLabel`, so AHK `#Warn` raised an unresolved-function warning and stopped launcher compilation. Restored the original helper's HWND validation and text update; added a static contract protecting event binding, callback, helper definition and reset label. Cross-compared the 34 intentionally removed AHK functions against all current AHK modules and found no remaining references. User subsequently confirmed the missing-helper warning was fixed on Windows (2026-11-02); no complete build transcript or separate interaction test was supplied.

### Codebase cleanup audit (2026-11-02)

- Top-to-bottom follow-up: removed the unreachable first-run TES3MP scanner/status overlay (the actual startup now uses `CheckFirstRunMorrowind`), old custom-client overwrite/skip prompt and markerless hash wrapper, dormant setup-check wrappers, duplicate updater confirmation, orphaned character-count helper and `OpenMacros` alias.
- Removed the no-longer-used 11-function proprietary Magic Cards bitmap parser/atlas/renderer path and its startup probing; the working bundled Mystic Cards TrueType font remains. Removed a dead Chat Host paint-coordinate local.
- Harmonized `.editorconfig` AHK/PowerShell line endings with Git's LF policy, removed redundant CI steps that silently edited the patch helper, and expanded retired scheduler checks to the Chat Host C# source and PowerShell workers. Preserved live custom-client SHA-256 verification, patched client, recovery, macros ListView selection model, import and native GUI dependencies.
- See `docs/CODEBASE-AUDIT-2026-11-02.md` for layer-by-layer inventory, traceability, retained legacy Installer/Repair downgrade risk and complete Windows regression checklist. Source analysis and GitHub writes are complete; post-cleanup Windows build and runtime checks remain pending.

- Removed unused standalone in-game chat preview GUI and its handlers; the active embedded authenticated Discord/Game Chat host is unchanged.
- Removed orphaned startup-choice GUI and callbacks, the unused legacy chat-control command handler, an abandoned Magic Cards label helper, and two unused checkbox toggle callbacks. Existing character launching, Favorite handling, login progress and settings application remain in source.
- Removed the C# Happy Hour backfill boolean that was assigned but never read (the previously observed CS0414 warning). No relevant control-flow condition used it.
- Confirmed the retired daily-login scheduler module is absent and not included by the launcher. Added regression gates against reintroducing the removed functions. Historical scheduler names in negative tests/upgrade compatibility guidance are intentional protections, not active scheduling code.
- Cleaned stale scheduler/Launch All/startup choice claims from user and release docs; updated the user guide for first-character auto-favorite and current login progress UI.
- Recorded detailed findings and outstanding runtime validation in `docs/CODEBASE-AUDIT-2026-11-02.md`. Static inspection and GitHub writes completed; Windows build, dynamic callbacks and full game UI regression tests remain to be run. No release approval is implied.


### Removed / code audit — 2026-11-02

- Completed source-tree reachability review and removed the dormant 1,225-line daily-login/event scheduler, its startup polling and shutdown writes, missed-event warnings, editor/hotkey controls, stale character-book references and event/hotkey portable-backup serialization. Old user settings remain untouched, inert and backward-compatible for character restore.
- Removed the unreachable scheduled/batch claim-close controller and its queue fields, dead Launch All & Close dialog and permanently hidden full-width Launch Character button. Preserved normal per-row Play, front-page favorite quick launch, and the four-client limit.
- Removed unused old Troubleshooting popup and broad diagnostic report, unused display-reset callback, and obsolete source-ZIP packager command. Kept current Launcher Data tools and the actual Windows packaging process.
- Kept editable species/branding PNG masters in Git source but excluded their unused copies from the compiled standalone resources; ICO runtime art stays embedded. Corrected stale background-asset documentation and added source/build safety contracts against these dead paths.
- See `docs/CODE-AUDIT-2026-11-02.md` for exact scope, intentionally retained active components, legacy bundled-repair downgrade risk and Windows acceptance tests. This cleaned code has **not** yet passed the next Windows build/runtime revalidation; the user's verified Expansion Pack v0.2 baseline predates the cleanup.


### Verified on Windows — 2026-11-02

- **NP Expansion Pack v0.2 installation and live TES3MP connection succeeded (user-confirmed).** After rebuilding the alpha launcher with the atomic `progress.ini`/result publishing fix, the launcher displayed “Expansion files installed and backed up.” The user subsequently launched TES3MP, connected to Nerevarine Prophecies, and confirmed it worked without the prior plugin checksum rejection. This closes the reproduced v0.1-to-v0.2 Expansion Pack mismatch/install failure for this configuration; it does not certify every possible ZIP/folder layout or file-lock scenario.
- Preserve as the verified working baseline: unified native ZIP/folder picker; large-package importer without arbitrary byte-size caps; safe asset staging and SHA-256 verification; existing backup and rollback journal; lock handling and atomic status updates. Future broader code audit of legacy Install / Repair remains deferred by user request. No application code changed in this checkpoint.

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

- Fixed a live NP Expansion Pack v0.2 import stopping at file 221/857 with `another process has locked a portion of the file` despite retries on asset copies. Root-cause investigation found `CheckPatchWorker()` reads `progress.ini` twice every 50 ms while the import worker wrote that same INI in place on every asset. Progress and final result records now publish complete UTF-16 INI files via a same-directory temporary file and atomic move/replace with the existing bounded Win32 sharing/lock retries. The original progress/result format, rollback, asset hashes and game-file install process are preserved. Added an isolated Windows test that holds the existing `progress.ini` open without delete sharing, observes the worker's attempted atomic publication, releases it and requires a successful import with preserved backup journal. Source checks passed; Windows fixture and actual v0.2 re-import are still pending.

- Fixed the Windows import failure at `installing file 4 of 4`: the final file is the existing `openmw.cfg`, and Windows PowerShell 5.1 coerces `$null` passed into a .NET string parameter to an empty filename. Using `[IO.File]::Replace(..., $null)` therefore generated `The path is not of a legal form` when its optional backup argument was interpreted as `""`. The importer now supplies `[NullString]::Value` (real CLR null) to `File.Replace`, removes stale surplus call arguments, and adds a disposable Windows test replacing an already-existing config file plus a guarded architecture contract. The existing verified transaction journal, rollback, and lock handling remain unchanged. Windows build and official NP Expansion Pack v0.2 live import remain pending.

- Corrected the recurring Windows ZIP fixture failure `The path is not of a legal form` after prior lock-retry changes. Removed all cross-scope caller scriptblock execution and replaced it with a typed `InvokeFileOperation` dispatcher that receives explicit source/destination paths for hashing, disposable copying, atomic replacement, moving and ZIP opening. Retry remains limited to Win32 sharing/lock errors 32/33 (six attempts), the backup journal and committed-only rollback remain intact, and rejected imports now include a non-sensitive stage label. Updated Windows synthetic ZIP/folder/byte-range-lock fixtures and architecture guards. Windows build and real v0.2 import remain pending verification.

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
