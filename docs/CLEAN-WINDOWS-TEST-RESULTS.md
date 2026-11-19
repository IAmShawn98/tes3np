# Windows release test results

Status: PENDING_CLEAN_MACHINE

## November 17 developer preflight

- Source commit `1b13ea57cdbcfc141a5e6bb96e73c467b83f8a43`.
- ZIP `dist/tes3np-windows.zip` with SHA-256
  `f0bd20791e9876db158d62dc49e1ad0171a61195af14b832e5371eaee8cbdc36`.
- Passed the Windows build, compiled `--check`, package integrity check
  with `--require-console-client`, updater metadata and tamper fixtures,
  and isolated upgrade and rollback fixtures. The packaged markerless
  client printed `--help` with its matching DLLs.
- The Chat Host built successfully with one `MSB3277` warning.
- The first packaged `--check-owned-menu-scaling` invocation, with
  unredirected output, exited 217. On retest with stdout and stderr
  redirected, the same packaged EXE printed PASS for owner movement,
  work-area bounds, 50–100% scaling, and font release. The source probe at
  `8566ff7ac492b8a68d7b64ea7b19c3a554f44204` also printed PASS using the
  package's AutoHotkey runtime. PowerShell did not print numeric exit codes
  on the retest.

## November 17 developer rebuild with Chat Host notices

- Source commit `cdca0fe7a9fe25d1ca038fecc99effdd04d74613`.
- ZIP `dist/tes3np-windows.zip` with SHA-256
  `0bdffb81715bdc4e66e0f46eab2a5b9aa6f7e62f05566597c11e5a1b26ed87b6`.
- The Windows build, compiled `--check`, and ZIP verification with
  `--require-console-client` passed. This package check includes the
  required Chat Host license and notice files.
- The packaged source-built client printed `--help` with its matching
  DLLs. The tester confirmed the TES3NP launcher opened.
- The Chat Host built with the existing WindowsBase `MSB3277` warning.
- The tester confirmed that the Game Chat window worked and Morrowind
  launched from TES3NP on this build.

## November 17 fresh Windows 11 profile

The tester extracted the .21 distribution ZIP in a fresh Windows 11
user account on the development PC. TES3NP opened, Discord sign-in worked,
the tester added a character in the launcher, and the character logged
into Morrowind successfully.

Clean-machine validation is pending. Account privileges and the Morrowind
folder picker are unverified for this run.

## November 17 clean Windows 11 Dell test

- Dell Latitude 7420, fresh Windows 11 Pro 26H2 x64, build `26300.9974`.
  The tester used their everyday Windows account. Account privileges and
  display scale were not recorded.
- The expected package is the rebuild at `cdca0fe7a9fe25d1ca038fecc99effdd04d74613`,
  listed above. The Dell ZIP hash output was not included in the report.
- **PASS reported:** First launch, desktop shortcut creation, Discord sign-in
  and live Game Chat, and missing-Morrowind setup. Steam GOTY was detected
  after installation.
- **PASS reported:** Official Expansion Pack download and import. The saved
  ESP existed and its SHA-256 matched the import record.
- **FAIL:** After a successful import the button showed Disabled, while the
  next click disabled the entry in OpenMW. After disabling it, enabling
  again offered another install even though the pack was on disk.
- **FAIL on clean baseline:** The bundled TES3MP client exited before the
  game window with `0xC0000135`, including on a direct `--help` probe. The
  probe subsequently printed help and exited zero after the Visual C++ x64
  runtime troubleshooting step. The client still printed current-directory
  errors in the Unicode extraction path. The tester reported that the game
  window opened after removing the accented character from the folder name.
  Reaching the NP world is still unverified for this run.
- The launcher logged a WebView2 detection warning even though live chat
  worked. The tester reported a Discord sign-in window scaling issue and a
  Windows Security removal followed by successful restore. The detection
  name and affected file were not confirmed in Protection History.
- **SKIP:** Standard-user coverage and public updater flow are pending.

## November 17 Dell retest after the Expansion Pack and chat fixes

- Build source `191012e76667afee45b4e36a69779c558f62e9d7`. The Windows
  build, Expansion Pack import and toggle fixtures, compiled launcher
  `--check`, and final ZIP integrity check passed. Chat Host published with
  the existing WindowsBase `MSB3277` warning.
- `tes3np-windows.zip` SHA-256
  `4ccea0f543176bc8a0809edd44989ab5fb37d81d6afa9b424eb453a2b107a9c7`
  matched on the development PC and the Dell after USB transfer.
- The tester opened the verified package on the same Dell and Windows
  profile, with Steam GOTY and the previous runtime troubleshooting already
  in place. The extraction folder used an ASCII name.
- **PASS:** The launcher checked for an Expansion Pack update, reused the
  verified local pack, and showed Enabled plus the success confirmation.
  The tester then reported successful login into the NP world.
- **FAIL:** The follow-up screenshots show the Discord form collapsing at
  the smallest launcher preset, oversized chat and sign-in at larger sizes,
  and the release notes exceeding the launcher bounds at 50%. Some launcher
  labels clipped, and resetting appearance exposed both launcher frames.
  Repeat the visual checks with the sizing corrections.
- **Pending:** A full disable/re-enable cycle was not confirmed on this
  ZIP. This build used the fallback markerless client. Repeat final
  clean-machine login acceptance with the intended source-built console
  client and a standard Windows user.

## November 19 developer regression with the source-built console client

- Source commit `19a67990312dba136b8b7bce7d2ab00a4d8707b1`.
- ZIP `dist/tes3np-windows.zip` with SHA-256
  `20a8ccd7209fdeb8020c0ee29105ba14e177fbdd57b1021425d28e4647b044e7`.
- The complete Windows build and compiled launcher `--check` passed. Source,
  Chat Host architecture, diagnostic privacy, Expansion Pack import and toggle
  fixtures, and native picker COM smoke checks passed.
- The source-built console client was staged with 45 matching DLLs and printed
  `--help` from the package. ZIP verification with `--require-console-client`
  passed. Chat Host compiled and published with the existing WindowsBase
  `MSB3277` warning.
- Updater source, metadata and tamper checks passed, along with twelve isolated
  transaction and rollback scenarios. The transcript ends after starting the
  extracted launcher. Packaged owned-menu smoke and clean-machine results
  for this ZIP are pending.

## November 19 developer retest with the compiled menu probe

- Source commit `96e95f5776e0b8f3ff1ba83a385563db3e0711d9`.
- ZIP `dist/tes3np-windows.zip` with SHA-256
  `c8465dc09601236f04752422c78a37a0f8d9d632eb1d110004a9b9d42cc2b394`.
- **PASS:** The compiled launcher menu probe exited `0` and reported 50–100%
  menu scaling, owner tracking, work-area bounds and font release. The display
  refresh and release-note row checks passed at 50% and 100%.
- **PASS:** Full Windows build, compiled `--check`, ZIP integrity, packaged
  source-built TES3MP console client `--help`, and offline updater fixtures,
  including twelve transaction and rollback scenarios. The existing
  WindowsBase `MSB3277` warning remained.
- Clean Windows standard-user acceptance for this ZIP is pending.

## November 19 second-PC console probe

- The transferred ZIP for `96e95f5` matched SHA-256
  `c8465dc09601236f04752422c78a37a0f8d9d632eb1d110004a9b9d42cc2b394`.
- The bundled client ran from an extraction path with spaces and an accented
  character. `tes3mp.exe --help` printed the command options and exited `0`
  after three `Error 3 when changing current directory` warnings.
- At the pinned TES3MP revision, `components/files/windowspath.cpp` reads
  the EXE path with `GetModuleFileNameW` and passes the encoded path to
  `SetCurrentDirectoryA`. The launcher already passes the executable's
  directory as the working directory.
- **PASS on ASCII path:** A fresh extraction of the same verified ZIP to a
  path with spaces and ASCII-only characters printed the normal help text
  with no directory warnings in the captured output and exited `0`.
## November 19 fresh-device launcher acceptance

- Tested the `96e95f5` ZIP identified above on the second PC. The tester
  confirmed that TES3NP opened from a fresh extraction in an ASCII path
  and reported that the launcher features they exercised worked.
- **PASS in the diagnostic log:** First startup, the missing-Morrowind setup
  prompt, three saved-character logins using the bundled client, manual
  New Adventure startup, and a normal process exit.
- **PASS in the diagnostic log:** Official Expansion Pack discovery, local
  package import, and a subsequent pre-launch pack check followed by a
  successful bundled-client login.
- **Pending:** The startup update availability check was unavailable. The
  `update-feed` branch was absent when checked. The stock public .20-to-.21
  update still needs a live test after the approved publication and bridge.
- Windows account privilege and DPI details were not captured for this run.
  The final ZIP from the reviewed release source still needs its own evidence.

## November 19 build from reviewed main

- Source commit `c2d8ed4a59c536e9b39a7fa065cf2ef0bf49290a`.
- Candidate `tes3np-v0.1.21-alpha-windows.zip`, 140,035,216 bytes, with SHA-256
  `f3f17d41ff0c9450196be366d5270d4e1bc8a2b373424d19dd76ba4b85b8c4f3`.
- **PASS:** Full developer Windows regression, including compiled launcher
  checks, compiled menu smoke with exit code `0`, release-note layout at 50%
  and 100%, and updater transaction and rollback fixtures.
- **PASS:** The versioned ZIP passed package validation with
  `--require-console-client`. The staged client used the tested executable
  and 45 DLLs and printed `--help` during the build. The generated channel
  metadata and independent file hash agreed.
- **Pending:** Second-PC acceptance of this exact release ZIP.

## November 19 developer build with final Race wording

- Source commit `00f0c93fb4581a2c79d9502137297d77acdde4f9`.
- Candidate `tes3np-v0.1.21-alpha-windows.zip`, 140,035,207 bytes, with SHA-256
  `ee3de2d7c6958215ef0c7cf25f49ce76c1a8db77f8a39a5c64c595ec5027cd4d`.
- **PASS:** Windows build, compiled launcher `--check`, and compiled menu
  smoke at 50% and 100%. The source, Chat Host architecture, diagnostic
  privacy, Expansion Pack fixtures, and native picker COM checks passed.
  Chat Host built with the existing WindowsBase `MSB3277` warning.
- **PASS:** The versioned ZIP passed `--require-console-client`. The
  packaged client printed `--help` with the 45 matching DLLs during the
  build. Generated update metadata and the independent file hash agreed.
- **PASS reported:** The maintainer tested the packaged launcher and
  confirmed the Race wording was updated throughout the areas checked.
- **Pending:** Standard-user acceptance and the upgrade and rollback
  checks on the exact final ZIP. The earlier second-PC report covers
  the `96e95f5` ZIP identified above.

Record the source commit, SHA-256, Windows versions, fresh standard-user
install results, and upgrade and rollback results for the final ZIP built
from the reviewed release source. Use the [acceptance checklist](ALPHA-COMPATIBILITY-CHECKLIST.md).
