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

Record the source, asset decision, and Windows results in
[RELEASE-REVIEW.md](RELEASE-REVIEW.md). Use `ASSET_RIGHTS_REVIEWED` when the
distribution review is complete or `MAINTAINER_APPROVED` when the maintainer
accepts the recorded asset evidence for the candidate. Run
`python scripts/check-release-gates.py` before publication and obtain the
repository owner's approval to publish.

## Player-facing release notes

Use [RELEASE_NOTES.md](../RELEASE_NOTES.md) for player-visible changes since
the previous public release. Retain published entries. Use a version heading
and order the applicable categories as New Features, Improvements, Bug Fixes,
Hotfixes, and Removed Features. A hotfix may contain new features and
improvements as well as fixes. The launcher and publisher use this file.

## Categorized release notes and hotfixes (v0.1.21-alpha.1 onward)

- Keep a separate `## v<version>` section in `RELEASE_NOTES.md` for each
  feature release and every published hotfix. Preserve all previously published
  sections and their contents. Never replace the original feature release
  changelog with a single hotfix entry.
- Drafts and commits are never player-facing updates. A change appears in the
  update preview only after its exact GitHub release is published. Preview
  dates use the public release's `published_at` UTC calendar date.
- A hotfix release (for example `v0.1.22-alpha.1`) gets its own short notes
  describing only that hotfix. Do not repeat the base release changelog in its
  notes. Publishing uses the exact version section to populate GitHub Releases.
- The version footer always shows the installed version, with a red `(1)`
  for each unseen newer published update. After the preview is viewed, the
  indicator disappears and stays hidden until another version is published.
  Either the version or indicator opens the optional updater; dismissing a
  preview never installs files.
- The update preview shows **only missed published changes**, categorized
  as New Features, Improvements, Bug Fixes, Hotfixes, or Removed Features.
  Fixes introduced by a hotfix belong under Hotfixes, even when that hotfix
  also introduces new features or improvements. Changes retain their original
  release version and publication date, newest first within each category.
  There are no separate tabs in the launcher preview.
- After installation, Version Status displays one **cumulative changelog**
  for that installed base release and all installed hotfixes. Original release
  changes and hotfix additions appear under their appropriate categories,
  marked by source version. The bundled changelog is used offline; missing
  required installed sections are shown as unavailable rather than silently
  omitted. No future/uninstalled changes appear in this view.
- Unverified, incomplete, or unpublished update history must be labeled
  unavailable rather than silently truncated. Users install the latest
  verified package directly, without sequential intermediate updates.
- GitHub release descriptions are **append-only for hotfix history**:
  the original feature release's full changelog and all previously published
  hotfix descriptions must remain unchanged. After publishing a hotfix and
  verifying its public ZIP, the alpha publisher uses
  `scripts/update-hotfix-index.ps1` to add or refresh only the base release's
  marked **Published Hotfixes** section. Entries link to the exact published
  hotfix tags, include UTC publication dates, and appear newest first.
  Re-running a publication is idempotent; malformed or missing history fails
  closed. The verified feed advances only after the index has been updated.
- Before approving any candidate, compare prior published version sections
  with their GitHub release bodies, ignoring only the dedicated generated
  hotfix-index suffix on the base release, and confirm no original changelog
  content was removed or rewritten. The existing full regression and
  publication approval requirements still apply.

## Website release history

The public [TES3NP website](https://iamshawn98.github.io/tes3np/) is
published from the repository's `website` branch. Its release section uses
`release-history.js` to fetch the verified `update-feed/alpha.json` version,
confirm the matching public GitHub release/ZIP, then display its original
feature notes and published dated hotfixes in separate tabs. Previous feature
releases link to their historical GitHub release entries. No draft hotfix or
unverified newer package becomes the website's latest download.

The page retains a static v0.1.21-alpha fallback if the public API/feed is
unavailable. When publishing later versions, keep that offline fallback
current with a deliberately verified site snapshot. GitHub release
descriptions may change **only in their machine-marked Published Hotfixes
index**; the website and launcher remove that index before rendering the original
release notes. The **website** retains its separate Hotfix History tab;
the **launcher** groups changes by category instead. Each hotfix retains its
own GitHub release description.

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
