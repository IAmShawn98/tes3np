# Releasing TES3NP

Publish numbered releases in `IAmShawn98/tes3np`. GitHub Pages uses the
`website` branch. Keep branch protection and validation workflows in place.
Keep personal AppData and character exports out of Git.

## Channels and files

| Channel | Example tag and hotfix | Release type | Feed on `update-feed` |
| --- | --- | --- | --- |
| Alpha | `v0.1.21-alpha`, `v0.1.21-alpha.1` | Prerelease | `alpha.json` |
| Beta | `v2.0.0-beta`, `v2.0.0-beta.1` | Prerelease | `beta.json` |
| Live | `v2.0.0-live`, `v2.0.0-live.1` | Stable | `live.json` |

The installed build follows its own channel. Keep experimental Alpha work
separate. An approved Beta may merge into `main` for a newly built Live
candidate. The current **Publish Alpha** workflow publishes the `.21` cutover
from `main`.

Use `AppConfig.Version` in `src/state.ahk` for the application version and
prefix Git tags with `v`. Each release gets a ZIP named
`tes3np-v<version>-windows.zip` and its `.sha256` file. Generate the matching
schema 2 manifest and checksum with `scripts/generate-update-metadata.ps1`
using `-ChannelFeed -PackagePath <zip> -ManifestPath <manifest>`.

## Windows acceptance

Use the exact release ZIP in disposable Windows profiles and a copy of game
data. Record the source commit, ZIP hash, OS, DPI, privileges, and outcomes
in [RELEASE-REVIEW.md](RELEASE-REVIEW.md). Record skipped checks explicitly.

- **Build:** Run `scripts/run-local-regression.ps1` and the packaged
  `--check-owned-menu-scaling` check. Check source, PowerShell, Chat Host,
  Expansion Pack, ZIP integrity, updater metadata, and rollback.
- **First use and UI:** Test a standard account on clean Windows 10 and 11 x64,
  writable paths with spaces and Unicode, missing WebView2 or GOTY, shortcut
  choices, and a moved installation. Exercise
  50–100% launcher scale and Windows DPI at 100%, 125%, and 150%, including
  owner movement, modal prompts, and cached page reopen.
- **Characters and macros:** Exercise add/edit/favorite, portable backups,
  stock and custom portraits, normal exit and crash recovery, manual and
  saved login, up to four clients, bundled/custom client, and AHK/ZIP/EXE macros.
- **Expansion Pack:** Test first setup, toggling, signed-in and signed-out
  download/retry/cancel, ZIP and folder imports, mismatch diagnostics,
  unrelated files and mods, and failed-write recovery.
- **Game Chat:** Test first sign-in, sign-out, live chat and updates,
  and genuine active and expired Happy Hour announcements, including
  signed-out display from the local archive. Inspect shared diagnostics
  and bug reports for private data.
- **Upgrade:** Use an isolated `.20` installation and a disposable Windows
  account. Verify restart into `.21` and preservation of character data,
  delays, custom overrides, chat preferences, and shortcut choices.
  Exercise failure after backup and after installation in the fixtures.

## Release evidence gate

Complete the source, distribution, and Windows checks in
[RELEASE-REVIEW.md](RELEASE-REVIEW.md). Run `python scripts/check-release-gates.py`
before publication and obtain the repository owner's approval.

## Player-facing release notes

Use [RELEASE_NOTES.md](../RELEASE_NOTES.md) for player-visible changes since
the previous public release. Retain published entries. Use a version heading
and order the applicable categories as New Features, Improvements, Bug
Fixes, and Removed Features. The launcher and publisher use this file.

## Publish Alpha

1. Build the reviewed commit using `TES3NP_MARKERLESS_CONSOLE_EXE` and
   `TES3NP_MARKERLESS_CONSOLE_DLLS`. Run
   `python scripts/check-windows-package.py <zip> --require-console-client`.
   Test the versioned ZIP and keep those exact bytes for the release.
2. Prepare a prerelease draft pinned to the full commit SHA. Attach only the
   versioned ZIP and checksum. Complete the release review on `main`.
3. After owner approval and the visibility change, run **Publish Alpha**
   from `main` using the tag and ZIP SHA-256. It verifies the draft, publishes
   the release, checks the public download, then updates `update-feed:alpha.json`.
4. Verify the release and feed signed out. If feed verification fails after
   publication, fix the issue and rerun with the same tag, commit, and ZIP.
   Keep the latest approved download per feature build and channel.

## Publish the one-time v0.1.20-alpha bridge

After verifying the public `.21` release and feed, obtain owner approval
for the legacy bridge. Copy the verified `.21` ZIP byte-for-byte to
`tes3np-windows.zip` and run `scripts/generate-update-metadata.ps1` without
`-ChannelFeed` to generate the schema 1 `tes3np-update.json` and checksum.

1. Preserve the numbered `.20` ZIP and checksum. Verify the manifest
   currently serves `.20` or the exact approved `.21` manifest on a retry.
2. Replace `tes3np-windows.zip` and `tes3np-windows.zip.sha256` on
   [the legacy latest-alpha release](https://github.com/IAmShawn98/tes3np-releases/releases/tag/latest-alpha).
   Download and verify both without signing in. Restore the original pair
   if verification fails.
3. Replace `tes3np-update.json` last. Fetch it publicly and verify schema,
   version, filename, size, and SHA-256. Use the stock `.20` update button
   in a disposable account to verify restart into `.21`, preserved data,
   and access to the new alpha feed.
4. Keep the legacy release available until `.22` and its update feed are
   verified. Coordinate retirement and the site transition with the owner.
