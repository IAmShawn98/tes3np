; Build and CI probes use the launcher's real modules and process exit codes.
; Every recognized check exits before normal startup.

RunLauncherChecks(args)
{
    if !A_IsCompiled && args.Length = 4 && args[4] = "--check-update-state"
        CheckUpdateStateHandshake()
    if !args.Length
        return

    switch args[1]
    {
        case "--check":
            if !CheckBackupExecutablePaths()
                ExitApp(225)
            if !CheckExpansionRecoveryLaunchGate()
                ExitApp(226)
            if !CheckFirstRunOpenMWConfiguration()
                ExitApp(228)
            if !CheckExpansionPackToggleState()
                ExitApp(229)
            if !CheckGameLoginProgressFit()
                ExitApp(230)
            if !CheckCategorizedUpdateNotes()
                ExitApp(234)
            CheckCrashRecoveryProfiles()
        case "--check-expansion-ui":
            CheckExpansionProgressBindings()
        case "--check-expansion-window":
            CheckExpansionProgressWindow()
        case "--check-page-compositor":
            CheckPageCompositor()
        case "--check-cached-character-return":
            CheckCachedCharacterReturn()
        case "--check-owned-menu-scaling":
            CheckOwnedMenuScaling()
        case "--check-game-login-card":
            ExitApp(CheckGameLoginCardStacking() ? 0 : 231)
    }
}


; Pure data check: verify release and hotfix notes appear in the correct
; categories and retain source versions without opening a test-only UI.
CheckCategorizedUpdateNotes()
{
    base := {Version: "0.1.21-alpha", Label: "v0.1.21-alpha", Hotfix: false,
        Notes: "### New Features`n- **Chat:** Original feature.`n### Bug Fixes`n- **Login:** Original fix."}
    patch := {Version: "0.1.21-alpha.1", Label: "v0.1.21-alpha.1",
        Hotfix: true, Notes: "### New Features`n- **Alerts:** New indicator."
            . "`n### Improvements`n- **Pack:** Better verification."
            . "`n### Bug Fixes`n- **Pack:** Fixed disabling."}
    result := BuildCategorizedUpdateNotes([base, patch])
    if !InStr(result, "### New Features`n`n#### v0.1.21-alpha")
        || !InStr(result, "#### v0.1.21-alpha.1`n- **Alerts:** New indicator.")
        || !InStr(result, "### Improvements`n`n#### v0.1.21-alpha.1")
        || !InStr(result, "### Bug Fixes`n`n#### v0.1.21-alpha")
        || !InStr(result, "#### v0.1.21-alpha.1`n- **Pack:** Fixed disabling.")
        || InStr(result, "### Hotfixes")
        return false

    ; Installed history is grouped by version newest-first. The published
    ; update preview above must retain its category-first formatting.
    installed := BuildInstalledVersionNotes([base, patch])
    latest := InStr(installed, "## Latest Patch — v0.1.21-alpha.1")
    original := InStr(installed, "## Base Release — v0.1.21-alpha")
    if !latest || !original || latest >= original
        || !InStr(installed, "### New Features`n`n- **Alerts:** New indicator.")
        || !InStr(installed, "### Improvements`n`n- **Pack:** Better verification.")
        || !InStr(installed, "### Bug Fixes`n`n- **Pack:** Fixed disabling.")
        || !InStr(installed, "### Bug Fixes`n`n- **Login:** Original fix.")
        || InStr(installed, "### Hotfixes")
        || InStr(installed, "#### v0.1.21")
        return false

    ; Historical notes containing a Hotfixes heading must remain readable.
    newerPatch := {Version: "0.1.21-alpha.2", Label: "v0.1.21-alpha.2",
        Hotfix: true, Notes: "### Hotfixes`n- **Updater:** Newest fix."}
    stacked := BuildInstalledVersionNotes([base, patch, newerPatch])
    newest := InStr(stacked, "## Latest Patch — v0.1.21-alpha.2")
    earlier := InStr(stacked, "## Earlier Patch — v0.1.21-alpha.1")
    baseStart := InStr(stacked, "## Base Release — v0.1.21-alpha")
    if !newest || !earlier || !baseStart || newest >= earlier
        || earlier >= baseStart
        || !InStr(stacked, "### Bug Fixes`n`n- **Updater:** Newest fix.")
        || InStr(stacked, "### Hotfixes")
        return false

    ; Preview prominently shows only the latest missed version. The two
    ; earlier published versions are complete after expanding, not discarded.
    newestMissed := {Version: "0.1.21-alpha.3",
        Label: "v0.1.21-alpha.3 — November 23, 2026", Hotfix: true,
        Notes: "### Bug Fixes`n- **Updater:** Latest repair."}
    previousMissed := {Version: "0.1.21-alpha.2",
        Label: "v0.1.21-alpha.2 — November 22, 2026", Hotfix: true,
        Notes: "### Improvements`n- **Launcher:** Previous improvement."}
    previewSections := BuildPublishedPreviewSections([newestMissed, previousMissed, patch])
    if previewSections.EarlierCount != 2
        || !previewSections.HistoryVerified
        || previewSections.MissedVersions.Length != 2
        || previewSections.MissedVersions[1].Version != "0.1.21-alpha.2"
        || previewSections.MissedVersions[2].Version != "0.1.21-alpha.1"
        || !InStr(previewSections.Title, "Latest Patch — v0.1.21-alpha.3")
        || !InStr(previewSections.Compact, "**Updater:** Latest repair.")
        || !InStr(previewSections.Compact, "You also missed 2 earlier updates.")
        || InStr(previewSections.Compact, "**Launcher:** Previous improvement.")
        || !InStr(previewSections.Expanded, "**Launcher:** Previous improvement.")
        || !InStr(previewSections.Expanded, "**Pack:** Fixed disabling.")
        return false
    previewOnly := BuildPublishedPreviewSections([newestMissed])
    if previewOnly.EarlierCount != 0 || previewOnly.MissedVersions.Length != 0
        || !previewOnly.HistoryVerified
        || previewOnly.Compact != previewOnly.Expanded
        return false
    unavailablePreview := EmptyPublishedPreviewSections("Published release history is unavailable.")
    if unavailablePreview.Title != "" || unavailablePreview.EarlierCount
        || unavailablePreview.HistoryVerified
        return false

    published := []
    AddPublishedNoteRecords("### v0.1.21-alpha.1 — November 21, 2026"
        . "`n`n### Improvements`n- **Launcher:** Updated.", published)
    if published.Length != 1 || published[1].Version != "0.1.21-alpha.1"
        || !published[1].Hotfix || !InStr(published[1].Label, "November 21, 2026")
        || CompareUpdateNoteVersions("0.1.21-alpha.1", "0.1.21-alpha") <= 0
        return false
    return true
}

CheckGameLoginProgressFit()
{
    game := {X: -1300, Y: 20, Width: 1100, Height: 902}
    client := {X: -1292, Y: 51, Width: 1084, Height: 863}
    normal := FitGameLoginProgress(client, game, 1.5)
    if normal.Scale != 1.5 || normal.Width != 630 || normal.Height != 722
        || normal.X != -1065 || normal.Y != 110
        return false

    normal.GameWindow := game
    dragged := {X: 240, Y: -123, Width: game.Width, Height: game.Height}
    moved := TranslateGameLoginProgress(normal, dragged)
    returned := TranslateGameLoginProgress(moved, game)
    if moved.X != 475 || moved.Y != -33 || moved.Scale != normal.Scale
        || moved.Width != normal.Width || moved.Height != normal.Height
        || returned.X != normal.X || returned.Y != normal.Y
        || IsObject(TranslateGameLoginProgress(moved, {X: 240, Y: -123, Width: 320, Height: game.Height}))
        return false

    ; Both dimensions can limit the fit, including partially visible games
    ; on a monitor to the left of the primary display.
    for area in [{X: 30, Y: 50, Width: 640, Height: 360},
        {X: -320, Y: 40, Width: 275, Height: 500},
        {X: 1, Y: 7, Width: 320, Height: 240}]
    {
        fitted := FitGameLoginProgress(area, game, 1.5)
        if !IsObject(fitted) || fitted.Scale >= 1.5
            || fitted.X < area.X || fitted.Y < area.Y
            || fitted.X + fitted.Width > area.X + area.Width
            || fitted.Y + fitted.Height > area.Y + area.Height
            || (fitted.Width != area.Width && fitted.Height != area.Height)
            return false
    }
    return !IsObject(FitGameLoginProgress({X: 0, Y: 0, Width: 0, Height: 100}, game, 1))
}

ReportLoginCardSmokeFailure(stage)
{
    FileAppend("FAIL: login card Z-order smoke | " stage "`n", "*")
    return false
}

CheckGameLoginCardStacking()
{
    ; Disposable windows test the production placement against real Windows
    ; Z-order without launching a game or activating the card.
    game := Gui("-Caption +ToolWindow -DPIScale", "Game window fixture")
    cover := Gui("-Caption +ToolWindow -DPIScale", "Overlapping window fixture")
    card := Gui("-Caption +ToolWindow -DPIScale +E0x08000020", "Login card fixture")
    try
    {
        game.Show("NA x60 y60 w320 h320")
        cover.Show("NA x45 y45 w180 h180")
        card.Show("Hide x80 y80 w100 h120")
        for topOfBand in [0, -1, -2] ; Normal, topmost, then normal again.
        {
            if !DllCall("SetWindowPos", "Ptr", game.Hwnd, "Ptr", topOfBand,
                "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13, "Int")
                return ReportLoginCardSmokeFailure("stage " A_Index ": raise game window")
            layout := {X: 75 + A_Index * 5, Y: 80, Width: 100, Height: 120}
            foreground := DllCall("GetForegroundWindow", "Ptr")
            if !PositionGameLoginProgress(card.Hwnd, game.Hwnd, layout, A_Index = 1, true)
                || DllCall("GetWindow", "Ptr", game.Hwnd, "UInt", 3, "Ptr") != card.Hwnd
                || !DllCall("IsWindowVisible", "Ptr", card.Hwnd)
                || DllCall("GetForegroundWindow", "Ptr") != foreground
                return ReportLoginCardSmokeFailure("stage " A_Index ": position initial card and preserve focus")
            ; Raise the covering window in the same band. The card should
            ; stay above the game and below the covering window.
            if !DllCall("SetWindowPos", "Ptr", cover.Hwnd, "Ptr", topOfBand,
                "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13, "Int")
                return ReportLoginCardSmokeFailure("stage " A_Index ": raise cover window")
            if !PositionGameLoginProgress(card.Hwnd, game.Hwnd, layout, false, false)
                || DllCall("GetWindow", "Ptr", game.Hwnd, "UInt", 3, "Ptr") != card.Hwnd
                || DllCall("GetWindow", "Ptr", card.Hwnd, "UInt", 3, "Ptr") != cover.Hwnd
                || ((WinGetExStyle("ahk_id " card.Hwnd) & 0x8) != 0) != (topOfBand = -1)
                || DllCall("GetForegroundWindow", "Ptr") != foreground
                return ReportLoginCardSmokeFailure("stage " A_Index ": reposition card and verify z-order")
            WinGetPos(&x, &y, &width, &height, "ahk_id " card.Hwnd)
            if x != layout.X || y != layout.Y || width != layout.Width || height != layout.Height
                return ReportLoginCardSmokeFailure("stage " A_Index ": verify card bounds")
        }
        if !CheckGameLoginCardMoveTracking(game, card, layout)
            return ReportLoginCardSmokeFailure("stage " A_Index ": track game-window movement")
    }
    finally
    {
        card.Destroy()
        cover.Destroy()
        game.Destroy()
    }
    FileAppend("PASS: login card stays with the game during focus and position changes`n", "*")
    return true
}

CheckGameLoginCardMoveTracking(game, card, layout)
{
    global LoginProgressGui, LoginProgressShown, LoginProgressTracking
    original := GetGameLoginProgressWindow(game.Hwnd)
    layout.GameWindow := original
    layout.Scale := 1
    card.ProgressLayout := layout
    LoginProgressGui := card
    LoginProgressShown := true
    try
    {
        TrackGameLoginProgressWindow(game.Hwnd)
        if !IsObject(LoginProgressTracking) || !LoginProgressTracking.Hook
            return ReportLoginCardSmokeFailure("tracking: install movement hook")
        for offset in [28, -11, 43]
        {
            ; Move the fixture without running the login timer. Only the
            ; queued native window event can move the card to the new spot.
            if !DllCall("SetWindowPos", "Ptr", game.Hwnd, "Ptr", 0,
                "Int", original.X + offset, "Int", original.Y + offset, "Int", 0, "Int", 0, "UInt", 0x15, "Int")
                return ReportLoginCardSmokeFailure("tracking: move fixture game window")
            deadline := A_TickCount + 1000
            while card.ProgressLayout.GameWindow.X != original.X + offset && A_TickCount < deadline
                Sleep(10)
            if card.ProgressLayout.GameWindow.X != original.X + offset
            {
                ; Some hosted CI desktops suppress location-change events for
                ; their synthetic same-process tool windows. Exercise the real
                ; Windows event pipeline rather than calling our handler directly.
                FileAppend("DIAGNOSTIC: fixture produced no automatic location event; "
                    . "requiring native NotifyWinEvent hook delivery" Chr(10), "*")
                DllCall("user32\NotifyWinEvent", "UInt", 0x800B, "Ptr", game.Hwnd,
                    "Int", 0, "Int", 0)
                deadline := A_TickCount + 1000
                while card.ProgressLayout.GameWindow.X != original.X + offset && A_TickCount < deadline
                    Sleep(10)
            }
            WinGetPos(&x, &y, &width, &height, "ahk_id " card.Hwnd)
            if x != layout.X + offset || y != layout.Y + offset || width != layout.Width || height != layout.Height
            {
                ; Diagnostic only: a direct event can distinguish callback logic
                ; from hosted-runner WinEvent delivery. Never count this as pass.
                tracking := LoginProgressTracking
                OnGameLoginProgressLocationChange(tracking.Hook, 0x800B, game.Hwnd,
                    0, 0, tracking.ThreadId, A_TickCount)
                WinGetPos(&directX, &directY, , , "ahk_id " card.Hwnd)
                FileAppend("DIAGNOSTIC: direct WinEvent callback | cardX=" directX
                    " cardY=" directY " trackedGameX=" card.ProgressLayout.GameWindow.X "`n", "*")
                return ReportLoginCardSmokeFailure("tracking: follow moved game window | offset=" offset " actualGameX=" GetGameLoginProgressWindow(game.Hwnd).X " expectedCardX=" (layout.X + offset) " actualCardX=" x " expectedCardY=" (layout.Y + offset) " actualCardY=" y)
            }
        }
    }
    finally
    {
        StopGameLoginProgressTracking()
        LoginProgressShown := false
        LoginProgressGui := 0
    }
    return !IsObject(LoginProgressTracking)
}

CheckExpansionRecoveryLaunchGate()
{
    global ExpansionRecoveryRunning, ExpansionRecoveryPending, ExpansionToggleRunning
    ExpansionRecoveryRunning := true
    activeBlocksUse := PatchInProgress() && !CanUseNPLauncher(false) && !CanResetLauncherAppData(false)
    ExpansionRecoveryRunning := false
    ExpansionRecoveryPending := true
    pendingBlocksUse := !PatchInProgress() && !CanUseNPLauncher(false) && !CanResetLauncherAppData(false)
    ExpansionRecoveryPending := false
    ExpansionToggleRunning := true
    toggleBlocksUse := PatchInProgress() && !CanUseNPLauncher(false) && !CanResetLauncherAppData(false)
    ExpansionToggleRunning := false
    return activeBlocksUse && pendingBlocksUse && toggleBlocksUse
        && CanUseNPLauncher(false) && CanResetLauncherAppData(false)
}

CheckBackupExecutablePaths()
{
    settings := A_Temp "\tes3np-backup-check-" NewLauncherFileId() ".ini"
    bundled := A_ScriptDir "\client\tes3mp.exe"
    custom := A_Temp "\Custom TES3MP\tes3mp.exe"
    try
    {
        if GetBackupExecutable(settings) != bundled || FileExist(settings)
            throw Error("Backup lookup failed for default client settings.")
        IniWrite("CustomExe", settings, "Launch", "ClientMode")
        if GetBackupExecutable(settings) != ""
            throw Error("Backup lookup should allow a missing custom path.")
        IniWrite(custom, settings, "Launch", "CustomExecutable")
        for mode, expected in Map("Bundled", bundled, "CustomExe", custom,
            "CustomRuntime", custom, "Custom", custom, "CustomOverrides", "")
        {
            IniWrite(mode, settings, "Launch", "ClientMode")
            before := FileRead(settings)
            if GetBackupExecutable(settings) != expected || FileRead(settings) != before
                throw Error("Backup executable lookup failed for " mode ".")
        }
    }
    catch Error as err
    {
        try FileAppend(err.Message "`n", "**")
        return false
    }
    finally
        try FileDelete(settings)
    return true
}

CheckFirstRunOpenMWConfiguration()
{
    root := A_Temp "\tes3np-openmw-check-" NewLauncherFileId()
    config := root "\OpenMW\openmw.cfg"
    morrowind := root "\Morrowind GOTY"
    try
    {
        CreateVanillaOpenMWConfiguration(config, morrowind)
        before := FileRead(config, "UTF-8")
        expectedPath := StrReplace(StrReplace(StrReplace(morrowind, "\", "/"), "@", "@a"), "#", "@h")
        expected := 'data="' expectedPath '/Data Files"'
        for master in ["Morrowind", "Tribunal", "Bloodmoon"]
            expected .= "`r`nfallback-archive=" master ".bsa`r`ncontent=" master ".esm"
        if RTrim(before, "`r`n") != expected || ExpansionPackInLoadOrder(config)
            throw Error("First-run OpenMW configuration must load only Morrowind GOTY.")

        FileAppend("content=NP Expansion Pack.esp`r`n", config, "UTF-8-RAW")
        before := FileRead(config, "UTF-8")
        CreateVanillaOpenMWConfiguration(config, root "\Another Installation")
        if FileRead(config, "UTF-8") != before || !ExpansionPackInLoadOrder(config)
            throw Error("First-run setup must preserve an existing OpenMW configuration.")
    }
    catch Error as err
    {
        try FileAppend(err.Message "`n", "**")
        return false
    }
    finally
        try DirDelete(root, true)
    return true
}

CheckExpansionPackToggleState()
{
    global DataFile, LauncherExpansionToggle
    previousSettings := DataFile
    previousToggle := IsSet(LauncherExpansionToggle) ? LauncherExpansionToggle : 0
    root := A_Temp "\tes3np-expansion-check-" NewLauncherFileId()
    game := root "\Morrowind Caf" Chr(0xE9)
    data := game "\Data Files"
    config := root "\openmw.cfg"
    esp := data "\NP Expansion Pack.esp"
    panel := Gui()
    try
    {
        DirCreate(data)
        DataFile := root "\settings.ini"
        FileOpen(DataFile, "w", "UTF-16").Close()
        LauncherExpansionToggle := panel.AddButton(, "Expansion Pack")
        IniWrite(config, DataFile, "Patch", "ConfigFile")
        IniWrite(game "\", DataFile, "Patch", "MorrowindFolder")
        for master in ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm"]
            FileAppend("fixture", data "\" master, "UTF-8-RAW")

        FileAppend("content=NP Expansion Pack.esp`r`n", config, "UTF-8-RAW")
        RefreshExpansionPackToggle()
        if LauncherExpansionToggle.Text != "Expansion Pack: Unverified" || ExpansionPackIsEnabled()
            throw Error("A load-order entry alone cannot enable the pack.")

        FileAppend("abc", esp, "UTF-8-RAW")
        expectedHash := "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        if SHA256File(esp) != expectedHash
            throw Error("Raw SHA-256 did not match for a file in a spaced Unicode path.")
        IniWrite(game "\.\Data Files\NP Expansion Pack.esp", DataFile, "ExpansionPack", "VerifiedEspPath")
        IniWrite(expectedHash, DataFile, "ExpansionPack", "VerifiedEspSHA256")
        RefreshExpansionPackToggle()
        if LauncherExpansionToggle.Text != "Expansion Pack: Enabled" || !ExpansionPackIsEnabled()
            throw Error("A verified ESP in the load order must show as enabled.")

        FileDelete(config)
        FileAppend("content=Morrowind.esm`r`n", config, "UTF-8-RAW")
        RefreshExpansionPackToggle()
        if LauncherExpansionToggle.Text != "Expansion Pack: Disabled"
            || !ExpansionPackInstalled(game "\", config)
            throw Error("Disabling the load order must leave the already verified, installed pack available.")

        FileAppend("changed", esp, "UTF-8-RAW")
        FileAppend("content=NP Expansion Pack.esp`r`n", config, "UTF-8-RAW")
        RefreshExpansionPackToggle()
        if ExpansionPackInstalled(game, config) || ExpansionPackIsEnabled()
            || LauncherExpansionToggle.Text != "Expansion Pack: Unverified"
            throw Error("A changed ESP must not pass the installed pack verification.")


        ; A fresh launcher has no local import record. Simulate the official
        ; ZIP comparison at the trust-restoration boundary.
        IniDelete(DataFile, "ExpansionPack", "VerifiedEspPath")
        IniDelete(DataFile, "ExpansionPack", "VerifiedEspSHA256")
        crc := ExpansionPackEspChecksum(esp)
        if !ExpansionPackNeedsOfficialVerification(config)
            throw Error("A missing verified record must be eligible for official recheck.")
        if RestoreExistingExpansionPackVerification(config, "", "v0.2c")
            || RestoreExistingExpansionPackVerification(config, "00000000", "v0.2c")
            || RestoreExistingExpansionPackVerification(config, crc, "unknown")
            throw Error("Unverified or mismatched official metadata must not establish trust.")
        if IniRead(DataFile, "ExpansionPack", "VerifiedEspPath", "") != ""
            throw Error("Failed official comparisons must not create an installation record.")
        if !RestoreExistingExpansionPackVerification(config, crc, "v0.2c")
            || !ExpansionPackInstalled(game, config) || !ExpansionPackIsEnabled(config)
            throw Error("Matching official ZIP evidence must restore the installed SHA-256 record.")
        if ExpansionPackNeedsOfficialVerification(config)
            || IniRead(DataFile, "ExpansionPack", "VerifiedEspSHA256", "") != SHA256File(esp)
            throw Error("Recovered trust must be persisted against the actual installed ESP.")
        FileAppend("modified again", esp, "UTF-8-RAW")
        if ExpansionPackInstalled(game, config) || ExpansionPackIsEnabled(config)
            || RestoreExistingExpansionPackVerification(config, crc, "v0.2c")
            throw Error("A modified ESP must invalidate the recovered trust and official comparison.")

        ; Reusing an official checksum must not override a conflicting version
        ; declared by the installed plugin's TES3/HEDR description.
        FileDelete(esp)
        header := Buffer(336, 0)
        NumPut("UInt", 0x33534554, "UInt", 320, header, 0) ; TES3 record
        NumPut("UInt", 0x4D524F46, "UInt", 4, header, 16) ; FORM
        NumPut("UInt", 0x52444548, "UInt", 300, header, 28) ; HEDR
        StrPut("NP Expansion Pack v0.2a", header.Ptr + 76, 256, "CP0")
        headerFile := FileOpen(esp, "w")
        try headerFile.RawWrite(header)
        finally headerFile.Close()
        IniDelete(DataFile, "ExpansionPack", "VerifiedEspPath")
        IniDelete(DataFile, "ExpansionPack", "VerifiedEspSHA256")
        headerCrc := ExpansionPackEspChecksum(esp)
        if TES3MPReadExpansionHeaderVersion(esp) != "v0.2a"
            throw Error("The test ESP must expose its declared version.")
        if RestoreExistingExpansionPackVerification(config, headerCrc, "v0.2c")
            throw Error("An official attachment with a different version must not restore trust.")
        if !RestoreExistingExpansionPackVerification(config, headerCrc, "v0.2a")
            || !ExpansionPackInstalled(game, config)
            throw Error("An installed ESP with matching checksum and version must be recoverable.")
    }
    catch Error as err
    {
        try FileAppend(err.Message "`n", "**")
        return false
    }
    finally
    {
        DataFile := previousSettings
        LauncherExpansionToggle := previousToggle
        panel.Destroy()
        try DirDelete(root, true)
    }
    return true
}

CheckCrashRecoveryProfiles()
{
    global Profiles, SelectedProfile, AppDataDirectory, DataFile
    if !IsTES3MPCrashExit(0xC0000005) || !IsTES3MPCrashExit(0xE06D7363)
        || IsTES3MPCrashExit(0) || IsTES3MPCrashExit(1)
        || IsTES3MPCrashExit(0xC000013A) || IsTES3MPCrashExit(0xC0000135)
        || NewCharacterProfile().AutoReconnect
        ExitApp(222)
    oldProfile := NewCharacterProfile()
    oldProfile.Name := "Recovery fixture"
    oldProfile.AutoReconnect := true
    Profiles := [oldProfile.Clone()]
    if FindCrashRecoveryProfile(oldProfile) != Profiles[1]
        ExitApp(223)
    Profiles[1].AutoReconnect := false
    if IsObject(FindCrashRecoveryProfile(oldProfile))
        ExitApp(224)
    AppDataDirectory := A_Temp "\tes3np-reconnect-check-" NewLauncherFileId()
    DataFile := AppDataDirectory "\settings.ini"
    first := NewCharacterProfile()
    first.Name := "Reconnect enabled"
    first.Password := "synthetic first password"
    first.AutoReconnect := true
    second := NewCharacterProfile()
    second.Name := "Reconnect disabled"
    second.Password := "synthetic second password"
    Profiles := [first, second]
    SelectedProfile := 2
    failure := ""
    try
    {
        SaveProfiles()
        Profiles := []
        SelectedProfile := 0
        LoadProfiles()
        if Profiles.Length != 2 || SelectedProfile != 2
            || IniRead(DataFile, "Character1", "AutoReconnect", "") != "1"
            || IniRead(DataFile, "Character2", "AutoReconnect", "") != "0"
            || FindCrashRecoveryProfile(first) != Profiles[1] || IsObject(FindCrashRecoveryProfile(second))
            throw Error("Reload did not preserve the initial per-character reconnect settings.")
        Profiles[1].AutoReconnect := false
        Profiles[2].AutoReconnect := true
        SaveProfiles()
        LoadProfiles()
        if Profiles.Length != 2 || SelectedProfile != 2
            || IniRead(DataFile, "Character1", "AutoReconnect", "") != "0"
            || IniRead(DataFile, "Character2", "AutoReconnect", "") != "1"
            || IsObject(FindCrashRecoveryProfile(first)) || FindCrashRecoveryProfile(second) != Profiles[2]
            throw Error("Reload did not preserve the updated per-character reconnect settings.")
        IniDelete(DataFile, "Character2", "AutoReconnect")
        LoadProfiles()
        if Profiles[2].AutoReconnect
            throw Error("A legacy profile without AutoReconnect should default to off.")
    }
    catch Error as err
        failure := err.Message
    finally
        try DirDelete(AppDataDirectory, true)
    if failure != ""
    {
        try FileAppend("FAIL: " failure "`n", "**")
        ExitApp(227)
    }
    ; The compiled GUI may have no console. The exit code carries the result.
    try FileAppend("PASS: per-character AutoReconnect survives saving and reloading in both directions.`n", "*")
    ExitApp(0)
}

; Noninteractive compiled-host probe. Verify native expansion progress can
; resolve its actual UI functions without starting any window or game.
CheckExpansionProgressBindings()
{
    global ButtonFaces, PatchFrame
    for index, name in ["CaptureInterfaceFrame", "AddStyledButton",
        "DestroyBookControl", "ReleaseCapturedInterfaceFrame",
        "PaintButtonNow", "UpdateExpansionLoadingProgress",
        "UploadExpansionFromFile"]
    {
        try callback := %name%
        catch
            ExitApp(100 + index)
        if !HasMethod(callback, "Call")
            ExitApp(120 + index)
    }
    ; The real installer callback must leave the Static window caption
    ; alone and ignore duplicate worker polls. The probe needs no window.
    try
    {
        probePanel := {Hwnd: 0, Text: "Initial caption"}
        PatchFrame := {Panel: probePanel}
        ButtonFaces[0] := {Progress: 0}
        if !UpdatePatchProgress("Installing", 37)
            || UpdatePatchProgress("Installing", 37)
            || !UpdatePatchProgress("Verifying", 37)
            || !UpdatePatchProgress("Verifying", 45)
            || Abs(ButtonFaces[0].Progress - 0.45) > 0.0001
            || ButtonFaces[0].ProgressText != "Verifying (45%)"
            || probePanel.Text != "Initial caption"
            ExitApp(93)
    }
    catch
        ExitApp(94)
    finally
    {
        ButtonFaces.Delete(0)
        PatchFrame := 0
    }
    ExitApp(0)
}

; CI-only Windows GUI smoke test: exercise the same real screenshot cover,
; native card, custom Cancel button and protected renderer as first enable.
; No Discord, user game files or installer are started.
CheckExpansionProgressWindow()
{
    global LauncherGui, ExpansionAutoProgressFrame, ExpansionAutoCancelButton, LauncherLogFile
    LauncherGui := Gui("-Caption -Border", "Native Expansion download smoke")
    LauncherGui.BackColor := "1B140B"
    LauncherGui.Add("Text", "x20 y20 w500 h50", "Disposable launcher window")
    LauncherGui.Show("w960 h720")
    ; Real launcher buttons initialize this painter before first enable.
    ; Without it a synthetic window correctly raises UnsetError, which is
    ; a test-harness setup fault rather than the download-window defect.
    InitButtonPainter()
    ; Match the real flow: a cloaked owned Discord discovery window exists
    ; before the native download progress overlay is constructed.
    probeDialog := Gui("+Owner" LauncherGui.Hwnd " -MaximizeBox -MinimizeBox", "tes3np")
    TES3MPExpansionCloakDialog(probeDialog, true)
    probeDialog.Show("w660 h627")
    try
    {
        if !TES3MPExpansionBeginNativeProgress()
            throw Error("Native progress card creation returned false.")
        if !IsObject(ExpansionAutoProgressFrame)
            || !IsObject(ExpansionAutoCancelButton)
            || !DllCall("IsWindowVisible", "Ptr", ExpansionAutoCancelButton.Hwnd)
            throw Error("Native Cancel button or card is not visible.")
        TES3MPExpansionUpdateNativeProgress("Downloading Expansion Pack... 27%", 27)
        TES3MPExpansionUpdateNativeProgress("Downloading Expansion Pack... 65%", 65)
        TES3MPExpansionEndNativeProgress()
        FileAppend("PASS: native Expansion progress card and cancel UI" Chr(10), "*")
    }
    catch Error as err
    {
        ; Print only the type and first-party stage, never a path or secret.
        FileAppend("FAIL: native Expansion progress - " Type(err) Chr(10), "*")
        try
        {
            if FileExist(LauncherLogFile)
            {
                lines := StrSplit(FileRead(LauncherLogFile, "UTF-8"), Chr(10))
                count := 0
                for index, item in lines
                {
                    if InStr(item, "EXPANSION | Native")
                    {
                        FileAppend("DIAGNOSTIC: " Trim(item) Chr(10), "*")
                        count += 1
                        if count > 8
                            break
                    }
                }
            }
        }
        try TES3MPExpansionEndNativeProgress()
        ExitApp(181)
    }
    ExitApp(0)
}

; Windows-only page presentation smoke: verify DWM really retains a
; staged native GUI out of desktop composition until its paint is complete.
; This uses a disposable window, not launcher profiles, Discord or files.
CheckPageCompositor()
{
    testWindow := Gui("-Caption -Border", "TES3NP staged page smoke")
    testWindow.Add("Text", "x12 y12 w255 h35", "Paint-ready test page")
    if !SetPageCompositorCloak(testWindow, true)
        ExitApp(191)
    ; Reproduce Settings' exact hidden + DWM-cloaked color-key setup. AHK
    ; WinSetTransColor by window title failed in this state; by-HWND must work.
    testWindow.Show("Hide w280 h90")
    if !SetPageColorKey(testWindow, 0x010101)
        ExitApp(195)
    colorKey := Buffer(4, 0), colorAlpha := Buffer(1, 0), colorFlags := Buffer(4, 0)
    if !DllCall("GetLayeredWindowAttributes", "Ptr", testWindow.Hwnd,
        "Ptr", colorKey, "Ptr", colorAlpha, "Ptr", colorFlags, "Int")
        || NumGet(colorKey, 0, "UInt") != 0x010101
        || NumGet(colorFlags, 0, "UInt") != 1
        ExitApp(196)
    testWindow.Show()
    before := Buffer(4, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", testWindow.Hwnd,
        "UInt", 14, "Ptr", before, "UInt", 4, "Int") != 0
        || NumGet(before, 0, "Int") = 0
        ExitApp(192)
    RevealPaintedPage(testWindow)
    after := Buffer(4, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", testWindow.Hwnd,
        "UInt", 14, "Ptr", after, "UInt", 4, "Int") != 0
        || NumGet(after, 0, "Int") != 0
        ExitApp(193)
    if !DllCall("IsWindowVisible", "Ptr", testWindow.Hwnd)
        ExitApp(194)
    FileAppend("PASS: staged page hidden until native paint and then revealed" Chr(10), "*")
    testWindow.Destroy()
    ExitApp(0)
}

; CI-only fast return check: the full launcher is already visible beneath
; its owned Character Book. Closing the book must not repaint all registered
; themed controls or synchronously rebuild the parent menu.
CheckCachedCharacterReturn()
{
    global LauncherGui, LauncherScale, LauncherScaleMode, LauncherRequestedScale
    global LauncherCachedScale, LauncherControlLayout, LauncherCachedLayoutCount, ButtonFaces
    LauncherGui := Gui("-Caption -Border", "Cached return smoke")
    LauncherGui.Show("w560 h350")
    LauncherRequestedScale := 100
    LauncherScaleMode := "Manual"
    LauncherCachedScale := 100
    LauncherScale := LauncherCachedScale := GetLauncherPlacement().Scale
    LauncherControlLayout := Map()
    LauncherCachedLayoutCount := 0
    ; If ShowLauncherWindow accidentally invokes RepaintMenuButtons, its
    ; stale-handle sweep deletes this marker. The fast branch must not do so.
    probeHandle := 0x7E5A01
    ButtonFaces[probeHandle] := {State: "probe"}
    probeBook := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border", "Book")
    probeBook.Show("w220 h160")
    began := A_TickCount
    ShowLauncherWindow(true)
    probeBook.Hide()
    elapsed := A_TickCount - began
    if !ButtonFaces.Has(probeHandle)
        ExitApp(201)
    if !DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        || DllCall("IsWindowVisible", "Ptr", probeBook.Hwnd)
        ExitApp(202)
    if elapsed >= 750
        ExitApp(203)
    ButtonFaces.Delete(probeHandle)
    FileAppend("PASS: cached Character Book return avoids global repaint" Chr(10), "*")
    ExitApp(0)
}

; Exercise owner-relative positioning, monitor bounds, and scaled font cleanup.
CheckOwnedMenuScaling()
{
    global LauncherScale, LauncherGui
    LauncherScale := 60
    LauncherGui := Gui("-Caption -Border", "Owned menu placement smoke")
    primary := MonitorGetPrimary()
    MonitorGetWorkArea(primary, &ml, &mt, &mr, &mb)
    ox := ml + 100, oy := mt + 90
    LauncherGui.Show("x" ox " y" oy " w560 h425")
    child := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border", "Child menu")
    child.SetFont("s12", "Segoe UI")
    label := child.Add("Text", "x20 y25 w210 h30", "Scaled menu")
    button := child.Add("Button", "x30 y95 w160 h40", "Test")
    try
    {
        for percent in [50, 60, 70, 80, 90, 100]
        {
            LauncherScale := percent
            scale := GetOwnedMenuScale()
            ScaleOwnedMenuContent(child, scale)
            child.Show("Hide w" Round(400 * scale) " h" Round(250 * scale))
            if !PositionOwnedMenuAtParent(child, LauncherGui)
                ExitApp(211)
            label.GetPos(&lx, &ly, &lw, &lh)
            button.GetPos(&bx, &by, &bw, &bh)
            if Abs(lx - Round(20 * scale)) > 1
                || Abs(lw - Round(210 * scale)) > 1
                || Abs(bx - Round(30 * scale)) > 1
                || Abs(bw - Round(160 * scale)) > 1
                ExitApp(212)
            parentRect := Buffer(16, 0), childRect := Buffer(16, 0)
            DllCall("GetWindowRect", "Ptr", LauncherGui.Hwnd, "Ptr", parentRect)
            DllCall("GetWindowRect", "Ptr", child.Hwnd, "Ptr", childRect)
            parentCenterX := (NumGet(parentRect, 0, "Int") + NumGet(parentRect, 8, "Int")) / 2
            parentCenterY := (NumGet(parentRect, 4, "Int") + NumGet(parentRect, 12, "Int")) / 2
            childCenterX := (NumGet(childRect, 0, "Int") + NumGet(childRect, 8, "Int")) / 2
            childCenterY := (NumGet(childRect, 4, "Int") + NumGet(childRect, 12, "Int")) / 2
            if Abs(parentCenterX - childCenterX) > 2
                || Abs(parentCenterY - childCenterY) > 2
                ExitApp(213)
        }
        ; Move the parent AFTER constructing the child. Reposition must use
        ; the new owner rectangle and never its original desktop coordinates.
        DllCall("SetWindowPos", "Ptr", LauncherGui.Hwnd, "Ptr", 0,
            "Int", ox + 70, "Int", oy + 55,
            "Int", 0, "Int", 0, "UInt", 0x0015)
        if !PositionOwnedMenuAtParent(child, LauncherGui)
            ExitApp(214)
        movedRect := Buffer(16, 0)
        DllCall("GetWindowRect", "Ptr", child.Hwnd, "Ptr", movedRect)
        if Abs(NumGet(movedRect, 0, "Int") - NumGet(childRect, 0, "Int") - 70) > 2
            || Abs(NumGet(movedRect, 4, "Int") - NumGet(childRect, 4, "Int") - 55) > 2
            ExitApp(215)
        ; Test an owner moved to the visible right/bottom edge. Child must
        ; remain inside the OWNER monitor work area rather than opening in
        ; an unrelated desktop coordinate space.
        DllCall("SetWindowPos", "Ptr", LauncherGui.Hwnd, "Ptr", 0,
            "Int", mr - 280, "Int", mb - 280,
            "Int", 0, "Int", 0, "UInt", 0x0015)
        if !PositionOwnedMenuAtParent(child, LauncherGui)
            ExitApp(218)
        edgeRect := Buffer(16, 0)
        DllCall("GetWindowRect", "Ptr", child.Hwnd, "Ptr", edgeRect)
        if NumGet(edgeRect, 0, "Int") < ml
            || NumGet(edgeRect, 4, "Int") < mt
            || NumGet(edgeRect, 8, "Int") > mr
            || NumGet(edgeRect, 12, "Int") > mb
            ExitApp(219)
        child.Show()
        if !DllCall("IsWindowVisible", "Ptr", child.Hwnd)
            ExitApp(216)
        fonts := child.OwnedGeneratedFonts.Clone()
        if !fonts.Length
            ExitApp(220)
        fontDefinition := Buffer(92, 0) ; LOGFONTW
        for font in fonts
            if DllCall("gdi32\GetObjectW", "Ptr", font,
                "Int", fontDefinition.Size, "Ptr", fontDefinition, "Int") != fontDefinition.Size
                ExitApp(220)
        DestroyScaledMenu(child)
        ; GDI can batch deletions. Check handle lifetime after the batch has completed.
        if !DllCall("gdi32\GdiFlush", "Int")
        {
            try FileAppend("FAIL: GDI batch failed while releasing generated menu fonts." Chr(10), "**")
            ExitApp(221)
        }
        for font in fonts
        {
            ; Query the font's data so a stale type alone cannot report a leak.
            if DllCall("gdi32\GetObjectW", "Ptr", font,
                "Int", fontDefinition.Size, "Ptr", fontDefinition, "Int")
            {
                try FileAppend("FAIL: generated menu font data is still readable after destruction and GDI flush." Chr(10), "**")
                ExitApp(221)
            }
        }
        CheckDisplaySettingsAndReleaseNotes()
        ; A compiled GUI launch can lack console streams. Preserve the real result.
        try FileAppend("PASS: menus follow moved owner, stay onscreen, scale 50-100 percent and release generated fonts" Chr(10), "*")
    }
    catch Error as err
    {
        try FileAppend("FAIL: owned menu scale/position - " Type(err) " in " err.What
            " at line " err.Line ": " SanitizeDiagnosticText(err.Message) Chr(10), "**")
        ExitApp(217)
    }
    ExitApp(0)
}

; All launcher-owned native copy must observe Normal / Large / Extra Large,
; including nonbutton labels and the cached character book. Compare actual
; LOGFONT handles and keep the UI geometry unchanged.
NativeInterfaceFontHeight(control)
{
    font := DllCall("SendMessageW", "Ptr", control.Hwnd, "UInt", 0x0031,
        "Ptr", 0, "Ptr", 0, "Ptr")
    definition := Buffer(92, 0)
    if !font || DllCall("gdi32\GetObjectW", "Ptr", font, "Int",
        definition.Size, "Ptr", definition, "Int") < 92
        throw Error("Native control font was not readable.")
    return Abs(NumGet(definition, 0, "Int"))
}


; Native, pure layout preflight: verify the exact baseline and overflow
; condition that the previous partial Character Book reflow got wrong.
CheckAccessibleLayoutPreflight()
{
    rows := {Id: "character-rows", Height: 239, GapAfter: 10}
    add := {Id: "add-character", Height: 30, MinimumTop: 540}
    baseline := PlanAccessibleVerticalStack([
        {Id: "full-description", Height: 81, GapAfter: 3}, rows, add], 80, 570)
    if !baseline.Feasible || baseline.Items[1].Top != 80
        || baseline.Items[2].Top != 164 || baseline.Items[3].Top != 540
        throw Error("Baseline Character Book layout planning changed.")
    enlarged := PlanAccessibleVerticalStack([
        {Id: "full-description", Height: 220, GapAfter: 3}, rows, add], 80, 570)
    if enlarged.Feasible || enlarged.Overflow <= 0
        throw Error("Infeasible enlarged Character Book geometry was accepted.")
    restored := PlanAccessibleVerticalStack([
        {Id: "full-description", Height: 81, GapAfter: 3}, rows, add], 80, 570)
    if !restored.Feasible || restored.Items[2].Top != baseline.Items[2].Top
        throw Error("Normal layout did not restore its original geometry.")
    alignedControls := ValidateAccessibleControlRectangles([
        {Id: "name", X: 95, Y: 164, Width: 140, Height: 23},
        {Id: "play", X: 240, Y: 164, Width: 55, Height: 22},
        {Id: "edit", X: 300, Y: 164, Width: 60, Height: 22},
        {Id: "remove", X: 365, Y: 164, Width: 75, Height: 22}], 960, 650)
    if !alignedControls.Feasible
        throw Error("Approved Normal Character Book controls were considered overlapping.")
    collision := ValidateAccessibleControlRectangles([
        {Id: "play", X: 240, Y: 164, Width: 55, Height: 22},
        {Id: "edit", X: 250, Y: 164, Width: 60, Height: 22}], 960, 650)
    if collision.Feasible
        throw Error("Dynamic hit-target collision was not detected.")
    tooWide := ValidateAccessibleControlRectangles([
        {Id: "name", X: 900, Y: 164, Width: 140, Height: 23}], 960, 650)
    if tooWide.Feasible
        throw Error("Text-aware layout accepted an off-parent control.")
    normalBook := PlanAccessibleBookGeometry(70, 40, 23, 62, 1920, 1080)
    if !normalBook.Feasible || normalBook.Height != 650
        || normalBook.CharacterTop != 164 || normalBook.MacroTop != 140
        || normalBook.FooterTop != 575
        throw Error("Complete normal two-column Book baseline changed.")
    largeBook := PlanAccessibleBookGeometry(220, 72, 23, 62, 1920, 1080)
    if !largeBook.Feasible || largeBook.Height <= 650
        || !largeBook.RequiresArtworkExtension
        || normalBook.RequiresArtworkExtension
        || largeBook.CharacterTop <= normalBook.CharacterTop
        || largeBook.FooterTop <= normalBook.FooterTop
        throw Error("Whole-book Large reflow did not reserve enough parent/artwork space.")
    noSpace := PlanAccessibleBookGeometry(220, 72, 23, 62, 960, 650)
    if noSpace.Feasible || noSpace.Height != 0
        throw Error("Oversized Character Book produced a partial screen layout.")
    biggerRows := PlanAccessibleBookGeometry(70, 40, 38, 130, 1920, 1080)
    if !biggerRows.Feasible || biggerRows.CharacterPitch <= normalBook.CharacterPitch
        || biggerRows.MacroPitch <= normalBook.MacroPitch
        throw Error("Measured larger row fonts were not given extra spacing.")
    emptyState := PlanAccessibleBookGeometry(70, 40, 23, 62, 1920, 1080, 0, 0)
    if !emptyState.Feasible || emptyState.AddTop != 164
        || emptyState.ImportTop != 199 || emptyState.WipeTop != 0
        throw Error("Empty Book Add/Import layout does not match the approved baseline.")
    fullState := PlanAccessibleBookGeometry(70, 40, 23, 62,
        1920, 1080, 10, 4, true)
    if !fullState.Feasible || fullState.NoticeTop != 429
        || fullState.WipeTop != 577
        throw Error("Full Character Book warning/Wipe layout changed.")
    enlargedFull := PlanAccessibleBookGeometry(220, 72, 38, 130,
        1920, 1080, 10, 4, true)
    if !enlargedFull.Feasible
        || enlargedFull.NoticeTop < enlargedFull.CharacterBottom + 8
        || enlargedFull.AddTop < enlargedFull.NoticeBottom + 10
        || enlargedFull.FooterTop < enlargedFull.AddTop + 35
        throw Error("Enlarged character warning intersects rows or Add/Close actions.")
    halfScale := PlanAccessibleBookGeometry(220, 72, 38, 130,
        520, 490, 10, 4, false, 0.5, 1.0)
    if !halfScale.Feasible || halfScale.Height <= 650
        throw Error("Half-scale launcher failed to preserve full logical text layout.")
    dpiBalanced := PlanAccessibleBookGeometry(70, 40, 23, 62,
        960, 650, 10, 4, false, 0.5, 2.0)
    if !dpiBalanced.Feasible || dpiBalanced.CharacterTop != normalBook.CharacterTop
        throw Error("DPI and independent launcher zoom produced different layout anchors.")
    dpiTooBig := PlanAccessibleBookGeometry(70, 40, 23, 62,
        960, 650, 10, 4, false, 1.0, 1.5)
    if dpiTooBig.Feasible || dpiTooBig.Height != 0
        throw Error("Physically oversized book incorrectly accepted by the monitor planner.")
    normalAgain := PlanAccessibleBookGeometry(70, 40, 23, 62, 1920, 1080)
    if normalAgain.Height != normalBook.Height
        || normalAgain.CharacterTop != normalBook.CharacterTop
        || normalAgain.MacroTop != normalBook.MacroTop
        throw Error("Whole-book layout did not restore its normal anchors.")
}


; Measure real, unchanged Character/Macro copy using the chosen Windows font.
; This is a disposable GUI: it cannot move the actual cached Character Book.
; Never claim a full-view pass merely because a text string was measurable.
CheckMeasuredAccessibleBookPreflight()
{
    global AccessibilityTextSize
    previousMode := AccessibilityTextSize
    fullDescription := "This is a list of all your characters. You can add, edit, or delete your character details at any time. Please note that adding, editing, and deleting characters on this list does not impact them in-game!"
    macroCopy := "Upload, run, or stop macros here. Click the pencil to rename a macro."
    heights := [], plans := [], nameWidths := []
    try
    {
        for mode in ["Normal", "Large", "Extra Large"]
        {
            AccessibilityTextSize := mode
            probe := Gui("-DPIScale")
            try
            {
                SetAccessibleTextFont(probe, "s11 Norm c241408", "Georgia")
                description := probe.Add("Text", "x8 y8 w390 h81", fullDescription)
                descriptionHeight := MeasureAccessibleWrappedText(description,
                    fullDescription, 382)
                SetAccessibleTextFont(probe, "s11 Norm c241408", "Georgia")
                macro := probe.Add("Text", "x8 y100 w355 h48", macroCopy)
                macroHeight := MeasureAccessibleWrappedText(macro, macroCopy, 347)
                SetAccessibleTextFont(probe, "s12 Norm c241408", "Georgia")
                characterName := probe.Add("Text", "x8 y160 w140 h23", "Character Name")
                characterHeight := MeasureAccessibleWrappedText(characterName,
                    "Character Name", 136)
                longNameMetrics := MeasureAccessibleSingleLineText(characterName,
                    "A character name that should not ever be cut off or replaced")
                if longNameMetrics.Width <= 140
                    throw Error("Long-name fixture did not exceed the original fixed name column.")
                nameWidths.Push(longNameMetrics.Width)
                SetAccessibleTextFont(probe, "s12 Norm c241408", "Georgia")
                macroName := probe.Add("Text", "x8 y205 w125 h22", "Macro Name")
                macroNameHeight := MeasureAccessibleWrappedText(macroName,
                    "Macro Name", 121)
                heights.Push({Description: descriptionHeight, Macro: macroHeight,
                    Character: characterHeight, MacroRow: Max(62, macroNameHeight + 40)})
                plan := PlanAccessibleBookGeometry(descriptionHeight, macroHeight,
                    Max(23, characterHeight), Max(62, macroNameHeight + 40),
                    1920, 1200)
                if !plan.Feasible
                    throw Error("Measured accessible text exceeded the full-work-area fixture at " mode ".")
                if plan.CharacterTop < 80 + Max(81, descriptionHeight) + 3
                    || plan.MacroTop < 87 + Max(48, macroHeight) + 5
                    throw Error("Measured text overlaps a neighboring row at " mode ".")
                plans.Push(plan)
            }
            finally probe.Destroy()
        }
        if nameWidths[1] >= nameWidths[2] || nameWidths[2] >= nameWidths[3]
            throw Error("Large Interface Text failed to increase unshortened character-name width.")
        if heights[1].Description > heights[2].Description
            || heights[2].Description > heights[3].Description
            throw Error("The original Character Book description got smaller at a larger text preference.")
        if plans[3].RequiredHeight < plans[1].RequiredHeight
            throw Error("Larger text reduced the required whole-book height.")
        constrained := PlanAccessibleBookGeometry(heights[3].Description,
            heights[3].Macro, Max(23, heights[3].Character),
            heights[3].MacroRow, 800, 650)
        if constrained.Feasible || constrained.Height != 0
            throw Error("Infeasible measured two-column layout was accepted.")
        try FileAppend("PASS: measured unchanged Character/Macro text feeds reversible whole-book layout preflight" Chr(10), "*")
    }
    finally AccessibilityTextSize := previousMode
}

CheckInterfaceTextAccessibility()
{
    global AccessibilityTextSize, V016SettingsScale
    oldMode := AccessibilityTextSize, oldScale := V016SettingsScale
    CheckAccessibleLayoutPreflight()
    CheckMeasuredAccessibleBookPreflight()
    try
    {
        bodyHeights := [], settingsHeights := []
        for mode in ["Normal", "Large", "Extra Large"]
        {
            AccessibilityTextSize := mode
            V016SettingsScale := 1.0
            panel := Gui("-DPIScale")
            try
            {
                SetAccessibleTextFont(panel, "s11 Norm c382314", "Segoe UI")
                body := panel.Add("Text", "x4 y4 w330 h40", "Character and settings copy")
                bodyHeights.Push(NativeInterfaceFontHeight(body))
                SetAccessibleTextFont(body, "c241408")
                if NativeInterfaceFontHeight(body) != bodyHeights[bodyHeights.Length]
                    throw Error("Changing a font color incorrectly resized its text.")
                SetAccessibleTextFont(panel, "s" V016Font(13) " Norm c241408", "Georgia")
                settingsLabel := panel.Add("Text", "x4 y48 w330 h40", "Settings section label")
                settingsHeights.Push(NativeInterfaceFontHeight(settingsLabel))
            }
            finally panel.Destroy()
        }
        if bodyHeights[1] >= bodyHeights[2] || bodyHeights[2] >= bodyHeights[3]
            || settingsHeights[1] >= settingsHeights[2]
            || settingsHeights[2] >= settingsHeights[3]
            throw Error("Interface Text choice does not enlarge native body and settings labels.")
        AccessibilityTextSize := "Normal"
        book := Gui("-DPIScale")
        try
        {
            SetAccessibleTextFont(book, "s11 Norm", "Segoe UI")
            label := book.Add("Text", "x20 y20 w300 h30", "Cached character menu")
            book.InterfaceFontMode := "Normal"
            label.GetPos(&x, &y, &width, &height)
            before := NativeInterfaceFontHeight(label)
            AccessibilityTextSize := "Extra Large"
            RefreshCachedBookTextPreference(book)
            if NativeInterfaceFontHeight(label) <= before
                throw Error("Cached Character Book kept its old font size.")
            label.GetPos(&ax, &ay, &aw, &ah)
            if ax != x || ay != y || aw != width || ah != height
                throw Error("Cached font refresh moved a character control.")
            if !book.HasOwnProp("OwnedGeneratedFonts") || !book.OwnedGeneratedFonts.Length
                throw Error("Cached Character Book did not own its generated fonts.")
        }
        finally DestroyScaledMenu(book)
        try FileAppend("PASS: Interface Text scales native copy and cached books without changing hit targets" Chr(10), "*")
    }
    finally
    {
        AccessibilityTextSize := oldMode
        V016SettingsScale := oldScale
    }
}

; A closed update GUI must not crash a still-dispatching native mouse callback.
; This reproduces WM_LBUTTONDOWN arriving after the modal is destroyed but
; before its OnMessage callback has been removed from the global dispatcher.
CheckUpdateNoteCallbackLifetime()
{
    dialog := Gui("-DPIScale", "Disposed update callback check")
    viewport := dialog.Add("Text", "x0 y0 w40 h40", "")
    track := dialog.Add("Text", "x40 y0 w12 h40", "")
    thumb := dialog.Add("Text", "x40 y0 w12 h12", "")
    dialogHwnd := dialog.Hwnd
    viewportHwnd := viewport.Hwnd
    trackHwnd := track.Hwnd
    thumbHwnd := thumb.Hwnd
    page := {MaxOffset: 2, Offset: 1, Closed: false}
    drag := {Active: false, Timer: 0, PanelHwnd: dialogHwnd}
    refresh := (*) => 0
    dialog.Destroy()
    if DllCall("user32\IsWindow", "Ptr", dialogHwnd, "Int")
        throw Error("Disposed update test dialog was not destroyed.")
    StartUpdateNotesDrag(dialogHwnd, thumbHwnd, trackHwnd, drag, page, refresh,
        0, 0, 0, dialogHwnd)
    UpdateNotesMouseWheel(viewportHwnd, page, refresh, 0, 0, 0, dialogHwnd)
    page.Closed := true
    StartUpdateNotesDrag(dialogHwnd, thumbHwnd, trackHwnd, drag, page, refresh,
        0, 0, 0, dialogHwnd)
    UpdateNotesMouseWheel(viewportHwnd, page, refresh, 0, 0, 0, dialogHwnd)
    try FileAppend("PASS: native update mouse callbacks ignore destroyed modal HWNDs" Chr(10), "*")
}

; Exercise the actual composited native note row, rather than assuming that
; static layout checks can detect a one-frame gold-background erase.
CheckBufferedReleaseNoteRow(row)
{
    global UpdateNoteRowPaintState
    if !IsSet(UpdateNoteRowPaintState) || !UpdateNoteRowPaintState.Has(row.Hwnd)
        throw Error("Visible release-note row has no dedicated buffered painter.")
    bounds := Buffer(16, 0)
    if !DllCall("user32\GetClientRect", "Ptr", row.Hwnd, "Ptr", bounds, "Int")
        throw OSError()
    width := NumGet(bounds, 8, "Int"), height := NumGet(bounds, 12, "Int")
    sourceDC := DllCall("user32\GetDC", "Ptr", row.Hwnd, "Ptr")
    memoryDC := 0, bitmap := 0, oldBitmap := 0
    try
    {
        memoryDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", sourceDC, "Ptr")
        bitmap := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", sourceDC, "Int", width, "Int", height, "Ptr")
        if !memoryDC || !bitmap
            throw OSError()
        oldBitmap := DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", bitmap, "Ptr")
        ; Send WM_PRINTCLIENT through the installed native Static subclass.
        DllCall("user32\SendMessageW", "Ptr", row.Hwnd, "UInt", 0x0318,
            "Ptr", memoryDC, "Ptr", 4)
        pixel := DllCall("gdi32\GetPixel", "Ptr", memoryDC, "Int", width - 3,
            "Int", height - 3, "UInt")
        if pixel != 0x081017 ; COLORREF of exact #171008 background
            throw Error("A painted release-note row exposed a non-dark background.")
        ; A solid dark bitmap would also pass the background check while
        ; silently dropping all lettering. Require at least one glyph pixel.
        hasTextPixel := false
        Loop Min(width - 3, 200)
        {
            sampleX := A_Index
            Loop Min(height - 2, 32)
            {
                sampleY := A_Index
                sample := DllCall("gdi32\GetPixel", "Ptr", memoryDC, "Int", sampleX,
                    "Int", sampleY, "UInt")
                if sample != 0x081017 && sample != 0xFFFFFFFF
                {
                    hasTextPixel := true
                    break
                }
            }
            if hasTextPixel
                break
        }
        if !hasTextPixel
            throw Error("A buffered release-note row painted its background but not its lettering.")
    }
    finally
    {
        if oldBitmap
            DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", oldBitmap, "Ptr")
        if bitmap
            DllCall("gdi32\DeleteObject", "Ptr", bitmap)
        if memoryDC
            DllCall("gdi32\DeleteDC", "Ptr", memoryDC)
        if sourceDC
            DllCall("user32\ReleaseDC", "Ptr", row.Hwnd, "Ptr", sourceDC)
    }
}

; The owned-menu probe already runs on Windows in CI. Use its disposable owner
; to exercise the real display refresh and release-note rows at both extremes.
; Exercise the real union screenshot, not just a black window enlarged
; over a small old-size bitmap. Use native Gui backdrops with known pixels so
; the Windows smoke fails if the new outer area is blank/black/misplaced.
CheckExtremeDisplayFrameCoverage()
{
    cases := [
        {X: 160, Y: 150, Width: 240, Height: 180,
            Target: {X: 70, Y: 60, Width: 480, Height: 360}, Expanded: true},
        {X: 70, Y: 60, Width: 480, Height: 360,
            Target: {X: 160, Y: 150, Width: 240, Height: 180}, Expanded: false}
    ]
    for testcase in cases
    {
        left := Min(testcase.X, testcase.Target.X)
        top := Min(testcase.Y, testcase.Target.Y)
        right := Max(testcase.X + testcase.Width, testcase.Target.X + testcase.Target.Width)
        bottom := Max(testcase.Y + testcase.Height, testcase.Target.Y + testcase.Target.Height)
        width := right - left, height := bottom - top
        backdrop := Gui("-Caption -Border -DPIScale +ToolWindow")
        backdrop.BackColor := "426B93" ; distinct nonblack real-screen area
        source := Gui("-Caption -Border -DPIScale +ToolWindow")
        source.BackColor := "946734"
        frame := 0
        memoryDC := 0, sourceDC := 0, oldBitmap := 0
        try
        {
            backdrop.Show("NA x" left " y" top " w" width " h" height)
            source.Show("NA x" testcase.X " y" testcase.Y
                " w" testcase.Width " h" testcase.Height)
            DllCall("RedrawWindow", "Ptr", backdrop.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0181)
            DllCall("RedrawWindow", "Ptr", source.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0181)
            ; A brand-new synthetic source can be WS_VISIBLE and repainted
            ; while the desktop compositor still presents its prior pixels.
            ; Wait briefly in this TEST ONLY until the fixture itself appears
            ; in the screen DC, then let the desktop composition settle.
            readyPixel := 0xFFFFFFFF
            Loop 20
            {
                probeDC := DllCall("GetDC", "Ptr", 0, "Ptr")
                readyPixel := DllCall("GetPixel", "Ptr", probeDC,
                    "Int", testcase.X + 15, "Int", testcase.Y + 15, "UInt")
                DllCall("ReleaseDC", "Ptr", 0, "Ptr", probeDC)
                if readyPixel = 0x346794
                    break
                Sleep(25)
            }
            if readyPixel != 0x346794
                throw Error("Synthetic source never appeared in desktop pixels ("
                    Format("0x{:06X}", readyPixel) ").")
            Sleep(80) ; compositor readiness of synthetic fixture only
            frame := CaptureInterfaceFrame(source, false, testcase.Target)
            if !IsObject(frame) || !IsObject(frame.Gui) || !frame.Bitmap
                throw Error("The full desktop-union screenshot could not be captured.")
            if frame.Expanded != testcase.Expanded
                throw Error("The capture did not recognize an extreme-size transition.")
            bounds := Buffer(16, 0)
            if !DllCall("GetWindowRect", "Ptr", frame.Gui.Hwnd, "Ptr", bounds, "Int")
                throw OSError()
            if NumGet(bounds, 0, "Int") != left || NumGet(bounds, 4, "Int") != top
                || NumGet(bounds, 8, "Int") != right || NumGet(bounds, 12, "Int") != bottom
                throw Error("Captured union does not cover both launcher rectangles.")
            frame.Face.GetPos(&fx, &fy, &fw, &fh)
            if fx != 0 || fy != 0 || fw != width || fh != height
                throw Error("The full-union image does not fill the full cover or was stretched.")
            sourceDC := DllCall("GetDC", "Ptr", 0, "Ptr")
            memoryDC := DllCall("CreateCompatibleDC", "Ptr", sourceDC, "Ptr")
            if !sourceDC || !memoryDC
                throw OSError()
            oldBitmap := DllCall("SelectObject", "Ptr", memoryDC, "Ptr", frame.Bitmap, "Ptr")
            ; Read a pixel safely within the old launcher and require the
            ; snapshot to reproduce its native background, not a fake matte.
            innerX := testcase.X - left + 15
            innerY := testcase.Y - top + 15
            inner := DllCall("GetPixel", "Ptr", memoryDC, "Int", innerX, "Int", innerY, "UInt")
            if inner != 0x346794 ; old launcher RGB #946734, COLORREF #346794
            {
                ; Print only fixture RGB values; no desktop content or paths.
                sourceWindowDC := DllCall("GetDC", "Ptr", source.Hwnd, "Ptr")
                actualWindowColor := DllCall("GetPixel", "Ptr", sourceWindowDC,
                    "Int", 15, "Int", 15, "UInt")
                DllCall("ReleaseDC", "Ptr", source.Hwnd, "Ptr", sourceWindowDC)
                directScreenColor := DllCall("GetPixel", "Ptr", sourceDC,
                    "Int", testcase.X + 15, "Int", testcase.Y + 15, "UInt")
                throw Error("The original launcher pixels were not preserved. "
                    "Bitmap=" Format("0x{:06X}", inner)
                    " sourceDC=" Format("0x{:06X}", actualWindowColor)
                    " desktopDC=" Format("0x{:06X}", directScreenColor) ".")
            }
            if testcase.Expanded
            {
                ; This point is outside the small source but inside the 100%
                ; target. It MUST contain the actual colored desktop behind
                ; the source, not a synthesized opaque black rectangle.
                outer := DllCall("GetPixel", "Ptr", memoryDC, "Int", 15, "Int", 15, "UInt")
                if outer != 0x936B42 ; desktop RGB #426B93, COLORREF #936B42
                    throw Error("The expanded screenshot contains a blank/black outer region.")
            }
        }
        finally
        {
            if oldBitmap
                DllCall("SelectObject", "Ptr", memoryDC, "Ptr", oldBitmap, "Ptr")
            if memoryDC
                DllCall("DeleteDC", "Ptr", memoryDC)
            if sourceDC
                DllCall("ReleaseDC", "Ptr", 0, "Ptr", sourceDC)
            if IsObject(frame)
                ReleaseCapturedInterfaceFrame(frame)
            source.Destroy()
            backdrop.Destroy()
        }
    }
}

CheckDisplaySettingsAndReleaseNotes()
{
    global LauncherGui, LauncherHeading, LauncherScale, LauncherScaleMode, LauncherRequestedScale, ButtonFaces
    global V016SettingsGuiHwnd, InterfaceFrameCover
    CheckInterfaceTextAccessibility()
    CheckUpdateNoteCallbackLifetime()
    CheckExtremeDisplayFrameCoverage()
    if GetLauncherScaleForWorkArea(1920, 1040, 1.0) != 100
        || GetLauncherScaleForWorkArea(1280, 680, 1.5) != 60
        || GetLauncherScaleForWorkArea(1280, 680, 1.5, 100) != 63
        || GetLauncherScaleForWorkArea(640, 440, 2.0, 50) != 30
        throw Error("Launcher scale did not fit the work area at the requested DPI.")
    LauncherHeading := 0
    control := LauncherGui.Add("Text", "x20 y30 w200 h50", "Display layout smoke")
    CaptureLauncherControlLayout()
    settings := Gui("-Caption +Owner" LauncherGui.Hwnd)
    InitButtonPainter()
    try
    {
        for step, percent in [50, 100, 0, 0]
        {
            LauncherScaleMode := percent ? "Manual" : "Auto"
            if percent
                LauncherRequestedScale := percent
            if step != 2
            {
                settings.Show("w280 h170")
                DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 0)
            }
            faceCount := ButtonFaces.Count
            message := step = 2 ? "Restoring display settings..."
                : percent ? "Applying display settings..." : "Resetting display settings..."
            RefreshLauncherDisplay(message, settings)
            control.GetPos(&x, &y, &width, &height)
            if Abs(width - Round(200 * LauncherScale / 100)) > 1 || Abs(y - Round(30 * LauncherScale / 100)) > 1
                throw Error("Display refresh did not resize the launcher controls.")
            if !DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd, "Int")
                || !DllCall("IsWindowEnabled", "Ptr", LauncherGui.Hwnd, "Int")
                || DllCall("IsIconic", "Ptr", LauncherGui.Hwnd, "Int")
                || DllCall("IsWindowVisible", "Ptr", settings.Hwnd, "Int") || ButtonFaces.Count != faceCount
                throw Error("Display refresh did not restore the live launcher or release its loading card.")
        }
        ; This was invisible to prior tests: WM_SETREDRAW(FALSE) can strip
        ; WS_VISIBLE off the top-level Settings GUI underneath its cover.
        settings.Show("w280 h170")
        settings.Add("Text", "x15 y20 w220 h30", "Settings transition visibility smoke")
        previousSettingsHwnd := V016SettingsGuiHwnd
        V016SettingsGuiHwnd := settings.Hwnd
        try
        {
            BeginInterfaceUpdate(settings, "Settings transition", false)
            try
            {
                if IsObject(InterfaceFrameCover)
                    && !DllCall("user32\IsWindowVisible", "Ptr", settings.Hwnd, "Int")
                    throw Error("Covered Settings unexpectedly lost WS_VISIBLE.")
            }
            finally EndInterfaceUpdate()
            if !DllCall("user32\IsWindowVisible", "Ptr", settings.Hwnd, "Int")
                throw Error("Settings did not remain visible after the native transition.")
        }
        finally V016SettingsGuiHwnd := previousSettingsHwnd
    }
    finally
    {
        DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 1)
        settings.Destroy()
    }
    longWord := ""
    Loop 180
        longWord .= "M"
    notes := "First paragraph.`n`n`n### Section heading`n`n- First bullet.`n" longWord
    for percent in [50, 100]
    {
        LauncherScale := percent
        scale := GetOwnedMenuScale()
        panel := CreateGoldNativePrompt(LauncherGui, "Release notes smoke", 800, 600)
        ; Exercise the native themed tab and footer controls at both scales.
        tab := AddStyledButton(panel, 30, 123, 199, 30, "Release Notes", (*) => 0)
        footer := AddStyledButton(panel, 410, 544, 212, 34, "Close", (*) => 0)
        unregister := 0
        switcher := {}
        try
        {
            ScaleOwnedMenuContent(panel, scale)
            unregister := AddUpdateNotesViewport(panel, "Short note.", scale, switcher)
            if !switcher.HasOwnProp("Update")
                throw Error("Release-note tab switch handler was not installed.")
            ; Verify the switch from a single row back to a long, scrollable page.
            switcher.Update.Call(notes)
            ShowGoldNativePrompt(panel)
            PaintGoldUpdateDialogButtons(panel)
            if !DllCall("user32\IsWindowVisible", "Ptr", tab.Hwnd, "Int")
                || !DllCall("user32\IsWindowVisible", "Ptr", footer.Hwnd, "Int")
                throw Error("Release note tabs or footer buttons did not become visible.")
            paragraphY := 0, headingY := 0, bulletY := 0, rowHeight := 0
            for row in panel
            {
                if !row.Visible || row.Text = ""
                    continue
                row.GetPos(, &top, &width, &height)
                if row.Text = "First paragraph."
                {
                    paragraphY := top, rowHeight := height
                    CheckBufferedReleaseNoteRow(row)
                }
                else if row.Text = "Section heading"
                    headingY := top
                else if row.Text = "• First bullet."
                    bulletY := top
                if top >= Round(170 * scale) && top < Round(516 * scale) && width = Round(686 * scale)
                {
                    if height < ReleaseNoteLineHeight(row) || top + height > Round(516 * scale)
                        || !ReleaseNoteFits(row, row.Text, width)
                        throw Error("A release note does not fit inside its row.")
                }
            }
            spacing := Max(1, Round(2 * scale)) + Max(1, Round(4 * scale))
            if !paragraphY || headingY - paragraphY != rowHeight + spacing || bulletY - headingY != rowHeight + spacing
                throw Error("Release notes contain a missing heading, bullet, or extra section space.")
        }
        finally
        {
            if IsObject(unregister)
                unregister()
            CloseGoldNativePrompt(panel)
        }
    }
    CheckUpdatePreviewMetadataLayout()
    CheckCenteredCompactUpdateMetadata()
    CheckCircularUpdateBadgeRendering()
    CheckUnreadPublishedReleaseCounts()
    CheckExpandablePublishedPreviewViewport()
    CheckCompactPublishedPreviewViewport()
    CheckMissedUpdateLinkViewport()
    try FileAppend("PASS: live display refresh and reset, loading cleanup, readable release-note rows, and version metadata layout at 50 and 100 percent" Chr(10), "*")
}

; Offline count contract: newly published versions increase the count,
; opening the preview advances the last-viewed baseline, and older releases
; never reappear as unread on the next launcher start.
CheckUnreadPublishedReleaseCounts()
{
    records := [
        {Version: "0.1.21-alpha.4"},
        {Version: "0.1.21-alpha.3"},
        {Version: "0.1.21-alpha.2"},
        {Version: "0.1.21-alpha.1"}
    ]
    seen := Map()
    expected := 4
    if CountUnseenPublishedUpdateRecords(records, "0.1.21-alpha", seen).Count != expected
        throw Error("Four published releases must start as four separate unread receipts.")
    ; Reading the offered newest version must NOT clear the three older ones.
    for version in ["0.1.21-alpha.4", "0.1.21-alpha.2",
        "0.1.21-alpha.1", "0.1.21-alpha.3"]
    {
        seen[version] := true
        expected -= 1
        if CountUnseenPublishedUpdateRecords(records, "0.1.21-alpha", seen).Count != expected
            throw Error("Reading " version " cleared another version's notification.")
    }
    ; Installed and duplicate published versions cannot double-count.
    records.Push({Version: "0.1.21-alpha"}, {Version: "0.1.21-alpha.4"})
    if CountUnseenPublishedUpdateRecords(records, "0.1.21-alpha", Map()).Count != 4
        throw Error("Installed or duplicated releases incorrectly inflated the unread count.")
    ; The only persistent-state smoke uses a disposable INI: it must never
    ; modify the user's live update receipts or installed launcher settings.
    fixture := A_Temp "\tes3np-read-receipts-" DllCall("GetCurrentProcessId", "UInt")
        . "-" A_TickCount ".ini"
    try
    {
        MarkPublishedVersionRead("0.1.21-alpha.4", true, fixture)
        if !IsPublishedVersionRead("0.1.21-alpha.4", fixture)
            || IsPublishedVersionRead("0.1.21-alpha.3", fixture)
            throw Error("Preview read receipt accidentally cleared an older version.")
        MarkPublishedVersionRead("0.1.21-alpha.2", false, fixture)
        if !IsPublishedVersionRead("0.1.21-alpha.2", fixture)
            || IsPublishedVersionRead("0.1.21-alpha.1", fixture)
            throw Error("Link read receipt did not persist independently.")
        if IniRead(fixture, "Updates", "LastAutoPreviewVersion", "") != "0.1.21-alpha.4"
            throw Error("Clicking older GitHub releases changed automatic popup dedup.")
    }
    finally
        try FileDelete(fixture)
    CheckUnreadBadgeTextAdjacency()
    ; The actual launcher uses a PNG Picture control. An earlier Text-only
    ; test passed while Windows painted the native 48px PNG as a 52px circle.
    ; This compiled probe must read the same extracted asset as production:
    ; the bundled-resource preflight runs before --check-owned-menu-scaling.
    ; Scripts in scripts/ are not covered by the staged src/ path rewriter.
    global BundledResourceRoot
    assetRoot := A_IsCompiled ? BundledResourceRoot : A_ScriptDir
    badgeAsset := assetRoot "\assets\controls\update-unread-circle.png"
    if !FileExist(badgeAsset)
        throw Error("Numeric unread badge smoke cannot load bundled PNG: " badgeAsset)
    ; Exercise the real image load order, DPI scaling and Win32 dimensions.
    for percent in [50, 100]
    {
        scale := percent / 100
        dpiScale := GetLauncherBadgeDpiScale()
        diameter := LauncherUnreadBadgeDiameter(24, scale)
        oneDigit := LauncherUnreadBadgeDiameter(1, scale)
        expectedPixels := Max(20, Round(27 * scale))
        if diameter < oneDigit || diameter < 1
            throw Error("Two-digit unread badge must fit a readable, circular number.")
        panel := Gui(, "Native numeric unread badge smoke")
        badge := panel.Add("Picture", "x0 y0 w" diameter " h" diameter
            . " +0x40 BackgroundTrans",
            badgeAsset)
        region := 0
        try
        {
            imagePixels := Max(1, Round(diameter * dpiScale))
            badge.Value := "*w" imagePixels " *h" imagePixels " "
                . badgeAsset
            badge.Move(0, 0, diameter, diameter)
            ShapeCircularUpdateBadge(badge)
            rect := Buffer(16, 0)
            if !DllCall("user32\GetClientRect", "Ptr", badge.Hwnd, "Ptr", rect)
                throw Error("Unread picture bounds cannot be measured.")
            width := NumGet(rect, 8, "Int"), height := NumGet(rect, 12, "Int")
            if width != height || Abs(width - expectedPixels) > 2
                throw Error("Unread badge must be " expectedPixels
                    " physical pixels at " percent "% launcher scale, actual "
                    width "x" height " (DPI " dpiScale ").")
            if width > 30
                throw Error("Footer unread circle is visually oversized: " width " pixels.")
            ; Verify the ACTUAL white two-digit overlay can use a readable
            ; font inside that unchanged circle. Check native text metrics,
            ; not merely the requested point size in source code.
            insetWidth := Max(1, Round(diameter * 0.90))
            insetHeight := insetWidth
            number := panel.Add("Text", "x0 y0 w" insetWidth " h" insetHeight
                . " Center +0x200 BackgroundTrans", "24")
            ApplyLauncherBadgeFont(scale, number)
            ShapeCircularUpdateBadge(number)
            numberRect := Buffer(16, 0)
            if !DllCall("user32\GetClientRect", "Ptr", number.Hwnd,
                "Ptr", numberRect, "Int")
                throw Error("Could not measure unread numeral bounds.")
            usableWidth := Max(1, NumGet(numberRect, 8, "Int") - 1)
            usableHeight := NumGet(numberRect, 12, "Int")
            measuredHeight := ReleaseNoteLineHeight(number)
            if !ReleaseNoteFits(number, number.Text, usableWidth)
                || measuredHeight > usableHeight
                throw Error("Enlarged unread digits clip the unchanged circular badge.")
            if percent = 100 && measuredHeight < 16
                throw Error("Unread numeral is still too small to read at full launcher scale.")
            region := DllCall("gdi32\CreateRectRgn", "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "Ptr")
            if !region
                throw Error("Unread circle region probe failed.")
            kind := DllCall("user32\GetWindowRgn", "Ptr", badge.Hwnd, "Ptr", region, "Int")
            if kind <= 0
                throw Error("Unread picture does not have its circular clipping region.")
            center := width // 2
            if !DllCall("gdi32\PtInRegion", "Ptr", region,
                "Int", center, "Int", center, "Int")
                || DllCall("gdi32\PtInRegion", "Ptr", region,
                    "Int", 0, "Int", 0, "Int")
                throw Error("Unread picture circle must clip its corners, not its center.")
            ; Confirm the transparent number overlays the circle safely.
            if DllCall("user32\GetWindowRgn", "Ptr", number.Hwnd,
                "Ptr", region, "Int") <= 0
                throw Error("Unread numeral overlay is not clipped to a circle.")
            if !DllCall("gdi32\PtInRegion", "Ptr", region,
                "Int", usableWidth // 2, "Int", usableHeight // 2, "Int")
                || DllCall("gdi32\PtInRegion", "Ptr", region,
                    "Int", 0, "Int", 0, "Int")
                throw Error("Unread numeral overlay region is not circular.")
        }
        finally
        {
            if region
                DllCall("gdi32\DeleteObject", "Ptr", region)
            panel.Destroy()
        }
    }
    try FileAppend("PASS: unread counts 4,3,2,1,0 and 20-27px PNG circle with legible fitted numeral" Chr(10), "*")
}

; The version Text control has intentionally padded bounds to avoid clipping
; at small launcher scales. The unread badge must follow the actual rendered
; last glyph, not that large transparent Text rectangle.
CheckUnreadBadgeTextAdjacency()
{
    dpi := GetLauncherBadgeDpiScale()
    panel := Gui(, "Unread badge text adjacency smoke")
    panel.SetFont("s9 cC5A45C", "Segoe UI")
    label := panel.Add("Text", "x12 y10 BackgroundTrans",
        "tes3np · v0.1.21-alpha.1")
    label.GetPos(, , &naturalWidth)
    padded := Ceil(naturalWidth * 1.25) + 4
    try
    {
        for percent in [50, 100]
        {
            scale := percent / 100
            label.Move(Round(12 * scale), Round(10 * scale),
                Round(padded * scale), Round(18 * scale))
            label.SetFont("s" Max(5, Round(9 * scale)), "Segoe UI")
            FitLauncherVersionLabelToText(label)
            label.GetPos(&labelX, , &labelWidth)
            badgeX := GetLauncherUnreadBadgeX(label, scale)
            textPixels := MeasureMissedUpdateTextWidth(label, label.Text)
            if labelWidth < Ceil(textPixels / dpi) + 1
                throw Error("Footer version glyphs still clip after native text fitting.")
            ; The circle previously sat visibly above the text baseline.
            ; Require a positive five-screen-pixel downward alignment.
            downInset := Max(1, Round(5 / dpi))
            if downInset < 1 || Abs(downInset * dpi - 5) > dpi
                throw Error("Unread badge vertical offset is inconsistent with display DPI.")
            screenGap := Round((badgeX - labelX) * dpi - textPixels)
            if screenGap < 0 || screenGap > Round(8 * dpi)
                throw Error("Footer badge must follow visible version text, "
                    "not the padded label bounds; gap=" screenGap
                    " device px at " percent "% scale.")
            if badgeX >= labelX + labelWidth + Max(1, Round(2 * scale))
                throw Error("Footer badge still anchors after the oversized padded text box.")
        }
    }
    finally
        panel.Destroy()
    try FileAppend("PASS: unread badge stays beside rendered version glyphs at 50 and 100 percent" Chr(10), "*")
}

; Verify native clipping for the actual circular red badge at the same
; launcher scales used by the compiled menu suite. Disposable controls only:
; no launcher profile, update feed, installed game or release data is changed.
CheckCircularUpdateBadgeRendering()
{
    for percent in [50, 100]
    {
        panel := Gui("-DPIScale", "Circular update badge smoke")
        badge := panel.Add("Text",
            "x0 y0 w22 h22 Center +0x200 BackgroundD63232", "1")
        badge.SetFont("s10 Bold cFFFFFF", "Segoe UI")
        region := 0
        try
        {
            ScaleOwnedMenuContent(panel, percent / 100)
            ShapeCircularUpdateBadge(badge)
            rect := Buffer(16, 0)
            if !DllCall("user32\GetClientRect", "Ptr", badge.Hwnd, "Ptr", rect, "Int")
                throw Error("Could not measure the native update badge.")
            width := NumGet(rect, 8, "Int")
            height := NumGet(rect, 12, "Int")
            expected := Round(22 * percent / 100)
            if width != expected || height != expected
                throw Error("Circular update badge did not scale to " percent " percent.")
            region := DllCall("gdi32\CreateRectRgn", "Int", 0, "Int", 0,
                "Int", 0, "Int", 0, "Ptr")
            if !region
                throw Error("Could not allocate update badge region probe.")
            kind := DllCall("user32\GetWindowRgn",
                "Ptr", badge.Hwnd, "Ptr", region, "Int")
            if kind = 0 || kind = -1
                throw Error("Circular update badge has no native clipping region.")
            center := expected // 2
            if !DllCall("gdi32\PtInRegion", "Ptr", region,
                "Int", center, "Int", center, "Int")
                || DllCall("gdi32\PtInRegion", "Ptr", region,
                    "Int", 0, "Int", 0, "Int")
                throw Error("Update badge must clip corners but retain its center.")
        }
        finally
        {
            if region
                DllCall("gdi32\DeleteObject", "Ptr", region)
            DestroyScaledMenu(panel)
        }
    }
    try FileAppend("PASS: circular red update badge has native clipping at 50 and 100 percent" Chr(10), "*")
}

; Exercise the real expanded-history scroll viewport against a disposable native
; panel. Only these local fixture notes are used; this never calls the updater,
; changes the published feed, or writes installed-version/user data.
CheckExpandablePublishedPreviewViewport()
{
    global ButtonFaces
    records := [
        {Version: "0.1.21-alpha.3", Label: "v0.1.21-alpha.3",
            Hotfix: true, Notes: "### New Features`n- **Update:** Latest update."},
        {Version: "0.1.21-alpha.2", Label: "v0.1.21-alpha.2",
            Hotfix: true, Notes: "### Improvements`n- **Launcher:** Previous improvement."},
        {Version: "0.1.21-alpha.1", Label: "v0.1.21-alpha.1",
            Hotfix: true, Notes: "### Bug Fixes`n- **Pack:** Older correction."}
    ]
    sections := BuildPublishedPreviewSections(records)
    if sections.EarlierCount != 2
        throw Error("Expected two earlier missed updates in preview fixture.")
    for percent in [50, 100]
    {
        scale := percent / 100
        panel := Gui("-DPIScale", "Missed-update history viewport smoke")
        panel.BackColor := "171008"
        switcher := {Update: 0}
        unregister := 0
        try
        {
            ScaleOwnedMenuContent(panel, scale)
            unregister := AddUpdateNotesViewport(panel, sections.Compact, scale,
                switcher, 44, 28, true)
            if !IsObject(switcher.Update)
                throw Error("Update preview has no expandable history viewport.")
            ; No earlier version's details should be in the compact notes.
            if InStr(sections.Compact, "Previous improvement.")
                || InStr(sections.Compact, "Older correction.")
                throw Error("Compact preview leaked an earlier hotfix's change.")
            ; Match the production callback call style: no implicit receiver.
            switcher.Update.Call(sections.Expanded)
            down := 0
            for control in panel
                if control.Text = "↓"
                    down := control
            if !IsObject(down) || !ButtonFaces.Has(down.Hwnd)
                throw Error("Update preview has no scroll-down button.")
            foundPrevious := false, foundOlder := false
            Loop 100
            {
                for row in panel
                {
                    if !row.Visible
                        continue
                    if InStr(row.Text, "Previous improvement.")
                        foundPrevious := true
                    if InStr(row.Text, "Older correction.")
                        foundOlder := true
                    if !InStr(row.Text, "Previous improvement.")
                        && !InStr(row.Text, "Older correction.")
                        continue
                    row.GetPos(, &top, , &height)
                    if top < Round(214 * scale) || top + height > Round(544 * scale)
                        throw Error("Expanded missed-update content overlaps the preview header or footer.")
                }
                if foundPrevious && foundOlder
                    break
                ButtonFaces[down.Hwnd].Action.Call()
            }
            if !foundPrevious || !foundOlder
                throw Error("Earlier missed hotfix details cannot be reached by scrolling.")
            switcher.Update.Call(sections.Compact)
            for row in panel
                if row.Visible && (InStr(row.Text, "Previous improvement.")
                    || InStr(row.Text, "Older correction."))
                    throw Error("Collapsing earlier history did not hide older changes.")
        }
        finally
        {
            if IsObject(unregister)
                unregister()
            DestroyScaledMenu(panel)
        }
    }
    try FileAppend("PASS: expandable missed-update history scrolls and collapses at 50 and 100 percent" Chr(10), "*")
}

; Confirm the real 600px-wide reference composition keeps its notes inside
; the reserved upper section, with earlier history pinned beneath it. All
; controls and release records are disposable and contain no public update.
CheckCompactPublishedPreviewViewport()
{
    global ButtonFaces
    records := [
        {Version: "0.1.21-alpha.3", Label: "v0.1.21-alpha.3",
            Hotfix: true, Notes: "### New Features`n- Red circular 1 update notification.`n`n### Improvements`n- Cleaner update preview layout.`n- Better readability for grouped changes.`n`n### Bug Fixes`n- Fixed Expansion Pack disable flow when verification fails."},
        {Version: "0.1.21-alpha.2", Label: "v0.1.21-alpha.2",
            Hotfix: true, Notes: "### Improvements`n- Previous sample improvement."},
        {Version: "0.1.21-alpha.1", Label: "v0.1.21-alpha.1",
            Hotfix: true, Notes: "### Bug Fixes`n- Older sample repair."}
    ]
    sections := BuildPublishedPreviewSections(records)
    if sections.Title != "Latest Patch — v0.1.21-alpha.3"
        || sections.EarlierLabels.Length != 2
        || !InStr(sections.Latest, "New Features")
        || InStr(sections.Latest, "Previous sample improvement.")
        throw Error("Compact preview latest/earlier data contract changed.")
    for percent in [41, 50, 82, 100]
    {
        scale := percent / 100
        panel := Gui("-DPIScale", "Compact preview viewport regression")
        panel.BackColor := "171008"
        switcher := {Update: 0}
        unregister := 0
        try
        {
            ScaleOwnedMenuContent(panel, scale)
            unregister := AddUpdateNotesViewport(panel, sections.Latest, scale,
                switcher, 0, 100, true, true, true)
            if !IsObject(switcher.Update)
                throw Error("Compact preview scroll-update callback was not initialized.")
            borderFound := false, up := 0, down := 0, track := 0, thumb := 0
            for control in panel
            {
                control.GetPos(&cx, &cy, &cw, &ch)
                if Abs(cx - Round(23 * scale)) <= 1
                    && Abs(cy - Round(168 * scale)) <= 1
                    && Abs(cw - Round(554 * scale)) <= 1
                    && Abs(ch - Round(241 * scale)) <= 1
                    borderFound := true
                if control.Text = "↑"
                    up := control
                if control.Text = "↓"
                    down := control
                if Abs(cx - Round(561 * scale)) <= 1
                    && Abs(cw - Round(16 * scale)) <= 1
                    && ch > Round(100 * scale)
                    track := control
                if Abs(cx - Round(565 * scale)) <= 1
                    && Abs(cw - Round(8 * scale)) <= 1
                    thumb := control
            }
            if !borderFound
                throw Error("Compact gold viewport does not match the reference card bounds.")
            if !IsObject(up) || !IsObject(down) || !IsObject(track) || !IsObject(thumb)
                throw Error("Compact preview scrollbar controls are missing.")
            if !ButtonFaces.Has(down.Hwnd)
                throw Error("Compact preview scroll-down button lost its themed face.")
            ; Track and thumb must be wholly between the arrows, not painted
            ; beneath the upper button as in the regressed production preview.
            up.GetPos(, &upY, , &upHeight)
            down.GetPos(, &downY)
            track.GetPos(, &trackY, , &trackHeight)
            if trackY < upY + upHeight + Max(1, Round(2 * scale))
                || trackY + trackHeight > downY - Max(1, Round(2 * scale))
                throw Error("Compact scrollbar track overlaps an arrow button.")
            ; The taller missed-version list intentionally shortens the
            ; changelog. Confirm the first heading and the last fix remain
            ; available through its independent arrowed scrollbar.
            if percent = 82 || percent = 100
            {
                seenFirst := false, seenLast := false
                for row in panel
                    if row.Visible && row.Text = "New Features"
                        seenFirst := true
                if !seenFirst
                    throw Error("Compact notes lost the first New Features heading.")
                Loop 100
                {
                    for row in panel
                        if row.Visible && InStr(row.Text, "Fixed Expansion Pack")
                            seenLast := true
                    if seenLast
                        break
                    if !down.Visible
                        throw Error("Latest changelog cannot scroll to its last fix.")
                    ButtonFaces[down.Hwnd].Action.Call()
                }
                if !seenLast
                    throw Error("Compact latest notes cannot reach the final Bug Fixes entry.")
            }
            switcher.Update.Call(sections.Expanded)
            if track.Visible != thumb.Visible
                throw Error("Compact scrollbar track and thumb visibility disagree.")
            if track.Visible
            {
                thumb.GetPos(, &thumbY, , &thumbHeight)
                if thumbY < trackY || thumbY + thumbHeight > trackY + trackHeight
                    throw Error("Compact scrollbar thumb extends outside its track.")
            }
            seenOlder := false
            Loop 100
            {
                for row in panel
                {
                    if !row.Visible || !InStr(row.Text, "Older sample repair.")
                        continue
                    row.GetPos(, &y, , &height)
                    if y < Round(178 * scale) || y + height > Round(409 * scale)
                        throw Error("Expanded earlier notes overlap the fixed preview summary.")
                    seenOlder := true
                }
                if seenOlder
                    break
                ButtonFaces[down.Hwnd].Action.Call()
            }
            if !seenOlder
                throw Error("Earlier note cannot be scrolled into the compact preview.")
            switcher.Update.Call(sections.Latest)
            for row in panel
                if row.Visible && InStr(row.Text, "Older sample repair.")
                    throw Error("Collapsing compact history did not restore latest-only notes.")
        }
        finally
        {
            if IsObject(unregister)
                unregister()
            DestroyScaledMenu(panel)
        }
    }
    ; Exercise the bundled hotfix release-note text as well as short
    ; isolated fixtures: the final Bug Fixes must fit at 100%.
    realNotes := ReadBundledVersionNotes("0.1.21-alpha.1")
    if realNotes != ""
    {
        realSection := BuildPublishedPreviewSections([
            {Version: "0.1.21-alpha.1", Label: "v0.1.21-alpha.1",
                Hotfix: true, Notes: realNotes}])
        panel := Gui("-DPIScale", "Bundled release-note clipping check")
        unregister := 0
        try
        {
            switcher := {Update: 0}
            unregister := AddUpdateNotesViewport(panel, realSection.Latest, 1.0,
                switcher, 0, 100, true, true, false)
            ; The real changelog is scrollable. A valid final fix may be
            ; below the first page; verify that the native arrows reach it.
            seenFix := false, seenFirstFix := false, seenFinalFix := false
            down := 0
            for control in panel
                if control.Text = Chr(0x2193)
                    down := control
            if !IsObject(down) || !ButtonFaces.Has(down.Hwnd)
                throw Error("Bundled hotfix scrollbar has no native down action.")
            Loop 100
            {
                for control in panel
                {
                    if !control.Visible
                        continue
                    if control.Text = "Bug Fixes"
                        seenFix := true
                    if InStr(control.Text, "Fixed an issue")
                        seenFirstFix := true
                    if InStr(control.Text, "verified.")
                        seenFinalFix := true
                    if control.Text = "Bug Fixes"
                        || InStr(control.Text, "Fixed an issue")
                        || InStr(control.Text, "verified.")
                    {
                        control.GetPos(, &rowY, , &rowHeight)
                        if rowY < 178 || rowY + rowHeight > 580
                            throw Error("Bundled hotfix note exceeds scroll viewport.")
                    }
                }
                if seenFix && seenFirstFix && seenFinalFix
                    break
                if !down.Visible
                    break
                ButtonFaces[down.Hwnd].Action.Call()
            }
            if !seenFix || !seenFirstFix || !seenFinalFix
                throw Error("Bundled hotfix Bug Fixes cannot all be reached: "
                    . "heading=" seenFix ", first=" seenFirstFix
                    ", final=" seenFinalFix ".")
        }
        finally
        {
            if IsObject(unregister)
                unregister()
            DestroyScaledMenu(panel)
        }
    }
    try FileAppend("PASS: full-height production preview and bundled hotfix clipping at 41, 50, 82 and 100 percent" Chr(10), "*")
}

; Verify one, three, and many published update links at the actual native
; preview scales. These disposable versions never reach GitHub or the updater.
CheckMissedUpdateLinkViewport()
{
    global ButtonFaces
    for count in [1, 3, 7, 24]
    {
        ; Generate one offered version followed by exactly 'count' older
        ; skipped releases; the offered version must NEVER enter this list.
        offered := "0.1.21-alpha." (count + 1)
        records := [{Version: offered, Label: "v" offered,
            Hotfix: true, Notes: "### Bug Fixes`n- Current offered update."}]
        Loop count
        {
            version := "0.1.21-alpha." (count - A_Index + 1)
            records.Push({Version: version, Label: "v" version,
                Hotfix: true, Notes: "### Bug Fixes`n- A verified test note."})
        }
        sections := BuildPublishedPreviewSections(records)
        if sections.MissedVersions.Length != count
            throw Error("Missed-updates list included the current offer or lost earlier releases.")
        if sections.MissedVersions[1].Version != records[2].Version
            || sections.MissedVersions[count].Version != records[count + 1].Version
            throw Error("Missed versions do not preserve newest-first order.")
        for record in sections.MissedVersions
            if record.Url != GetPublishedVersionNotesUrl(record.Version)
                throw Error("Missed update does not link to its exact GitHub release tag.")
        for percent in [41, 50, 82, 100]
        {
            scale := percent / 100
            panel := Gui("-DPIScale", "Missed updates viewport smoke")
            ; Mirror the production heading BEFORE launcher scaling, so its
            ; real scaled HWND bounds can be checked against the opaque list.
            panel.SetFont("s12 Bold cE7BE70", "Georgia")
            heading := panel.Add("Text", "x40 y424 w520 h28 BackgroundTrans", "Updates You Missed")
            ; Disposable records exercise one, several and many releases.
            ; Their read callbacks never access the user's real INI state.
            items := sections.MissedVersions
            seen := Map()
            state := {Offered: "",
                IsRead: (version) => seen.Has(version),
                MarkRead: (version) => (seen[version] := true),
                RefreshCount: (*) => 0}
            observer := {}
            unregister := 0
            try
            {
                ScaleOwnedMenuContent(panel, scale)
                unregister := AddMissedUpdateLinks(panel, items,
                    scale, 0, 100, heading, observer, state)
                if !IsObject(observer.Refresh) || observer.Rows.Length != 4
                    || observer.Badges.Length != 4 || !IsObject(observer.Clear)
                    throw Error("Missed-updates viewport did not initialize its rows.")
                expectedCaption := count > 1 ? "Mark All Read" : "Mark Read"
                if observer.Clear.Text != expectedCaption
                    throw Error("Unread-count action caption incorrect on initialization.")
                if !IsMissedUpdateCursorTarget(observer.Rows[1].Hwnd)
                    || !IsMissedUpdateCursorTarget(observer.Badges[1].Hwnd)
                    throw Error("Clickable release controls must use the hand cursor.")
                ; Every link begins at the production inset, independent
                ; of how many published versions must be displayed.
                observer.Rows[1].GetPos(&firstLinkX)
                if Abs(firstLinkX - Round(48 * scale)) > 1
                    throw Error("Version links must start at the production row inset.")
                ; This previously passed because the smoke test contained no
                ; heading: the list was drawn five pixels over its last glyphs.
                heading.GetPos(, &headingY, , &headingHeight)
                observer.Viewport.GetPos(, &listY, , &listHeight)
                if listY < headingY + headingHeight + Max(1, Round(8 * scale))
                    throw Error("Opaque missed-updates viewport covers the heading text.")
                if listY + listHeight > Round(622 * scale) + 1
                    throw Error("Missed-updates viewport spills below the gold frame.")
                ; Actual lower heading separator is at y454. The first
                ; release link needs visible air below it at all scales.
                if listY < Round(462 * scale) - 1
                    throw Error("First missed-version entry starts too close to its gold divider.")
                visible := 0
                previousBottom := 0
                for slot, row in observer.Rows
                {
                    badge := observer.Badges[slot]
                    if !row.Visible
                    {
                        if badge.Visible
                            throw Error("An offscreen missed update retains its red (1) badge.")
                        continue
                    }
                    if !badge.Visible
                        throw Error("A visible missed update is missing its red (1) badge.")
                    visible += 1
                    row.GetPos(&x, &y, &width, &height)
                    if previousBottom && y <= previousBottom
                        throw Error("Missed-update Text controls overlap and may erase glyphs.")
                    previousBottom := y + height
                    badge.GetPos(&badgeX, &badgeY, &badgeWidth, &badgeHeight)
                    if badgeX < x || badgeX + badgeWidth > x + width
                        || badgeY < y || badgeY + badgeHeight > y + height
                        || Abs(badgeWidth - Round(20 * scale)) > 1
                        || Abs(badgeHeight - Round(20 * scale)) > 1
                        throw Error("Red (1) must stay directly beside its missed version inside the visible link.")
                    if x < Round(48 * scale) - 1
                        || x + width > Round(544 * scale) + 1
                        || y < Round(462 * scale) - 1
                        || y + height > Round(622 * scale) + 1
                        || !ReleaseNoteFits(row, row.Text, width)
                        || height < ReleaseNoteLineHeight(row) + Round(8 * scale)
                        throw Error("A missed-update hyperlink or its font clips the lower gold frame.")
                }
                if visible != Min(observer.Page.VisibleRows, count)
                    throw Error("Missed-updates list shows the wrong number of visible links.")
                if percent = 100 && count = 24 && observer.Page.VisibleRows < 4
                    throw Error("A normal-sized missed-updates list must display four entries: "
                        observer.Page.VisibleRows " fitted, native row=" observer.RowHeight
                        "px, step=" observer.RowStep "px, list top=" listY
                        "px, bottom=" observer.BottomLimit "px.")
                scrollExpected := count > observer.Page.VisibleRows
                if (observer.Track.Visible || observer.Thumb.Visible
                    || observer.Up.Visible || observer.Down.Visible) != scrollExpected
                    throw Error("Missed-updates arrows and scrollbar must appear together only when scrolling is needed.")
                if !ButtonFaces.Has(observer.Up.Hwnd) || !ButtonFaces.Has(observer.Down.Hwnd)
                    throw Error("Missed-updates arrows do not use the parent changelog's themed buttons.")
                observer.Up.GetPos(, &upY, , &upHeight)
                observer.Down.GetPos(, &downY)
                observer.Track.GetPos(, &trackY, , &trackHeight)
                if trackY < upY + upHeight + Max(1, Round(2 * scale))
                    || trackY + trackHeight > downY - Max(1, Round(2 * scale))
                    throw Error("Missed-update scrollbar track overlaps a themed arrow.")
                if count > observer.Page.VisibleRows
                {
                    observer.Page.Offset := observer.Page.MaxOffset
                    observer.Refresh.Call()
                    foundLast := false
                    for row in observer.Rows
                        if row.Visible && row.Text = sections.MissedVersions[count].Label
                            foundLast := true
                    if !foundLast
                        throw Error("Scrolling missed updates cannot reach the oldest omitted version.")
                    observer.Track.GetPos(, &trackY, , &trackHeight)
                    observer.Thumb.GetPos(, &thumbY, , &thumbHeight)
                    if thumbY < trackY || thumbY + thumbHeight > trackY + trackHeight
                        throw Error("Missed-updates scrollbar thumb escapes the track.")
                }
                ; Mark Read is a fixed footer control, not an item in the
                ; scrollable release list. It must be visible at BOTH ends.
                if !observer.Clear.Visible || observer.Clear.Text != expectedCaption
                    throw Error("Unread-count action must stay visible beneath release links.")
                observer.Clear.GetPos(&clearX, &clearY, &clearWidth, &clearHeight)
                originalClearY := clearY
                if clearX < Round(34 * scale) - 1
                    || clearY < listY + listHeight + Max(1, Round(4 * scale))
                    || clearY + clearHeight > Round(654 * scale) + 1
                    throw Error("Mark Read must fit inside the reserved gold footer area.")
                observer.Page.Offset := observer.Page.MaxOffset
                observer.Refresh.Call()
                observer.Clear.GetPos(, &scrolledClearY)
                if !observer.Clear.Visible || scrolledClearY != originalClearY
                    throw Error("Mark Read moved or disappeared when scrolling releases.")
                if count >= 7
                {
                    ; Only the selected release is marked read first.
                    observer.Page.Offset := 1
                    observer.Refresh.Call()
                    first := items[1]
                    MarkMissedUpdateItemRead(observer.Page, first)
                    observer.Refresh.Call()
                    if !IsMissedUpdateRead(observer.Page, first)
                        || observer.Badges[1].Visible
                        throw Error("Click-to-read hid the entry or left its red notification visible.")
                    ClearMissedUpdateBadges(observer.Page)
                    if !observer.Clear.Visible || observer.Clear.Text != "Mark Read"
                        throw Error("Mark Read must remain visible after clearing.")
                    for item in items
                        if !IsMissedUpdateRead(observer.Page, item)
                            throw Error("Clear failed to mark all missed versions read.")
                    observer.Page.Offset := 1
                    observer.Refresh.Call()
                    if !observer.Rows[1].Visible || observer.Badges[1].Visible
                        throw Error("Clear must preserve visible links while hiding their red badge.")
                }
                if count = 3 && percent = 100
                {
                    MarkMissedUpdateItemRead(observer.Page, items[1])
                    MarkMissedUpdateItemRead(observer.Page, items[2])
                    observer.Refresh.Call()
                    if observer.Clear.Text != "Mark Read"
                        throw Error("One remaining unread release must display Mark Read.")
                    MarkMissedUpdateItemRead(observer.Page, items[3])
                    observer.Refresh.Call()
                    if observer.Clear.Text != "Mark Read"
                        throw Error("Cleared release list must not show Mark All Read.")
                }
            }
            finally
            {
                if IsObject(unregister)
                {
                    unregister()
                    if IsMissedUpdateCursorTarget(observer.Rows[1].Hwnd)
                        throw Error("Closed preview retained stale link-cursor target.")
                }
                panel.Destroy()
            }
        }
    }
    try FileAppend("PASS: missed-update links and red (1) markers fit and scroll for 1, 3, 7 and 24 versions at 41-100 percent" Chr(10), "*")
}

; Exercise actual AutoHotkey Text autosizing and the metadata fallback without
; showing an update or changing any installed profile, game, or release data.
CheckUpdatePreviewMetadataLayout()
{
    scenarios := [
        {Installed: "0.1.20-alpha", Latest: "0.1.22-alpha.2", Channel: "alpha"},
        {Installed: "0.1.22-alpha.1", Latest: "0.1.22-alpha.2", Channel: "alpha"},
        {Installed: "0.1.22-alpha.10", Latest: "0.1.23-alpha.100", Channel: "alpha"},
        {Installed: "1.0.0-live.10", Latest: "1.0.0-live.100", Channel: "live"},
        ; Deliberately long build numbers exercise the second- and third-row
        ; fallback so future hotfix suffixes never paint over Channel.
        {Installed: "0.1.22-alpha.12345678901234567890",
            Latest: "0.1.23-alpha.12345678901234567890", Channel: "alpha"},
        {Installed: "0.1.22-alpha.1234567890123456789012345678901234567890",
            Latest: "0.1.23-alpha.1234567890123456789012345678901234567890", Channel: "alpha"}
    ]
    for scenario in scenarios
    {
        metadataPanel := Gui("-DPIScale")
        try
        {
            extra := AddUpdatePreviewMetadata(metadataPanel,
                scenario.Installed, scenario.Latest, scenario.Channel)
            bounds := [], separators := 0
            for control in metadataPanel
            {
                control.GetPos(&x, &y, &width, &height)
                ; The premium metadata card includes decorative gold rules.
                ; Keep caption validation strict, and separately verify the
                ; dividers rather than treating them as truncated captions.
                if control.Text = ""
                {
                    if width != 1 || height != 18 || y != 83 || x < 30 || x > 770
                        throw Error("Gold metadata separator escaped its measured gap.")
                    separators += 1
                    continue
                }
                fits := ReleaseNoteFits(control, control.Text, width)
                if x < 30 || x + width > 770 || width < 1 || height != 26 || !fits
                    throw Error("Update preview metadata is clipped or offscreen: " control.Text
                        " [x=" x ", y=" y ", width=" width ", height=" height ", textFits=" fits "]")
                bounds.Push({X: x, Y: y, Right: x + width, Bottom: y + height})
            }
            if bounds.Length != 3 || (extra != 0 && extra != 32 && extra != 64)
                throw Error("Update preview metadata layout returned invalid controls or spacing.")
            expectedSeparators := extra = 0 ? 2 : extra = 32 ? 1 : 0
            if separators != expectedSeparators
                throw Error("Gold metadata dividers do not match the wrapped caption rows.")
            bottomRow := Max(bounds[1].Y, bounds[2].Y, bounds[3].Y)
            if bottomRow - 80 != extra
                throw Error("Update preview frame does not follow the bottom metadata row.")
            for i, current in bounds
                for j, later in bounds
                {
                    if j <= i
                        continue
                    if current.X < later.Right && current.Right > later.X
                        && current.Y < later.Bottom && current.Bottom > later.Y
                        throw Error("Update preview metadata overlaps at this version length.")
                }
        }
        finally
            metadataPanel.Destroy()
    }
}

; Use real AHK Text measurement to ensure reference-size update metadata is
; centered as one group with padding and cannot overlap a neighboring field.
CheckCenteredCompactUpdateMetadata()
{
    cases := [
        {Installed: "0.1.21-alpha", Latest: "0.1.21-alpha.3", Channel: "alpha"},
        {Installed: "0.1.22-alpha.10", Latest: "0.1.23-alpha.100", Channel: "alpha"}
    ]
    for item in cases
    {
        panel := Gui("-DPIScale")
        try
        {
            extra := AddUpdatePreviewMetadata(panel, item.Installed, item.Latest,
                item.Channel, true)
            if extra != 0
                throw Error("Compact Installed | Latest | Channel must stay on one line.")
            textParts := [], separators := []
            for control in panel
            {
                control.GetPos(&x, &y, &width, &height)
                if control.Text = ""
                {
                    separators.Push({X: x, Y: y, Width: width, Height: height})
                    continue
                }
                if x < 48 || x + width > 552 || y != 61 || height != 26
                    throw Error("Compact metadata clipped or wrapped onto another line.")
                if !ReleaseNoteFits(control, control.Text, width)
                    throw Error("Compact metadata text was truncated.")
                textParts.Push({Text: control.Text, X: x, Y: y,
                    Right: x + width, Bottom: y + height})
            }
            if textParts.Length != 6 || separators.Length != 2
                throw Error("Compact preview requires three separately colored label/value pairs and two dividers.")
            expectedLabels := ["Installed:", "Latest:", "Channel:"]
            expectedValues := ["v" item.Installed, "v" item.Latest, item.Channel]
            fields := []
            Loop 3
            {
                label := textParts[2 * A_Index - 1]
                value := textParts[2 * A_Index]
                if label.Text != expectedLabels[A_Index] || value.Text != expectedValues[A_Index]
                    throw Error("Compact label/value texts do not match the reference.")
                if label.Y != value.Y || value.X - label.Right != 3
                    throw Error("Gold metadata labels must align directly before their ivory values.")
                fields.Push({X: label.X, Right: value.Right})
            }
            visualCenter := (fields[1].X + fields[3].Right) / 2
            if Abs(visualCenter - 300) > 2
                throw Error("Installed/Latest/Channel are not centered together.")
            if fields[1].X < 48 || fields[3].Right > 552
                throw Error("Compact metadata lost its balanced side padding.")
            if fields[1].Right >= fields[2].X || fields[2].Right >= fields[3].X
                throw Error("Compact metadata fields overlap.")
            for sep in separators
                if sep.Y != 64 || sep.Width != 1 || sep.Height != 18
                    throw Error("Gold column divider not aligned with metadata.")
            if separators[1].X - fields[1].Right < 8
                || fields[2].X - (separators[1].X + 1) < 8
                || separators[2].X - fields[2].Right < 8
                || fields[3].X - (separators[2].X + 1) < 8
                throw Error("Gold separators need visible breathing room on both sides.")
        }
        finally
            panel.Destroy()
    }
    try FileAppend("PASS: gold metadata labels and ivory values, centered with safe dividers" Chr(10), "*")
}

; Exercise the update handshake without launching the UI or writing AppData.
CheckUpdateStateHandshake()
{
    try
    {
        GetPendingUpdateStatePath()
        ExitApp(0)
    }
    catch Error as err
    {
        FileAppend("Update-state probe: " err.Message Chr(10), "*")
        ExitApp(223)
    }
}
