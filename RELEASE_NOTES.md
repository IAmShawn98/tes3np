# TES3NP Release Notes

## v0.1.21-alpha — unreleased

Changes since the last public release, v0.1.20-alpha.

### New Features

- **Game Chat:** Read live Nerevarine Prophecies Discord messages alongside the launcher.
- **Game Updates:** Read server announcements in the launcher and react to posts when signed in to Discord.
- **Bug reporting:** Send a report from **Launcher Data** with diagnostic logs and optional screenshots.
- **Bundled TES3MP:** The Windows ZIP includes the TES3MP 0.8.1 client and its dependencies.
- **Happy Hour notifications:** See an active Happy Hour and its remaining time on the launcher.
- **Plugin mismatch recovery:** If your plugins don't match the server's, the launcher helps you download the Expansion Pack and troubleshoot the problem.
- **TES3MP Setup:** Choose a custom TES3MP executable without replacing the bundled client.
- **Login Progress:** See your character's login steps in a dedicated progress window.
- **Species:** Select your character's species in **Manage Characters** to show its matching icon during login.
- **Original Character:** Choose **Original Character** in the **Species** selector to use a custom portrait.

### Improvements

- **Expansion Pack updates:** TES3NP checks for the official pack before character login or re-enabling an installed pack. The update prompt shows the installed version when it can identify it, shows the available version, and lets you install from Discord or select a local package.
- **Expansion Pack toggle:** See progress while enabling the pack and a single confirmation when it is enabled or disabled.
- **Launcher update channels:** Alpha, beta, and live builds check their own feeds and show when a hotfix is available.
- **Launcher Interface:** Improved window scaling, menu positioning, and dialog appearances for a more consistent experience.
- **Upload Expansion:** Install the Expansion Pack from a downloaded ZIP file or an extracted folder.
- **Diagnostics:** Improved diagnostics for mismatches and error handling.
- **Favorite character:** Your first added character is now automatically selected as your favorite.

### Bug Fixes

- **Character reconnect** — Edit a character to enable automatic reconnect after a crash. Closing the game normally leaves it closed.
- **Game Chat** — Fixed a blank chat panel after first-time sign-in that could require restarting the launcher. The loading message and scrollbar now appear during the transition into Game Chat.
- **Discord sign-in** — Expansion Pack checks open the dedicated sign-in window when needed and resume after you sign in. Sign-in requests made while Discord is initializing are also handled.
- **Manage Characters** — Fixed visible flashing when editing or deleting characters and reduced the delay when closing the page.
- **Manage Macros** — Fixed a brief redraw glitch when saving a macro name.
- **Morrowind setup** — Fixed launch attempts that could proceed with missing game files. The launcher now opens the Morrowind folder picker.
- **Expansion Pack imports** — Fixed imports that could fail when Windows briefly locked a file and removed a size limit that rejected the official Expansion Pack ZIP.
- **Character backups** — Fixed an import error caused by the launcher trying to update a removed TES3MP executable field while restoring game client settings.
- **Desktop shortcut prompt** — Fixed cases where the prompt could reappear after a choice had already been saved.
- **Launcher updates** — Fixed a Windows PowerShell encoding issue that could prevent the updated launcher from confirming startup.
- **AppData cleanup** — The launcher now clears stale partial downloads, temporary files, and obsolete launcher caches on startup.
- **Diagnostic privacy** — Removed sensitive details such as local file paths and private URLs from diagnostic logs and copied reports.

### Removed Features

- **Scheduled Events:** I decided to remove Scheduled Events because it both wasn't ready and doesn't align with how I currently envision the overall launcher operating. Pieces of this feature will return in future updates in some way.

