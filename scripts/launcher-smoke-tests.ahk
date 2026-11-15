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
    }
}

CheckCrashRecoveryProfiles()
{
    global Profiles
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
    ExitApp(0)
}

; Noninteractive compiled-host probe. Verify native expansion progress can
; resolve its actual UI functions without starting any window or game.
CheckExpansionProgressBindings()
{
    global ButtonFaces
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
    ; Execute the progress painting routine against a disposable in-memory
    ; panel. No visible window or game files are involved. This exercises the
    ; exact callback path that had previously warned only on a real click.
    try
    {
        probePanel := {Hwnd: 0, Text: ""}
        probeFrame := {Panel: probePanel}
        ButtonFaces[0] := {Progress: 0}
        painterName := "UpdateExpansionLoadingProgress"
        painter := %painterName%
        painter.Call(probeFrame, "Expansion progress probe", 37)
        if Abs(ButtonFaces[0].Progress - 0.37) > 0.0001
            || probePanel.Text != "Expansion progress probe"
            ExitApp(93)
        ButtonFaces.Delete(0)
    }
    catch
        ExitApp(94)
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
        DestroyScaledMenu(child)
        for font in fonts
            if DllCall("gdi32\GetObjectType", "Ptr", font, "UInt")
                ExitApp(221)
        FileAppend("PASS: menus follow moved owner, stay onscreen and scale 50-100 percent" Chr(10), "*")
    }
    catch Error as err
    {
        FileAppend("FAIL: owned menu scale/position - " Type(err) Chr(10), "*")
        ExitApp(217)
    }
    ExitApp(0)
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
