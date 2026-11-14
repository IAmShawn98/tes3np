# TES3NP alpha source audit — November 13, 2026

Baseline: `8ec10f1` on `Update/v0.1.21-alpha`. The public updater still
serves v0.1.20-alpha. The source snapshot was checked against the private
GitHub tree before changes.

| Area | Findings and changes |
| --- | --- |
| Launcher entry, startup and native UI | Removed the unused legacy TES3MP install scanner and completion flag, the duplicate profile load and menu repaint, an unused menu handle, a no-op Chat Host resize callback, and a hidden game-status control. The login overlay still has its stage callbacks and presentation timer. |
| Characters, backups and sessions | Removed the reconnect checkbox and unused per-character Expansion Pack preference. Automatic restart was already retired in `0bc3521`. V1 exports retain the legacy reconnect field with value `0` for older readers. The importer accepts older backups and ignores that field. |
| Custom client | The legacy custom EXE cache now incorporates the source file's SHA-256 and verifies the staged copy before marking it ready. This handles replacements with an identical size and timestamp. |
| Updater and packaging | Confirmation follows resource extraction and the main launcher startup. The worker quotes the state path, launches from the install directory, merges Chat Host folders at their actual destinations, and uses a separate rollback backup per attempt. Rollback can proceed if the updater cannot write its status file. |
| Chat Host | Removed the disabled expired Happy Hour preview and its alternate history window. Active-event detection still uses the original Discord timestamp, the offline archive, and the existing live history path. |
| Expansion Pack, macros and resources | Checked the installed-only toggle, shared importer, picker, macro worker and resource bundling entry points. The corresponding Windows checks below are still required. |

## Verification

- PowerShell syntax and updater source/metadata fixtures passed. Eleven
  isolated updater transaction scenarios passed in PowerShell 7, including
  an in-place Chat Host asset update and restoration of the old asset during
  rollback, file/directory collision, overlapping workers, preservation of an
  unrelated recovery directory, and startup recovery without staging. The
  fixtures do not execute a Windows launcher.
- Diagnostic privacy contracts and synthetic scanner tests passed. Roslyn
  parsed the C# source without syntax diagnostics. Windows build,
  dependency resolution and WebView2 behavior remain pending.
- The local source snapshot lacks the exact launcher background, Discord
  emblem and tracked markerless EXE. The GitHub tree lists them. The source and
  Chat Host contracts passed with the background presence verified from
  the GitHub tree. Local asset validation and the payload hash remain
  pending. The release gate still requires its three evidence files.

## Pending Windows checks

1. Build the packaged candidate with the verified markerless EXE and matching
   DLLs. Confirm the launcher and Chat Host compile and ZIP validation passes.
2. Check character edit layout, legacy backup import, login overlay and the
   four-client limit. Replace a legacy custom executable with a different
   file of the same length and timestamp and confirm the new copy is used.
3. Check live and archived Happy Hour through expiry, Game Chat sign-in,
   macro import/run, and Expansion Pack toggle and ZIP/folder import.
4. On the isolated second-PC install, exercise the actual public
   v0.1.20-alpha package and the staged v0.1.21-alpha update. Verify the
   restart and retained user settings, including a path with spaces. Check
   failure before launcher confirmation restores the previous version.
5. Verify compiled startup recovery after interrupting the updater in a
   disposable install. The published v0.1.20-alpha worker remains embedded
   in that release, so validate the offline corrected worker and the legacy
   handoff separately.

## Second source pass

- Each download stages in a unique directory. An installation-scoped mutex
  serializes workers. A recovery journal persists beside the install and
  can restore the previous package after the download directory is gone.
  The packaged launcher can invoke recovery on startup.
- Character list writes stage a copy of the settings INI before committing.
  Failed saves restore the prior in-memory list, favorite, and page. Backup
  import preserves unrelated local settings. Legacy profile holes retain
  the saved favorite by original slot.
- Chat image reads have a byte limit and a response-body timeout. An
  unreadable chat text archive can retry before being rewritten. Closing the
  host disposes the cached image previews and the Happy Hour timer.
- Macro extraction disposes both streams if a file cannot be created.
  Stop feedback reports failure when Windows cannot close the process.
- Windows packaging builds and verifies the new ZIP before replacing the
  previous dist output. Morrowind discovery checks secondary libraries from
  the registered Steam installation as well as the default locations.
- Expansion Pack import carries only the active worker state and avoids
  rebuilding the unrelated character menu after an import.

## Third source pass

- Expansion Pack toggle reads its real worker exit status and acts on the
  selected OpenMW configuration. The verified ESP still determines the
  enabled indicator. Removed the write-only global flag.
- Expansion Pack error details use the common sanitizer. Existing diagnostic
  files remain readable, while the launcher records current import failures
  directly instead of mirroring the obsolete patch log.
- OpenMW config read failures leave Morrowind discovery able to check the
  registry and Steam libraries. Release-note fetches use the system Windows
  PowerShell path.
- Removed the duplicate loading-overlay predicate and a first-run flag
  with no readers. File hash checks require certutil to exit successfully.
- The dev PC build remains deferred while the source audit continues.
  The second PC upgrade test follows a passing dev PC regression run.


## Fourth source pass

- Game counting now retains a process handle when TES3MP starts, including
  clients whose login monitor is stopped before the SDL window opens.
  Stopping the monitor releases its copy of the saved credentials. Stale
  focus waits no longer continue a cancelled or replaced login.
- Macro Run and Stop keep a handle for the launched instance, including
  when the character book is rebuilt. Launcher shutdown closes tracked
  script processes and leaves linked apps running.
- Custom-client cache hits check the stored signature and retain existing
  caches that a running game could be using. A new override selection first
  recovers a prior interrupted override swap.
- The compiler wrapper enforces its requested timeout and captures each
  process's output independently. Disposable PowerShell checks passed for
  compiler success, failure output, timeout and build-output rollback.
- The Expansion Pack toggle uses a unique staging file and checks that
  OpenMW settings are still current before replacing them.
- The batch build passes its ZIP and extraction paths through environment
  variables so apostrophes in the checkout path do not break PowerShell.
