; v0.1.16 test-branch UI refinements.

global V016CharacterLayoutApplied := false
global V016SettingsGuiHwnd := 0

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
    if localY >= 0 && localY <= 62
        return 2 ; HTCAPTION
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
    global V016SettingsGuiHwnd

    settings := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border -MinimizeBox -MaximizeBox +ToolWindow", "tes3np — Launcher Settings")
    settings.MarginX := 0, settings.MarginY := 0
    settings.BackColor := "010101"
    V016SettingsGuiHwnd := settings.Hwnd

    settings.Add("Picture", "x-12 y-18 w372 h474", A_ScriptDir "\assets\controls\scroll-panel.png")

    settings.SetFont("s12 Bold c241408", "Segoe UI")
    settings.Add("Text", "x9 y59 w330 h28 Center BackgroundTrans", "Launcher Settings")

    settings.SetFont("s8 Bold c382314", "Segoe UI")
    settings.Add("Text", "x9 y91 w100 h20 BackgroundTrans", "Launcher size")
    settings.SetFont("s9 c382314", "Segoe UI")
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x121 y87 w218 Choose" choice, choices)
    settings.SetFont("s7 c5A4027", "Segoe UI")
    settings.Add("Text", "x9 y117 w330 h30 BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s8 Bold c382314", "Segoe UI")
    settings.Add("Text", "x9 y153 w100 h20 BackgroundTrans", "Interface text")
    settings.SetFont("s9 c382314", "Segoe UI")
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x121 y149 w218 Choose" textChoice, textChoices)
    settings.SetFont("s7 c5A4027", "Segoe UI")
    settings.Add("Text", "x9 y179 w330 h22 BackgroundTrans", "Choose how big or small the launcher interface is for you.")

    ; Do not use native CheckBox controls on this chroma-keyed window: Windows paints
    ; their client background independently and it punches rectangular holes through
    ; the parchment. These compact text toggles keep the parchment itself untouched.
    settings.SetFont("s8 Bold c382314", "Segoe UI")
    readability := settings.Add("Text", "x9 y207 w330 h22 +0x100 BackgroundTrans", (EnhancedReadability ? "☑" : "☐") "  Enhanced readability")
    readability.Value := EnhancedReadability ? 1 : 0
    readability.OnEvent("Click", ToggleV016TextCheck.Bind(readability, "Enhanced readability"))
    settings.SetFont("s7 c5A4027", "Segoe UI")
    settings.Add("Text", "x27 y231 w312 h28 BackgroundTrans", "Uses stronger contrast and brighter button text while keeping the Morrowind artwork intact.")

    settings.SetFont("s8 Bold c382314", "Segoe UI")
    followWindows := settings.Add("Text", "x9 y265 w330 h22 +0x100 BackgroundTrans", (FollowWindowsAccessibility ? "☑" : "☐") "  Follow Windows accessibility settings")
    followWindows.Value := FollowWindowsAccessibility ? 1 : 0
    followWindows.OnEvent("Click", ToggleV016TextCheck.Bind(followWindows, "Follow Windows accessibility settings"))
    reduceMotionBox := {Value: 0}

    AddStyledButton(settings, 9, 297, 158, 28, "Preview & Apply", PreviewLauncherSettings.Bind(settings, scaleList, textList, readability, reduceMotionBox, followWindows, "Applying launcher settings..."))
    AddStyledButton(settings, 181, 297, 158, 28, "Cancel", (*) => settings.Destroy())
    AddStyledButton(settings, 9, 333, 330, 28, "Reset Launcher Settings", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, reduceMotionBox, followWindows))
    AddStyledButton(settings, 9, 369, 330, 28, "AppData Settings", OpenAppDataSettingsV016)

    settings.OnEvent("Escape", (*) => settings.Destroy())
    settings.OnEvent("Close", (*) => settings.Destroy())
    settings.Show("w348 h446")
    WinSetTransColor("010101", "ahk_id " settings.Hwnd)
    FinishButtonDisplay()
}

ToggleV016TextCheck(control, label, *)
{
    control.Value := control.Value ? 0 : 1
    control.Text := (control.Value ? "☑" : "☐") "  " label
}

ResetLauncherSettingsV016(settings, scaleList, textList, readability, reduceMotionBox, followWindows, *)
{
    if MsgBox("Reset launcher settings to their defaults?", "tes3np — Reset Launcher Settings", "YesNo Icon?") != "Yes"
        return
    scaleList.Choose(1), textList.Choose(1), readability.Value := 0, reduceMotionBox.Value := 0, followWindows.Value := 1
    readability.Text := "☐  Enhanced readability"
    followWindows.Text := "☑  Follow Windows accessibility settings"
    PreviewLauncherSettings(settings, scaleList, textList, readability, reduceMotionBox, followWindows, "Resetting launcher settings...")
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
