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
    return Max(7, Round(value * V016SettingsScale))
}

AddV016SettingsCopy(settings, x, y, width, reservedHeight, text)
{
    ; Let the native control measure the wrapped text with the current
    ; font and DPI. Reuse the default space unless the copy needs more.
    label := settings.Add("Text", "x" V016S(x) " y" y " w" V016S(width) " BackgroundTrans +Wrap", text)
    label.GetPos(, , , &measuredHeight)
    reserved := V016S(reservedHeight)
    if measuredHeight < reserved
        label.Move(, , , reserved)
    return Max(0, measuredHeight - reserved)
}

GrowV016SettingsParchment(settings, extra)
{
    if extra <= settings.ParchmentExtra
        return false
    settings.ParchmentExtra := extra
    settings.Parchment.Move(, , , V016S(650) + extra)
    settings.Parchment.Value := A_ScriptDir "\\assets\\controls\\scroll-panel.png"
    return true
}

GetV016SettingsFitScale()
{
    global LauncherGui
    ; Match the active launcher percentage, bounded by owner work-area fit.
    ; The old independent "readability" fit left Settings at 100% even for
    ; a 50% launcher. Keep the same proportional sizes for every page.
    WinGetPos(&x, &y, &w, &h, "ahk_id " LauncherGui.Hwnd)
    monitor := MonitorFromPoint(x + w // 2, y + h // 2)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    dpi := A_ScreenDPI / 96
    fit := Min(1.0, (right - left - 24) / (512 * dpi),
        (bottom - top - 24) / (590 * dpi))
    return Max(0.45, Min(GetOwnedMenuScale(), fit))
}

HandleV016SettingsHitTest(wParam, lParam, msg, hwnd)
{
    global V016SettingsGuiHwnd
    if !V016SettingsGuiHwnd || hwnd != V016SettingsGuiHwnd || !DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd, "Int")
        return
    pt := Buffer(8, 0)
    NumPut("Int", (lParam & 0xFFFF) << 48 >> 48, pt, 0)
    NumPut("Int", ((lParam >> 16) & 0xFFFF) << 48 >> 48, pt, 4)
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
    MoveStyledButton(AddCharacterButton, 70, Profiles.Length ? 540 : 164, 370, 30)
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
    global LauncherGui, LauncherScale, LauncherScaleMode, AccessibilityTextSize, FollowWindowsAccessibility, LauncherMorrowindFont, DataFile
    global V016SettingsGuiHwnd, V016SettingsScale, V016ReadabilityState, V016FollowWindowsState

    ; Launcher Settings is a single modal-style window. If it is already open,
    ; bring that instance forward instead of creating duplicates.
    if V016SettingsGuiHwnd && DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd, "Int")
    {
        WinActivate("ahk_id " V016SettingsGuiHwnd)
        return
    }
    V016SettingsGuiHwnd := 0

    ; Match the existing launcher scale, with the monitor as an upper bound.
    V016SettingsScale := GetV016SettingsFitScale()

    settings := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border -MinimizeBox -MaximizeBox +ToolWindow", "tes3np — Launcher Settings")
    settings.MarginX := 0, settings.MarginY := 0
    settings.BackColor := "010101"
    settings.MenuButtonScale := V016SettingsScale
    settings.SavedReadability := IniRead(DataFile, "Accessibility", "EnhancedReadability", "0") = "1" ? 1 : 0
    settings.SavedReduceMotion := IniRead(DataFile, "Accessibility", "ReduceMotion", "0") = "1" ? 1 : 0
    V016ReadabilityState := settings.SavedReadability
    V016FollowWindowsState := FollowWindowsAccessibility ? 1 : 0

    settings.Parchment := settings.Add("Picture", "x" V016S(-12) " y" V016S(-20) " w" V016S(544) " h" V016S(650), A_ScriptDir "\\assets\\controls\\scroll-panel.png")
    settings.ParchmentExtra := 0

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
    copyExtra := AddV016SettingsCopy(settings, 32, V016S(196), 448, 40,
        "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" (V016S(242) + copyExtra) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Interface text")
    settings.SetFont("s" V016Font(12) " Norm c241408", LauncherMorrowindFont)
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x" V016S(184) " y" (V016S(237) + copyExtra) " w" V016S(296) " Choose" textChoice, textChoices)
    settings.SetFont("s" V016Font(11) " Norm c382314", LauncherMorrowindFont)
    copyExtra += AddV016SettingsCopy(settings, 32, V016S(269) + copyExtra, 448, 30,
        "Choose how big or small the launcher interface is for you.")

    settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
    readabilityPrefix := V016ReadabilityState ? "☑" : "■"
    readability := settings.Add("Text", "x" V016S(32) " y" (V016S(305) + copyExtra) " w" V016S(448) " h" V016S(32) " +0x100 BackgroundTrans", readabilityPrefix "  Enhanced readability")
    readability.OnEvent("Click", ToggleV016ReadabilityControl.Bind(readability))
    settings.ReadabilityControl := readability
    settings.SetFont("s" V016Font(11) " Norm c382314", LauncherMorrowindFont)
    copyExtra += AddV016SettingsCopy(settings, 70, V016S(335) + copyExtra, 410, 42,
        "Improves readability by providing stronger contrast and brighter button text.")
    GrowV016SettingsParchment(settings, copyExtra)

    readabilityValue := {Value: V016ReadabilityState}
    followWindowsValue := {Value: FollowWindowsAccessibility ? 1 : 0}
    reduceMotionBox := {Value: settings.SavedReduceMotion}

    AddStyledButton(settings, V016S(32), V016S(387) + copyExtra, V016S(214), V016S(30), "Preview Changes", ApplyV016LauncherSettings.Bind(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(266), V016S(387) + copyExtra, V016S(214), V016S(30), "Reset Changes", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(32), V016S(435) + copyExtra, V016S(214), V016S(30), "Launcher Data", OpenAppDataSettingsV016.Bind(settings))
    AddStyledButton(settings, V016S(266), V016S(435) + copyExtra, V016S(214), V016S(30), "TES3MP Setup", OpenClientSelectionSettings)
    ; Restore the original full-width Close Settings button exactly as it
    ; appeared before the desktop-shortcut button divided this row.
    AddStyledButton(settings, V016S(32), V016S(483) + copyExtra, V016S(448), V016S(30),
        "Close Settings", CloseLauncherSettingsV016.Bind(settings))

    ; Keep both parchment views in the same GUI. The common backdrop is never
    ; destroyed, and all data controls are created only once per settings window.
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    V016SettingsMainControls := []
    for control in settings
        V016SettingsMainControls.Push(control)
    V016SettingsDataControls := []
    V016SettingsDataActive := false

    settings.OnEvent("Escape", HandleLauncherSettingsEscapeV016)
    settings.OnEvent("Close", CloseLauncherSettingsV016.Bind(settings))
    V016SettingsGuiHwnd := settings.Hwnd
    ; The transparency key must be applied to the hidden Settings GUI, but
    ; that alone does not prevent DWM from presenting its unpainted native
    ; controls on the first visible frame. Cloak before Show and uncloak only
    ; after the completed parchment and themed controls have been painted.
    staged := SetPageCompositorCloak(settings, true)
    try
    {
        settings.Show("Hide w" V016S(512) " h" (V016S(590) + settings.ParchmentExtra))
        ; Anchor after sizing, while still DWM-cloaked, to the actual current
        ; launcher HWND instead of Windows' stale/default page position.
        PositionOwnedMenuAtParent(settings, LauncherGui)
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
    catch as err
    {
        CloseLauncherSettingsV016(settings)
        throw err
    }
    finally
    {
        if staged
            try SetPageCompositorCloak(settings, false)
    }
}

HandleLauncherSettingsEscapeV016(settings)
{
    if IsBugReportPageVisible(settings)
        CloseBugReportPage(settings)
    else
        CloseLauncherSettingsV016(settings)
}

CloseLauncherSettingsV016(settings, *)
{
    global LauncherGui, V016SettingsGuiHwnd
    if settings.HasOwnProp("ReportControls")
    {
        if settings.ReportBusy
            return true
        StopBugReportRequest(settings)
    }
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
    PreviewLauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue)
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
    PreviewLauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue, true)
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
        copyExtra := AddV016SettingsCopy(settings, 42, V016S(166), 428, 65,
            "Characters and preferences are saved in AppData. Export characters before resetting.")
        AddStyledButton(settings, V016S(32), V016S(243) + copyExtra, V016S(448), V016S(30), "Open Launcher AppData Folder", OpenLauncherDataFolder)
        AddStyledButton(settings, V016S(32), V016S(284) + copyExtra, V016S(214), V016S(30), "Reset Launcher AppData", ShowResetAppDataActions)
        settings.ReportPageButton := AddStyledButton(settings, V016S(266), V016S(284) + copyExtra, V016S(214), V016S(30),
            "Report A Bug", OpenBugReportPage.Bind(settings))
        settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
        settings.Add("Text", "x" V016S(32) " y" (V016S(351) + copyExtra) " w" V016S(448) " h" V016S(24) " BackgroundTrans", "Advanced Diagnostic Logs")
        AddStyledButton(settings, V016S(32), V016S(385) + copyExtra, V016S(448), V016S(30), "Copy Launcher Logs", CopyAppDataLog.Bind("launcher.log"))
        AddStyledButton(settings, V016S(32), V016S(426) + copyExtra, V016S(214), V016S(30), "Copy Expansion Pack Logs", CopyExpansionPackLogs)
        AddStyledButton(settings, V016S(266), V016S(426) + copyExtra, V016S(214), V016S(30), "Copy Render Errors", CopyAppDataLog.Bind("render-errors.log"))
        AddStyledButton(settings, V016S(32), V016S(483) + copyExtra, V016S(448), V016S(30), "Go Back", CloseLauncherDataV016.Bind(settings))
        if GrowV016SettingsParchment(settings, copyExtra)
            settings.Show("NA h" (V016S(590) + settings.ParchmentExtra))
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

CopyAppDataLog(filename, *)
{
    global AppDataDirectory
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
    ; Windows writes Event ID 1000 asynchronously. This query is performed
    ; only on Copy Launcher Logs, not on the UI watchdog's timing-critical path.
    if StrLen(exitLine) < 19
        return "Crash event unavailable: missing exit timestamp."
    timestamp := SubStr(exitLine, 1, 19)
    query := A_Temp "\tes3np-crash-query-" ProcessExist() "-" A_TickCount
    scriptPath := query ".ps1"
    resultPath := query ".txt"
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
    finally
    {
        try FileDelete(scriptPath)
        try FileDelete(resultPath)
    }
}

ShowResetAppDataActions(*)
{
    global AppDataDirectory, LauncherDataResetting, EmbeddedChatPid
    choice := MsgBox("Yes: Open the AppData folder`nNo: Reset AppData`nCancel: Return", "tes3np — Reset AppData", "YesNoCancel Icon?")
    if choice = "Yes"
        return OpenLauncherDataFolder()
    if choice != "No" || !CanResetLauncherAppData()
        return
    warning := "This will delete all information inside tes3np AppData, including your saved characters and launcher settings.`n`nYou should export your character data before doing this.`n`ntes3np will close after the reset.`n`nAre you sure you want to continue?"
    if MsgBox(warning, "tes3np — Reset AppData", "YesNo Icon!") != "Yes"
        return
    if MsgBox("This cannot be undone. Permanently reset tes3np AppData and close now?", "tes3np — Final Confirmation", "YesNo Icon!") != "Yes"
        return
    if !CanResetLauncherAppData()
        return
    ; ChatHost continuously indexes Discord history. Stop this owned process
    ; and game recovery BEFORE deleting the shared Roaming AppData root.
    StopGameRecovery()
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
    ; A worker may have started while the confirmations or Chat Host wait yielded.
    previousCritical := Critical("On")
    errorMessage := ""
    try
    {
        canReset := CanResetLauncherAppData(false)
        if canReset
        {
            LauncherDataResetting := true
            if DirExist(AppDataDirectory)
                DirDelete(AppDataDirectory, true)
        }
    }
    catch as err
    {
        LauncherDataResetting := false
        errorMessage := "AppData reset failed: " err.Message "`n`nRestart tes3np before retrying."
    }
    finally Critical(previousCritical)
    if errorMessage != ""
    {
        MsgBox(errorMessage, "tes3np — Reset AppData", "Icon!")
        return
    }
    if !canReset
    {
        CanResetLauncherAppData()
        return
    }
    ; Do not recreate AppData here, and do not leave background timers running:
    ; CleanupLauncher's reset path skips its normal settings/log writes.
    ExitApp()
}

CanResetLauncherAppData(showMessage := true)
{
    global ExpansionRecoveryPending, MacroImport
    if PatchInProgress()
        message := "Finish the current Expansion Pack operation before resetting launcher data."
    else if ExpansionRecoveryPending
        message := "An interrupted Expansion Pack import still needs its backups. Close any TES3MP/OpenMW clients and restart TES3NP to retry recovery before resetting launcher data."
    else if IsObject(MacroImport)
        message := "Finish the current macro import before resetting launcher data."
    else
        return true
    if showMessage
        MsgBox(message, "tes3np — Reset AppData", "Icon!")
    return false
}

OpenClientSelectionSettings(*)
{
    global LauncherGui, DataFile, V016SettingsGuiHwnd
    mode := IniRead(DataFile, "Launch", "ClientMode", "Bundled")
    saved := FileExist(GetCustomOverrideFolder() "\tes3mp.exe") ? true : false
    ; The Settings page owns this borderless native card, not the disabled
    ; launcher. A compact card is sized from its actual visible actions.
    ownerHwnd := V016SettingsGuiHwnd && DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd) ? V016SettingsGuiHwnd : LauncherGui.Hwnd
    initialHeight := saved ? 460 : 412
    menu := CreateGoldNativePrompt(ownerHwnd, "tes3np — TES3MP Setup", 680, initialHeight)
    menu.SetFont("s17 Bold cC5A45C", "Georgia")
    heading := menu.Add("Text", "x30 y25 w620 BackgroundTrans +Wrap", "TES3MP Setup")
    heading.GetPos(, , , &headingHeight)
    activeY := Max(78, 25 + headingHeight + 8)
    display := mode = "Bundled" ? "Using the included TES3MP setup" : "Using your custom TES3MP setup"
    menu.SetFont("s11 Bold cE7BE70", "Segoe UI")
    activeLabel := menu.Add("Text", "x30 y" activeY " w620 BackgroundTrans +Wrap", display)
    activeLabel.GetPos(, , , &activeHeight)
    detailsY := Max(115, activeY + activeHeight + 8)
    menu.SetFont("s10 Norm cEDE1C9", "Segoe UI")
    details := menu.Add("Text", "x30 y" detailsY " w620 BackgroundTrans +Wrap",
        "Choose which copy of TES3MP opens when you launch the game. "
        . "TES3NP comes with a setup that's ready to play.")
    textOffset := FitGameClientPromptCopyV016(menu, details, detailsY, 190)
    customize := AddStyledButton(menu, 30, 190 + textOffset, 620, 40, "Choose a Custom EXE", (*) => ConfigureCustomClientV016(menu))
    reactivate := AddStyledButton(menu, 30, 238 + textOffset, 620, 40, "Use Custom Setup", (*) => ActivateSavedCustomClientV016(menu))
    reactivate.Visible := saved
    reactivate.Enabled := saved
    restoreY := (saved ? 286 : 238) + textOffset
    restore := AddStyledButton(menu, 30, restoreY, 620, 40, "Use Included TES3MP", (*) => RestoreBundledClientV016(menu))
    menu.SetFont("s10 Norm cEDE1C9", "Segoe UI")
    statusY := (saved ? 339 : 291) + textOffset
    statusLabel := menu.Add("Text", "x30 y" statusY " w620 h48 BackgroundTrans +Wrap", "")
    closeY := (saved ? 399 : 351) + textOffset
    close := AddStyledButton(menu, 231, closeY, 218, 38, "Close", CloseGameClientSettingsV016.Bind(menu))
    menu.ClientFeedback := {Active: activeLabel, Status: statusLabel, Reactivate: reactivate,
        Restore: restore, Close: close, SavedVisible: saved, TextOffset: textOffset}
    menu.OnEvent("Escape", CloseGameClientSettingsV016.Bind(menu))
    menu.OnEvent("Close", CloseGameClientSettingsV016.Bind(menu))
    ShowGoldNativePrompt(menu)
}

FitGameClientPromptCopyV016(panel, details, detailsY, buttonY)
{
    details.GetPos(, , , &textHeight)
    ; Allow an extra line because scaled fonts and control widths round separately.
    paddedHeight := textHeight + Ceil(24 * A_ScreenDPI / 96)
    details.Move(, , , paddedHeight)
    offset := Max(0, detailsY + paddedHeight + 12 - buttonY)
    if offset
    {
        panel.NativePromptHeight += offset
        panel.NativePromptBackground.Move(, , , panel.NativePromptHeight - 4)
    }
    return offset
}

; Reflow the card when a new saved client makes its extra action available.
RefreshGameClientSettingsLayoutV016(menu)
{
    if !IsObject(menu) || !DllCall("IsWindow", "Ptr", menu.Hwnd)
        return
    saved := FileExist(GetCustomOverrideFolder() "\tes3mp.exe") ? true : false
    state := menu.ClientFeedback
    state.Reactivate.Enabled := saved
    state.Reactivate.Visible := saved
    if state.SavedVisible = saved
        return
    scale := menu.HasOwnProp("OwnedContentScale") ? menu.OwnedContentScale : 1.0
    state.SavedVisible := saved
    offset := state.TextOffset
    moveY := (saved ? 286 : 238) + offset
    MoveStyledButton(state.Restore, Round(30 * scale), Round(moveY * scale),
        Round(620 * scale), Round(40 * scale))
    state.Status.Move(Round(30 * scale), Round(((saved ? 339 : 291) + offset) * scale),
        Round(620 * scale), Round(48 * scale))
    MoveStyledButton(state.Close, Round(231 * scale), Round(((saved ? 399 : 351) + offset) * scale),
        Round(218 * scale), Round(38 * scale))
    menu.NativePromptHeight := (saved ? 460 : 412) + offset
    menu.NativePromptBackground.Move(Round(2 * scale), Round(2 * scale),
        Round(676 * scale), Round((menu.NativePromptHeight - 4) * scale))
    ShowCenteredGoldPrompt(menu, menu.NativePromptBackdrop,
        Round(680 * scale), Round(menu.NativePromptHeight * scale))
    DllCall("RedrawWindow", "Ptr", menu.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
}

RestoreBundledClientV016(menu, *)
{
    global DataFile
    IniWrite("Bundled", DataFile, "Launch", "ClientMode")
    LogLauncherEvent("GAME | Original bundled runtime restored as active client.")
    UpdateGameClientFeedbackV016(menu, "Using the included TES3MP setup", "The included setup is ready to play.")
}

ActivateSavedCustomClientV016(menu, *)
{
    global DataFile
    if !FileExist(GetCustomOverrideFolder() "\tes3mp.exe")
        return
    IniWrite("CustomOverrides", DataFile, "Launch", "ClientMode")
    LogLauncherEvent("GAME | Saved custom runtime overrides reactivated.")
    UpdateGameClientFeedbackV016(menu, "Using your custom TES3MP setup", "Your custom setup is ready to play.")
}

ConfigureCustomClientV016(menu, *)
{
    source := FileSelect(1, , "Choose your custom tes3mp.exe", "Executable (*.exe)")
    if source = ""
        return
    SplitPath(source, &name)
    if StrLower(name) != "tes3mp.exe" || !FileExist(source)
    {
        MsgBox("Select a file named tes3mp.exe.", "TES3MP Setup", "Icon!")
        return
    }
    ; Preserve the dependency workflow inside the same borderless,
    ; changelog-style native card system as its parent TES3MP Setup.
    options := CreateGoldNativePrompt(menu, "Set Up Your Custom EXE", 640, 382)
    options.SetFont("s15 Bold cC5A45C", "Georgia")
    heading := options.Add("Text", "x30 y22 w580 BackgroundTrans +Wrap", "Set Up Your Custom EXE")
    heading.GetPos(, , , &headingHeight)
    detailsY := Max(72, 22 + headingHeight + 8)
    options.SetFont("s10 Norm cEDE1C9", "Segoe UI")
    details := options.Add("Text", "x30 y" detailsY " w580 BackgroundTrans +Wrap",
        "TES3NP will use the tes3mp.exe you selected. If it came with its own DLLs or other files, "
        . "choose the folder that contains them. If you're only swapping the EXE, use the files that come with TES3NP.")
    textOffset := FitGameClientPromptCopyV016(options, details, detailsY, 198)
    add := AddStyledButton(options, 30, 198 + textOffset, 580, 38, "Choose Folder With Extra Files",
        (*) => ChooseCustomDependencyFolderV016(menu, options, source))
    skip := AddStyledButton(options, 30, 246 + textOffset, 580, 38, "Use My Custom Exe",
        (*) => SaveCustomClientV016(menu, options, source, ""))
    cancel := AddStyledButton(options, 188, 317 + textOffset, 264, 38, "Cancel",
        (*) => CloseGoldNativePrompt(options))
    options.OnEvent("Escape", (*) => CloseGoldNativePrompt(options))
    options.OnEvent("Close", (*) => CloseGoldNativePrompt(options))
    ShowGoldNativePrompt(options)
}

ChooseCustomDependencyFolderV016(menu, options, source, *)
{
    ; Use the modern Explorer-style picker, but select a folder rather than a file.
    folder := FileSelect("D", , "Choose the folder with your custom EXE's extra files")
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
    CloseGoldNativePrompt(options)
    UpdateGameClientFeedbackV016(menu, "Using your custom TES3MP setup", folder = ""
        ? "Custom EXE saved with included files."
        : "Custom EXE and extra files saved.")
}

UpdateGameClientFeedbackV016(menu, active, message)
{
    if !IsObject(menu) || !DllCall("IsWindow", "Ptr", menu.Hwnd)
        return
    menu.ClientFeedback.Active.Text := active
    menu.ClientFeedback.Status.Text := message
    RefreshGameClientSettingsLayoutV016(menu)
    menu.Show()
    WinActivate("ahk_id " menu.Hwnd)
}

CloseGameClientSettingsV016(menu, *)
{
    global V016SettingsGuiHwnd, LauncherGui
    CloseGoldNativePrompt(menu)
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
