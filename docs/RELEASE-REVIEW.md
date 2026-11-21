# TES3NP release review

## v0.1.21-alpha.1 — hotfix candidate (not published)

- Development branch: `Update/v0.1.22-alpha`; version staged in `src/state.ahk` as `0.1.21-alpha.1`.
- Player notes: the new `v0.1.21-alpha.1` section retains New Features, Improvements, and Hotfixes. The historical `v0.1.21-alpha` body was checked against its published GitHub release and matches exactly.
- Windows CI checks at [`250ba505`](https://github.com/IAmShawn98/tes3np/commit/250ba5054ac5bea23a6b8a138d27a59460539564): updater/source and publication-history fixtures, updater metadata, transaction and rollback, Expansion Pack import/toggle, AHK compilation, compiled launcher `--check`, and owned menu tests passed.
- **Local Windows regression (maintainer log, 2026-11-20 ET):** The `Update/v0.1.22-alpha` checkout fast-forwarded from `d5fbb09` to `dddd6d7`, then `pwsh -NoProfile -File .\scripts\run-local-regression.ps1 -NoLaunch` completed with `PASS | Windows build and offline updater fixtures complete.` The build included source/privacy, Chat Host, Expansion Pack import/toggle, official TES3MP runtime, AutoHotkey compilation, compiled `--check`, compiled menu smoke tests, ZIP structure/integrity, categorized missed-update and installed-note checks, red `(1)` viewed-state contracts, version metadata, updater metadata/tamper fixtures, and isolated rollback/recovery fixtures. A nonfatal .NET `WindowsBase` MSB3277 warning remained. This was an **offline/no-launch** run: it does **not** verify interactive dialog rendering, native WinEvent login-card movement, real update installation, or live rollback. The ZIP's release-candidate SHA-256 was not supplied in the log.
- **CI remains failed** at the existing login-card native WinEvent delivery smoke test (exit code 231). The [run log](https://github.com/IAmShawn98/tes3np/actions/runs/44866793691) shows the dummy game window moved to X=88 while the card stayed at X=90. A direct call to the existing location-change callback moved the card correctly to X=118, Y=108. This distinguishes the callback behavior from native event delivery on the hosted runner; it is **not** an interactive-Windows acceptance pass. The same smoke failure predates this hotfix on `main`.
- **Still pending:** an exact Windows candidate ZIP and SHA-256, desktop UI review at tested DPI/scales, real window-movement verification, installed/uninstalled changelog display and red `(1)` dismissal/restart checks, update confirmation and rollback acceptance, and an approved release source commit.
- No `v0.1.21-alpha.1` public release, ZIP, checksum, or feed advancement has been performed. Do not publish without maintainer approval.

## v0.1.21-alpha

- Source commit: [`00f0c93`](https://github.com/IAmShawn98/tes3np/commit/00f0c93fb4581a2c79d9502137297d77acdde4f9)
- Windows ZIP: `tes3np-v0.1.21-alpha-windows.zip`
- ZIP SHA-256: `ee3de2d7c6958215ef0c7cf25f49ce76c1a8db77f8a39a5c64c595ec5027cd4d`
- TES3MP source: VERIFIED_SOURCE_AND_BUILD
- Asset distribution: MAINTAINER_APPROVED
- Windows testing: CLEAN_MACHINE_TESTED

### TES3MP client

The source-built TES3MP 0.8.1 Windows x64 console client and all 45 DLLs
passed package verification. The client printed `--help` from the staged
package. EXE SHA-256: `9028acd49dd6d87df54daa1fd4c3ea393e5e80f3680d0b4ef01d364a0d28d50b`.
See the [pinned source revisions, build instructions, patches, and notices](../research/markerless/README.md).

### Asset distribution

The Windows build verified that the standalone executable excludes the legacy
Expansion Pack payload. The final ZIP passed checks for the bundled AutoHotkey,
TES3MP, CrabNet, DejaVu, .NET, Windows Desktop, and WebView2 notices. Mystic
Cards ships with its SIL Open Font License notice. The maintainer approved
retaining the recreated launcher artwork. The review record still has open
entries for the distribution basis of Morrowind-derived art and Discord branding.
The launcher uses the player's Morrowind GOTY masters. The historical pack
and legacy markerless EXE have separate provenance. Preserve the pack's
original notice. The current ZIP includes the verified source-built client.

`assets/backgrounds/launcher.png` is the recreated launcher background.
`assets/icons/discord.png` comes from the [Discord brand kit](https://discord.com/branding).
Chat Host also bundles `game-chat/assets/DiscordInt.png` for sign-in.
The project has no blanket license for artwork or launcher source.

### Windows testing

The exact ZIP passed the Windows package and menu checks. The maintainer
confirmed a fresh Windows 11 Pro x64 installation (build 26300) under a
standard user account. The diagnostics confirm launcher startup, Expansion Pack
import and disable, bundled-client login, and New Adventure. All 12 updater
transaction and rollback checks passed. The maintainer reported a successful
isolated `.20` → `.21` upgrade before publication.

After publication, the public `.21` ZIP matched the tested SHA-256, and the
checksum and alpha feed matched that package. The maintainer confirmed that the
stock `.20` launcher on a fresh PC discovered and downloaded `.21` through the
public legacy bridge, restarted into `.21`, and retained working characters and
settings.

### Repository visibility and legacy updates

The maintainer confirmed permission to make the repository public, including
the history containing the `.20` source and its original Expansion Pack asset
notice. Preserve the `.20` tag, ZIP, and checksum. Keep the legacy release
repository available through the `.20` → `.21` bridge and retire it after the
public `.22` release and its update feed have been verified.
