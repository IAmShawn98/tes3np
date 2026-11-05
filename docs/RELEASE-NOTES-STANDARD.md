# Player-Facing Release Notes Standard

This standard applies to `RELEASE_NOTES.md` and to the text published with a TES3NP release. The detailed `CHANGELOG.md` is for internal development history, diagnostics, failed experiments, and verification.

## Comparison and eligibility

- Compare the upcoming build against the **last publicly released version**, not intermediate private builds, commits, or unshipped experiments.
- Include only net changes that users can observe or benefit from. If a feature was added and then removed before release, do not mention it.
- A bug introduced and fixed entirely during closed development is not a public bug fix. Do not include it unless the released baseline also had that problem.
- Verify claims against the released baseline and the candidate build before publishing. Draft entries are not proof of release readiness.
- Never mention source files, commit hashes, internal tests, implementation details, speculative fixes, or release-gate status in player-facing notes.

## Required format

Use this structure, in order (omit any category with no eligible changes):

```markdown
# TES3NP Release Notes

## vX.Y.Z-channel — unreleased

Changes since the last public release, vPREVIOUS.

### New Features

- **Feature:** What new capability users now have.

### Improvements

- **Area:** What is better for users.

### Bug Fixes

- **Area:** Fixed a specific user-visible problem.

### Removed Features

- **Feature:** What previously available capability was removed.
```

- Keep **New Features**, **Improvements**, **Bug Fixes**, **Removed Features** in that order when present.
- Each entry is one short bullet, with a bold feature/area label followed by a plain-language outcome.
- Use one entry per distinct change. Do not repeat the same change in another category or split one change into multiple bullets.
- **New Features** describe newly available capabilities only; do not add bug fixes or improvements to those bullets.
- **Improvements** describe upgrades to existing capabilities, not entirely new features or bug fixes.
- **Bug Fixes** describe previously released defects and the corrected behavior.
- **Removed Features** describe functionality available in the previous public version that players can no longer use.
- Omit an empty category rather than inventing content. Do not add dates to individual bullets.
- Keep wording consistent and avoid marketing claims or implementation jargon.
- Update the comparison version and version heading for each new release. When published, replace `unreleased` with the actual release date.
- Preserve published release notes for historical versions; do not silently rewrite past release descriptions.

## Publication review

Before publication, review every bullet for baseline accuracy, user visibility, duplicate coverage, category fit, and confirmed behavior. Publish the approved player-facing text with the release; never substitute the internal development changelog.
