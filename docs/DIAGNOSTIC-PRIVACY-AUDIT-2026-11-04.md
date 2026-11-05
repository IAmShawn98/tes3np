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

The cleaner deletes the private value and the empty field, then compacts separators. It does **not** emit `REDACTED`, `[path omitted]`, or other visible privacy notices. Public in-game **character names remain** in character-labeled fields. The Windows account name is removed from other diagnostic fields, including when it appears without a path. Useful event types, timestamps, step names and status codes are preserved where possible. A narrowly scoped one-time migration advances `PrivacyScrubVersion` to **3** and reprocesses older diagnostic logs, including legacy placeholders.

## Intentionally private application state (not a support log)

- `settings.ini` and DPAPI-protected profile credentials, portable character backup files, original character portraits, installed macros and any user-generated macro ZIPs
- `expansion-imports/*/journal.json`, staged package paths and rollback backups; these require real paths for transactional recovery. Do **not** paste the private journal into a public report.
- `Logs/game-chat.log` and `Logs/game-chat-index.json`: real Discord messages, author/snowflake IDs and attachment links. Required by authenticated chat history and Happy Hour detection, **never** processed by the diagnostic scrub or included in Copy Logs.
- `chat-webview2` Discord authentication/browser profile; do not upload or modify this as part of diagnostics
- Native TES3MP/OpenMW client logs outside TES3NP's own diagnostic boundaries are not automatically cleaned. Review them separately before sharing.

The picker must temporarily return an actual selected local path to the launcher. The importer must store real backup paths in its private journal. Those are functional data, not shareable diagnostics, and their handling is deliberately unchanged.

## Guardrails added or extended

- `scripts/check-diagnostic-privacy.py`: verifies the launcher, C# host, updater, importer, toggle worker, picker and GUI data boundaries; rejects omitted-field markers and raw exception sinks.
- `scripts/test-diagnostic-privacy.ahk`: disposable fake Windows username, password, email, URL, path, historical-placeholder and version-2-to-3 migration cases. Confirms a fake private Discord archive is unchanged and character names remain.
- `scripts/test-import-expansion-folder.ps1`: verifies the importer publishes result metadata without the disposable absolute job path or privacy placeholder, while keeping the atomic publisher and rollback journal.
- `scripts/build-windows.ps1`: already invokes the source guard and disposable AHK fixture as preflight gates; no GitHub Actions are needed.

## Outstanding Windows acceptance — not source work

1. Re-run `Build tes3np.bat` on the existing alpha branch. Record PowerShell parse, AHK fixture, C# preflight, Ahk2Exe compilation, ZIP integrity, importer and picker fixture results. The previous Ahk2Exe comment error was corrected but a successful full rebuild after these changes is still **unconfirmed**.
2. Open the newly built launcher with existing data. Confirm legacy diagnostic logs become clean, Copy Launcher Logs, Copy Expansion Pack Logs and Copy Render Errors contain no private values or empty labels, and the private chat archive and saved settings remain intact.
3. Exercise character login, macro import/run, Expansion Pack ZIP/folder import and toggle, native picker error paths, Game Chat and genuine Happy Hour detection. Check that error dialogs still explain failures.
4. Run the existing offline updater regression and examine safe updater events. Separate source checks from real package/runtime acceptance.
5. Only after acceptance should the public alpha/release checklist be considered.

**Release decision:** Source privacy changes are committed to `Update/v0.1.21-alpha` only. No release was published by the audit.
