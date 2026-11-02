# TES3NP Codebase Audit — 2026-11-02

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
