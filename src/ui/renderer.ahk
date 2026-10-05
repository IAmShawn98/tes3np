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
    artwork := 0, parchment := 0, book := 0, background := 0, quest := 0, together := 0
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\controls\button.png", "Ptr*", &artwork)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\controls\scroll-panel.png", "Ptr*", &parchment)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\backgrounds\character-book.png", "Ptr*", &book)
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
        if !handle || !ButtonFaces.Has(handle) || !DllCall("IsWindow", "Ptr", handle)
        {
            if handle && ButtonFaces.Has(handle)
                ButtonFaces.Delete(handle)
            return
        }
        face := ButtonFaces[handle]
        target := NumGet(lParam, A_PtrSize = 8 ? 32 : 24, "Ptr")
        rectOffset := A_PtrSize = 8 ? 40 : 28
        width := NumGet(lParam, rectOffset + 8, "Int") - NumGet(lParam, rectOffset, "Int")
        height := NumGet(lParam, rectOffset + 12, "Int") - NumGet(lParam, rectOffset + 4, "Int")
        if width <= 0 || height <= 0
            return
        if face.HasOwnProp("IsInfo")
            return PaintInfoCard(handle, target, width, height)
{
    global ButtonFaces, ButtonPaint
    face := ButtonFaces[handle]
    dc := DllCall("CreateCompatibleDC", "Ptr", target, "Ptr")
    bitmap := DllCall("CreateCompatibleBitmap", "Ptr", target, "Int", width, "Int", height, "Ptr")
    oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
    graphics := 0, brush := 0
    face.Control.GetPos(, , &logicalWidth)
    scale := width / logicalWidth
    DllCall("gdiplus\\GdipCreateFromHDC", "Ptr", dc, "Ptr*", &graphics)
    DllCall("gdiplus\\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
    DllCall("gdiplus\\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Background, "Int", Round(-face.X * scale), "Int", Round((-4 - face.Y) * scale), "Int", Round(960 * scale), "Int", Round(720 * scale))
    tile := Max(1, Round(4 * scale))
    y := 0
    while y < height
    {
        x := 0
        while x < width
        {
            edgeX := Min(1, (x + tile / 2) / (28 * scale), (width - x - tile / 2) / (28 * scale))
            edgeY := Min(1, (y + tile / 2) / (22 * scale), (height - y - tile / 2) / (38 * scale))
            alpha := Round(190 * Max(0, edgeX) * Max(0, edgeY))
            DllCall("gdiplus\\GdipCreateSolidFill", "UInt", (alpha << 24) | 0x191710, "Ptr*", &brush)
            DllCall("gdiplus\\GdipFillRectangle", "Ptr", graphics, "Ptr", brush, "Float", x, "Float", y, "Float", Min(tile, width - x), "Float", Min(tile, height - y))
            DllCall("gdiplus\\GdipDeleteBrush", "Ptr", brush)
            x += tile
        }
        y += tile
    }
    DllCall("gdiplus\\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Headings[face.Heading], "Int", Round(12 * scale), "Int", Round(3 * scale), "Int", Round(256 * scale), "Int", Round(85 * scale))
    DllCall("gdiplus\\GdipDeleteGraphics", "Ptr", graphics)
    font := DllCall("SendMessageW", "Ptr", handle, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
    oldFont := DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
    DllCall("SetBkMode", "Ptr", dc, "Int", 1)
    rect := Buffer(16, 0)
    NumPut("Int", Round(18 * scale), "Int", Round(82 * scale), "Int", width - Round(18 * scale), "Int", height - Round(16 * scale), rect)
    shadowRect := Buffer(16, 0)
    Loop 4
        NumPut("Int", NumGet(rect, (A_Index - 1) * 4, "Int") + Max(1, Round(scale)), shadowRect, (A_Index - 1) * 4)
    DllCall("SetTextColor", "Ptr", dc, "UInt", 0x080808)
    DllCall("DrawTextW", "Ptr", dc, "WStr", face.Control.Text, "Int", -1, "Ptr", shadowRect, "UInt", 0x810)
    DllCall("SetTextColor", "Ptr", dc, "UInt", 0xC5E2F2)
    DllCall("DrawTextW", "Ptr", dc, "WStr", face.Control.Text, "Int", -1, "Ptr", rect, "UInt", 0x810)
    DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", height, "Ptr", dc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
    DllCall("DeleteObject", "Ptr", bitmap)
    DllCall("DeleteDC", "Ptr", dc)
    return true
}
