# TES3NP — Expansion Pack import and recovery

## Active workflow

TES3NP includes its own TES3MP client. The NP Expansion Pack is optional and **disabled by default** unless already enabled in the user’s actual `openmw.cfg`. Enabling requires an already-installed nonempty `NP Expansion Pack.esp`; it never copies legacy assets. When missing, the launcher requests the official Discord download dialog, but first opens the existing branded Game Chat sign-in if Discord is unauthenticated. Only confirmed live channel authentication can authorize the download dialog; closing sign-in cancels the request. Disabling edits the OpenMW content entry only, preserving user-installed assets and other mods. The first-run Morrowind GOTY folder picker remains separate.

When the server reports that plugins or load order do not match, the launcher offers the existing **Upload Expansion** action. Choose a current NP ZIP or extracted folder obtained from the official server community. The chooser and importer do not automatically download files or authenticate the package against the server.

The active worker, scripts/import-expansion-pack.ps1, stages the selected archive or folder, validates allowed Data Files paths, hashes staged files, checks disk space, verifies Morrowind/Tribunal/Bloodmoon requirements, updates the selected active openmw.cfg, backs up files to be changed and uses atomic replacements with rollback on failure. It preserves unrelated mod files, the bundled TES3MP executable, character credentials and launcher settings. Only connection to the NP server can confirm compatibility.

## Retired bundled installer

The former **Install / Repair**, **Verify**, and **Restore Backup** panel was retired on 2026-11-02. Its callbacks and legacy worker are absent. On November 5, the release manifest was reduced to the separately packaged markerless TES3MP client. Historical v0.1 Expansion Pack art may still be present in the repository checkout, but is not staged, embedded, validated, shipped, or copied into a player's game. The only supported installer is the current user-selected ZIP/folder importer.

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
