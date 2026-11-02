# TES3NP alpha release candidate — draft only

**NOT FOR PUBLIC DISTRIBUTION.** Release approval has not been given.

## Included features
- Standalone Windows x64 launcher including a TES3MP 0.8.1 client runtime.
- Character profiles, import/export, auto-login, and per-character recovery.
- Configurable optional custom executable and dependency overrides.
- Embedded Discord Game Chat with optional visibility modes.
- Global, optional NP Expansion Pack enable/disable with backups.
- Verified ZIP integrity and updater rollback/safety regression tests.

## Known limitations / dependencies
- Morrowind GOTY with Tribunal and Bloodmoon remains required; no Bethesda game data is included.
- Embedded chat requires WebView2 Runtime; the .NET SDK is not required for end users.
- WindowsBase MSB3277 build warning remains in the WinForms chat host dependency; existing tester reported chat operational.
- Latest shortcut-prompt persistence fix has not yet received a Windows retest.
- Clean Windows 10/11 environments without development tools still require testing.

## Release blockers
1. Obtain and make available **corresponding source and build instructions for the exact modified markerless TES3MP binary**. Identify modification author, version, and applicable license notices.
2. Confirm redistribution rights and notices for NP Expansion Pack, launcher artwork, and all other third-party assets.
3. Select/document licensing for TES3NP's own source, with separate third-party notices.
4. Pass clean-machine testing and repeat key workflows with the exact final ZIP.
5. Obtain explicit owner approval before creating a tag, enabling update metadata, or making a public GitHub release.

## Verification reference
The developer branch is `Update/v0.1.21-alpha`; see
`docs/ALPHA-COMPATIBILITY-CHECKLIST.md` for observed results and
outstanding scenarios. This document is intentionally not a claim of
distribution clearance.
