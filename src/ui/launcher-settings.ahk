; Launcher-specific display and accessibility settings.
; Auto mode is the default: keep the launcher at 100% whenever it fits and only
; reduce it when the monitor's usable work area requires it.

global LauncherScale := 100
global LauncherScaleMode := "Auto"
global LauncherBaseWidth := 960
global LauncherBaseHeight := 716

LoadLauncherScale()
{
    global DataFile, LauncherScale, LauncherScaleMode
    saved := IniRead(DataFile, "Launcher", "Scale", "Auto")
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
    global LauncherGui, LauncherScale, LauncherScaleMode
    settings := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — Launcher Settings")
    settings.BackColor := "E2CEA2"
    settings.SetFont("s11 c382314", "Segoe UI")
    settings.Add("Text", "x20 y18 w330 h26", "Display & Accessibility")
    settings.SetFont("s9 c382314", "Segoe UI")
    settings.Add("Text", "x20 y48 w330 h50", "Automatic is recommended. tes3np will stay at full size when possible and shrink only when needed to fit your screen.")
    settings.SetFont("s10 c382314", "Segoe UI")
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x20 y108 w330 Choose" choice, choices)
    apply := settings.Add("Button", "x20 y154 w158 h34 Default", "Preview & Apply")
    cancel := settings.Add("Button", "x192 y154 w158 h34", "Cancel")
    apply.OnEvent("Click", PreviewLauncherScale.Bind(settings, scaleList))
    cancel.OnEvent("Click", (*) => settings.Destroy())
    settings.OnEvent("Escape", (*) => settings.Destroy())
    settings.Show("w370 h208")
}

ScaleChoiceIndex(scale)
{
    return Max(1, Min(6, ((scale - 50) // 10) + 1))
}

PreviewLauncherScale(settings, scaleList, *)
{
    global LauncherScale, LauncherScaleMode
    oldScale := LauncherScale
    oldMode := LauncherScaleMode
    if scaleList.Value = 1
    {
        LauncherScaleMode := "Auto"
        LauncherScale := GetAutomaticLauncherScale()
        pending := "Auto"
    }
    else
    {
        LauncherScaleMode := "Manual"
        LauncherScale := Integer(StrReplace(scaleList.Text, "%"))
        pending := LauncherScale
    }
    settings.Hide()
    ApplyLauncherScaleToWindow(true)
    result := MsgBox("Does this launcher size look good?`n`nChoose Yes to keep it. Choose No to return to your previous size.", "tes3np — Confirm Launcher Size", "YesNo Icon?")
    if result = "Yes"
    {
        SaveLauncherScale(pending)
        settings.Destroy()
        return
    }
    LauncherScale := oldScale
    LauncherScaleMode := oldMode
    ApplyLauncherScaleToWindow(true)
    settings.Show()
}

SaveLauncherScale(value)
{
    global DataFile
    DirCreate(AppDataDirectory)
    IniWrite(value, DataFile, "Launcher", "Scale")
}

GetAutomaticLauncherScale()
{
    global LauncherBaseWidth, LauncherBaseHeight
    MouseGetPos(&mouseX, &mouseY)
    monitor := MonitorFromPoint(mouseX, mouseY)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    ; AHK's GUI dimensions are logical pixels and Windows applies the current DPI
    ; scale when the window is shown. Compare against that real on-screen size.
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

    ; 100% must be restored through Gui.Show(), not a raw SetWindowPos size.
    ; Gui.Show uses AHK's DPI-aware logical coordinates; SetWindowPos uses physical
    ; pixels and was the reason a 100% restore clipped the right/bottom of the UI.
    if LauncherScale = 100
    {
        LauncherGui.Show("w" LauncherBaseWidth " h" LauncherBaseHeight)
        if center
            CenterLauncherWithoutResizing()
        return
    }

    ; Reduced-size preview remains intentionally temporary until the user confirms it.
    ; Account for Windows DPI when converting logical launcher dimensions to pixels.
    dpiFactor := A_ScreenDPI / 96
    scale := LauncherScale / 100
    width := Round(LauncherBaseWidth * dpiFactor * scale)
    height := Round(LauncherBaseHeight * dpiFactor * scale)
    MouseGetPos(&mouseX, &mouseY)
    monitor := MonitorFromPoint(mouseX, mouseY)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    x := left + Max(0, ((right - left) - width) // 2)
    y := top + Max(0, ((bottom - top) - height) // 2)
    DllCall("SetWindowPos", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Int", x, "Int", y,
        "Int", width, "Int", height, "UInt", 0x0004 | 0x0010)
}
