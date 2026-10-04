# Development guide

## Source map

| Path | Responsibility |
| --- | --- |
| `tes3np.ahk` | Explicit include order and application startup |
| `src/state.ahk` | Shared state, AppConfig defaults and paths initialized before startup |
| `src/app/bootstrap.ahk` | Startup choice, tray menu, icons and cleanup |
| `src/ui/renderer.ahk` | Native buffered drawing and GDI resource lifetime |
| `src/ui/windows.ahk` | Construction hiding and window reveal |
| `src/ui/front-page.ahk` | Main-page layout, descriptions and menu scrolling |
| `src/ui/controls.ahk` | Themed control builders, pointer states and event routing |
| `src/ui/actions.ahk` | Wiki and front-page actions |
| `src/ui/characters.ahk` | Character book, add/edit form and launch-all explanation |
| `src/ui/macros.ahk` | Local macro library, import workflow and tracked script processes |
| `src/ui/macro-bindings.ahk` | Declared macro actions, binding prompt and per-package saved keys |
| `src/ui/patcher.ahk` | Setup gate, startup verification, patch UI and asynchronous progress |
| `scripts/patch-tes3mp.ps1` | Verified file plans, backups, rollback, repair and restore |
| `patches/` | Supplied markerless client and EP with SHA-256 file manifest |
| `scripts/import-macro.ps1` | Bounded ZIP validation and extraction |
| `src/ui/loading.ahk` | Frame covers and loading feedback for actual interface work |
| `src/data/settings.ahk` | INI persistence, executable settings and DPAPI password protection |
| `src/data/backup.ahk` | Portable export, validated import and local re-encryption |
| `src/game/session.ahk` | Login state machine, watchdog and sequential character launches |
| `assets/backgrounds/` | Launcher and character-book artwork |
| `assets/controls/` | Button and scroll-panel artwork |
| `assets/headings/` | Feature title artwork |
| `assets/icons/` | Launcher ICO and PNG |

All includes are explicit in the entry script. Asset paths use `A_ScriptDir`, so running from another working directory does not break them. The modules share application state; this refactor separates responsibilities without introducing a new framework.

## Common changes

- Main-page text and layout: `front-page.ahk`.
- Character fields and editor positions: `characters.ahk`.
- Add a saved preference: update profile defaults/load/save in `settings.ahk`, the editor in `characters.ahk`, and its consumer in `session.ahk`.
- Login and reconnect behavior: keep it in the single `ClientTick` state machine. Do not add an overlapping recovery timer.
- Replace artwork: retain the referenced dimensions, transparency and paths, or update every reference and the startup asset list.

## Rendering conventions

Coordinates are logical pixels at 96 DPI. Preserve the custom buffered paint path for themed controls. Keep immutable owner HWNDs on paint records; do not query a destroyed GUI's HWND. Destroy windows and release paint resources before shutting down GDI+.

Reuse precreated controls when editing. Redraw changed controls locally for scrolling. Use loading feedback for actual work; do not add artificial waits or a loading screen for ordinary scrolling. Avoid whole-window composited styles, which previously caused freezes.

## Data and packaging

Keep personal settings and logs outside the source tree. Preserve existing INI keys and defaults when adding preferences. Do not store credentials in code, screenshots, examples or committed settings files. There is no automatic migration to Local AppData in this version.

To distribute a script build, ZIP the `tes3np` folder with the entry script, source, assets, scripts, bundled patches and documentation. Do not include user settings, logs, temporary files or compiler output. A compiled release still needs its external assets beside the executable; compiled distribution is not currently supplied.

## Validation before release

Test on Windows with AutoHotkey v2:

1. Fresh startup and startup with a saved default; tray access after quick launch.
2. Add, edit, save, cancel, remove confirmation and the 10-character limit.
3. Tick persistence and per-row Play without changing the default.
4. Login timings, terminal-only startup, process loss and reconnect on/off.
5. Launch All & Close, its 10-second wait, cancellation of its explanation and saved suppression choice.
6. Hover/press states, minimizing/restoring, dialogs and shutdown without artifacts or errors.
7. Saved settings survive replacement of the application folder.

Static checks alone do not validate Windows GUI behavior, game login acceptance or daily-point awards.

Patching release checks are listed in [PATCHING.md](PATCHING.md). Menu availability uses freshly verified runtime state, not a stored completion flag alone. The patch worker owns file mutations; the GUI only reads its progress/result files. Progress uses the existing buffered loading card with measured percentages.

## Collaboration tooling

Start with [CONTRIBUTING.md](../CONTRIBUTING.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
Run `python scripts/project.py check` for source/manifest checks and
`powershell -NoProfile -File scripts/check-powershell.ps1` for actual PowerShell
parser checks on Windows. The GitHub workflow runs both.
`python scripts/project.py package` builds a checked complete release ZIP.
The build number is defined once in `AppConfig.Build` in `src/state.ahk`.
See [RELEASING.md](RELEASING.md) for packaging and repository setup.
