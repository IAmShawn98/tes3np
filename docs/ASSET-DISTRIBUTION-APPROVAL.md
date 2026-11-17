# Asset distribution review

Status: PENDING_RIGHTS_REVIEW

The Windows package and public Git refs both need review. The `.21` source
tree excludes the original Expansion Pack. The `.20` source tag and the
existing public `.20` Windows ZIP each contain 142 files under
`patches/expansion-pack/`, including Learwolf's original [asset notice](https://github.com/IAmShawn98/tes3np/blob/a77a1fac99845be4954323220f46535079b390b1/patches/expansion-pack/LICENSE.txt).
The notice limits the assets to the Nerevarine Prophecies ecosystem. The
scope of permission for the historical source and downloadable archive still
needs to be documented before making this repository public.

| Material | Evidence and open review |
| --- | --- |
| Original Expansion Pack | Identify written permission covering the retained source and archived Windows ZIP, or keep the affected history private while resolving distribution. |
| Legacy markerless executable | Present in Git history and the public `.20` ZIP. Review the older binary separately from the planned source-built payload. See [client provenance](MODIFIED-TES3MP-SOURCE-PROVENANCE.md). |
| Launcher artwork and documentation screenshots | The [asset inventory](ASSETS.md) identifies the main artwork, icons, and font. Verify which files and historical versions can be published. |
| Packaged third-party components | Match the licenses and notices to the exact ZIP, including TES3MP, CrabNet, AutoHotkey, the embedded Chat Host runtime, and fonts. The source-built package includes CrabNet's pinned license. |

Record the reviewer, date, supporting permission or license, and the approved
package and history scope here once reviewed.
