# v0.1.21-alpha asset distribution review

Status: PENDING_RIGHTS_REVIEW

This record covers the contents of the v0.1.21-alpha Windows ZIP.
Review ownership, redistribution scope, and notices against the exact ZIP
selected for release.

| Material | Evidence and open review |
| --- | --- |
| Expansion Pack | The .21 source tree and build manifest exclude the original Expansion Pack. The launcher can import a pack obtained from the official channel. Confirm the final ZIP excludes the historical payload. |
| Modified TES3MP client | Verify the packaged source-built console client, corresponding source, and notices against the [client provenance record](MODIFIED-TES3MP-SOURCE-PROVENANCE.md). |
| Launcher artwork, fonts, and documentation images | Match the [asset inventory](ASSETS.md) to the files in the .21 package and record the applicable licenses or permissions. |
| Third-party components | Match the notices to the final ZIP. The package checker requires the AutoHotkey and TES3MP notices. The self-contained Chat Host publishes license files from its resolved .NET, Windows Desktop, and WebView2 packages, and the ZIP checker requires those files. The source-built console client includes CrabNet's pinned license. |

Record the reviewer, date, supporting permission or license, and exact
ZIP SHA-256 when the .21 review is complete.

## Historical .20 release and repository visibility

Preserve the original .20 tag, versioned Windows ZIP, and checksum as shipped.
The .20 source tag and the existing public .20 ZIP each contain 142 Expansion
Pack files, including the original [asset notice](https://github.com/IAmShawn98/tes3np/blob/a77a1fac99845be4954323220f46535079b390b1/patches/expansion-pack/LICENSE.txt),
alongside the legacy client. The unversioned legacy feed assets are the
compatibility bridge for installing the approved .21 ZIP.

Making the source repository public would expose retained source history and
tags. Review what that visibility change exposes separately from the contents
of the .21 release ZIP.
