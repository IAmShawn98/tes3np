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
        LauncherMapPanel := CreateLauncherMapPanel(LauncherGui, loadContent)
    LauncherMapOpen := !!open
    if LauncherMapOpen
    {
        try
        {
            ; Keep the requested open state even if the owner is temporarily hidden.
            SyncLauncherMapPanel()
            if loadContent
                StartLauncherMapBrowser(LauncherMapPanel)
            ; Follow native owner movement immediately; keep a fast watchdog for
            ; visibility, work-area, scale and missed movement notifications.
            OnMessage(0x0003, LauncherMapOwnerMoved)
            OnMessage(0x0201, LauncherMapFrameDown, -1)
            OnMessage(0x0203, LauncherMapFrameDown, -1)
            OnMessage(0x0020, LauncherMapFrameCursor, -1)
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
        OnMessage(0x0201, LauncherMapFrameDown, 0)
        OnMessage(0x0203, LauncherMapFrameDown, 0)
        OnMessage(0x0020, LauncherMapFrameCursor, 0)
        if IsObject(LauncherMapPanel)
            FinishLauncherMapDrag(LauncherMapPanel)
        SetTimer(SyncLauncherMapPanel, 0)
        if IsObject(LauncherMapPanel)
            LauncherMapPanel.Hide()
    }
    if IsObject(LauncherMapToggle)
        DllCall("InvalidateRect", "Ptr", LauncherMapToggle.Hwnd, "Ptr", 0, "Int", 0)
}

CreateLauncherMapPanel(owner, loadPlacement := true)
{
    panel := Gui("-Caption -Border -DPIScale +ToolWindow +Owner" owner.Hwnd, "Drak's Server Map")
    panel.MarginX := 0, panel.MarginY := 0
    panel.BackColor := "A68B50"
    panel.MapTexture := A_ScriptDir "\assets\controls\map-frame.png"
    try
    {
        panel.MapFrame := panel.Add("Picture", "x0 y0 w1 h1 +0x100", panel.MapTexture)
        panel.MapTitle := panel.Add("Text", "x0 y0 w1 h1 Center +0x200 +0x100 Background10100D cE1BD79", "Drak's Server Map")
        ; WS_CLIPCHILDREN prevents the native backing label from painting over
        ; the separate WebView2 child. The label is also a retry target if needed.
        panel.MapViewport := panel.Add("Text", "x0 y0 w1 h1 Center +0x200 +0x100 +0x02000000 Background132725 cE1BD79", "")
        panel.MapViewport.OnEvent("Click", (*) => StartLauncherMapBrowser(panel))
        panel.MapBrowserPid := 0
        panel.MapBrowserStarted := false
        panel.MapSizeKey := ""
        panel.MapManualBounds := loadPlacement ? ReadLauncherMapPlacement() : false
        panel.MapPlacementEnabled := loadPlacement
        panel.MapDrag := false
        panel.MapLastTitleClick := -10000
        panel.MapLastTitleX := 0, panel.MapLastTitleY := 0
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

; Mirror Game Chat's monitor-edge policy: prefer the right dock, switch
; sides when needed, and clamp the entire panel to the monitor work area.
; Keep the map's native scale and gap; never move the launcher to make room.
GetLauncherMapPlacement(owner, work)
{
    if owner.R <= owner.L || owner.B <= owner.T || work.R <= work.L || work.B <= work.T
        return {Available: false}
    scale := Max(0.01, (owner.R - owner.L) / 960)
    gap := Max(1, Round(4 * scale))
    fit := Min(scale, (work.R - work.L) / 480, (work.B - work.T) / 405)
    leftSpace := owner.L - work.L - gap
    rightSpace := work.R - owner.R - gap
    sideWidth := Max(leftSpace, rightSpace)
    ; As in Game Chat, only fit to side space if a useful side exists.
    ; Otherwise keep the work-area fitted size and allow clamped overlap.
    if sideWidth >= Min(220, Round(480 * 0.5))
        fit := Min(fit, sideWidth / 480)
    w := Min(work.R - work.L, Max(1, Round(480 * fit)))
    h := Min(work.B - work.T, Max(1, Round(405 * fit)))
    dockRight := rightSpace >= w || (leftSpace < w && rightSpace >= leftSpace)
    x := dockRight ? owner.R + gap : owner.L - gap - w
    x := Max(work.L, Min(work.R - w, x))
    y := Max(work.T, Min(work.B - h, Round((owner.T + owner.B - h) / 2)))
    return {Available: true, X: x, Y: y, W: w, H: h}
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
    manual := IsObject(panel.MapManualBounds)
    key := w "|" h "|" AccessibilityTextSize "|" A_ScreenDPI "|" manual
    if panel.MapSizeKey = key
        return
    scale := Min(w / 480, h / 405)
    if manual
        scale := Min(scale, Max(1, A_ScreenDPI / 96))
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

; Position data is separate from imported launcher profiles/settings.
LauncherMapPlacementFile()
{
    global AppDataDirectory
    return AppDataDirectory "\map-window-bounds.ini"
}

ParseLauncherMapBounds(value)
{
    parts := StrSplit(value, ",")
    if parts.Length != 4
        return false
    for part in parts
        if !RegExMatch(part, "^-?\d{1,7}$")
            return false
    x := Integer(parts[1]), y := Integer(parts[2]), w := Integer(parts[3]), h := Integer(parts[4])
    if Abs(x) > 1000000 || Abs(y) > 1000000 || w < 1 || w > 32768 || h < 1 || h > 32768
        return false
    return {X: x, Y: y, W: w, H: h}
}

ReadLauncherMapPlacement()
{
    try return ParseLauncherMapBounds(IniRead(LauncherMapPlacementFile(), "Window", "Bounds", "auto"))
    catch
        return false
}

SaveLauncherMapPlacement(panel)
{
    global AppDataDirectory
    if !panel.MapPlacementEnabled
        return
    r := panel.MapManualBounds
    value := IsObject(r) ? r.X "," r.Y "," r.W "," r.H : "auto"
    try
    {
        DirCreate(AppDataDirectory)
        IniWrite(value, LauncherMapPlacementFile(), "Window", "Bounds")
    }
    catch as err
        try LogLauncherEvent("UI | Map placement save failed (" Type(err) ").")
}

ClampLauncherMapBounds(r, work)
{
    w := Min(work.R - work.L, Max(144, r.W))
    h := Min(work.B - work.T, Max(122, r.H))
    return {Available: true, X: Max(work.L, Min(work.R - w, r.X)),
        Y: Max(work.T, Min(work.B - h, r.Y)), W: w, H: h}
}

LauncherMapWorkAt(x, y)
{
    MonitorGetWorkArea(MonitorFromPoint(x, y), &l, &t, &r, &b)
    return {L: l, T: t, R: r, B: b}
}

LauncherMapFrameHit(x, y, w, h, edge, header)
{
    hit := (x < edge ? 1 : x >= w - edge ? 2 : 0) | (y < edge ? 4 : y >= h - edge ? 8 : 0)
    return hit ? hit : y < header ? 16 : 0
}

ResizeLauncherMapBounds(r, hit, dx, dy)
{
    if hit = 16
        return {X: r.X + dx, Y: r.Y + dy, W: r.W, H: r.H}
    l := (hit & 1) ? Min(r.X + r.W - 144, r.X + dx) : r.X
    right := (hit & 2) ? Max(r.X + 144, r.X + r.W + dx) : r.X + r.W
    t := (hit & 4) ? Min(r.Y + r.H - 122, r.Y + dy) : r.Y
    b := (hit & 8) ? Max(r.Y + 122, r.Y + r.H + dy) : r.Y + r.H
    return {X: l, Y: t, W: right - l, H: b - t}
}

LauncherMapFrameCursor(wParam, lParam, msg, hwnd)
{
    global LauncherMapPanel, LauncherMapOpen
    panel := LauncherMapPanel
    if !LauncherMapOpen || !IsObject(panel)
        return
    if wParam != panel.Hwnd && wParam != panel.MapFrame.Hwnd && wParam != panel.MapTitle.Hwnd
        return
    rect := Buffer(16, 0), pt := Buffer(8, 0)
    if !DllCall("GetWindowRect", "Ptr", panel.Hwnd, "Ptr", rect) || !DllCall("GetCursorPos", "Ptr", pt)
        return
    x := NumGet(rect, 0, "Int"), y := NumGet(rect, 4, "Int")
    w := NumGet(rect, 8, "Int") - x, h := NumGet(rect, 12, "Int") - y
    panel.MapViewport.GetPos(, &header)
    edge := Max(3, Min(7, Round(7 * Min(w / 480, h / 405))))
    hit := LauncherMapFrameHit(NumGet(pt, 0, "Int") - x, NumGet(pt, 4, "Int") - y, w, h, edge, header)
    switch hit
    {
        case 1, 2: cursorId := 32644
        case 4, 8: cursorId := 32645
        case 5, 10: cursorId := 32642
        case 6, 9: cursorId := 32643
        case 16: cursorId := 32646
        default: return
    }
    cursor := DllCall("LoadCursorW", "Ptr", 0, "Ptr", cursorId, "Ptr")
    if cursor
    {
        DllCall("SetCursor", "Ptr", cursor)
        return 1
    }
}

LauncherMapFrameDown(wParam, lParam, msg, hwnd)
{
    global LauncherMapPanel, LauncherMapOpen
    panel := LauncherMapPanel
    if !LauncherMapOpen || !IsObject(panel)
        return
    if hwnd != panel.Hwnd && hwnd != panel.MapFrame.Hwnd && hwnd != panel.MapTitle.Hwnd
        return
    rect := Buffer(16, 0), pt := Buffer(8, 0)
    if !DllCall("GetWindowRect", "Ptr", panel.Hwnd, "Ptr", rect) || !DllCall("GetCursorPos", "Ptr", pt)
        return
    x := NumGet(rect, 0, "Int"), y := NumGet(rect, 4, "Int")
    w := NumGet(rect, 8, "Int") - x, h := NumGet(rect, 12, "Int") - y
    px := NumGet(pt, 0, "Int"), py := NumGet(pt, 4, "Int")
    panel.MapViewport.GetPos(, &header)
    edge := Max(3, Min(7, Round(7 * Min(w / 480, h / 405))))
    hit := LauncherMapFrameHit(px - x, py - y, w, h, edge, header)
    if !hit
        return
    now := A_TickCount
    if hit = 16 && (msg = 0x0203 || (now - panel.MapLastTitleClick <= DllCall("GetDoubleClickTime", "UInt")
        && Abs(px - panel.MapLastTitleX) <= Max(2, DllCall("GetSystemMetrics", "Int", 36) // 2)
        && Abs(py - panel.MapLastTitleY) <= Max(2, DllCall("GetSystemMetrics", "Int", 37) // 2)))
    {
        FinishLauncherMapDrag(panel)
        panel.MapLastTitleClick := -10000
        panel.MapManualBounds := false
        SaveLauncherMapPlacement(panel)
        SyncLauncherMapPanel()
        return 0
    }
    panel.MapLastTitleClick := hit = 16 ? now : -10000
    panel.MapLastTitleX := px, panel.MapLastTitleY := py
    panel.MapDrag := {Start: {X: x, Y: y, W: w, H: h}, X: px, Y: py, Hit: hit, Changed: false}
    return 0
}

TrackLauncherMapDrag(panel)
{
    drag := panel.MapDrag
    if !IsObject(drag)
        return
    primary := DllCall("GetSystemMetrics", "Int", 23) ? 2 : 1
    pt := Buffer(8, 0)
    if DllCall("GetCursorPos", "Ptr", pt)
    {
        x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
        dx := x - drag.X, dy := y - drag.Y
        if drag.Changed || Abs(dx) >= 4 || Abs(dy) >= 4
        {
            drag.Changed := true
            panel.MapLastTitleClick := -10000
            panel.MapManualBounds := ClampLauncherMapBounds(ResizeLauncherMapBounds(drag.Start, drag.Hit, dx, dy),
                LauncherMapWorkAt(x, y))
        }
    }
    if !(DllCall("GetAsyncKeyState", "Int", primary, "Short") & 0x8000)
        FinishLauncherMapDrag(panel)
}

FinishLauncherMapDrag(panel)
{
    drag := panel.MapDrag
    panel.MapDrag := false
    if IsObject(drag) && drag.Changed
        SaveLauncherMapPlacement(panel)
}

LauncherMapOwnerMoved(wParam, lParam, msg, hwnd)
{
    global LauncherGui, LauncherMapOpen
    ; WM_MOVE also arrives for the map and other windows. Only the launcher
    ; drives docking; do not intercept the native message or change activation.
    if LauncherMapOpen && IsObject(LauncherGui) && hwnd = LauncherGui.Hwnd
        SyncLauncherMapPanel()
}

SyncLauncherMapPanel(*)
{
    static syncing := false
    if syncing
        return
    syncing := true
    try return SyncLauncherMapPanelCore()
    finally syncing := false
}

SyncLauncherMapPanelCore()
{
    global LauncherGui, LauncherMapPanel, LauncherMapOpen, LauncherMapToggle
    if !LauncherMapOpen || !IsObject(LauncherMapPanel) || !IsObject(LauncherGui)
        return
    if !DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd) || DllCall("IsIconic", "Ptr", LauncherGui.Hwnd)
        || !DllCall("IsWindowEnabled", "Ptr", LauncherGui.Hwnd)
    {
        FinishLauncherMapDrag(LauncherMapPanel)
        LauncherMapPanel.Hide()
        return
    }
    TrackLauncherMapDrag(LauncherMapPanel)
    bounds := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", LauncherGui.Hwnd, "Ptr", bounds)
        return false
    owner := {L: NumGet(bounds, 0, "Int"), T: NumGet(bounds, 4, "Int"),
        R: NumGet(bounds, 8, "Int"), B: NumGet(bounds, 12, "Int")}
    monitor := MonitorFromPoint((owner.L + owner.R) // 2, (owner.T + owner.B) // 2)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    placement := GetLauncherMapPlacement(owner, {L: left, T: top, R: right, B: bottom})
    if IsObject(LauncherMapPanel.MapManualBounds)
    {
        saved := LauncherMapPanel.MapManualBounds
        placement := ClampLauncherMapBounds(saved, LauncherMapWorkAt(saved.X + saved.W // 2, saved.Y + saved.H // 2))
    }
    if !placement.Available
    {
        ; Invalid bounds can be temporary. Keep the tab open for recovery.
        LauncherMapPanel.Hide()
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
    OnMessage(0x0201, LauncherMapFrameDown, 0)
    OnMessage(0x0203, LauncherMapFrameDown, 0)
    OnMessage(0x0020, LauncherMapFrameCursor, 0)
    OnMessage(0x0003, LauncherMapOwnerMoved, 0)
    SetTimer(SyncLauncherMapPanel, 0)
    LauncherMapOpen := false
    if IsObject(LauncherMapPanel)
    {
        FinishLauncherMapDrag(LauncherMapPanel)
        pid := LauncherMapPanel.MapBrowserPid
        LauncherMapPanel.Destroy()
        ; The map-only process detects its lost viewport and exits normally.
        ; Do not terminate the shared Game Chat process or WebView2 workers.
        if pid && ProcessExist(pid)
            try ProcessWaitClose(pid, 2)
    }
    LauncherMapPanel := 0
}
