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
| `src/game/expansion-mismatch.ahk` | Fresh TES3MP client log watcher and server plugin rejection dialog |
| `src/ui/expansion-upload.ahk` | Local ZIP/ESP picker and shared patch-worker UI bridge |
| `scripts/import-expansion-pack.ps1` | Safe user-supplied expansion ZIP/ESP staging, verified backup, install and rollback |
| `scripts/import-macro.ps1` | Bounded ZIP validation and extraction |
| `src/ui/loading.ahk` | Frame covers and loading feedback for actual interface work |
| `src/ui/login-progress.ahk` | Nonactivating game login step card; presentation timer and cleanup |
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
- Installed Macros occupy the right side of Manage Characters and retain
  private script/ZIP packages under `%APPDATA%\tes3np\macros`.
  Linked .exe applications are stored as paths, never copied or uninstalled.
  The existing character editor temporarily hides this page's macro controls.
- Add a saved preference: update profile defaults/load/save in `settings.ahk`, the editor in `characters.ahk`, its consumer in `session.ahk`, and portable export/import in `backup.ahk`.
- Login and reconnect behavior: keep it in the single `ClientTick` state machine. Do not add an overlapping recovery timer.
- Replace artwork: retain the referenced dimensions, transparency and paths, or update every reference and the startup asset list.

## Rendering conventions

Coordinates are logical pixels at 96 DPI. Preserve the custom buffered paint path for themed controls. Keep immutable owner HWNDs on paint records; do not query a destroyed GUI's HWND. Destroy windows and release paint resources before shutting down GDI+.

Reuse precreated controls when editing. Redraw changed controls locally for scrolling. Use loading feedback for actual work; do not add artificial waits or a loading screen for ordinary scrolling. Avoid whole-window composited styles, which previously caused freezes.

## Data and packaging

Keep personal settings and logs outside the source tree. Preserve existing INI keys and defaults when adding preferences. Do not store credentials in code, screenshots, examples or committed settings files. There is no automatic migration to Local AppData in this version.

The Windows build script (`scripts/build-windows.ps1`, invoked by `Build tes3np.bat`) generates the compiled launcher and self-contained Chat Host in a complete `dist/tes3np-windows.zip` package. The Windows build first checks source, Chat Host persistence/authentication contracts, PowerShell syntax and C# compilation **before** deleting previous build artifacts or downloading runtime tools. Do not include user settings, logs, temporary files or developer credentials in a package. Public distribution remains blocked until the documented release evidence and explicit maintainer approval are complete.

Each compiled resource bundle extracts into its own `%APPDATA%\tes3np\resources\v-<content-hash>` directory instead of overwriting files used by an older launcher. This prevents cross-version `FileInstall` sharing violations when species artwork or other bundled assets change; short transient locks receive bounded retries. The build's `--check-resources` verification checks the version marker, required UI images, installed species ICOs and patch-manifest payloads before packaging. Existing roaming preferences, encrypted character passwords and the resources of already-running launchers are preserved. If extraction still fails, the error names the affected asset rather than silently launching with missing images.

Each Windows build stages downloaded tools in its own temporary directory. A temporary-file sharing violation during cleanup is retried and reported as a warning; once compilation, resources and ZIP integrity have passed, that cleanup issue must not prevent `Build tes3np.bat` from unpacking and publishing the new root executable. Actual compilation, validation or packaging failures still stop the build and must not launch an older executable. The operator should close the running launcher before rebuilding.

**Build SHA256 verification:** Three distinct integrity checks in `scripts/build-windows.ps1` (all extracted patch-manifest payloads, the official TES3MP archive, and the packaged markerless executable) use a streaming .NET SHA-256 helper rather than PowerShell's optional `Get-FileHash` cmdlet. Keep the expected-hash comparisons and fail-closed behavior. This addresses a Windows PowerShell 7.6.9 report where compilation succeeded but packaging stopped because `Get-FileHash` was not recognized. Windows confirmation of the next full package build remains pending.

The Launcher Settings → Launcher Data reset command stops Chat Host and recovery, deletes the shared Roaming AppData root, then exits without rewriting logs or scheduler state during shutdown. A failed delete must be reported rather than claimed successful. Reset does not erase the game installation. Legacy Happy Hour marker files in Local AppData are now inert and are not imported by Chat Host.

## Embedded Discord ZIP in plugin-mismatch dialog

The main page again displays the original **Expansion Pack: Enabled/Disabled** button. Only the plugin-mismatch dialog shows the Discord ZIP download. Its static child placeholder HWND is passed to the existing Chat Host through `0x8331` command `6`; command `7` closes/disposes the native WebView child. The Chat Host must reuse the same authenticated Discord profile, create no other Discord popup and never affect Game Chat or Happy Hour detection. Within the embedded browser, a scoped HTML overlay seeks the latest Discord channel messages, selects the newest ZIP by numeric message snowflake (not DOM order), searches a bounded number of older pages if needed, and observes new uploads/attachment URL refreshes. It displays the actual ZIP filename, size and clickable CDN link without reparenting Discord's DOM. **November 1 freeze regression:** letting the embedded WebView2 navigate to a large CDN ZIP (`target='_self'`) caused the popup to lock up without downloading. The card now uses `preventDefault()` and sends an explicit, user-initiated `expansion-download` message to the Chat Host. Validate scheme, exact CDN host, attachment path and ZIP extension before opening the signed link through Windows Shell with `UseShellExecute=true` on a background worker. Never log attachment tokens or navigate the embedded WebView2 away from its Discord session. The user's default browser handles the file download; there is no automatic installation. A further live report showed the embedded card seeming stuck *after* a download started, leaving no way to retry a cancelled browser download. The script now retains its click handler and immediately displays retry instructions, publishes `expansion-available` on ZIP discovery, and Chat Host caches only the validated latest signed URL in RAM. The native **Download ZIP / Retry** button sends command `8` with the popup placeholder HWND to request an independent browser handoff on every click. No completion/busy flag is used. Clearing the dialog clears the cache. The ZIP observer ignores updates within its own card and schedules a maximum of one scan per 150 ms; this guards against post-click WebView stalls from high-frequency Discord DOM mutations. Verify multiple successive clicks, browser cancellation and retry, missing URL, dismiss/reopen, latest ZIP rollover, and unchanged chat/Happy Hour. Prefer the real message ID to a filename version: future versions should require no launcher code change as long as Jiub posts a ZIP in the same channel. Do not claim guaranteed freshness if channel access, history loading or Discord markup fails; keep the existing manual channel link. Do not spoof URLs, override Discord's base grid, or install files automatically. The existing OK action still launches the transactional ZIP picker/import worker; the dialog includes an external channel link as a fallback. Verify via the existing chat architecture guard, .NET compilation, AutoHotkey build, and real Windows channel/download tests. The integration is SOURCE-ONLY until those Windows tests succeed.

## Embedded Chat Host changes

Treat `chat-host/Program.cs` as a separate WinForms process owned by the
AutoHotkey launcher, not as an independent application with its own data
conventions. Read `docs/ARCHITECTURE.md` and `src/ui/embedded-chat.ahk`
before editing it.

Persist personal Chat Host state only through `ChatDataRoot`, which matches
the launcher's `%APPDATA%\\tes3np`. The message index and export remain in
its `Logs` subfolder; the WebView2 profile stays in `chat-webview2`.
Changing the installation folder must not reset user state. Chat Host no longer
uses Local AppData, including the old Happy Hour last-seen marker. Removing
the earlier duplicate-popup feature also removed its migration and storage
logic. Clearing Roaming data intentionally must produce a fresh profile,
even if an obsolete marker remains on disk elsewhere.

Game Chat needs authentication to **retrieve or paginate live Discord
messages**, not to display a genuine recent announcement in the existing
Roaming chat archive. Load the archive at Chat Host startup even while signed
out. Its genuine bot text and pixel-verified image announcements have original
Discord message IDs; only those IDs determine the active one-hour window.
An empty archive, obsolete marker or expired announcement must not display
anything. Logout stops live fetching but must not dismiss a valid cached banner
or restart its countdown. The banner is the sole Happy Hour notification.

For first sign-in, finish initializing and navigating the native HTML message
renderer before hiding its WinForms parent for the Discord login screen.
After authentication restore the existing docked Game Chat, preserve an
already-open chat panel, and reload the authenticated Discord channel once
to complete the SPA handoff. Do not require an application restart or add
a parallel WebView2 profile, Chat Host, or authentication timer.

Before committing a Chat Host change:

1. Read the existing state/auth/archive and launcher ownership contracts.
2. Run `python scripts/check-chat-architecture.py`.
3. On Windows, compile with
   `dotnet build chat-host/tes3np.ChatHost.csproj -c Release -r win-x64 --no-self-contained`.
4. Run `Build tes3np.bat` and exercise fresh sign-in **without restarting**,
   signed-out active archive, signed-out empty archive, logout/relogin while a
   banner is active, expired event, and current event paths.
5. Verify the completed chat UI and window ownership; source checks and
   successful compilation alone cannot prove runtime behavior.

Both the lightweight CI workflow and the Windows packaging workflow run the
architectural regression guard. The lightweight CI also compiles Chat Host,
so C# syntax errors are caught without waiting for the complete launcher build.

## Happy Hour and Jiub production behavior

The temporary expired-announcement detection override
`ShowExpiredHappyHourForAlphaTest` is set to `false`. Only authentic
Yagrum-authored Discord activations less than one hour old display the normal
Happy Hour banner, Jiub alternate face and RGB dust. Expired announcements are
still retained in the archive but do not produce a visible Happy Hour or a fake
`0m 0s` countdown. No developer replay, launch flag, tray control or separate
notification is used.

1. Pull, build and launch `tes3np.exe` normally. With a recent verified
   announcement already in the Roaming archive, confirm that the genuine
   countdown appears even when Discord is signed out.
2. Confirm an expired-only or empty archive shows no Happy Hour banner,
   Jiub alternate face or RGB dust. The live search should cover the normal
   one-hour window, not the former alpha seven-day lookback.
3. Confirm that an active banner disappears when the original Discord event
   reaches one hour old, including after logout, window movement and resizing.
4. With a real active event, confirm the standard banner and on-launcher
   Jiub image at `x438 y84 w120 h135`, plus the established subtle RGB
   dust. They must remain synchronized, not intercept controls, and vanish
   together when the banner closes.
5. Confirm new authentic announcements supersede older ones; messages from
   other users, quoted announcements and unverified images cannot trigger it.
6. Run the architecture guard and C# build, then verify the launched Windows
   application. Code inspection or static checks alone do not prove runtime
   behavior.

## Validation before release

Test on Windows with AutoHotkey v2:

1. Fresh startup and startup with a saved default; tray access after quick launch.
2. Add, edit, save, cancel, remove confirmation and the 10-character limit. Test all ten species in alphabetical order plus the final **Original Character** option. A readable PNG/JPG/JPEG/BMP (≤10 MB) of any reasonable dimensions must open the separate race chooser and be silently center-cropped and resized to a 512 × 512 PNG on character Save. Confirm the stored PNG dimensions and transparency, and that both non-square landscapes and portraits retain a centered subject without distortion. No resize notification should appear. The editor's main dropdown must switch from `Original Character` to the **actual selected race** immediately after the popup, with `Species: <race> | Change portrait` visible below it; reopening the editor must keep the race displayed while retaining the OC image. Clicking Change portrait must reopen the picker even though the main dropdown now shows a race. The Character Book must remain visible, enabled and foregrounded on Confirm, Cancel, X and Escape (never minimize or drop behind the launcher). The cosmetic species prompt must never override the selected OC portrait on the actual login card. Save and test the same character from Play, quick launch and sequential login, then reopen the editor to confirm persistence. Test rejection (corrupt or unsupported image, too-large file or decoded dimensions), picker/race-dialog cancel restoring the previous selection, changing back to stock species, editing an existing OC through the clickable `Species: ... | Change portrait` hint, new-character Save, restart, and missing-file fallback. Preserve auto-reconnect, expansion-pack settings, old character compatibility and real race through the portable backup round-trip (the v1 INI export does not carry image bytes).
3. The first saved character must be automatically favorited and appear as the
   main-page quick-launch target, including after restart. Clicking that
   character's checked tick must not remove the only favorite. On the **first**
   switch attempt, a Yes/No explanation must appear with No as the default:
   No must leave both the old tick and persistent selection unchanged; Yes
   must move the checkmark to exactly one new character and immediately
   update the main-page quick-launch label. Both Yes and No acknowledge the
   explanation, so later switches happen without a repeated popup, even after
   restarting or restoring a backup. The Characters description uses the
   existing compact 390x95 block at (70,80), with the 24-pixel-spaced list
   beginning at y=180; do not add another text control or blank spacer.
   Verify restart persistence, a legacy list/portable backup with Selected=0,
   importing an existing selected character, deleting a nonfavorite,
   deleting the favorite with survivors, removing the final character, and
   per-row Play without altering the favorite.
4. Login timings, terminal-only startup, process loss and reconnect on/off. Confirm each saved species uses its corresponding bundled ICO, and each Original Character uses its private local portrait. Verify a missing OC picture falls back to the species icon and consecutive logins switch portraits correctly. Test the production four-step gold-bordered card, split heading and centered favicon/name, animated ellipses, blue active exclamations, green completed checks and three-second dismissal after password input. Verify focus and minimized/inactive hiding, queued batch/scheduled logins and a one-second saved LoadDelay.
5. Confirm Manage Characters no longer has a developer preview button; test the approved UI using a real login. Test Launch All & Close, its 10-second wait, cancellation of its explanation and saved suppression choice.
6. Installed Macros: on the right Character Book page, verify the exact
   empty-state text, and the same parchment-painted selectable buttons and
   labels as the left character list. The legacy ListView may remain hidden
   to preserve selection and process logic, but its opaque Windows table must
   never be visible. With zero, one, and five macros, controls follow the last
   row without large empty gaps; with six or more, Previous/Next page through
   all installed entries. Verify selected gold outline, active Run/Stop/Remove
   and Edit Keys, status updates, script/ZIP/EXE imports, and persistence after
   reopening/restarting. Editing characters must hide these controls until
   Save/Cancel; linked app removal never uninstalls it, and launcher exit does
   not terminate linked apps. The main menu has no standalone Macros entry.
   On first opening Manage Characters after launcher startup, verify that
   the character editor and macro panel are initialized in the correct order:
   no MacroList.GetNext() call may run on the zero integer placeholder.
   Verify close/reopen and editor Save/Cancel restore the panel cleanly.
7. Hover/press states, minimizing/restoring, dialogs and shutdown without artifacts or errors.
7. Saved settings survive replacement of the application folder.

Static checks alone do not validate Windows GUI behavior, game login acceptance or daily-point awards.

Patching release checks are listed in [PATCHING.md](PATCHING.md). Menu availability uses freshly verified runtime state, not a stored completion flag alone. The patch worker owns file mutations; the GUI only reads its progress/result files. Progress uses the existing buffered loading card with measured percentages.

## Collaboration tooling

Start with [ARCHITECTURE.md](ARCHITECTURE.md).
Run `python scripts/project.py check` for source/manifest checks and
`powershell -NoProfile -File scripts/check-powershell.ps1` for actual PowerShell
parser checks on Windows. The GitHub workflow runs both.
`python scripts/project.py package` builds a checked complete release ZIP.
The build number is defined once in `AppConfig.Build` in `src/state.ahk`.
See [RELEASING.md](RELEASING.md) for packaging and repository setup.
