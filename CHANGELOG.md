# Changelog

## v0.1.17-alpha — 2026-10-05

- Add safe public-alpha updating with validated manifests, SHA-256 verification, transactional installation, rollback protection, and release publishing checks.
- Add automatic launcher scaling for smaller and high-DPI displays, including proportional control and settings-window scaling.
- Redesign Launcher Settings with interface text sizing, enhanced readability, preview behavior, and modal interaction that prevents duplicate settings windows or background clicks.
- Restore the Quest & Conquer and Play Together artwork on the launcher and refine the main launcher layout.
- Improve themed-button rendering and click handling, including fixes for destroyed-control crashes, paint artifacts, and intermittently swallowed first clicks.
- Add Daily Login scheduling and integrate its controls with the Manage Characters layout.
- Refine character management layout, action-button sizing and spacing, and Launch Settings visibility while adding or editing characters.
- Redesign AppData tools with direct log-copy actions, AppData-folder access, clearer recovery guidance, and simplified controls.
- Reorder the main launcher so Our Wiki appears above Macros.

## v0.1.0-alpha — 2026-10-03

- Split entry wiring, lifecycle, renderer and window helpers into focused modules.
- Replace obsolete template/demo identifiers with launcher names.
- Centralize state, paths, endpoints, profile defaults and controller timings.
- Handle malformed saved character counts and enforce the ten-character load limit.
- Add collaboration documentation, issue/PR templates, formatting rules, CI and
  repeatable packaging. Retain the required payload EXE in Git.
- Preserve installer fixes and friendly setup-needed behavior from earlier development.
- Add a compiled Windows launcher with the custom tes3np icon and automatic GitHub Actions builds.

Validation: static source, payload hashes, package integrity, PowerShell parsing and
compiled-launcher validation. Full Windows GUI/TES3MP runtime testing is still required.
