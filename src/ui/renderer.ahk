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
    global ButtonFaces
    if message = 0x0002 ; WM_DESTROY, while the control HWND is still accessible
    {
        ; Closing a parent destroys its child HWNDs without calling the
        ; individual control helpers. Unregister before HWND reuse.
        if ButtonFaces.Has(handle)
            try UnregisterThemedControl(ButtonFaces[handle].Control)
    }
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
    if message = 0x0020 ; WM_SETCURSOR for our painted buttons
    {
        if ButtonFaces.Has(handle)
        {
            face := ButtonFaces[handle]
            if (!face.HasOwnProp("IsLabel") || face.HasOwnProp("IsTick") || face.HasOwnProp("IsClickable"))
                && face.Control.Enabled && face.Control.Visible
            {
                SetLauncherHandCursor()
                return 1
            }
        }
    }
    if message = 0x0318
    {
        PaintButtonToDC(handle, wParam)
        return 0
    }
    return DllCall("comctl32\DefSubclassProc", "Ptr", handle, "UInt", message, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

SetLauncherHandCursor()
{
    ; IDC_HAND (32649) is the standard Windows pointing cursor.
    hand := DllCall("user32\LoadCursorW", "Ptr", 0, "Ptr", 32649, "Ptr")
    if hand
        DllCall("user32\SetCursor", "Ptr", hand)
}

HandleNativeClickableCursor(wParam, lParam, msg, hwnd)
{
    ; Native buttons and links use the same hand cursor as painted buttons.
    if !wParam || !DllCall("IsWindow", "Ptr", wParam)
        || !DllCall("IsWindowEnabled", "Ptr", wParam)
        || !DllCall("IsWindowVisible", "Ptr", wParam)
        return
    classBuffer := Buffer(128, 0)
    if !DllCall("user32\GetClassNameW", "Ptr", wParam, "Ptr", classBuffer, "Int", 64, "Int")
        return
    className := StrGet(classBuffer, "UTF-16")
    if className = "Button" || className = "SysLink"
        || (className = "Static" && (IsMissedUpdateCursorTarget(wParam)
            || IsLauncherFooterUpdateCursorTarget(wParam)))
    {
        SetLauncherHandCursor()
        return 1
    }
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
    artwork := 0, parchment := 0, book := 0, background := 0, quest := 0, together := 0, discordLogo := 0
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\controls\button.png", "Ptr*", &artwork)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\controls\scroll-panel.png", "Ptr*", &parchment)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\backgrounds\character-book.png", "Ptr*", &book)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\backgrounds\launcher.png", "Ptr*", &background)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\headings\quest.png", "Ptr*", &quest)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\headings\together.png", "Ptr*", &together)
    DllCall("gdiplus\GdipLoadImageFromFile", "WStr", A_ScriptDir "\assets\icons\discord.png", "Ptr*", &discordLogo)
    ButtonPaint := {Background: background, Headings: Map("Quest", quest, "Together", together), Module: module, Disposed: false, Token: token, Artwork: artwork, Parchment: parchment, Book: book, BookExtended: 0, DiscordLogo: discordLogo}
    OnMessage(0x002B, PaintButton)
    OnMessage(0x0014, KeepButtonBackground)
    OnMessage(0x0020, HandleNativeClickableCursor)
}

; Insert mirrored strips in the straight middle of the existing Book.
; The observed right-hand parchment begins its triangular footer below
; this band. All original pixels, including corners, spine and triangle,
; remain in their original order; no decorative region is stretched.
CreateExtendedBookArtwork(source, extra)
{
    if !source || extra <= 0
        throw Error("An original book and positive extension are required.")
    width := 0, height := 0
    if DllCall("gdiplus\GdipGetImageWidth", "Ptr", source, "UInt*", &width)
        || DllCall("gdiplus\GdipGetImageHeight", "Ptr", source, "UInt*", &height)
        || width < 1 || height < 1
        throw Error("Could not read the original Book artwork.")
    seam := Round(height * 340 / 650)
    band := Max(1, Round(height * 80 / 650))
    added := 2 * Ceil(extra * height / 1300)
    result := 0, sourceLocked := false, targetLocked := false
    sourceData := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
    targetData := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
    sourceRect := Buffer(16, 0), targetRect := Buffer(16, 0)
    NumPut("Int", width, "Int", height, sourceRect, 8)
    NumPut("Int", width, "Int", height + added, targetRect, 8)
    try
    {
        if DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", width,
            "Int", height + added, "Int", 0, "Int", 0x26200A,
            "Ptr", 0, "Ptr*", &result) || !result
            throw Error("Could not allocate extended Book artwork.")
        ; Lock both bitmaps as straight 32-bit ARGB. GDI+ DrawImage can
        ; change pixels through interpolation/compositing even at 1:1.
        ; Copy exact scanlines, including the original alpha channel.
        if DllCall("gdiplus\GdipBitmapLockBits", "Ptr", source,
            "Ptr", sourceRect, "UInt", 1, "Int", 0x26200A, "Ptr", sourceData)
            throw Error("Could not lock original Book pixels.")
        sourceLocked := true
        if DllCall("gdiplus\GdipBitmapLockBits", "Ptr", result,
            "Ptr", targetRect, "UInt", 2, "Int", 0x26200A, "Ptr", targetData)
            throw Error("Could not lock extended Book pixels.")
        targetLocked := true
        sourceStride := NumGet(sourceData, 8, "Int")
        targetStride := NumGet(targetData, 8, "Int")
        sourceScan := NumGet(sourceData, 16, "Ptr")
        targetScan := NumGet(targetData, 16, "Ptr")
        if !sourceScan || !targetScan || Abs(sourceStride) < width * 4
            || Abs(targetStride) < width * 4
            throw Error("Invalid Book pixel buffer.")
        CopyBookPixelRows(sourceScan, sourceStride, targetScan, targetStride,
            width, 0, 0, seam)
        dest := seam, remaining := added
        while remaining
        {
            half := Min(band, remaining // 2)
            CopyBookPixelRows(sourceScan, sourceStride, targetScan, targetStride,
                width, seam - 1, dest, half, -1)
            CopyBookPixelRows(sourceScan, sourceStride, targetScan, targetStride,
                width, seam - half, dest + half, half)
            dest += 2 * half, remaining -= 2 * half
        }
        CopyBookPixelRows(sourceScan, sourceStride, targetScan, targetStride,
            width, seam, dest, height - seam)
        status := DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", result, "Ptr", targetData)
        targetLocked := false
        if status
            throw Error("Could not unlock extended Book pixels.")
        status := DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", source, "Ptr", sourceData)
        sourceLocked := false
        if status
            throw Error("Could not unlock original Book pixels.")
        image := result
        result := 0
        return image
    }
    finally
    {
        if targetLocked
            DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", result, "Ptr", targetData)
        if sourceLocked
            DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", source, "Ptr", sourceData)
        if result
            DllCall("gdiplus\GdipDisposeImage", "Ptr", result)
    }
}

CopyBookPixelRows(source, sourceStride, target, targetStride,
    width, sourceY, targetY, count, direction := 1)
{
    Loop count
    {
        offset := A_Index - 1
        DllCall("ntdll\RtlMoveMemory",
            "Ptr", target + (targetY + offset) * targetStride,
            "Ptr", source + (sourceY + offset * direction) * sourceStride,
            "UPtr", width * 4)
    }
}

; The Picture control and owner-drawn controls must share ONE composed
; image. The temporary PNG is only a native Picture loading mechanism;
; it is deleted immediately and never enters launcher data or the package.
; Prepare color-key edges once, on the existing Picture load path.
; Resample transparent artwork first, then threshold coverage natively.
; No AHK pixel loop, new window subclass or image work during WM_PAINT.
CreateKeyedReducedBookImage(source, width, height)
{
    sw := 0, sh := 0, sampled := 0, graphics := 0, attrs := 0
    try
    {
        if width < 1 || height < 1
            || DllCall("gdiplus\GdipGetImageWidth", "Ptr", source, "UInt*", &sw)
            || DllCall("gdiplus\GdipGetImageHeight", "Ptr", source, "UInt*", &sh)
            || !sw || !sh
            throw Error("Invalid Book image dimensions.")
        if DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", width,
            "Int", height, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &sampled)
            || DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", sampled, "Ptr*", &graphics)
            || DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &attrs)
            throw Error("Could not prepare reduced Book image.")
        if DllCall("gdiplus\GdipSetCompositingMode", "Ptr", graphics, "Int", 1)
            || DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
            || DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", graphics, "Int", 4)
            || DllCall("gdiplus\GdipSetImageAttributesColorKeys", "Ptr", attrs,
                "Int", 1, "Int", 1, "UInt", 0xFFFF00FF, "UInt", 0xFFFF00FF)
            || DllCall("gdiplus\GdipSetImageAttributesWrapMode", "Ptr", attrs,
                "Int", 3, "UInt", 0, "Int", 0)
            || DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0)
            || DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", graphics, "Ptr", source,
                "Int", 0, "Int", 0, "Int", width, "Int", height,
                "Int", 0, "Int", 0, "Int", sw, "Int", sh, "Int", 2,
                "Ptr", attrs, "Ptr", 0, "Ptr", 0)
            throw Error("Could not resample Book artwork.")
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        graphics := 0
        DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", attrs)
        attrs := 0
        KeyReducedBookPixels(sampled, width, height)
        result := sampled
        sampled := 0
        return result
    }
    finally
    {
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        if attrs
            DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", attrs)
        if sampled
            DllCall("gdiplus\GdipDisposeImage", "Ptr", sampled)
    }
}

; Operate on straight ARGB after resampling, before the native Picture loads.
; The layered window needs a binary color key, not partial alpha blended
; onto magenta. Convert each physical pixel exactly once, outside WM_PAINT.
KeyReducedBookPixels(image, width, height)
{
    rect := Buffer(16, 0), data := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
    NumPut("Int", width, "Int", height, rect, 8)
    if DllCall("gdiplus\GdipBitmapLockBits", "Ptr", image, "Ptr", rect,
        "UInt", 3, "Int", 0x26200A, "Ptr", data)
        throw Error("Could not lock reduced Book pixels.")
    try
    {
        stride := NumGet(data, 8, "Int"), scan := NumGet(data, 16, "Ptr")
        if !scan || Abs(stride) < width * 4
            throw Error("Invalid reduced Book pixel buffer.")
        Loop height
        {
            row := scan + (A_Index - 1) * stride
            Loop width
            {
                offset := (A_Index - 1) * 4
                pixel := NumGet(row, offset, "UInt")
                if (pixel >> 24) < 128
                    NumPut("UInt", 0xFFFF00FF, row, offset)
                else if (pixel >> 24) != 255
                    NumPut("UInt", pixel | 0xFF000000, row, offset)
            }
        }
    }
    finally
    {
        if DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", image, "Ptr", data)
            throw Error("Could not unlock reduced Book pixels.")
    }
}

TryLoadReducedBookPicture(page, source)
{
    if !page.HasOwnProp("OwnedContentScale") || page.OwnedContentScale >= 0.999
        return false
    rect := Buffer(16, 0)
    if !DllCall("GetClientRect", "Ptr", page.BookBackground.Hwnd, "Ptr", rect)
        return false
    width := NumGet(rect, 8, "Int"), height := NumGet(rect, 12, "Int")
    image := 0, temporary := A_Temp "\tes3np-book-keyed-" NewLauncherFileId() ".png"
    try
    {
        image := CreateKeyedReducedBookImage(source, width, height)
        encoder := Buffer(16, 0)
        if DllCall("ole32\CLSIDFromString",
            "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", encoder)
            || DllCall("gdiplus\GdipSaveImageToFile", "Ptr", image,
                "WStr", temporary, "Ptr", encoder, "Ptr", 0)
            throw Error("Could not encode reduced Book artwork.")
        page.BookBackground.Value := temporary
        return true
    }
    catch Error
    {
        ; Preserve the established native Picture fallback.
        return false
    }
    finally
    {
        if image
            DllCall("gdiplus\GdipDisposeImage", "Ptr", image)
        if FileExist(temporary)
            try FileDelete(temporary)
    }
}

; Use the actual native Picture's physical bounds for all reduced Book
; faces. In particular, a 7px tick and a 173px name must not derive
; different DPI multipliers from separately rounded widths.
ReducedBookPictureBounds(page, handle)
{
    if !page.HasOwnProp("OwnedContentScale") || page.OwnedContentScale >= 0.999
        || !page.HasOwnProp("BookBackground")
        return 0
    picture := page.BookBackground.Hwnd
    rect := Buffer(16, 0), origin := Buffer(8, 0)
    if !DllCall("GetClientRect", "Ptr", picture, "Ptr", rect)
        return 0
    DllCall("MapWindowPoints", "Ptr", handle, "Ptr", picture, "Ptr", origin, "UInt", 1)
    width := NumGet(rect, 8, "Int"), height := NumGet(rect, 12, "Int")
    if width < 1 || height < 1
        return 0
    return {Picture: picture, X: NumGet(origin, 0, "Int"),
        Y: NumGet(origin, 4, "Int"), Width: width, Height: height}
}

; The existing native STATIC owns this bitmap. Borrow it for one BitBlt;
; never select it permanently, delete it, or change the Picture procedure.
CopyNativeBookPictureSlice(bounds, target, width, height)
{
    if !IsObject(bounds) || bounds.X < 0 || bounds.Y < 0
        || bounds.X + width > bounds.Width || bounds.Y + height > bounds.Height
        return false
    bitmap := DllCall("SendMessageW", "Ptr", bounds.Picture, "UInt", 0x0173,
        "Ptr", 0, "Ptr", 0, "Ptr") ; STM_GETIMAGE, IMAGE_BITMAP
    definition := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
    if !bitmap || !DllCall("gdi32\GetObjectW", "Ptr", bitmap,
        "Int", definition.Size, "Ptr", definition, "Int")
        || NumGet(definition, 4, "Int") != bounds.Width
        || Abs(NumGet(definition, 8, "Int")) != bounds.Height
        return false
    dc := DllCall("CreateCompatibleDC", "Ptr", target, "Ptr")
    if !dc
        return false
    oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
    try
    {
        if !oldBitmap || oldBitmap = -1
            return false
        return DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0,
            "Int", width, "Int", height, "Ptr", dc, "Int", bounds.X,
            "Int", bounds.Y, "UInt", 0xCC0020, "Int") != 0
    }
    finally
    {
        if oldBitmap && oldBitmap != -1
            DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
        DllCall("DeleteDC", "Ptr", dc)
    }
}

ApplyExtendedBookArtwork(page, extra)
{
    global ButtonPaint
    InitButtonPainter()
    oldImage := ButtonPaint.BookExtended
    oldExtra := page.HasOwnProp("BookExtra") ? page.BookExtra : 0
    if !extra
    {
        page.BookBackground.Move(, , BookS(960), BookS(650))
        if !TryLoadReducedBookPicture(page, ButtonPaint.Book)
            page.BookBackground.Value := A_ScriptDir "\assets\backgrounds\character-book.png"
        page.BookExtra := 0
        ButtonPaint.BookExtended := 0
        if oldImage
            DllCall("gdiplus\GdipDisposeImage", "Ptr", oldImage)
        return
    }
    candidate := 0, temporary := A_Temp "\tes3np-book-" NewLauncherFileId() ".png"
    try
    {
        candidate := CreateExtendedBookArtwork(ButtonPaint.Book, extra)
        encoder := Buffer(16, 0)
        if DllCall("ole32\CLSIDFromString",
            "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", encoder)
            || DllCall("gdiplus\GdipSaveImageToFile", "Ptr", candidate,
                "WStr", temporary, "Ptr", encoder, "Ptr", 0)
            throw Error("Could not encode extended Book artwork.")
        ; The image is ready before changing the visible Picture rectangle.
        page.BookBackground.Move(, , BookS(960), BookS(650 + extra))
        if !TryLoadReducedBookPicture(page, candidate)
            page.BookBackground.Value := temporary
        page.BookExtra := extra
        ButtonPaint.BookExtended := candidate
        candidate := 0
        if oldImage
            DllCall("gdiplus\GdipDisposeImage", "Ptr", oldImage)
    }
    catch Error as err
    {
        page.BookBackground.Move(, , BookS(960), BookS(650 + oldExtra))
        throw err
    }
    finally
    {
        if candidate
            DllCall("gdiplus\GdipDisposeImage", "Ptr", candidate)
        if FileExist(temporary)
            try FileDelete(temporary)
    }
}

PaintButton(wParam, lParam, *)
{
    previousCritical := A_IsCritical
    Critical("On")
    try
    {
        global ButtonFaces, ButtonPaint, EnhancedReadability, LauncherScale, LauncherDiscordStatus
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
        if face.HasOwnProp("IsLoading")
            return PaintLoadingPanel(handle, target, width, height)
        isLabel := face.HasOwnProp("IsLabel")
        isChatTab := face.HasOwnProp("IsChatTab")
        isDiscordName := face.HasOwnProp("IsDiscordName")
        isDiscordPortrait := face.HasOwnProp("IsDiscordPortrait")
        labelText := ""
        if !face.HasOwnProp("IsTick")
        {
            ; Resolve control-backed text before allocating any GDI resources.
            ; Controls can be destroyed while a queued paint is unwinding.
            if !DllCall("IsWindow", "Ptr", handle)
            {
                ButtonFaces.Delete(handle)
                return
            }
            try labelText := face.Label.Text
            catch
            {
                if ButtonFaces.Has(handle)
                    ButtonFaces.Delete(handle)
                return
            }
        }
        if isLabel && face.HasOwnProp("AccessibleWrappedName")
            && face.AccessibleWrappedName && face.HasOwnProp("AccessibleNameText")
            labelText := face.AccessibleNameText
        scale := width / 220
        visibleHeight := height
        ; Paint the original full-height artwork and caption, then copy only
        ; the portion owned by the shorter first-button window.
        if face.HasOwnProp("TopPadding") && face.TopPadding
            height := Max(visibleHeight, Round(face.BaseHeight * scale))
        paintTop := height - visibleHeight
        dc := DllCall("CreateCompatibleDC", "Ptr", target, "Ptr")
        bitmap := DllCall("CreateCompatibleBitmap", "Ptr", target, "Int", width, "Int", height, "Ptr")
        oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
        reducedBounds := 0, nativeSlice := false
        if !isChatTab && !isDiscordName && !isDiscordPortrait && face.HasOwnProp("Book") && face.Book
        {
            reducedBounds := ReducedBookPictureBounds(face.Gui, handle)
            nativeSlice := CopyNativeBookPictureSlice(reducedBounds, dc, width, height)
        }
        graphics := 0
        DllCall("gdiplus\GdipCreateFromHDC", "Ptr", dc, "Ptr*", &graphics)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
        if !nativeSlice
            DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0xFFC6A369)
        if isChatTab || isDiscordName || isDiscordPortrait
            PaintLauncherBackgroundSlice(graphics, face.X, face.Y, (A_ScreenDPI / 96) * LauncherScale / 100)
        else if face.Book && !nativeSlice
        {
            face.Control.GetPos(&logicalX, &logicalY, &logicalWidth, &logicalHeight)
            dpiScale := width / logicalWidth
            x := face.X, y := face.Y, bookWidth := 960, bookHeight := 650
            extended := face.Gui.HasOwnProp("BookExtra") && face.Gui.BookExtra
                && ButtonPaint.BookExtended
            if face.HasOwnProp("UseControlPosition") || extended
            {
                x := logicalX, y := logicalY
                face.Gui.BookBackground.GetPos(, , &bookWidth, &bookHeight)
            }
            bookImage := extended ? ButtonPaint.BookExtended : ButtonPaint.Book
            if IsObject(reducedBounds)
                DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", bookImage,
                    "Int", -reducedBounds.X, "Int", -reducedBounds.Y,
                    "Int", reducedBounds.Width, "Int", reducedBounds.Height)
            else
                DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", bookImage, "Int", Round(-x * dpiScale), "Int", Round(-y * dpiScale), "Int", Round(bookWidth * dpiScale), "Int", Round(bookHeight * dpiScale))
        }
        else if !nativeSlice
            DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Parchment, "Int", Round(-49 * scale), "Int", Round((372 - face.Y) * scale), "Int", Round(318 * scale), "Int", Round(305 * scale))
        shift := face.State = "down" ? 2 : 0
        if isDiscordPortrait
            PaintLauncherDiscordPortrait(graphics, face, width, height)
        else if !isDiscordName && !isLabel
            PaintButtonArtwork(graphics, face, width, height, shift)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        font := DllCall("SendMessageW", "Ptr", handle, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        oldFont := DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        DllCall("SetBkMode", "Ptr", dc, "Int", 1)
        fitLabel := isDiscordName ? LauncherDiscordStatus = 0 : !isLabel && !isChatTab && !isDiscordPortrait
        ; When the actual Character Book row has reflowed to its measured
        ; accessible button widths, never shrink the requested font back down.
        if face.HasOwnProp("NoAccessibleDownfit") && face.NoAccessibleDownfit
            fitLabel := false
        fittedFont := fitLabel && labelText != "" && font
            ? FitButtonLabelFont(dc, font, labelText, Max(1, width - 4), Max(1, height - 2)) : 0
        if fittedFont
            DllCall("SelectObject", "Ptr", dc, "Ptr", fittedFont, "Ptr")
        textColor := face.HasOwnProp("TextColor") ? face.TextColor : isLabel ? 0x142338 : EnhancedReadability ? 0xFFFFFF : 0xCDEBFF
        DllCall("SetTextColor", "Ptr", dc, "UInt", textColor)
        bounds := Buffer(16, 0)
        NumPut("Int", 2, "Int", shift, "Int", width - 2, "Int", height + shift, bounds)
        if isChatTab
            PaintLauncherChatTab(dc, width, height, labelText, textColor, shift)
        else if isDiscordName
        {
            ; A shadow keeps the right-aligned name legible on the stone artwork.
            DllCall("SetTextColor", "Ptr", dc, "UInt", 0)
            NumPut("Int", 3, "Int", shift + 1, "Int", width - 1, "Int", height + shift + 1, bounds)
            DllCall("DrawTextW", "Ptr", dc, "WStr", labelText, "Int", -1, "Ptr", bounds, "UInt", 0x8826)
            DllCall("SetTextColor", "Ptr", dc, "UInt", face.State = "hover" && face.Control.Enabled ? 0x75D3FF : textColor)
            NumPut("Int", 2, "Int", shift, "Int", width - 2, "Int", height + shift, bounds)
            DllCall("DrawTextW", "Ptr", dc, "WStr", labelText, "Int", -1, "Ptr", bounds, "UInt", 0x8826)
        }
        else if !isDiscordPortrait && face.HasOwnProp("IsTick")
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
        else if !isDiscordPortrait
        {
            ; Normal themed names retain their approved single-line painter.
            ; Reflowed long names must actually WRAP at the measured width,
            ; never use DT_SINGLELINE/DT_END_ELLIPSIS in their taller bounds.
            drawFlags := isLabel ? 0x8820 : 0x8825
            if isLabel && face.HasOwnProp("AccessibleWrappedName")
                && face.AccessibleWrappedName
                drawFlags := 0x0810 ; DT_NOPREFIX | DT_WORDBREAK
            else if !isLabel && face.HasOwnProp("AccessibleWrappedButton")
                && face.AccessibleWrappedButton
            {
                ; DT_CENTER | DT_NOPREFIX | DT_WORDBREAK; center the
                ; entire measured multiline caption in its expanded face.
                drawFlags := 0x0811
                measuredBounds := Buffer(16, 0)
                NumPut("Int", 2, "Int", 0, "Int", width - 2, "Int", 0, measuredBounds)
                textHeight := DllCall("DrawTextW", "Ptr", dc, "WStr", labelText,
                    "Int", -1, "Ptr", measuredBounds, "UInt", drawFlags | 0x400)
                NumPut("Int", Max(0, (height - textHeight) // 2) + shift, bounds, 4)
            }
            DllCall("DrawTextW", "Ptr", dc, "WStr", labelText, "Int", -1,
                "Ptr", bounds, "UInt", drawFlags)
        }
        DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", visibleHeight, "Ptr", dc, "Int", 0, "Int", paintTop, "UInt", 0xCC0020)
        DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
        if fittedFont
            DllCall("DeleteObject", "Ptr", fittedFont)
        DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
        DllCall("DeleteObject", "Ptr", bitmap)
        DllCall("DeleteDC", "Ptr", dc)
        return true
    }
    finally Critical(previousCritical)
}

PaintButtonArtwork(graphics, face, width, height, shift)
{
    global ButtonPaint, EnhancedReadability
    scale := width / 220
    if face.Book
        DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", graphics, "Ptr", ButtonPaint.Artwork, "Int", 0, "Int", shift, "Int", width, "Int", height, "Int", 44, "Int", 171, "Int", 2086, "Int", 390, "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)
    else
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Artwork, "Int", 0, "Int", shift, "Int", width, "Int", height)
    overlay := EnhancedReadability ? (face.State = "down" ? 0xE0100803 : face.State = "hover" ? 0xB06A4518 : 0xC0180C04) : (face.State = "down" ? 0xA02B190A : face.State = "hover" ? 0x802B190A : 0x602B190A)
    selectedMacro := face.HasOwnProp("MacroSelected") && face.MacroSelected
    if selectedMacro
        overlay := 0xA0583719
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", overlay, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillRectangleI", "Ptr", graphics, "Ptr", brush, "Int", face.Book ? 1 : Round(5 * scale), "Int", (face.Book ? 1 : Round(12 * scale)) + shift, "Int", face.Book ? width - 2 : Round(210 * scale), "Int", face.Book ? height - 4 : Round(24 * scale))
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    if selectedMacro
    {
        selectionPen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFE6C17B,
            "Float", 1.4, "Int", 2, "Ptr*", &selectionPen)
        DllCall("gdiplus\GdipDrawRectangleI", "Ptr", graphics,
            "Ptr", selectionPen, "Int", 1, "Int", 1 + shift,
            "Int", width - 3, "Int", height - 4)
        DllCall("gdiplus\GdipDeletePen", "Ptr", selectionPen)
    }
    if EnhancedReadability && face.State = "hover"
    {
        pen := 0
        DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFE9C875, "Float", 2.0, "Int", 2, "Ptr*", &pen)
        DllCall("gdiplus\GdipDrawRectangleI", "Ptr", graphics, "Ptr", pen, "Int", 1, "Int", 1 + shift, "Int", width - 3, "Int", height - 4)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }
}

FitButtonLabelFont(dc, font, text, maxWidth, maxHeight)
{
    extent := Buffer(8, 0)
    if !DllCall("gdi32\GetTextExtentPoint32W", "Ptr", dc, "WStr", text,
        "Int", StrLen(text), "Ptr", extent)
        return 0
    width := NumGet(extent, 0, "Int"), height := NumGet(extent, 4, "Int")
    ratio := Min(maxWidth / Max(1, width), maxHeight / Max(1, height))
    return ratio < 1 ? CopyLabelFontAtScale(font, ratio) : 0
}

CopyLabelFontAtScale(font, ratio)
{
    definition := Buffer(92, 0) ; LOGFONTW
    if DllCall("gdi32\GetObjectW", "Ptr", font, "Int", definition.Size, "Ptr", definition, "Int") < 92
        return 0
    height := NumGet(definition, 0, "Int")
    if !height
        return 0
    NumPut("Int", (height < 0 ? -1 : 1) * Max(1, Floor(Abs(height) * ratio)), definition, 0)
    NumPut("Int", 0, definition, 4)
    return DllCall("gdi32\CreateFontIndirectW", "Ptr", definition, "Ptr")
}

FitWrappedLabelFont(dc, font, text, bounds)
{
    if !font
        return 0
    measured := Buffer(16, 0)
    candidate := 0
    try
    {
        Loop 10
        {
            Loop 4
                NumPut("Int", NumGet(bounds, (A_Index - 1) * 4, "Int"), measured, (A_Index - 1) * 4)
            DllCall("user32\DrawTextW", "Ptr", dc, "WStr", text, "Int", -1, "Ptr", measured, "UInt", 0xC10)
            if NumGet(measured, 8, "Int") <= NumGet(bounds, 8, "Int")
                && NumGet(measured, 12, "Int") <= NumGet(bounds, 12, "Int")
                return candidate
            if A_Index = 10
                break
            DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
            if candidate
                DllCall("DeleteObject", "Ptr", candidate)
            candidate := CopyLabelFontAtScale(font, 1 - A_Index * 0.055)
            if !candidate
                return 0
            DllCall("SelectObject", "Ptr", dc, "Ptr", candidate, "Ptr")
        }
    }
    finally DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
    if candidate
        DllCall("DeleteObject", "Ptr", candidate)
    return 0
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

SetPaintedLabelText(label, text)
{
    handle := label.Hwnd
    previousCritical := Critical("On")
    try
    {
        ; A static control can paint its native background during WM_SETTEXT.
        ; Suppress that paint so the book's color key never exposes the launcher.
        DllCall("SendMessageW", "Ptr", handle, "UInt", 0x000B, "Ptr", 0, "Ptr", 0, "Ptr")
        try DllCall("SetWindowTextW", "Ptr", handle, "WStr", text, "Int")
        finally
            DllCall("SendMessageW", "Ptr", handle, "UInt", 0x000B, "Ptr", 1, "Ptr", 0, "Ptr")
        ; RDW_INVALIDATE | RDW_NOERASE | RDW_UPDATENOW.
        DllCall("RedrawWindow", "Ptr", handle, "Ptr", 0, "Ptr", 0, "UInt", 0x0121)
    }
    finally Critical(previousCritical)
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
    OnMessage(0x0020, HandleNativeClickableCursor, 0)
    if IsSet(ButtonPaintCallback)
    {
        for handle, face in ButtonFaces
            if DllCall("IsWindow", "Ptr", handle)
                DllCall("comctl32\RemoveWindowSubclass", "Ptr", handle, "Ptr", ButtonPaintCallback, "UPtr", 1)
        CallbackFree(ButtonPaintCallback)
    }
    for image in [ButtonPaint.Artwork, ButtonPaint.Parchment, ButtonPaint.Book, ButtonPaint.BookExtended, ButtonPaint.Background, ButtonPaint.DiscordLogo]
        if image
            DllCall("gdiplus\GdipDisposeImage", "Ptr", image)
    for heading in ButtonPaint.Headings
        DllCall("gdiplus\GdipDisposeImage", "Ptr", ButtonPaint.Headings[heading])
    DllCall("gdiplus\GdiplusShutdown", "Ptr", ButtonPaint.Token)
    DllCall("FreeLibrary", "Ptr", ButtonPaint.Module)
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
    paintFace := ButtonFaces[handle]
    loadingText := paintFace.HasOwnProp("ProgressText") ? paintFace.ProgressText : paintFace.Control.Text
    fittedFont := 0
    if paintFace.HasOwnProp("ProgressText")
    {
        fittedFont := FitWrappedLabelFont(dc, font, loadingText, rect)
        if fittedFont
            DllCall("SelectObject", "Ptr", dc, "Ptr", fittedFont, "Ptr")
        measured := Buffer(16, 0)
        NumPut("Int", 8, "Int", Round(8 * scale), "Int", width - 8, "Int", Round(42 * scale), measured)
        textHeight := DllCall("DrawTextW", "Ptr", dc, "WStr", loadingText, "Int", -1,
            "Ptr", measured, "UInt", 0xC10) ; DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX
        top := NumGet(rect, 4, "Int")
        NumPut("Int", top + Max(0, (NumGet(rect, 12, "Int") - top - textHeight) // 2), rect, 4)
        DllCall("DrawTextW", "Ptr", dc, "WStr", loadingText, "Int", -1, "Ptr", rect, "UInt", 0x811)
    }
    else
        DllCall("DrawTextW", "Ptr", dc, "WStr", loadingText, "Int", -1, "Ptr", rect, "UInt", 0x825)
    ; The automatic ZIP downloader keeps its Cancel button inside this ONE
    ; full-height native panel. PaintButtonNow uses GetDC + BitBlt, so simply
    ; setting WS_CLIPSIBLINGS on two sibling HWNDs does not protect the
    ; button from a parent blit. Clip the button's *actual screen rectangle*
    ; out of the target DC, then restore the original clip. Other native
    ; loading cards have no ProtectedButtonHwnd and render unchanged.
    savedTargetClip := 0
    protectedButton := ButtonFaces[handle].HasOwnProp("ProtectedButtonHwnd")
        ? ButtonFaces[handle].ProtectedButtonHwnd : 0
    if protectedButton && DllCall("IsWindow", "Ptr", protectedButton)
    {
        buttonRect := Buffer(16, 0)
        if DllCall("GetWindowRect", "Ptr", protectedButton, "Ptr", buttonRect)
        {
            ; A RECT is two POINT structures; map both screen corners to
            ; the loading panel's client pixel coordinates.
            DllCall("MapWindowPoints", "Ptr", 0, "Ptr", handle, "Ptr", buttonRect, "UInt", 2)
            savedTargetClip := DllCall("SaveDC", "Ptr", target, "Int")
            if savedTargetClip
                DllCall("ExcludeClipRect", "Ptr", target,
                    "Int", NumGet(buttonRect, 0, "Int"), "Int", NumGet(buttonRect, 4, "Int"),
                    "Int", NumGet(buttonRect, 8, "Int"), "Int", NumGet(buttonRect, 12, "Int"))
        }
    }
    ; On download progress ticks, only the top original loading-header
    ; height changes. Never blit the overlapping Cancel/footer pixels, nor
    ; invalidate them through SetWindowText. Full WM_PAINT still repaints the
    ; full card when Windows actually exposes/resizes it.
    blitHeight := paintFace.HasOwnProp("ProgressHeaderOnly") && paintFace.ProgressHeaderOnly
        ? Min(height, Round(68 * scale)) : height
    try DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", blitHeight, "Ptr", dc, "Int", 0, "Int", 0, "UInt", 0xCC0020)
    finally
        if savedTargetClip
            DllCall("RestoreDC", "Ptr", target, "Int", savedTargetClip)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
    if fittedFont
        DllCall("DeleteObject", "Ptr", fittedFont)
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

PaintLauncherBackgroundSlice(graphics, x, y, scale)
{
    global ButtonPaint
    DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Background, "Int", Round(-x * scale), "Int", Round((-4 - y) * scale), "Int", Round(960 * scale), "Int", Round(720 * scale))
}

; Info cards deliberately retain their original artwork-integrated renderer.
; Accessibility contrast applies only to interactive controls, never these cards.
PaintInfoCard(handle, target, width, height)
{
    global ButtonFaces, ButtonPaint
    face := ButtonFaces[handle]
    dc := DllCall("CreateCompatibleDC", "Ptr", target, "Ptr")
    bitmap := DllCall("CreateCompatibleBitmap", "Ptr", target, "Int", width, "Int", height, "Ptr")
    oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
    graphics := 0, brush := 0
    ; Render from the card's original 96-DPI dimensions so the physical
    ; paint scale includes both Windows DPI and tes3np's launcher scale.
    scale := width / face.BaseWidth
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", dc, "Ptr*", &graphics)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
    PaintLauncherBackgroundSlice(graphics, face.X, face.Y, scale)
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
            DllCall("gdiplus\GdipCreateSolidFill", "UInt", (alpha << 24) | 0x191710, "Ptr*", &brush)
            DllCall("gdiplus\GdipFillRectangle", "Ptr", graphics, "Ptr", brush, "Float", x, "Float", y, "Float", Min(tile, width - x), "Float", Min(tile, height - y))
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
            x += tile
        }
        y += tile
    }
    DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", ButtonPaint.Headings[face.Heading], "Int", Round(8 * scale), "Int", Round(3 * scale), "Int", Round(264 * scale), "Int", Round(85 * scale))
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
    font := DllCall("SendMessageW", "Ptr", handle, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
    oldFont := DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
    DllCall("SetBkMode", "Ptr", dc, "Int", 1)
    rect := Buffer(16, 0)
    bodyBottom := face.BodyBottom > 0 ? Round(face.BodyBottom * scale) : height - Round(16 * scale)
    NumPut("Int", Round(18 * scale), "Int", Round(67 * scale), "Int", width - Round(18 * scale), "Int", bodyBottom, rect)
    label := face.Control.Text
    fittedFont := FitWrappedLabelFont(dc, font, label, rect)
    if fittedFont
        DllCall("SelectObject", "Ptr", dc, "Ptr", fittedFont, "Ptr")
    shadowRect := Buffer(16, 0)
    Loop 4
        NumPut("Int", NumGet(rect, (A_Index - 1) * 4, "Int") + Max(1, Round(scale)), shadowRect, (A_Index - 1) * 4)
    DllCall("SetTextColor", "Ptr", dc, "UInt", 0x080808)
    DllCall("DrawTextW", "Ptr", dc, "WStr", label, "Int", -1, "Ptr", shadowRect, "UInt", 0x810)
    DllCall("SetTextColor", "Ptr", dc, "UInt", 0xC5E2F2)
    DllCall("DrawTextW", "Ptr", dc, "WStr", label, "Int", -1, "Ptr", rect, "UInt", 0x810)
    DllCall("BitBlt", "Ptr", target, "Int", 0, "Int", 0, "Int", width, "Int", height, "Ptr", dc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
    if fittedFont
        DllCall("DeleteObject", "Ptr", fittedFont)
    DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
    DllCall("DeleteObject", "Ptr", bitmap)
    DllCall("DeleteDC", "Ptr", dc)
    return true
}
