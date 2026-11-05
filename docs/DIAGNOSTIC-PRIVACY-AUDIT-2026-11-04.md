# TES3NP diagnostic privacy audit — November 4, 2026

**Status: Source-side privacy cleanup complete; Windows build and runtime acceptance pending. Not release-approved.**

This audit covers the current `Update/v0.1.21-alpha` code. The goal is to keep shareable diagnostics useful without printing personal Windows details or visible privacy placeholders. It is **not** a claim that a fresh Windows package or a live game session has been tested after these commits.

## Shareable diagnostics and their write/read boundaries

| Output | Responsible source | Privacy boundary |
| --- | --- | --- |
| `%APPDATA%/tes3np/launcher.log` | `src/app/diagnostics.ahk` | `LogLauncherEvent` cleans on write; patch mirror cleans again |
| `chat-host.log` | `chat-host/Program.cs` | Independent `Log` filter removes paths, usernames, credentials, URLs, emails and identifiers |
| `patch-all.log`, `patch-errors.log` | `src/ui/patcher.ahk` | Shared cleaner at write boundary; clipboard exports cleaned again |
| `render-errors.log` | `src/ui/loading.ahk` | Error type only, no raw exception message |
| Updater lines in `launcher.log` | `scripts/tes3np-updater.ps1` | Independent worker-side filter; console failures no longer echo raw exceptions |
| Expansion Pack import `result.ini` | `scripts/import-expansion-pack.ps1` | Clean error message before atomic result publish; the existing `Backup` field is a non-sensitive availability indicator, not an absolute path |
| Expansion toggle `expansion-toggle-result.txt` | `scripts/toggle-expansion-pack.ps1` | Clean exceptions before saving results; launcher filters again before displaying |
| Native ZIP/folder picker `.error` | `scripts/select-expansion-package.ps1` | Exception type and HRESULT only, not raw exception text; launcher filters dialogs |
| Macro import `.import-error` | `scripts/import-macro.ps1` | Allowlisted static errors or exception type; macro GUI uses shared cleaner |
| Copied Launcher, Expansion Pack and Render logs | `src/ui/v016-refinements.ahk` | Sanitize before clipboard; Windows crash-event text is not exported |

The cleaner deletes the private value and the empty field, then compacts separators. It does **not** emit `REDACTED`, `[path omitted]`, or other visible privacy notices. Public in-game **character names remain** in character-labeled fields. The Windows account name is removed from other diagnostic fields, including when it appears without a path. Useful event types, timestamps, step names and status codes are preserved where possible. A narrowly scoped one-time migration now advances `PrivacyScrubVersion` to **4** and reprocesses older diagnostic logs, including legacy placeholders and joined timestamp boundaries. It restores a trailing newline on persisted diagnostics so later events stay separate.

## Intentionally private application state (not a support log)

- `settings.ini` and DPAPI-protected profile credentials, portable character backup files, original character portraits, installed macros and any user-generated macro ZIPs
- `expansion-imports/*/journal.json`, staged package paths and rollback backups; these require real paths for transactional recovery. Do **not** paste the private journal into a public report.
- `Logs/game-chat.log` and `Logs/game-chat-index.json`: real Discord messages, author/snowflake IDs and attachment links. Required by authenticated chat history and Happy Hour detection, **never** processed by the diagnostic scrub or included in Copy Logs.
- `chat-webview2` Discord authentication/browser profile; do not upload or modify this as part of diagnostics
- Native TES3MP/OpenMW client logs outside TES3NP's own diagnostic boundaries are not automatically cleaned. Review them separately before sharing.

The picker must temporarily return an actual selected local path to the launcher. The importer must store real backup paths in its private journal. Those are functional data, not shareable diagnostics, and their handling is deliberately unchanged.

## Guardrails added or extended

- `scripts/check-diagnostic-privacy.py`: verifies the launcher, C# host, updater, importer, toggle worker, picker and GUI data boundaries; rejects omitted-field markers and raw exception sinks.
- `scripts/test-diagnostic-privacy.ahk`: disposable fake Windows username, password, email, URL, path, historical-placeholder, version-3-to-4 migration and newline-boundary cases. Confirms a fake private Discord archive is unchanged and character names remain.
- `scripts/test-import-expansion-folder.ps1`: verifies the importer publishes result metadata without the disposable absolute job path or privacy placeholder, while keeping the atomic publisher and rollback journal.
- `scripts/build-windows.ps1`: already invokes the source guard and disposable AHK fixture as preflight gates; no GitHub Actions are needed.

## Uploaded Launcher Log acceptance — November 5

- The user reported the PowerShell build/launch succeeded before the latest formatting follow-up. A build transcript was not attached.
- Three Copy Launcher Logs uploads were byte-identical, each containing 2,711 lines. Their inspected content did not expose raw Windows user paths, URLs, emails, IP addresses, token/password labels, Discord snowflake identifiers or privacy-placeholder clutter; useful game events and character names survived.
- **Formatting defect detected:** two historical entries were concatenated to their following timestamps. The v3 migration had written sanitized text without preserving the terminal newline. The new v4 cleanup repairs this narrow old pattern and guarantees a terminal newline when persisting logs; the first launcher log append also handles a pre-existing file missing its terminator.
- **Not yet reverified:** the v4 formatting repair needs a fresh Windows build and new copied log. The three uploads are Launcher Log copies, not evidence that `chat-host.log`, patch worker result files or direct game/chat operations passed.

## Verified Windows build and Launcher Log — November 5

- The user supplied a complete `git pull --ff-only` and `Build tes3np.bat` transcript for alpha HEAD `24a2359`, followed by `Start-Process .\\tes3np.exe`. PowerShell helper parsing, source/manifest checks, privacy source guard, disposable diagnostic privacy and plugin-mismatch AutoHotkey fixtures, importer ZIP/folder regression, native picker COM fixture, C# Chat Host publish, Ahk2Exe smoke and final launcher compilation, launcher `--check`, runtime and asset SHA checks, and downloadable ZIP integrity **all passed**. The recurring WindowsBase MSB3277 warning was nonfatal. The user did not provide an independent extracted-ZIP interactive test.
- Fresh Copy Launcher Logs report: **2,720 total lines** (seven report header lines and **2,713 timestamped launcher event lines**). Every event starts with a normal timestamp, including the two previously concatenated entries. Scan found **zero** merged timestamps, placeholder tokens, stray empty delimiters, Windows absolute or UNC paths, user-directory environment roots, URLs, emails, IPv4 literals, long Discord-like IDs, or password/token/secret fields. Public character names, status codes and timelines remained.
- **Accepted:** v4 compile/build checkpoints, fixture execution, downloadable ZIP packaging and copied Launcher Log privacy and line formatting. **Still pending:** direct inspection of Chat Host/Expansion Pack/render logs, private-data non-mutation checks and real-game feature regressions. Clipboard output does not independently prove the on-disk trailing newline, but event separation passed.

## Read-only secondary-log and updater readiness utility — November 5

A new `scripts/audit-local-privacy.py` provides one privacy-preserving local audit without rebuilding the launcher. Run `python scripts/audit-local-privacy.py` from the checked-out repository in Windows PowerShell. It scans the local launcher, Chat Host, Expansion Pack, render and Windows crash-query diagnostic files, plus up to 30 importer `result.ini` records. It checks paths, account names, credentials, IPs, contact/URL patterns, IDs, placeholders, empty separators, launcher timestamps, the persisted terminal newline, and private backup paths in the importer result metadata.

**The utility prints only filenames, counts, category labels, and PASS/REVIEW/SKIP statuses**; it never prints log lines, character details, user paths or secret values, and never reads or modifies `settings.ini` or the private Discord message archive. Missing optional logs are SKIP, **not** evidence they passed. The tool invokes existing updater source/version, metadata/tamper and transaction/rollback fixtures using disposable data. If PowerShell 7 is absent, the transaction fixture is explicitly skipped; no real updater is launched. A standalone synthetic scanner self-test passed in this environment; real Windows run is pending.

The tool does **not** claim actual saved-data preservation before the prior migration, a tested live login, real Happy Hour retrieval, macro execution, completed import/toggle interactions or a clean-machine extracted-ZIP launch. These remain interactive acceptance tasks.

## Actual local privacy audit and legacy importer follow-up — November 5

The user ran `python scripts/audit-local-privacy.py` on Windows after pulling `8c498d1`:

- **PASS:** `launcher.log` (2,714 lines), `chat-host.log` (11,255 lines), `tes3mp-crash-query.txt` (one line); no flagged patterns. On-disk Launcher Log final-newline verification also passed.
- **PASS:** isolated updater source/version, metadata/tamper, and transaction/rollback fixtures. No missing PowerShell runtime or fixture failures.
- **SKIP (not a pass):** absent patch-all, patch-errors, render-errors, and expansion-toggle-result files.
- **REVIEW:** one of four historical `expansion-imports/*/result.ini` files exposed a legacy absolute Windows path, account name and old `Backup=` absolute-path value. The four files had 16 lines total. All three findings appear to concern the same legacy field; this inference has not been confirmed by inspecting its raw contents, and **raw results must not be shared**.
- **Present only (not verified unchanged):** settings.ini, game-chat.log and game-chat-index.json, 3/3. Their contents were deliberately never inspected.

The *current* importer already writes a clean status and does not publish rollback locations. To address **historical** results, the audit script now exposes the explicit `--repair-legacy-import-results` option. Default audit remains read-only. The opt-in repair only considers completed `[Result]` records with `State=success/error`, at least ten minutes old, smaller than 1 MiB, in direct child job folders (no symlinks); it preserves the format/encoding, maintains a safe message and `State`, converts `Backup` to `available` only when a sibling journal exists, checks for changed files before atomically replacing **result.ini only**, and never opens, alters or deletes rollback journal, backup, settings, game files, or Discord history. This targeted fix includes a synthetic UTF-16 status/journal non-mutation regression test.

**Pending user confirmation:** run `python scripts/audit-local-privacy.py --self-test`, then `python scripts/audit-local-privacy.py --repair-legacy-import-results --skip-updater`, and confirm the historical results pass. The Windows run of this new command is not yet verified; do not mark the import-result finding closed prematurely.



## Outstanding Windows acceptance — not source work

1. **Completed November 5:** Full Windows build and all reported compiler, source-check, fixtures and packaged ZIP gates passed on alpha HEAD `24a2359`. An independent extracted-ZIP interactive run is still pending.
2. **Launcher Log copy passed November 5.** Confirm separate Chat Host, Expansion Pack and Render Logs have no private values or empty labels; verify the private chat archive and saved settings remain intact.
3. Exercise character login, macro import/run, Expansion Pack ZIP/folder import and toggle, native picker error paths, Game Chat and genuine Happy Hour detection. Check that error dialogs still explain failures.
4. Run the existing offline updater regression and examine safe updater events. Separate source checks from real package/runtime acceptance.
5. Only after acceptance should the public alpha/release checklist be considered.

**Release decision:** Source privacy changes are committed to `Update/v0.1.21-alpha` only. No release was published by the audit.
