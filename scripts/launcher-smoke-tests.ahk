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
    latest := InStr(installed, "## Latest Hotfix — v0.1.21-alpha.1")
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
    newest := InStr(stacked, "## Latest Hotfix — v0.1.21-alpha.2")
    earlier := InStr(stacked, "## Earlier Hotfix — v0.1.21-alpha.1")
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
        || !InStr(previewSections.Title, "Latest Hotfix — v0.1.21-alpha.3")
        || !InStr(previewSections.Compact, "**Updater:** Latest repair.")
        || !InStr(previewSections.Compact, "You also missed 2 earlier updates.")
        || InStr(previewSections.Compact, "**Launcher:** Previous improvement.")
        || !InStr(previewSections.Expanded, "**Launcher:** Previous improvement.")
        || !InStr(previewSections.Expanded, "**Pack:** Fixed disabling.")
        return false
    previewOnly := BuildPublishedPreviewSections([newestMissed])
    if previewOnly.EarlierCount != 0 || previewOnly.Compact != previewOnly.Expanded
        return false
    unavailablePreview := EmptyPublishedPreviewSections("Published release history is unavailable.")
    if unavailablePreview.Title != "" || unavailablePreview.EarlierCount
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

; The owned-menu probe already runs on Windows in CI. Use its disposable owner
; to exercise the real display refresh and release-note rows at both extremes.
CheckDisplaySettingsAndReleaseNotes()
{
    global LauncherGui, LauncherHeading, LauncherScale, LauncherScaleMode, LauncherRequestedScale, ButtonFaces
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
                    paragraphY := top, rowHeight := height
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
    CheckExpandablePublishedPreviewViewport()
    CheckCompactPublishedPreviewViewport()
    try FileAppend("PASS: live display refresh and reset, loading cleanup, readable release-note rows, and version metadata layout at 50 and 100 percent" Chr(10), "*")
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
    if sections.Title != "Latest Hotfix — v0.1.21-alpha.3"
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
                    && Abs(ch - Round(305 * scale)) <= 1
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
            if !IsObject(up) || !IsObject(down) || !ButtonFaces.Has(down.Hwnd)
                || !IsObject(track) || !IsObject(thumb)
                throw Error("Compact preview scrollbar controls are missing.")
            ; Track and thumb must be wholly between the arrows, not painted
            ; beneath the upper button as in the regressed production preview.
            up.GetPos(, &upY, , &upHeight)
            down.GetPos(, &downY)
            track.GetPos(, &trackY, , &trackHeight)
            if trackY < upY + upHeight + Max(1, Round(2 * scale))
                || trackY + trackHeight > downY - Max(1, Round(2 * scale))
                throw Error("Compact scrollbar track overlaps an arrow button.")
            ; Full-sized initial preview must show the first heading and last
            ; fix simultaneously, with no orphan scrollbar when content fits.
            if percent = 82 || percent = 100
            {
                seenFirst := false, seenLast := false
                for row in panel
                {
                    if !row.Visible
                        continue
                    if row.Text = "New Features"
                        seenFirst := true
                    if InStr(row.Text, "Fixed Expansion Pack")
                        seenLast := true
                }
                if !seenFirst || !seenLast
                    throw Error("Compact Update Preview hides the first category or last bug fix at 100 percent.")
                if down.Visible
                    throw Error("No-scroll compact notes should not display orphan scrollbar arrows.")
            }
            switcher.Update.Call(sections.Expanded)
            if !track.Visible || !thumb.Visible
                throw Error("Expanded changelog did not show the scroll track and thumb.")
            thumb.GetPos(, &thumbY, , &thumbHeight)
            if thumbY < trackY || thumbY + thumbHeight > trackY + trackHeight
                throw Error("Compact scrollbar thumb extends outside its track.")
            seenOlder := false
            Loop 100
            {
                for row in panel
                {
                    if !row.Visible || !InStr(row.Text, "Older sample repair.")
                        continue
                    row.GetPos(, &y, , &height)
                    if y < Round(178 * scale) || y + height > Round(473 * scale)
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
    ; Exercise the actual pending .1 release-note text, not only fabricated
    ; short data: the final Bug Fixes section must be visible at 100%.
    realNotes := ReadBundledVersionNotes("0.1.21-alpha.1")
    if realNotes != ""
    {
        realSection := BuildPublishedPreviewSections([
            {Version: "0.1.21-alpha.1", Label: "v0.1.21-alpha.1",
                Hotfix: true, Notes: realNotes}])
        panel := Gui("-DPIScale", "Real unreleased release-note clipping check")
        unregister := 0
        try
        {
            switcher := {Update: 0}
            unregister := AddUpdateNotesViewport(panel, realSection.Latest, 1.0,
                switcher, 0, 100, true, true, false)
            seenFix := false, seenLastLine := false
            for control in panel
                if control.Visible
                {
                    if control.Text = "Bug Fixes"
                        seenFix := true
                    if InStr(control.Text, "Fixed an issue")
                        seenLastLine := true
                }
            if !seenFix || !seenLastLine
                throw Error("Real pending hotfix has clipped Bug Fixes notes at 100%.")
        }
        finally
        {
            if IsObject(unregister)
                unregister()
            DestroyScaledMenu(panel)
        }
    }
    try FileAppend("PASS: full-height production preview and draft hotfix clipping at 41, 50, 82 and 100 percent" Chr(10), "*")
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
            labels := [], separators := []
            for control in panel
            {
                control.GetPos(&x, &y, &width, &height)
                if control.Text = ""
                {
                    separators.Push({X: x, Y: y, Width: width, Height: height})
                    continue
                }
                if x < 44 || x + width > 556 || y != 61 || height != 26
                    throw Error("Compact metadata clipped or wrapped onto another line.")
                if !ReleaseNoteFits(control, control.Text, width)
                    throw Error("Compact metadata text was truncated.")
                labels.Push({X: x, Right: x + width, Y: y, Bottom: y + height})
            }
            if labels.Length != 3 || separators.Length != 2
                throw Error("Compact preview needs all three captions and two gold dividers.")
            visualCenter := (labels[1].X + labels[3].Right) / 2
            if Abs(visualCenter - 300) > 2
                throw Error("Installed/Latest/Channel are not centered together.")
            if labels[1].Right >= labels[2].X
                || labels[2].Right >= labels[3].X
                throw Error("Compact metadata fields overlap.")
            for sep in separators
                if sep.Y != 64 || sep.Width != 1 || sep.Height != 18
                    throw Error("Gold column divider not aligned with metadata.")
            if separators[1].X <= labels[1].Right
                || separators[1].X >= labels[2].X
                || separators[2].X <= labels[2].Right
                || separators[2].X >= labels[3].X
                throw Error("Gold separators must sit between adjacent metadata labels.")
        }
        finally
            panel.Destroy()
    }
    try FileAppend("PASS: Installed | Latest | Channel on one centered line with two gold separators" Chr(10), "*")
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
