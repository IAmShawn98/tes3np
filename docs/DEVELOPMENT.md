# Development guide

## Source map

| Path | Responsibility |
| --- | --- |
| `tes3np.ahk` | Explicit include order and application startup |
| `src/state.ahk` | Shared state, AppConfig defaults and paths initialized before startup |
| `src/app/bootstrap.ahk` | Startup, tray menu, icons and cleanup |
| `src/ui/renderer.ahk` | Native buffered drawing and GDI resource lifetime |
| `src/ui/windows.ahk` | Construction hiding and window reveal |
| `src/ui/front-page.ahk` | Main-page layout, descriptions and menu scrolling |
| `src/ui/controls.ahk` | Themed control builders, pointer states and event routing |
| `src/ui/actions.ahk` | Wiki and front-page actions |
| `src/ui/characters.ahk` | Character book, favorite selection and profile editor |
| `src/ui/macros.ahk` | Local macro library, import workflow and tracked script processes |
| `src/ui/patcher.ahk` | Setup gate, startup verification, patch UI and asynchronous progress |
| `scripts/import-expansion-pack.ps1` | Active ZIP/folder importer with verified file plans, backup and rollback; retired bundled Install/Repair removed |
| `patches/` | Legacy markerless client and its SHA-256 manifest |
| `src/game/expansion-mismatch.ahk` | Fresh TES3MP client log watcher and server plugin rejection dialog |
| `src/ui/expansion-upload.ahk` | Native ZIP/folder picker and import worker startup |
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

The Windows build script (`scripts/build-windows.ps1`, invoked by `Build tes3np.bat`) generates the compiled launcher and self-contained Chat Host in a complete `dist/tes3np-windows.zip` package. The Windows build checks source, Chat Host persistence and authentication contracts, PowerShell syntax, and C# compilation before downloading runtime tools. It replaces the previous build output after validating the new ZIP. Do not include user settings, logs, temporary files or developer credentials in a package. Public distribution remains blocked until the documented release evidence and explicit maintainer approval are complete.

Each compiled resource bundle extracts into its own `%APPDATA%\tes3np\resources\v-<content-hash>` directory instead of overwriting files used by an older launcher. This prevents cross-version `FileInstall` sharing violations when species artwork or other bundled assets change; short transient locks receive bounded retries. The build's `--check-resources` verification checks the version marker, required UI images, installed species ICOs and patch-manifest payloads before packaging. Existing roaming preferences, encrypted character passwords and the resources of already-running launchers are preserved. If extraction still fails, the error names the affected asset rather than silently launching with missing images.

Each Windows build stages downloaded tools in its own temporary directory. A temporary-file sharing violation during cleanup is retried and reported as a warning; once compilation, resources and ZIP integrity have passed, that cleanup issue must not prevent `Build tes3np.bat` from unpacking and publishing the new root executable. Actual compilation, validation or packaging failures still stop the build and must not launch an older executable. The operator should close the running launcher before rebuilding.

**Build SHA256 verification:** Three distinct integrity checks in `scripts/build-windows.ps1` (all extracted patch-manifest payloads, the official TES3MP archive, and the packaged markerless executable) use a streaming .NET SHA-256 helper rather than PowerShell's optional `Get-FileHash` cmdlet. Keep the expected-hash comparisons and fail-closed behavior. This addresses a Windows PowerShell 7.6.9 report where compilation succeeded but packaging stopped because `Get-FileHash` was not recognized. Windows confirmation of the next full package build remains pending.

The Launcher Settings → Launcher Data reset command stops Chat Host and recovery, deletes the shared Roaming AppData root, then exits without rewriting logs or settings during shutdown. A failed delete must be reported rather than claimed successful. Reset does not erase the game installation. Legacy Happy Hour marker files in Local AppData are now inert and are not imported by Chat Host.

## Embedded Discord ZIP in plugin-mismatch dialog

The main page retains the original **Expansion Pack: Enabled/Disabled** button. The **Plugins Don't Match the Server** dialog creates a native HWND placeholder that the existing ChatHost (same WebView2 environment/profile as Game Chat) populates using command `6`. The HTML overlay selects the latest visible ZIP by Discord message snowflake; it navigates neither the full browser nor the game files when clicked. A signed CDN HTTPS attachment URL is validated and opened by Windows Shell in the user's default browser via a worker task. The manual fallback channel link and existing OK → safe ZIP importer are preserved.

**November 1 freeze follow-up:** The prior iteration still locked the **TES3NP launcher** after the first download attempt. The user did NOT report restarting Windows, only restarting TES3NP. Source inspection exposed two remaining coupling points: `Run(url)` ShellExecute invoked on the launcher UI thread, and a visible, cross-process WebView2 child embedded in the mismatch dialog even after the signed URL had already been discovered. Preserve the original Discord ZIP discovery while replacing the on-screen card with an **AutoHotkey-owned hidden-until-ready clickable filename**. After validating sender PID + current placeholder + official signed ZIP attachment via bounded WM_COPYDATA, the AHK handler defers activation until the IPC reply returns, sends command `9` to hide the WebView, **also hides the AHK-owned placeholder Text HWND**, and explicitly raises/repaints the main file button. Windows feedback showed the main download button was unclickable while the separate Retry worked; the placeholder overlapping the button was the likely click interceptor. Both buttons now call the exact same request function, with separate diagnostic click-origin labels. Command `9` uses Win32 `ShowWindow(..., SW_HIDE)` on the existing embedded window, deliberately **not** `Dispose`, `SetParent`, or reinitialize; repeated downloads don't touch the browser lifecycle. Both the ZIP filename button and Download ZIP / Retry run a short-lived `rundll32.exe url.dll,FileProtocolHandler "<URL>"` subprocess, not direct `Run(url)`, so URL-handler work cannot block AHK's event loop. Keep the same original Discord session, latest-attachment selection, signed URL refresh, manual fallback, OK/Cancel importer and Enable/Disable toggle. **Mismatch diagnostics:** the expanded owned prompt adds **Copy Diagnostic Info** with the user's requested guidance. `TES3MPBuildSafeMismatchDiagnostics()` returns only a deliberately allowlisted report: launcher version, UTC report time, number of enabled OpenMW content entries, fixed built-in master/Expansion Pack flags, position/last/duplicate flag for NP Expansion Pack.esp, an optional installed-file presence check without a path, and Boolean indicators scanned from a bounded 64 KiB tail of the most recently modified TES3MP client log. No raw config lines, other plugin names, paths, usernames, account details, Discord data or signed URLs enter the report; clipboard contents contain only formatted static fields and counts. The existing broad `BuildLauncherDiagnostics()` and its path fields must NOT be used for this public bug-report button. The download status no longer displays **Starting Download...** or any persistent progress text; only copying the report gives a brief confirmation. User feedback before this UI change was that the combined download/main-button fix and architecture-check correction **seemed to work** on Windows; preserve the download handoff behavior. The new wording and status removal are visible on Windows, but the user screenshot confirmed that **Copy Diagnostic Info showed 'Could not copy diagnostic info.'** The original handler conflated two causes (report-builder error and post-assignment `ClipWait(1)` timeout). The revised handler now uses the already-established native `A_Clipboard := report` pattern without `ClipWait`; builds an allowlisted minimal report if optional config/log collection fails; retries a temporary locked clipboard with three timer-driven assignments; and logs only the error *type*, source line, and stage (never error messages that could contain filenames). It displays a distinct clipboard-busy message if even the retries fail. Windows clipboard verification is still outstanding. The existing downloading path is unchanged. Recheck compilation and window hierarchy, then run multiple download/cancel/retry cycles on Windows; still pending.

### Live client-log evidence capture (November 1)
Windows user supplied a report with valid four-entry configured load order (Morrowind, Tribunal, Bloodmoon, NP Expansion Pack last; ESP present), but **Client log check: Read error** and all server-rejection indicators Unknown. The active mismatch watcher already successfully opens the NEW TES3MP client log and reads the exact rejection before the failed game is terminated. Reopening the selected latest log later from the Copy button can fail while another process holds or rotates the file; the report cannot then differentiate causes. **Do not assume this was definitely a sharing violation** without a Windows error code. The watcher now classifies the actual triggering text immediately and keeps only fixed booleans/status in `TES3MPLastMismatchEvidence` (never raw log text). The report prefers those classifications and labels the evidence **Captured during failed login**. The existing bounded log-file reader remains as a fallback only when no live rejection is available; failures remain visible as Read error rather than being treated as clean results. `StartProfileSession` resets the cached classification for each new login, including batch launches. Isolated fixtures assert that captured classifications survive without a second log open and do not expose arbitrary mod names. The failed log read is a **diagnostic collection failure**, not evidence that the game installation is correct or incorrect. Windows runtime verification of the live capture is pending.

### Plugin-mismatch copy report — separating expansion vs other plugins
The mismatch popup's **Copy Diagnostic Info** now produces `TES3NP - Plugin Mismatch Diagnostics` without the redundant SAFE/Privacy lines. The UI reports only **Diagnostic Info Copied!**, or a clipboard error; unavailable checks are explained inside the copied report. `TES3MPAnalyzeMismatchConfig(configText)` and `TES3MPAnalyzeMismatchLogText(raw)` are pure testable functions. Configuration analysis counts enabled entries, Expansion Pack presence/position/last status, other plugin entries, duplicate other entries, and the three known base-game masters, without returning arbitrary names. The log analyzer confines classification to a bounded window around the most recent server plugin-mismatch rejection, distinguishing explicitly missing NP Expansion Pack, other named-extension plugins, base masters, unspecified missing dependencies, and *additional* ordering evidence. The rejection's generic "load order" phrase does **not** count as a separate order error.

The report identifies evidence pointing to Expansion Pack configuration, another plugin/base dependency, both, or insufficient information. It explicitly says the Expansion Pack version is **not verified**; no server manifest comparison exists. File-not-found, too-large, and read-error states are distinct from an actual negative finding; the exceptional minimal report says collection failed and never silently claims everything is fine. Only static allowlisted strings, numeric counts and fixed flags are copied. No raw config/log lines, unapproved mod filenames, user paths, account info, or signed Discord links are exported. There is no server-side transmission. Preserve this privacy contract and do not reuse broad launcher diagnostics here.

`scripts/test-expansion-diagnostics.ahk` contains isolated synthetic fixtures for Expansion Pack vs other missing plugins, duplicate other entries, absent config/logs, generic-order false positives, real order errors, master dependencies, no definitive cause, and secret redaction. The Windows build now runs those real AutoHotkey parser/report fixtures after extracting the interpreter and **fails packaging** if they fail. This is independent of the actual GUI clipboard/runtime test, which still requires Windows testing. The confirmed working ZIP download/retry code and existing Game Chat/Happy Hour architecture were not modified. **Windows warning regression (November 1):** The next user build reported `#Warn` for missing `PatchConfigurationPath` in the standalone fixture and `Return` making later report fields unreachable in the compiled launcher. The fixture now defines inert test-only launcher dependencies (never invoked), and `project.py` excludes those isolated stubs from production duplicate-function registration while still validating syntax/includes. The report renderer now appends all fields to a variable and returns only at the end; a new fixture assertion verifies both middle and last fields, so silent truncation fails the test. The Windows build captures fixture output and fails packaging even when AutoHotkey prints warnings but exits with code zero. Full Windows build/runtime revalidation is pending.

## Embedded Chat Host changes

`game-chat/Program.cs` starts the WinForms process owned by the AutoHotkey
launcher. The `GameChatWindow.*.cs` files group its feed, history, archive,
Discord session, Happy Hour, downloads, and launcher integration. Read
`docs/ARCHITECTURE.md` and `src/ui/embedded-chat.ahk` before changing ownership
or launcher messages.

Edit `game-chat/web/message-feed.html` for visible message layout, colors, and
scrolling. `web/extract-feed.js` reads the Discord DOM, and `DiscordFeedReader.cs`
turns that data into C# message rows. `web/discord-sign-in.js` styles the sign-in
form. The build embeds the files under `web/`. The editable `game-chat/chat.css`
styles the Discord source page, and the Windows package keeps the installed
`chat-host/tes3np.ChatHost.exe`, `chat.css`, and `chat.ini` paths for existing
updaters and user settings.

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
   `dotnet build game-chat/tes3np.GameChat.csproj -c Release -r win-x64 --no-self-contained`.
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

Use the [Windows acceptance checklist](ALPHA-COMPATIBILITY-CHECKLIST.md)
for interactive testing on the extracted build. Record the tested ZIP and
outcomes there or in the corresponding release evidence. The automated
source, packaging, and updater checks are available through the local
regression runner below.

## Collaboration tooling

Start with [ARCHITECTURE.md](ARCHITECTURE.md).
Run `python scripts/project.py check` for source/manifest checks and
`powershell -NoProfile -File scripts/check-powershell.ps1` for actual PowerShell
parser checks on Windows. The GitHub workflow runs both.
`Build tes3np.bat` builds the Windows ZIP. The launcher version is defined
in `AppConfig.Version` in `src/state.ahk`.
See [RELEASING.md](RELEASING.md) for packaging and repository setup.

### Local Windows regression without GitHub Actions

From an existing `Update/v0.1.21-alpha` checkout, run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-local-regression.ps1` to build the launcher, run its existing source/Chat Host/synthetic Expansion Pack checks, run the additional isolated updater client/metadata/rollback fixtures, and launch the built executable. The BAT build pauses at its normal confirmation prompt. PowerShell 7 (`pwsh.exe`) is required by the updater transaction fixture. The runner refuses to claim a complete offline pass if it is missing. Use `-SkipBuild` to rerun the updater fixtures against an already successful build and `-NoLaunch` to avoid opening the UI.

The runner uses only the repository build output and synthetic temporary files; it does **not** edit the player's Morrowind installation, perform an Expansion Pack downgrade or launch GitHub Actions. Human verification of characters, Game Chat, Happy Hour, file import and live server login remains outstanding until someone runs the interactive checklist.
