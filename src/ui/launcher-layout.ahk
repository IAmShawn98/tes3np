; Capture the main window's control layout, then scale and present it.

global LauncherBaseWidth := 960
global LauncherBaseHeight := 716
global LauncherControlLayout := Map()
global LauncherCachedScale := 0
global LauncherCachedLayoutCount := 0

CaptureLauncherControlLayout()
{
    global LauncherGui, LauncherControlLayout
    LauncherControlLayout := Map()
    for control in LauncherGui
    {
        try
        {
            control.GetPos(&x, &y, &width, &height)
            LauncherControlLayout[control.Hwnd] := {Control: control, X: x, Y: y, Width: width, Height: height}
        }
    }
}

ApplyLauncherControlScale(suspendRedraw := true)
{
    global LauncherGui, LauncherScale, LauncherControlLayout, ButtonFaces, LauncherHeading, LauncherMorrowindFont
    if !IsObject(LauncherGui) || LauncherControlLayout.Count = 0
        return
    scale := LauncherScale / 100
    if suspendRedraw
        DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
    try
    {
        for hwnd, item in LauncherControlLayout
        {
            if !DllCall("IsWindow", "Ptr", hwnd)
                continue
            item.Control.Move(Round(item.X * scale), Round(item.Y * scale), Round(item.Width * scale), Round(item.Height * scale))
        }
        for hwnd, face in ButtonFaces
        {
            if !DllCall("IsWindow", "Ptr", hwnd) || face.Window != LauncherGui.Hwnd
                continue
            if face.HasOwnProp("IsInfo")
                face.Control.SetFont("s" Max(5, Round(10 * scale)) " Norm", "Palatino Linotype")
            else if !face.HasOwnProp("IsLabel")
                face.Control.SetFont("s" Max(5, Round(AccessibilityFontSize(10) * scale)) " Bold", "Segoe UI")
        }
        if IsObject(LauncherHeading)
            LauncherHeading.SetFont("s" Round(19 * scale) " Norm c241408", LauncherMorrowindFont)
        ScaleLauncherServerUpdates(scale)
        ScaleLauncherVersionLabel(scale)
    }
    finally
        if suspendRedraw
            DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0085 | 0x0100 | 0x0001 | 0x0004)
    RepaintMenuButtons()
}

ShowLauncherWindow(reuseCached := false, *)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, LauncherControlLayout, LauncherCachedScale, LauncherCachedLayoutCount
    ; The Character Book can close immediately when its parent is already painted at the requested scale.
    if reuseCached && LauncherCachedScale > 0
        && DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        && LauncherControlLayout.Count = LauncherCachedLayoutCount
    {
        desiredCachedScale := LauncherScaleMode = "Auto" ? GetAutomaticLauncherScale() : LauncherScale
        if desiredCachedScale = LauncherCachedScale
            return
    }
    ; Validate control positions before showing a cached layout.
    if LauncherCachedScale > 0 && DllCall("IsWindow", "Ptr", LauncherGui.Hwnd)
        && LauncherControlLayout.Count = LauncherCachedLayoutCount
    {
        desiredScale := LauncherScaleMode = "Auto" ? GetAutomaticLauncherScale() : LauncherScale
        if desiredScale = LauncherCachedScale
        {
            healthy := true
            for hwnd, item in LauncherControlLayout
            {
                if !DllCall("IsWindow", "Ptr", hwnd)
                {
                    healthy := false
                    break
                }
                item.Control.GetPos(&x, &y, &w, &h)
                ratio := desiredScale / 100
                if Abs(x - Round(item.X * ratio)) > 2 || Abs(y - Round(item.Y * ratio)) > 2
                    || Abs(w - Round(item.Width * ratio)) > 2 || Abs(h - Round(item.Height * ratio)) > 2
                {
                    healthy := false
                    break
                }
            }
            if healthy
            {
                LauncherGui.Show()
                RepaintMenuButtons()
                return
            }
            LogLauncherEvent("UI | Cached launcher geometry invalid; rebuilding launcher controls.")
        }
    }
    ; Apply the saved scale before first paint to avoid flashing the default window size.
    if !LauncherCachedScale
    {
        LauncherGui.Show("Hide w960 h716")
        ApplyLauncherScaleToWindow()
        LauncherCachedScale := LauncherScale
        LauncherCachedLayoutCount := LauncherControlLayout.Count
        LauncherGui.Show()
        RepaintMenuButtons()
        return
    }
    ; Stage the existing window while changing its bounds. A screenshot of the
    ; old size can expose a second copy when the new window grows behind it.
    LauncherGui.Show()
    cloaked := SetPageCompositorCloak(LauncherGui, true)
    try ApplyLauncherScaleToWindow()
    finally
        if cloaked
            RevealPaintedPage(LauncherGui)
}

GetAutomaticLauncherScale()
{
    global LauncherBaseWidth, LauncherBaseHeight
    MouseGetPos(&mouseX, &mouseY)
    monitor := MonitorFromPoint(mouseX, mouseY)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    dpiFactor := A_ScreenDPI / 96
    requiredWidth := LauncherBaseWidth * dpiFactor, requiredHeight := LauncherBaseHeight * dpiFactor
    fit := Min(1.0, (right - left) / requiredWidth, (bottom - top) / requiredHeight)
    if fit < 1
        fit := Max(0.5, fit * 0.96)
    percent := Floor((fit * 100) / 10) * 10
    return Max(50, Min(100, percent))
}

ApplyLauncherScaleToWindow(suspendRedraw := true)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, LauncherBaseWidth, LauncherBaseHeight
    global LauncherCachedScale, LauncherCachedLayoutCount, LauncherControlLayout

    if LauncherScaleMode = "Auto"
        LauncherScale := GetAutomaticLauncherScale()

    ; Resize the window and its controls together so artwork and hit targets stay aligned.
    dpiFactor := A_ScreenDPI / 96
    scale := LauncherScale / 100
    width := Round(LauncherBaseWidth * dpiFactor * scale)
    height := Round(LauncherBaseHeight * dpiFactor * scale)
    MouseGetPos(&mouseX, &mouseY)
    monitor := MonitorFromPoint(mouseX, mouseY)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    x := left + Max(0, ((right - left) - width) // 2)
    y := top + Max(0, ((bottom - top) - height) // 2)
    if !DllCall("SetWindowPos", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Int", x, "Int", y, "Int", width, "Int", height, "UInt", 0x0004 | 0x0010, "Int")
        throw OSError()
    ApplyLauncherControlScale(suspendRedraw)

    ; Refresh the cache for settings previews and rollbacks.
    LauncherCachedScale := LauncherScale
    LauncherCachedLayoutCount := LauncherControlLayout.Count
}
