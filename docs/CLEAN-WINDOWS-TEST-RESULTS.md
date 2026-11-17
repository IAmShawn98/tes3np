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
- `--check-owned-menu-scaling` exited 217. This is the probe's exception
  handler. The command captured the exit code, so the underlying exception
  remains to be identified from a run with output redirected.

Record the source commit, SHA-256, Windows versions, fresh standard-user
install results, and upgrade and rollback results for the final ZIP built
from the reviewed release source. Use the [acceptance checklist](ALPHA-COMPATIBILITY-CHECKLIST.md).
