# TES3NP development

Build on Windows with `Build tes3np.bat`. Close the launcher before replacing
the executable. The build validates source, PowerShell, Chat Host, bundled
resources, and the package before replacing `dist/tes3np-windows.zip`.
`AppConfig.Version` in `src/state.ahk` is the application version.

## Source map

| Area | Entry points |
| --- | --- |
| Startup, shared state, shutdown | `tes3np.ahk`, `src/state.ahk`, `src/app/bootstrap.ahk` |
| Layout, owned windows, and paint | `src/ui/front-page.ahk`, `src/ui/windows.ahk`, `src/ui/controls.ahk`, `src/ui/renderer.ahk` |
| Character profiles, backups, and macros | `src/ui/characters.ahk`, `src/data/settings.ahk`, `src/data/backup.ahk`, `src/ui/macros.ahk` |
| Game launch and crash recovery | `src/game/session.ahk`, `src/ui/login-progress.ahk` |
| Expansion Pack and mismatch handling | `src/ui/patcher.ahk`, `src/game/expansion-mismatch.ahk`, `src/ui/expansion-upload.ahk`, `scripts/import-expansion-pack.ps1` |
| Discord, Game Chat, and Happy Hour | `src/ui/embedded-chat.ahk`, `src/ui/happy-hour.ahk`, `game-chat/GameChatWindow.*.cs`, `game-chat/web/` |
| Packaging and resource extraction | `scripts/build-windows.ps1`, `scripts/check-windows-package.py`, `scripts/generate-bundled-resources.py` |

## Launcher UI and data

- `tes3np.ahk` loads explicit includes into one AutoHotkey process. Initialize
  shared state before startup and keep assets relative to `A_ScriptDir`.
- Lay out controls at 96-DPI logical sizes. Use `GetOwnedMenuScale`,
  `ScaleOwnedMenuContent`, and `PositionOwnedMenuAtParent` to anchor owned
  dialogs to the current owner HWND and monitor work area. Keep the staged
  Settings and Character Book first paint and the cached book's local redraw.
  Hit tests for the book account for both monitor DPI and launcher scale.
- Keep owner HWNDs immutable during buffered painting. Release windows and
  paint callbacks before GDI+ shutdown. Draw the composited launcher
  background once, then draw controls and the mouse-transparent Happy Hour art.
- Store personal data under `%APPDATA%\tes3np`, with DPAPI for saved
  passwords. Preserve settings keys and defaults. When adding a compatible
  profile field, update load/save, the editor, its consumer, and portable
  import/export together. Keep `Species` as the persisted key for the race.
- Stock race art uses `assets/icons/species/<race-slug>.ico`. Keep the PNG
  masters transparent around the crescent. Custom portraits are resized to
  512 × 512 and stored by generated name in AppData. The portable INI carries
  the race, and the local portrait file stays in AppData.
- Keep diagnostic output sanitized at each process's output boundary. Private
  settings, the Discord profile and archive, and rollback journals retain the
  data they need. Never commit personal exports or live logs.
- Rebuild after changing embedded artwork. Bundled resources extract under
  `resources\v-<content-hash>` so concurrent versions can use their own assets.

## Game sessions and Expansion Pack

- `ClientTick` owns launch, login, and crash recovery, with a four-client
  limit. Track the visible SDL window for the launched PID. The login card
  presents input progress. A normal game exit leaves the game closed.
- Mismatch recovery reads the fresh client log for the failed session and
  stops that session. Report fixed diagnostic categories and counts, never
  raw logs, mod filenames, or signed download URLs.
- Use the existing Discord session and authenticated ZIP discovery. Preserve
  download, retry, cancel, and manual import paths. Dispatch the browser
  handoff off the launcher UI thread. Keep the native download Cancel
  control available until the completed ZIP moves to import.
- The import worker owns staging, path checks, hashing, backups, atomic
  writes, and rollback. It reports through `PatchJob` and its job INI files.
  Toggle only the installed pack's OpenMW content entry. See
  [Expansion Pack import and recovery](PATCHING.md).

## Game Chat and Happy Hour

- Keep one Chat Host and WebView2 profile. The launcher owns lifecycle and
  placement. Chat Host owns chat state and the shared Discord session.
  The packaged `chat-host` binary, `chat.ini`, and `chat.css` paths are part
  of the updater contract.
- Initialize the native feed before the first Discord sign-in transition.
  Restore the dock and reload the authenticated channel once. On the first
  real feed, show the message parent before its WebView and restore the real
  scrollbar after rendering.
- Save the chat archive atomically in Roaming AppData. Live fetching needs
  Discord authentication. A genuine cached Yagrum announcement can still
  display while signed out. Use the original Discord message timestamp and
  expire the banner, Jiub, and dust together after one hour.
- The banner moves with the launcher through its existing window-event hook.
  The countdown timer updates time. Keep the overlay mouse-transparent.

## Validation

- Run `python scripts/project.py check`,
  `python scripts/check-chat-architecture.py`, and
  `powershell -NoProfile -File scripts/check-powershell.ps1` as applicable.
- For Chat Host changes, compile on Windows with
  `dotnet build game-chat/tes3np.GameChat.csproj -c Release -r win-x64 --no-self-contained`.
- Run `scripts/run-local-regression.ps1` on the Windows development checkout.
  It uses PowerShell 7 for updater fixtures. Use `-SkipBuild` on an existing
  build or `-NoLaunch` to skip the UI launch.
- See [Windows acceptance](RELEASING.md#windows-acceptance) for release tests.
