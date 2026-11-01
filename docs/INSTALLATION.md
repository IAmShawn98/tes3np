# Installing TES3NP (Windows)

TES3NP is a standalone launcher for Nerevarine Prophecies. **You do not need a separate TES3MP download**: the Windows package contains the TES3MP 0.8.1 runtime. You **do** need a legally installed copy of Morrowind GOTY (including Tribunal and Bloodmoon).

## Install the Windows build

1. Obtain the packaged Windows ZIP from the project's approved release or test build.
2. Extract the entire ZIP to a writable folder such as `Documents\\TES3NP`. **Do not run it inside the ZIP** and do not move `tes3np.exe` away from the accompanying `client`, `chat-host`, `assets`, and other folders.
3. Launch `tes3np.exe` normally. Administrative privileges are not required for the launcher itself.
4. For a returning account, choose **Manage Characters**. To create a new game account, choose **Start New Adventure**.

TES3NP stores launcher preferences and managed custom-client overrides under `%APPDATA%\\tes3np`. Installing a newer build into a different folder must not require deleting this user data.

## Optional Expansion Pack

The launcher works without the NP Expansion Pack. The upper-left **Expansion Downloads** button opens the Nerevarine Prophecies Discord download channel (`1555049936800718928`) in a raw WebView2 panel over the main launcher, sharing the existing Game Chat sign-in. Click again or close the panel to hide it. This first version only shows Discord: it does not install downloaded files or change the load order automatically.

To enable or disable an installed pack for future game clients, right-click the TES3NP tray icon and choose **Enable / Disable Expansion Pack**. Close TES3MP/OpenMW first. **Optional Expansion Pack** in the same tray opens the existing Install / Repair and Verify interface. TES3NP preserves unrelated mod entries and backs up the selected OpenMW configuration before changing it. When the active `openmw.cfg` or Morrowind installation is not found, configure the correct locations rather than guessing a path.

**Important:** The optional Expansion Pack modifies the selected Morrowind data directory and OpenMW configuration. The custom game client setting does not: it assembles an isolated merged runtime in AppData.

## Optional custom TES3MP executable

Open **Launcher Settings → Game Client Settings → Set Up Custom EXE**. Choose a file named `tes3mp.exe`, then either select a folder containing its additional dependencies/resources or choose **Use Bundled Dependencies Only**. TES3NP keeps the supplied files in managed overrides, and never changes the original bundled `client` directory. You can restore the original client and reactivate saved custom files later.

## Chat and prerequisites

The Windows package includes a self-contained chat-host executable; end users do not need the .NET SDK. Embedded Game Chat requires Microsoft's **WebView2 Runtime**. If WebView2 is unavailable, the game launcher should remain usable without chat. The **source build**, by contrast, needs the documented developer tools, including .NET 8 SDK, AutoHotkey v2, and a Windows build environment.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Morrowind is on another drive or installed through GOG/Steam | Select the actual Morrowind folder containing `Data Files\\Morrowind.esm`; do not select `Data Files` itself. |
| A custom TES3MP executable crashes | Reconfigure its optional dependency folder and use **Launcher Settings → Launcher Data → Copy Launcher Logs**. |
| Expansion Pack cannot be enabled | Close all game clients and review the specific error. Verify `openmw.cfg` and Morrowind data locations. |
| Chat does not load | Check whether WebView2 Runtime is installed; gameplay does not depend on Discord chat. |
| Character login timing is wrong | Edit the character's username/password/loading delays. |
| Windows denies file writes | Extract TES3NP into a writable user folder and ensure you have permission to change the Morrowind installation for optional content. |
| Settings appear missing after an update | Check `%APPDATA%\\tes3np`; don't reset launcher data before backing it up. |

For recovery information, see [Patching and recovery](PATCHING.md).

## Release note

Do not redistribute a public build until the corresponding source/build instructions for the modified GPL-licensed TES3MP executable and all applicable third-party notices are available.
