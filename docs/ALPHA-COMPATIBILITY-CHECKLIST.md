# TES3NP Windows acceptance checklist

When the owner chooses a release candidate, record its source commit, exact
ZIP filename and SHA-256, Windows version and display scale, privileges,
and game, WebView2, and tool versions where applicable. Test the extracted
ZIP in disposable Windows profiles and copies of game data. Record PASS,
FAIL, or SKIP with the tested build and evidence. Prior results below apply
to the builds tested.

## Local build and release evidence

- [ ] Run `scripts/run-local-regression.ps1` on Windows. Confirm the full
  launcher and Chat Host build, native picker smoke test, synthetic import
  and toggle, exact Windows package checks, and updater metadata and rollback
  fixtures. Use PowerShell 7 for the updater transaction fixtures.
- [ ] Check `--check-owned-menu-scaling`, including its font cleanup, in the
  final release ZIP with stdout and stderr captured. The packaged and source
  probes passed on the developer PC. See the
  [Windows evidence record](CLEAN-WINDOWS-TEST-RESULTS.md).
- [ ] Complete the three evidence records and gate in
  [RELEASING.md](RELEASING.md#release-evidence-gate). Record Windows
  acceptance against the ZIP hash selected for release.

## Fresh install, first launch, and interface

- [ ] On clean Windows 10 and 11 x64 as a standard user, extract to a writable
  path with spaces and Unicode. Exercise first startup without development
  tools, with and without WebView2. Missing chat must leave the game usable.
  Verify missing package files produce an actionable error and moving the
  launcher folder preserves settings in AppData.
- [ ] On a complete fresh install, accept the desktop shortcut on one clean
  profile and decline it on another. Verify the saved choice on restart and
  the shortcut target. The incomplete/source build skips this prompt.
  Verify GOTY and Discord prompts appear only when their features need them.
- [ ] Test missing GOTY from a saved character and Start New Adventure.
  **Not Now** postpones the picker until the next game launch. Test Steam,
  GOG and a manually selected folder, selecting Game Data Files itself and
  invalid folders, and confirm all three masters are required.
- [ ] At Windows 100%, 125%, and 150% DPI, test Automatic and the launcher
  presets from 50% through 100%. Move the launcher and use a second monitor
  if available. Confirm settings, character pages, and child dialogs center
  relative to their actual owner, clamp to the work area, and scale without
  clipped art, controls, or hitboxes.
- [ ] Open and close fresh and cached pages repeatedly, including rapid
  clicks, Esc, and scale changes. Verify first-frame rendering, no black
  flash or desktop exposure, the full-width Settings Close button, and
  immediate Character Book Close without stale art or lost editor state.

## Characters, login, macros, and game client

- [ ] Add, edit, remove, and reach the ten-character limit. The first
  character is auto-favorited, the one-time favorite-switch prompt respects
  Yes and No, and later switches and restart preserve one favorite.
  Exercise old or empty selections, import/export, wiping local data,
  per-row Play, and normal preferences and login delays.
- [ ] Verify the ten stock species and **Original Character**. Import
  supported portrait formats, inspect the centered 512 × 512 result, test
  invalid or oversized images, cancel and missing-file fallback. Verify the
  selected race is displayed, the portrait chooser keeps the book visible,
  and the custom portrait survives restart and appears on consecutive
  logins. The portable INI preserves supported settings and species.
- [ ] Run saved character and manual login, including short saved delays,
  terminal-only startup and up to four clients. Verify the centered
  four-stage login card, correct icons, progress, three-second close, and
  focus behavior. Idle and legacy scheduler data must launch nothing.
- [ ] Exercise opt-in reconnect after a genuine crash or server reset,
  disabled reconnect, and normal game or console exit. Check the one
  recovery attempt and retained login/profile data.
- [ ] Run AHK, ZIP, and linked EXE macros. Test zero, one, five, and more
  than five entries, wheel and drag scrolling, inline rename, editor/cancel
  transitions, persistence, and Run/Stop/Remove. Check layout and controls at
  both scale extremes. Test single-script and multi-script ZIPs, a manifest
  with a nested entry script, Unicode and spaced paths, and rejection of
  malformed or unsafe archives before any write outside staging. Removing
  a linked app entry or closing TES3NP must leave that app intact.
- [ ] Switch between the included and custom game clients with optional
  dependencies. Replace a custom EXE with different bytes of the same size
  and timestamp to test cache invalidation. Interrupt a staged custom-client
  replacement and confirm recovery to the previous configuration.

## Expansion Pack, Game Chat, and diagnostics

- [ ] Test missing or empty ESP, valid ESP in a separate OpenMW data
  directory, installed-only toggling, expected prompts with active clients,
  and preservation of unrelated mods and load order. Test old-to-current
  pack update before login or enabling, and a second launch with the current
  pack.
- [ ] Test signed-out and signed-in Discord handoffs for missing packs and
  plugin mismatch. Confirm one sign-in window, **Not Now** and reopen,
  download/retry, manual selection, and cancel without writes. Use both ZIP
  and extracted folder imports in a disposable game directory. Exercise
  read-only/low-space failure, a sharing lock, restart recovery, and a
  successful reimport. Confirm the retired Install/Repair controls and
  embedded v0.1 payload are absent.
- [ ] Test clean Discord sign-in, live chat, artwork, images, scrolling,
  first-login loading, and modal-window behavior. With each popup visible,
  change between Automatic, 50%, 80%, and 100% and reject one preview.
  Check the sign-in title, instructions, close button, logo, fields and
  sign-in actions. Check the chat frame and header, loading text, feed text,
  images, scrollbar arrows and thumb drag at each size. Confirm the popup
  stays on the monitor and the scale restores on a rejected preview.
  Verify genuine Happy Hour
  detection in live and saved chat, signed-out display while active, and
  removal at expiry.
- [ ] Inspect fresh launcher, chat, updater, and import diagnostic exports.
  Verify diagnostic privacy, final newlines and continued appends, and
  versioned historical log migration without mutating private profiles,
  Discord state or import journals. Run the local privacy audit and test
  journal recovery in a disposable copy. Exercise bug reports with logs and
  screenshots and verify the report preview and retained attachments.

## Updater and distribution

- [ ] On a disposable Windows install, exercise a complete upgrade with
  profiles, delays, custom overrides, chat preferences and shortcut choice.
  Test rollback, restart confirmation, conflicting workers or running games,
  unavailable storage, and unrelated file preservation.
- [ ] Verify the approved channel manifest, published ZIP and checksum.
  After the approved public bridge update, use the normal update button in
  the stock .20 launcher and confirm it restarts on .21 with user data and
  can reach the new alpha feed. See [the bridge runbook](RELEASING.md#publish-the-one-time-v0120-alpha-bridge).

## Prior verification

| Evidence | Verified scope |
| --- | --- |
| November 2 Windows acceptance | Build and offline updater checks passed. The tester also accepted characters/favorites, macros, custom-client settings and backups, Game Chat and Happy Hour, and Expansion Pack import/toggle. |
| November 5 build `24a2359` | Full Windows build and ZIP validation passed. Local and copied-log privacy checks passed within their recorded scope after a legacy importer result repair. Categories with no records were skipped. |
| November 13 build `ec11b6f` | Full Windows build, twelve updater transaction scenarios, and reported live development-PC checks passed. |
| Development bridge build `23e0212` | Public .20 launcher code installed and restarted the candidate in the isolated test, preserving saved character and preferences. An earlier intentional failure restored .20. |
| Second-PC private bridge | The tester reported discovery, install, restart confirmation, candidate executable hash match, and retained game and data. The public-feed upgrade and final ZIP acceptance are still open. |
| Recent feature checks | Interrupted Expansion Pack import recovered on restart and a fresh import succeeded. The tester reported clean-profile Discord sign-in, game launch, missing-Morrowind handling on a separate PC, and custom TES3MP setup copy and layout acceptance. Record machine and candidate identity for the release gate. |

Earlier reports and exact evidence remain in the
[pre-consolidation docs](https://github.com/IAmShawn98/tes3np/tree/aebc384e384a71daa4080fa8e69fbbcd9bcf1a82/docs).
The [second-PC test issue](https://github.com/IAmShawn98/tes3np/issues/4)
covers the private test scope.
