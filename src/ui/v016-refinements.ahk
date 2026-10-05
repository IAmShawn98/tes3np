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
    settings.BackColor := "D9B875"
    V016SettingsGuiHwnd := settings.Hwnd
    settings.Add("Picture", "x0 y0 w370 h472", A_ScriptDir "\assets\controls\scroll-panel.png")

    settings.SetFont("s12 Bold c241408", "Segoe UI")
    settings.Add("Text", "x20 y76 w330 h28 Center BackgroundTrans", "Launcher Settings")

    settings.SetFont("s8 Bold c382314", "Segoe UI")
    settings.Add("Text", "x20 y108 w100 h20 BackgroundTrans", "Launcher size")
    settings.SetFont("s9 c382314", "Segoe UI")
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x132 y104 w218 Choose" choice, choices)
    settings.SetFont("s7 c5A4027", "Segoe UI")
    settings.Add("Text", "x20 y134 w330 h30 BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s8 Bold c382314", "Segoe UI")
    settings.Add("Text", "x20 y170 w100 h20 BackgroundTrans", "Interface text")
    settings.SetFont("s9 c382314", "Segoe UI")
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x132 y166 w218 Choose" textChoice, textChoices)
    settings.SetFont("s7 c5A4027", "Segoe UI")
    settings.Add("Text", "x20 y196 w330 h22 BackgroundTrans", "Choose how big or small the launcher interface is for you.")

    settings.SetFont("s8 Bold c382314", "Segoe UI")
    readability := settings.Add("CheckBox", "x20 y224 w330 h22", "Enhanced readability")
    readability.Value := EnhancedReadability ? 1 : 0
    settings.SetFont("s7 c5A4027", "Segoe UI")
    settings.Add("Text", "x38 y248 w312 h28 BackgroundTrans", "Uses stronger contrast and brighter button text while keeping the Morrowind artwork intact.")
    settings.SetFont("s8 Bold c382314", "Segoe UI")
    followWindows := settings.Add("CheckBox", "x20 y282 w330 h22", "Follow Windows accessibility settings")
    followWindows.Value := FollowWindowsAccessibility ? 1 : 0
    reduceMotionBox := settings.Add("CheckBox", "x-500 y-500 w1 h1 Hidden", "")
    reduceMotionBox.Value := 0

    AddStyledButton(settings, 20, 314, 158, 28, "Preview & Apply", PreviewLauncherSettings.Bind(settings, scaleList, textList, readability, reduceMotionBox, followWindows, "Applying launcher settings..."))
    AddStyledButton(settings, 192, 314, 158, 28, "Cancel", (*) => settings.Destroy())
    AddStyledButton(settings, 20, 350, 330, 28, "Reset Launcher Settings", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, reduceMotionBox, followWindows))
    AddStyledButton(settings, 20, 386, 330, 28, "AppData Settings", OpenAppDataSettingsV016)

    settings.OnEvent("Escape", (*) => settings.Destroy())
    settings.OnEvent("Close", (*) => settings.Destroy())
    settings.Show("w370 h472")

    ; Do not color-key the parchment. The old TransColor method also keyed pixels
    ; inside the artwork and native checkbox backgrounds, which caused blue holes
    ; and gold speckles. Instead, trim only the outer GUI canvas with a DPI-aware
    ; native window region. The region is calculated from the real client size so
    ; it remains correct at Windows display scaling above 100%.
    ApplyV016ScrollRegion(settings.Hwnd)
    FinishButtonDisplay()
}

ApplyV016ScrollRegion(hwnd)
{
    rect := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", rect)
    w := NumGet(rect, 8, "Int")
    h := NumGet(rect, 12, "Int")
    if w <= 0 || h <= 0
        return

    ; The visible scroll occupies roughly x=8..362 and y=18..462 in the
    ; 370x472 source. Scale those measurements to the actual client pixels.
    sx := w / 370.0
    sy := h / 472.0
    x1 := Round(7 * sx), x2 := Round(363 * sx)
    y1 := Round(17 * sy), y2 := Round(463 * sy)

    ; A gently shaped polygon follows the scroll's outer silhouette while keeping
    ; every rolled end intact. It removes only the redundant backing canvas.
    pts := x1 "," Round(30*sy) " " Round(13*sx) "," y1 " " Round(357*sx) "," y1 " " x2 "," Round(30*sy)
        . " " x2 "," Round(430*sy) " " Round(359*sx) "," y2 " " Round(11*sx) "," y2 " " x1 "," Round(430*sy)
    WinSetRegion(pts, "ahk_id " hwnd)
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
