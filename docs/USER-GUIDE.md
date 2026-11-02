# Using tes3np

## Launching characters

- **Play** beside a character launches it without changing your saved default.
- Tick one character to make it your default. **Launch <character>** uses that choice.
- **Launch All & Close** appears with two or more saved characters. It launches them in list order, waits 10 seconds after each configured loading delay, closes that game client, and moves to the next. The launcher stays open afterward. Its explanation includes a saved **Don't show me this again** option.
- **Auto reconnect on close or crash** is saved separately for each character under Edit. It defaults to on and applies on the next launch. Turn it off if you want to close the game without it restarting. In a batch, a failed character with reconnect off is skipped.
- **Start New Adventure** launches once without saved login input or automatic recovery.

**Wipe Character Data** appears when at least one character exists. It asks for confirmation before removing all saved character credentials and the favorite selection, and stops active automation. It does not delete in-game characters or the executable setting. Export first if you need a backup. With no characters, Add character moves beneath the introductory description and Import Data becomes available.

Up to 10 characters can be saved. Remove asks for confirmation. Adding a character does not change your ticked default.

With no saved characters, startup opens the launcher. After setup is verified and a character exists, startup offers **Launch <character>**, **Manage Characters**, or **Open Launcher**, preferring the ticked character and otherwise using the first saved character.

Closing the character page returns to the main launcher, including after opening it from the startup choice.

Use the tray menu to **Open Launcher** or **Stop game recovery**. Quitting the launcher stops automation and leaves any running game open.

## Moving to another computer

**Export Data** at the lower-right of the character book saves a portable INI backup containing characters, passwords, login delays, reconnect choices, the ticked default, executable path and launch-all explanation preference. Export warns that passwords are readable in this file. Keep it private; do not share or commit it.

With an empty character list, this button becomes **Import Data**. Select a backup created by Export Data. Import validates it before replacing settings and encrypts passwords for the destination Windows account. An executable path that does not exist there is cleared; use Browse to select TES3MP again. Copying the normal encrypted `settings.ini` is not a portable password backup.

## Login and recovery

Login uses foreground keyboard input and each character's configured delays. Avoid typing during credential entry. These delays do not verify the contents of login screens or prove that the server accepted the login or awarded daily points.

Status tooltips appear inside the active TES3MP game window during login. They show countdowns and current steps, disappear when the configured character-loading wait finishes, hide when you switch away, and never attach to the terminal. Crash monitoring continues without a tooltip.

The controller checks its tracked process and visible SDL game window every second. A terminal window does not qualify. Game-window startup allows 30 seconds; enabled recovery waits 5 seconds before retrying. Only the launched process is managed.

**Our Wiki** opens https://wiki.nerevarineprophecies.com/Main_Page. **Macros** opens the local ZIP macro manager. Import `.ahk` files directly or ZIP packages, choose their main `.ahk` script, then run, stop or remove them. See [Macro packages](MACRO-PACKAGES.md) for the ZIP format and requirements. Imported scripts can execute code; only run packages you trust.

## Saved data

Settings are stored in `%APPDATA%\tes3np\settings.ini`, separate from the extracted application. Passwords are encrypted with Windows DPAPI under the current Windows account. Do not commit or share your settings file.

Loading-overlay failures are recorded in `%APPDATA%\tes3np\render-errors.log`. Patching activity is recorded in `patch-all.log` and patch failures in `patch-errors.log` in the same folder. Logs omit personal paths and credentials. Patch backups are stored separately under `patch-jobs`.

**Expansion Pack:** The original upper-left **Expansion Pack: Enabled/Disabled** button controls future game load order; close all games before changing it. If the server rejects your plugin/load-order configuration, the **Your Plugins Don't Match the Servers** dialog checks the official Nerevarine Prophecies Discord channel for its newest available ZIP attachment. Future ZIP uploads in the same channel are picked up without hardcoding the current expansion version. Discord sign-in, permissions or markup changes can prevent discovery; the dialog also provides the direct channel link. Click the ZIP to open its actual Discord attachment in your default browser, where the file can be downloaded. If the browser download is cancelled or fails, click the ZIP filename again or use the dialog's **Download ZIP / Retry** button; both can request another download without restarting TES3NP. The mismatch prompt stays open during downloads. Once Discord finds the latest ZIP, its download area switches to a launcher-owned clickable filename while the embedded Discord view is hidden. Both this filename and **Download ZIP / Retry** open the signed ZIP using a separate Windows URL-handler process, so you can retry without restarting TES3NP. No persistent download-status text is shown. If a current Expansion Pack still doesn't fix the rejection, select **Copy Diagnostic Info** and paste the resulting structured report into the server's Discord bug-reports channel. It includes only basic launcher/configuration flags, counts, and fixed error indicators—not raw logs, player/mod names, computer paths, login information or authentication tokens. Once the download completes, return to TES3NP and select **OK** to locate the ZIP and run the existing safe import worker. The embedded Discord view stays on the channel rather than attempting to download the large file itself. The Discord embed shares Game Chat's login and does not install anything automatically. If the embed cannot load, use the dialog's link to open the channel in Discord. Cancel closes the mismatch dialog.

Game Chat diagnostics are in `%APPDATA%\\tes3np\\chat-host.log`. Its
message archive lives under `%APPDATA%\\tes3np\\Logs\\`, and its Discord
browser profile is in `%APPDATA%\\tes3np\\chat-webview2\\`.
Happy Hour announcements appear directly in the small banner attached to
the launcher, with no extra activation popup. If an authenticated Discord
session previously saved a **genuine, still-active** announcement to the local
chat archive, its banner remains available even while you're signed out.
Signing in is required only to fetch new announcements or live chat. With no
matching local announcement, nothing is displayed until Game Chat can retrieve
one. An expired announcement also keeps the banner hidden. The obsolete
`happy-hour-last-seen.txt` marker from earlier test builds is no longer used.

**Resetting chat:** Back up the Roaming data directory first. Closing the
launcher and clearing the intended chat data resets the archive and stored
Discord session. The old Local AppData notification marker from pre-fix
development builds is not sufficient to restore an event or a fresh profile.
Do not delete all TES3NP Roaming data unless you also intend to remove saved
character settings and other launcher preferences. The built-in **Reset Launcher
AppData** command requires confirmation, stops Chat Host and launcher recovery,
and closes tes3np after removing data. Restart it afterward to create a clean
profile. If Windows cannot delete the folder, the launcher reports the failure
instead of claiming the reset succeeded.

