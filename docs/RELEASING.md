# Releases and GitHub setup

`IAmShawn98/tes3np` holds the launcher source, numbered GitHub Releases,
and the channel feeds on `update-feed`. The permanent GitHub Pages site
uses the root of the `website` branch at https://iamshawn98.github.io/tes3np/.
The original v0.1.20-alpha Windows ZIP and checksum are already preserved
in this repository's numbered prerelease.

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

## October 29 provenance investigation for the previously supplied client

**Do not publish the modified markerless TES3MP executable yet.** The current
build verifies its SHA-256 and bundles the upstream license, but this repository
does not establish the exact corresponding source tree, modification diff, and
reproducible build instructions for that *modified* executable. A link to
unmodified upstream TES3MP is not enough by itself to document the changes.

Confirmed upstream download provenance (user supplied, October 29, 2026):
the official Morrowind Multiplayer Steam group announcement of May 1,
2022 links the **regular TES3MP 0.8.1 Windows client/server ZIP** to
`https://github.com/TES3MP/TES3MP/releases/download/tes3mp-0.8.1/tes3mp.Win64.release.0.8.1.zip`.
This is the normal, non-VR upstream distribution and is consistent with
the official TES3MP runtime downloaded by the TES3NP build. It does
**not** identify the author or corresponding source of the separately
supplied `patches/markerless/tes3mp.exe` modification; the upstream
link alone does not clear that blocker.
Announcement:
`https://steamcommunity.com/groups/mwmulti/announcements/detail/3208261824668407228`.

Maintainer communication (reported by project owner, October 29, 2026):
the owner believes **jiub created the markerless executable**, is in
direct communication with him, and reports that jiub supports the TES3NP
project. Treat authorship as **reported, not independently confirmed**.
Project support is valuable but does not by itself document corresponding
GPL source or establish every third-party asset permission. Next action:
request the May 2023 markerless code patch/source revision, toolchain,
and build instructions from jiub; confirm the binary provenance and any
redistribution conditions in writing. Do not interpret this report as
legal clearance.

Discord post attribution and purpose (user-provided screenshot, October 29,
2026): in NP Discord `#posted-fixes`, **jiub** posted at **May 2, 2023,
3:30 AM** under “Frequent Crashes/Crashes Near Multiple Players”.
The post states that player map markers on the minimap may cause crashes
and links a build of **TES3MP 0.8.1 that completely disables player map
markers**, reportedly improving stability. The screenshot's original link is
`https://www.dropbox.com/s/9x7stbzq2vi6oco/tes3mp.exe?dl=0`,
different from the newer `/scl/fi/` URL supplied by the tester.
The screenshot identifies **jiub as the poster, not necessarily the
programmer/compiler**. The screenshot is evidence of the stated intended
change, not proof of the bundled binary's exact bytes or source provenance.
Before marking this gate complete, obtain the modification's source patch
and build instructions from its author or NP maintainers and verify the
distributed executable against that provenance.

Markerless binary distribution provenance (reported by tester on October 29, 2026):
the `tes3mp.exe` used by the launcher was downloaded from the
Nerevarine Prophecies Discord channel `#posted-fixes`, at
`https://www.dropbox.com/scl/fi/3kef7phv9q0rkzlm066oy/tes3mp.exe?rlkey=ahaa4wrcnidmvd52v0qh3h87y&e=1&dl=0`.
This identifies a **distribution channel/link**, not the modification
author, original source revision, or corresponding build procedure.
We could not directly verify the Dropbox file content or compare its
hash to the vendored executable in this investigation. Request the
original Discord post attribution, version/date, and source/build
information from the poster or NP maintainers before clearing the
modified-client GPL source gate.

Further fork history investigation (October 29, 2026): the head commit
`9d121f13b113e797df965d5425bd06ec515c0578` is dated
**March 7, 2026**, with changes to Windows CI build scripting and
RakNet discovery, not the two markerless functions. Its preceding
commit `ea209fd6` is also dated March 7, 2026 and changes player
cell-handling behavior. Thus the fork contains other technical changes
and is not evidence of a May 2023 jiub build merely because of its
`markerless for now` comments. We attempted comparing the fork's
`surf_tes3mp` branch directly to an `0.8.1` tag using GitHub's
compare endpoint, but it returned 404 because that ref is not exposed
in the fork. A complete, verified fork-to-upstream diff remains undone.
Official TES3MP 0.8.1 contains Windows MSVC2019 build pipeline details
in its `.gitlab-ci.yml`, providing a baseline for a possible
independently built replacement, but no replacement has been compiled.

Verified source comparison against the official `TES3MP/TES3MP`
`0.8.1` tag (October 29, 2026): upstream
`GUIController::updatePlayersMarkers` normally iterates and redraws map
marker widgets; upstream `DedicatedPlayer::updateMarker` normally
updates the player's marker collection. The `Skooma-Breath/surf_tes3mp`
fork prepends an unconditional `return;` to each, leaving the old code
unreachable. This matches the *function* described by the May 2023
Discord fix, but **does not establish binary correspondence**, complete
patch equivalence, authorship, or build provenance.

Public code inspection, October 29, 2026: the
`Skooma-Breath/surf_tes3mp` fork has **two distinct early-return edits**
labeled `return; // markerless for now`:
`apps/openmw/mwmp/GUIController.cpp` in
`GUIController::updatePlayersMarkers`, and
`apps/openmw/mwmp/DedicatedPlayer.cpp` in
`DedicatedPlayer::updateMarker`. These disable two player-marker update
paths and are technically consistent with jiub's stated minimap-crash
workaround. They are a plausible *example implementation*, **not verified**
as jiub's source or as the source corresponding to our executable. We
have not established the fork's author, change date, base revision,
compiler flags or binary hash equivalence.

Source research lead (unverified): a public fork at
`https://github.com/Skooma-Breath/surf_tes3mp` contains
`apps/openmw/mwmp/GUIController.cpp` with a comment saying
`return; // markerless for now`. That proves a markerless-oriented change
exists in a public source tree; it **does not establish** that the bundled
executable was built from that fork or any specific revision. Do not cite
the fork as the binary's corresponding source without provenance or
rebuilding and validating the exact changes.

Before public redistribution, obtain from the person or project that made the
markerless binary:

1. Exact source revision and complete modifications corresponding to the
   distributed `patches/markerless/tes3mp.exe`.
2. Build toolchain, dependencies, configuration, and commands sufficient to
   rebuild that modified client; record any reproducibility limits honestly.
3. Applicable copyright/license notices and distribution permissions for all
   bundled materials, including NP Expansion Pack assets and original artwork.
4. A clear source-offer/access method distributed with the binary, reviewed
   against TES3MP's GPLv3 plus additional permitted terms. Get qualified
   legal review if necessary.

**Do not solve this blocker by removing notices, relabeling the binary,
claiming it is unmodified, or silently substituting another binary.**

The lone `WindowsBase` MSB3277 build warning originates from WebView2's
WPF reference in a Windows Forms .NET 8 project. The currently compiled chat
host works in existing tests; this warning is not the gating issue.

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
- Check the affected GUI/game paths in `DEVELOPMENT.md` and patch paths in
  `PATCHING.md`. Record Windows, AutoHotkey and TES3MP versions tested.
- Inspect the automatic validation results. A passing compile and package
  check does not certify live login, gameplay or imported macros.
- Record the candidate ZIP hash, Windows results, corresponding source
  details and distribution review before requesting owner approval.
