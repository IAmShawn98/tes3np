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

## Embedded Game Chat and Happy Hour contract

The AutoHotkey launcher remains authoritative for the application lifecycle,
window ownership, user settings, and diagnostics. `src/ui/embedded-chat.ahk`
starts/stops the separate Windows Forms/WebView2 companion
(`chat-host/Program.cs`). The Chat Host owns its own docked window and chat
content; it communicates chat visibility through the existing window messages
`0x8331` (launcher commands) and `0x8332` (Chat Host state). Do not add a
second Chat Host process, popup ownership controller, or competing chat timer.
Its existing `WatchLauncherMovement` WinEvent hook tracks the AutoHotkey
launcher's native `EVENT_OBJECT_LOCATIONCHANGE` events. The Happy Hour banner
is an **owned top-level popup** (not a clipped child window): ownership controls
z-order/minimization, but does not automatically move the popup with its owner.
Use the same event hook and native, nonactivating `SetWindowPos` to move it
immediately. The existing chat positioning poll is only a fallback, and the
Happy Hour one-second timer updates countdown text rather than window position.

**One persistent data root:** `src/state.ahk` declares
`AppDataDirectory := A_AppData "\\tes3np"`. Chat Host uses the corresponding
`ChatDataRoot` (`%APPDATA%\\tes3np`), with:

- `chat-host.log`: Chat Host diagnostics at the root, alongside `launcher.log`.
- `Logs/game-chat-index.json` and `Logs/game-chat.log`: Discord messages and
  real snowflake IDs, including verified image attachments.
- `chat-webview2/`: embedded Discord browser profile.
- `chat-display-mode.txt`: saved chat visibility preference. A Happy Hour
  detection uses only actual Discord messages in the archive, not marker files.

`chat.ini`, `chat.css`, and packaged chat artwork stay beside the executable:
they are distribution/configuration assets, not personal logs. Earlier development
builds wrote a `happy-hour-last-seen.txt` marker in Local AppData or Roaming
AppData; the banner-only implementation no longer reads, migrates, or writes
that obsolete file. Clearing Roaming data must remain a genuine reset. No new
persistent Chat Host state is written to Local AppData.

**Happy Hour lifecycle:** on Chat Host startup read the local Roaming chat
archive even if Discord is signed out. A genuine bot-authored text announcement
or pixel-verified image with its original Discord snowflake can display the
banner offline, but only during the real sixty-minute active period. An empty
archive, old expired message or obsolete last-seen marker cannot trigger it.
Authentication gates **fetching new Discord messages and history paging**, not
presenting an already verified active announcement. When Discord becomes
available, search the indexed messages first and page the hidden channel if
necessary. The original snowflake determines the expiry; the existing countdown
timer closes the banner at its end. Logout pauses network collection without
hiding a still-valid cached banner or resetting its countdown. The unattended
scan ends at the active one-hour boundary. Chat visibility and manual scrolling
never control pagination. The launcher-owned banner is the **only** Happy Hour
notification; no separate large popup appears.

Archive exports are written to temporary files and atomically replaced to
avoid corrupting the only saved index during long history scans. Do not rewrite
the entire archive once per message.

**First Discord sign-in:** the native HTML chat renderer must initialize and
finish its local navigation before the login view hides its WinForms parent.
When Discord redirects to Game Chat, restore the original docked panel and
reload that authenticated channel **once** to complete the SPA handoff, without
restarting the launcher or spawning another Chat Host. Keep an already-open
Automatic chat panel visible through this transition. This sequence changes
neither the persisted browser profile nor the Happy Hour archive.

**Validation:** `scripts/check-chat-architecture.py` guards these contracts
and the normal CI checks now compile `chat-host/tes3np.ChatHost.csproj`.
Static checks do not establish successful Discord authentication, WebView2
rendering, Happy Hour recognition, or Windows window positioning. Verify those
behaviors in an actual launcher build. Expired-announcement preview mode has
been retired and the CI architecture guard rejects its reintroduction.

## Session contract

`ClientTick` owns recovery. Phases are `launch`, `window`, `username`, `password`,
`loading`, `playing`, `claim`, `closing`, `retry` and `stopped`.
`UpdateGameLoginProgress` only presents state in a nonactivating, click-through
native window. It does not send inputs or add a recovery watchdog. The step dots
track timed screen waits and actual SendText calls. The approved four-step
gold-bordered production display finishes when the password input is sent and
closes three seconds later. This marks **input completion**, not server-confirmed
authentication. The saved in-game load delay, crash recovery, ten-second batch
claim wait, and scheduled multi-login handoff timing remain unchanged.
The simulated developer preview has been removed. Cancelled sessions dispose
of the card. Only a visible SDL window belonging
to the tracked PID qualifies as the game. Credentials use configured delays, not
OCR. Never add a second watchdog.

`AppConfig` centralizes endpoints, default delays and controller intervals.
Existing characters retain saved delays. The sorted 10-race species selector
requires an explicit choice for new characters; existing profiles with no
species remain editable and use the original login icon. Species is saved in
each character's INI section and portable export/import. A selected species
maps to `assets/icons/species/<slug>.ico` (lowercase with hyphens) when that
portrait exists; otherwise the original TES3NP icon remains. Bundled builds
already include nested assets automatically. The separate `Original Character`
entry at the bottom of the editor dropdown opens an image picker, accepts only
512 x 512 PNG/JPG/JPEG/BMP images up to 10 MB, and then prompts for the
character's actual species in a small owned dialog. The race is shown directly
below the editor dropdown and remains saved as the ordinary `Species` INI key.
Each character can independently select an OC portrait. Only when the character
is saved is the image copied to `%APPDATA%\tes3np\portraits` with a generated
basename stored as `PortraitFile`; arbitrary source paths are never saved.
Cancelled or rejected selections preserve previous settings. At login the
existing presentation-only card uses the saved image when present, falling back
to the species ICO if it is missing. Input timing and game recovery are unchanged.
Custom images are local data and are not bundled in the portable v1 INI export;
restoring the backup keeps the real species and its stock icon. `NewCharacterProfile`
supplies new-profile defaults. `%APPDATA%\tes3np` remains the data root.

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
