; Launcher-specific display and accessibility settings.
; Auto mode is the default: keep the launcher at 100% whenever it fits and only
; reduce it when the monitor's usable work area requires it.

global LauncherScale := 100
global LauncherScaleMode := "Auto"
global LauncherRequestedScale := 100
global AccessibilityTextSize := "Normal"
global EnhancedReadability := false
global ReduceMotion := false
global FollowWindowsAccessibility := true

global WindowsHighContrastDetected := false
global WindowsAnimationsDisabled := false

LoadLauncherScale()
{
    global DataFile, LauncherScale, LauncherScaleMode, LauncherRequestedScale
    global AccessibilityTextSize, EnhancedReadability, ReduceMotion, FollowWindowsAccessibility
    saved := IniRead(DataFile, "Launcher", "Scale", "Auto")
    AccessibilityTextSize := IniRead(DataFile, "Accessibility", "TextSize", "Normal")
    EnhancedReadability := IniRead(DataFile, "Accessibility", "EnhancedReadability", "0") = "1"
    ReduceMotion := IniRead(DataFile, "Accessibility", "ReduceMotion", "0") = "1"
    FollowWindowsAccessibility := IniRead(DataFile, "Accessibility", "FollowWindows", "1") = "1"
    if !RegExMatch(AccessibilityTextSize, "^(Normal|Large|Extra Large)$")
        AccessibilityTextSize := "Normal"
    DetectWindowsAccessibility()
    ApplyWindowsAccessibilityPreferences()
    if !RegExMatch(saved, "^(?:50|60|70|80|90|100)$")
    {
        LauncherScaleMode := "Auto"
        LauncherScale := LauncherRequestedScale := 100
        return
    }
    LauncherScaleMode := "Manual"
    LauncherScale := LauncherRequestedScale := Integer(saved)
}

DetectWindowsAccessibility()
{
    global WindowsHighContrastDetected, WindowsAnimationsDisabled
    WindowsHighContrastDetected := false
    WindowsAnimationsDisabled := false
    hcSize := A_PtrSize = 8 ? 16 : 12
    hc := Buffer(hcSize, 0)
    NumPut("UInt", hcSize, hc, 0)
    if DllCall("SystemParametersInfoW", "UInt", 0x0042, "UInt", hcSize, "Ptr", hc.Ptr, "UInt", 0)
        WindowsHighContrastDetected := (NumGet(hc, 4, "UInt") & 0x00000001) != 0
    animations := Buffer(4, 0)
    if DllCall("SystemParametersInfoW", "UInt", 0x1042, "UInt", 0, "Ptr", animations.Ptr, "UInt", 0)
        WindowsAnimationsDisabled := NumGet(animations, 0, "Int") = 0
}

ApplyWindowsAccessibilityPreferences()
{
    global FollowWindowsAccessibility, WindowsHighContrastDetected, WindowsAnimationsDisabled, EnhancedReadability, ReduceMotion
    if !FollowWindowsAccessibility
        return
    if WindowsHighContrastDetected
        EnhancedReadability := true
    if WindowsAnimationsDisabled
        ReduceMotion := true
}

ScaleChoiceIndex(scale)
{
    return Max(1, Min(6, ((scale - 50) // 10) + 1))
}

PreviewLauncherSettings(settings, scaleList, textList, readability, reduceMotionBox, followWindows, reset := false)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, LauncherRequestedScale
    global AccessibilityTextSize, EnhancedReadability, ReduceMotion, FollowWindowsAccessibility
    global V016ReadabilityState, V016FollowWindowsState
    oldScale := LauncherScale, oldRequestedScale := LauncherRequestedScale, oldMode := LauncherScaleMode
    oldText := AccessibilityTextSize
    oldReadability := EnhancedReadability, oldReduceMotion := ReduceMotion, oldFollowWindows := FollowWindowsAccessibility
    oldReadabilityChoice := settings.SavedReadability
    oldMotionChoice := settings.SavedReduceMotion
    saveFailed := false
    saved := false
    if scaleList.Value = 1
    {
        LauncherScaleMode := "Auto", pendingScale := "Auto"
    }
    else
    {
        LauncherScaleMode := "Manual"
        LauncherRequestedScale := Integer(StrReplace(scaleList.Text, "%")), pendingScale := LauncherRequestedScale
    }
    AccessibilityTextSize := textList.Text
    requestedReadability := readability.Value = 1
    requestedReduceMotion := reduceMotionBox.Value = 1
    EnhancedReadability := requestedReadability
    ReduceMotion := requestedReduceMotion
    FollowWindowsAccessibility := followWindows.Value = 1
    DetectWindowsAccessibility()
    ApplyWindowsAccessibilityPreferences()
    operation := "preview"
    try
    {
        message := reset ? "Resetting display settings..." : "Applying display settings..."
        RefreshLauncherDisplay(message, settings)
        LauncherGui.Opt("+OwnDialogs")
        result := MsgBox("Do these display settings look good?`n`nChoose Yes to keep them. Choose No to return to your previous settings.", "tes3np — Confirm Display Settings", "YesNo Icon?")
        if result = "Yes"
        {
            operation := "save"
            SaveLauncherDisplaySettings(pendingScale, AccessibilityTextSize,
                requestedReadability, requestedReduceMotion, FollowWindowsAccessibility)
            saved := true
        }
    }
    catch Error as err
    {
        saveFailed := true
        LogLauncherEvent("UI | Display settings " operation " failed (" Type(err) ", line " err.Line ").")
    }
    if saved
    {
        CloseLauncherSettingsV016(settings)
        return
    }
    LauncherScale := oldScale, LauncherRequestedScale := oldRequestedScale
    LauncherScaleMode := oldMode, AccessibilityTextSize := oldText
    EnhancedReadability := oldReadability, ReduceMotion := oldReduceMotion, FollowWindowsAccessibility := oldFollowWindows
    try RefreshLauncherDisplay("Restoring display settings...", settings)
    catch Error as err
        LogLauncherEvent("UI | Display settings restore failed (" Type(err) ", line " err.Line ").")
    ; A declined preview must restore the visible selectors as well as the
    ; launcher geometry. Otherwise Reset/Preview can leave controls showing
    ; defaults until the next login even though the old state was restored.
    scaleList.Choose(oldMode = "Auto" ? 1 : ScaleChoiceIndex(oldRequestedScale) + 1)
    textList.Choose(oldText = "Large" ? 2 : oldText = "Extra Large" ? 3 : 1)
    readability.Value := oldReadabilityChoice
    reduceMotionBox.Value := oldMotionChoice
    followWindows.Value := oldFollowWindows ? 1 : 0
    V016ReadabilityState := readability.Value
    V016FollowWindowsState := followWindows.Value
    if settings.HasOwnProp("ReadabilityControl")
        UpdateV016ReadabilityLabel(settings.ReadabilityControl, V016ReadabilityState)
    ; Preview may have moved/rescaled the launcher; return Settings relative
    ; to that CURRENT location, not its pre-preview desktop coordinates.
    PositionOwnedMenuAtParent(settings, LauncherGui)
    settings.Show()
    ; Settings is modal again once the preview has been rejected/restored.
    DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 0)
    if saveFailed
    {
        settings.Opt("+OwnDialogs")
        MsgBox("Could not apply the display settings. Your saved preferences are still available.",
            "tes3np — Display Settings", "Icon!")
    }
}

RefreshLauncherDisplay(message, settings)
{
    global LauncherGui
    launcherHwnd := LauncherGui.Hwnd
    ; Read the real bounds even if Windows has already minimized the owner.
    if DllCall("IsIconic", "Ptr", launcherHwnd, "Int")
        DllCall("ShowWindow", "Ptr", launcherHwnd, "Int", 9) ; SW_RESTORE
    bounds := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", launcherHwnd, "Ptr", bounds, "Int")
        throw OSError()
    x := NumGet(bounds, 0, "Int"), y := NumGet(bounds, 4, "Int")
    width := NumGet(bounds, 8, "Int") - x, height := NumGet(bounds, 12, "Int") - y
    ; Capture the UNION of current and destination launcher bounds from the
    ; screen before showing any cover or progress card. A real bitmap of the
    ; whole region preserves the actual desktop around a 50%-sized launcher;
    ; the prior extension filled that region with an objectionable black matte.
    ; Fall back to the existing live progress loader if capture fails.
    loading := CaptureInterfaceFrame(LauncherGui, true, GetLauncherPlacement())
    hasDisplayFrame := IsObject(loading) && IsObject(loading.Gui)
    if !hasDisplayFrame
        loading := CreateLoadingCard(LauncherGui, x, y, width, height, message)
    LogLauncherEvent(hasDisplayFrame ? "UI | Display refresh stable frame captured."
        : "UI | Display refresh frame capture unavailable; live loading fallback.")
    try
    {
        if hasDisplayFrame && loading.Expanded
            LogLauncherEvent("UI | Display refresh union screenshot captured for scale transition.")
        ; Paint the loading card, then return foreground to the launcher before
        ; hiding its active owned Settings window. It must be enabled to take focus.
        SetLoadingCardProgress(loading.Panel, message, 0.15)
        DllCall("EnableWindow", "Ptr", launcherHwnd, "Int", 1)
        if !DllCall("IsWindowVisible", "Ptr", launcherHwnd, "Int")
            DllCall("ShowWindow", "Ptr", launcherHwnd, "Int", 4) ; SW_SHOWNOACTIVATE
        WinActivate("ahk_id " launcherHwnd)
        settings.Hide()
        ; WM_SETREDRAW would temporarily remove the visible window style.
        ; The live loading card already covers this repaint.
        ApplyLauncherScaleToWindow(false)
        if !DllCall("GetWindowRect", "Ptr", launcherHwnd, "Ptr", bounds, "Int")
            throw OSError()
        x := NumGet(bounds, 0, "Int"), y := NumGet(bounds, 4, "Int")
        width := NumGet(bounds, 8, "Int") - x, height := NumGet(bounds, 12, "Int") - y
        ; The union screenshot stays at its original screen position, while the
        ; loading card stays centered on the old launcher. Only the fallback
        ; (which has no snapshot) tracks the resized live launcher.
        if !hasDisplayFrame
        {
            DllCall("SetWindowPos", "Ptr", loading.Dim.Hwnd, "Ptr", 0,
                "Int", x, "Int", y, "Int", width, "Int", height, "UInt", 0x0014)
            PositionOwnedMenuAtParent(loading.Card, LauncherGui)
        }
        SetLoadingCardProgress(loading.Panel, "Updating interface text...", 0.55)
        ApplyAccessibilityTextSize(false)
        SetLoadingCardProgress(loading.Panel, "Updating readability...", 0.85)
        ApplyEnhancedReadability()
        DllCall("RedrawWindow", "Ptr", launcherHwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0181)
        ; The final all-children redraw occurs AFTER the earlier GDI button
        ; blits in the scale/text helpers. Repaint those custom faces once more
        ; before the captured frame is taken away.
        RepaintMenuButtons()
    }
    finally
    {
        if hasDisplayFrame
        {
            ; The original cleanup destroyed the dim/progress FIRST, exposing
            ; an undimmed stale screenshot for a compositor frame. Hide the
            ; capture (and its owned loading windows) as one presentation step;
            ; release HWNDs and the detached bitmap only AFTER that hide.
            try loading.Gui.Hide()
            finally ReleaseCapturedInterfaceFrame(loading)
        }
        else
            DestroyLoadingCard(loading)
    }
}

SaveLauncherDisplaySettings(scale, textSize, readability, reduceMotion, followWindows)
{
    global DataFile
    temporary := DataFile ".display-" NewLauncherFileId() ".tmp"
    previousCritical := Critical("On")
    try
    {
        DirCreate(AppDataDirectory)
        if FileExist(DataFile)
            FileCopy(DataFile, temporary)
        IniWrite(scale, temporary, "Launcher", "Scale")
        IniWrite(textSize, temporary, "Accessibility", "TextSize")
        IniWrite(readability ? "1" : "0", temporary, "Accessibility", "EnhancedReadability")
        IniWrite(reduceMotion ? "1" : "0", temporary, "Accessibility", "ReduceMotion")
        IniWrite(followWindows ? "1" : "0", temporary, "Accessibility", "FollowWindows")
        FileMove(temporary, DataFile, true)
    }
    finally
    {
        try FileDelete(temporary)
        Critical(previousCritical)
    }
}
AccessibilityFontMultiplier(preference := unset)
{
    global AccessibilityTextSize
    if !IsSet(preference)
        preference := AccessibilityTextSize
    return preference = "Extra Large" ? 1.35 : preference = "Large" ? 1.18 : 1.0
}

AccessibilityFontSize(baseSize)
{
    return Round(baseSize * AccessibilityFontMultiplier())
}

; Use the *same* interface text multiplier for native labels, inputs, headings
; and modal copy, not only owner-drawn buttons. Preserve all other font options
; and the exact Normal size. GUI geometry and window scaling stay independent.
SetAccessibleTextFont(target, options, fontName := unset)
{
    if RegExMatch(options, "i)(^|\s)s(\d+(?:\.\d+)?)(?=\s|$)", &matched)
        options := StrReplace(options, matched[0],
            matched[1] "s" AccessibilityFontSize(matched[2] + 0))
    if IsSet(fontName)
        return target.SetFont(options, fontName)
    return target.SetFont(options)
}

ApplyLauncherButtonFont(face, scale)
{
    size := AccessibilityFontSize(10)
    if face.HasOwnProp("BaseWidth") && face.BaseWidth < 180
        size := Min(size, 11)
    face.Control.SetFont("s" Max(5, Round(size * scale)) " Bold", "Segoe UI")
}

ApplyAccessibilityTextSize(suspendRedraw := true)
{
    global LauncherGui, ButtonFaces, LauncherScale, LauncherHeading, LauncherMorrowindFont
    if !IsObject(LauncherGui)
        return
    ; Font changes must NEVER restore native hit targets to their 100% base
    ; positions. ApplyLauncherControlScale already moves every captured control
    ; from its immutable baseline, including at 50/60/70/80/90 percent.
    scale := LauncherScale / 100
    suspendRedraw := suspendRedraw && DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
    if suspendRedraw
        DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
    try
    {
        for handle, face in ButtonFaces
        {
            if !DllCall("IsWindow", "Ptr", handle) || face.Window != LauncherGui.Hwnd
                continue
            if face.HasOwnProp("IsInfo")
                face.Control.SetFont("s" Max(5, Round(AccessibilityFontSize(10) * scale))
                    " Norm", "Palatino Linotype")
            else if !face.HasOwnProp("IsLabel")
                ApplyLauncherButtonFont(face, scale)
        }
        ; The main heading and footer are native Text controls, not buttons.
        ; Font changes should never reset their already-scaled positions.
        if IsObject(LauncherHeading)
            LauncherHeading.SetFont("s" Max(1, Round(AccessibilityFontSize(19) * scale))
                " Norm c241408", LauncherMorrowindFont)
        ScaleLauncherVersionLabel(scale)
    }
    finally
        if suspendRedraw
            DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0085 | 0x0100 | 0x0001 | 0x0004)
    RepaintMenuButtons()
}
ApplyEnhancedReadability()
{
    global LauncherGui, ButtonFaces, EnhancedReadability
    if !IsObject(LauncherGui)
        return
    for handle, face in ButtonFaces
    {
        if !DllCall("IsWindow", "Ptr", handle) || face.HasOwnProp("IsLabel") || face.Window != LauncherGui.Hwnd
            continue
        if EnhancedReadability
            face.TextColor := 0xFFFFFF
        else if face.HasOwnProp("TextColor")
            face.DeleteProp("TextColor")
    }
    DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0085 | 0x0100 | 0x0001 | 0x0004)
    RepaintMenuButtons()
}
MonitorFromPoint(x, y)
{
    count := MonitorGetCount()
    Loop count
    {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        if x >= left && x < right && y >= top && y < bottom
            return A_Index
    }
    return MonitorGetPrimary()
}
