# Expansion Pack import and recovery

The Expansion Pack is optional. **Expansion Pack** enables or disables the
installed `NP Expansion Pack.esp` in OpenMW. Disabling removes its content
entry and preserves the files and other mods. Close game clients first.

If the pack is missing or the server rejects the load order, open the official
Discord download prompt and sign in if asked. Use **Install ZIP**,
**Repair / Install ZIP**, or **Upload Expansion** to import the official ZIP
or its extracted folder. The worker checks the game files, stages the import,
and backs up changes to game data and `openmw.cfg`. Reconnect to confirm that
the server accepts the result.

Backups and import journals are under `%APPDATA%\tes3np\expansion-imports`.
The worker attempts rollback after a failed import. Keep the journal and use
**Copy Diagnostic Info** in the mismatch dialog if the failure persists.
