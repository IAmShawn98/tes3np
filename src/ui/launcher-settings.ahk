; Launcher-specific display and accessibility settings.
; Auto mode is the default: keep the launcher at 100% whenever it fits and only
; reduce it when the monitor's usable work area requires it.

global LauncherScale := 100
global LauncherScaleMode := "Auto"
global LauncherBaseWidth := 960
global LauncherBaseHeight := 716
global AccessibilityTextSize := "Normal"
global EnhancedReadability := false
global ReduceMotion := false

LoadLauncherScale()
{
    global DataFile, LauncherScale, LauncherScaleMode, AccessibilityTextSize, EnhancedReadability, ReduceMotion
    saved := IniRead(DataFile, "Launcher", "Scale", "Auto")
    AccessibilityTextSize := IniRead(DataFile, "Accessibility", "TextSize", "Normal")
    EnhancedReadability := IniRead(DataFile, "Accessibility", "EnhancedReadability", "0") = "1"
    ReduceMotion := IniRead(DataFile, "Accessibility", "ReduceMotion", "0") = "1"
    if !RegExMatch(AccessibilityTextSize, "^(Normal|Large|Extra Large)$")
        AccessibilityTextSize := "Normal"
    if saved = "Auto" || saved = ""
    {
        LauncherScaleMode := "Auto"
        LauncherScale := GetAutomaticLauncherScale()
        return
    }
    LauncherScaleMode := "Manual"
    LauncherScale := RegExMatch(saved, "^(?:50|60|70|80|90|100)$") ? Integer(saved) : GetAutomaticLauncherScale()
}

OpenLauncherSettings(*)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, AccessibilityTextSize, EnhancedReadability, ReduceMotion
    settings := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — Launcher Settings")
    settings.BackColor := EnhancedReadability ? "F4E4BE" : "E2CEA2"
    settings.SetFont("s11 Bold c241408", "Segoe UI")
    settings.Add("Text", "x20 y18 w330 h26", "Display & Accessibility")
    settings.SetFont("s9 c382314", "Segoe UI")
    settings.Add("Text", "x20 y48 w330 h44", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")
    settings.SetFont("s9 Bold c382314", "Segoe UI")
    settings.Add("Text", "x20 y100 w120 h22", "Launcher size")
    settings.SetFont("s10 c382314", "Segoe UI")
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x145 y96 w205 Choose" choice, choices)

    settings.SetFont("s9 Bold c382314", "Segoe UI")
    settings.Add("Text", "x20 y142 w120 h22", "Interface text")
    settings.SetFont("s10 c382314", "Segoe UI")
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x145 y138 w205 Choose" textChoice, textChoices)

    settings.SetFont("s9 Bold c382314", "Segoe UI")
    readability := settings.Add("CheckBox", "x20 y178 w330 h24", "Enhanced readability")
    readability.Value := EnhancedReadability ? 1 : 0
    settings.SetFont("s8 c5A4027", "Segoe UI")
    settings.Add("Text", "x38 y202 w312 h38", "Uses stronger contrast and brighter button text while keeping the Morrowind artwork intact.")

    settings.SetFont("s9 Bold c382314", "Segoe UI")
    reduceMotionBox := settings.Add("CheckBox", "x20 y246 w330 h24", "Reduce motion")
    reduceMotionBox.Value := ReduceMotion ? 1 : 0
    settings.SetFont("s8 c5A4027", "Segoe UI")
    settings.Add("Text", "x38 y270 w312 h38", "Reduces nonessential animated feedback and keeps interface changes as immediate and still as possible.")

    apply := settings.Add("Button", "x20 y318 w158 h34 Default", "Preview & Apply")
    cancel := settings.Add("Button", "x192 y318 w158 h34", "Cancel")
    apply.OnEvent("Click", PreviewLauncherSettings.Bind(settings, scaleList, textList, readability, reduceMotionBox))
    cancel.OnEvent("Click", (*) => settings.Destroy())
    settings.OnEvent("Escape", (*) => settings.Destroy())
    settings.Show("w370 h372")
}

ScaleChoiceIndex(scale)
{
    return Max(1, Min(6, ((scale - 50) // 10) + 1))
}

PreviewLauncherSettings(settings, scaleList, textList, readability, reduceMotionBox, *)
{
    global LauncherScale, LauncherScaleMode, AccessibilityTextSize, EnhancedReadability, ReduceMotion
    oldScale := LauncherScale
    oldMode := LauncherScaleMode
    oldText := AccessibilityTextSize
    oldReadability := EnhancedReadability
    oldReduceMotion := ReduceMotion
    if scaleList.Value = 1
    {
        LauncherScaleMode := "Auto"
        LauncherScale := GetAutomaticLauncherScale()
        pendingScale := "Auto"
    }
    else
    {
        LauncherScaleMode := "Manual"
        LauncherScale := Integer(StrReplace(scaleList.Text, "%"))
        pendingScale := LauncherScale
    }
    AccessibilityTextSize := textList.Text
    EnhancedReadability := readability.Value = 1
    ReduceMotion := reduceMotionBox.Value = 1
    settings.Hide()
    ApplyLauncherScaleToWindow(true)
    ApplyAccessibilityTextSize()
    ApplyEnhancedReadability()
    result := MsgBox("Do these display settings look good?`n`nChoose Yes to keep them. Choose No to return to your previous settings.", "tes3np — Confirm Display Settings", "YesNo Icon?")
    if result = "Yes"
    {
        SaveLauncherScale(pendingScale)
        SaveAccessibilityTextSize(AccessibilityTextSize)
        SaveEnhancedReadability(EnhancedReadability)
        SaveReduceMotion(ReduceMotion)
        settings.Destroy()
        return
    }
    LauncherScale := oldScale
    LauncherScaleMode := oldMode
    AccessibilityTextSize := oldText
    EnhancedReadability := oldReadability
    ReduceMotion := oldReduceMotion
    ApplyLauncherScaleToWindow(true)
    ApplyAccessibilityTextSize()
    ApplyEnhancedReadability()
    settings.Show()
}

SaveLauncherScale(value)
{
    global DataFile
    DirCreate(AppDataDirectory)
    IniWrite(value, DataFile, "Launcher", "Scale")
}

SaveAccessibilityTextSize(value)
{
    global DataFile
    DirCreate(AppDataDirectory)
    IniWrite(value, DataFile, "Accessibility", "TextSize")
}

SaveEnhancedReadability(value)
{
    global DataFile
    DirCreate(AppDataDirectory)
    IniWrite(value ? "1" : "0", DataFile, "Accessibility", "EnhancedReadability")
}

SaveReduceMotion(value)
{
    global DataFile
    DirCreate(AppDataDirectory)
    IniWrite(value ? "1" : "0", DataFile, "Accessibility", "ReduceMotion")
}

AccessibilityFontSize(baseSize)
{
    global AccessibilityTextSize
    multiplier := AccessibilityTextSize = "Extra Large" ? 1.35 : AccessibilityTextSize = "Large" ? 1.18 : 1.0
    return Round(baseSize * multiplier)
}

ApplyAccessibilityTextSize()
{
    global LauncherGui, ButtonFaces
    if !IsObject(LauncherGui)
        return
    DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
    try
    {
        for handle, face in ButtonFaces
        {
            if !DllCall("IsWindow", "Ptr", handle) || face.HasOwnProp("IsLabel") || face.Window != LauncherGui.Hwnd
                continue
            size := AccessibilityFontSize(10)
            if face.HasOwnProp("BaseWidth")
            {
                face.Control.Move(face.BaseX, , face.BaseWidth, face.BaseHeight)
                if face.BaseWidth < 180
                    size := Min(size, 11)
            }
            face.Control.SetFont("s" size " Bold", "Segoe UI")
        }
    }
    finally
    {
        DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    }
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

GetAutomaticLauncherScale()
{
    global LauncherBaseWidth, LauncherBaseHeight
    MouseGetPos(&mouseX, &mouseY)
    monitor := MonitorFromPoint(mouseX, mouseY)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    dpiFactor := A_ScreenDPI / 96
    requiredWidth := LauncherBaseWidth * dpiFactor
    requiredHeight := LauncherBaseHeight * dpiFactor
    fit := Min(1.0, (right - left) / requiredWidth, (bottom - top) / requiredHeight)
    if fit < 1
        fit := Max(0.5, fit * 0.96)
    percent := Floor((fit * 100) / 10) * 10
    return Max(50, Min(100, percent))
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

CenterLauncherWithoutResizing()
{
    global LauncherGui
    MouseGetPos(&mouseX, &mouseY)
    monitor := MonitorFromPoint(mouseX, mouseY)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    WinGetPos(,, &width, &height, "ahk_id " LauncherGui.Hwnd)
    x := left + Max(0, ((right - left) - width) // 2)
    y := top + Max(0, ((bottom - top) - height) // 2)
    WinMove(x, y,,, "ahk_id " LauncherGui.Hwnd)
}

ApplyLauncherScaleToWindow(center := false)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, LauncherBaseWidth, LauncherBaseHeight
    if LauncherScaleMode = "Auto"
        LauncherScale := GetAutomaticLauncherScale()
    if LauncherScale = 100
    {
        LauncherGui.Show("w" LauncherBaseWidth " h" LauncherBaseHeight)
        if center
            CenterLauncherWithoutResizing()
        return
    }
    dpiFactor := A_ScreenDPI / 96
    scale := LauncherScale / 100
    width := Round(LauncherBaseWidth * dpiFactor * scale)
    height := Round(LauncherBaseHeight * dpiFactor * scale)
    MouseGetPos(&mouseX, &mouseY)
    monitor := MonitorFromPoint(mouseX, mouseY)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    x := left + Max(0, ((right - left) - width) // 2)
    y := top + Max(0, ((bottom - top) - height) // 2)
    DllCall("SetWindowPos", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Int", x, "Int", y, "Int", width, "Int", height, "UInt", 0x0004 | 0x0010)
}
