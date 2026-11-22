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
    suspendRedraw := suspendRedraw && DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
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
                ApplyLauncherButtonFont(face, scale)
        }
        if IsObject(LauncherHeading)
            LauncherHeading.SetFont("s" Max(1, Round(19 * scale)) " Norm c241408", LauncherMorrowindFont)
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
    global LauncherGui, LauncherControlLayout, LauncherCachedScale, LauncherCachedLayoutCount
    global LauncherUpdateBadge, LauncherUpdateNumber, LauncherVersionLabel
    if DllCall("IsIconic", "Ptr", LauncherGui.Hwnd)
        DllCall("ShowWindow", "Ptr", LauncherGui.Hwnd, "Int", 9) ; SW_RESTORE
    placement := GetLauncherPlacement()
    if placement.Scale = LauncherCachedScale && DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        && LauncherControlLayout.Count = LauncherCachedLayoutCount
    {
        ; The Character Book closes without repainting an already-painted launcher.
        if reuseCached
            return
        healthy := true
        ratio := placement.Scale / 100
        for hwnd, item in LauncherControlLayout
        {
            if !DllCall("IsWindow", "Ptr", hwnd)
            {
                healthy := false
                break
            }
            ; The unread circle and its numeral are anchored after the
            ; rendered label at each scale. Their position and diameter are
            ; intentionally dynamic rather than the captured base rectangle.
            if (IsObject(LauncherUpdateBadge) && hwnd = LauncherUpdateBadge.Hwnd)
                || (IsObject(LauncherUpdateNumber) && hwnd = LauncherUpdateNumber.Hwnd)
                continue
            item.Control.GetPos(&x, &y, &w, &h)
            expectedWidth := Round(item.Width * ratio)
            ; Unlike the snapshot, the version Text control may grow after
            ; applying the minimum font size. Validate that measured width
            ; rather than mistaking a legitimate fit for stale geometry.
            if IsObject(LauncherVersionLabel) && hwnd = LauncherVersionLabel.Hwnd
                try expectedWidth := Max(expectedWidth,
                    LauncherVersionLabelRequiredWidth(item.Control))
            if Abs(x - Round(item.X * ratio)) > 2 || Abs(y - Round(item.Y * ratio)) > 2
                || Abs(w - expectedWidth) > 2 || Abs(h - Round(item.Height * ratio)) > 2
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
    ; Apply the saved scale before first paint to avoid flashing the default window size.
    if !LauncherCachedScale
    {
        LauncherGui.Show("Hide w960 h716")
        ApplyLauncherScaleToWindow(true, placement)
        LauncherGui.Show()
        RepaintMenuButtons()
        return
    }
    ; Stage the existing window while changing its bounds.
    LauncherGui.Show()
    cloaked := SetPageCompositorCloak(LauncherGui, true)
    try ApplyLauncherScaleToWindow(true, placement)
    finally
        if cloaked
            RevealPaintedPage(LauncherGui)
}

GetLauncherScaleForWorkArea(workWidth, workHeight, dpiFactor, requestedScale := 0)
{
    global LauncherBaseWidth, LauncherBaseHeight
    fit := Min(1.0, workWidth / (LauncherBaseWidth * dpiFactor), workHeight / (LauncherBaseHeight * dpiFactor))
    fittedPercent := Max(1, Floor(fit * 100))
    if requestedScale
        return Min(requestedScale, fittedPercent)
    if fit >= 1 || fittedPercent < 50
        return fittedPercent
    ; Preserve Auto's ten-point presets and its padding when a preset fits.
    return Max(50, Floor(fit * 9.6) * 10)
}

GetLauncherPlacement()
{
    global LauncherGui, LauncherScaleMode, LauncherRequestedScale, LauncherBaseWidth, LauncherBaseHeight
    global LauncherCachedScale
    rect := Buffer(16, 0)
    hasPosition := LauncherCachedScale > 0 && !DllCall("IsIconic", "Ptr", LauncherGui.Hwnd)
        && DllCall("GetWindowRect", "Ptr", LauncherGui.Hwnd, "Ptr", rect)
    if hasPosition
    {
        centerX := (NumGet(rect, 0, "Int") + NumGet(rect, 8, "Int")) / 2
        centerY := (NumGet(rect, 4, "Int") + NumGet(rect, 12, "Int")) / 2
    }
    else
        MouseGetPos(&centerX, &centerY)
    monitor := MonitorFromPoint(centerX, centerY)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    if !hasPosition
        centerX := (left + right) / 2, centerY := (top + bottom) / 2
    dpiFactor := A_ScreenDPI / 96
    requested := LauncherScaleMode = "Auto" ? 0 : LauncherRequestedScale
    percent := GetLauncherScaleForWorkArea(right - left, bottom - top, dpiFactor, requested)
    width := Round(LauncherBaseWidth * dpiFactor * percent / 100)
    height := Round(LauncherBaseHeight * dpiFactor * percent / 100)
    x := Max(left, Min(right - width, Round(centerX - width / 2)))
    y := Max(top, Min(bottom - height, Round(centerY - height / 2)))
    return {Scale: percent, X: x, Y: y, Width: width, Height: height}
}

ApplyLauncherScaleToWindow(suspendRedraw := true, placement := unset)
{
    global LauncherGui, LauncherScale, LauncherCachedScale, LauncherCachedLayoutCount, LauncherControlLayout
    if !IsSet(placement)
        placement := GetLauncherPlacement()
    if !DllCall("SetWindowPos", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Int", placement.X, "Int", placement.Y,
        "Int", placement.Width, "Int", placement.Height, "UInt", 0x0004 | 0x0010, "Int")
        throw OSError()
    LauncherScale := placement.Scale
    ApplyLauncherControlScale(suspendRedraw)

    ; Refresh the cache for settings previews and rollbacks.
    LauncherCachedScale := LauncherScale
    LauncherCachedLayoutCount := LauncherControlLayout.Count
}
