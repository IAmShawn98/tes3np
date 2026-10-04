# Patching TES3MP for Nerevarine Prophecies

## User flow

Place the extracted `tes3np` folder inside a complete TES3MP 0.8.1 Win64 installation and run `tes3np.ahk`. The executable can also sit directly beside `tes3mp.exe`; all launcher subfolders must remain beside it. Startup checks the current and parent folder before falling back to saved installation paths.

If all required installed files and configuration match the supplied patches, no files are replaced. Normal launcher features become available. Otherwise only Patch Tes3mp, Our Wiki and Quit Launcher appear. Patch Tes3mp opens the setup panel, which detects the usual configuration and game paths and offers Browse when needed. Confirm the folders, read the EP license and choose Install / Repair.

Morrowind detection checks the saved path, `data=` entries in the configuration, the game's registry entries, the Steam installation registry path and common Steam/GOG folders. Custom Steam libraries can be selected manually. The default user configuration is `Documents\My Games\OpenMW\openmw.cfg`, using the Windows Documents location rather than assuming a username or drive. For a custom configuration, browse to the actual active user file.

## What is installed

- The supplied markerless Win64 `tes3mp.exe` replaces the selected client's executable.
- The supplied NP Expansion Pack v0.1 `Data Files` are merged into the selected Morrowind GOTY installation. All three official master files must already exist.
- A copy of the EP license is retained in the TES3MP folder. The original license remains intact in the launcher payload.
- The Morrowind data path is added to the selected user `openmw.cfg` if absent. Existing settings, comments and other plugin order are retained. Existing EP entries are removed and one `content=NP Expansion Pack.esp` is appended last. A previously empty configuration also receives Morrowind.esm, Tribunal.esm and Bloodmoon.esm.
- tes3np's shared executable path is updated after verification. Launching through tes3np uses `--connect=NerevarineProphecies.servegame.com:25565`.

Base game files are not redistributed. No changes are made to the original Morrowind executable, character credentials, settings.cfg or keybindings. The supplied binary is for TES3MP 0.8.1 Win64; other versions are rejected. Automatic configuration-chain rewriting and linked installation directories are deliberately unsupported. For a nonstandard setup, choose its active user configuration; a file containing `config=` redirections is rejected rather than guessed. The launcher validates the selected file, not every potential higher-priority configuration or command-line override.

The NP server's login chat message is the final in-game confirmation that EP is accepted. Local verification does not prove the server accepted it or prevent every possible client crash.

## Progress and logs

The existing dimmed loading card shows the current operation/file and `(x%)`, and its bar follows reported work. Operations run in a separate Windows PowerShell process so the UI remains responsive. Controls and launcher-owned game launches are blocked during the job. There are no artificial loading waits. The first and final loading placeholders use Waiting for Jiub.

The worker reports checking, backing up, patching, restoring and final verification. Patch logs are `%APPDATA%\tes3np\patch-all.log` and `patch-errors.log`, using generic managed-file numbers and operation descriptions rather than personal paths. Settings and journals contain actual paths because they are necessary for recovery; they are local operational data, not public logs.

## Backups, repair and restore

Before changing any files, the worker creates and verifies backups under `%APPDATA%\tes3np\patch-jobs\<job-id>`. A journal records original and installed hashes and whether each file existed. Copies use a temporary file beside the destination, verify its hash and then replace the destination. If an operation fails, this attempt's changed files are restored automatically where possible. Backups are retained.

Install / Repair skips files that already match. A repair that changes files creates another backup linked to the previous one. Restore Backup undoes the most recent successful changing operation, restoring overwritten files and removing files that operation newly created. It leaves unrelated files intact and returns the launcher to the setup gate. A subsequent restore can undo an earlier operation. If managed files changed after installation, restore stops before mutation to preserve those changes. Verify/unchanged repair do not replace the latest useful backup pointer.

An interrupted worker or machine shutdown may leave an incomplete journal. Keep that job folder; it is not a completed restore point, and recovery from it may require restoring its recorded backups manually. Do not delete patch-jobs if you want to retain recovery options. Do not force-close the worker or launcher while files are being changed.

## Maintainer payload

`patches/manifest.json` lists SHA-256 hashes for the supplied markerless executable, each EP file and license. Updating payload files requires updating this manifest. Keep NP assets intact and preserve their supplied license. Startup verifies both payload and installed file content rather than trusting a completion flag. The optional copied license does not gate an otherwise already manually patched installation.

## Required Windows validation

Test AutoHotkey v2 and Windows PowerShell 5.1 before distributing publicly:

1. Fresh complete TES3MP 0.8.1 Win64 plus clean Steam/GOG Morrowind GOTY; new and existing user configs.
2. Detection when launcher is inside TES3MP, placed directly beside the executable, or launched from another working directory.
3. Startup of an already manually patched installation, restart after setup, missing/changed payloads, missing installed EP assets and disabled/reordered EP.
4. Existing unrelated files, comments and plugin order survive; the EP appears exactly once and last. Config encoding, Unicode paths, spaces, custom Steam libraries and relocated Documents.
5. Repair does not recopy unchanged files or lose the original backup pointer. Restore removes only newly created managed files, restores originals byte-for-byte, and refuses post-install changes.
6. Permission/disk errors, open game and OpenMW Launcher, failure after partial copying and rollback. Launcher launch controls remain blocked during patching.
7. Progress text and percentage match the bar, the proven loading card stays visible, and settings persist after replacing launcher files.
8. Connect to NP and check the server's installed-EP login message. Local static checks are insufficient to establish this.

Patch failures now identify the selected field, operation and managed file where available, plus exception type and Windows error codes. GUI validation errors also report the source filename/line. Details are recorded in patch-errors.log; personal paths remain omitted. Missing files are identified individually.
