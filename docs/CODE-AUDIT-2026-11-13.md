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

- PowerShell syntax and updater source/metadata fixtures passed. Seven
  isolated updater transaction scenarios passed in PowerShell 7, including
  an in-place Chat Host asset update and restoration of the old asset during
  rollback. The fixtures do not execute a Windows launcher.
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
5. Assess overlapping update attempts across installs and an interrupted
   updater before release. The normal launcher uses a shared per-user
   staging/state path and the published v0.1.20-alpha worker remains
   embedded in that installation. The corrected worker must be used in the
   private transaction test to exercise the changes made here.
