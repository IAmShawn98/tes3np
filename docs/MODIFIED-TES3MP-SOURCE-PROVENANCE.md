# Modified TES3MP source provenance

Status: VERIFIED_SOURCE_AND_BUILD

The v0.1.21-alpha release is intended to use the source-built TES3MP 0.8.1
Windows x64 console client. The recorded SHA-256 of the previously playtested
EXE is `9028acd49dd6d87df54daa1fd4c3ea393e5e80f3680d0b4ef01d364a0d28d50b`.
The release build expects 45 matching DLLs. The full list and individual
hashes are captured in `client-files.json` when the package is built.

- [Pinned TES3MP source](https://github.com/TES3MP/TES3MP/tree/68954091c54d0596037c4fb54d2812313b7582a1)
- [Pinned CrabNet source](https://github.com/TES3MP/CrabNet/tree/19e66190e83f53bcdcbcd6513238ed2e54878a21)
- [Build procedure, launcher patches, and CrabNet license](../research/markerless/README.md)
- [TES3MP license at the pinned source revision](https://github.com/TES3MP/TES3MP/blob/68954091c54d0596037c4fb54d2812313b7582a1/LICENSE)

Both TES3NP patches passed `git apply --check` against the affected files at
the pinned TES3MP source revision. The package checker validates the pinned EXE
hash, console subsystem, DLL hashes, build instructions, patches, and CrabNet
license when run with `--require-console-client`. The November 17 developer
ZIP passed this verification and the bundled client printed `--help` with
its matching DLLs.

The old `patches/markerless/tes3mp.exe` in Git and in the published .20 ZIP
has SHA-256 `0066f76fa8898180dfdf2897152b8c33b252fecbd64d206ac9b94d5c79dc9b81`.
The older binary's exact source, build process, and modification authorship
are still unverified.

## November 19 initial v0.1.21-alpha release candidate


- Package: `tes3np-v0.1.21-alpha-windows.zip`, 140,035,216 bytes.
- ZIP SHA-256: `f3f17d41ff0c9450196be366d5270d4e1bc8a2b373424d19dd76ba4b85b8c4f3`.
- The Windows build staged the recorded console EXE and 45 matching DLLs.
  The packaged client printed `--help`. The package checker passed with
  `--require-console-client` against the versioned ZIP.
- This package check verified the pinned EXE hash, PE console subsystem,
  each EXE and DLL hash in the bundled `client-files.json`, and the
  build recipe, patches, and CrabNet license in
  `licenses/TES3MP/markerless-source/`.
- The pinned TES3MP and CrabNet source license files were retrieved from
  their upstream repositories. The bundled CrabNet license source matched
  the pinned upstream license after line-ending normalization. The
  package's source recipe and notices identify the corresponding source.

## November 19 final v0.1.21-alpha release candidate


- Package: `tes3np-v0.1.21-alpha-windows.zip`, 140,035,207 bytes.
- ZIP SHA-256: `ee3de2d7c6958215ef0c7cf25f49ce76c1a8db77f8a39a5c64c595ec5027cd4d`.
- The Windows build verified and staged the approved console EXE and 45
  matching DLLs. The packaged client printed `--help` with those DLLs.
- The final versioned ZIP passed `--require-console-client`, which verifies
  the pinned EXE hash and console subsystem, the packaged EXE and DLL
  hashes, and the source recipe, patches, and notices.
