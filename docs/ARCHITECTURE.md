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
| `src/ui/macros.ahk` | Embedded Installed Macros in Character Book; script/ZIP import, linked apps and process tracking |
| `src/ui/macro-bindings.ahk` | Declarations and saved macro keys |
| `src/ui/patcher.ahk` | Setup gate, worker orchestration and results |
| `scripts/patch-tes3mp.ps1` | Verification, backups, installation and rollback |
| `scripts/import-macro.ps1` | ZIP validation and extraction |

State remains shared rather than class-based to preserve the accepted native GUI
behavior. Each feature has one initialization point and one responsible module.

## Launcher background artwork

The approved vintage beast pair is permanently composited into
`assets/backgrounds/launcher.png` at source resolution (1448 × 1086).
`src/ui/front-page.ahk` draws this image once at `x0 y-4 w960 h720`.
The obsolete `og-creatures-overlay.png` and its separate `x50 y230`
picture control have been removed. Preserve the single-image design
when adjusting artwork; the separate overlay previously showed seams
and the original beasts underneath. Keep all native launcher controls,
the Game Chat tab, and Happy Hour pixie dust drawn afterward.

## Embedded Game Chat and Happy Hour contract

The AutoHotkey launcher remains authoritative for the application lifecycle,
window ownership, user settings, and diagnostics. `src/ui/embedded-chat.ahk`
starts/stops the separate Windows Forms/WebView2 companion
(`chat-host/Program.cs`). The Chat Host owns its own docked window and chat
content; it communicates chat visibility through the existing window messages
`0x8331` (launcher commands) and `0x8332` (Chat Host state). Do not add a
second Chat Host process, popup ownership controller, or competing chat timer.

## Embedded Discord download inside plugin-mismatch dialog

The original top-left Expansion Pack enabled/disabled control is restored and still calls `ToggleExpansionPack` / `RefreshExpansionPackToggle`. The separate Expansion Downloads popup has been retired. `src/game/expansion-mismatch.ahk` creates the standard owned plugin rejection dialog, including a native placeholder HWND. It posts command `6` with that placeholder handle on the existing Chat Host `0x8331` route. `chat-host/Program.cs` creates a *native WS_CHILD window* attached via `SetParent` to that control and sizes it from `GetClientRect` (no separate floating download window). Command `7` requests disposal before destroying the AHK dialog. The Chat Host's existing `CoreWebView2Environment` and `chat-webview2` Discord profile remain shared; no second process, profile, or Happy Hour watchdog is created.

The `ExpansionDownloadsFocusScript` preserves Discord's DOM and identifies the most recently available ZIP in channel `1555049936800718928` by numeric Discord message snowflakes (with bounded history search and refreshed signed CDN URLs). A temporary, launcher-owned mismatch dialog contains a native WebView2 child sharing Game Chat's existing Discord profile. ZIP clicks use `preventDefault()` and a WebMessage to ChatHost, which validates HTTPS, exact Discord CDN host, attachment path, and ZIP extension before launching the signed URL in the default browser on a worker thread. Files are never installed automatically; the existing OK/file picker and safe import worker remain unchanged. The plain Discord-channel link is the fallback for authentication or markup failures.

**November 1 rollback / recovery:** The experiment replacing the browser with a native WinForms card immediately upon ZIP discovery caused the entire dialog to freeze and has been reverted. The tested pre-experiment WebView2 card is restored. After Windows accepts a download handoff, ChatHost sends WM_APP `0x8335` with the current placeholder HWND. AHK validates the session, hides the old dialog, and sends existing command `7` to dispose the embedded browser. ChatHost acknowledges disposal with `0x8336`; only then does AHK destroy and reopen the mismatch prompt, triggering fresh Discord discovery. A bounded fallback shows the original dialog if no acknowledgment arrives. A stale HWND/timeout cannot reopen an unrelated dialog. Every new ZIP request starts a new browser handoff; no download-busy lock is used. The only user-facing click status is **Starting Download...**. The original Expansion Pack enable/disable toggle, Game Chat, Happy Hour, and external browser download are separate. Windows compile/runtime validation of this auto-reopen workflow remains pending.

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

**Happy Hour lifecycle (normal behavior):** Chat Host reads the Roaming chat
archive at startup, including while Discord is signed out, and recognizes only
genuine Yagrum-authored text or pixel-verified image announcements. An event is
active for one hour after its original Discord message timestamp. The temporary
`ShowExpiredHappyHourForAlphaTest` override is set to `false`: expired events
remain in the archive but cannot display the banner, Jiub alternate face or
pixie dust. Genuine active events show their true remaining time, and newer
valid announcements replace older ones. An empty or expired-only archive
shows nothing. Authenticated Discord is required only for live fetching and
paging; an active cached announcement can be shown while signed out. Historical
discovery stops after covering the current one-hour window, subject to the
existing six-minute/500-attempt safeguards. No obsolete last-seen markers are
read or written.

**Banner and Jiub presentation:** The one existing bronze Happy Hour banner has
no dismiss button and uses the normal `HAPPY HOUR ACTIVE - Mastery Points Are
Doubled!` title and actual remaining countdown, only while active.
Jiub's image is `assets/happy-hour/jiub-happy-hour.png`, presented as a
transparent child control by `src/ui/happy-hour.ahk` at the user's adjusted
`x438 y84 w120 h135`. The **static** transparent RGB dust (`assets/happy-hour/pixie-dust.png`,
960x720) adds a sparse scattering of tiny colored speckles. The original
one-pixel cores were practically invisible at normal launcher scale, so the
same asset is drawn four times at logical offsets (0,0), (1,0), (0,1), and
(1,1) for a restrained, more legible twinkle. These four disabled and
mouse-transparent native picture children are created immediately after the
original background and before interactive controls. They share the launcher
window, scale and move with its layout, and cannot draw on the desktop or
intercept clicks. The existing verified banner signal toggles all four
together with Jiub. There is no animation timer, separate top-level window,
or compositor-follow loop. The original crescent, background and all launcher
controls are unchanged. Chat Host posts `WM_APP + 0x334` to the launcher
whenever it shows/hides this banner; Jiub follows the same message and moves
natively with the launcher. The separate 60-second developer replay,
command-line dev flag, alternate banner text, tray toggle, and 20-second
portrait-only preview have all been removed. No separate overlay window,
animation, or graphic effects remain. Windows compilation and runtime checks of both live and expired announcements
are still required to complete validation.

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
entry at the bottom of the editor dropdown opens an image picker for
PNG/JPG/JPEG/BMP files up to 10 MB, with a bounded decoded-pixel limit.
It does not require the user to resize manually: on Save, the chosen image is
silently center-cropped to a square, resized with GDI+ high-quality bicubic
interpolation and saved as a transparent-capable 512 x 512 PNG under
`%APPDATA%\tes3np\portraits`. Unsupported/corrupt or excessively large
images are rejected; valid images receive no resizing notification.
After a valid image is selected, an owned species dropdown asks for the
character's actual Morrowind species. Once confirmed, the **main species
dropdown displays that race** rather than remaining on "Original Character",
and a clickable hint below identifies the private portrait and offers to
change it. The chosen race is also saved as the ordinary `Species` INI key.
Selecting a different stock race manually later removes the unsaved custom
portrait choice, but returning from the OC species dialog does not.
The selection and the portrait are independent: a species entered in
the OC dialog is descriptive metadata and must never overwrite the chosen
picture with the standard species icon. The editor keeps explicit OC mode
rather than relying on the transient native dropdown text. The species label
is drawn below (not underneath) the dropdown, without reopening the book.
Each character can independently select an OC portrait. The file gets a
generated basename stored as `PortraitFile` only when Save completes; arbitrary
source paths are never saved.
Cancelled or rejected selections preserve previous settings. At login the
existing presentation-only card uses the saved image when present, falling back
to the species ICO if it is missing. Input timing and game recovery are unchanged.
Custom images are local data and are not bundled in the portable v1 INI export;
restoring the backup keeps the real species and its stock icon. `NewCharacterProfile`
supplies new-profile defaults. `%APPDATA%\tes3np` remains the data root.

## TES3MP plugin mismatch recovery

`src/game/expansion-mismatch.ahk` is called from the **existing** `ClientTick` watchdog. It records client log lengths before each launch, reads only fresh `tes3mp-client*.log` content in the configured OpenMW user directory (including relocated Documents), and handles the exact server plugin/load-order rejection message. It stops only the failed PID, cancels batch/scheduled follow-ups, and displays the owned Upload Expansion / Cancel dialog. It does not impersonate the server, assume a new pack exists, or establish checksum compatibility without a real connection.

`src/ui/expansion-upload.ahk` owns the file picker. Its PowerShell worker runs through the existing `PatchJob` progress loop and owns all game/config writes. `scripts/import-expansion-pack.ps1` accepts downloaded ZIP/ESP files, validates paths and extensions, stages and verifies bytes, and journals overwritten files for rollback. Never install downloaded code/executables from these archives or replace the launcher/markerless TES3MP client. The manually imported pack can differ from the separately bundled manifest, which remains the authoritative expected content for the older Install / Repair path. Windows tests are required to confirm native popup timing and the upload dialog.

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
