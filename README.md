# tes3np — Nerevarine Prophecies Launcher

Launch Morrowind on the Nerevarine Prophecies multiplayer server, save your characters, and install the server patches from one place.

## What you need

- A Windows PC.
- Morrowind **Game of the Year Edition**, installed with Tribunal and Bloodmoon.
- **TES3MP 0.8.1 for Windows 64-bit**, downloaded and extracted.
- For the source ZIP only: **AutoHotkey v2**, installed. The Windows executable package includes it.

Morrowind and TES3MP are not included in this download.

## Install the Windows launcher

Download the **tes3np-windows** package from the completed **Build Windows launcher** run under this repository’s **Actions** tab. Extract the downloaded artifact ZIP, then extract `tes3np-windows.zip`. Move the `tes3np` folder into your TES3MP folder and double-click **tes3np.exe**. Its custom icon is embedded, and no separate AutoHotkey installation is needed. Keep the accompanying folders together.

Choose **Patch Tes3mp** if shown, finish setup, then choose **Start New Adventure** or **Returning Fetcher**.

## Install from source in 4 steps

1. **Download:** Click the green **Code** button on this GitHub page, then **Download ZIP**.
2. **Extract:** Right-click the ZIP and choose **Extract All**. Move the extracted launcher folder into your TES3MP folder—the folder containing `tes3mp.exe`. Keep everything inside the launcher folder together.
3. **Set up:** Open the launcher folder and double-click **tes3np.ahk**. If **Patch Tes3mp** appears, click it, check the suggested locations, read the Expansion Pack license, and click **Install / Repair**. Wait for setup to finish.
4. **Play:** Choose **Start New Adventure** to log in yourself, or **Returning Fetcher** to add an existing character and save its login details.

Already patched? The launcher checks your installation and opens the normal menu when everything is ready.

Need help choosing folders? See the [step-by-step installation guide](docs/INSTALLATION.md).

## Your next launch

Tick a character in **Manage Characters** to make it your favorite. Next time you open tes3np, you can launch that character directly or open the launcher.

- **Play** launches any saved character.
- **Edit** changes a character's login details, waiting times, and automatic reconnect option.
- **Our Wiki** opens the Nerevarine Prophecies wiki.
- **Macros** lets you import and run macros you trust.

Removing a character from the launcher does not delete it in the game. Use **Export Data** before moving to another PC; the exported file contains passwords, so keep it private.

## Help

[Installation help](docs/INSTALLATION.md) · [User guide](docs/USER-GUIDE.md) · [Report a problem](../../issues)

Technical details: [Development](docs/DEVELOPMENT.md) · [Architecture](docs/ARCHITECTURE.md) · [Patching](docs/PATCHING.md) · [Releases](docs/RELEASING.md)
