; v0.1.16 test-branch UI refinements.

global V016CharacterLayoutApplied := false
global V016SettingsGuiHwnd := 0
global V016SettingsScale := 1.0
global V016ReadabilityState := 0
global V016FollowWindowsState := 0

InitializeV016UiRefinements()
{
    SetTimer(ApplyV016CharacterLayout, 250)
    OnMessage(0x84, HandleV016SettingsHitTest)
}

V016S(value)
{
    global V016SettingsScale
    return Round(value * V016SettingsScale)
}

V016Font(value)
{
    global V016SettingsScale
    return Max(6, Round(value * V016SettingsScale))
}

HandleV016SettingsHitTest(wParam, lParam, msg, hwnd)
{
    global V016SettingsGuiHwnd
    if !V016SettingsGuiHwnd || hwnd != V016SettingsGuiHwnd || !DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd, "Int")
        return
    pt := Buffer(8, 0)
    NumPut("Int", lParam & 0xFFFF, pt, 0)
    NumPut("Int", (lParam >> 16) & 0xFFFF, pt, 4)
    DllCall("ScreenToClient", "Ptr", V016SettingsGuiHwnd, "Ptr", pt)
    localY := NumGet(pt, 4, "Int")
    if localY >= 0 && localY <= V016S(96)
        return 2
}

ApplyV016CharacterLayout(*)
{
    global CharacterPage, LaunchCharacterButton, ExecutableInput, V016CharacterLayoutApplied
    if V016CharacterLayoutApplied || !IsObject(CharacterPage)
        return
    try
    {
        LaunchCharacterButton.Visible := false
        ExecutableInput.GetPos(, &executableY, , &executableHeight)
        global LaunchSettingsControls
        CharacterPage.SetFont("s9 Bold c382314", "Segoe UI")
        dailyHeading := CharacterPage.Add("Text", "x70 y610 w370 h22 BackgroundTrans Hidden", "Daily Character Login")
        CharacterPage.SetFont("s8 c5A4027", "Segoe UI")
        dailyDescription := CharacterPage.Add("Text", "x70 y610 w370 h34 BackgroundTrans Hidden", "Optionally run Launch All & Close automatically once per day while tes3np is running.")
        global DailyLoginScheduleEnabled, DailyLoginScheduleTime
        label := DailyLoginScheduleEnabled ? "Daily Login: On — " DailyLoginScheduleTime : "Daily Login: Off"
        dailyButton := AddStyledButton(CharacterPage, 70, 510, 370, 25, label, OpenDailyLoginScheduleDialog)
        ; Daily-login controls are part of Launch Settings and must hide with the
        ; rest of that panel whenever the add/edit character form is open.
        LaunchSettingsControls.Push(dailyHeading, dailyDescription, dailyButton)
        ; Keep the bottom action stack on the same 32px rhythm as the existing
        ; Launch All / Wipe buttons: Add 475, Daily 507, Launch All 539, Wipe 571.
        dailyButton.Move(70, 507, 370, 25)
        ButtonFaces[dailyButton.Hwnd].Y := 507
        LaunchAllButton.Move(70, 539, 370, 25)
        ButtonFaces[LaunchAllButton.Hwnd].Y := 539
        WipeCharacterButton.Move(70, 571, 370, 25)
        ButtonFaces[WipeCharacterButton.Hwnd].Y := 571
        V016CharacterLayoutApplied := true
    }
}

OpenLauncherSettingsV016(*)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, AccessibilityTextSize, EnhancedReadability, FollowWindowsAccessibility
    global V016SettingsGuiHwnd, V016SettingsScale, V016ReadabilityState, V016FollowWindowsState

    ; Launcher Settings is a single modal-style window. If it is already open,
    ; bring that instance forward instead of creating duplicates.
    if V016SettingsGuiHwnd && DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd, "Int")
    {
        WinActivate("ahk_id " V016SettingsGuiHwnd)
        return
    }
    V016SettingsGuiHwnd := 0

    ; Use the same resolved launcher scale (automatic or manual) as the main window.
    ; AHK still handles monitor DPI; this factor handles tes3np's own 50-100% launcher scale.
    V016SettingsScale := LauncherScale / 100

    settings := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border -MinimizeBox -MaximizeBox +ToolWindow", "tes3np — Launcher Settings")
    settings.MarginX := 0, settings.MarginY := 0
    settings.BackColor := "010101"
    V016SettingsGuiHwnd := settings.Hwnd
    V016ReadabilityState := EnhancedReadability ? 1 : 0
    V016FollowWindowsState := FollowWindowsAccessibility ? 1 : 0

    settings.Add("Picture", "x" V016S(-20) " y" V016S(-30) " w" V016S(620) " h" V016S(780), A_ScriptDir "\\assets\\controls\\scroll-panel.png")

    settings.SetFont("s" V016Font(16) " Bold c241408", "Segoe UI")
    settings.Add("Text", "x" V016S(34) " y" V016S(101) " w" V016S(526) " h" V016S(38) " Center BackgroundTrans", "Launcher Settings")

    settings.SetFont("s" V016Font(11) " Bold c382314", "Segoe UI")
    settings.Add("Text", "x" V016S(34) " y" V016S(151) " w" V016S(155) " h" V016S(26) " BackgroundTrans", "Launcher size")
    settings.SetFont("s" V016Font(12) " c382314", "Segoe UI")
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x" V016S(208) " y" V016S(145) " w" V016S(352) " Choose" choice, choices)
    settings.SetFont("s" V016Font(10) " Bold c5A4027", "Segoe UI")
    settings.Add("Text", "x" V016S(34) " y" V016S(178) " w" V016S(526) " h" V016S(42) " BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s" V016Font(11) " Bold c382314", "Segoe UI")
    settings.Add("Text", "x" V016S(34) " y" V016S(226) " w" V016S(155) " h" V016S(26) " BackgroundTrans", "Interface text")
    settings.SetFont("s" V016Font(12) " c382314", "Segoe UI")
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x" V016S(208) " y" V016S(220) " w" V016S(352) " Choose" textChoice, textChoices)
    settings.SetFont("s" V016Font(10) " Bold c5A4027", "Segoe UI")
    settings.Add("Text", "x" V016S(34) " y" V016S(253) " w" V016S(526) " h" V016S(30) " BackgroundTrans", "Choose how big or small the launcher interface is for you.")

    settings.SetFont("s" V016Font(13) " Bold c382314", "Segoe UI Symbol")
    readability := settings.Add("Text", "x" V016S(34) " y" V016S(291) " w" V016S(526) " h" V016S(34) " +0x100 BackgroundTrans", V016CheckLabel(V016ReadabilityState, "Enhanced readability"))
    readability.OnEvent("Click", ToggleV016Readability.Bind(readability))
    settings.SetFont("s" V016Font(10) " Bold c5A4027", "Segoe UI")
    settings.Add("Text", "x" V016S(76) " y" V016S(322) " w" V016S(484) " h" V016S(44) " BackgroundTrans", "Improves readability by providing stronger contrast and brighter button text.")

    readabilityValue := {Value: V016ReadabilityState}
    followWindowsValue := {Value: FollowWindowsAccessibility ? 1 : 0}
    reduceMotionBox := {Value: 0}

    AddStyledButton(settings, V016S(34), V016S(370), V016S(250), V016S(40), "Preview Changes", ApplyV016LauncherSettings.Bind(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(310), V016S(370), V016S(250), V016S(40), "Close", CloseLauncherSettingsV016.Bind(settings))
    AddStyledButton(settings, V016S(34), V016S(454), V016S(526), V016S(40), "Reset Launcher Settings", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(34), V016S(510), V016S(526), V016S(40), "AppData Settings", OpenAppDataSettingsV016)

    settings.OnEvent("Escape", CloseLauncherSettingsV016.Bind(settings))
    settings.OnEvent("Close", CloseLauncherSettingsV016.Bind(settings))
    settings.OnEvent("Size", (*) => 0)
    settings.Show("w" V016S(594) " h" V016S(720))
    DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 0)
    WinSetTransColor("010101", "ahk_id " settings.Hwnd)
    FinishButtonDisplay()
}

CloseLauncherSettingsV016(settings, *)
{
    global LauncherGui, V016SettingsGuiHwnd
    hwnd := 0
    try hwnd := settings.Hwnd
    if hwnd && V016SettingsGuiHwnd = hwnd
        V016SettingsGuiHwnd := 0
    try settings.Destroy()
    if IsObject(LauncherGui) && DllCall("IsWindow", "Ptr", LauncherGui.Hwnd, "Int")
    {
        DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 1)
        WinActivate("ahk_id " LauncherGui.Hwnd)
    }
}

V016CheckLabel(state, label)
{
    return (state ? "☑" : "☐") "  " label
}

ToggleV016Readability(control, *)
{
    global V016ReadabilityState
    V016ReadabilityState := !V016ReadabilityState
    ; Updating this custom-painted label synchronously from its click callback can
    ; re-enter the renderer. Defer the visual refresh until the click message unwinds.
    SetTimer(UpdateV016ReadabilityLabel.Bind(control, V016ReadabilityState), -1)
}

UpdateV016ReadabilityLabel(control, state)
{
    if !IsObject(control) || !DllCall("IsWindow", "Ptr", control.Hwnd, "Int")
        return
    try control.Text := V016CheckLabel(state, "Enhanced readability")
}

ToggleV016FollowWindows(control, *)
{
    global V016FollowWindowsState
    V016FollowWindowsState := !V016FollowWindowsState
    control.Text := V016CheckLabel(V016FollowWindowsState, "Follow Windows accessibility settings")
}

ApplyV016LauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue, *)
{
    global V016ReadabilityState, V016FollowWindowsState
    readabilityValue.Value := V016ReadabilityState
    followWindowsValue.Value := V016FollowWindowsState
    PreviewLauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue, "Applying launcher settings...")
}

ResetLauncherSettingsV016(settings, scaleList, textList, readability, readabilityValue, reduceMotionBox, followWindowsValue, *)
{
    global V016ReadabilityState, V016FollowWindowsState
    if MsgBox("Reset launcher settings to their defaults?", "tes3np — Reset Launcher Settings", "YesNo Icon?") != "Yes"
        return
    scaleList.Choose(1), textList.Choose(1)
    V016ReadabilityState := 0, V016FollowWindowsState := 1
    readability.Text := V016CheckLabel(0, "Enhanced readability")
    readabilityValue.Value := 0, reduceMotionBox.Value := 0, followWindowsValue.Value := 1
    PreviewLauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue, "Resetting launcher settings...")
}

OpenAppDataSettingsV016(*)
{
    global LauncherGui
    window := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — AppData Settings")
    window.BackColor := "E2CEA2"
    window.SetFont("s11 Bold c241408", "Segoe UI")
    window.Add("Text", "x20 y18 w380 h26", "AppData Settings")
    window.SetFont("s9 c382314", "Segoe UI")
    window.Add("Text", "x20 y48 w380 h60", "Manage tes3np's saved launcher data and logs. You can open their folder, copy their data, or delete them when appropriate.")
    logs := window.Add("Button", "x20 y122 w380 h34", "Launcher Logs")
    diagnostics := window.Add("Button", "x20 y166 w380 h34", "Diagnostic Information")
    reset := window.Add("Button", "x20 y210 w380 h34", "Reset AppData")
    close := window.Add("Button", "x20 y260 w380 h34 Default", "Close")
    logs.OnEvent("Click", ShowLauncherLogActions)
    diagnostics.OnEvent("Click", ShowDiagnosticActions)
    reset.OnEvent("Click", ShowResetAppDataActions)
    close.OnEvent("Click", (*) => window.Destroy())
    window.OnEvent("Escape", (*) => window.Destroy())
    window.Show("w420 h314")
}

ShowLauncherLogActions(*)
{
    choice := MsgBox("Yes: Open the launcher log`nNo: Copy the launcher log to the clipboard`nCancel: More options", "tes3np — Launcher Logs", "YesNoCancel Icon?")
    if choice = "Yes"
        return OpenLauncherLog()
    if choice = "No"
    {
        global LauncherLogFile
        SyncPatchLogToLauncherLog()
        A_Clipboard := FileExist(LauncherLogFile) ? FileRead(LauncherLogFile, "UTF-8") : ""
        MsgBox("Launcher log copied to the clipboard.", "tes3np")
        return
    }
    if MsgBox("Delete the launcher log?", "tes3np — Launcher Logs", "YesNo Icon!") = "Yes"
        ClearLauncherLog()
}

ShowDiagnosticActions(*)
{
    choice := MsgBox("Yes: Open the AppData folder`nNo: Copy diagnostic information`nCancel: Return", "tes3np — Diagnostic Information", "YesNoCancel Icon?")
    if choice = "Yes"
        OpenLauncherDataFolder()
    else if choice = "No"
        CopyLauncherDiagnostics()
}

ShowResetAppDataActions(*)
{
    global AppDataDirectory
    choice := MsgBox("Yes: Open the AppData folder`nNo: Reset AppData`nCancel: Return", "tes3np — Reset AppData", "YesNoCancel Icon?")
    if choice = "Yes"
        return OpenLauncherDataFolder()
    if choice != "No"
        return
    warning := "This will delete all information inside tes3np AppData, including your saved characters and launcher settings.`n`nYou should export your character data before doing this.`n`nAre you sure you want to continue?"
    if MsgBox(warning, "tes3np — Reset AppData", "YesNo Icon!") != "Yes"
        return
    if MsgBox("This cannot be undone. Permanently reset tes3np AppData now?", "tes3np — Final Confirmation", "YesNo Icon!") != "Yes"
        return
    try DirDelete(AppDataDirectory, true)
    DirCreate(AppDataDirectory)
    MsgBox("AppData has been reset. Restart tes3np before continuing.", "tes3np — AppData Settings")
}
