# Releases and GitHub setup

`IAmShawn98/tes3np` holds the launcher source and numbered GitHub Releases,
including the original v0.1.20-alpha Windows ZIP and checksum. The first
approved Alpha publication creates the `update-feed` branch. The permanent
GitHub Pages source is staged at the root of the `website` branch for
https://iamshawn98.github.io/tes3np/.

`IAmShawn98/tes3np-releases` currently serves the temporary site and the
public `latest-alpha` bridge used by installed v0.1.20-alpha launchers.
Keep the old route and its versioned .20 download reachable during the
transition. Publishing v0.1.21-alpha, making `tes3np` public, updating the
legacy feed, and retiring the old repository require owner approval.

Never commit character exports or live `%APPDATA%\\tes3np` data.
Require branch protection and the validation workflows before publishing.

## Upgrade compatibility gate: v0.1.20-alpha → v0.1.21-alpha

Use an **isolated test installation and disposable Windows user profile**
with a copy of non-sensitive test profiles. Do not overwrite actual
player credentials. Capture the existing installation layout, the
update feed asset names, and a SHA-256 of each installed package.

1. Install the actual public v0.1.20-alpha package in a writable folder.
   Record whether the old install is nested in a TES3MP directory.
2. Preserve a non-sensitive test character, its settings and launch
   delays, and a custom-client configuration.
3. Attempt upgrade using the candidate package through the update
   transaction (or an offline staged test). Validate the existing
   install layout against the staging safety checks; do not force an
   unrecognized ZIP nesting.
4. Confirm character data, login delays, custom overrides,
   chat preferences and desktop shortcut decision survive.
   Old scheduler INI sections, if present, must remain inert and must not
   trigger scheduled actions or be imported into portable backups.
5. Exercise both successful update and deliberate simulated
   `after-backup` / `after-install` failure; verify rollback restores
   working files and unrelated files remain untouched.
6. Verify update metadata version comparison, expected asset filenames,
   ZIP checksum, and restart behavior without pointing live users to
   a development package.
7. Test fresh-install behavior separately from upgrading an existing
   v0.1.20-alpha profile. Neither test replaces a clean Windows 10/11
   machine verification.

The development-PC offline bridge test passed using the updater shipped
in the public v0.1.20-alpha ZIP. The channel-aware v0.1.21-alpha candidate
restarted and retained the test character and launcher settings.
Validate the final combined candidate on the second PC. Live discovery
and download through the legacy feed and reachability of the new alpha
feed remain pending.

## Release channels and promotion

| Channel | Base tag | Hotfix tags | GitHub Release | Launcher feed |
| --- | --- | --- | --- | --- |
| Alpha | `v0.1.21-alpha` | `v0.1.21-alpha.1`, `v0.1.21-alpha.2` | Prerelease | `alpha.json` |
| Beta | `v2.0.0-beta` | `v2.0.0-beta.1`, `v2.0.0-beta.2` | Prerelease | `beta.json` |
| Live | `v1.0.0-live` | `v1.0.0-live.1`, `v1.0.0-live.2` | Stable release | `live.json` |

- **Alpha** is the experimental track. Publish Alpha builds from their own
  branches. Alpha builds stay Alpha, and Alpha branches are never promoted
  or merged into Beta or Live.
- **Beta** is the public testing track for the next Live version. Develop
  that version on a dedicated branch and publish its Beta builds while the
  current Live release continues to receive its own updates. When the Beta
  is approved, merge the entire tested branch into `main`, set the Live
  version, and build and validate a new Live ZIP from the merged source.
  For example, the `v2.0.0-beta` series leads to `v2.0.0-live`.
- **Live** is the stable release track. Mark the current Live release as
  Latest on GitHub. The website recommends the current approved download.
  When the first Live build is available, point its **Download for Windows**
  button at Live and keep GitHub Releases as the direct download option.

The canonical application version is `AppConfig.Version` in `src/state.ahk`.
Git tags and GitHub Releases add a leading `v`. Published hotfixes get a
new numbered tag, ZIP and checksum. Verify the public ZIP and checksum
before advancing the matching channel manifest. The launcher stays on the
installed build's channel, including after a Beta is promoted to Live.
Players switch channels by installing a build from the channel they want.

## Previously supplied markerless client

The legacy `patches/markerless/tes3mp.exe` is distinct from the source-built
console candidate. Its exact corresponding source, build procedure and
modification authorship remain unverified. The May 2023 Nerevarine
Prophecies Discord post describes disabling remote map markers. Upstream
TES3MP 0.8.1 and the public example patches document the baseline and
possible implementation. The legacy binary still needs its own review
before redistribution.

The [original provenance investigation](https://github.com/IAmShawn98/tes3np/blob/aebc384e384a71daa4080fa8e69fbbcd9bcf1a82/docs/RELEASING.md#october-29-provenance-investigation-for-the-previously-supplied-client)
records the supplied download, attribution, source comparison and limitations.
The known `WindowsBase` MSB3277 warning comes from the WebView2 dependency in
the WinForms Chat Host. Existing Windows tests compiled and ran it.

## Source-built markerless console candidate

The independent TES3MP 0.8.1 console client was built and playtested.
See `research/markerless/README.md` for the pinned source revisions,
patches and build procedure, and `console-candidate.json` in that
directory for its approved test EXE hash and DLL requirements. The
release package checker verifies the EXE and the staged DLL manifest
against the packaged source materials. Capture those results for the
exact release ZIP in the formal provenance evidence. The previously
supplied binary remains tracked at `patches/markerless/tes3mp.exe`.
Before changing repository visibility, review that file and retained
asset history as well as the contents of the Windows package.

## Release evidence gate

Before proposing a public release, run
`python scripts/check-release-gates.py`. This intentionally **fails**
until three reviewed evidence files exist:

- `docs/MODIFIED-TES3MP-SOURCE-PROVENANCE.md`: exact modified binary
  SHA-256, corresponding source revision/patch, reproducible build commands,
  author/source access and license notices; mark
  `Status: VERIFIED_SOURCE_AND_BUILD` only after verification.
- `docs/ASSET-DISTRIBUTION-APPROVAL.md`: review ownership, redistribution
  rights and all third-party notices; mark
  `Status: ASSET_RIGHTS_REVIEWED` only when confirmed.
- `docs/CLEAN-WINDOWS-TEST-RESULTS.md`: actual fresh Windows machine/VM
  results with OS versions, packaged ZIP hash, prerequisites, user-level
  permissions and regression outcomes; mark
  `Status: CLEAN_MACHINE_TESTED` only when completed.

The check looks for documentation and review markers, not independent legal
proof. Passing it still requires the repository owner's explicit release
approval. Do not invent or pre-fill approvals.

## Player-facing release notes

Use `RELEASE_NOTES.md` for changes since the last publicly shipped version.
Keep internal build details, diagnostics, tests, and closed development
experiments in `CHANGELOG.md` and the project history. Include changes players
can observe. Verify each fix against the released baseline and the candidate.

Use `## vX.Y.Z-channel — unreleased` and a line identifying the public
comparison version. Include only applicable categories in this order:
**New Features**, **Improvements**, **Bug Fixes**, **Removed Features**.
Give each distinct change one plain-language bullet with a bold feature
or area label and its outcome. Remove duplication and unverified claims.
Set the release date at publication and preserve historical published notes.

The launcher renders plain headings and bullet points. Validate word wrapping
and scrolling at supported Windows display scales. The publish workflow uses
the matching section of `RELEASE_NOTES.md`.

## Single-repository updater contract

The new launcher reads `alpha.json`, `beta.json` or `live.json` from the
`update-feed` branch of the development repository. The installed version
determines the channel. Version numbers are compared numerically within the
installed channel. Older unsuffixed Live versions remain readable.

To generate a schema 2 candidate manifest and checksum after packaging,
copy the validated ZIP to `tes3np-v<version>-windows.zip` and pass that
path to `scripts/generate-update-metadata.ps1 -ChannelFeed -PackagePath`.
Use `-ManifestPath` for the candidate manifest path. The launcher derives
the download address and release notes from the exact tag and validates
the filename, size and SHA-256 before staging. Generate with
`-DisableUpdates` to prepare a manifest with automatic updates disabled.

## Publish the v0.1.21-alpha cutover candidate

The staged **Publish Alpha** action runs from `main` for this cutover.
Future Alpha publication from isolated branches and Beta and Live
publication have yet to be wired into the workflow.


1. Merge the reviewed alpha source into `main` before producing the final
   candidate. Record the full source SHA. On Windows, build from that commit
   with both `TES3NP_MARKERLESS_CONSOLE_EXE` and
   `TES3NP_MARKERLESS_CONSOLE_DLLS` set. Run
   `python scripts/check-windows-package.py dist/tes3np-windows.zip --require-console-client`.
   Retain the exact ZIP tested on clean Windows. Copy it to the versioned
   filename and use the channel metadata generator above to obtain its
   matching checksum. Commit the three evidence files to `main` after
   review. Only those files may differ between the candidate's source
   commit and the workflow's checkout.
2. Prepare a prerelease **draft** in `IAmShawn98/tes3np` with the numbered
   tag, the full reviewed source SHA as its target, the matching section
   of `RELEASE_NOTES.md`, and only the versioned ZIP and checksum.
3. After owner approval and the visibility change, run **Publish Alpha**
   from the current `main` with the draft tag and reviewed ZIP SHA-256.
   The workflow validates the package and evidence, publishes the draft
   with its matching notes from `RELEASE_NOTES.md`,
   confirms that the tag resolves to the reviewed commit, and checks the
   public downloads before creating or updating `update-feed:alpha.json`.
   If the release publishes but feed verification fails, resolve the
   failure and rerun against the same commit and ZIP. Keep the versioned
   release assets and their names stable during the retry.
4. With the approved cutover, enable Pages from `website:/(root)`. Using
   a signed-out session, verify the homepage, all eight slides and the
   download button, README link, and numbered Releases download.
5. After a later hotfix's feed and download are verified, remove the
   superseded ZIP and checksum for that channel and feature build while
   retaining its notes. Keep the latest approved ZIP per feature build.

## Publish the one-time v0.1.20-alpha bridge

Do this after the numbered v0.1.21-alpha release and alpha feed are
verified and the owner has approved the bridge. Use the exact public
v0.1.21-alpha ZIP after verifying its SHA-256 against the reviewed ZIP.
From the same source checkout, copy the bytes to `tes3np-windows.zip`
and run the metadata generator without `-ChannelFeed` to produce the
schema 1 `tes3np-update.json` and `tes3np-windows.zip.sha256`.

1. Check that the current legacy manifest still offers v0.1.20-alpha
   (or is already the exact approved v0.1.21-alpha manifest on a retry).
   Keep the versioned .20 ZIP and its checksum available for the old site
   and stock-client tests.
2. On `IAmShawn98/tes3np-releases`, replace the two unversioned
   `latest-alpha` assets `tes3np-windows.zip` and
   `tes3np-windows.zip.sha256`. Download both from their signed-out URLs
   and compare the SHA-256 and checksum contents with the schema 1 manifest
   before replacing `tes3np-update.json`. If either verification fails,
   restore the original .20 pair and retry. Launchers check the size and
   hash, so a partial replacement is rejected.
3. Replace `tes3np-update.json` last and fetch it from the public URL.
   Verify schema 1, version, filename, size and SHA-256. In a disposable
   Windows profile, open the stock public .20 launcher and use its normal
   update button. Verify it restarts as .21, preserves profiles and
   preferences, and can use the new alpha feed.
4. Keep the bridge reachable for returning .20 installs. They need a
   manual download after the legacy repository goes away. Coordinate
   the old site's transition and repository retirement with the owner.

[Binaries and manifest on the legacy release](https://github.com/IAmShawn98/tes3np-releases/releases/tag/latest-alpha)

## Release checklist

- Verify `AppConfig.Version` in `src/state.ahk` and its matching
  `CHANGELOG.md` and `RELEASE_NOTES.md` entries.
- Run `python scripts/project.py check` with all payload files present and
  `powershell -NoProfile -File scripts/check-powershell.ps1` on Windows.
- Use the [Windows acceptance checklist](ALPHA-COMPATIBILITY-CHECKLIST.md)
  for GUI, game, upgrade and recovery testing.
- Inspect the automatic validation results. A passing compile and package
  check does not certify live login, gameplay or imported macros.
- Record the candidate ZIP hash, Windows results, corresponding source
  details and distribution review before requesting owner approval.
