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

Record the source commit, SHA-256, Windows versions, fresh standard-user
install results, and upgrade and rollback results for the final ZIP built
from the reviewed release source. Use the [acceptance checklist](ALPHA-COMPATIBILITY-CHECKLIST.md).
