# Patching TES3MP for Nerevarine Prophecies

## User flow

Place the extracted `tes3np` folder inside a complete TES3MP 0.8.1 Win64 installation and run `tes3np.ahk`. The executable can also sit directly beside `tes3mp.exe`; all launcher subfolders must remain beside it. Startup checks the current and parent folder before falling back to saved installation paths.

The Expansion Pack is optional; TES3NP includes the TES3MP client separately. The Optional Expansion Pack panel offers **Upload / Repair** to choose a current downloaded NP ZIP or extracted folder. **Verify** only checks whether the locally installed ESP exists and its entry is last in the selected active OpenMW load order; it cannot certify version or NP server compatibility. The legacy bundled v0.1 installer is disabled and cannot write files.

Morrowind detection checks the saved path, `data=` entries in the configuration, the game's registry entries, the Steam installation registry path and common Steam/GOG folders. Custom Steam libraries can be selected manually. The default user configuration is `Documents\My Games\OpenMW\openmw.cfg`, using the Windows Documents location rather than assuming a username or drive. For a custom configuration, browse to the actual active user file.

## What is installed

- TES3NP packages its own TES3MP Win64 client; optional Expansion Pack import does **not** replace `tes3mp.exe`.
- The **user-selected** NP Expansion Pack ZIP/folder is installed into the selected Morrowind GOTY `Data Files`, with required masters validated, file hashes and transactional backups.
- The current importer retains unrelated config entries, places `content=NP Expansion Pack.esp` at the bottom of `openmw.cfg`, and supports restoring its own import backups from its saved journal. It does not use the old bundled v0.1 asset hashes as the definition of a current pack.
- Launcher game-client selection remains managed under **Launcher Settings > Game Client Settings**.

Base game files are not redistributed. No changes are made to the original Morrowind executable, character credentials, settings.cfg or keybindings. The supplied binary is for TES3MP 0.8.1 Win64; other versions are rejected. Automatic configuration-chain rewriting and linked installation directories are deliberately unsupported. For a nonstandard setup, choose its active user configuration; a file containing `config=` redirections is rejected rather than guessed. The launcher validates the selected file, not every potential higher-priority configuration or command-line override.

The NP server's login chat message is the final in-game confirmation that EP is accepted. Local verification does not prove the server accepted it or prevent every possible client crash.

## Detecting mismatched server plugins and importing a downloaded expansion

When a TES3MP launch is rejected with `Your plugins or their load order don't match the server's`, TES3NP watches **only new client log output produced by that launch** and stops the failed TES3MP process. It replaces the recovery experience with an owned launcher dialog explaining that the cause may be a new NP Expansion Pack, different plugin versions, or a mismatched load order. It does not claim an update exists until the user checks the NP Discord server, and it cannot guarantee that the TES3MP-owned error popup never flashes before detection.

**Upload Expansion** is a manual local-package importer, not a network downloader. One native Windows Explorer-style browser replaces the former two-button source chooser. Select a `.zip` file with **Open ZIP**, or highlight/navigate to an extracted package and press **Use This Folder** in the same dialog. The importer detects ZIP versus directory. The selected directory may be `Data Files` itself or an extracted wrapper containing `Data Files`. The existing worker also retains standalone `NP Expansion Pack.esp` compatibility for legacy callers, but the launcher directs users toward a complete archive or extracted package. The installer recognizes the ESP and supported `Data Files/Icons|Meshes|Textures/tes3mp_np` assets; it refuses unexpected content inside `Data Files` until that layout has been reviewed. The PowerShell worker validates ZIP paths and allowed asset types, stages and hashes the content, checks free space on staging, backup and game drives, backs up existing game files and `openmw.cfg`, then replaces files transactionally with rollback on failure. There is no arbitrary 1 GiB total or 128 MiB per-file cap. The temporary stage is deleted after completion or failure, while the backup journal is retained. It never overwrites the bundled `tes3mp.exe`, official master files, saved characters, or launcher passwords. Only the NP server can establish whether the selected download is the version now required. The import's backup journal is retained under `%APPDATA%\\tes3np\\expansion-imports`. Windows file-sharing or byte-range locks during hashing, backup, or replacement are retried only for the two transient Win32 lock conditions (32/33), up to six attempts. Persistent locks fail safely with an operation/file ordinal and the existing rollback; close other programs that may be reading the selected archive or game assets before retrying.

**Upload / Repair** now calls the current-package importer instead of the older v0.1 installer. The legacy PowerShell **Apply** action also fails closed even when invoked directly. Verify checks installed ESP presence and load order without comparing new files to old bundled checksums; a successful Verify is not proof of server acceptance. Legacy Restore Backup remains available only for old completed backups that do not overlap later completed manual imports; the original file-hash safety checks still apply. Do not run any restore against the real installation just to test it.

The session controller includes the check in its existing watchdog, including the short connection window for Start New Adventure. It never adds a parallel login/reconnect timer, and it stops only the rejected client without scheduling further logins. On Windows, test redirected OneDrive Documents log directories, old logs versus fresh failures, ZIP/ESP imports, mismatched masters, rollback, and connection to the actual NP server.

## Progress and logs

The existing dimmed loading card shows the current operation/file and `(x%)`, and its bar follows reported work. Operations run in a separate Windows PowerShell process so the UI remains responsive. Controls and launcher-owned game launches are blocked during the job. There are no artificial loading waits. The first and final loading placeholders use Waiting for Jiub.

The worker reports checking, backing up, patching, restoring and final verification. Patch logs are `%APPDATA%\tes3np\patch-all.log` and `patch-errors.log`, using generic managed-file numbers and operation descriptions rather than personal paths. Settings and journals contain actual paths because they are necessary for recovery; they are local operational data, not public logs.

## Backups, repair and restore

Before changing any files, the worker creates and verifies backups under `%APPDATA%\tes3np\patch-jobs\<job-id>`. A journal records original and installed hashes and whether each file existed. Copies use a temporary file beside the destination, verify its hash and then replace the destination. If an operation fails, this attempt's changed files are restored automatically where possible. Backups are retained.

New Upload / Repair imports back up only files they change; the importer retains its completed backup journal in `expansion-imports` and attempts rollback on failure. **Restore Backup** on the old panel is only for a completed *legacy* patch journal. It refuses altered post-install files and now refuses legacy restoration when a completed manual import touched an overlapping file. Do not delete either backup location. Verify is read-only and does not overwrite the useful old backup pointer.

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
