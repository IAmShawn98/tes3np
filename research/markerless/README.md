# TES3MP 0.8.1 markerless console client

The source-built client was tested on Windows 11 through TES3NP. It connected to
Nerevarine Prophecies, loaded a character, hid remote player map markers, and
launched with a visible Windows console after the matching DLLs were installed.
Clean-install and upgrade acceptance remain separate release checks.

## Source and build

- TES3MP source, commit `68954091c54d0596037c4fb54d2812313b7582a1`:
  https://github.com/TES3MP/TES3MP/tree/68954091c54d0596037c4fb54d2812313b7582a1
- CrabNet source, commit `19e66190e83f53bcdcbcd6513238ed2e54878a21`:
  https://github.com/TES3MP/CrabNet/tree/19e66190e83f53bcdcbcd6513238ed2e54878a21
- The included `tes3mp-0.8.1-markerless-experimental.patch` disables the two
  remote-player marker update functions. `tes3mp-release-console.patch` selects
  the Windows console subsystem and the normal C runtime entry point.

Install Visual Studio 2022 C++ tools and a Windows SDK, Git for Windows,
7-Zip, Python 3.11, and CMake 3.31.10. Put Git, Python, CMake and 7-Zip on PATH.
Use a short writable build directory with no spaces. Keep both patches and the
PowerShell scripts in one directory, then run:

```powershell
$buildRoot = Join-Path $env:LOCALAPPDATA 'TES3MP-Markerless-Build'
$env:CI = 'true'
.\build-markerless.ps1 -WorkRoot $buildRoot
.\Restore-Markerless-Console.ps1 -BuildId '<ID printed by first script>' -WorkRoot $buildRoot
```

The first script configures both clients with Visual Studio 2022 using the
upstream dependency recipe. It pins Qt 5.15.0 and adds the explicit chrono
include required by the newer compiler. The second reuses that build and
relinks the markerless Release executable as a console application. The
source-built package uses the DLLs and plugins staged from the same local
build, alongside the official 0.8.1 runtime resources. Build tools and
timestamps may differ between builds, so a rebuild is not expected to have
the same SHA-256.

The playtested console executable has SHA-256
`9028acd49dd6d87df54daa1fd4c3ea393e5e80f3680d0b4ef01d364a0d28d50b`.
The candidate ZIP records the exact EXE and the 45 staged DLL hashes in
`client-files.json`. The executable previously bundled by TES3NP has separate
provenance. See the parent TES3MP license and notices.
