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
  Game Chat runtime and Morrowind launch verification for this build
  remain pending.

Record the source commit, SHA-256, Windows versions, fresh standard-user
install results, and upgrade and rollback results for the final ZIP built
from the reviewed release source. Use the [acceptance checklist](ALPHA-COMPATIBILITY-CHECKLIST.md).
