# TES3NP — Expansion Pack import and recovery

## Active workflow

TES3NP includes its own TES3MP client. The NP Expansion Pack is optional and **disabled by default** unless already enabled in the user’s actual `openmw.cfg`. Enabling requires an already-installed nonempty `NP Expansion Pack.esp`; it never copies legacy assets. When missing, the launcher requests the official Discord download dialog, but first opens the existing branded Game Chat sign-in if Discord is unauthenticated. Only confirmed live channel authentication can authorize the download dialog; closing sign-in cancels the request. Disabling edits the OpenMW content entry only, preserving user-installed assets and other mods. The first-run Morrowind GOTY folder picker remains separate.

When the server reports a plugin or load-order mismatch, the launcher offers the official download and an **Install ZIP** action. The **Repair / Install ZIP** fallback opens the same picker. The picker accepts an official ZIP or an extracted folder, and passes it to the import worker.

The active worker, scripts/import-expansion-pack.ps1, stages the selected archive or folder, validates allowed Data Files paths, hashes staged files, checks disk space, verifies Morrowind/Tribunal/Bloodmoon requirements, updates the selected active openmw.cfg, backs up files to be changed and uses atomic replacements with rollback on failure. It preserves unrelated mod files, the bundled TES3MP executable, character credentials and launcher settings. Only connection to the NP server can confirm compatibility.

## Retired bundled installer

The former **Install / Repair**, **Verify**, and **Restore Backup** panel was retired on 2026-11-02. Its callbacks and legacy worker are absent. On November 5, the release manifest was reduced to the separately packaged markerless TES3MP client. Historical v0.1 Expansion Pack art remains in older Git trees. The current build and importer use the active package and installed data. The only supported installer is the current user-selected ZIP/folder importer.

Do not treat the old bundled manifest as a current installed-version check. The local enable/disable control reads the active OpenMW configuration, while the server's response remains the definitive compatibility test.

## Backups and errors

The current importer stores its completed backup journal and original changed files under %APPDATA%\tes3np\expansion-imports. It attempts rollback if an import fails and preserves the journal for later manual recovery. The retired **Restore Backup** button is not a recovery path for these newer imports. Do not delete or overwrite backup journals or test recovery against a real Morrowind install; use a disposable copy.

Progress and results are written atomically to the import job directory and displayed through the existing launcher loading overlay. Errors retain a bounded step description. Persistent Windows sharing locks, insufficient disk space, invalid archives or unsafe paths fail without intentionally replacing unrelated data.

## Windows validation

The local build runs the synthetic ZIP/folder importer and installed-only
toggle fixtures. Use the [Windows acceptance checklist](ALPHA-COMPATIBILITY-CHECKLIST.md)
to exercise the actual client, game configuration and recovery on a
disposable copy.
