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
    global DragStrip, LauncherServerStatus
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
                face.Control.SetFont("s" Max(5, Round(AccessibilityFontSize(10) * scale))
                    " Norm", "Palatino Linotype")
            else if !face.HasOwnProp("IsLabel")
                ApplyLauncherButtonFont(face, scale)
        }
        if IsObject(LauncherHeading)
            LauncherHeading.SetFont("s" Max(1, Round(AccessibilityFontSize(19) * scale))
                " Norm c241408", LauncherMorrowindFont)
        if IsObject(DragStrip)
            DragStrip.SetFont("s" Max(5, Round(AccessibilityFontSize(14) * scale))
                " Bold c" LauncherServerStatusColor(LauncherServerStatus), "Segoe UI")
        ReflowLauncherAccessibleEdgeControls(scale)
        ScaleLauncherVersionLabel(scale)
    }
    finally
        if suspendRedraw
            DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0085 | 0x0100 | 0x0001 | 0x0004)
    RepaintMenuButtons()
}

ReflowLauncherAccessibleEdgeControls(scale)
{
    global LauncherGui, LauncherControlLayout, ButtonFaces, AccessibilityTextSize
    global LauncherExpansionToggle, LauncherChatToggle, DragStrip
    if !IsObject(LauncherGui) || !LauncherControlLayout.Count
        return
    for control in [LauncherExpansionToggle, LauncherChatToggle, DragStrip]
        if !IsObject(control) || !LauncherControlLayout.Has(control.Hwnd)
            return
    LauncherGui.AccessibleEdgeRects := Map()
    expansion := LauncherControlLayout[LauncherExpansionToggle.Hwnd]
    tab := LauncherControlLayout[LauncherChatToggle.Hwnd]
    drag := LauncherControlLayout[DragStrip.Hwnd]
    ew := Round(expansion.Width * scale), eh := Round(expansion.Height * scale)
    tw := Round(tab.Width * scale), th := Round(tab.Height * scale)
    dx := Round(drag.X * scale), dw := Round(drag.Width * scale)
    ty := Round(tab.Y * scale)
    if AccessibilityTextSize != "Normal"
    {
        ; Measure every state so toggling never shifts the drag region.
        for caption in ["Expansion Pack: Enabled", "Expansion Pack: Disabled", "Expansion Pack: Unverified"]
        {
            extent := MeasureAccessibleSingleLineText(LauncherExpansionToggle, caption)
            ew := Max(ew, extent.Width + Max(8, Round(16 * scale)))
            eh := Max(eh, extent.Height + Max(4, Round(6 * scale)))
        }
        dx := Max(dx, ew + Round(15 * scale))
        dw := Max(1, Round((drag.X + drag.Width) * scale) - dx)
        metrics := MeasureLauncherChatCaption(LauncherChatToggle, scale)
        dpi := A_ScreenDPI / 96
        tw := Max(tw, Ceil(metrics.RequiredWidth / dpi))
        th := Max(th, Ceil(metrics.RequiredHeight / dpi))
        ty := Round((tab.Y + tab.Height / 2) * scale - th / 2)
    }
    for entry in [{Control: LauncherExpansionToggle, X: 0, Y: 0, W: ew, H: eh},
        {Control: LauncherChatToggle, X: 0, Y: ty, W: tw, H: th},
        {Control: DragStrip, X: dx, Y: Round(drag.Y * scale), W: dw, H: Round(drag.Height * scale)}]
    {
        entry.Control.GetPos(&x, &y, &w, &h)
        if x != entry.X || y != entry.Y || w != entry.W || h != entry.H
            entry.Control.Move(entry.X, entry.Y, entry.W, entry.H)
        LauncherGui.AccessibleEdgeRects[entry.Control.Hwnd] := entry
    }
    ButtonFaces[LauncherExpansionToggle.Hwnd].NoAccessibleDownfit := AccessibilityTextSize != "Normal"
    ; The backdrop slice expects base design units.
    ButtonFaces[LauncherChatToggle.Hwnd].Y := AccessibilityTextSize = "Normal" ? tab.Y : ty / scale
}

; Prepare the exact final-size native face bitmaps before the first Show.
; The scratch surface is private GDI memory, never a capture of the desktop.
; A hidden owner cannot be prepared through PaintButtonNow, which skips
; invisible controls. Keep the existing paint path for the actual window.
PrepareInitialLauncherFaces()
{
    global LauncherGui, ButtonFaces
    if DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        return false
    handles := [], width := 0, height := 0
    rect := Buffer(16, 0)
    for handle, face in ButtonFaces
    {
        if !DllCall("IsWindow", "Ptr", handle) || !LauncherFaceCacheEligible(face)
            continue
        if !DllCall("GetClientRect", "Ptr", handle, "Ptr", rect)
            continue
        w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
        if w <= 0 || h <= 0
            continue
        handles.Push(handle)
        width := Max(width, w), height := Max(height, h)
    }
    if !handles.Length
        return true
    screen := DllCall("GetDC", "Ptr", 0, "Ptr")
    dc := 0, bitmap := 0, oldBitmap := 0
    if !screen
        return false
    try
    {
        dc := DllCall("gdi32\CreateCompatibleDC", "Ptr", screen, "Ptr")
        bitmap := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", screen,
            "Int", width, "Int", height, "Ptr")
        if !dc || !bitmap
            return false
        oldBitmap := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
        if !oldBitmap || oldBitmap = -1
            return false
        for handle in handles
            if DllCall("IsWindow", "Ptr", handle) && ButtonFaces.Has(handle)
                PaintButtonToDC(handle, dc)
        return true
    }
    finally
    {
        if oldBitmap && oldBitmap != -1
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldBitmap)
        if dc
            DllCall("gdi32\DeleteDC", "Ptr", dc)
        if bitmap
            DllCall("gdi32\DeleteObject", "Ptr", bitmap)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", screen)
    }
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
            expectedX := Round(item.X * ratio), expectedY := Round(item.Y * ratio)
            expectedHeight := Round(item.Height * ratio)
            if LauncherGui.HasOwnProp("AccessibleEdgeRects") && LauncherGui.AccessibleEdgeRects.Has(hwnd)
            {
                edge := LauncherGui.AccessibleEdgeRects[hwnd]
                expectedX := edge.X, expectedY := edge.Y, expectedWidth := edge.W, expectedHeight := edge.H
            }
            ; Unlike the snapshot, the version Text control may grow after
            ; applying the minimum font size. Validate that measured width
            ; rather than mistaking a legitimate fit for stale geometry.
            if IsObject(LauncherVersionLabel) && hwnd = LauncherVersionLabel.Hwnd
            {
                rect := GetLauncherVersionLabelRect(item.Control, ratio, expectedWidth)
                expectedWidth := rect.W, expectedY := rect.Y, expectedHeight := rect.H
            }
            if Abs(x - expectedX) > 2 || Abs(y - expectedY) > 2
                || Abs(w - expectedWidth) > 2 || Abs(h - expectedHeight) > 2
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
        PrepareInitialLauncherFaces()
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
