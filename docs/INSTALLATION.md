# Installing tes3np

You only need to do this setup once. The launcher installs the supplied server patches for you.

## 1. Prepare your game

Install Morrowind Game of the Year Edition, including Tribunal and Bloodmoon. Download and extract TES3MP **0.8.1 for Windows 64-bit**. Install AutoHotkey **v2** so Windows can open the launcher.

## 2. Download the launcher

On the tes3np GitHub page, click **Code → Download ZIP**. Right-click the downloaded ZIP and choose **Extract All**. Open the extracted folder; you should see `tes3np.ahk` alongside folders such as `src`, `assets`, `scripts`, and `patches`.

Move that entire folder into the TES3MP folder containing `tes3mp.exe`. Do not run it from inside the ZIP or move just the `.ahk` file.

## 3. Run setup

Double-click **tes3np.ahk**. If the launcher shows **Patch Tes3mp**, open it.

Check the suggested locations. Use **Browse** if one is wrong:

| Location | What to choose |
| --- | --- |
| TES3MP folder | The folder containing `tes3mp.exe`. |
| Morrowind folder | The folder containing Morrowind's existing `Data Files` folder. |
| OpenMW configuration | Your active `openmw.cfg` file. The usual location is `Documents\My Games\OpenMW\openmw.cfg`. |

Close the game and the OpenMW Launcher before installing. Read the Expansion Pack license, then click **Install / Repair**. The loading panel shows progress. Leave the launcher open until setup finishes.

Setup installs the supplied crash-fix executable and NP Expansion Pack, then enables the pack. It also makes backups of files it changes. You do not need to copy these patches yourself.

If your installation already matches, the launcher opens the normal menu without replacing files.

## 4. Log in and play

- **New player:** Choose **Start New Adventure** and follow the game's login or registration prompts. This option does not automatically reconnect.
- **Returning player:** Choose **Returning Fetcher**, add your character name and password, and save. Choose **Play** beside the character. The launcher enters your details after the configured waits.

Keep the game window selected during automatic login and avoid typing while the launcher enters your details. Status messages explain what it is waiting for. After login, check the server's chat message to confirm the Expansion Pack is accepted.

Tick your preferred character to use it for quick launch next time.

## If something goes wrong

| Problem | What to do |
| --- | --- |
| Windows asks how to open `.ahk` files | Install AutoHotkey v2, then open `tes3np.ahk` again. |
| Setup cannot find your game | Use Browse and choose the folders listed above. Steam games may be installed on another drive. |
| Setup says official game files are missing | Make sure Morrowind, Tribunal, and Bloodmoon are installed. For an existing OpenMW setup, enable all three in the OpenMW Launcher first. |
| Login happens too soon or too late | Open Manage Characters, click Edit beside the character, and adjust its waiting times. |
| Closing the game makes it reopen | Turn off that character's automatic reconnect option under Edit. |
| Setup still fails | Copy the error message or take a screenshot and report it through the repository's Issues page. Never include your password or exported character file. |

For backup and repair details, see [Patching and recovery](PATCHING.md). For saved characters, exports, and macros, see the [user guide](USER-GUIDE.md).
