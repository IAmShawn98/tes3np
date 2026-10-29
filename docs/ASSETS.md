# Asset provenance

| Location | Origin | Notes |
| --- | --- | --- |
| `assets/` | Artwork supplied or developed for this launcher | No blanket asset license is assigned by this cleanup |
| `patches/markerless/tes3mp.exe` | Supplied markerless TES3MP 0.8.1 Win64 client | Preserve bytes; upstream licensing is separate from launcher source |
| `patches/expansion-pack/` | Supplied NP Expansion Pack v0.1 | Learwolf's September 30, 2026 `ASSET USAGE & COMMUNITY GUIDELINES` limits assets to NP's TES3MP server ecosystem; separate launcher ZIP redistribution is not expressly authorized. Project owner reports Learwolf is jiub and has verbally approved TES3NP; obtain and retain explicit written confirmation covering redistribution in our launcher ZIP before marking this release gate complete. Preserve original `LICENSE.txt` unchanged. |
| `patches/manifest.json` | SHA-256 inventory | Update hashes only when intentionally updating payloads |

Bethesda's base game masters are not included. The installer uses the player's
existing Morrowind GOTY installation. No launcher source license has been selected.
The repository owner should choose one before calling the project open source.
Do not replace the EP license with the launcher's future source license.
