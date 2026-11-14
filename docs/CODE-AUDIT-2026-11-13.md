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
- ZIP validation rejects ambiguous Windows paths, links and file/directory
  conflicts. Corrected outdated build commands in the development guide.


## Fifth source pass

- Expansion Pack imports verify the previous contents immediately before
  replacing game files and OpenMW config. Rollback checks that the installed
  copy still belongs to the import before restoring or deleting it.
- Import journals are published atomically. A successful import stays
  committed if its final status file cannot be written. New jobs use unique
  folders, and a reused folder keeps its existing backups and journal.
- Chat archive writes remain pending after transient failures and retry
  even on an unchanged feed. Failed rendering can retry the same snapshot.
  Removed a no-op frame hook and released GDI regions when Windows rejects
  a clip update. Launcher shutdown asks its own Chat Host to close and flush
  before falling back to termination.
- Disposable tests passed for a real ESP import, a reused job directory,
  a config edit during install, and a final status write failure. An
  isolated archive test exercised a failed write and the eventual retry.
  Full Windows import, WebView2 and launcher tests remain pending.

## Sixth source pass

- Macro ZIPs are validated before extraction, including Windows filename
  conflicts and launcher-owned marker names. Extracted files must match
  their declared sizes. The package list skips unfinished import folders.
- Macro ZIP extraction tracks the worker's process handle. Timeout and
  shutdown request termination and wait before removing staging. Linked
  applications publish their registration after writing all metadata.
- Expansion Pack progress reads tolerate a transient status file error.
  The launcher also releases the import handle during shutdown.
- Eleven disposable macro ZIP fixtures passed, covering a valid nested
  Unicode package, rejected paths and metadata, preservation of a nonempty
  staging folder, and rejection of a size mismatch. Source contracts and
  the updater transaction fixtures passed again. Native macro UI, timeout
  and launcher shutdown remain Windows runtime checks.

## Seventh source pass

- Failed character saves discard the newly generated portrait. Imported v1
  profiles have the same portrait field as locally created profiles. The
  exporter retains the executable field for older readers, while import
  preserves the destination PC's active client settings.
- The updater retries a temporarily unreadable startup confirmation,
  checks its version, and uses the launched process handle during rollback.
  Recovery validates the full journal before deleting staged additions.
- The resource generator includes the runtime artwork, font license,
  species icons and workers explicitly. The release ZIP checker rejects
  extra root entries. A reference scan covered all 395 launcher declarations,
  including UI callbacks referenced by name, and found no unreferenced
  function declarations.
- Twelve updater transaction fixtures passed, including invalid-journal
  recovery. Resource generation passed against a disposable source fixture.
  The packaged Windows build and full runtime checklist remain pending.

## Eighth source pass

The GitHub tree for `b877b1d` listed 128 tracked files. The 125 local
files matched GitHub blob IDs before edits. The launcher background, Discord
sign-in emblem, and tracked markerless EXE were available as tree entries only.

- Removed Chat Host's unused companion toggle, hidden frame controls, old
  header texture and ineffective X/Y preferences. The launcher-owned Game
  Chat tab and Chat Host's live frame and scrollbar still have their callers.
- A reopened Expansion dialog can initialize its own WebView while a closed
  one finishes. ZIP messages are accepted from the current browser and the
  configured channel. Shutdown disposes timers, textures and sign-in UI.
- Build validation now bounds resource extraction and compiler smoke waits.
  The build pins the official TES3MP archive for both client variants and
  omits upstream server, editor and import tools from the launcher ZIP.
- The markerless console rebuild takes an explicit build ID and directs the
  developer to the matching dependencies. PowerShell syntax checks now
  include the markerless research scripts.
- Source contracts, six embedded JavaScript bodies, C# and PowerShell syntax,
  workflow YAML, the compiler wrapper fixture, the upstream archive selection,
  and twelve updater transaction fixtures passed. The release gate remains
  blocked on the existing provenance, asset approval and clean Windows evidence.

### File coverage through pass eleven

“Source inspected” records a source read-through. Targeted review and
reference checks cover selected behavior and call sites. Later passes below
record the exact additional coverage and the remaining source work. Windows
compilation and GUI execution are still pending.

| File | Coverage |
| --- | --- |
| `.editorconfig` | Inventory and dependency check |
| `.gitattributes` | Inventory and dependency check |
| `.github/workflows/build-windows.yml` | Workflow read and YAML parsed |
| `.github/workflows/checks.yml` | Workflow read and YAML parsed |
| `.github/workflows/publish-alpha.yml` | Workflow read and YAML parsed |
| `.gitignore` | Inventory and dependency check |
| `Build tes3np.bat` | Source inspected |
| `chat-host/Program.cs` | Source inspected |
| `chat-host/assets/DiscordInt.png` | GitHub tree only |
| `chat-host/border-texture.b64` | Runtime reference verified |
| `chat-host/chat.css` | Source inspected and runtime reader verified |
| `chat-host/chat.ini` | Source inspected |
| `chat-host/header-texture.b64` | Removed with unused header |
| `chat-host/scrollbar-texture.b64` | Runtime reference verified |
| `chat-host/tes3np.ChatHost.csproj` | Source inspected |
| `patches/manifest.json` | Source inspected |
| `patches/markerless/tes3mp.exe` | GitHub tree only |
| `research/markerless/README.md` | Inventory and dependency check |
| `research/markerless/Restore-Markerless-Console.ps1` | Source inspected |
| `research/markerless/build-markerless.ps1` | Source inspected |
| `research/markerless/console-candidate.json` | Source inspected |
| `research/markerless/tes3mp-0.8.1-markerless-experimental.patch` | Source inspected |
| `research/markerless/tes3mp-release-console.patch` | Source inspected |
| `scripts/audit-local-privacy.py` | Source inspected |
| `scripts/build-windows.ps1` | Source inspected |
| `scripts/check-ahk-compile.ps1` | Source inspected |
| `scripts/check-chat-architecture.py` | Source inspected |
| `scripts/check-diagnostic-privacy.py` | Source inspected |
| `scripts/check-powershell.ps1` | Source inspected |
| `scripts/check-release-gates.py` | Source inspected |
| `scripts/check-windows-package.py` | Source inspected |
| `scripts/fetch-release-notes.ps1` | Source inspected |
| `scripts/generate-bundled-resources.py` | Source inspected |
| `scripts/generate-update-metadata.ps1` | Source inspected |
| `scripts/import-expansion-pack.ps1` | Prior targeted review or fixture checks |
| `scripts/import-macro.ps1` | Source inspected |
| `scripts/project.py` | Source inspected |
| `scripts/run-local-regression.ps1` | Source inspected |
| `scripts/select-expansion-package.ps1` | Targeted review and source checks |
| `scripts/stage-markerless-console.ps1` | Source inspected |
| `scripts/tes3np-updater.ps1` | Source inspected |
| `scripts/test-diagnostic-privacy.ahk` | Prior targeted review or fixture checks |
| `scripts/test-expansion-diagnostics.ahk` | Prior targeted review or fixture checks |
| `scripts/test-expansion-toggle.ps1` | Prior targeted review or fixture checks |
| `scripts/test-import-expansion-folder.ps1` | Prior targeted review or fixture checks |
| `scripts/test-update-client.ps1` | Prior targeted review or fixture checks |
| `scripts/test-update-metadata.ps1` | Prior targeted review or fixture checks |
| `scripts/test-updater-transaction.ps1` | Prior targeted review or fixture checks |
| `scripts/toggle-expansion-pack.ps1` | Source inspected |
| `src/app/bootstrap.ahk` | Source inspected |
| `src/app/client-detection.ahk` | Source inspected |
| `src/app/diagnostics.ahk` | Source inspected |
| `src/app/update-check.ahk` | Prior targeted review and reference checks |
| `src/data/backup.ahk` | Source inspected |
| `src/data/cleanup.ahk` | Source inspected |
| `src/data/settings.ahk` | Source inspected |
| `src/game/expansion-mismatch.ahk` | Targeted review and source checks |
| `src/game/session.ahk` | Source inspected |
| `src/state.ahk` | Source inspected |
| `src/ui/actions.ahk` | Source inspected |
| `src/ui/characters.ahk` | Prior targeted review and reference checks |
| `src/ui/controls.ahk` | Source inspected |
| `src/ui/embedded-chat.ahk` | Source inspected |
| `src/ui/expansion-upload.ahk` | Prior targeted review and reference checks |
| `src/ui/front-page.ahk` | Source inspected |
| `src/ui/happy-hour.ahk` | Source inspected |
| `src/ui/launcher-settings.ahk` | Source inspected |
| `src/ui/loading.ahk` | Source inspected |
| `src/ui/login-progress.ahk` | Source inspected |
| `src/ui/macros.ahk` | Prior targeted review and reference checks |
| `src/ui/patcher.ahk` | Prior targeted review and reference checks |
| `src/ui/renderer.ahk` | Source inspected |
| `src/ui/v016-refinements.ahk` | Source inspected |
| `src/ui/windows.ahk` | Source inspected |
| `tes3np.ahk` | Prior targeted review and reference checks |

The remaining tree entries are artwork and fonts under `assets/`, release
and historical Markdown, and GitHub templates. Runtime asset selection was
checked in pass seven. The unmodified binary assets were inventoried by Git
identity. The audit does not include upstream TES3MP source files outside
this repository.

## Ninth source pass

- Read the window scaling, GDI renderer, themed input, loading overlay,
  and front-page modules. Scaled dialogs now release their generated fonts
  after destruction. The themed control subclass unregisters controls when
  Windows destroys their HWNDs through the parent window.
- Partial loading-card construction releases its windows and controls.
  Failed capture logging cannot interrupt bitmap cleanup. The Expansion
  Pack retry clears a failed frame and delayed callbacks retain the dialog
  or slot they were scheduled for. ZIP URL refreshes during a download
  leave the current progress display in place.
- The live plugin-mismatch watcher retains carry text per client log and
  updates its read position after a successful read. A Windows fixture
  covers split rejection text in one file and fragments in separate files.
- The Windows owned-menu smoke fixture now checks that generated font
  handles are freed when the child window closes. Both new Windows cases
  remain pending. Continue the behavioral read-through of the remaining
  AutoHotkey settings, login and expansion diagnostics code and the larger
  validation scripts before the dev-PC handoff.

## Tenth source pass

- Read the display and accessibility settings, Game Client Settings and
  diagnostics dialogs, login progress card, and game-session watchdog.
  Display settings now commit as one INI replacement and restore the
  preview when saving fails. Windows accessibility overrides are applied
  at runtime without being written back as the user's explicit choice.
- The watchdog rechecks session ownership after dialogs and checks the
  active window and PID before credential input. Login progress releases
  a partially constructed window and stops polling after dismissal.
  Settings caption dragging handles monitors with negative coordinates.
- Reviewed the Expansion Pack diagnostic evidence, fingerprint and
  clipboard paths. A clipboard retry remains scoped to its own dialog.
  The local privacy scanner preserves legacy status-file line endings,
  and updater fixtures route their diagnostics to disposable AppData.
- Coverage added for `src/ui/launcher-settings.ahk`,
  `src/ui/v016-refinements.ahk`, `src/ui/login-progress.ahk`,
  `src/game/session.ahk`, the diagnostic functions in
  `src/game/expansion-mismatch.ahk`, `scripts/audit-local-privacy.py`, and
  `scripts/check-diagnostic-privacy.py`. The larger source-contract scripts
  still need a complete review and reconciliation against this inventory.

## Eleventh source pass

- Source-contract checks now report the affected invariant when a guarded
  statement or section disappears. The Chat Host checks read each repeated
  source dependency once and no longer use a character offset to test when
  the Happy Hour clock initializes. Launcher and privacy checks also report
  missing ordered statements by name.
- The package check rejects a directory where a required file should be
  and reports a missing required markerless client manifest directly.
- Reconciled the local baseline against private commit `bb7b40f`. All 124
  local tracked files match their GitHub blob IDs. The remote tree has 127
  files, including the launcher background, Discord emblem and markerless
  EXE that are absent locally. The exact binary payload hash and Windows
  package validation remain pending.
- Source checks, five disposable missing-fragment cases, four synthetic
  ZIP cases, PowerShell parsing, update metadata and twelve updater
  transaction fixtures passed. The source-check run used GitHub tree
  evidence for launcher background presence. The ZIP fixture used a
  synthetic manifest and executable bytes.
- Remaining read-throughs include the launcher entry and update UI, Character
  Book and macro UI, the rest of Expansion Pack coordination and workers,
  and the fixtures still marked targeted in the table. Inventory coverage
  now spans the entire Git tree. The line-by-line audit remains open.
  The dev-PC build follows source sign-off, and the second-PC upgrade
  follows a passing dev-PC run.
