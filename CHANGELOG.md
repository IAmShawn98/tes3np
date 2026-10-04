# Changelog

## Build 143 — 2026-10-03

- Split entry wiring, lifecycle, renderer and window helpers into focused modules.
- Replace obsolete template/demo identifiers with launcher names.
- Centralize state, paths, endpoints, profile defaults and controller timings.
- Handle malformed saved character counts and enforce the ten-character load limit.
- Add collaboration documentation, issue/PR templates, formatting rules, CI and
  repeatable packaging. Retain the required payload EXE in Git.
- Preserve build 142's installer fixes and friendly setup-needed behavior.

Validation: static source, payload hashes and package integrity. Windows runtime
testing of the refactor is pending.
