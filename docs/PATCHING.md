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

When the ESP already exists but TES3NP's saved verification record has been
lost (for example, after resetting launcher data), enabling the pack runs an
authenticated check of the latest official Discord ZIP. If the installed ESP
matches the official published checksum and release version, TES3NP records
its current SHA-256 and offers to enable it **without downloading or copying
it again**. If the plugin was already in the OpenMW load order, choose
**Verify Existing** to re-establish the record; **Disable Entry** is still
available. If Discord or the official checksum cannot be checked, TES3NP does
not silently trust the ESP. Retry the check or import the official ZIP using
the established safe installer. This check compares the ZIP's published ESP
CRC-32 metadata; the locally stored SHA-256 then detects later file changes.

Backups and import journals are under `%APPDATA%\tes3np\expansion-imports`.
The worker attempts rollback after a failed import. Keep the journal and use
**Copy Diagnostic Info** in the mismatch dialog if the failure persists.
