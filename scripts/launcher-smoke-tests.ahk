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

CheckGameLoginProgressFit()
{
    game := {X: -1300, Y: 20, Width: 1100, Height: 902}
    client := {X: -1292, Y: 51, Width: 1084, Height: 863}
    normal := FitGameLoginProgress(client, game, 1.5)
    if normal.Scale != 1.5 || normal.Width != 630 || normal.Height != 722
        || normal.X != -1065 || normal.Y != 110
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
                return false
            layout := {X: 75 + A_Index * 5, Y: 80, Width: 100, Height: 120}
            foreground := DllCall("GetForegroundWindow", "Ptr")
            if !PositionGameLoginProgress(card.Hwnd, game.Hwnd, layout, A_Index = 1, true)
                || DllCall("GetWindow", "Ptr", game.Hwnd, "UInt", 3, "Ptr") != card.Hwnd
                || !DllCall("IsWindowVisible", "Ptr", card.Hwnd)
                || DllCall("GetForegroundWindow", "Ptr") != foreground
                return false
            ; Raise the covering window in the same band. The card should
            ; stay above the game and below the covering window.
            if !DllCall("SetWindowPos", "Ptr", cover.Hwnd, "Ptr", topOfBand,
                "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13, "Int")
                return false
            if !PositionGameLoginProgress(card.Hwnd, game.Hwnd, layout, false, false)
                || DllCall("GetWindow", "Ptr", game.Hwnd, "UInt", 3, "Ptr") != card.Hwnd
                || DllCall("GetWindow", "Ptr", card.Hwnd, "UInt", 3, "Ptr") != cover.Hwnd
                || ((WinGetExStyle("ahk_id " card.Hwnd) & 0x8) != 0) != (topOfBand = -1)
                || DllCall("GetForegroundWindow", "Ptr") != foreground
                return false
            WinGetPos(&x, &y, &width, &height, "ahk_id " card.Hwnd)
            if x != layout.X || y != layout.Y || width != layout.Width || height != layout.Height
                return false
        }
    }
    finally
    {
        card.Destroy()
        cover.Destroy()
        game.Destroy()
    }
    FileAppend("PASS: login card stays with the unfocused game in normal and topmost Z-order`n", "*")
    return true
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
    global LauncherGui, LauncherScale, LauncherScaleMode, LauncherCachedScale, LauncherControlLayout, LauncherCachedLayoutCount, ButtonFaces
    LauncherGui := Gui("-Caption -Border", "Cached return smoke")
    LauncherGui.Show("w560 h350")
    LauncherScale := 100
    LauncherScaleMode := "Manual"
    LauncherCachedScale := 100
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
    global LauncherGui, LauncherHeading, LauncherScale, LauncherScaleMode, ButtonFaces
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
                LauncherScale := percent
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
        unregister := 0
        try
        {
            ScaleOwnedMenuContent(panel, scale)
            unregister := AddUpdateNotesViewport(panel, notes, scale)
            ShowGoldNativePrompt(panel)
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
    try FileAppend("PASS: live display refresh and reset, loading cleanup, and readable release-note rows at 50 and 100 percent" Chr(10), "*")
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
