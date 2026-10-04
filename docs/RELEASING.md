# Releases and GitHub setup

Create a repository named `tes3np` and push this folder's contents as its root.
`.github` belongs beside `tes3np.ahk`, not inside a nested project directory.
The ignore rules retain the required markerless executable and exclude local data.

A source-only package omits the large payload. Copy `patches/` from a complete
build before committing the complete project or making a full release. Never
commit character exports or your live `%APPDATA%\tes3np` folder.

Configure branch protection in GitHub settings and require the `Static and
PowerShell checks` workflow. Decide who can merge and publish. These files do not
create a remote repository, grant permissions or enable branch protection.

## Release checklist

1. Update `AppConfig.Build` in `src/state.ahk` and `CHANGELOG.md`.
2. Run `python scripts/project.py check` with all payload files present.
3. Run `powershell -NoProfile -File scripts/check-powershell.ps1` on Windows.
4. Complete affected GUI/game checks in `DEVELOPMENT.md` and patch checks in
   `PATCHING.md`. Record Windows, AutoHotkey and TES3MP versions tested.
5. Run `python scripts/project.py package` and inspect the ZIP in `dist/`.
6. Tag the reviewed commit, create a GitHub Release and attach the complete ZIP.
   Describe changes, validation and known limitations. Publish after review.

Packaging checks source, hashes and ZIP integrity. It does not compile, sign,
publish or certify login behavior. CI never launches the game or imported macros.
Build 143 was statically checked on Linux; its refactored Windows flows still need
runtime validation before a public release.
