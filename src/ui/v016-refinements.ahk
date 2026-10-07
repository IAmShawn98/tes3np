; v0.1.16 test-branch UI refinements.

global V016CharacterLayoutApplied := false
global V016SettingsGuiHwnd := 0
global V016SettingsScale := 1.0
global V016ReadabilityState := 0
global V016FollowWindowsState := 0
global V016DailyLoginControls := []

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
        global ScheduledEvents
        label := ScheduledEvents.Length ? "Scheduled Events (" ScheduledEvents.Length ")" : "Schedule Event"
        dailyButton := AddStyledButton(CharacterPage, 70, 510, 370, 25, label, OpenScheduledEventsMenu)
        ; Scheduled Events belongs to the character action stack, not Launch Settings.
        ; Keep it independent so opening the add/edit form does not hide it.
        global V016DailyLoginControls
        V016DailyLoginControls := [dailyButton]
        hasCharacters := Profiles.Length > 0
        for control in V016DailyLoginControls
            control.Visible := hasCharacters
        ; Keep the character actions contiguous: Add Character, Scheduled Events, then Wipe Character List.
        addY := Profiles.Length ? 505 : 185
        AddCharacterButton.Move(70, addY, 370, 30)
        ButtonFaces[AddCharacterButton.Hwnd].Y := addY
        dailyButton.Move(70, 540, 370, 30)
        ButtonFaces[dailyButton.Hwnd].Y := 540
        WipeCharacterButton.Move(70, 575, 370, 30)
        ButtonFaces[WipeCharacterButton.Hwnd].Y := 575
        V016CharacterLayoutApplied := true
    }
}

global LauncherMorrowindFont := "Georgia"
global LauncherMorrowindFontPath := ""
global LauncherMorrowindFontLoaded := false

InitializeLauncherMorrowindFont()
{
    global LauncherMorrowindFont, LauncherMorrowindFontPath, LauncherMorrowindFontLoaded
    fontDir := A_ScriptDir "\\assets\\fonts"
    fontPath := fontDir "\\MysticCards.ttf"
    LauncherMorrowindFontPath := fontPath
    LauncherMorrowindFont := "Georgia"
    LauncherMorrowindFontLoaded := false

    if !FileExist(fontPath)
    {
        try
        {
            DirCreate(fontDir)
            Download("https://raw.githubusercontent.com/OpenMW/openmw/master/files/data/fonts/MysticCards.ttf", fontPath)
        }
        catch as err
            LogLauncherEvent("FONT | MysticCards download failed: " err.Message)
    }

    if !FileExist(fontPath)
    {
        LogLauncherEvent("FONT | MysticCards unavailable. Using Georgia fallback.")
        return
    }

    try
    {
        loaded := DllCall("Gdi32.dll\\AddFontResourceExW", "Str", fontPath, "UInt", 0x10, "Ptr", 0, "Int")
        if loaded > 0
        {
            ; MysticCards.ttf identifies its Windows family as Pelagiad. The file
            ; name is MysticCards, but SetFont must use the internal family name.
            LauncherMorrowindFont := "Mystic Cards"
            LauncherMorrowindFontLoaded := true
            LogLauncherEvent("FONT | MysticCards registered. Requesting internal family Mystic Cards from " fontPath ".")
            return
        }
        LogLauncherEvent("FONT | MysticCards registration returned 0. Using Georgia fallback.")
    }
    catch as err
        LogLauncherEvent("FONT | MysticCards registration failed: " err.Message ". Using Georgia fallback.")
}

ReleaseLauncherMorrowindFont()
{
    global LauncherMorrowindFontPath, LauncherMorrowindFontLoaded
    if LauncherMorrowindFontLoaded && LauncherMorrowindFontPath != ""
        try DllCall("Gdi32.dll\\RemoveFontResourceExW", "Str", LauncherMorrowindFontPath, "UInt", 0x10, "Ptr", 0)
    LauncherMorrowindFontLoaded := false
}

OpenLauncherSettingsV016(*)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, AccessibilityTextSize, EnhancedReadability, FollowWindowsAccessibility, LauncherMorrowindFont
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

    settings.Add("Picture", "x" V016S(-12) " y" V016S(-20) " w" V016S(544) " h" V016S(650), A_ScriptDir "\\assets\\controls\\scroll-panel.png")

    settings.SetFont("s" V016Font(16) " Bold c241408", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(76) " w" V016S(448) " h" V016S(34) " Center BackgroundTrans", "Launcher Settings")

    settings.SetFont("s" V016Font(11) " Bold c382314", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(124) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Launcher size")
    settings.SetFont("s" V016Font(12) " c382314", LauncherMorrowindFont)
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x" V016S(184) " y" V016S(119) " w" V016S(296) " Choose" choice, choices)
    settings.SetFont("s" V016Font(10) " Bold c5A4027", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(151) " w" V016S(448) " h" V016S(40) " BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s" V016Font(11) " Bold c382314", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(197) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Interface text")
    settings.SetFont("s" V016Font(12) " c382314", LauncherMorrowindFont)
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x" V016S(184) " y" V016S(192) " w" V016S(296) " Choose" textChoice, textChoices)
    settings.SetFont("s" V016Font(10) " Bold c5A4027", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(224) " w" V016S(448) " h" V016S(30) " BackgroundTrans", "Choose how big or small the launcher interface is for you.")

    settings.SetFont("s" V016Font(13) " Bold c382314", LauncherMorrowindFont)
    readability := settings.Add("Text", "x" V016S(32) " y" V016S(260) " w" V016S(448) " h" V016S(32) " +0x100 BackgroundTrans", V016CheckLabel(V016ReadabilityState, "Enhanced readability"))
    readability.OnEvent("Click", ToggleV016Readability.Bind(readability))
    settings.SetFont("s" V016Font(10) " Bold c5A4027", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(70) " y" V016S(290) " w" V016S(410) " h" V016S(42) " BackgroundTrans", "Improves readability by providing stronger contrast and brighter button text.")

    readabilityValue := {Value: V016ReadabilityState}
    followWindowsValue := {Value: FollowWindowsAccessibility ? 1 : 0}
    reduceMotionBox := {Value: 0}

    AddStyledButton(settings, V016S(32), V016S(338), V016S(214), V016S(38), "Preview Changes", ApplyV016LauncherSettings.Bind(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(266), V016S(338), V016S(214), V016S(38), "Close", CloseLauncherSettingsV016.Bind(settings))
    AddStyledButton(settings, V016S(32), V016S(400), V016S(448), V016S(38), "Reset Launcher Settings", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(32), V016S(450), V016S(448), V016S(38), "AppData Settings", OpenAppDataSettingsV016)

    settings.OnEvent("Escape", CloseLauncherSettingsV016.Bind(settings))
    settings.OnEvent("Close", CloseLauncherSettingsV016.Bind(settings))
    settings.OnEvent("Size", (*) => 0)
    settings.Show("w" V016S(512) " h" V016S(590))
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
    window := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — AppData")
    window.BackColor := "E2CEA2"
    window.SetFont("s11 Bold c241408", "Segoe UI")
    window.Add("Text", "x20 y18 w520 h26", "AppData")
    window.SetFont("s9 c382314", "Segoe UI")
    window.Add("Text", "x20 y48 w520 h92", "AppData stores the launcher's settings and all of your local characters you added to the launcher. Make sure before tampering with these files you export your character data under the 'Manage Characters' page. This way if something goes wrong you can fully restore all your set characters and preferences.")
    openFolder := window.Add("Button", "x20 y150 w520 h34", "Open AppData Folder")
    copyLauncher := window.Add("Button", "x20 y194 w255 h34", "Copy Launcher Log")
    copyRender := window.Add("Button", "x285 y194 w255 h34", "Copy Render Errors Log")
    copyPatch := window.Add("Button", "x20 y238 w255 h34", "Copy Patch Log")
    copyPatchErrors := window.Add("Button", "x285 y238 w255 h34", "Copy Patch Errors Log")
    reset := window.Add("Button", "x20 y292 w520 h34", "Reset AppData")
    close := window.Add("Button", "x20 y336 w520 h34 Default", "Close")
    openFolder.OnEvent("Click", OpenLauncherDataFolder)
    copyLauncher.OnEvent("Click", CopyAppDataLog.Bind("launcher.log", true))
    copyRender.OnEvent("Click", CopyAppDataLog.Bind("render-errors.log"))
    copyPatch.OnEvent("Click", CopyAppDataLog.Bind("patch-all.log"))
    copyPatchErrors.OnEvent("Click", CopyAppDataLog.Bind("patch-errors.log"))
    reset.OnEvent("Click", ShowResetAppDataActions)
    close.OnEvent("Click", (*) => window.Destroy())
    window.OnEvent("Escape", (*) => window.Destroy())
    window.Show("w560 h390")
}

CopyAppDataLog(filename, syncLauncher := false, *)
{
    global AppDataDirectory
    if syncLauncher
        SyncPatchLogToLauncherLog()
    path := AppDataDirectory "\" filename
    if !FileExist(path)
    {
        MsgBox(filename " does not exist yet.", "tes3np — AppData")
        return
    }
    try A_Clipboard := FileRead(path, "UTF-8")
    catch as err
    {
        MsgBox("Could not read " filename ".\n\n" err.Message, "tes3np — AppData")
        return
    }
    MsgBox(filename " copied to the clipboard.", "tes3np — AppData")
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
