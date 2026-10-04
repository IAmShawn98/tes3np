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
