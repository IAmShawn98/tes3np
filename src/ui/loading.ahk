; Buffered interface updates and loading feedback.

BeginInterfaceUpdate(gui := 0, message := "", showLoading := false, totalSteps := 0)
{
    global CharacterPage, InterfaceUpdating, InterfaceUpdateDepth, InterfaceFrameCover, InterfaceUpdateGui, InterfaceCompletedSteps, InterfaceTotalSteps
    InterfaceUpdateDepth += 1
    if InterfaceUpdateDepth > 1
    {
        if showLoading && IsObject(InterfaceFrameCover)
            EnsureInterfaceLoading()
        if message != ""
            SetInterfaceLoadingText(message)
        return
    }
    Critical("On")
    SetTimer(ShowSlowInterfaceLoading, 0)
    startedAt := A_TickCount
    SetTimer(ReleaseInterfaceFrame, 0)
    ReleaseInterfaceFrame()
    InterfaceUpdateGui := IsObject(gui) ? gui : CharacterPage
    InterfaceCompletedSteps := 0
    InterfaceTotalSteps := Max(1, totalSteps ? totalSteps : DefaultLoadingSteps(InterfaceUpdateGui, message))
    InterfaceUpdating := true
    SetInterfaceLoadingText("Waiting for Jiub...")
    InterfaceFrameCover := CaptureInterfaceFrame(InterfaceUpdateGui, showLoading)
    if message != ""
        SetInterfaceLoadingText(message)
    if IsObject(InterfaceFrameCover) && !IsObject(InterfaceFrameCover.Panel)
        SetTimer(ShowSlowInterfaceLoading, -Max(1, 50 - (A_TickCount - startedAt)))
    Critical("Off")
}

EndInterfaceUpdate()
{
    global InterfaceUpdateGui, InterfaceUpdating, InterfaceUpdateDepth, InterfaceFrameCover, ButtonFaces
    InterfaceUpdateDepth -= 1
    if InterfaceUpdateDepth > 0
        return
    targetWindow := InterfaceUpdateGui.Hwnd
    try
    {
        ; Keep the delayed indicator eligible until the redraw is complete.
        ; The separate cover holds the previous frame while this window paints.
        ; Keep the real book visible and preserve its background beneath the cover.
        DllCall("RedrawWindow", "Ptr", targetWindow, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
        for handle, face in ButtonFaces
            if face.Window = targetWindow && DllCall("IsWindow", "Ptr", handle)
            {
                SetInterfaceLoadingText(face.HasOwnProp("IsTick") ? "Drawing character checkbox..." : face.HasOwnProp("IsLabel") ? "Drawing text label..." : "Drawing button...")
                PaintButtonNow(handle)
            }
        ; Commit geometry and pointer state while the captured frame still
        ; covers the real window. This makes the first click after loading use
        ; the final controls even if the pointer never moved during the update.
        SyncDynamicButtonGeometry()
        ResetThemedPointerState()
        UpdateButtonHover()
        DllCall("UpdateWindow", "Ptr", targetWindow)
        if IsObject(InterfaceFrameCover)
        {
            for layer in [InterfaceFrameCover.Gui, InterfaceFrameCover.Dim, InterfaceFrameCover.Card]
                if IsObject(layer)
                    DllCall("SetWindowPos", "Ptr", layer.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
            DllCall("dwmapi\DwmFlush", "Int")
        }
    }
    finally
    {
        SetTimer(ShowSlowInterfaceLoading, 0)
        InterfaceUpdating := false
        if IsObject(InterfaceFrameCover)
        {
            if IsObject(InterfaceFrameCover.Panel)
                SetInterfaceLoadingText("Waiting for Jiub")
            ReleaseInterfaceFrame()
        }
        Critical("Off")
    }
}


; A transient owned window preserves the last visible frame during layout updates.
; Its bitmap stays in memory and is released after the completed redraw.

CaptureInterfaceFrame(sourceWindow, showLoading := false)
{
    if !DllCall("IsWindowVisible", "Ptr", sourceWindow.Hwnd)
        return 0
    rect := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", sourceWindow.Hwnd, "Ptr", rect)
    width := NumGet(rect, 8, "Int")
    height := NumGet(rect, 12, "Int")
    if width <= 0 || height <= 0
        return 0
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", sourceWindow.Hwnd, "Ptr", origin)
    x := NumGet(origin, 0, "Int")
    y := NumGet(origin, 4, "Int")
    screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    memoryDC := DllCall("CreateCompatibleDC", "Ptr", screenDC, "Ptr")
    bitmap := DllCall("CreateCompatibleBitmap", "Ptr", screenDC, "Int", width, "Int", height, "Ptr")
    if !screenDC || !memoryDC || !bitmap
    {
        if bitmap
            DllCall("DeleteObject", "Ptr", bitmap)
        if memoryDC
            DllCall("DeleteDC", "Ptr", memoryDC)
        if screenDC
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
        return 0
    }
    previous := DllCall("SelectObject", "Ptr", memoryDC, "Ptr", bitmap, "Ptr")
    copied := DllCall("BitBlt", "Ptr", memoryDC, "Int", 0, "Int", 0,
        "Int", width, "Int", height, "Ptr", screenDC, "Int", x, "Int", y, "UInt", 0x00CC0020)
    DllCall("SelectObject", "Ptr", memoryDC, "Ptr", previous)
    DllCall("DeleteDC", "Ptr", memoryDC)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
    if !copied
    {
        DllCall("DeleteObject", "Ptr", bitmap)
        return 0
    }
    cover := 0
    try
    {
        cover := Gui("-Caption -Border -DPIScale +ToolWindow +E0x08000000 +Owner" sourceWindow.Hwnd)
        face := cover.Add("Custom", "ClassStatic x0 y0 w" width " h" height " +0xE")
        DllCall("SendMessageW", "Ptr", face.Hwnd, "UInt", 0x172, "Ptr", 0, "Ptr", bitmap)
        cover.Show("NA x" x " y" y " w" width " h" height)
        DllCall("SetWindowPos", "Ptr", cover.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        DllCall("UpdateWindow", "Ptr", cover.Hwnd)
        frame := {Gui: cover, Face: face, Bitmap: bitmap, Dim: 0, Card: 0, Panel: 0, X: x, Y: y, Width: width, Height: height}
        if showLoading
        {
            loading := CreateLoadingCard(cover, x, y, width, height)
            frame.Dim := loading.Dim
            frame.Card := loading.Card
            frame.Panel := loading.Panel
        }
        return frame
    }
    catch Error as err
    {
        ReportLoadingFailure(err)
        if IsObject(cover)
            cover.Destroy()
        DllCall("DeleteObject", "Ptr", bitmap)
        return 0
    }
}

ReleaseInterfaceFrame()
{
    global InterfaceFrameCover, ButtonFaces, ButtonPaintCallback
    if !IsObject(InterfaceFrameCover)
        return
    frame := InterfaceFrameCover
    InterfaceFrameCover := 0
    ReleaseCapturedInterfaceFrame(frame)
}

ReleaseCapturedInterfaceFrame(frame)
{
    global ButtonFaces, ButtonPaintCallback
    if !IsObject(frame)
        return
    if IsObject(frame.Panel)
    {
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", frame.Panel.Hwnd, "Ptr", ButtonPaintCallback, "UPtr", 1)
        ButtonFaces.Delete(frame.Panel.Hwnd)
        frame.Card.Destroy()
        frame.Dim.Destroy()
    }
    frame.Gui.Hide()
    ; Detach before deletion: the native Static control does not own our bitmap.
    DllCall("SendMessageW", "Ptr", frame.Face.Hwnd, "UInt", 0x172, "Ptr", 0, "Ptr", 0)
    frame.Gui.Destroy()
    DllCall("DeleteObject", "Ptr", frame.Bitmap)
}

; Keep the proven screenshot cover unmodified. Native windows supply dimming
; and the status card, so bitmap alpha cannot erase the card text or progress bar.

CreateLoadingCard(owner, x, y, width, height)
{
    global ButtonFaces, InterfaceLoadingText
    dim := Gui("-Caption -Border -DPIScale +ToolWindow +E0x08000000 +Owner" owner.Hwnd)
    dim.BackColor := "000000"
    PrepareWindowDisplay(dim)
    dim.Show("NA x" x " y" y " w" width " h" height)
    DllCall("SetLayeredWindowAttributes", "Ptr", dim.Hwnd, "UInt", 0, "UChar", 130, "UInt", 2)
    DllCall("SetWindowPos", "Ptr", dim.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    card := Gui("-Caption -Border -DPIScale +ToolWindow +E0x08000000 +Owner" dim.Hwnd)
    card.BackColor := "C5A45C"
    scale := width / 960
    cw := Round(320 * scale)
    ch := Round(68 * scale)
    card.SetFont("s" Round(11 * scale * 96 / A_ScreenDPI) " cC5A45C", "Georgia")
    panel := card.Add("Custom", "ClassStatic x0 y0 w" cw " h" ch, InterfaceLoadingText)
    ButtonFaces[panel.Hwnd] := {Control: panel, Label: panel, Gui: card, Window: card.Hwnd, IsLabel: true,
        IsLoading: true, Progress: 0, State: "normal", Action: 0}
    AttachButtonPainter(panel.Hwnd)
    PrepareWindowDisplay(card)
    card.Show("NA x" (x + Round((width - cw) / 2)) " y" (y + Round((height - ch) / 2)) " w" cw " h" ch)
    DllCall("RedrawWindow", "Ptr", card.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
    PaintButtonNow(panel.Hwnd)
    DllCall("SetLayeredWindowAttributes", "Ptr", card.Hwnd, "UInt", 0, "UChar", 255, "UInt", 2)
    DllCall("SetWindowPos", "Ptr", card.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    DllCall("dwmapi\DwmFlush", "Int")
    return {Dim: dim, Card: card, Panel: panel}
}

ReportLoadingFailure(err)
{
    static reported := false
    ; Keep diagnostics free of credentials and personal file paths.
    DirCreate(AppDataDirectory)
    detail := RegExReplace(err.Message, "i)[A-Z]:\\[^`r`n]+", "[path omitted]")
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " Loading overlay: " detail "`n",
        AppDataDirectory "\render-errors.log", "UTF-8")
    if !reported
    {
        reported := true
        TrayTip("The loading overlay could not be displayed. Details were written to render-errors.log.", "tes3np")
    }
}

SetInterfaceLoadingText(message)
{
    global InterfaceLoadingText, InterfaceFrameCover, InterfaceUpdating, InterfaceCompletedSteps, InterfaceTotalSteps, ButtonFaces
    InterfaceLoadingText := message
    if InterfaceUpdating && !InStr(message, "Waiting for Jiub")
        InterfaceCompletedSteps += 1
    if IsObject(InterfaceFrameCover) && IsObject(InterfaceFrameCover.Panel)
    {
        InterfaceFrameCover.Panel.Text := message
        ButtonFaces[InterfaceFrameCover.Panel.Hwnd].Progress := message = "Waiting for Jiub" ? 1 : Min(0.99, InterfaceCompletedSteps / InterfaceTotalSteps)
        PaintButtonNow(InterfaceFrameCover.Panel.Hwnd)
    }
}

LoadingMessageForButton(face)
{
    if face.HasOwnProp("LoadingText")
        return face.LoadingText
    text := face.Control.Text
    messages := Map("Add character", "Opening new character form...",
        "Edit", "Loading character settings...", "Remove", "Removing character...",
        "Save changes", "Saving character...", "Browse", "Choosing game executable...",
        "Manage Characters", "Opening character menu...", "Returning Fetcher", "Opening character menu...",
        "Start New Adventure", "Launching a new adventure...", "Macros", "Opening macros...",
        "Our Wiki", "Opening the NP wiki...", "Quit Launcher", "Closing launcher...",
        "Close", "Closing character menu...", "X", "Closing character editor...")
    return messages.Has(text) ? messages[text] : InStr(text, "Launch ") = 1 ? "Launching game..." : "Waiting for Jiub..."
}

EnsureInterfaceLoading()
{
    global InterfaceFrameCover
    if IsObject(InterfaceFrameCover.Panel)
        return
    frame := InterfaceFrameCover
    SetInterfaceLoadingText("Waiting for Jiub...")
    loading := CreateLoadingCard(frame.Gui, frame.X, frame.Y, frame.Width, frame.Height)
    frame.Dim := loading.Dim
    frame.Card := loading.Card
    frame.Panel := loading.Panel
}

ButtonNeedsRenderCover(face)
{
    text := face.Control.Text
    return text = "Manage Characters" || text = "Returning Fetcher" || text = "Edit"
        || text = "Add character" || text = "Save changes"
}

ButtonLoadsContent(face)
{
    ; Content preparation starts immediately for these actions, even when its
    ; data is already in memory. Close/link actions bypass the loading overlay.
    return ButtonNeedsRenderCover(face)
}

; Reveal only if work is still in progress after 50 ms. This schedules feedback,
; never delays completion and never keeps the overlay up after work finishes.

ShowSlowInterfaceLoading()
{
    global InterfaceUpdating, InterfaceFrameCover, InterfaceLoadingText
    if !InterfaceUpdating || !IsObject(InterfaceFrameCover) || IsObject(InterfaceFrameCover.Panel)
        return
    message := InterfaceLoadingText
    EnsureInterfaceLoading()
    SetInterfaceLoadingText(message)
}

CountLoadingDrawObjects(window)
{
    global ButtonFaces
    count := 0
    for handle, face in ButtonFaces
        if face.Window = window && DllCall("IsWindow", "Ptr", handle)
            count += 1
    return count
}

DefaultLoadingSteps(sourceWindow, message)
{
    draws := CountLoadingDrawObjects(sourceWindow.Hwnd)
    ; Account for the message, setting fields and the subsequent control paints.
    return draws + (message = "Loading character settings..." ? 6 : message = "Loading more settings..." ? 5 : 1)
}

LoadingStepsForButton(face)
{
    global Profiles, CharacterPage
    draws := CountLoadingDrawObjects(face.Window)
    text := face.Control.Text
    if text = "Manage Characters" || text = "Returning Fetcher"
        return draws + (IsObject(CharacterPage) ? 1 : 58 + Profiles.Length)
    if face.HasOwnProp("LoadingText") && face.LoadingText = "Saving character..."
        return draws + 3 + 3 * (Profiles.Length + (text = "Add character" ? 1 : 0))
    if text = "Save changes"
        return draws + 3 + 3 * Profiles.Length
    if text = "Remove"
        return draws + 3 + 3 * Max(0, Profiles.Length - 1)
    if text = "Edit" || text = "Add character"
        return draws + 7
    return draws + 1
}

