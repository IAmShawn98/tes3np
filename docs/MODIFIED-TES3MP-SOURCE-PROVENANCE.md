# Modified TES3MP source provenance

Status: PENDING_FINAL_ZIP

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
its matching DLLs. See the [Windows evidence record](CLEAN-WINDOWS-TEST-RESULTS.md).

The old `patches/markerless/tes3mp.exe` in Git and in the published .20 ZIP
has SHA-256 `0066f76fa8898180dfdf2897152b8c33b252fecbd64d206ac9b94d5c79dc9b81`.
The older binary's exact source, build process, and modification authorship
are still unverified. Review it separately before publicizing Git history.

Complete this record using the exact Windows release ZIP. Record the source
commit, ZIP SHA-256, package-check output, packaged EXE and DLL manifest,
and the corresponding source and notices made available to recipients.
