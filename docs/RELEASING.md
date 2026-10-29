# Releases and GitHub setup

Create a repository named `tes3np` and push this folder's contents as its root.
`.github` belongs beside `tes3np.ahk`, not inside a nested project directory.
The ignore rules retain the required markerless executable and exclude local data.

A source-only package omits the large payload. Copy `patches/` from a complete
package before committing the complete project or making a full release. Never
commit character exports or your live `%APPDATA%\tes3np` folder.

Configure branch protection in GitHub settings and require the `Static and
PowerShell checks` workflow. Decide who can merge and publish.

## Versioning

tes3np uses Semantic Versioning rather than internal build numbers.

- `0.x.y-alpha` — active development; features and behavior may change.
- `0.x.y-beta` — feature-complete enough for broader testing.
- `0.x.y-rc.N` — release candidate undergoing final validation.
- `1.0.0` — first stable public release.

The canonical application version is `AppConfig.Version` in `src/state.ahk`.
Git tags and GitHub Releases use the same version prefixed with `v`, for example
`v0.1.0-alpha`.

## Current alpha release blockers (October 29, 2026)

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

## Release checklist

1. Update `AppConfig.Version` in `src/state.ahk` and add the matching version to `CHANGELOG.md`.
2. Run `python scripts/project.py check` with all payload files present.
3. Run `powershell -NoProfile -File scripts/check-powershell.ps1` on Windows.
4. Complete affected GUI/game checks in `DEVELOPMENT.md` and patch checks in
   `PATCHING.md`. Record Windows, AutoHotkey and TES3MP versions tested.
5. Confirm the automatic `Build Windows launcher` workflow succeeds and inspect its package.
6. Tag the reviewed commit, create a GitHub Release and attach the Windows package.
   Describe changes, validation and known limitations. Publish after review.

Packaging checks source, hashes and ZIP integrity. CI compiles and validates the
launcher but does not certify live TES3MP login, gameplay or imported macro behavior.
Development versions remain prereleases until runtime validation is complete.
