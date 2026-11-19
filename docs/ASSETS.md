# Asset provenance

| Location | Origin | Notes |
| --- | --- | --- |
| `assets/` | Artwork supplied or developed for this launcher | No blanket asset license is assigned by this cleanup |
| `assets/backgrounds/launcher.png` | Approved Morrowind-inspired launcher artwork with the beast pair composited directly into the background | Single-source background drawn by `src/ui/front-page.ahk`. The former separate `og-creatures-overlay.png` was retired; it is neither shipped nor drawn. Preserve native controls, Game Chat and Happy Hour overlays above this background. |
| `assets/icons/species/` | Morrowind-inspired race portraits approved for TES3NP | Ten 512×512 transparent PNG masters plus matching multi-resolution ICOs. Retain the race slugs and alpha channel. |
| `assets/icons/discord.png` | White symbol from the [Discord brand kit](https://discord.com/branding) on a Blurple tile | The signed-out account control uses this icon and the standalone launcher embeds it. |
| `patches/markerless/tes3mp.exe` | Supplied markerless TES3MP 0.8.1 Win64 client | Preserve bytes; upstream licensing is separate from launcher source |
| `patches/expansion-pack/` | Historical NP Expansion Pack v0.1 source assets only | The 142 legacy files remain in the `v0.1.20-alpha` source tree and older Git history. The alpha checkout excludes them from its source, build manifest, and standalone package. Current Expansion Pack downloads and installation are user-directed from official Discord. The original asset license and provenance must remain intact; these legacy assets are **not authorized for separate redistribution** by this launcher. |
| `patches/manifest.json` | SHA-256 inventory | Update hashes only when intentionally updating payloads |

Bethesda's base game masters are not included. The installer uses the player's
existing Morrowind GOTY installation. No launcher source license has been selected.
The repository owner should choose one before calling the project open source.
Do not replace the EP license with the launcher's future source license.

The login overlay resolves each saved character race to its matching
`assets/icons/species/<race-slug>.ico`. The `.png` siblings are the original
full-resolution editable/raster masters; the runtime loads `.ico` files.
Each pair must preserve transparency outside the gold crescent so the
login-window background shows through. Rebuild the launcher after changing
a race image; its standalone resources are embedded at build time.
