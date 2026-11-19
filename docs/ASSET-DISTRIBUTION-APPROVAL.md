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

## November 19 review of the tested candidate

The developer build and second-PC test used source commit
`96e95f5776e0b8f3ff1ba83a385563db3e0711d9` and ZIP SHA-256
`c8465dc09601236f04752422c78a37a0f8d9d632eb1d110004a9b9d42cc2b394`.
The [Windows evidence](CLEAN-WINDOWS-TEST-RESULTS.md) records package
verification, the source-built client and matching DLLs, and the clean
device's launcher and game tests. Repeat package verification on the final
ZIP from the reviewed release source.

| Material | Evidence available | Still to record |
| --- | --- | --- |
| Launcher artwork and documentation images | The maintainer identified the original Morrowind launcher as the basis for `assets/backgrounds/launcher.png` and supplied a screenshot showing the stone frame, Morrowind title treatment, bear and horned creature. The [asset inventory](ASSETS.md) identifies the remaining artwork and portrait masters. The standalone resource generator lists the embedded artwork. The Chat Host has its own sign-in image. | Review any third-party elements in the recreated background, Character Book, UI artwork, Happy Hour artwork, headings, portraits, sign-in image and documentation images shipped in the final ZIP. |
| Mystic Cards font | [Bundled notice](../assets/fonts/MysticCardsFontLicense.txt) identifies the OpenMW and Pelagiad authors and SIL OFL 1.1. The build embeds both font and notice. | Confirm the final package contains that font and corresponding notice. |
| Discord symbol | The [asset inventory](ASSETS.md) identifies the Discord brand kit as its source. | Review the shipped account icon and sign-in artwork against [Discord's brand guidelines](https://discord.com/branding). |
| Client and runtime components | The tested build passed ZIP validation with the pinned console EXE and 45 DLLs, TES3MP, CrabNet and AutoHotkey notices, and the Chat Host runtime notices. | Verify the same materials and corresponding-source access against the final ZIP. |

On November 19, the maintainer confirmed that the background artwork was
recreated for TES3NP using the original Morrowind launcher as its reference.
The maintainer approved retaining that artwork and described both TES3NP and
Nerevarine Prophecies as noncommercial projects.

## Published guidance for adapted Morrowind artwork

The [Morrowind GOTY PC manual](https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/22320/manuals/mwgoty_pcmanual.pdf)
identifies the Morrowind name and logo as ZeniMax marks and points to the
game's license for the packaged materials. The [ZeniMax trademark and
brand guidelines](https://documents.bethesda.net/en/legal-information)
distinguish plain-text references to game titles from use of visual
brand assets and direct uses outside their guidance to an authorized
ZeniMax contact. Bethesda's [fan video policy](https://bethesda.net/en-US/news/bethesda-video-policy)
covers fan videos. No permission specific to bundling the adapted launcher
background in the TES3NP Windows ZIP was identified in these sources.

## Historical .20 release and repository visibility

Preserve the original .20 tag, versioned Windows ZIP, and checksum as shipped.
The .20 source tag and the existing public .20 ZIP each contain 142 Expansion
Pack files, including the original [asset notice](https://github.com/IAmShawn98/tes3np/blob/a77a1fac99845be4954323220f46535079b390b1/patches/expansion-pack/LICENSE.txt),
alongside the legacy client. The unversioned legacy feed assets are the
compatibility bridge for installing the approved .21 ZIP.

The maintainer confirmed that previous released versions are public and
that permission to make the development repository public has been obtained.
The confirmed cutover keeps `IAmShawn98/tes3np` private during preparation
and makes it public immediately before the approved .21 publication. This
visibility change includes retained source history and tags.

Publish the numbered .21 release and alpha feed from
`IAmShawn98/tes3np`. Keep `IAmShawn98/tes3np-releases` public during the
one-time .20-to-.21 bridge. Retire the legacy repository after the public
.22 release and its update feed have been verified. The release ZIP has
its own package and source review above.
