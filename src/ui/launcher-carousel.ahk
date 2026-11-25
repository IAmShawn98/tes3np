; v10: real Happy Hour artwork track on the approved v8 renderer; no native painter changes.
; The original native controls paint normally until the first transition.
global LauncherCarousel := 0

CreateLauncherCarousel(background, parchment)
{
    global LauncherCarousel
    ; Keep stable endpoint IDs and load only assigned artwork.
    ; Endpoint 1 uses the original native launcher background.
    paths := Map(1, "", 8, A_ScriptDir "\assets\carousel\default\07.png",
        18, A_ScriptDir "\assets\carousel\default\17.png")
    for index, path in paths
        if index != 1 && !FileExist(path)
            return
    cleanPath := A_ScriptDir "\assets\carousel\clean.png"
    if !FileExist(cleanPath)
        return
    LauncherCarousel := {Background: background, Parchment: parchment, Callback: 0, Paths: paths,
        CleanPath: cleanPath, Current: 1, Next: 0, Elapsed: 0, Fade: 0, Last: 0,
        Tracks: Map("default", [1], "no_characters", [18], "happy_hour", [8]), Track: "",
        Frames: Map(), Snapshot: 0, Width: 0, Height: 0, Active: false, Failed: false,
        DustComposited: false, DustLayer: 0, DustWidth: 0, DustHeight: 0,
        TransparentRepair: false, Transparent: Map(), Attached: [],
        Shade: 0, ShadeWidth: 0, ShadeHeight: 0, ShadeScale: 0, ShadeFailed: false}
}

StartLauncherCarousel(*)
{
    global LauncherCarousel
    if !IsObject(LauncherCarousel) || LauncherCarousel.Failed
        return
    LauncherCarousel.Last := DllCall("GetTickCount64", "UInt64")
    SetTimer(TickLauncherCarousel, 250)
    TickLauncherCarousel()
}

; Profile mutations are committed under InterfaceUpdating, which the tick
; already respects. Zero saved characters selects the welcome track.
SelectLauncherArtworkTrack()
{
    global Profiles, HappyHourBannerVisible
    ; Live event art takes precedence; restore the current profile track on end.
    if HappyHourBannerVisible
        return "happy_hour"
    return Profiles.Length = 0 ? "no_characters" : "default"
}

; Tracks are arrays of stable endpoint IDs in Paths. Future holiday/event
; selection can return another track without changing the renderer.
NextLauncherArtworkIndex(state, track)
{
    for position, index in track
        if index = state.Current
            return track[Mod(position, track.Length) + 1]
    return track[1]
}

TickLauncherCarousel(*)
{
    global LauncherCarousel, LauncherGui, InterfaceUpdating, HappyHourBannerVisible
    if !IsObject(LauncherCarousel) || LauncherCarousel.Failed
        return
    state := LauncherCarousel
    now := DllCall("GetTickCount64", "UInt64")
    delta := Min(500, Max(0, now - state.Last))
    state.Last := now
    if InterfaceUpdating || !DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        || DllCall("IsIconic", "Ptr", LauncherGui.Hwnd)
        return
    previousCritical := A_IsCritical
    Critical("On")
    try
    {
        state.Elapsed += delta
        refresh := false
        desired := SelectLauncherArtworkTrack()
        if state.Track = ""
        {
            ; Initial selection is immediate, without a 20-second wait.
            ; Native startup has already painted before this timer starts.
            state.Track := desired
            state.Current := state.Tracks[desired][1]
            state.Elapsed := 0
            if state.Current != 1
            {
                AttachLauncherCarouselPainter(state)
                refresh := true
            }
        }
        else if !state.Next
        {
            track := state.Tracks[desired]
            target := 0
            if desired != state.Track
            {
                state.Track := desired
                state.Elapsed := 0
                target := track[1]
            }
            else if track.Length > 1 && state.Elapsed >= 20000
            {
                state.Elapsed := 0
                target := NextLauncherArtworkIndex(state, track)
            }
            else if track.Length = 1
                state.Elapsed := 0
            if target && target != state.Current
            {
                state.Next := target
                state.Fade := 0
                AttachLauncherCarouselPainter(state)
                SetTimer(TickLauncherCarousel, 40)
                refresh := true
            }
        }
        else if state.Next
        {
            state.Fade := Min(1200, state.Fade + delta)
            if state.Fade >= 1200
            {
                old := state.Current
                state.Current := state.Next
                state.Next := 0
                state.Fade := 0
                if state.Frames.Has(old)
                {
                    DllCall("gdiplus\GdipDisposeImage", "Ptr", state.Frames[old])
                    state.Frames.Delete(old)
                }
                SetTimer(TickLauncherCarousel, 250)
                if state.Current = 1 && !HappyHourBannerVisible
                {
                    ResetLauncherCarousel(state, false)
                    return
                }
            }
            refresh := true
        }
        if !state.Next && state.Current = 1 && !state.Active
            return
        rect := Buffer(16, 0)
        if !DllCall("GetClientRect", "Ptr", state.Background.Hwnd, "Ptr", rect)
            throw Error("Carousel background unavailable.")
        w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
        if refresh || w != state.Width || h != state.Height || !state.Active
        {
            GetLauncherCarouselFrames(state, w, h)
            ComposeLauncherCarouselSnapshot(state)
            state.Active := true
            dustChanged := UpdateLauncherCarouselDustMode(state)
            RepaintLauncherCarouselRegion(state, dustChanged)
        }
    }
    catch Error as err
    {
        try LogLauncherEvent("UI | Carousel v9 paint failed: " err.Message)
        DisableLauncherCarousel()
    }
    finally Critical(previousCritical)
}

AttachLauncherCarouselPainter(state)
{
    global DragStrip, LauncherHeading, LauncherVersionLabel, HappyHourJiubPicture
    if state.Callback
        return
    callback := CallbackCreate(LauncherCarouselWindowProc, "Fast", 6)
    attached := []
    controls := [state.Background, state.Parchment]
    ; Transparent native statics need a real opaque backing after the native
    ; full-window dust pictures are hidden. Keep their HWNDs and input events.
    for entry in [[DragStrip, "drag"], [LauncherHeading, "heading"],
        [LauncherVersionLabel, "version"], [HappyHourJiubPicture, "jiub"]]
    {
        if IsObject(entry[1])
        {
            controls.Push(entry[1])
            state.Transparent[entry[1].Hwnd] := entry[2]
        }
    }
    try
    {
        for control in controls
        {
            if !DllCall("comctl32\SetWindowSubclass", "Ptr", control.Hwnd, "Ptr", callback, "UPtr", 1, "UPtr", 0)
                throw Error("Carousel picture subclass failed.")
            attached.Push(control)
        }
        state.Attached := attached
        state.Callback := callback
    }
    catch Error
    {
        for control in attached
            DllCall("comctl32\RemoveWindowSubclass", "Ptr", control.Hwnd, "Ptr", callback, "UPtr", 1)
        state.Transparent.Clear()
        CallbackFree(callback)
        throw
    }
}

LauncherCarouselWindowProc(handle, message, wParam, lParam, subclassID, reference)
{
    global LauncherCarousel
    ; Do not alter normal startup, first slide or fallback painting.
    if !LauncherCarouselBackdropActive()
        || (LauncherCarousel.Transparent.Has(handle) && !LauncherCarousel.TransparentRepair)
        return DllCall("comctl32\DefSubclassProc", "Ptr", handle, "UInt", message, "Ptr", wParam, "Ptr", lParam, "Ptr")
    if message = 0x0014
        return 1
    if message = 0x000F || message = 0x0318
    {
        paint := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
        previousCritical := A_IsCritical
        Critical("On")
        dc := message = 0x000F ? DllCall("BeginPaint", "Ptr", handle, "Ptr", paint, "Ptr") : wParam
        try
        {
            if dc
                PaintLauncherCarouselPicture(LauncherCarousel, handle, dc)
        }
        catch Error
            SetTimer(DisableLauncherCarousel, -1)
        finally
        {
            if message = 0x000F
                DllCall("EndPaint", "Ptr", handle, "Ptr", paint)
            Critical(previousCritical)
        }
        return 0
    }
    return DllCall("comctl32\DefSubclassProc", "Ptr", handle, "UInt", message, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

GetLauncherCarouselFrames(state, width, height)
{
    if width <= 0 || height <= 0
        throw Error("Invalid carousel frame dimensions.")
    if state.Width != width || state.Height != height
    {
        ReleaseLauncherCarouselFrames(state)
        state.Width := width, state.Height := height
    }
    for index in [state.Current, state.Next]
        if index && !state.Frames.Has(index)
            state.Frames[index] := MakeLauncherCarouselFrame(state, index, width, height)
    if state.Frames.Count > 2
        throw Error("Carousel frame cache exceeded its two-image limit.")
}

MakeLauncherCarouselFrame(state, index, width, height)
{
    global ButtonPaint
    frame := 0, graphics := 0, slide := 0, clean := 0
    try
    {
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", width, "Int", height,
            "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &frame))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", frame, "Ptr*", &graphics))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF272722))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Background,
            "Int", 0, "Int", 0, "Int", width, "Int", height))
        if index > 1
        {
            x := Round(490 * width / 960), y := Round(250 * height / 720)
            w := Round(930 * width / 960) - x, h := Round(696 * height / 720) - y
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipLoadImageFromFile", "WStr", state.CleanPath, "Ptr*", &clean))
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", clean,
                "Int", x, "Int", y, "Int", w, "Int", h))
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipLoadImageFromFile", "WStr", state.Paths[index], "Ptr*", &slide))
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", slide,
                "Int", x, "Int", y, "Int", w, "Int", h))
        }
        result := frame
        frame := 0
        return result
    }
    finally
    {
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        for image in [clean, slide, frame]
            if image
                DllCall("gdiplus\GdipDisposeImage", "Ptr", image)
    }
}

; Create one immutable full-background snapshot per tick. No screen pixels or
; previous composite are ever used as input. All overlapping painters sample it.
ComposeLauncherCarouselSnapshot(state)
{
    frame := 0, graphics := 0
    try
    {
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", state.Width, "Int", state.Height,
            "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &frame))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", frame, "Ptr*", &graphics))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF272722))
        DrawLauncherCarouselFrames(state, graphics, 0, 0, state.Width, state.Height)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        graphics := 0
        previous := state.Snapshot
        state.Snapshot := frame
        frame := 0
        if previous
            DllCall("gdiplus\GdipDisposeImage", "Ptr", previous)
    }
    finally
    {
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        if frame
            DllCall("gdiplus\GdipDisposeImage", "Ptr", frame)
    }
}

DrawLauncherCarouselFrames(state, graphics, x, y, width, height)
{
    attributes := 0
    try
    {
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", state.Frames[state.Current],
            "Int", x, "Int", y, "Int", width, "Int", height))
        if state.Next
        {
            t := state.Fade / 1200
            alpha := t * t * (3 - 2 * t)
            matrix := Buffer(100, 0)
            for offset in [0, 24, 48, 96]
                NumPut("Float", 1.0, matrix, offset)
            NumPut("Float", alpha, matrix, 72)
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &attributes))
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "Ptr", attributes,
                "Int", 1, "Int", 1, "Ptr", matrix, "Ptr", 0, "Int", 0))
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", graphics, "Ptr", state.Frames[state.Next],
                "Int", x, "Int", y, "Int", width, "Int", height,
                "Int", 0, "Int", 0, "Int", state.Width, "Int", state.Height,
                "Int", 2, "Ptr", attributes, "Ptr", 0, "Ptr", 0))
        }
    }
    finally
        if attributes
            DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", attributes)
}

LauncherCarouselBackdropActive()
{
    global LauncherCarousel
    return IsObject(LauncherCarousel) && LauncherCarousel.Active && !LauncherCarousel.Failed && LauncherCarousel.Snapshot
}

; Map the same physical background rectangle into each native picture/card.
DrawLauncherCarouselSnapshot(state, graphics, handle, image := 0)
{
    a := Buffer(16, 0), b := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", state.Background.Hwnd, "Ptr", a)
        || !DllCall("GetWindowRect", "Ptr", handle, "Ptr", b)
        throw Error("Carousel picture coordinates unavailable.")
    x := NumGet(a, 0, "Int") - NumGet(b, 0, "Int")
    y := NumGet(a, 4, "Int") - NumGet(b, 4, "Int")
    w := NumGet(a, 8, "Int") - NumGet(a, 0, "Int")
    h := NumGet(a, 12, "Int") - NumGet(a, 4, "Int")
    CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", image ? image : state.Snapshot,
        "Int", x, "Int", y, "Int", w, "Int", h))
}

PaintLauncherCarouselBackdrop(graphics, x, y, scale, handle := 0)
{
    global LauncherCarousel
    if !LauncherCarouselBackdropActive()
        return
    state := LauncherCarousel
    try
    {
        if handle
            DrawLauncherCarouselSnapshot(state, graphics, handle)
        else
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", state.Snapshot,
                "Int", Round(-x * scale), "Int", Round((-4 - y) * scale),
                "Int", Round(960 * scale), "Int", Round(720 * scale)))
    }
    catch Error
        SetTimer(DisableLauncherCarousel, -1)
}

PaintLauncherCarouselPicture(state, handle, target)
{
    global ButtonPaint
    rect := Buffer(16, 0)
    if !DllCall("GetClientRect", "Ptr", handle, "Ptr", rect)
        return
    w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
    if w <= 0 || h <= 0
        return
    dc := 0, bitmap := 0, old := 0, graphics := 0, faceImage := 0
    role := state.Transparent.Has(handle) ? state.Transparent[handle] : ""
    try
    {
        dc := DllCall("gdi32\CreateCompatibleDC", "Ptr", target, "Ptr")
        bitmap := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", target, "Int", w, "Int", h, "Ptr")
        if !dc || !bitmap
            throw Error("Carousel buffer unavailable.")
        old := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
        if !old || old = -1
            throw Error("Carousel buffer selection failed.")
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipCreateFromHDC", "Ptr", dc, "Ptr*", &graphics))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFF272722))
        DrawLauncherCarouselSnapshot(state, graphics, handle)
        if handle = state.Parchment.Hwnd || role = "heading"
            DrawLauncherCarouselControlArtwork(graphics, handle, state.Parchment.Hwnd, ButtonPaint.Parchment)
        ; Dust is a separate transparent layer, not part of the slide endpoints.
        ; Paint it on the two backing pictures, below the native text/buttons.
        if state.DustComposited
        {
            EnsureLauncherCarouselDustLayer(state)
            if state.DustLayer
                DrawLauncherCarouselSnapshot(state, graphics, handle, state.DustLayer)
        }
        if role = "jiub"
        {
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\happy-hour\jiub-happy-hour.png", "Ptr*", &faceImage))
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", faceImage,
                "Int", 0, "Int", 0, "Int", w, "Int", h))
        }
        if role = "drag"
            PaintLauncherStatusShade(graphics, w, h)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        graphics := 0
        if role = "heading" || role = "version" || role = "drag"
            DrawLauncherCarouselNativeText(handle, dc, w, h, role)
        savedClip := DllCall("SaveDC", "Ptr", target, "Int")
        if !savedClip
            throw Error("Carousel picture clip unavailable.")
        try
        {
            ExcludeLauncherCarouselForeground(state, handle, target)
            if !DllCall("gdi32\BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", w, "Int", h,
                "Ptr", dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
                throw Error("Carousel picture paint failed.")
        }
        finally DllCall("RestoreDC", "Ptr", target, "Int", savedClip)
    }
    finally
    {
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        if faceImage
            DllCall("gdiplus\GdipDisposeImage", "Ptr", faceImage)
        if old && old != -1
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", old)
        if dc
            DllCall("gdi32\DeleteDC", "Ptr", dc)
        if bitmap
            DllCall("gdi32\DeleteObject", "Ptr", bitmap)
    }
}

; Draw a native asset in the coordinates of its actual scaled control.
DrawLauncherCarouselControlArtwork(graphics, target, source, image)
{
    a := Buffer(16, 0), b := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", source, "Ptr", a)
        || !DllCall("GetWindowRect", "Ptr", target, "Ptr", b)
        throw Error("Carousel foreground artwork coordinates unavailable.")
    CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", image,
        "Int", NumGet(a, 0, "Int") - NumGet(b, 0, "Int"),
        "Int", NumGet(a, 4, "Int") - NumGet(b, 4, "Int"),
        "Int", NumGet(a, 8, "Int") - NumGet(a, 0, "Int"),
        "Int", NumGet(a, 12, "Int") - NumGet(a, 4, "Int")))
}

; Preserve the live font, caption and alignment of the existing Text HWND.
; The backing bitmap is already opaque; no native transparent erase is needed.
DrawLauncherCarouselNativeText(handle, dc, width, height, role)
{
    global LauncherHeading, LauncherVersionLabel, DragStrip, LauncherServerStatus
    control := role = "heading" ? LauncherHeading : role = "drag" ? DragStrip : LauncherVersionLabel
    label := control.Text
    font := DllCall("SendMessageW", "Ptr", handle, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
    saved := DllCall("SaveDC", "Ptr", dc, "Int")
    if !saved
        throw Error("Carousel text DC unavailable.")
    try
    {
        if font
            DllCall("SelectObject", "Ptr", dc, "Ptr", font)
        DllCall("SetBkMode", "Ptr", dc, "Int", 1)
        ; Original heading RGB 241408, version RGB C5A45C (COLORREF BGR).
        rgb := Integer("0x" LauncherServerStatusColor(LauncherServerStatus))
        statusColor := ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
        DllCall("SetTextColor", "Ptr", dc, "UInt", role = "heading" ? 0x081424 : role = "drag" ? statusColor : 0x5CA4C5)
        rect := Buffer(16, 0)
        NumPut("Int", width, "Int", height, rect, 8)
        style := DllCall("GetWindowLongW", "Ptr", handle, "Int", -16, "UInt")
        flags := 0x800 | (role = "heading" || role = "drag" ? 1 : 0)
        if style & 0x200 ; SS_CENTERIMAGE
            flags |= 0x24 ; DT_SINGLELINE | DT_VCENTER
        if label != ""
        {
            if role = "drag"
            {
                ; Status-only dark outline, scaled with the drag-strip height.
                ; Draw into the same fresh backing buffer, never over old text.
                radius := Max(1, Round(height / 32))
                DllCall("SetTextColor", "Ptr", dc, "UInt", 0x080808)
                for offset in [[-radius, -radius], [0, -radius], [radius, -radius],
                    [-radius, 0], [radius, 0], [-radius, radius], [0, radius], [radius, radius]]
                {
                    NumPut("Int", offset[1], "Int", offset[2], "Int", width + offset[1], "Int", height + offset[2], rect)
                    DllCall("DrawTextW", "Ptr", dc, "WStr", label, "Int", -1, "Ptr", rect, "UInt", flags)
                }
                NumPut("Int", 0, "Int", 0, "Int", width, "Int", height, rect)
                DllCall("SetTextColor", "Ptr", dc, "UInt", statusColor)
            }
            DllCall("DrawTextW", "Ptr", dc, "WStr", label, "Int", -1, "Ptr", rect, "UInt", flags)
        }
    }
    finally DllCall("RestoreDC", "Ptr", dc, "Int", saved)
}

; The snapshot is opaque and never accumulated. Native partial WM_PAINT
; alone did not keep overlapping child controls in sync on the owner PC.
; Explicitly paint the two pictures and themed controls from the same snapshot.
RepaintLauncherCarouselRegion(state, full := false)
{
    global LauncherGui, ButtonFaces
    a := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", state.Background.Hwnd, "Ptr", a)
        return
    bx := NumGet(a, 0, "Int"), by := NumGet(a, 4, "Int")
    w := NumGet(a, 8, "Int") - bx, h := NumGet(a, 12, "Int") - by
    region := {L: bx + Floor(490 * w / 960), T: by + Floor(250 * h / 720),
        R: bx + Ceil(930 * w / 960), B: by + Ceil(696 * h / 720)}
    ; Only a real dust-mode change needs the whole backing picture. Fades
    ; keep the proven v4 clipped region, not a full parent-window redraw.
    if full
        region := {L: bx, T: by, R: bx + w, B: by + h}
    ; Reset uses the original native painter, then refresh every visible child.
    if !state.Active
    {
        DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
        RepaintMenuButtons()
        ; Native redraw alone can leave the old Together pixels on screen.
        ; The snapshot is already disposed and Active is false, so the
        ; existing painter now uses only the original backing artwork.
        for control in LauncherGui
        {
            handle := control.Hwnd
            if !ButtonFaces.Has(handle) || !LauncherCarouselIntersects(handle, region)
                continue
            if ButtonFaces[handle].HasOwnProp("IsInfo")
            {
                ReleaseLauncherFaceCache(handle)
                PaintButtonNow(handle)
            }
        }
        return
    }
    ; Paint the background without writing into the foreground child rectangles.
    PaintLauncherCarouselDirect(state, state.Background.Hwnd, region)
    PaintLauncherCarouselDirect(state, state.Parchment.Hwnd, region)
    for control in LauncherGui
    {
        handle := control.Hwnd
        if handle = state.Background.Hwnd || handle = state.Parchment.Hwnd
            continue
        if !LauncherCarouselIntersects(handle, region)
            continue
        if ButtonFaces.Has(handle)
        {
            ; No partial invalidation or stale cached face: explicitly invoke
            ; the existing native painter for the entire themed control.
            if ButtonFaces[handle].HasOwnProp("IsInfo")
                ReleaseLauncherFaceCache(handle)
            PaintButtonNow(handle)
        }
        else if state.TransparentRepair && state.Transparent.Has(handle)
            PaintLauncherCarouselDirect(state, handle, region)
        else
            DllCall("RedrawWindow", "Ptr", handle, "Ptr", 0, "Ptr", 0, "UInt", 0x0121)
    }
}

LauncherCarouselIntersects(handle, region)
{
    if !DllCall("IsWindowVisible", "Ptr", handle)
        return false
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", handle, "Ptr", rect)
        return false
    return NumGet(rect, 0, "Int") < region.R && NumGet(rect, 8, "Int") > region.L
        && NumGet(rect, 4, "Int") < region.B && NumGet(rect, 12, "Int") > region.T
}

; Exclude foreground child HWNDs when painting backing pictures. This is
; deliberately DC-local, never a persistent WS_CLIPSIBLINGS/z-order change.
PaintLauncherCarouselDirect(state, handle, region)
{
    global LauncherGui
    if !LauncherCarouselIntersects(handle, region)
        return
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", handle, "Ptr", rect)
        return
    x := NumGet(rect, 0, "Int"), y := NumGet(rect, 4, "Int")
    target := DllCall("GetDC", "Ptr", handle, "Ptr")
    if !target
        throw Error("Carousel direct picture DC unavailable.")
    saved := 0
    try
    {
        saved := DllCall("SaveDC", "Ptr", target, "Int")
        if !saved
            throw Error("Carousel picture clip unavailable.")
        DllCall("IntersectClipRect", "Ptr", target, "Int", region.L - x, "Int", region.T - y,
            "Int", region.R - x, "Int", region.B - y)
        PaintLauncherCarouselPicture(state, handle, target)
    }
    finally
    {
        if saved
            DllCall("RestoreDC", "Ptr", target, "Int", saved)
        DllCall("ReleaseDC", "Ptr", handle, "Ptr", target)
    }
}

; Protect sibling controls even during ordinary expose/resize painting.
ExcludeLauncherCarouselForeground(state, handle, dc)
{
    global LauncherGui
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", handle, "Ptr", rect)
        return
    x := NumGet(rect, 0, "Int"), y := NumGet(rect, 4, "Int")
    for control in LauncherGui
    {
        child := control.Hwnd
        if child = handle || child = state.Background.Hwnd
            continue
        ; A repaired transparent heading owns its own opaque parchment slice.
        ; Its backing Picture is not a foreground occluder for this paint.
        if state.Transparent.Has(handle) && child = state.Parchment.Hwnd
            continue
        if !DllCall("IsWindowVisible", "Ptr", child)
            continue
        if DllCall("GetWindowRect", "Ptr", child, "Ptr", rect)
            DllCall("ExcludeClipRect", "Ptr", dc,
                "Int", NumGet(rect, 0, "Int") - x, "Int", NumGet(rect, 4, "Int") - y,
                "Int", NumGet(rect, 8, "Int") - x, "Int", NumGet(rect, 12, "Int") - y)
    }
}

; The Together card's shade is static for a given physical size. Cache only
; that transparent layer, never the live background or text. V4 clipping and
; synchronized redraw are unchanged. If this optional cache fails, the native
; renderer draws its original tile loop instead.
PaintLauncherCarouselInfoShade(graphics, width, height, scale)
{
    global LauncherCarousel
    if !LauncherCarouselBackdropActive()
        return false
    state := LauncherCarousel
    if state.ShadeFailed
        return false
    candidate := 0, layerGraphics := 0
    try
    {
        if !state.Shade || state.ShadeWidth != width || state.ShadeHeight != height || state.ShadeScale != scale
        {
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", width, "Int", height,
                "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &candidate))
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", candidate, "Ptr*", &layerGraphics))
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGraphicsClear", "Ptr", layerGraphics, "UInt", 0))
            ; SourceCopy preserves the exact per-tile alpha on this empty layer.
            CheckLauncherCarouselGdi(DllCall("gdiplus\GdipSetCompositingMode", "Ptr", layerGraphics, "Int", 1))
            PaintLauncherFeatheredShade(layerGraphics, width, height, scale, 0, 190, 28, 22, 38, true)
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", layerGraphics)
            layerGraphics := 0
            ReleaseLauncherCarouselShade(state)
            state.Shade := candidate, candidate := 0
            state.ShadeWidth := width, state.ShadeHeight := height, state.ShadeScale := scale
        }
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", state.Shade,
            "Int", 0, "Int", 0, "Int", width, "Int", height))
        return true
    }
    catch Error as err
    {
        state.ShadeFailed := true
        ReleaseLauncherCarouselShade(state)
        try LogLauncherEvent("UI | Carousel shade cache unavailable; original tile painter retained: " err.Message)
        return false
    }
    finally
    {
        if layerGraphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", layerGraphics)
        if candidate
            DllCall("gdiplus\GdipDisposeImage", "Ptr", candidate)
    }
}

ReleaseLauncherCarouselShade(state)
{
    if state.Shade
        DllCall("gdiplus\GdipDisposeImage", "Ptr", state.Shade)
    state.Shade := 0, state.ShadeWidth := 0, state.ShadeHeight := 0, state.ShadeScale := 0
}

CheckLauncherCarouselGdi(status)
{
    if status
        throw Error("Carousel graphics status " status)
}

ReleaseLauncherCarouselFrames(state)
{
    for index, image in state.Frames
        DllCall("gdiplus\GdipDisposeImage", "Ptr", image)
    state.Frames.Clear()
}

; Called after the existing event visibility handler updates Jiub. The real
; banner signal changes only the dust presentation, never the slide or clock.
SyncLauncherCarouselHappyHour(visible)
{
    global LauncherCarousel
    if !IsObject(LauncherCarousel) || LauncherCarousel.Failed || !LauncherCarousel.Active
        return
    state := LauncherCarousel
    previousCritical := A_IsCritical
    Critical("On")
    try
    {
        if UpdateLauncherCarouselDustMode(state)
            RepaintLauncherCarouselRegion(state, true)
    }
    catch Error as err
    {
        try LogLauncherEvent("UI | Carousel Happy Hour composition failed: " err.Message)
        DisableLauncherCarousel()
    }
    finally Critical(previousCritical)
}

; The four native dust Pictures cover the entire launcher. While visible,
; v4's sibling exclusion would clip away the entire carousel. Preserve their
; normal startup/fallback path. During active composition use a single scaled
; PNG impression at the original first HWND position, avoiding four-pass
; source-over alpha buildup that enlarged visible particles in the v7 test.
UpdateLauncherCarouselDustMode(state)
{
    global HappyHourBannerVisible, HappyHourDustPictures
    desired := !!(state.Active && !state.Failed && HappyHourBannerVisible && HappyHourDustPictures.Length)
    if desired = state.DustComposited
        return false
    if desired
        EnsureLauncherCarouselDustLayer(state)
    state.DustComposited := desired
    if desired
        state.TransparentRepair := true
    for dust in HappyHourDustPictures
        dust.Visible := HappyHourBannerVisible && !desired
    if !desired
        ReleaseLauncherCarouselDustLayer(state)
    return true
}

EnsureLauncherCarouselDustLayer(state)
{
    global HappyHourDustPictures
    if state.DustLayer && state.DustWidth = state.Width && state.DustHeight = state.Height
        return
    if !HappyHourDustPictures.Length
        return
    candidate := 0, graphics := 0, source := 0
    try
    {
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", state.Width, "Int", state.Height,
            "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &candidate))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", candidate, "Ptr*", &graphics))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7))
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\happy-hour\pixie-dust.png", "Ptr*", &source))
        origin := Buffer(16, 0), rect := Buffer(16, 0)
        if !DllCall("GetWindowRect", "Ptr", state.Background.Hwnd, "Ptr", origin)
            throw Error("Carousel dust origin unavailable.")
        ; Do not stack the four native impressions in an alpha-composited
        ; bitmap. Their overlapping translucent edges become wider/brighter.
        ; Use the first native picture's physical geometry for one impression.
        dust := HappyHourDustPictures[1]
        if !DllCall("GetWindowRect", "Ptr", dust.Hwnd, "Ptr", rect)
            throw Error("Carousel dust coordinates unavailable.")
        x := NumGet(rect, 0, "Int") - NumGet(origin, 0, "Int")
        y := NumGet(rect, 4, "Int") - NumGet(origin, 4, "Int")
        w := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
        h := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
        CheckLauncherCarouselGdi(DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", source,
            "Int", x, "Int", y, "Int", w, "Int", h))
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        graphics := 0
        ReleaseLauncherCarouselDustLayer(state)
        state.DustLayer := candidate, candidate := 0
        state.DustWidth := state.Width, state.DustHeight := state.Height
    }
    finally
    {
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        if source
            DllCall("gdiplus\GdipDisposeImage", "Ptr", source)
        if candidate
            DllCall("gdiplus\GdipDisposeImage", "Ptr", candidate)
    }
}

ReleaseLauncherCarouselDustLayer(state)
{
    if state.DustLayer
        DllCall("gdiplus\GdipDisposeImage", "Ptr", state.DustLayer)
    state.DustLayer := 0, state.DustWidth := 0, state.DustHeight := 0
}

ResetLauncherCarousel(state, resetElapsed := true)
{
    state.Active := false
    UpdateLauncherCarouselDustMode(state)
    state.TransparentRepair := false
    state.Current := 1, state.Next := 0, state.Fade := 0
    if resetElapsed
        state.Elapsed := 0
    if state.Snapshot
        DllCall("gdiplus\GdipDisposeImage", "Ptr", state.Snapshot)
    state.Snapshot := 0
    ReleaseLauncherCarouselShade(state)
    ReleaseLauncherCarouselFrames(state)
    SetTimer(TickLauncherCarousel, 250)
    RepaintLauncherCarouselRegion(state)
}

DisableLauncherCarousel(*)
{
    global LauncherCarousel
    if !IsObject(LauncherCarousel) || LauncherCarousel.Failed
        return
    state := LauncherCarousel
    state.Failed := true
    ResetLauncherCarousel(state)
    SetTimer(TickLauncherCarousel, 0)
    try LogLauncherEvent("UI | Play Together carousel disabled; original artwork retained.")
}

DisposeLauncherCarousel(*)
{
    global LauncherCarousel
    SetTimer(StartLauncherCarousel, 0)
    SetTimer(TickLauncherCarousel, 0)
    SetTimer(DisableLauncherCarousel, 0)
    if !IsObject(LauncherCarousel)
        return
    state := LauncherCarousel
    LauncherCarousel := 0
    if state.Callback
    {
        for control in state.Attached
            if DllCall("IsWindow", "Ptr", control.Hwnd)
                DllCall("comctl32\RemoveWindowSubclass", "Ptr", control.Hwnd, "Ptr", state.Callback, "UPtr", 1)
        CallbackFree(state.Callback)
    }
    if state.Snapshot
        DllCall("gdiplus\GdipDisposeImage", "Ptr", state.Snapshot)
    ReleaseLauncherCarouselShade(state)
    ReleaseLauncherCarouselDustLayer(state)
    ReleaseLauncherCarouselFrames(state)
}
