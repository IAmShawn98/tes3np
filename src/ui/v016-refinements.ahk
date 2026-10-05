; v0.1.16 test-branch UI refinements.

global V016CharacterLayoutApplied := false
global V016SettingsGuiHwnd := 0
global V016ReadabilityState := 0
global V016FollowWindowsState := 0

InitializeV016UiRefinements()
{
    SetTimer(ApplyV016CharacterLayout, 250)
    OnMessage(0x84, HandleV016SettingsHitTest)
}

HandleV016SettingsHitTest(wParam, lParam, msg, hwnd)
{
    global V016SettingsGuiHwnd
    if !V016SettingsGuiHwnd || hwnd != V016SettingsGuiHwnd || !DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd)
        return
    pt := Buffer(8, 0)
    NumPut("Int", lParam & 0xFFFF, pt, 0)
    NumPut("Int", (lParam >> 16) & 0xFFFF, pt, 4)
    DllCall("ScreenToClient", "Ptr", V016SettingsGuiHwnd, "Ptr", pt)
    localY := NumGet(pt, 4, "Int")
    if localY >= 0 && localY <= 96
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
        CharacterPage.SetFont("s9 Bold c382314", "Segoe UI")
        CharacterPage.Add("Text", "x525 y" (executableY + executableHeight + 14) " w360 h22 BackgroundTrans", "Daily Character Login")
        CharacterPage.SetFont("s8 c5A4027", "Segoe UI")
        CharacterPage.Add("Text", "x525 y" (executableY + executableHeight + 36) " w360 h34 BackgroundTrans", "Optionally run Launch All & Close automatically once per day while tes3np is running.")
        global DailyLoginScheduleEnabled, DailyLoginScheduleTime
        label := DailyLoginScheduleEnabled ? "Daily Login: On — " DailyLoginScheduleTime : "Daily Login: Off"
        AddStyledButton(CharacterPage, 525, executableY + executableHeight + 73, 360, 30, label, OpenDailyLoginScheduleDialog)
        V016CharacterLayoutApplied := true
    }
}

OpenLauncherSettingsV016(*)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, AccessibilityTextSize, EnhancedReadability, FollowWindowsAccessibility
    global V016SettingsGuiHwnd, V016ReadabilityState, V016FollowWindowsState

    settings := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border -MinimizeBox -MaximizeBox +ToolWindow", "tes3np — Launcher Settings")
    settings.MarginX := 0, settings.MarginY := 0
    settings.BackColor := "010101"
    V016SettingsGuiHwnd := settings.Hwnd
    V016ReadabilityState := EnhancedReadability ? 1 : 0
    V016FollowWindowsState := FollowWindowsAccessibility ? 1 : 0

    settings.Add("Picture", "x-20 y-30 w620 h780", A_ScriptDir "\assets\controls\scroll-panel.png")

    settings.SetFont("s16 Bold c241408", "Segoe UI")
    settings.Add("Text", "x34 y101 w526 h38 Center BackgroundTrans", "Launcher Settings")

    settings.SetFont("s11 Bold c382314", "Segoe UI")
    settings.Add("Text", "x34 y151 w155 h26 BackgroundTrans", "Launcher size")
    settings.SetFont("s12 c382314", "Segoe UI")
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x208 y145 w352 Choose" choice, choices)
    settings.SetFont("s10 Bold c5A4027", "Segoe UI")
    settings.Add("Text", "x34 y190 w526 h48 BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s11 Bold c382314", "Segoe UI")
    settings.Add("Text", "x34 y256 w155 h26 BackgroundTrans", "Interface text")
    settings.SetFont("s12 c382314", "Segoe UI")
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x208 y250 w352 Choose" textChoice, textChoices)
    settings.SetFont("s10 Bold c5A4027", "Segoe UI")
    settings.Add("Text", "x34 y295 w526 h34 BackgroundTrans", "Choose how big or small the launcher interface is for you.")

    settings.SetFont("s13 Bold c382314", "Segoe UI Symbol")
    readability := settings.Add("Text", "x34 y350 w526 h34 +0x100 BackgroundTrans", V016CheckLabel(V016ReadabilityState, "Enhanced readability"))
    readability.OnEvent("Click", ToggleV016Readability.Bind(readability))
    settings.SetFont("s10 Bold c5A4027", "Segoe UI")
    settings.Add("Text", "x76 y394 w484 h50 BackgroundTrans", "Uses stronger contrast and brighter button text while keeping the Morrowind artwork intact.")

    settings.SetFont("s13 Bold c382314", "Segoe UI Symbol")
    followWindows := settings.Add("Text", "x34 y462 w526 h34 +0x100 BackgroundTrans", V016CheckLabel(V016FollowWindowsState, "Follow Windows accessibility settings"))
    followWindows.OnEvent("Click", ToggleV016FollowWindows.Bind(followWindows))

    readabilityValue := {Value: V016ReadabilityState}
    followWindowsValue := {Value: V016FollowWindowsState}
    reduceMotionBox := {Value: 0}

    ; Pull the action group higher into the open parchment area.
    AddStyledButton(settings, 34, 475, 250, 40, "Preview & Apply", ApplyV016LauncherSettings.Bind(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, 310, 475, 250, 40, "Cancel", (*) => settings.Destroy())
    AddStyledButton(settings, 34, 525, 526, 40, "Reset Launcher Settings", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, followWindows, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, 34, 575, 526, 40, "AppData Settings", OpenAppDataSettingsV016)

    settings.OnEvent("Escape", (*) => settings.Destroy())
    settings.OnEvent("Close", (*) => settings.Destroy())
    settings.Show("w594 h720")
    WinSetTransColor("010101", "ahk_id " settings.Hwnd)
    FinishButtonDisplay()
}

V016CheckLabel(state, label)
{
    return (state ? "☑" : "☐") "  " label
}

ToggleV016Readability(control, *)
{
    global V016ReadabilityState
    V016ReadabilityState := !V016ReadabilityState
    control.Text := V016CheckLabel(V016ReadabilityState, "Enhanced readability")
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

ResetLauncherSettingsV016(settings, scaleList, textList, readability, followWindows, readabilityValue, reduceMotionBox, followWindowsValue, *)
{
    global V016ReadabilityState, V016FollowWindowsState
    if MsgBox("Reset launcher settings to their defaults?", "tes3np — Reset Launcher Settings", "YesNo Icon?") != "Yes"
        return
    scaleList.Choose(1), textList.Choose(1)
    V016ReadabilityState := 0, V016FollowWindowsState := 1
    readability.Text := V016CheckLabel(0, "Enhanced readability")
    followWindows.Text := V016CheckLabel(1, "Follow Windows accessibility settings")
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
