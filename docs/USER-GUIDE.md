# Using TES3NP

## Install and update

1. Download the Windows ZIP from [GitHub Releases](https://github.com/IAmShawn98/tes3np/releases).
2. On Windows 10 or 11 x64, extract the entire ZIP to a writable folder such as `Documents\TES3NP`. Keep `tes3np.exe` with the other extracted files.
3. Run `tes3np.exe` as a standard user. When prompted for the game, select your Morrowind GOTY folder. It must contain `Data Files\Morrowind.esm` and both expansions, Tribunal and Bloodmoon.
4. Open **Manage Characters** to save a profile, or use **Start New Adventure** to log in manually.

TES3NP includes TES3MP and the AutoHotkey runtime. Game Chat uses Microsoft WebView2 Runtime. Gameplay is available without Game Chat.

Click the version number in the launcher to review and install updates. Keep
`%APPDATA%\tes3np` when replacing or moving the launcher folder so your saved
characters and settings carry over.

## Characters, login, and recovery

- Save up to ten characters and run up to four game clients at once. Your first saved character becomes your favorite. Use the tick box to change the favorite and the main-page launch button to play it. A character's **Play** button launches it without changing your favorite.
- The login window shows progress as TES3NP enters the character name and password. Avoid typing during this step. You can edit each character's login delays if the game needs more time.
- In a character's editor, enable **Auto reconnect on crash** to let TES3NP retry after a recognized crash. Closing the game normally leaves it closed. The tray menu offers **Stop game recovery**.
- **Wipe Character List** removes saved credentials and favorite selection from the launcher after confirmation. Your in-game characters remain on the server.

## Moving to another computer

**Export Data** in Manage Characters saves an INI backup of characters,
passwords, login delays, and the favorite. The backup stores readable
passwords. Keep it private.

With an empty character list, use **Import Data** to restore the backup.
TES3NP validates it before applying changes and encrypts passwords for the
current Windows account. Set up your game client and custom dependencies on
the destination computer.

## Optional Expansion Pack

The launcher can run without the pack. Close running game clients before
using the **Expansion Pack** button to enable or disable it for future sessions.

When a pack is missing or a server rejects the load order, follow the prompt
to download the current ZIP from the official Nerevarine Prophecies Discord
channel. Sign in to Discord if asked. In the download dialog, click the ZIP
filename. **Connect / Retry** retries discovery or downloading. If the
embedded view is unavailable, use its link to the official channel. For a
manual import, choose **Install ZIP** or **Repair / Install ZIP** and select
the downloaded ZIP or extracted folder. You can also use **Upload Expansion** with a package you
already downloaded. An import modifies the selected game data and OpenMW
configuration and backs up the files it changes.

If the server still rejects the load order, use **Copy Diagnostic Info** in
the mismatch dialog. The report includes configuration flags and error counts.
See [Expansion Pack import and recovery](PATCHING.md) for backup locations.

## Custom TES3MP client and macros

Open **Launcher Settings → TES3MP Setup → Choose a Custom EXE** and select
your `tes3mp.exe`. Choose **Use My Custom Exe** to use the included dependencies,
or **Choose Folder With Extra Files** if your build needs its own. Use
**Use Included TES3MP** to switch back and **Use Custom Setup** to reactivate
your saved configuration. The launcher stages the custom runtime separately
from your Morrowind installation.

The macro panel in **Manage Characters** accepts AutoHotkey scripts, ZIP
packages, and links to installed Windows applications. Only run macros from
sources you trust. See [Macro packages](MACRO-PACKAGES.md) for the format.

## Game Chat and Happy Hour

Sign in to Discord through **Game Chat** to fetch new messages and
announcements. If a genuine Happy Hour announcement is still active and is
already in the local chat archive, the launcher can show its countdown while
you are signed out.

## Troubleshooting and saved data

| Symptom | What to check |
| --- | --- |
| Game folder is missing or on another drive | Select the Morrowind install containing `Data Files\Morrowind.esm`, `Tribunal.esm`, and `Bloodmoon.esm`. |
| Custom client crashes | Check its dependency folder or try **Use Included TES3MP**. |
| Chat does not load | Check WebView2 Runtime and Discord sign-in. |
| Login types credentials too early or too late | Adjust the character's saved login delays. |
| Windows denies file writes | Move TES3NP to a writable folder. Optional Expansion Pack imports also need permission to modify the selected game data and configuration. |
| Settings appear missing after an update | Check `%APPDATA%\tes3np` before resetting anything. Back up saved data first. |

Use **Launcher Settings → Launcher Data → Copy Launcher Logs** when reporting
an issue. Review logs and screenshots before sharing. Keep character exports,
`settings.ini`, and the raw Discord archive private.

Game Chat logs to `%APPDATA%\tes3np\chat-host.log`. The Discord session lives
under `chat-webview2`, and the archive is under `Logs`. Close TES3NP and back
up its data before clearing individual chat files. **Reset Launcher AppData**
removes launcher data, including saved characters and preferences, after
confirmation. Restart TES3NP afterward to create a fresh profile.
