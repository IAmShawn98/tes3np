; Native buffered painting and GDI resource lifetime. Do not perform product actions here.

AttachButtonPainter(handle)
{
    global ButtonPaintCallback
    if !IsSet(ButtonPaintCallback)
        ButtonPaintCallback := CallbackCreate(ButtonWindowProc, "Fast", 6)
    DllCall("comctl32\SetWindowSubclass", "Ptr", handle, "Ptr", ButtonPaintCallback, "UPtr", 1, "UPtr", 0)
}

ButtonWindowProc(handle, message, wParam, lParam, subclassID, reference)
{
    if message = 0x000F
    {
        paint := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
        dc := DllCall("BeginPaint", "Ptr", handle, "Ptr", paint, "Ptr")
        try PaintButtonToDC(handle, dc)
        finally DllCall("EndPaint", "Ptr", handle, "Ptr", paint)
        return 0
    }
    if message = 0x0014
        return 1
    if message = 0x0318
    {
        PaintButtonToDC(handle, wParam)
        return 0
    }
    return DllCall("comctl32\DefSubclassProc", "Ptr", handle, "UInt", message, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

InitButtonPainter()
{
    global ButtonPaint
    if IsSet(ButtonPaint)
        return
    module := DllCall("LoadLibraryW", "WStr", "gdiplus.dll", "Ptr")
    if !module
        throw Error("Could not load the graphics library.")
    startup := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, startup)
    token := 0
    status := DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", startup, "Ptr", 0)
    if status != 0
    {
        DllCall("FreeLibrary", "Ptr", module)
        throw Error("Could not initialize the graphics library.")
    }
    artwork := 0, parchment := 0
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\controls\button.png", "Ptr*", &artwork)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\controls\scroll-panel.png", "Ptr*", &parchment)
    book := 0
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\backgrounds\character-book.png", "Ptr*", &book)
    background := 0, quest := 0, together := 0
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\backgrounds\launcher.png", "Ptr*", &background)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\headings\quest.png", "Ptr*", &quest)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\headings\together.png", "Ptr*", &together)
    ButtonPaint := {Background: background, Headings: Map("Quest", quest, "Together", together), Module: module, Disposed: false, Token: token, Artwork: artwork, Parchment: parchment, Book: book}
    OnMessage(0x002B, PaintButton)
    OnMessage(0x0014, KeepButtonBackground)
}

PaintButton(wParam, lParam, *)
{
    previousCritical := A_IsCritical
    Critical("On")
    try
    {
        global ButtonFaces, ButtonPaint, EnhancedReadability
        if ButtonPaint.Disposed
            return
        handle := NumGet(lParam, A_PtrSize = 8 ? 24 : 20, "Ptr")
        if !ButtonFaces.Has(handle)
            return
        face := ButtonFaces[handle]
        target := NumGet(lParam, A_PtrSize = 8 ? 32 : 24, "Ptr")
        rectOffset := A_PtrSize = 8 ? 40 : 28
        width := NumGet(lParam, rectOffset + 8, "Int") - NumGet(lParam, rectOffset, "Int")
        height := NumGet(lParam, rectOffset + 12, "Int") - NumGet(lParam, rectOffset + 4, "Int")
        if width <= 0 || height <= 0
            return
        if face.HasOwnProp("IsInfo")
            return PaintInfoCard(handle, target, width, height)
        if face.HasOwnProp("IsLoading")
            return PaintLoadingPanel(handle, target, width, height)
        scale := width / 220
        dc := DllCall("CreateCompatibleDC", "Ptr", target, "Ptr")
        bitmap := DllCall("CreateCompatibleBitmap", "Ptr", target, "Int", width, "Int", height, "Ptr")
        oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
        graphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", dc, "Ptr*", &graphics)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFFC6A369)
        if face.Book
        {
            face.Control.GetPos(, , &logicalWidth, &logicalHeight)
            dpiScale := width / logicalWidth
            DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Book, "Int", Round(-face.X * dpiScale), "Int", Round(-face.Y * dpiScale), "Int", Round(960 * dpiScale), "Int", Round(650 * dpiScale))
        }
        else
            DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Parchment, "Int", Round(-49 * scale), "Int", Round((372 - face.Y) * scale), "Int", Round(318 * scale), "Int", Round(305 * scale))
        shift := face.State = "down" ? 2 : 0
        isLabel := face.HasOwnProp("IsLabel")
        if !isLabel
        {
            if face.Book
                DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", graphics, "Ptr", ButtonPaint.Artwork, "Int", 0, "Int", shift, "Int", width, "Int", height - 2, "Int", 44, "Int", 171, "Int", 2086, "Int", 390, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
            else
                DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Artwork, "Int", 0, "Int", shift, "Int", width, "Int", height)

            ; Enhanced readability keeps the original art but substantially darkens
            ; the label plate. Hover/focus becomes deliberately brighter so keyboard
            ; navigation is obvious without changing the Morrowind visual language.
            if EnhancedReadability
                overlay := face.State = "down" ? 0xE0100803 : face.State = "hover" ? 0xB06A4518 : 0xC0180C04
            else
                overlay := face.State = "down" ? 0xA02B190A : face.State = "hover" ? 0x802B190A : 0x602B190A
            brush := 0
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", overlay, "Ptr*", &brush)
            DllCall("gdiplus\GdipFillRectangleI", "Ptr", graphics, "Ptr", brush, "Int", face.Book ? 1 : Round(5 * scale), "Int", (face.Book ? 1 : Round(12 * scale)) + shift, "Int", face.Book ? width - 2 : Round(210 * scale), "Int", face.Book ? height - 4 : Round(24 * scale))
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)

            if EnhancedReadability && face.State = "hover"
            {
                pen := 0
                DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFE9C875, "Float", 2.0, "Int", 2, "Ptr*", &pen)
                DllCall("gdiplus\GdipDrawRectangleI", "Ptr", graphics, "Ptr", pen, "Int", 1, "Int", 1 + shift, "Int", width - 3, "Int", height - 4)
                DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
            }
        }
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        font := DllCall("SendMessageW", "Ptr", handle, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        DllCall("SetBkMode", "Ptr", dc, "Int", 1)
        textColor := face.HasOwnProp("TextColor") ? face.TextColor : isLabel ? 0x142338 : EnhancedReadability ? 0xFFFFFF : 0xCDEBFF
        DllCall("SetTextColor", "Ptr", dc, "UInt", textColor)
        bounds := Buffer(16, 0)
        NumPut("Int", 2, "Int", shift, "Int", width - 2, "Int", height + shift, bounds)
        if face.HasOwnProp("IsTick")
        {
            pen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", 0x17304B, "Ptr")
            oldPen := DllCall("SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
            brush := DllCall("CreateSolidBrush", "UInt", 0x24476B, "Ptr")
            oldBrush := DllCall("SelectObject", "Ptr", dc, "Ptr", brush, "Ptr")
            DllCall("RoundRect", "Ptr", dc, "Int", 1, "Int", 1, "Int", width - 1, "Int", height - 1, "Int", 4, "Int", 4)
            if face.Checked
            {
                checkPen := DllCall("CreatePen", "Int", 0, "Int", 2, "UInt", 0x77D3F5, "Ptr")
                DllCall("SelectObject", "Ptr", dc, "Ptr", checkPen)
                DllCall("MoveToEx", "Ptr", dc, "Int", Round(width * 0.22), "Int", Round(height * 0.5), "Ptr", 0)
                DllCall("LineTo", "Ptr", dc, "Int", Round(width * 0.43), "Int", Round(height * 0.73))
                DllCall("LineTo", "Ptr", dc, "Int", Round(width * 0.8), "Int", Round(height * 0.25))
                DllCall("SelectObject", "Ptr", dc, "Ptr", pen)
                DllCall("DeleteObject", "Ptr", checkPen)
            }
            DllCall("SelectObject", "Ptr", dc, "Ptr", oldBrush)
            DllCall("DeleteObject", "Ptr", brush)
            DllCall("SelectObject", "Ptr", dc, "Ptr", oldPen)
            DllCall("DeleteObject", "Ptr", pen)
        }
        else
            DllCall("DrawTextW", "Ptr", dc, "WStr", face.Label.Text, "Int", -1, "Ptr", bounds, "UInt", isLabel ? 0x8820 : 0x825)
        DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", height, "Ptr", dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
        DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
        DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
        DllCall("DeleteObject", "Ptr", bitmap)
        DllCall("DeleteDC", "Ptr", dc)
        return true
    }
    finally Critical(previousCritical)
}

KeepButtonBackground(wParam, lParam, msg, hwnd)
{
    global ButtonFaces
    if ButtonFaces.Has(hwnd)
        return 1
}

PaintButtonNow(handle)
{
    if !DllCall("IsWindowVisible", "Ptr", handle)
        return
    dc := DllCall("GetDC", "Ptr", handle, "Ptr")
    if !dc
        return
    try PaintButtonToDC(handle, dc)
    finally DllCall("ReleaseDC", "Ptr", handle, "Ptr", dc)
}

PaintButtonToDC(handle, dc)
{
    global ButtonFaces
    if !dc || !ButtonFaces.Has(handle)
        return
    item := Buffer(A_PtrSize = 8 ? 64 : 48, 0)
    hwndOffset := A_PtrSize = 8 ? 24 : 20
    dcOffset := A_PtrSize = 8 ? 32 : 24
    rectOffset := A_PtrSize = 8 ? 40 : 28
    NumPut("Ptr", handle, item, hwndOffset)
    NumPut("Ptr", dc, item, dcOffset)
    DllCall("GetClientRect", "Ptr", handle, "Ptr", item.Ptr + rectOffset)
    PaintButton(0, item.Ptr)
}

DisposeButtonPainter(*)
{
    global ButtonPaint, ButtonPaintCallback, ButtonFaces
    if !IsSet(ButtonPaint) || ButtonPaint.Disposed
        return
    ButtonPaint.Disposed := true
    OnMessage(0x002B, PaintButton, 0)
    OnMessage(0x0014, KeepButtonBackground, 0)
    if IsSet(ButtonPaintCallback)
    {
        for handle, face in ButtonFaces
            if DllCall("IsWindow", "Ptr", handle)
                DllCall("comctl32\RemoveWindowSubclass", "Ptr", handle, "Ptr", ButtonPaintCallback, "UPtr", 1)
        CallbackFree(ButtonPaintCallback)
    }
    DllCall("gdiplus\GdipDisposeImage", "Ptr", ButtonPaint.Artwork)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", ButtonPaint.Parchment)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", ButtonPaint.Book)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", ButtonPaint.Background)
    for heading in ButtonPaint.Headings
        DllCall("gdiplus\GdipDisposeImage", "Ptr", ButtonPaint.Headings[heading])
    DllCall("gdiplus\GdiplusShutdown", "Ptr", ButtonPaint.Token)
    ButtonPaint.Token := 0
    DllCall("FreeLibrary", "Ptr", ButtonPaint.Module)
    ButtonPaint.Module := 0
}

PaintLoadingPanel(handle, target, width, height)
{
    global ButtonFaces
    dc := DllCall("CreateCompatibleDC", "Ptr", target, "Ptr")
    bitmap := DllCall("CreateCompatibleBitmap", "Ptr", target, "Int", width, "Int", height, "Ptr")
    oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
    scale := width / 320
    FillLoadingRect(dc, 0, 0, width, height, 0x5CA4C5)
    FillLoadingRect(dc, 2, 2, width - 2, height - 2, 0x071016)
    FillLoadingRect(dc, Round(14 * scale), Round(48 * scale), width - Round(14 * scale), Round(55 * scale), 0x5CA4C5)
    FillLoadingRect(dc, Round(15 * scale), Round(49 * scale), width - Round(15 * scale), Round(54 * scale), 0x1A3442)
    progress := Max(0, Min(1, ButtonFaces[handle].Progress))
    fillLeft := Round(15 * scale)
    fillRight := fillLeft + Round((width - 2 * fillLeft) * progress)
    if fillRight > fillLeft
        FillLoadingRect(dc, fillLeft, Round(49 * scale), fillRight, Round(54 * scale), 0xA1AB55)
    font := DllCall("SendMessageW", "Ptr", handle, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
    oldFont := DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
    DllCall("SetBkMode", "Ptr", dc, "Int", 1)
    DllCall("SetTextColor", "Ptr", dc, "UInt", 0x5CA4C5)
    rect := Buffer(16, 0)
    NumPut("Int", 8, "Int", Round(8 * scale), "Int", width - 8, "Int", Round(42 * scale), rect)
    DllCall("DrawTextW", "Ptr", dc, "WStr", ButtonFaces[handle].Control.Text, "Int", -1, "Ptr", rect, "UInt", 0x825)
    DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", height, "Ptr", dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
    DllCall("DeleteObject", "Ptr", bitmap)
    DllCall("DeleteDC", "Ptr", dc)
}

FillLoadingRect(dc, left, top, right, bottom, color)
{
    rect := Buffer(16, 0)
    NumPut("Int", left, "Int", top, "Int", right, "Int", bottom, rect)
    brush := DllCall("CreateSolidBrush", "UInt", color, "Ptr")
    DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", brush)
    DllCall("DeleteObject", "Ptr", brush)
}

PaintInfoCard(handle, target, width, height)
{
    global ButtonFaces
    dc := DllCall("CreateCompatibleDC", "Ptr", target, "Ptr")
    bitmap := DllCall("CreateCompatibleBitmap", "Ptr", target, "Int", width, "Int", height, "Ptr")
    oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
    FillLoadingRect(dc, 0, 0, width, height, 0x5CA4C5)
    FillLoadingRect(dc, 1, 1, width - 1, height - 1, 0x071016)
    font := DllCall("SendMessageW", "Ptr", handle, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
    oldFont := DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
    DllCall("SetBkMode", "Ptr", dc, "Int", 1)
    DllCall("SetTextColor", "Ptr", dc, "UInt", ButtonFaces[handle].HasOwnProp("TextColor") ? ButtonFaces[handle].TextColor : 0x5CA4C5)
    rect := Buffer(16, 0)
    NumPut("Int", 8, "Int", 6, "Int", width - 8, "Int", height - 6, rect)
    DllCall("DrawTextW", "Ptr", dc, "WStr", ButtonFaces[handle].Control.Text, "Int", -1, "Ptr", rect, "UInt", 0x810)
    DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", height, "Ptr", dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
    DllCall("DeleteObject", "Ptr", bitmap)
    DllCall("DeleteDC", "Ptr", dc)
}
