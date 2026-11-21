# TES3NP release review

## v0.1.21-alpha.1 — hotfix candidate (not published)

- Development branch: `Update/v0.1.22-alpha`; version staged in `src/state.ahk` as `0.1.21-alpha.1`.
- Player notes: the new `v0.1.21-alpha.1` section retains New Features, Improvements, and Bug Fixes. The historical `v0.1.21-alpha` body was checked against its published GitHub release and matches exactly.
- Windows CI checks at [`250ba505`](https://github.com/IAmShawn98/tes3np/commit/250ba5054ac5bea23a6b8a138d27a59460539564): updater/source and publication-history fixtures, updater metadata, transaction and rollback, Expansion Pack import/toggle, AHK compilation, compiled launcher `--check`, and owned menu tests passed.
- **Local Windows regression (maintainer log, 2026-11-20 ET):** The `Update/v0.1.22-alpha` checkout fast-forwarded from `d5fbb09` to `dddd6d7`, then `pwsh -NoProfile -File .\scripts\run-local-regression.ps1 -NoLaunch` completed with `PASS | Windows build and offline updater fixtures complete.` The build included source/privacy, Chat Host, Expansion Pack import/toggle, official TES3MP runtime, AutoHotkey compilation, compiled `--check`, compiled menu smoke tests, ZIP structure/integrity, categorized missed-update and installed-note checks, red `(1)` viewed-state contracts, version metadata, updater metadata/tamper fixtures, and isolated rollback/recovery fixtures. A nonfatal .NET `WindowsBase` MSB3277 warning remained. This was an **offline/no-launch** run: it does **not** verify interactive dialog rendering, native WinEvent login-card movement, real update installation, or live rollback. The ZIP's release-candidate SHA-256 was not supplied in the log.
- **Windows desktop validation (maintainer PowerShell log, after local `dddd6d7` build):** `dist/tes3np-windows.zip` SHA-256 `0C09C89A36D60C1EC4255B002E1E82C2062F924EBF1CFC4D7B30D89C5C14AA89`. The packaged `dist/local-build/tes3np.exe --check-game-login-card` returned exit code **0** on the maintainer's interactive Windows PC, establishing a passing native-window login-card smoke test there. `Start-Process` was invoked for that packaged EXE without PowerShell errors; this by itself does **not** verify actual GUI appearance or manual interactions. No player data was changed by the checks reported. CI's hosted runner failure remains recorded below. Still need human confirmation of installed version, cumulative categorized changelog, modal/scaling/scroll, and update notification behavior; real feed behavior requires a published hotfix. Do not publish without owner approval.
- **CI remains failed** at the existing login-card native WinEvent delivery smoke test (exit code 231). The [run log](https://github.com/IAmShawn98/tes3np/actions/runs/44866793691) shows the dummy game window moved to X=88 while the card stayed at X=90. A direct call to the existing location-change callback moved the card correctly to X=118, Y=108. This distinguishes the callback behavior from native event delivery on the hosted runner; it is **not** an interactive-Windows acceptance pass. The same smoke failure predates this hotfix on `main`.
- **50% launcher-scale screenshots (maintainer, Nov 20–21 ET):** The packaged candidate is visibly running as a compact, centered launcher on the Windows desktop; its Version Status gold modal shows `Build: v0.1.21-alpha.1`, an up-to-date message, `Release Notes`, category `New Features`, the original `v0.1.21-alpha` heading and bullets, a scrollbar, and both footer buttons. No obvious visual clipping or overlapping labels in the provided crop. The screenshot does not demonstrate scroll action, the later `.21-alpha.1` section, native movement in actual game play, or 100% scale. **Code review:** `GetUpdatePromptFitScale()` sizes the modal to available screen area (clamped 0.5–1.0), independently of the saved launcher scale, so the larger dialog beside a 50%-scale launcher matches current design.
- **50% corner-version regression and targeted patch (maintainer screenshots, Nov 20–21 ET):** Zooming the main-launcher screenshot shows only `tes3np` at bottom-left; the intended `v0.1.21-alpha.1` suffix is clipped, although the independent Version Status modal displays the full version. Root cause in `src/app/update-check.ahk`: the Text control was created with `h18` but no width, preventing reliable caption auto-sizing, as already documented for the update-dialog metadata controls. A targeted development-branch patch at `2e40fa66` now creates the label with both dimensions unspecified, reads its natural width, then assigns padded width and the original 18-height; the red `(1)` remains anchored to the final label width. Source regression guard updated at `303a1ada`. **Fix is source-reviewed and committed, not yet rebuilt or desktop verified.** The previously measured candidate ZIP SHA-256 belongs to the prior build and is not a hash for these new commits.
- **Rebuilt 50% corner-version candidate (maintainer PowerShell log, 2026-11-20/21 ET):** Local checkout fast-forwarded `dddd6d7` → `d994ef1`; `pwsh -NoProfile -File .\scripts\run-local-regression.ps1 -NoLaunch` completed `PASS | Windows build and offline updater fixtures complete.` Specifically, the updated source-contract assertions for caption natural-width measurement and final width/height passed, as did AHK compilation, compiled `--check`, menu smoke tests, packaged ZIP integrity, Chat Host/Expansion Pack checks, categorized update notes, metadata, tamper and isolated rollback fixtures. Nonfatal .NET `WindowsBase` MSB3277 warning remains. `Start-Process` was invoked on `dist/local-build/tes3np.exe` without PowerShell errors. **Maintainer subsequently confirmed visually on the rebuilt Windows launcher at 50% that the entire bottom-left version caption now displays correctly. This is a user-reported interactive visual PASS (no new screenshot supplied).** New candidate ZIP SHA-256 not yet recorded; the prior `0C09...AA89` hash is for the older pre-fix ZIP only.
- **Still pending:** scroll to and visually verify the `.21-alpha.1` entries under New Features, Improvements and Bug Fixes; 100% launcher-scale and other DPI desktop visual review; update preview and viewed/red `(1)` persistence against published data; actual update confirmation and rollback acceptance; broader Windows acceptance and an approved release source commit.
- **Installed history grouping proposed and source-implemented (2026-11-20/21 ET):** `ReadInstalledCumulativeNotes` now renders latest installed hotfix first, older installed hotfixes in descending version order, then the base release. Each version retains its own category headings and original bullet text. The missed-published-update preview continues to use the prior category-first formatter. This is a targeted presentation change to the existing scrollable Version Status panel, with no tabs, no feed or installer changes. Expanded compiled pure-data smoke checks cover single and multiple hotfixes, category preservation, ordering, and lack of duplicate version headings. **Not yet Windows-built, screenshot-tested, or approved for release.**
- **CI architecture-contract follow-up:** The first CI run for category simplification (workflow run `44868572758`) failed before updater tests because `scripts/check-chat-architecture.py` still required the superseded category-interleaved installed changelog and `Hotfixes` subcategory. Updated only that obsolete cross-module assertion to require the new version-first installed layout, preserved missed-published category formatter, legacy `Hotfixes` → `Bug Fixes` display compatibility, and unchanged dialog/viewport safeguards. **CI recheck and Windows rebuild remain pending.** Earlier grouping-only CI run `44868447956` passed compiled AHK/data smoke and updater tests but failed the already-known hosted WinEvent/login-card delivery fixture (231); the maintainer separately passed it on their interactive PC.
- **Hotfix-category simplification (maintainer decision, 2026-11-20/21 ET):** Removed the redundant `Hotfixes` change category from the unreleased `v0.1.21-alpha.1` notes. Both the installed version-grouped history and the missed-published-update preview now display fixes under `Bug Fixes`, while the version headings still identify the update as a hotfix. Legacy historical `### Hotfixes` input is mapped to `Bug Fixes` for display only; original published release bodies are not rewritten. New source checks cover category ordering and this legacy mapping. **Source is staged, not yet rebuilt or visually tested on Windows.**
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
