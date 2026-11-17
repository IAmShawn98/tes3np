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
| `src/ui/patcher.ahk` | Shared Morrowind discovery, Expansion Pack toggle, active import progress/exit guards |
| `src/ui/expansion-upload.ahk` | Native ZIP/folder selection and active import startup |
| `scripts/import-expansion-pack.ps1` | Validated current-package import, backups, rollback and results |
| `scripts/import-macro.ps1` | ZIP validation and extraction |

State remains shared rather than class-based to preserve the accepted native GUI
behavior. Each feature has one initialization point and one responsible module.

## Launcher-owned page geometry and scale

The launcher controls its own effective `LauncherScale` (Auto or manual). A child page must **not** infer position/scale from the mouse cursor or Windows' remembered first-show location.

`src/ui/windows.ahk` provides `GetOwnedMenuScale`, `PositionOwnedMenuAtParent`, and `ScaleOwnedMenuContent`. Child positioning uses the owning HWND's current screen rectangle and monitor work area; child geometry and native LOGFONT handles are rescaled while hidden or cloaked. Only staged Settings/Character Book use DWM first-paint protection. Preserve the approved original contents/layout; do not insert extra whitespace or cover controls with a separate background.

Launcher Settings uses `V016SettingsScale` equal to the effective launcher percentage (limited by monitor fit) and `V016S`/`V016Font` for native geometry. Themed buttons receive `MenuButtonScale` so their text follows the same percentage. Character Book is a persistent cached GUI: `ApplyCharacterBookScale` rescales its children and reloads its existing parchment at the new size; `BookS` maps dynamic editor and macro positions from immutable 100%-size logical coordinates. Mouse-wheel and thumb drag hit tests divide by both Windows DPI and book scale to remain aligned. A moved/scaled book does **not** invalidate the parent launcher cache or invoke its costly global repaint on Close.

Keep the following invariants: after dragging the launcher, both owned pages are positioned from its **current** HWND; after any Settings Preview Changes result, Settings anchors to the current launcher again; cached book reopens at the current launcher scale and position; nested native dialogs center on their immediate owner. DWM cloaking remains only for the existing staged pages. The native Expansion Pack download UI, its Discord-hosted repair page and ChatHost geometry are independent; they were not changed in this menu-page pass.

CI: `scripts/check-ahk-compile.ps1` executes `--check-owned-menu-scaling` on a disposable Windows GUI (50–100% child geometry, owner moved after child construction, monitor-edge clamping). A GUI smoke passing cannot replace actual desktop checks for readable page fonts, complete parchment, controls and no latency/pop-in.

## Launcher background artwork

The approved vintage beast pair is permanently composited into
`assets/backgrounds/launcher.png` at source resolution (1448 × 1086).
`src/ui/front-page.ahk` draws this image once at `x0 y-4 w960 h720`.
The obsolete `og-creatures-overlay.png` and its separate `x50 y230`
picture control have been removed. Preserve the single-image design
when adjusting artwork; the separate overlay previously showed seams
and the original beasts underneath. Keep all native launcher controls,
the Game Chat tab, and Happy Hour pixie dust drawn afterward.

## Diagnostic privacy and recovery-state boundaries

The launcher-wide `LogLauncherEvent` writer and clipboard exports pass through
`SanitizeDiagnosticText`. The standalone C# Chat Host and PowerShell updater
sanitize their **own** write boundaries. Import/toggle workers clean result/error
messages, and native picker errors report only exception category and HRESULT.
Sensitive details are removed without visible placeholders, while public
character names remain in character-labeled launcher events. A versioned,
best-effort one-time cleanup of historical diagnostic logs runs after profiles
load; the current checkpoint is `PrivacyScrubVersion=4`; log migrations write a final newline and repair the historical joined-timestamp pattern seen in a copied Launcher Log.

Private state is distinct from shareable diagnostics. Do not scrub
`settings.ini`, profile/portrait/macro data, the WebView2 authenticated profile,
`Logs/game-chat.log`/`game-chat-index.json`, Expansion Pack rollback
`journal.json` or backup files: some require real local paths or Discord
content to recover safely. The user-facing importer `result.ini` retains an
availability indicator, not an absolute backup path. See
[historical diagnostic privacy audit](https://github.com/IAmShawn98/tes3np/blob/aebc384e384a71daa4080fa8e69fbbcd9bcf1a82/docs/DIAGNOSTIC-PRIVACY-AUDIT-2026-11-04.md)
and the [Windows acceptance checklist](ALPHA-COMPATIBILITY-CHECKLIST.md).

## Embedded Game Chat and Happy Hour contract

The AutoHotkey launcher remains authoritative for the application lifecycle,
window ownership, user settings, and diagnostics. `src/ui/embedded-chat.ahk`
starts/stops the separate Windows Forms/WebView2 companion
(`chat-host/Program.cs`). The Chat Host owns its own docked window and chat
content; it communicates chat visibility through the existing window messages
`0x8331` (launcher commands) and `0x8332` (Chat Host state). Do not add a
second Chat Host process, popup ownership controller, or competing chat timer.

## Authenticated Discord download for missing Expansion Pack or plugin mismatch

The original top-left Expansion Pack control still calls `ToggleExpansionPack` / `RefreshExpansionPackToggle`. Installed-pack detection now examines both `Morrowind/Data Files` and existing `data=` directories in the selected `openmw.cfg`; the PowerShell toggle rechecks these same locations without copying files. It **never installs assets on enable**: a present `Data Files/NP Expansion Pack.esp` can be enabled in OpenMW, while a missing file triggers an install request. A plugin mismatch triggers the same dialog in diagnostic mode. Both requests first send command `10` to the existing ChatHost using the `0x8331` route. For a previously authenticated channel, the ChatHost rechecks the **live** Discord message-list DOM rather than trusting an earlier ready flag. ChatHost reveals its established Game Chat Discord login UI if signed out and responds with `0x8336` (the originating ChatHost HWND and requested mode) **only after** its genuine Game Chat channel is authenticated. AHK validates this HWND belongs to its current ChatHost PID before showing either dialog. A zero-mode reply cancels pending requests when the user closes or hides sign-in. No Discord-dependent dialog is shown early. The existing child ZIP browser is attached via `SetParent` only after authentication and rejects unauthenticated command `6` calls. Command `7` disposes it; command `9` hides it after a real signed ZIP link is found, preserving the native retry button. ChatHost continues to share one `CoreWebView2Environment` and one `chat-webview2` Discord profile with Game Chat. Discord ZIP discovery remains authenticated through the existing ChatHost. For the first-enable flow, the user can explicitly approve an automatic download and install; the existing manual ZIP/folder import remains available for repair. No second login window, second ChatHost, or Happy Hour polling process is added.

The `ExpansionDownloadsFocusScript` preserves Discord's DOM and identifies the most recently available ZIP in channel `1555049936800718928` by numeric Discord message snowflakes (with bounded history search and refreshed signed CDN URLs). A temporary, launcher-owned mismatch dialog contains a native WebView2 child sharing Game Chat's existing Discord profile. ZIP clicks use `preventDefault()` and a WebMessage to ChatHost, which validates HTTPS, exact Discord CDN host, attachment path, and ZIP extension before launching the signed URL in the default browser on a worker thread. In Browse and plugin-mismatch mode, browser download still requires a separate manual import. In first-enable mode only, a user-approved automatic transfer can invoke that same transactional importer after the complete ZIP has arrived. The plain Discord-channel link is the fallback for authentication or markup failures.

**Post-download freeze mitigation, November 1:** The launcher previously called `Run(url)` synchronously from its AutoHotkey GUI event and left a live, cross-process WebView2 painted over the ZIP controls. That could cause the whole launcher window to stop responding after a browser handoff. This update keeps the same ChatHost and shared authenticated Discord profile, but **only uses the visible embedded WebView2 while discovering the current ZIP**. Once ChatHost sends the latest signed attachment URL through bounded `WM_COPYDATA`, the launcher verifies the exact host PID, current placeholder and ZIP URL, reveals an **AHK-owned button with the filename**, and asynchronously requests ChatHost command `9` to **hide** (not destroy/recreate) the child WebView. The launcher additionally hides the **placeholder Text HWND itself**, then raises and redraws the filename button, because Windows feedback showed it was visible but did not respond to clicks while the separate Retry button worked. Both controls dispatch the same ZIP request routine and are distinguished in logs. The two native AHK download buttons stay accessible even if Discord stops repainting. AHK now starts `rundll32.exe url.dll,FileProtocolHandler "<validated-url>"` as a separate process, rather than invoking the browser ShellExecute synchronously on its own GUI thread. Browser downloads and cancellation occur outside both the AHK GUI thread and the embedded WebView. There is no per-download WebView creation, disposal, busy flag, or popup recreation. The download buttons no longer leave a persistent progress label; they simply hand off the ZIP URL to the user's default browser. The hidden WebView may continue refreshing signed URLs in the background; closing the prompt disposes it using the original command `7`. The file picker/installer, Happy Hour, Game Chat, and original enable/disable toggle are unchanged. The mismatch **Copy Diagnostic Info** action generates only allowlisted flags/counts from local config and bounded log inspection. Following a Windows-reported copy failure, it copies directly with AHK's synchronous `A_Clipboard` assignment (matching the established Troubleshooting copy routine), rather than waiting with `ClipWait`. Optional-report errors use an allowlisted minimal report; temporary clipboard locking is retried asynchronously. Debug logs record only error class and source line, never raw exception messages or private file contents. **This is a source-level mitigation; Windows responsiveness and repeated-download behavior are not yet verified.**

**First-enable automatic download and local repair (November 9, source implementation pending Windows checks):** When the global Expansion Pack toggle is enabled but `NP Expansion Pack.esp` is missing, a user confirmation offers automatic download, manual ZIP/folder installation, or cancellation. The authenticated, current Discord attachment already discovered in the official channel is the only accepted automatic source. Native command `13` sends the current owned ZIP-preview HWND to the existing ChatHost; it verifies current authenticated channel state, slot ownership and exact HTTPS Discord CDN/attachment ZIP constraints. It downloads using one cancellable asynchronous `.NET HttpClient` worker, without invoking the default browser, blocking AHK, or placing short-lived signed CDN tokens on a command line or in logs. The URL remains in ChatHost memory. Automatic transfers reject redirects, missing space, oversized/incomplete downloads, and non-ZIP signatures, write only private transient `.partial` files, and rename to `.zip` on completion. The dispatcher sends sanitized progress via `0x8338` and returns the finished private ZIP path via bounded `WM_COPYDATA` with ID `0x8337`. AHK checks the current ChatHost PID and the file's expected private directory/filename before deferring installation out of the synchronous native callback. The existing `StartExpansionImportWorker` performs all archive allowlist checks, staged hashing, verified backups, atomic replacements and rollback; no second importer is introduced. Once the import finishes, the auto-downloaded ZIP is removed, not the backup/journal. Failed download leaves Morrowind and `openmw.cfg` untouched and offers **Repair / Install ZIP**, using the existing native local picker; a failed install offers that same recovery path while retaining backup evidence. A cancelled dialog cancels its transfer. Signed attachment provenance does **not** prove live server compatibility without a published checksum/version manifest. This is not yet a tested Windows runtime result.

**Automatic first-install presentation refinement (November 9, pending Windows validation):** The first Yes on the top-left toggle no longer displays the Expansion Pack Downloads/Repair page as the normal progress surface. Once Game Chat's existing authentication succeeds, the launcher constructs the existing native `CaptureInterfaceFrame(LauncherGui, true)` loading card and progress bar with a dedicated **Cancel Download** button. The normal launcher window is disabled while that modal download card is active. To retain WebView2's required visible HWND for live Discord DOM discovery, the existing authenticated discovery dialog is created but `DwmSetWindowAttribute(DWMWA_CLOAK)` is applied **before its first Show**, keeping it invisible to desktop composition without moving it offscreen, invoking `SW_HIDE`, or creating another ChatHost/profile. The validated ZIP notification starts the existing asynchronous transfer; `0x8338` updates only the native progress card. After successful transfer, the auto progress card and cancel control are destroyed before the existing transactional install worker displays its own progress. The same dialog is uncloaked and exposed **only** on download/discovery failure, missing progress UI, or timeout, retaining the original official ZIP, Retry and manual **Repair / Install ZIP** choices. User cancellation closes the hidden dialog, cancels the ChatHost transfer, and releases the native progress overlay without revealing the fallback page. All existing manual Browse/plugin-mismatch dialogs remain visible as before. `DWM` cloaking must be verified against real WebView2 navigation on Windows; the source/CI checks alone cannot establish that a WebView inside a cloaked parent will discover messages successfully.

**Native Cancel Download repaint correction (November 9, pending Windows visual recheck):** User runtime screenshots verified that Discord discovery and the native download card work; the progress percent updates, and the original full-height dark panel with Cancel inside the same gold border is the approved appearance. The first flicker was caused by the loading panel's custom `GetDC/BitBlt` repaint covering a button that is a sibling HWND. A temporary non-overlapping, dark-recolored card avoided flicker but created a visible separate footer, which the user rejected. The approved layout is restored: the native loading panel fills the entire card, Cancel remains just below its progress bar at the original coordinates, and `ProtectExpansionLoadingCancel` records the button HWND in the loading renderer's `ButtonFaces` state. Only this download panel's `PaintLoadingPanel` now uses the button's actual screen rectangle mapped to the panel client, `SaveDC` / `ExcludeClipRect` around the final `BitBlt`, and `RestoreDC` afterward. Other loading panels are unchanged. This protects the button's pixels during every progress repaint without artificially repainting/recreating it. The completed-ZIP handoff still immediately locks and destroys Cancel before transactional installation, and failed downloads still use the existing repair fallback. Source and CI validation are separate from final Windows no-flicker verification.

**Native Cancel flash correction (November 9, pending Windows visual recheck):** A 13-second user-recorded 60 fps Windows video showed that the cancellation button still flashed solid white for roughly 1–3 frames whenever the automatic download status changed, before the extra repaint restored the themed gold button. This confirmed the prior **repaint Cancel after every progress update** mitigation hid the problem after the fact, without preventing transient native white paints. The actual trigger was `UpdateExpansionLoadingProgress` setting `frame.Panel.Text` on every update, which calls native `WM_SETTEXT` on the enlarged full-height Static panel, invalidating the entire overlapped footer. The renderer now stores a dedicated `DownloadText` caption on the existing loading `ButtonFaces` record, uses that text when painting the panel, and flags `ProgressHeaderOnly` exclusively during incremental progress updates. `PaintLoadingPanel` then blits just the original 68-unit title/progress area, not the button/footer region. It still draws the complete panel when Windows needs an actual full paint or exposure; other loading panels continue with their original text and drawing behavior. No new controls or repaint timer are introduced; cancel remains inside the same full-height gold-framed dark box and is locked/removed on completed ZIP handoff. Windows outcome remains unverified at this source checkpoint.

**Premature Expansion repair dialog regression (November 9, pending Windows retest):** After the header-only cancel-button paint update, a user Windows screenshot showed the **Expansion Pack Download Needs Attention** page immediately after first-enable, with a subsequently discovered official ZIP named and a contradictory **Beginning automatic download** status. Source inspection confirmed a startup state sequencing bug: the first native progress-card capture failure revealed Repair immediately, while a later asynchronous authenticated Discord ZIP callback unconditionally overwrote the repair reason and could still schedule an automatic download. The first-enable path now retries a failed native card capture **once after 300 ms**, retaining the DWM-cloaked authenticated WebView2 discovery parent; the final repair page appears only if the second attempt also fails. A ZIP discovered before the retry is retained but never auto-transferred until a valid native progress frame exists; once the frame recovers, a single guarded delayed transfer is scheduled. On a real failure the repair page retains its actual failure status even if a later ZIP link refresh arrives. Stage-specific allowlisted log messages distinguish capture from native card/button setup. Existing manual Browse and mismatch dialogs, ZIP allowlisting, rollback, and Cancel's completed-ZIP lock are unchanged. The screenshot by itself does not distinguish a native presentation failure from a Discord/HTTP transfer failure; real Windows logs and runtime confirmation remain necessary if the fallback persists.

**Verified native downloader construction fix (November 9, CI Windows GUI tested; user runtime recheck pending):** Two Windows user screenshots showed the auto-download path opening **Expansion Pack Download Needs Attention** with a valid Discord ZIP discovered and eventually the specific `Native download window could not initialize` message. Repeated UI capture retries did not fix it. Source-only compilation and earlier synthetic painter checks missed the error. A new opt-in `--check-expansion-window` launcher mode builds a disposable 960x720 native window, initializes the same native painter, creates a DWM-cloaked owned discovery window, calls the **actual** `TES3MPExpansionBeginNativeProgress`, checks the real Cancel HWND, and paints multiple progress values without touching game files or contacting Discord. The Windows CI workflow now runs this mode after Ahk2Exe compilation. It reproduced the failure before the fix, with `Native captured frame construction failed (ValueError, line 308, operation DllCall)`. Comparison with the previously working renderer found the exact defect: the incremental `PaintLoadingPanel` Win32 `BitBlt` call had accidentally dropped its source-Y coordinate value and passed `"UInt"` where the integer argument belonged. The missing `"Int", 0` was restored, with a strict architecture regression guard for this signature. On the corrected source the actual Windows GUI smoke test succeeded. The protected single-box Cancel button layout and header-only redraw logic remain; the safety lock still destroys Cancel once the ZIP is complete, before transactional installation. The later authenticated Discord transfer and the complete installation still require user Windows runtime verification.

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
Automatic chat panel visible through this transition. The login view
explicitly hides both `messageClip` (the HTML message WebView's **parent**)
and `messageBrowser` while the Discord sign-in UI is exposed.
`RestoreGameChatAfterSignIn` initially keeps them hidden with `nativeMode=false`.
When `RefreshNativeMessages` receives the first real authenticated feed and
switches `nativeMode=true`, it must restore `messageClip.Visible=true`
**before** `messageBrowser.Visible=true`: a visible child WebView under the
still-hidden parent produces a completely black message pane with the gold
frame/scrollbar rendered. Reopening the launcher can mask this first-login
bug because the sign-in route is skipped next time. The source guard now
requires the matching parent/child visibility transition. After the November 5 first-login visibility fix, the first authenticated
feed still revealed an incomplete view: `goldScrollbar` was hidden by
`ShowDiscordSignIn` and never shown again during `nativeMode` activation,
while `frameSurface.Paint` drew a static mock scrollbar underneath. The gold
arrows and bronze thumb therefore appeared stale until a later redraw.
The pending first-message state now explicitly calls `ShowConnectingChat()`
to show the existing `nativeMessages` label ("Connecting to live chat...")
in its normal `messageClip` parent with the gold title/frame visible and both
scrollbar/WebView message child hidden. The Discord source still fetches using
the same authenticated WebView2 profile, behind that loading view. The first
real message transition sizes/reveals `messageBrowser` behind the status text
**before** executing `window.setMessages`, then hides the label, restores the
single real textured `goldScrollbar`, runs `FitWebView`, and invalidates the
frame and thumb. The duplicate fake scrollbar painting has been removed, leaving
the real child as the only scrollbar. No new retry timers, login calls, browser
instances, or Happy Hour state changes are introduced. Windows visual/runtime
testing is required to confirm this post-login paint sequence. This sequence
changes neither the persisted browser profile nor the Happy Hour archive.

**Validation:** `scripts/check-chat-architecture.py` guards these contracts
and the normal CI checks now compile `chat-host/tes3np.ChatHost.csproj`.
Static checks do not establish successful Discord authentication, WebView2
rendering, Happy Hour recognition, or Windows window positioning. Verify those
behaviors in an actual launcher build. Expired-announcement preview mode has
been retired and the CI architecture guard rejects its reintroduction.

## Session contract

`ClientTick` owns recovery. Active phases are `launch`, `window`, `username`,
`password`, `loading` and `playing`; `stopped` is the terminal state.
`UpdateGameLoginProgress` only presents state in a nonactivating, click-through
native window. It does not send inputs or add a recovery watchdog. The step dots
track timed screen waits and actual SendText calls. The approved four-step
gold-bordered production display finishes when the password input is sent and
closes three seconds later. This marks **input completion**, not server-confirmed
authentication. The saved in-game load delay and crash recovery remain
unchanged; the retired scheduler, claim-and-close batch queue and event timer
are not compiled. Manual game launches still enforce the four-client limit.
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

`src/game/expansion-mismatch.ahk` is called from the **existing** `ClientTick` watchdog. It records client log lengths before each launch, reads only fresh `tes3mp-client*.log` content in the configured OpenMW user directory (including relocated Documents), and handles the exact server plugin/load-order rejection message. It stops only the failed PID and displays the owned Upload Expansion / Cancel dialog. It does not impersonate the server, assume a new pack exists, or establish checksum compatibility without a real connection.

`src/ui/expansion-upload.ahk` owns the file picker. Its PowerShell worker runs through the existing `PatchJob` progress loop and owns all game/config writes. `scripts/import-expansion-pack.ps1` accepts a downloaded ZIP or extracted folder, validates paths and extensions, stages and verifies bytes, and journals overwritten files for rollback. Never install downloaded code/executables from these archives or replace the launcher/markerless TES3MP client. The manually imported Expansion Pack is not compared against any old v0.1 payload; the current manifest tracks only the bundled markerless TES3MP client. No old Expansion Pack asset is a runtime or release dependency. The former Install / Repair UI and PowerShell worker have been retired. Windows tests are required to confirm native popup timing and the active upload dialog.

## Current Expansion Pack import worker contract

The only remaining `PatchJob` operation is `Import`, initiated by `StartExpansionImportWorker` using the current ZIP/folder worker. The GUI's existing loading overlay reads UTF-16 LE `progress.ini` and `result.ini` from the import job directory. A `success` result records the selected Morrowind and OpenMW locations and refreshes the Expansion Pack toggle; an `error` result presents the worker's diagnostics. Neither result asserts server version compatibility.

The worker owns staging, allowed-path checks, file hashing, backups, atomic file changes and rollback. Backups and journal metadata under `%APPDATA%\tes3np\expansion-imports` remain available for manual recovery; the old bundled patcher's Restore Backup control is not part of this workflow. The initial Morrowind selection is informational and never silently installs optional content. The retired `Apply` / `Verify` / `Restore` worker and its tray GUI must not be restored.

## Rendering and shutdown

Themed controls have `ButtonFaces` records with immutable owner `Window` HWNDs.
Native subclasses draw into buffers. Keep product actions out of paint callbacks.
Release windows and callbacks before GDI+ shutdown. Exit is blocked during patch
jobs so copying can finish. Shutdown stops owned automation and leaves the game open.
