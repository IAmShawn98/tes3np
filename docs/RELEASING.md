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
