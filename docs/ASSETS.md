# Asset provenance

| Location | Origin | Notes |
| --- | --- | --- |
| `assets/` | Artwork supplied or developed for this launcher | No blanket asset license is assigned by this cleanup |
| `patches/markerless/tes3mp.exe` | Supplied markerless TES3MP 0.8.1 Win64 client | Preserve bytes; upstream licensing is separate from launcher source |
| `patches/expansion-pack/` | Supplied NP Expansion Pack v0.1 | Preserve the original `LICENSE.txt`; those terms govern its assets |
| `patches/manifest.json` | SHA-256 inventory | Update hashes only when intentionally updating payloads |

Bethesda's base game masters are not included. The installer uses the player's
existing Morrowind GOTY installation. No launcher source license has been selected.
The repository owner should choose one before calling the project open source.
Do not replace the EP license with the launcher's future source license.
