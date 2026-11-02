# TES3NP Codebase Audit — 2026-11-02

## Latest verification — 2026-11-02

- **User-confirmed post-cleanup Windows verification:** After the missing `UpdateV016ReadabilityLabel` callback was restored, the user reported that the warning was fixed, then confirmed that **everything they checked is working**. This updates the earlier audit status from *Windows regression pending* to **user-verified working baseline for tested functionality**.
- Evidence scope: user's direct confirmation, not an independently captured full build log or a separate checklist proving every feature, clean-machine installation, updater release gate, and legacy repair path. Preserve these distinctions for future development.
- No new application code changes were made to record this checkpoint. Keep the legacy Install / Repair downgrade risk on the separate future-audit list rather than changing a working installation.

## Baseline and scope
- Branch: `Update/v0.1.21-alpha`; preceding verified runtime baseline: commit `8d89e43a28816c7127a628e4886b753d9568243b`, with user-confirmed successful NP Expansion Pack v0.2 installation and server connection.
- Repository inventory from the verified baseline: 256 tracked files, including 52 files with source/build/test extensions. Primary modules: AHK v2 launcher under `tes3np.ahk` and `src/`, C# embedded Chat Host under `chat-host/`, Windows PowerShell installer/import/update workers under `scripts/`, content-addressed embedded resources and NP Expansion Pack payloads under `patches/` and `assets/`.
- Examined source root/include ordering, major launcher UI and interaction modules, scheduler retirement gates, character/session dependencies, patch/install/import logic, build/package scripts, Chat Host for scheduler references, and selected docs. Audited explicit references and callback bindings before deleting the dead AHK helpers below.
- **Verification boundary:** Source and GitHub writes inspected; Windows `scripts/project.py check`, `scripts/check-chat-architecture.py`, compilation, interactive UI and actual gameplay regression tests must still be run locally. A source reference search alone cannot certify the entire binary/resource dependency graph. Treat findings below as audited items rather than a claim that every dynamic callback is provably dead.

## Removal: confirmed obsolete AHK code
- `src/ui/actions.ahk`: removed the unreachable standalone “In-Game Chat” preview, its old resize/Discord-open handlers, and `InGameChatGui`. The real game chat remains the authenticated embedded WebView2 Chat Host; its event wiring and assets are untouched.
- `src/app/bootstrap.ahk`: removed the unused startup-choice dialog and its three callbacks, plus the orphaned `LauncherChatCommandClick` handler. Kept the live `ToggleLauncherChat` behavior, session start paths, patch startup and system tray handling.
- `src/ui/v016-refinements.ahk`: removed `AddMagicCardsInteractiveLabel` and two unused settings-toggle callbacks. Kept the real `ApplyV016LauncherSettings`, settings persistence, fonts, layout helpers, and accessibility controls.
- `scripts/project.py`: extended the retired-symbol checks so all these obsolete functions cannot silently return. Existing retired scheduler/launch-all checks remain.

- `chat-host/Program.cs`: removed three occurrences (one declaration, two assignments) of `initialBackfillReanchored`, a private backfill state variable never read (the prior CS0414 warning). No Happy Hour/history behavior branches depended on it.
- `scripts/check-chat-architecture.py`: added a negative assertion preventing the dead backfill flag from returning.
- User and release documentation: removed false claims of a still-existing scheduler, scheduled sessions, Launch All workflow and removed startup-choice dialog from `docs/USER-GUIDE.md`, `docs/ALPHA-COMPATIBILITY-CHECKLIST.md` and `docs/ALPHA-RELEASE-DRAFT.md`. Updated the guide to reflect the automatic first-character favorite and login-progress window.
- `docs/RELEASING.md` deliberately retains a historical compatibility note: old scheduler INI sections in older published alpha installations must stay inert after an upgrade. This is a **migration safety requirement**, not active scheduler code.

## Scheduler findings
- The previously retired `src/app/daily-login-scheduler.ahk` is **not present** on the current branch. No scheduler module is included by `tes3np.ahk`.
- `scripts/project.py` intentionally retains **negative checks** against historical scheduler symbols, including the retired module path, `ScheduledEvents`, `ScheduledDailyLogin`, `OpenScheduledEvents`, `LoadDailyLoginSchedule` and other old entry points. These strings are test-only prohibitions, **not functioning scheduling code**. Removing them would weaken the guard against the very feature the user wants gone.
- No scheduler references were found in sampled live AHK modules, the inspected C# Chat Host, selected build workers, or the main README.

## Protect these live dependencies
- Character management, first-character automatic favorite selection, login progress, species icons and custom avatars, saved macros and game launching.
- Embedded Discord/game chat, authenticated data flow and Happy Hour detection, banner and graphical effects.
- Current NP v0.2 working import: unified native ZIP/folder picker, backed-up transactional install, checksum diagnostics, lock-safe atomic status updates and rollback.
- Bundled runtime extraction, startup patch/recovery, updater, offline artifact checks, WebView2 publish, and standalone ZIP package.
- Old `OpenPatcher` entry points are **not safe to delete by symbol search**: they remain connected to system tray and first-run patch/recovery flows. Defer until a dedicated replacement and Windows regression plan exists.

## Additional audit opportunities (not deleted without proof)
- `src/ui/front-page.ahk` contains `BeginGameDetectionDisplay`, with no static references found in the surveyed AHK modules. It shares globals with live detection UI: trace startup and status control behavior before removal.
- Some old `v016` names and legacy restoration helpers remain, but naming alone is not sufficient to classify them as unused.
- The historical bundled v0.1 expansion payload must not be deleted blindly: install/repair, resource packaging, offline checks and patch manifest still reference it, even though manual NP v0.2 import now works.
- Historical scheduler mentions in project validation are protective exclusions. Removing them from the checker would allow reintroduction.

## Validation required before further pruning
1. Run `python scripts/project.py check` and `python scripts/check-chat-architecture.py` (the standard Windows build runs both).
2. Run the existing `Build tes3np.bat` and all import/diagnostic/update fixtures; verify compiled launcher `--check`, extraction payload and final ZIP.
3. Smoke-test main page, Manage Characters, favorite selection, species/custom avatar loading, login progression and session limit, game chat/Happy Hour, settings scaling, updater, import v0.2, and system tray repair/recovery.
4. Verify no removed function is reachable from dynamic callbacks in a runtime session before considering more aggressive live UI/API deletion.

This is a rolling source-audit ledger, not a replacement for successful local Windows tests.

## Post-audit live callback regression — Enhanced Readability

- **Observed Windows failure:** AutoHotkey `#Warn` reported `UpdateV016ReadabilityLabel` as an unassigned local variable in `src/ui/v016-refinements.ahk` while compiling TES3NP.
- **Root cause:** The earlier removal of obsolete `ToggleV016ReadabilityParts` and `ToggleV016FollowWindows` also deleted the *live* `UpdateV016ReadabilityLabel(control, state)` function between them. The active Enhanced Readability checkbox still bound `ToggleV016ReadabilityControl` and called that helper.
- **Correction:** Restored the original helper, preserving its control/window validation and exact label update. Added an explicit `scripts/project.py check` guard for event binding, state callback, updater and reset path. No other Launcher Settings controls were changed.
- **Related cross-module review:** Compared function definitions from baseline `8d89e43` with current code in the nine AHK files altered by audit. There were 34 intentionally removed AHK functions; scanned all other current AHK entry/modules as well, and none of their names remain referenced. This does not prove Windows/UI behavior for every reachable function.
- **Validation pending:** Rebuild on Windows, confirm no `#Warn`, open Launcher Settings, toggle Enhanced Readability on/off, preview/reset settings, and verify saved preference. User confirmed on 2026-11-02 that this warning is fixed in their Windows environment. A complete build log and separate UI interaction results were not supplied.

## Top-to-bottom continuation — 2026-11-02

### Inspection map

| Layer | Reviewed | Cleanup / disposition |
| --- | --- | --- |
| Executable entry and startup | `tes3np.ahk`, `src/state.ahk`, `src/app/bootstrap.ahk`, `src/ui/front-page.ahk` | Removed superseded `OfferFirstRunSetup` scanner and abandoned `BeginGameDetectionDisplay`/`EndGameDetectionDisplay`/`RefreshGameDetectionText` overlay and associated state. Current `CheckFirstRunMorrowind` is the startup path and is retained. |
| Character/session state | `src/data/settings.ahk`, `src/data/backup.ahk`, `src/ui/characters.ahk`, `src/game/session.ahk`, `src/ui/login-progress.ahk` | Removed orphaned `HasSavedCharacters` helper. Preserved profile persistence, favorite choice, encrypted credentials, import/export, login stages and 4-game limit. |
| Native UI and layout | `src/ui/actions.ahk`, `controls.ahk`, `windows.ahk`, `renderer.ahk`, `loading.ahk`, `launcher-settings.ahk`, `v016-refinements.ahk` | Removed old chat preview, startup choice, inactive toggles, and abandoned 11-function proprietary bitmap-font rasterizer/parser. Preserved bundled Mystic Cards TrueType loading and live UI/layout controls. |
| Chat/Happy Hour | `src/ui/embedded-chat.ahk`, `src/ui/happy-hour.ahk`, `chat-host/Program.cs`, `chat.css`, `chat.ini`, `tes3np.ChatHost.csproj` and its assets | Removed unused C# backfill flag and orphaned paint coordinate; preserved WebView2, current message fetch/backfill state, Happy Hour detection, original artwork and settings. |
| Game client and recovery | `src/app/client-detection.ahk`, `src/ui/patcher.ahk`, `src/game/expansion-mismatch.ahk`, `src/ui/expansion-upload.ahk` | Removed unused markerless overwrite/skip prompt, obsolete manifest-hash lookup, setup-state accessor and abandoned startup patch-check wrapper. Preserved live `SHA256File` (used by custom client override verification), current patcher and v0.2 import. |
| Macros | `src/ui/macros.ahk`, `macro-bindings.ahk`, `scripts/import-macro.ps1` | Removed unused `OpenMacros` alias. Kept the active embedded macro panel and its hidden ListView **selection model**: removing it breaks selection and run/stop functionality. |
| Updater | `src/app/update-check.ahk`, `tes3np.ahk` confirmation entry, `scripts/tes3np-updater.ps1` and updater test scripts | Removed duplicate unused `ConfirmInstalledUpdate`; live root `HandleUpdaterStartupMode` and transactional rollback/confirmation remain. |
| Installer/build/security | PowerShell patch/import/toggle/browser workers; `project.py`, `check-chat-architecture.py`, `check-powershell.ps1`, resource generator, package/update/release validators, GitHub workflows | Kept file hashing, path sanitization, checksums, rollback, packaged picker and atomic progress records. Expanded scheduler exclusion scans from AHK to C# and PowerShell. Removed two workflow steps that silently rewrote a patch script during CI. |
| Repo/text assets and packaging | `.gitattributes`, `.editorconfig`, tracked `assets/` and `patches/`, `docs/`, release workflows | Aligned editor LF rules for AHK/PowerShell with Git checkout LF. Kept art originals, embedded dependencies, patch manifest, licenses and old patch resources because live packager or recovery paths still depend on them. |

### Additional retired identifiers guarded in `scripts/project.py`

- `OfferFirstRunSetup`, `BeginGameDetectionDisplay`, `EndGameDetectionDisplay`, `RefreshGameDetectionText`, `GameDetectionActive`, `LauncherHelpText`.
- `CheckModifiedClientForPatch`, `ShouldSkipMarkerless`, `BundledMarkerlessHash`, `ConfirmInstalledUpdate`, `HasSavedCharacters`, `OpenMacros`, `IsTES3MPSetupComplete`, `BeginStartupPatchCheck`.
- The retired Magic Cards bitmap-only parser, atlas, layout, rasterizer and control wrappers. The live native TrueType font loader is not part of the removal.

### Confirmed surviving risks and boundaries

- **Legacy Install / Repair is live**, reachable from system tray and explicit recovery. It still has paths to bundled older patch resources and therefore may replace a user-updated Expansion Pack. It cannot safely be deleted as dead code and requires a distinct redesign and migration test. No change was made to the verified v0.2 installer or imported game files.
- The old embedded `patches/expansion-pack` content is still used by the patch manifest, standalone resource generator, and patch/repair workers. Do not classify these files as orphaned just because the official user-installed package is newer.
- C# WebView2/WindowsBase assembly-version warning may persist; unlike the dead `initialBackfillReanchored` field, it originates in a live dependency and was not removed.
- Several macro and launcher UI internals have historic names or hidden presentation controls but are wired to actual selection, focus, and native-paint behavior. Names and invisibility alone are insufficient proof of dead code.
- Release gate remains intentionally blocked on the modified TES3MP client's corresponding source, rights review and clean-machine results. No tags, release assets, production update feed or user settings were modified.
- Static GitHub source analysis cannot exercise Windows timers, native COM dialogs, WebView2, AHK compile/runtime or a real NP session. The prior v0.2 server connection is the **pre-cleanup baseline**, not a post-cleanup regression pass.

### Exact post-change source graph check

At source HEAD `f29da3fcfdfc1871c19d061f626c9e837170478d` the Git tree has **257 tracked files**. All **25** live AHK modules under `src/` are included exactly once in the `tes3np.ahk` entrypoint (no missing or dangling `#Include`). No tracked filenames contain `scheduler`. Retired symbol scans over all AHK modules plus Chat Host C# and all PowerShell worker/test files found no remaining executable definitions or references for the retired scheduler and audited dead paths. This is a **source graph check**, not a claim of passing Windows compilation or dynamic tests.

### Verification and recommended Windows pass

The reviewed source has explicit branch commits and source post-write checks. The existing `scripts/project.py check` guard rejects reintroduced scheduler/obsolete symbols, including the PowerShell/C# scheduler check added in this audit. `scripts/check-chat-architecture.py`, PowerShell syntax, ZIP/folder synthetic fixture, AHK diagnostic fixture, updater fixture and packaging gates remain in the build.

Run the unchanged `git pull --ff-only` on `Update/v0.1.21-alpha`, then `Build tes3np.bat`. Check launch, favorite characters, launch limits, macro selection and execution, new-adventure login, settings and font appearance, game chat and Happy Hour, direct v0.2 ZIP selection, and the explicit legacy patch/repair screen without running a repair that could downgrade the game. Until this passes, the audit is **source-cleaned; Windows regression pending**.

## Follow-up dead-code review — orphaned executable field

- **Baseline:** The preceding audit cleanup was confirmed by the user to work on Windows; this new pass has not yet been rebuilt or runtime-verified.
- Rechecked the full AHK source/include graph for function calls before removing anything else. The apparent orphaned loading-message helpers, menu-scroll callbacks, themed-control geometry synchronizer and macro-panel hiding handler are **actually reachable** through shared event dispatch, loading transitions and character-editor controls. They were **preserved**. This cross-module check is especially important after the earlier Enhanced Readability regression.
- Identified `BrowseSharedExecutable` as unreachable from any active UI. Its only effect was to call `SaveSharedExecutable`, which also had no other callers. The related `ExecutableInput` control was no longer constructed (character-book initialization set it to integer `0`), yet old patch completion, custom-client settings and portable backup import still attempted to write `.Value` to it or ignored errors from that write.
- Removed both orphaned helper functions and every obsolete `ExecutableInput` reference across `src/ui/characters.ahk`, `src/data/settings.ahk`, `src/data/backup.ahk`, `src/ui/patcher.ahk`, and `src/ui/v016-refinements.ahk`. The old patch completion attempted `IsSet(ExecutableInput)` despite the scalar `0` being assigned; its direct `IniWrite(executable, DataFile, "Launch", "Executable")` remains intact.
- **Preserved:** `GetSharedExecutable`, portable backup `Launch/Executable` serialization, atomic imported settings commit, `ClientMode` selection, custom executable/dependencies installation, bundled-client restoration, and current recovery paths. None of these systems were removed or rewritten.
- Corrected the import-complete guidance and `docs/USER-GUIDE.md` to direct users to **Launcher Settings > Game Client Settings** instead of a nonexistent Browse textbox. Tightened source contracts in `scripts/project.py` to prohibit the orphaned UI symbols while positively verifying actual client selection, persistence, and portable backup behavior.
- **Source validation:** all 26 AHK entry/modules checked in two batches and no obsolete `ExecutableInput`, `SaveSharedExecutable` or `BrowseSharedExecutable` references remain. Targeted source-contract checks passed. No Windows compiler, packaging, WebView2, game-client or backup import/export runtime was available in this session; these checks remain pending.
- **Next runtime pass:** pull/build/launch the current alpha, open Game Client Settings and verify mode switches, ensure the character book and Enhanced Readability still work, and test disposable backup import/export and patch Verify before considering any additional recovery-layer cleanup. Do not run legacy Install/Repair against the real v0.2 game installation solely to test this cleanup.

## Additional dead-code pass — disconnected Chat Host helpers

- **Source reviewed:** current `Update/v0.1.21-alpha` `chat-host/Program.cs`, its native chat rendering/scroll handlers, existing Discord image download and pixel-verification flow, and `scripts/check-chat-architecture.py`.
- **Removed `HideNativeChatScrollbar`:** one empty method that did nothing and had no callers. The active custom bronze scrollbar, scroll events, browser-based message renderer, and scrollback paging remain unchanged.
- **Removed `AppendChatImage`:** one uncalled clipboard-based RichEdit image insertion method. It previously copied arbitrary image data onto the user's clipboard and restored its old clipboard object, but was no longer invoked by the current message feed. **Kept** `FetchChatImage`, `imageCache`, `RecognizePendingHappyHourImage`, `LooksLikeHappyHourImage`, and the rendered image/browser pipeline; the current Happy Hour pixel-verification route is unchanged.
- **Verification:** counted exactly one occurrence of each removed method name in `Program.cs` before editing, confirmed the deleted block had balanced braces, verified neither name remains in the updated remote `Program.cs`, and verified both negative assertions exist in `scripts/check-chat-architecture.py`. The code and guards were committed to the existing alpha branch (`d560a060` and `14718abd`). No launcher features, packaged art, client files or user settings were modified.
- **Runtime boundary:** Windows compilation, full Python/PowerShell preflight, WebView2 rendering, clipboard interaction, Game Chat scrolling, Happy Hour image recognition, and player login were **not** run during this connector-only cleanup. The last user-confirmed working Windows baseline predates these two commits.
- **Next:** run the existing one-command pull/build/launch; verify normal launcher UI, game chat with image attachments, scrolling/history loading and Happy Hour, and previously fixed Enhanced Readability and Game Client Settings. Do not run bundled Install / Repair against an installed NP Expansion Pack v0.2 for smoke-testing; its downgrade risk remains a separate tracked issue.

## Follow-up cleanup — unused native scrollbar imports and browser state

- **Date and scope:** 2026-11-02, `Update/v0.1.21-alpha`, Chat Host only. Reviewed the entire `chat-host/Program.cs` source for declaration/reference counts and inspected the live browser scrollbar, WebView2 message feed, native RichTextBox fallback, and existing source contract tests before editing.
- **Removed:** unused Win32 `GetScrollInfo` and `ShowScrollBar` P/Invoke declarations and the `SCROLLINFO` struct required only by the former. Both imported methods had no call sites; `SCROLLINFO` appeared only in its declaration and the unused method signature. Removed unused `let lastState='';` from the embedded message-browser HTML/JavaScript; it had no reads or writes.
- **Preserved:** active `goldScrollbar`, `ChatThumbY`, `ScrollChatToThumb`, message browser `scroll` event, `ResizeObserver`, WebView2 scroll metrics, image display, clipboard-free rendering, native fallback control, and all Happy Hour/Discord data handling.
- **New guard:** `scripts/check-chat-architecture.py` blocks the removed symbols from returning and asserts the live custom-scrollbar/scroll-metrics glue is retained. Static exact-match checks confirmed unique deletion targets and preservation of named dependencies; source changes do not constitute a Windows build or runtime smoke test.
- **Next:** `git pull --ff-only`, `Build tes3np.bat`, launch, then verify Game Chat opens, scrolls with wheel and bronze scrollbar, preserves scroll position when loading older history and displaying images, and still displays Happy Hour correctly. Continue checking character book, macros, Enhanced Readability and Game Client Settings as part of the accumulated post-cleanup regression pass. Do not run the legacy Install/Repair workflow on the working NP v0.2 install.

## Final legacy installer retirement — 2026-11-02

- **User clarified scope:** the old Install / Repair component is retired, not to be repurposed as another UI. An interim proposed safety redesign was reverted before retirement; no old repair UI/worker remains in the active source.
- **Removed:** old Optional Expansion Pack installer GUI, its Apply/Verify/Restore buttons, tray entry, obsolete location-picker callbacks and patch worker, and the v0.1 patch PowerShell script. Removed its resource-generator package entry and unused GUI state.
- **Retained:** first-run Morrowind discovery, FindTES3MPFolder, PatchConfigurationPath, Expansion Pack enable/disable, the separate ZIP/folder Upload Expansion importer, its PatchJob loading monitor and cancellation/exit guards, and the data/backup files that may exist in users' AppData from older builds.
- **Regressions guarded:** scripts/project.py now forbids the retired UI/worker identifiers and asserts the current importer, progress handler, profile game-launch check, first-run discovery, and toggle functions remain linked.
- **Historical entries above** describe the source at the times they were written; their former warnings that the old GUI is still live are superseded by this checkpoint. The old v0.1 payload/manifest is still included by resource packaging and source integrity checks and must not be deleted without separate provenance and packaging review.
- **Remaining local checks:** Windows build, synthetic importer tests, actual chat/Happy Hour, character/macros/settings, updater transaction fixtures and packaged-backup regression. No GitHub Actions. Release compliance is deferred.
