; v0.1.16 test-branch UI refinements.

global V016CharacterLayoutApplied := false

global V016SettingsDragHwnd := 0

InitializeV016UiRefinements()
{
    SetTimer(ApplyV016CharacterLayout, 250)
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
    global LauncherGui, LauncherScale, LauncherScaleMode, AccessibilityTextSize, EnhancedReadability, FollowWindowsAccessibility, V016SettingsDragHwnd
    ; Frameless popup: the parchment itself is the complete settings window.
    settings := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border -MinimizeBox -MaximizeBox +ToolWindow", "tes3np — Launcher Settings")
    settings.MarginX := 0, settings.MarginY := 0
    settings.BackColor := "E2CEA2"
    settings.Add("Picture", "x0 y0 w370 h472", A_ScriptDir "\assets\controls\scroll-panel.png")

    ; Invisible drag surface across the top roll so the frameless panel can still be moved.
    dragSurface := settings.Add("Text", "x18 y8 w334 h42 BackgroundTrans")
    V016SettingsDragHwnd := dragSurface.Hwnd
    dragSurface.OnEvent("Click", (*) => 0)

    settings.SetFont("s11 Bold c241408", "Segoe UI")
    settings.Add("Text", "x20 y18 w330 h26 BackgroundTrans", "Launcher Settings")
    settings.SetFont("s9 Bold c382314", "Segoe UI")
    settings.Add("Text", "x20 y58 w120 h22 BackgroundTrans", "Launcher size")
    settings.SetFont("s10 c382314", "Segoe UI")
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x145 y54 w205 Choose" choice, choices)
    settings.SetFont("s8 c5A4027", "Segoe UI")
    settings.Add("Text", "x20 y88 w330 h40 BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")
    settings.SetFont("s9 Bold c382314", "Segoe UI")
    settings.Add("Text", "x20 y140 w120 h22 BackgroundTrans", "Interface text")
    settings.SetFont("s10 c382314", "Segoe UI")
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x145 y136 w205 Choose" textChoice, textChoices)
    settings.SetFont("s8 c5A4027", "Segoe UI")
    settings.Add("Text", "x20 y170 w330 h28 BackgroundTrans", "Choose how big or small the launcher interface is for you.")
    settings.SetFont("s9 Bold c382314", "Segoe UI")
    readability := settings.Add("CheckBox", "x20 y210 w330 h24", "Enhanced readability")
    readability.Value := EnhancedReadability ? 1 : 0
    settings.SetFont("s8 c5A4027", "Segoe UI")
    settings.Add("Text", "x38 y234 w312 h38 BackgroundTrans", "Uses stronger contrast and brighter button text while keeping the Morrowind artwork intact.")
    settings.SetFont("s9 Bold c382314", "Segoe UI")
    followWindows := settings.Add("CheckBox", "x20 y280 w330 h24", "Follow Windows accessibility settings")
    followWindows.Value := FollowWindowsAccessibility ? 1 : 0
    reduceMotionBox := settings.Add("CheckBox", "x-500 y-500 w1 h1 Hidden", "")
    reduceMotionBox.Value := 0

    ; Use the same owner-drawn Morrowind buttons used throughout tes3np.
    apply := AddStyledButton(settings, 20, 330, 158, 34, "Preview & Apply", PreviewLauncherSettings.Bind(settings, scaleList, textList, readability, reduceMotionBox, followWindows, "Applying launcher settings..."))
    cancel := AddStyledButton(settings, 192, 330, 158, 34, "Cancel", (*) => settings.Destroy())
    reset := AddStyledButton(settings, 20, 374, 330, 34, "Reset Launcher Settings", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, reduceMotionBox, followWindows))
    appData := AddStyledButton(settings, 20, 418, 330, 34, "AppData Settings", OpenAppDataSettingsV016)

    settings.OnEvent("Escape", (*) => settings.Destroy())
    settings.OnEvent("Close", (*) => settings.Destroy())
    settings.Show("w370 h472")
    FinishButtonDisplay()
}

ResetLauncherSettingsV016(settings, scaleList, textList, readability, reduceMotionBox, followWindows, *)
{
    if MsgBox("Reset launcher settings to their defaults?", "tes3np — Reset Launcher Settings", "YesNo Icon?") != "Yes"
        return
    scaleList.Choose(1), textList.Choose(1), readability.Value := 0, reduceMotionBox.Value := 0, followWindows.Value := 1
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
