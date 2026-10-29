# Experimental source-based TES3MP 0.8.1 markerless investigation

**Research only. Do not replace the functioning TES3NP bundled executable or publish this patch's compiled output as an approved release.**

## Exact source baseline

- Upstream repository: https://github.com/TES3MP/TES3MP
- Source ref: `0.8.1`
- Target files:
  - `apps/openmw/mwmp/GUIController.cpp` (upstream file Git blob SHA `3dda6dc8080828c3d3d512f5ec622563d01523d5`)
  - `apps/openmw/mwmp/DedicatedPlayer.cpp` (upstream file Git blob SHA `eaac4407e8d7431cc715afbb507c1ca86e79f8cd`)

The patch in this directory adds an early `return;` to `mwmp::GUIController::updatePlayersMarkers` and `DedicatedPlayer::updateMarker`. The changes are closely patterned after two documented changes visible in https://github.com/Skooma-Breath/surf_tes3mp, but **not authenticated as jiub's original source**. They are a *new experimental proposal* against official TES3MP, not a reverse-engineered or verified replacement for the May 2023 binary.

## Apply safely in a separate upstream source checkout

Run these in a **separate clone** of upstream TES3MP, never in the TES3NP launcher source directory or any live game directory.

```powershell
git clone --recursive https://github.com/TES3MP/TES3MP.git tes3mp-markerless-research
cd tes3mp-markerless-research
git checkout 0.8.1
git submodule update --init --recursive
git status --short
git apply --check "C:\path\to\tes3np\research\markerless\tes3mp-0.8.1-markerless-experimental.patch"
git apply "C:\path\to\tes3np\research\markerless\tes3mp-0.8.1-markerless-experimental.patch"
git diff --check
git diff -- apps/openmw/mwmp/GUIController.cpp apps/openmw/mwmp/DedicatedPlayer.cpp
```

**These steps have not been executed on a Windows machine in this investigation.** GitHub file inspection confirmed the two target functions exist in upstream `0.8.1`, but compilation, patch application, and actual marker/crash behavior are still untested.

## Build and release gates

1. Verify patch application against a pristine exact upstream checkout and compare against official `0.8.1` source.
2. Record and test a complete pinned Windows toolchain and dependencies, including MSVC, CMake, Qt and TES3MP/OpenMW submodules.
3. Compile the new client in isolation, record its SHA-256 and source tree commit, and compare real gameplay behavior with unmodified upstream and the existing jiub-supplied binary.
4. Test player markers, minimap stability with multiple players, game login and server compatibility, OpenMW settings, antivirus false positives and clean Windows machines.
5. If the experimental client is ever distributed, provide its own exact source revision, this patch, full build scripts/instructions and all applicable GPLv3 and other license notices. Review all third-party asset permissions separately.

This research artifact does **not** prove the source of the existing markerless executable and does **not** clear the release gate for bundling that executable.
