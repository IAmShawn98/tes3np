# Contributing to tes3np

Read [Development](docs/DEVELOPMENT.md) and [Architecture](docs/ARCHITECTURE.md)
before changing shared state or rendering.

## Working together

1. Create a branch for one problem, such as `fix/login-retry` or `feat/macro-search`.
2. Keep commits focused. Describe the resulting behavior in the commit message.
3. Run `python scripts/project.py check` from the repository root.
4. On Windows, run `powershell -NoProfile -File scripts/check-powershell.ps1`.
5. Test the affected Windows workflow. State untested areas in the pull request.
6. Open a pull request using the supplied template and resolve review comments.

Use draft pull requests to coordinate changes to the same module. Prefer separate
changes to layout, session behavior, persistence and patch payloads. Use PascalCase
for public functions and camelCase for locals. Explicitly declare shared state in
functions that assign it. Avoid naming locals after AutoHotkey classes such as
`Gui`, `Buffer`, `Map` and `Array`.

Preserve INI keys unless a migration is included. Reuse the single watchdog and
existing paint pipeline. Do not add overlapping recovery timers, whole-book
redraws for scrolling or artificial loading waits. Store immutable owner HWNDs
on paint records. Release windows and callbacks before shutting down GDI+.

Never commit settings, character exports, logs, journals or credentials. Use
fictional data in reports. See [Asset provenance](docs/ASSETS.md) before distributing
artwork or payloads. No source license is selected by this cleanup.

## Packages

`python scripts/project.py package` creates a complete versioned ZIP in `dist/`.
Attach it to a GitHub Release rather than committing release archives.

`python scripts/project.py package --source-only` creates a smaller collaborator
package with code, artwork and the patch manifest. Copy the unchanged `patches/`
payload from a complete build before running its installer. Source-only checks
may use `check --allow-missing-payload`; complete release checks cannot.

See [Releases](docs/RELEASING.md) for GitHub setup and release gates. CI checks do
not exercise the Windows GUI or the game.
