; Public map in the native launcher frame, with its own isolated browser host.
global LauncherMapToggle := 0
global LauncherMapPanel := 0
global LauncherMapOpen := false

CreateLauncherMapToggle()
{
    global LauncherGui, LauncherMapToggle, ButtonFaces
    LauncherMapToggle := AddStyledButton(LauncherGui, 915, 294, 45, 112, "Server Map", ToggleLauncherMap)
    ButtonFaces[LauncherMapToggle.Hwnd].IsChatTab := true
    ButtonFaces[LauncherMapToggle.Hwnd].IsMapTab := true
}

LauncherSideTabDirection(isOpen, isMap := false)
{
    ; Right-edge Map reverses the arrow convention; Game Chat is unchanged.
    return (isOpen ? -1 : 1) * (isMap ? -1 : 1)
}

ToggleLauncherMap(*)
{
    global LauncherMapOpen
    SetLauncherMapOpen(!LauncherMapOpen)
}

SetLauncherMapOpen(open, loadContent := true)
{
    global LauncherMapOpen, LauncherMapPanel, LauncherMapToggle, LauncherGui
    if open && !IsObject(LauncherMapPanel)
        LauncherMapPanel := CreateLauncherMapPanel(LauncherGui)
    LauncherMapOpen := !!open
    if LauncherMapOpen
    {
        try
        {
            if !SyncLauncherMapPanel(true)
            {
                SetLauncherMapOpen(false)
                MsgBox("There is not enough room to open the map to the right of the launcher. Move the launcher left or reduce its scale.", "Drak's Server Map", "Icon!")
                return
            }
            if loadContent
                StartLauncherMapBrowser(LauncherMapPanel)
            ; Follow native owner movement immediately; keep a fast watchdog for
            ; visibility, work-area, scale and missed movement notifications.
            OnMessage(0x0003, LauncherMapOwnerMoved)
            SetTimer(SyncLauncherMapPanel, 16)
        }
        catch
        {
            DisposeLauncherMapPanel()
            throw
        }
    }
    else
    {
        OnMessage(0x0003, LauncherMapOwnerMoved, 0)
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
        panel.MapFrame := panel.Add("Picture", "x0 y0 w1 h1", panel.MapTexture)
        panel.MapTitle := panel.Add("Text", "x0 y0 w1 h1 Center +0x200 Background10100D cE1BD79", "Drak's Server Map")
        ; WS_CLIPCHILDREN prevents the native backing label from painting over
        ; the separate WebView2 child. The label is also a retry target if needed.
        panel.MapViewport := panel.Add("Text", "x0 y0 w1 h1 Center +0x200 +0x100 +0x02000000 Background132725 cE1BD79", "")
        panel.MapViewport.OnEvent("Click", (*) => StartLauncherMapBrowser(panel))
        panel.MapBrowserPid := 0
        panel.MapBrowserStarted := false
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

; Always dock outside the right edge. Fit the viewport to the monitor
; without covering the launcher. An explicit open may move the owner left
; just enough to make room; normal movement never relocates the owner.
GetLauncherMapPlacement(owner, work, allowOwnerMove := false)
{
    scale := Max(0.01, (owner.R - owner.L) / 960)
    gap := Max(1, Round(4 * scale))
    desiredWidth := Max(1, Round(480 * scale))
    minWidth := Min(desiredWidth, Max(160, Round(240 * scale)))
    ownerX := owner.L
    available := work.R - owner.R - gap
    if available < minWidth && allowOwnerMove
    {
        needed := minWidth - available
        ownerX := Max(work.L, owner.L - needed)
        available += owner.L - ownerX
    }
    fit := Min(scale, available / 480, (work.B - work.T) / 405)
    w := Floor(480 * fit), h := Floor(405 * fit)
    if w < minWidth || h < 1
        return {Available: false}
    x := owner.R + ownerX - owner.L + gap
    y := Max(work.T, Min(work.B - h, Round((owner.T + owner.B - h) / 2)))
    return {Available: true, X: x, Y: y, W: w, H: h, OwnerX: ownerX}
}

; Paint at native client resolution; the source strip is a repeating texture,
; not a single image to stretch over the entire window. Match the Game Chat
; frame's tiled/rotated border, weathered header and nested bronze/gold trim.
MapFrameCheck(status)
{
    if status
        throw Error("Map frame graphics status " status)
}

MapFrameBrush(color, resources)
{
    brush := 0
    MapFrameCheck(DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &brush))
    resources.Push(brush)
    return brush
}

MapFramePen(color, width, resources)
{
    pen := 0
    MapFrameCheck(DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", width, "Int", 2, "Ptr*", &pen))
    resources.Push(pen)
    return pen
}

MapFrameFill(graphics, brush, x, y, w, h)
{
    if w > 0 && h > 0
        MapFrameCheck(DllCall("gdiplus\GdipFillRectangleI", "Ptr", graphics, "Ptr", brush,
            "Int", x, "Int", y, "Int", w, "Int", h))
}

MapFrameLine(graphics, pen, x1, y1, x2, y2)
{
    MapFrameCheck(DllCall("gdiplus\GdipDrawLineI", "Ptr", graphics, "Ptr", pen,
        "Int", x1, "Int", y1, "Int", x2, "Int", y2))
}

MapFrameNoise(&seed, limit)
{
    ; Local deterministic grain; never changes the application's RNG state.
    seed := Mod(seed * 1664525 + 1013904223, 4294967296)
    return Mod(seed >> 16, Max(1, limit))
}

RenderLauncherMapFrame(texturePath, width, height, scale, headerBottom, bodyColor := 0xFF132725)
{
    InitButtonPainter()
    bitmap := 0, graphics := 0, texture := 0, vertical := 0, handle := 0
    brushes := [], pens := []
    try
    {
        MapFrameCheck(DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", width, "Int", height,
            "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &bitmap))
        MapFrameCheck(DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bitmap, "Ptr*", &graphics))
        MapFrameCheck(DllCall("gdiplus\GdipSetPageUnit", "Ptr", graphics, "Int", 2))
        MapFrameCheck(DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF97713A))
        MapFrameCheck(DllCall("gdiplus\GdipScaleWorldTransform", "Ptr", graphics,
            "Float", scale, "Float", scale, "Int", 0))
        w := Ceil(width / scale), h := Ceil(height / scale)

        MapFrameCheck(DllCall("gdiplus\GdipLoadImageFromFile", "WStr", texturePath, "Ptr*", &texture))
        MapFrameCheck(DllCall("gdiplus\GdipCloneImage", "Ptr", texture, "Ptr*", &vertical))
        MapFrameCheck(DllCall("gdiplus\GdipImageRotateFlip", "Ptr", vertical, "Int", 1))
        horizontalBrush := 0, verticalBrush := 0
        ; WrapModeTile is zero. Preserve the 88x15 source texel proportions.
        MapFrameCheck(DllCall("gdiplus\GdipCreateTexture", "Ptr", texture, "Int", 0, "Ptr*", &horizontalBrush))
        brushes.Push(horizontalBrush)
        MapFrameCheck(DllCall("gdiplus\GdipCreateTexture", "Ptr", vertical, "Int", 0, "Ptr*", &verticalBrush))
        brushes.Push(verticalBrush)
        MapFrameFill(graphics, horizontalBrush, 0, 0, w, 13)
        MapFrameFill(graphics, horizontalBrush, 0, h - 13, w, 13)
        MapFrameFill(graphics, verticalBrush, 0, 0, 13, h)
        MapFrameFill(graphics, verticalBrush, w - 13, 0, 13, h)

        headerBase := MapFrameBrush(0xFF8F6D3C, brushes)
        darkMottle := MapFrameBrush(0xFF70532D, brushes)
        lightMottle := MapFrameBrush(0xFFB8975C, brushes)
        midMottle := MapFrameBrush(0xFFA58148, brushes)
        MapFrameFill(graphics, headerBase, 13, 13, w - 26, headerBottom - 12)
        seed := 4108
        Loop w * 10
        {
            n := A_Index - 1
            x := 13 + MapFrameNoise(&seed, w - 26)
            y := 13 + MapFrameNoise(&seed, headerBottom - 12)
            fw := 1 + MapFrameNoise(&seed, 3), fh := 1 + MapFrameNoise(&seed, 2)
            MapFrameFill(graphics, Mod(n, 5) = 0 ? lightMottle : (Mod(n, 3) = 0 ? midMottle : darkMottle),
                x, y, fw, fh)
        }
        headerGold := MapFramePen(0xFFCFA962, 1, pens)
        headerShade := MapFramePen(0xFF382714, 1, pens)
        MapFrameLine(graphics, headerGold, 13, 14, w - 14, 14)
        MapFrameLine(graphics, headerShade, 13, headerBottom - 3, w - 14, headerBottom - 3)

        bright := MapFrameBrush(0xFFD3B16E, brushes)
        dark := MapFrameBrush(0xFF392715, brushes)
        seed := 4108
        Loop w * 9
        {
            n := A_Index - 1
            x := MapFrameNoise(&seed, w), y := MapFrameNoise(&seed, h)
            if y < headerBottom + 2
                continue
            MapFrameFill(graphics, Mod(n, 3) = 0 ? bright : dark, x, y, 1 + MapFrameNoise(&seed, 3), 1)
        }
        goldPen := MapFramePen(0xFFE0BE77, 2, pens)
        darkPen := MapFramePen(0xFF2D1D0E, 3, pens)
        MapFrameCheck(DllCall("gdiplus\GdipDrawRectangleI", "Ptr", graphics, "Ptr", goldPen,
            "Int", 2, "Int", 2, "Int", w - 5, "Int", h - 5))
        MapFrameCheck(DllCall("gdiplus\GdipDrawRectangleI", "Ptr", graphics, "Ptr", darkPen,
            "Int", 8, "Int", 8, "Int", w - 17, "Int", h - 17))
        body := MapFrameBrush(bodyColor, brushes)
        MapFrameFill(graphics, body, 13, headerBottom + 1, w - 26, h - headerBottom - 14)
        MapFrameLine(graphics, goldPen, 12, headerBottom, w - 13, headerBottom)

        MapFrameCheck(DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics))
        graphics := 0
        MapFrameCheck(DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bitmap,
            "Ptr*", &handle, "UInt", bodyColor))
        return handle
    }
    finally
    {
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        for pen in pens
            DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
        for brush in brushes
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
        for image in [vertical, texture, bitmap]
            if image
                DllCall("gdiplus\GdipDisposeImage", "Ptr", image)
    }
}

LayoutLauncherMapPanel(panel, w, h)
{
    global AccessibilityTextSize
    key := w "|" h "|" AccessibilityTextSize "|" A_ScreenDPI
    if panel.MapSizeKey = key
        return
    scale := Min(w / 480, h / 405)
    rim := Max(2, Round(13 * scale)), footer := Max(2, Round(14 * scale))
    titleTop := Max(1, Round(8 * scale))
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
    headerBottom := Min(Floor((h - footer - 2) / scale),
        Max(51, Ceil((titleTop + extent.Height + 2 * pad) / scale)))
    headerPx := Round(headerBottom * scale)
    bodyTop := Min(h - footer - 1, Max(headerPx + 1, Round((headerBottom + 1) * scale)))
    titleW := Min(innerW, extent.Width + Max(2 * pad, Round(28 * scale)))

    frame := RenderLauncherMapFrame(panel.MapTexture, w, h, scale, headerBottom)
    ; The Picture receives its own bitmap copy, so we can release our handle
    ; immediately. No disk cache, paint subclass or stretched strip controls.
    try panel.MapFrame.Value := "*w0 *h0 HBITMAP:*" frame
    finally DllCall("gdi32\DeleteObject", "Ptr", frame)
    panel.MapFrame.Move(0, 0, w, h)
    panel.MapTitle.Move(Round((w - titleW) / 2), titleTop, titleW, Max(1, headerPx - titleTop))
    panel.MapViewport.SetFont("s" Max(5, Round(AccessibilityFontSize(12) * scale * 96 / A_ScreenDPI)) " cE1BD79", LauncherThemeFont())
    panel.MapViewport.Move(rim, bodyTop, innerW, Max(1, h - footer - bodyTop))
    panel.MapSizeKey := key
}

LauncherMapOwnerMoved(wParam, lParam, msg, hwnd)
{
    global LauncherGui, LauncherMapOpen
    ; WM_MOVE also arrives for the map and other windows. Only the launcher
    ; drives docking; do not intercept the native message or change activation.
    if LauncherMapOpen && IsObject(LauncherGui) && hwnd = LauncherGui.Hwnd
        SyncLauncherMapPanel()
}

SyncLauncherMapPanel(allowOwnerMove := false, *)
{
    static syncing := false
    if syncing
        return
    syncing := true
    try return SyncLauncherMapPanelCore(allowOwnerMove)
    finally syncing := false
}

SyncLauncherMapPanelCore(allowOwnerMove := false)
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
    bounds := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", LauncherGui.Hwnd, "Ptr", bounds)
        return false
    owner := {L: NumGet(bounds, 0, "Int"), T: NumGet(bounds, 4, "Int"),
        R: NumGet(bounds, 8, "Int"), B: NumGet(bounds, 12, "Int")}
    monitor := MonitorFromPoint((owner.L + owner.R) // 2, (owner.T + owner.B) // 2)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    placement := GetLauncherMapPlacement(owner, {L: left, T: top, R: right, B: bottom}, allowOwnerMove)
    if !placement.Available
    {
        ; Never let a timer move the launcher or put the map over its art.
        if !allowOwnerMove
            SetLauncherMapOpen(false)
        return false
    }
    if placement.OwnerX != owner.L
    {
        ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE.
        if !DllCall("SetWindowPos", "Ptr", LauncherGui.Hwnd, "Ptr", 0,
            "Int", placement.OwnerX, "Int", owner.T, "Int", 0, "Int", 0, "UInt", 0x15)
            return false
    }
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
    if LauncherMapPanel.MapBrowserStarted && LauncherMapPanel.MapBrowserPid
        && !ProcessExist(LauncherMapPanel.MapBrowserPid)
    {
        LauncherMapPanel.MapBrowserPid := 0
        LauncherMapPanel.MapViewport.Text := "Map unavailable. Click to retry."
    }
    return true
}

StartLauncherMapBrowser(panel)
{
    global LauncherMapOpen
    if !LauncherMapOpen || !IsObject(panel)
        return
    if panel.MapBrowserPid && ProcessExist(panel.MapBrowserPid)
        return
    panel.MapBrowserStarted := true
    panel.MapBrowserPid := 0
    panel.MapViewport.Text := "Loading map..."
    host := A_ScriptDir "\chat-host\tes3np.ChatHost.exe"
    if !FileExist(host)
    {
        panel.MapViewport.Text := "Map browser missing. Rebuild the launcher."
        return
    }
    try
    {
        ownerPid := DllCall("GetCurrentProcessId", "UInt")
        Run('"' host '" --server-map ' panel.MapViewport.Hwnd ' ' ownerPid, A_ScriptDir, , &pid)
        panel.MapBrowserPid := pid
    }
    catch
        panel.MapViewport.Text := "Map unavailable. Click to retry."
}

DisposeLauncherMapPanel()
{
    global LauncherMapPanel, LauncherMapOpen
    OnMessage(0x0003, LauncherMapOwnerMoved, 0)
    SetTimer(SyncLauncherMapPanel, 0)
    LauncherMapOpen := false
    if IsObject(LauncherMapPanel)
    {
        pid := LauncherMapPanel.MapBrowserPid
        LauncherMapPanel.Destroy()
        ; The map-only process detects its lost viewport and exits normally.
        ; Do not terminate the shared Game Chat process or WebView2 workers.
        if pid && ProcessExist(pid)
            try ProcessWaitClose(pid, 2)
    }
    LauncherMapPanel := 0
}
