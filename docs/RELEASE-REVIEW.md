# TES3NP release review

## v0.1.21-alpha

- Source commit: [`00f0c93`](https://github.com/IAmShawn98/tes3np/commit/00f0c93fb4581a2c79d9502137297d77acdde4f9)
- Windows ZIP: `tes3np-v0.1.21-alpha-windows.zip`
- ZIP SHA-256: `ee3de2d7c6958215ef0c7cf25f49ce76c1a8db77f8a39a5c64c595ec5027cd4d`
- TES3MP source: VERIFIED_SOURCE_AND_BUILD
- Asset distribution: PENDING_RIGHTS_REVIEW
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
See the [asset inventory](ASSETS.md).

### Windows testing

The exact ZIP passed the Windows package and menu checks. The maintainer
confirmed a fresh Windows 11 Pro x64 installation (build 26300) under a
standard user account. The diagnostics confirm launcher startup, Expansion Pack
import and disable, bundled-client login, and New Adventure. All 12 updater
transaction and rollback checks passed. The maintainer reported a successful
isolated `.20` → `.21` upgrade. Live download and feed verification follow
publication.

### Repository visibility and legacy updates

The maintainer confirmed permission to make the repository public, including
the history containing the `.20` source and its original Expansion Pack asset
notice. Preserve the `.20` tag, ZIP, and checksum. Keep the legacy release
repository available through the `.20` → `.21` bridge and retire it after the
public `.22` release and its update feed have been verified.

### Detailed records in Git history

- [Modified TES3MP source provenance](https://github.com/IAmShawn98/tes3np/blob/d10a9ac9539257b84d8a186252b4d80a123325a8/docs/MODIFIED-TES3MP-SOURCE-PROVENANCE.md)
- [Asset distribution review](https://github.com/IAmShawn98/tes3np/blob/d10a9ac9539257b84d8a186252b4d80a123325a8/docs/ASSET-DISTRIBUTION-APPROVAL.md)
- [Windows release test results](https://github.com/IAmShawn98/tes3np/blob/d10a9ac9539257b84d8a186252b4d80a123325a8/docs/CLEAN-WINDOWS-TEST-RESULTS.md)
