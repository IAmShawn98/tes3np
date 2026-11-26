; First-stage public wiki map shell. No browser, authentication, or network
; requests until the owner supplies and approves the actual map URL.
global LauncherMapToggle := 0
global LauncherMapPanel := 0
global LauncherMapOpen := false

CreateLauncherMapToggle()
{
    global LauncherGui, LauncherMapToggle, ButtonFaces
    LauncherMapToggle := AddStyledButton(LauncherGui, 915, 294, 45, 112, "Map", ToggleLauncherMap)
    ButtonFaces[LauncherMapToggle.Hwnd].IsChatTab := true
    ButtonFaces[LauncherMapToggle.Hwnd].IsMapTab := true
}

LauncherSideTabDirection(isOpen, mirrored := false)
{
    return (isOpen ? -1 : 1) * (mirrored ? -1 : 1)
}

ToggleLauncherMap(*)
{
    global LauncherMapOpen
    SetLauncherMapOpen(!LauncherMapOpen)
}

SetLauncherMapOpen(open)
{
    global LauncherMapOpen, LauncherMapPanel, LauncherMapToggle, LauncherGui
    if open && !IsObject(LauncherMapPanel)
        LauncherMapPanel := CreateLauncherMapPanel(LauncherGui)
    LauncherMapOpen := !!open
    if LauncherMapOpen
    {
        try
        {
            SyncLauncherMapPanel()
            SetTimer(SyncLauncherMapPanel, 150)
        }
        catch
        {
            DisposeLauncherMapPanel()
            throw
        }
    }
    else
    {
        SetTimer(SyncLauncherMapPanel, 0)
        if IsObject(LauncherMapPanel)
            LauncherMapPanel.Hide()
    }
    if IsObject(LauncherMapToggle)
        DllCall("InvalidateRect", "Ptr", LauncherMapToggle.Hwnd, "Ptr", 0, "Int", 0)
}

CreateLauncherMapPanel(owner)
{
    panel := Gui("-Caption -Border -DPIScale +ToolWindow +Owner" owner.Hwnd, "Drak's Server Map")
    panel.MarginX := 0, panel.MarginY := 0
    panel.BackColor := "A68B50"
    panel.MapTexture := A_ScriptDir "\assets\controls\map-frame.png"
    try
    {
        panel.MapFrame := []
        Loop 5
            panel.MapFrame.Push(panel.Add("Picture", "x0 y0 w1 h1", panel.MapTexture))
        panel.MapTitle := panel.Add("Text", "x0 y0 w1 h1 Center +0x200 Background10100D cE1BD79", "Drak's Server Map")
        panel.MapViewport := panel.Add("Text", "x0 y0 w1 h1 Background132725", "")
        panel.MapSizeKey := ""
        panel.OnEvent("Close", (*) => SetLauncherMapOpen(false))
        panel.OnEvent("Escape", (*) => SetLauncherMapOpen(false))
        return panel
    }
    catch
    {
        panel.Destroy()
        throw
    }
}

; Work in physical screen pixels, preserving the reference map aspect ratio.
; Prefer a right-side pullout. If it won't fit, overlay the launcher instead,
; leaving its right-edge Map toggle reachable for closing.
GetLauncherMapPlacement(owner, work, tabWidth)
{
    scale := Max(0.01, (owner.R - owner.L) / 960)
    gap := Max(1, Round(4 * scale))
    availableRight := work.R - owner.R - gap
    availableInside := owner.R - tabWidth - gap - work.L
    outside := availableRight >= Round(480 * scale)
    widthLimit := outside ? availableRight : availableInside
    fit := Min(scale, Max(1, widthLimit) / 480, Max(1, work.B - work.T) / 405)
    w := Max(1, Floor(480 * fit)), h := Max(1, Floor(405 * fit))
    x := outside ? owner.R + gap : owner.R - tabWidth - gap - w
    x := Max(work.L, Min(work.R - w, x))
    y := Max(work.T, Min(work.B - h, Round((owner.T + owner.B - h) / 2)))
    return {X: x, Y: y, W: w, H: h, Outside: outside}
}

LayoutLauncherMapPanel(panel, w, h)
{
    global AccessibilityTextSize
    key := w "|" h "|" AccessibilityTextSize "|" A_ScreenDPI
    if panel.MapSizeKey = key
        return
    scale := Min(w / 480, h / 405)
    rim := Max(2, Round(7 * scale))
    header := Max(8, Round(34 * scale))
    innerW := Max(1, w - 2 * rim)
    pad := Max(2, Round(6 * scale))
    titleSize := Max(5, Round(AccessibilityFontSize(16) * scale * 96 / A_ScreenDPI))
    loop
    {
        panel.MapTitle.SetFont("s" titleSize " Bold cE1BD79", LauncherThemeFont())
        extent := MeasureAccessibleSingleLineText(panel.MapTitle, panel.MapTitle.Text)
        if extent.Width + 2 * pad <= innerW || titleSize <= 5
            break
        titleSize -= 1
    }
    header := Min(Max(1, h - 2 * rim - 1), Max(header, extent.Height + 2 * pad))
    titleW := Min(innerW, Max(Round(w * 0.78), extent.Width + 2 * pad))
    rects := [
        [0, 0, w, rim], [0, h - rim, w, rim],
        [0, rim, rim, Max(1, h - 2 * rim)], [w - rim, rim, rim, Max(1, h - 2 * rim)],
        [rim, rim, Max(1, w - 2 * rim), header]]
    for index, rect in rects
    {
        picture := panel.MapFrame[index]
        picture.Value := "*w" rect[3] " *h" rect[4] " " panel.MapTexture
        picture.Move(rect[1], rect[2], rect[3], rect[4])
    }
    panel.MapTitle.Move(Round((w - titleW) / 2), rim, titleW, header)
    panel.MapViewport.Move(rim, rim + header, Max(1, w - 2 * rim), Max(1, h - 2 * rim - header))
    panel.MapSizeKey := key
}

SyncLauncherMapPanel(*)
{
    global LauncherGui, LauncherMapPanel, LauncherMapOpen, LauncherMapToggle
    if !LauncherMapOpen || !IsObject(LauncherMapPanel) || !IsObject(LauncherGui)
        return
    if !DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd) || DllCall("IsIconic", "Ptr", LauncherGui.Hwnd)
        || !DllCall("IsWindowEnabled", "Ptr", LauncherGui.Hwnd)
    {
        LauncherMapPanel.Hide()
        return
    }
    bounds := Buffer(16, 0), tab := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", LauncherGui.Hwnd, "Ptr", bounds)
        || !IsObject(LauncherMapToggle) || !DllCall("GetWindowRect", "Ptr", LauncherMapToggle.Hwnd, "Ptr", tab)
        return
    owner := {L: NumGet(bounds, 0, "Int"), T: NumGet(bounds, 4, "Int"),
        R: NumGet(bounds, 8, "Int"), B: NumGet(bounds, 12, "Int")}
    monitor := MonitorFromPoint((owner.L + owner.R) // 2, (owner.T + owner.B) // 2)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    placement := GetLauncherMapPlacement(owner, {L: left, T: top, R: right, B: bottom},
        NumGet(tab, 8, "Int") - NumGet(tab, 0, "Int"))
    LayoutLauncherMapPanel(LauncherMapPanel, placement.W, placement.H)
    if !DllCall("IsWindowVisible", "Ptr", LauncherMapPanel.Hwnd)
        LauncherMapPanel.Show("NA x" placement.X " y" placement.Y " w" placement.W " h" placement.H)
    else
    {
        current := Buffer(16, 0)
        if DllCall("GetWindowRect", "Ptr", LauncherMapPanel.Hwnd, "Ptr", current)
            && (NumGet(current, 0, "Int") != placement.X || NumGet(current, 4, "Int") != placement.Y
                || NumGet(current, 8, "Int") - NumGet(current, 0, "Int") != placement.W
                || NumGet(current, 12, "Int") - NumGet(current, 4, "Int") != placement.H)
            DllCall("SetWindowPos", "Ptr", LauncherMapPanel.Hwnd, "Ptr", 0,
                "Int", placement.X, "Int", placement.Y, "Int", placement.W, "Int", placement.H, "UInt", 0x14)
    }
}

DisposeLauncherMapPanel()
{
    global LauncherMapPanel, LauncherMapOpen
    SetTimer(SyncLauncherMapPanel, 0)
    LauncherMapOpen := false
    if IsObject(LauncherMapPanel)
        LauncherMapPanel.Destroy()
    LauncherMapPanel := 0
}
