# Installing TES3NP (Windows)

TES3NP is a standalone launcher for Nerevarine Prophecies. **You do not need a separate TES3MP download**: the Windows package contains the TES3MP 0.8.1 runtime. You **do** need a legally installed copy of Morrowind GOTY (including Tribunal and Bloodmoon).

## Install the Windows build

1. Obtain the packaged Windows ZIP from the project's approved release or test build.
2. Extract the entire ZIP to a writable folder such as `Documents\\TES3NP`. **Do not run it inside the ZIP** and do not move `tes3np.exe` away from the accompanying `client`, `chat-host`, `assets`, and other folders.
3. Launch `tes3np.exe` normally. Administrative privileges are not required for the launcher itself.
4. For a returning account, choose **Manage Characters**. To create a new game account, choose **Start New Adventure**.

TES3NP stores launcher preferences and managed custom-client overrides under `%APPDATA%\\tes3np`. Installing a newer build into a different folder must not require deleting this user data.

## Optional Expansion Pack

The launcher works without the NP Expansion Pack. The **original top-left Expansion Pack: Enabled/Disabled button** is restored; use it to change the load order for *future* game sessions after closing TES3MP/OpenMW. The system tray retains the same toggle and Optional Expansion Pack installer.

If the server rejects a plugin/load-order mismatch, the existing **Plugins Don't Match the Server** dialog now embeds the latest downloadable ZIP file from Nerevarine Prophecies Discord channel `1555049936800718928` (using the Game Chat Discord session). Click the ZIP link to download it, then click **OK**. One native Windows Explorer-style browser opens: select the downloaded ZIP and click **Open ZIP**, or browse into the extracted package and click **Use This Folder** (you can also highlight a folder). The importer automatically detects which was selected, then stages and verifies the supported files with the existing backup/rollback process. If an unfamiliar file is present inside `Data Files`, installation stops rather than silently omitting it. **Cancel** closes the dialog. If the embedded ZIP cannot load, an ordinary link to the official Discord channel is provided. Downloads are not installed automatically. TES3NP preserves unrelated mods and backs up the selected OpenMW configuration before replacement.

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
