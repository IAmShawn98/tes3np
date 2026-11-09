; Live character-book and launcher-settings presentation.

global V016CharacterLayoutApplied := false
global V016SettingsGuiHwnd := 0
global V016SettingsScale := 1.0
global V016ReadabilityState := 0
global V016FollowWindowsState := 0

; Shared book/settings visibility helper. Both the native control and
; themed painted face must be hidden/shown together to prevent ghost buttons.
SetBookControlVisible(control, visible)
{
    global ButtonFaces
    try control.Visible := visible
    try if ButtonFaces.Has(control.Hwnd)
    {
        face := ButtonFaces[control.Hwnd]
        if face.HasOwnProp("Control") && IsObject(face.Control)
            face.Control.Visible := visible
        if face.HasOwnProp("Label") && IsObject(face.Label)
            face.Label.Visible := visible
    }
    ; Avoid forcing one parent repaint per control; the page update handles it.
}

InitializeV016UiRefinements()
{
    ; Character layout is applied explicitly when the Character Book is built or
    ; refreshed. Do not wake the launcher four times per second just to discover
    ; that the layout has already been applied.
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
    return Max(9, Round(value * V016SettingsScale))
}

GetV016SettingsFitScale()
{
    global LauncherGui
    ; Settings is a separate readable document: a 50% launcher should not
    ; force its dropdowns/labels to 50%. Only shrink when the actual monitor
    ; work area cannot fit the approved 512x590 parchment at Windows DPI.
    WinGetPos(&x, &y, &w, &h, "ahk_id " LauncherGui.Hwnd)
    monitor := MonitorFromPoint(x + w // 2, y + h // 2)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    dpi := A_ScreenDPI / 96
    fit := Min(1.0, (right - left - 24) / (512 * dpi),
        (bottom - top - 24) / (590 * dpi))
    return Max(0.45, fit)
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
    global CharacterPage, V016CharacterLayoutApplied
    global Profiles, AddCharacterButton, WipeCharacterButton
    if V016CharacterLayoutApplied || !IsObject(CharacterPage)
        return


    ; Keep Add Character immediately above Wipe Character List. Keep the Wipe
    ; button directly beneath it, using the same styled-button mover as
    ; RefreshProfiles so the painted and native button layers stay together.
    MoveStyledButton(AddCharacterButton, 70, Profiles.Length ? 540 : 180, 370, 30)
    MoveStyledButton(WipeCharacterButton, 70, 575, 370, 30)
    V016CharacterLayoutApplied := true
}

global LauncherMorrowindFont := "Georgia"
global LauncherMorrowindFontPath := ""
global LauncherMorrowindFontLoaded := false

InitializeLauncherMorrowindFont()
{
    global LauncherMorrowindFont, LauncherMorrowindFontPath, LauncherMorrowindFontLoaded

    ; Windows controls use the bundled Mystic Cards TrueType face where
    ; available, falling back to Georgia without probing proprietary bitmap assets.
    LauncherMorrowindFont := "Georgia"
    LauncherMorrowindFontPath := ""
    LauncherMorrowindFontLoaded := false

    ; Standard Windows controls cannot use Morrowind's .fnt/.tex bitmap face.
    ; Load the bundled OpenMW-compatible TrueType face for native controls so
    ; the settings page uses one font instead of mixing bitmap, Georgia and Segoe UI.
    nativeFontPath := A_ScriptDir "\\assets\\fonts\\MysticCards.ttf"
    LauncherMorrowindFontPath := nativeFontPath
    if FileExist(nativeFontPath)
    {
        try
        {
            if DllCall("Gdi32.dll\AddFontResourceExW", "Str", nativeFontPath, "UInt", 0x10, "Ptr", 0, "Int") > 0
            {
                LauncherMorrowindFont := "Mystic Cards"
                LauncherMorrowindFontLoaded := true
            }
        }
    }
}

ReleaseLauncherMorrowindFont()
{
    global LauncherMorrowindFontLoaded, LauncherMorrowindFontPath
    if LauncherMorrowindFontLoaded && LauncherMorrowindFontPath != ""
        try DllCall("Gdi32.dll\RemoveFontResourceExW", "Str", LauncherMorrowindFontPath, "UInt", 0x10, "Ptr", 0)
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

    ; Keep Settings readable regardless of the launcher percentage.
    ; Compute a separate work-area fit rather than shrinking the parchment
    ; and native dropdowns to 50% on small launcher presets.
    V016SettingsScale := GetV016SettingsFitScale()

    settings := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border -MinimizeBox -MaximizeBox +ToolWindow", "tes3np — Launcher Settings")
    settings.MarginX := 0, settings.MarginY := 0
    settings.BackColor := "010101"
    V016SettingsGuiHwnd := settings.Hwnd
    V016ReadabilityState := EnhancedReadability ? 1 : 0
    V016FollowWindowsState := FollowWindowsAccessibility ? 1 : 0

    settings.Add("Picture", "x" V016S(-12) " y" V016S(-20) " w" V016S(544) " h" V016S(650), A_ScriptDir "\\assets\\controls\\scroll-panel.png")

    settings.SetFont("s" V016Font(19) " Norm c241408", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(70) " y" V016S(121) " w" V016S(370) " h" V016S(34) " Center BackgroundTrans", "Launcher Settings")

    settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(169) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Launcher size")
    ; Native dropdowns cannot display the proprietary bitmap face directly.
    ; Keep their interactive chrome native, but use a neutral system font so
    ; they no longer inherit the old Georgia/MysticCards approximation.
    settings.SetFont("s" V016Font(12) " Norm c241408", LauncherMorrowindFont)
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x" V016S(184) " y" V016S(164) " w" V016S(296) " Choose" choice, choices)
    settings.SetFont("s" V016Font(11) " Norm c382314", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(196) " w" V016S(448) " h" V016S(40) " BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(242) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Interface text")
    settings.SetFont("s" V016Font(12) " Norm c241408", LauncherMorrowindFont)
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x" V016S(184) " y" V016S(237) " w" V016S(296) " Choose" textChoice, textChoices)
    settings.SetFont("s" V016Font(11) " Norm c382314", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(269) " w" V016S(448) " h" V016S(30) " BackgroundTrans", "Choose how big or small the launcher interface is for you.")

    settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
    readabilityPrefix := V016ReadabilityState ? "☑" : "■"
    readability := settings.Add("Text", "x" V016S(32) " y" V016S(305) " w" V016S(448) " h" V016S(32) " +0x100 BackgroundTrans", readabilityPrefix "  Enhanced readability")
    readability.OnEvent("Click", ToggleV016ReadabilityControl.Bind(readability))
    settings.ReadabilityControl := readability
    settings.SetFont("s" V016Font(11) " Norm c382314", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(70) " y" V016S(335) " w" V016S(410) " h" V016S(42) " BackgroundTrans", "Improves readability by providing stronger contrast and brighter button text.")

    readabilityValue := {Value: V016ReadabilityState}
    followWindowsValue := {Value: FollowWindowsAccessibility ? 1 : 0}
    global ReduceMotion
    reduceMotionBox := {Value: ReduceMotion ? 1 : 0}

    AddStyledButton(settings, V016S(32), V016S(387), V016S(214), V016S(30), "Preview Changes", ApplyV016LauncherSettings.Bind(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(266), V016S(387), V016S(214), V016S(30), "Reset Changes", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(32), V016S(435), V016S(214), V016S(30), "Launcher Data", OpenAppDataSettingsV016.Bind(settings))
    AddStyledButton(settings, V016S(266), V016S(435), V016S(214), V016S(30), "Game Client Settings", OpenClientSelectionSettings)
    ; Restore the original full-width Close Settings button exactly as it
    ; appeared before the desktop-shortcut button divided this row.
    AddStyledButton(settings, V016S(32), V016S(483), V016S(448), V016S(30),
        "Close Settings", CloseLauncherSettingsV016.Bind(settings))

    ; Keep both parchment views in the same GUI. The common backdrop is never
    ; destroyed, and all data controls are created only once per settings window.
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    V016SettingsMainControls := []
    for control in settings
        V016SettingsMainControls.Push(control)
    V016SettingsDataControls := []
    V016SettingsDataActive := false

    settings.OnEvent("Escape", CloseLauncherSettingsV016.Bind(settings))
    settings.OnEvent("Close", CloseLauncherSettingsV016.Bind(settings))
    settings.OnEvent("Size", (*) => 0)
    ; The transparency key must be applied to the hidden Settings GUI, but
    ; that alone does not prevent DWM from presenting its unpainted native
    ; controls on the first visible frame. Cloak before Show and uncloak only
    ; after the completed parchment and themed controls have been painted.
    staged := SetPageCompositorCloak(settings, true)
    try
    {
        settings.Show("Hide w" V016S(512) " h" V016S(590))
        ; AHK's WinSetTransColor looks up visible/eligible windows even for
        ; ahk_id; it cannot find our intentionally DWM-cloaked Settings HWND.
        ; Apply the unchanged 010101 key directly to the live native handle.
        if !SetPageColorKey(settings, 0x010101)
            throw Error("Could not prepare Launcher Settings transparency.")
        settings.Show()
        DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 0)
        ; The synchronous page reveal below already paints every child once.
        ; Scanning/painting all themed buttons *before* that pass doubled the
        ; work and caused multi-second click delays on complex pages.
        if staged
            RevealPaintedPage(settings)
        else
            FinishButtonDisplay()
    }
    finally
    {
        if staged
            SetPageCompositorCloak(settings, false)
    }
}

CloseLauncherSettingsV016(settings, *)
{
    global LauncherGui, V016SettingsGuiHwnd
    hwnd := 0
    try hwnd := settings.Hwnd
    if hwnd && V016SettingsGuiHwnd = hwnd
        V016SettingsGuiHwnd := 0
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    V016SettingsDataActive := false
    V016SettingsMainControls := []
    V016SettingsDataControls := []
    ; Hand foreground ownership back to the launcher BEFORE destroying the
    ; owned Settings window. Otherwise Windows can activate whichever third-
    ; party window was behind TES3NP (OBS in the recorded reproduction).
    launcherValid := IsObject(LauncherGui) && DllCall("IsWindow", "Ptr", LauncherGui.Hwnd, "Int")
    if launcherValid
    {
        DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 1)
        try LauncherGui.Show("NA")
        try WinActivate("ahk_id " LauncherGui.Hwnd)
    }
    try settings.Destroy()
}

V016CheckLabel(state, label)
{
    return (state ? "☑" : "■") "  " label
}

ToggleV016ReadabilityControl(control, *)
{
    global V016ReadabilityState
    V016ReadabilityState := !V016ReadabilityState
    UpdateV016ReadabilityLabel(control, V016ReadabilityState)
}

UpdateV016ReadabilityLabel(control, state)
{
    if !IsObject(control) || !DllCall("IsWindow", "Ptr", control.Hwnd, "Int")
        return
    try control.Text := V016CheckLabel(state, "Enhanced readability")
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
    ; Reset is still a reversible preview: the No path restores both saved
    ; values and every displayed selector/checkbox from the prior state.
    scaleList.Choose(1), textList.Choose(1)
    V016ReadabilityState := 0, V016FollowWindowsState := 1
    readability.Text := V016CheckLabel(0, "Enhanced readability")
    readabilityValue.Value := 0, reduceMotionBox.Value := 0, followWindowsValue.Value := 1
    PreviewLauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue, "Resetting launcher settings...")
}

OpenAppDataSettingsV016(settings, *)
{
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    global LauncherMorrowindFont
    if !IsObject(settings) || !DllCall("IsWindow", "Ptr", settings.Hwnd)
        return
    if V016SettingsDataActive
        return
    ; Snapshot the current parchment and suspend redraw while controls change.
    ; Quick cached transitions keep the old frame, without a loading card.
    BeginInterfaceUpdate(settings, "Opening Launcher Data...", false)
    try
    {
    ; Create the second view once. A return visit simply toggles visibility.
    if V016SettingsDataControls.Length = 0
    {
        before := Map()
        for control in settings
            before[control.Hwnd] := true
        settings.SetFont("s" V016Font(17) " Norm c241408", LauncherMorrowindFont)
        settings.Add("Text", "x" V016S(32) " y" V016S(126) " w" V016S(448) " h" V016S(32) " Center BackgroundTrans", "Launcher Data & Diagnostics")
        ; The original 10pt Morrowind font was difficult to read at default
        ; scale. Use larger lettering and concise copy within the same panel.
        settings.SetFont("s" V016Font(12) " Norm c382314", LauncherMorrowindFont)
        settings.Add("Text", "x" V016S(42) " y" V016S(166) " w" V016S(428) " h" V016S(96) " BackgroundTrans",
            "Characters and preferences are saved in AppData. Export characters before resetting. If the game crashes, copy Launcher Logs to share the error.")
        AddStyledButton(settings, V016S(32), V016S(268), V016S(448), V016S(30), "Open Launcher AppData Folder", OpenLauncherDataFolder)
        AddStyledButton(settings, V016S(32), V016S(309), V016S(448), V016S(30), "Copy Launcher Logs", CopyAppDataLog.Bind("launcher.log", true))
        settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
        settings.Add("Text", "x" V016S(32) " y" V016S(351) " w" V016S(448) " h" V016S(24) " BackgroundTrans", "Advanced Diagnostic Logs")
        AddStyledButton(settings, V016S(32), V016S(385), V016S(448), V016S(30), "Reset Launcher AppData", ShowResetAppDataActions)
        AddStyledButton(settings, V016S(32), V016S(426), V016S(214), V016S(30), "Copy Expansion Pack Logs", CopyExpansionPackLogs)
        AddStyledButton(settings, V016S(266), V016S(426), V016S(214), V016S(30), "Copy Render Errors", CopyAppDataLog.Bind("render-errors.log"))
        AddStyledButton(settings, V016S(32), V016S(483), V016S(448), V016S(30), "Go Back", CloseLauncherDataV016.Bind(settings))
        for control in settings
            if !before.Has(control.Hwnd)
                V016SettingsDataControls.Push(control)
    }
    ; Hide only the main view; keep the shared parchment picture visible.
    V016SettingsDataActive := true
    for index, control in V016SettingsMainControls
        if index > 1
            SetBookControlVisible(control, false)
    for control in V016SettingsDataControls
        SetBookControlVisible(control, true)
    ; EndInterfaceUpdate performs the single final redraw under the frame cover.
    }
    finally EndInterfaceUpdate()
}

CloseLauncherDataV016(settings, *)
{
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    if !V016SettingsDataActive || !DllCall("IsWindow", "Ptr", settings.Hwnd)
        return
    BeginInterfaceUpdate(settings, "Returning to Launcher Settings...", false)
    try
    {
    for control in V016SettingsDataControls
        SetBookControlVisible(control, false)
    for index, control in V016SettingsMainControls
        if index > 1
            SetBookControlVisible(control, true)
    V016SettingsDataActive := false
    ; EndInterfaceUpdate performs the single final redraw under the frame cover.
    }
    finally EndInterfaceUpdate()
}

CopyExpansionPackLogs(*)
{
    global AppDataDirectory
    ; Both logs are retained separately on disk. The clipboard gets a
    ; clearly labeled combined report, including any missing-file notices.
    try SyncPatchLogToLauncherLog()
    report := ""
    found := false
    for filename in ["patch-all.log", "patch-errors.log"]
    {
        path := AppDataDirectory "\" filename
        report .= "===== " filename " =====`r`n"
        if FileExist(path)
        {
            try
            {
                content := FileRead(path, "UTF-8")
                if Trim(content) != ""
                {
                    report .= SanitizeDiagnosticText(content) "`r`n`r`n"
                    found := true
                    continue
                }
            }
            catch Error as err
            {
                report .= "Could not read file (" Type(err) ").`r`n`r`n"
                continue
            }
        }
        report .= "(No entries available)`r`n`r`n"
    }
    if !found
    {
        MsgBox("No Expansion Pack log entries are available yet.", "tes3np — Diagnostics")
        return
    }
    A_Clipboard := SanitizeDiagnosticText(report)
    MsgBox("Expansion Pack diagnostics copied. Review before sharing.", "tes3np — Diagnostics")
}

CopyAppDataLog(filename, syncLauncher := false, *)
{
    global AppDataDirectory
    if syncLauncher
        SyncPatchLogToLauncherLog()
    path := AppDataDirectory "\" filename
    if !FileExist(path)
    {
        MsgBox("No " filename " has been created yet. This usually means there are no recorded events of that type.", "tes3np — Diagnostics")
        return
    }
    try
    {
        content := SanitizeDiagnosticText(FileRead(path, "UTF-8"))
        if Trim(content) = ""
        {
            MsgBox("The diagnostic log is empty.", "tes3np — Diagnostics")
            return
        }
        if filename = "launcher.log"
        {
            ; Put the most recent game exit at the top, but retain the full
            ; original chronological log below for developer investigation.
            recentExit := ""
            for line in StrSplit(content, "`n", "`r")
                if InStr(line, "GAME | EXIT |")
                    recentExit := line
            if recentExit != ""
            {
                ; Query only the Windows crash event around this specific exit,
                ; never unrelated recent Application Error entries.
                eventDetails := FindTes3mpWindowsCrash(recentExit)
                content := "===== MOST RECENT TES3MP EXIT =====`r`n" SanitizeDiagnosticText(recentExit)
                    . "`r`n`r`n===== WINDOWS TES3MP CRASH DETAILS =====`r`n" SanitizeDiagnosticText(eventDetails)
                    . "`r`n`r`n===== COMPLETE LAUNCHER LOG =====`r`n" content
            }

        }
        A_Clipboard := content
    }
    catch Error as err
    {
        MsgBox("Could not read " filename " (" Type(err) ").", "tes3np — Diagnostics", "Icon!")
        return
    }
    MsgBox("Diagnostic log copied to your clipboard. Review before sharing.", "tes3np — Diagnostics")
}

FindTes3mpWindowsCrash(exitLine)
{
    global AppDataDirectory
    ; Windows writes Event ID 1000 asynchronously. This query is performed
    ; only on Copy Launcher Logs, not on the UI watchdog's timing-critical path.
    if StrLen(exitLine) < 19
        return "Crash event unavailable: missing exit timestamp."
    timestamp := SubStr(exitLine, 1, 19)
    scriptPath := AppDataDirectory "\tes3mp-crash-query.ps1"
    resultPath := AppDataDirectory "\tes3mp-crash-query.txt"
    script := "
    (
param([string]$Stamp, [string]$OutputFile)
try {
    $target = [datetime]::ParseExact($Stamp, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    $events = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$target.AddMinutes(-1); EndTime=$target.AddMinutes(2)} -ErrorAction Stop
    $match = $events | Where-Object { $_.Message -match '(?i)(^|[^a-z0-9_-])tes3mp[.]exe([^a-z0-9_-]|$)' } | Sort-Object TimeCreated -Descending | Select-Object -First 1
    if ($match) {
        $lines = @('Windows Application Error (Event ID 1000)', 'Recorded: ' + $match.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), 'Source: ' + $match.ProviderName, 'TES3MP crash event detected.')
        [IO.File]::WriteAllText($OutputFile, ($lines -join [Environment]::NewLine), [Text.Encoding]::UTF8)
    } else {
        [IO.File]::WriteAllText($OutputFile, 'No matching Windows Application Error (Event ID 1000) was found for this TES3MP exit. A normal exit or an exception handled by the process may not create one.', [Text.Encoding]::UTF8)
    }
} catch {
    [IO.File]::WriteAllText($OutputFile, 'Windows crash details unavailable (Windows event query failed).', [Text.Encoding]::UTF8)
}
    )"
    try
    {
        DirCreate(AppDataDirectory)
        if FileExist(resultPath)
            FileDelete(resultPath)
        if FileExist(scriptPath)
            FileDelete(scriptPath)
        FileAppend(script, scriptPath, "UTF-8")
        ; No shell interpolation: quote the time and paths as separate arguments.
        command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' scriptPath '" "' timestamp '" "' resultPath '"'
        RunWait(command, , "Hide")
        if FileExist(resultPath)
            return Trim(FileRead(resultPath, "UTF-8"))
        return "Windows crash diagnostics could not be retrieved."
    }
    catch Error as err
        return "Windows crash diagnostics unavailable (" Type(err) ")."
}

ShowResetAppDataActions(*)
{
    global AppDataDirectory, LauncherDataResetting, EmbeddedChatPid
    choice := MsgBox("Yes: Open the AppData folder`nNo: Reset AppData`nCancel: Return", "tes3np — Reset AppData", "YesNoCancel Icon?")
    if choice = "Yes"
        return OpenLauncherDataFolder()
    if choice != "No"
        return
    warning := "This will delete all information inside tes3np AppData, including your saved characters and launcher settings.`n`nYou should export your character data before doing this.`n`ntes3np will close after the reset.`n`nAre you sure you want to continue?"
    if MsgBox(warning, "tes3np — Reset AppData", "YesNo Icon!") != "Yes"
        return
    if MsgBox("This cannot be undone. Permanently reset tes3np AppData and close now?", "tes3np — Final Confirmation", "YesNo Icon!") != "Yes"
        return
    ; A live patch worker owns changes and cannot be interrupted safely.
    if PatchInProgress()
    {
        MsgBox("Finish the current patch operation before resetting launcher data.", "tes3np — Reset AppData", "Icon!")
        return
    }
    ; ChatHost continuously indexes Discord history. Stop this owned process
    ; and game recovery BEFORE deleting the shared Roaming AppData root.
    StopClient()
    chatPid := EmbeddedChatPid
    StopEmbeddedInGameChat()
    ; ProcessClose requests termination but may return before Windows has
    ; released WebView2 files. Never delete a profile while its writer lives.
    if chatPid
    {
        try stillRunning := ProcessWaitClose(chatPid, 5)
        catch as err
        {
            MsgBox("Could not confirm that Game Chat closed: " err.Message
                "`n`nNo launcher data was deleted. Restart TES3NP before retrying.",
                "tes3np — Reset AppData", "Icon!")
            return
        }
        if stillRunning
        {
            MsgBox("Game Chat is still closing. No launcher data was deleted."
                "`n`nRestart TES3NP before retrying the reset.",
                "tes3np — Reset AppData", "Icon!")
            return
        }
    }
    LauncherDataResetting := true
    try
    {
        if DirExist(AppDataDirectory)
            DirDelete(AppDataDirectory, true)
    }
    catch as err
    {
        LauncherDataResetting := false
        MsgBox("AppData reset failed: " err.Message "`n`nRestart tes3np before retrying.", "tes3np — Reset AppData", "Icon!")
        return
    }
    ; Do not recreate AppData here, and do not leave background timers running:
    ; CleanupLauncher's reset path skips its normal settings/log writes.
    ExitApp()
}

OpenClientSelectionSettings(*)
{
    global LauncherGui, LauncherMorrowindFont, DataFile, V016SettingsGuiHwnd
    mode := IniRead(DataFile, "Launch", "ClientMode", "Bundled")
    saved := FileExist(GetCustomOverrideFolder() "\tes3mp.exe") ? true : false
    ; LauncherGui is disabled while the parchment Settings screen is open.
    ; Own this dialog to Settings instead, otherwise closing it can focus the
    ; disabled launcher and make both windows appear to have vanished.
    ownerHwnd := V016SettingsGuiHwnd && DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd) ? V016SettingsGuiHwnd : LauncherGui.Hwnd
    menu := Gui("+Owner" ownerHwnd " -MinimizeBox -MaximizeBox", "tes3np — Game Client Settings")
    menu.BackColor := "E2CEA2"
    menu.SetFont("s14 Bold c241408", LauncherMorrowindFont)
    menu.Add("Text", "x24 y20 w480 h35", "Game Client Settings")
    menu.SetFont("s10 c382314", "Segoe UI")
    display := mode = "Bundled" ? "Original TES3NP runtime" : mode = "CustomOverrides" ? "Custom overrides active" : "Legacy custom client (" mode ")"
    activeLabel := menu.Add("Text", "x24 y65 w480 h25", "Active client: " display)
    menu.Add("Text", "x24 y95 w480 h48", "Choose how TES3NP launches the game. Custom files are kept separate from the protected original runtime.")
    menu.SetFont("s11 Bold", "Segoe UI")
    customize := menu.Add("Button", "x24 y153 w480 h43", "Set Up Custom EXE")
    reactivate := menu.Add("Button", "x24 y205 w480 h43", "Use Saved Custom Client")
    reactivate.Enabled := saved
    restore := menu.Add("Button", "x24 y257 w480 h43", "Use Original TES3NP Client")
    statusLabel := menu.Add("Text", "x24 y307 w480 h40 +Wrap", "Select an option to change your game client.")
    close := menu.Add("Button", "x24 y354 w480 h38", "Close")
    menu.ClientFeedback := {Active: activeLabel, Status: statusLabel, Reactivate: reactivate}
    customize.OnEvent("Click", (*) => ConfigureCustomClientV016(menu))
    reactivate.OnEvent("Click", (*) => ActivateSavedCustomClientV016(menu))
    restore.OnEvent("Click", (*) => RestoreBundledClientV016(menu))
    close.OnEvent("Click", CloseGameClientSettingsV016.Bind(menu))
    menu.OnEvent("Escape", CloseGameClientSettingsV016.Bind(menu))
    menu.OnEvent("Close", CloseGameClientSettingsV016.Bind(menu))
    menu.Show("w528 h416")
}

RestoreBundledClientV016(menu, *)
{
    global DataFile
    IniWrite("Bundled", DataFile, "Launch", "ClientMode")
    LogLauncherEvent("GAME | Original bundled runtime restored as active client.")
    UpdateGameClientFeedbackV016(menu, "Original TES3NP runtime", "Original client restored. Your custom files remain saved for later.")
}

ActivateSavedCustomClientV016(menu, *)
{
    global DataFile
    if !FileExist(GetCustomOverrideFolder() "\tes3mp.exe")
        return
    IniWrite("CustomOverrides", DataFile, "Launch", "ClientMode")
    LogLauncherEvent("GAME | Saved custom runtime overrides reactivated.")
    UpdateGameClientFeedbackV016(menu, "Custom overrides active", "Saved custom EXE and dependencies are active again.")
}

ConfigureCustomClientV016(menu, *)
{
    global DataFile, AppDataDirectory
    source := FileSelect(1, , "Choose your modified tes3mp.exe", "Executable (*.exe)")
    if source = ""
        return
    SplitPath(source, &name)
    if StrLower(name) != "tes3mp.exe" || !FileExist(source)
    {
        MsgBox("Select a file named tes3mp.exe.", "Game Client", "Icon!")
        return
    }
    ; Clear action names make the optional step unambiguous.
    options := Gui("+Owner" menu.Hwnd " -MinimizeBox -MaximizeBox", "Optional Client Dependencies")
    options.BackColor := "E2CEA2"
    options.SetFont("s12 Bold c241408", "Segoe UI")
    options.Add("Text", "x20 y20 w470 h30", "Does your custom EXE need additional files?")
    options.SetFont("s10 c382314", "Segoe UI")
    options.Add("Text", "x20 y60 w470 h48", "Choose a folder containing matching DLLs, layouts, or other resources, or use TES3NP's bundled dependencies.")
    add := options.Add("Button", "x20 y122 w470 h40", "Choose Dependencies Folder")
    skip := options.Add("Button", "x20 y174 w470 h40", "Use Bundled Dependencies Only")
    cancel := options.Add("Button", "x20 y236 w470 h34", "Cancel Setup")
    add.OnEvent("Click", (*) => ChooseCustomDependencyFolderV016(menu, options, source))
    skip.OnEvent("Click", (*) => SaveCustomClientV016(menu, options, source, ""))
    cancel.OnEvent("Click", (*) => options.Destroy())
    options.OnEvent("Escape", (*) => options.Destroy())
    options.Show("w510 h292")
}

ChooseCustomDependencyFolderV016(menu, options, source, *)
{
    ; Use the modern Explorer-style picker, but select a folder rather than a file.
    folder := FileSelect("D", , "Select additional dependencies and resources")
    if folder != ""
        SaveCustomClientV016(menu, options, source, folder)
}

SaveCustomClientV016(menu, options, source, folder, *)
{
    global DataFile, AppDataDirectory
    if !PrepareMarkerlessClientRuntime() || !InstallCustomClientOverrides(source, folder)
        return
    DirCreate(AppDataDirectory)
    IniWrite("CustomOverrides", DataFile, "Launch", "ClientMode")
    LogLauncherEvent("GAME | Custom client configured | Additional dependencies: " (folder = "" ? "none" : "selected") ".")
    options.Destroy()
    UpdateGameClientFeedbackV016(menu, "Custom overrides active", folder = ""
        ? "Custom EXE saved. Bundled dependencies will be used."
        : "Custom EXE and dependency files saved successfully. Ready to launch.")
}

UpdateGameClientFeedbackV016(menu, active, message)
{
    if !IsObject(menu) || !DllCall("IsWindow", "Ptr", menu.Hwnd)
        return
    menu.ClientFeedback.Active.Text := "Active client: " active
    menu.ClientFeedback.Status.Text := message
    menu.ClientFeedback.Reactivate.Enabled := FileExist(GetCustomOverrideFolder() "\tes3mp.exe") ? true : false
    menu.Show()
    WinActivate("ahk_id " menu.Hwnd)
}

CloseGameClientSettingsV016(menu, *)
{
    global V016SettingsGuiHwnd, LauncherGui
    try menu.Destroy()
    if V016SettingsGuiHwnd && DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd)
    {
        WinShow("ahk_id " V016SettingsGuiHwnd)
        WinActivate("ahk_id " V016SettingsGuiHwnd)
    }
    else if IsObject(LauncherGui) && DllCall("IsWindow", "Ptr", LauncherGui.Hwnd)
    {
        WinShow("ahk_id " LauncherGui.Hwnd)
        WinActivate("ahk_id " LauncherGui.Hwnd)
    }
}
