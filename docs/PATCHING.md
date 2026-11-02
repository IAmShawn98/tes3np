# TES3NP — Expansion Pack import and recovery

## Active workflow

TES3NP includes its own TES3MP client. The NP Expansion Pack is optional and can be enabled or disabled with the launcher’s Expansion Pack control. The first-run Morrowind GOTY folder picker remains separate and does not install expansion files.

When the server reports that plugins or load order do not match, the launcher offers the existing **Upload Expansion** action. Choose a current NP ZIP or extracted folder obtained from the official server community. The chooser and importer do not automatically download files or authenticate the package against the server.

The active worker, scripts/import-expansion-pack.ps1, stages the selected archive or folder, validates allowed Data Files paths, hashes staged files, checks disk space, verifies Morrowind/Tribunal/Bloodmoon requirements, updates the selected active openmw.cfg, backs up files to be changed and uses atomic replacements with rollback on failure. It preserves unrelated mod files, the bundled TES3MP executable, character credentials and launcher settings. Only connection to the NP server can confirm compatibility.

## Retired bundled installer

The former **Install / Repair**, **Verify**, and **Restore Backup** panel was retired on 2026-11-02. Its tray entry, AutoHotkey callbacks and scripts/patch-tes3mp.ps1 worker are removed. Nothing routes into the bundled v0.1 installer, so a user-installed v0.2 Expansion Pack cannot be downgraded through that obsolete operation. Older bundled patch resources remain in the repository because source packaging and manifest integrity validation still reference them; their presence does not authorize copying them into a player's game.

Do not treat the old bundled manifest as a current installed-version check. The local enable/disable control reads the active OpenMW configuration, while the server's response remains the definitive compatibility test.

## Backups and errors

The current importer stores its completed backup journal and original changed files under %APPDATA%\tes3np\expansion-imports. It attempts rollback if an import fails and preserves the journal for later manual recovery. The retired **Restore Backup** button is not a recovery path for these newer imports. Do not delete or overwrite backup journals or test recovery against a real Morrowind install; use a disposable copy.

Progress and results are written atomically to the import job directory and displayed through the existing launcher loading overlay. Errors retain a bounded step description. Persistent Windows sharing locks, insufficient disk space, invalid archives or unsafe paths fail without intentionally replacing unrelated data.

## Windows validation (without GitHub Actions)

1. Run the existing local source/build preflight, including PowerShell parsing, Python source and chat checks and the synthetic ZIP/folder import fixture.
2. Confirm the launcher has no Install / Repair, Verify, Restore Backup panel or legacy tray entry. The Morrowind discovery prompt and Expansion Pack enable/disable control must still work.
3. Import a synthetic ZIP and folder into a disposable game installation; compare existing files, unrelated mods and config entries, backup journals and rollback outcomes. Never use the working v0.2 install as a disposable test.
4. Open the real launcher and check Manage Characters, first-character favorite, macros, game-client selection, Enhanced Readability, portable backups, Game Chat, image scrolling, Happy Hour and normal launching.
5. Run local updater transaction fixtures and test restoring a packaged update on a separate disposable launcher copy. Do not require GitHub Actions.
6. Server-login verification and any full release/license review remain separate; this source pass does not establish either.
