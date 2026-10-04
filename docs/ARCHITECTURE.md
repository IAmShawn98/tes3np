# Architecture

`tes3np.ahk` declares the dependency order and starts the app. Modules are included
into one AutoHotkey process, not isolated namespaces. Functions may reference
later declarations; state must be initialized before startup.

| Module | Responsibility |
| --- | --- |
| `src/state.ahk` | Shared state, paths, build number and defaults |
| `src/app/bootstrap.ahk` | Startup, quick launch, icons, tray and shutdown |
| `src/data/settings.ahk` | Profile factory, INI keys and DPAPI |
| `src/data/backup.ahk` | Portable exports and validated imports |
| `src/game/session.ahk` | Single controller, watchdog and sequential launches |
| `src/ui/front-page.ahk` | Main layout, menu entries and viewport |
| `src/ui/controls.ahk` | Control builders, pointer states and input routing |
| `src/ui/renderer.ahk` | Native buffered painting, callbacks and GDI resources |
| `src/ui/windows.ahk` | Window construction and reveal |
| `src/ui/loading.ahk` | Frame covers and loading feedback |
| `src/ui/characters.ahk` | Character book, editor and selection |
| `src/ui/macros.ahk` | Import jobs and tracked macro processes |
| `src/ui/macro-bindings.ahk` | Declarations and saved macro keys |
| `src/ui/patcher.ahk` | Setup gate, worker orchestration and results |
| `scripts/patch-tes3mp.ps1` | Verification, backups, installation and rollback |
| `scripts/import-macro.ps1` | ZIP validation and extraction |

State remains shared rather than class-based to preserve the accepted native GUI
behavior. Each feature has one initialization point and one responsible module.

## Session contract

`ClientTick` owns recovery. Phases are `launch`, `window`, `username`, `password`,
`loading`, `playing`, `claim`, `closing`, `retry` and `stopped`.
`UpdateGameStatusTooltip` only presents state. Only a visible SDL window belonging
to the tracked PID qualifies as the game. Credentials use configured delays, not
OCR. Never add a second watchdog.

`AppConfig` centralizes endpoints, default delays and controller intervals.
Existing characters retain saved delays. `NewCharacterProfile` supplies new-profile
defaults. `%APPDATA%\tes3np` remains the data root.

## Patch worker contract

The GUI invokes `Apply`, `Verify` or `Restore` and reads UTF-16 LE `progress.ini`
and `result.ini` from the job folder.

| State | Meaning | Menu |
| --- | --- | --- |
| `success` | Verification or installation completed | Unlocked, except after Restore |
| `needs_setup` | Verify found missing/different managed files | Setup required |
| `error` | Validation or operational failure | Setup required |

Verify creates job/staging files but does not change game files. Expected
setup-needed results use informational feedback and activity logging. Actual
errors retain detailed diagnostics. Startup never trusts the saved completion
flag without verification. The worker owns mutations; the GUI must not duplicate
that logic.

## Rendering and shutdown

Themed controls have `ButtonFaces` records with immutable owner `Window` HWNDs.
Native subclasses draw into buffers. Keep product actions out of paint callbacks.
Release windows and callbacks before GDI+ shutdown. Exit is blocked during patch
jobs so copying can finish. Shutdown stops owned automation and leaves the game open.
