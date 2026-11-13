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
    previousCritical := A_IsCritical
    Critical("On")
    try
    {
        SetTimer(ShowSlowInterfaceLoading, 0)
        startedAt := A_TickCount
        SetTimer(ReleaseInterfaceFrame, 0)
        ReleaseInterfaceFrame()
        target := IsObject(gui) ? gui : CharacterPage
        InterfaceUpdateGui := 0
        ; Hidden pages are already staged. WM_SETREDRAW(TRUE) would make a
        ; hidden book visible if an asynchronous macro import finishes there.
        if !IsObject(target) || !DllCall("IsWindowVisible", "Ptr", target.Hwnd)
            return
        InterfaceUpdateGui := target
        InterfaceCompletedSteps := 0
        InterfaceTotalSteps := Max(1, totalSteps ? totalSteps : DefaultLoadingSteps(InterfaceUpdateGui, message))
        InterfaceUpdating := true
        SetInterfaceLoadingText("Waiting for Jiub...")
        InterfaceFrameCover := CaptureInterfaceFrame(InterfaceUpdateGui, showLoading)
        ; Freeze the real window after capturing its current frame. All control
        ; destruction/creation happens under the captured, owned frame.
        if IsObject(InterfaceUpdateGui) && DllCall("IsWindow", "Ptr", InterfaceUpdateGui.Hwnd)
            DllCall("SendMessageW", "Ptr", InterfaceUpdateGui.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
        if message != ""
            SetInterfaceLoadingText(message)
        if IsObject(InterfaceFrameCover) && !IsObject(InterfaceFrameCover.Panel)
            SetTimer(ShowSlowInterfaceLoading, -Max(1, 120 - (A_TickCount - startedAt)))
    }
    finally Critical(previousCritical)
}

EndInterfaceUpdate()
{
    global CharacterPage, InterfaceUpdateGui, InterfaceUpdating, InterfaceUpdateDepth, InterfaceFrameCover
    ; Be defensive about mismatched cleanup. A stray EndInterfaceUpdate must not
    ; drive the depth negative or dereference a GUI that has already been closed.
    if InterfaceUpdateDepth <= 0
    {
        InterfaceUpdateDepth := 0
        InterfaceUpdating := false
        return
    }
    InterfaceUpdateDepth -= 1
    if InterfaceUpdateDepth > 0
        return
    targetWindow := IsObject(InterfaceUpdateGui) ? InterfaceUpdateGui.Hwnd : 0
    if !targetWindow || !DllCall("IsWindow", "Ptr", targetWindow)
    {
        SetTimer(ShowSlowInterfaceLoading, 0)
        InterfaceUpdating := false
        ReleaseInterfaceFrame()
        return
    }
    previousCritical := Critical("On")
    redrawEnabled := false
    isCharacterBook := InterfaceUpdateGui = CharacterPage
    try
    {
        DllCall("SendMessageW", "Ptr", targetWindow, "UInt", 0x000B, "Ptr", 1, "Ptr", 0) ; WM_SETREDRAW
        redrawEnabled := true
        if !isCharacterBook
            DllCall("RedrawWindow", "Ptr", targetWindow, "Ptr", 0, "Ptr", 0, "UInt", 0x0081)
        ; Commit geometry and pointer state while the captured frame still
        ; covers the real window. This makes the first click after loading use
        ; the final controls even if the pointer never moved during the update.
        SyncDynamicButtonGeometry()
        ResetThemedPointerState()
        UpdateButtonHover()
        if isCharacterBook
        {
            ; Use the same synchronous child repaint as the book's startup.
            ; RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW.
            DllCall("RedrawWindow", "Ptr", targetWindow, "Ptr", 0, "Ptr", 0, "UInt", 0x0181)
        }
        else
            DllCall("UpdateWindow", "Ptr", targetWindow)
        if IsObject(InterfaceFrameCover)
        {
            for layer in [InterfaceFrameCover.Gui, InterfaceFrameCover.Dim, InterfaceFrameCover.Card]
                if IsObject(layer)
                    DllCall("SetWindowPos", "Ptr", layer.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
            ; DwmFlush synchronously waits for Desktop Window Manager and
            ; can hold the GUI thread indefinitely under GPU/remote-display
            ; contention; do not use it in an interactive menu transition.
        }
    }
    finally
    {
        try
        {
            ; Never leave a window redraw-suspended if an update action throws.
            if !redrawEnabled && DllCall("IsWindow", "Ptr", targetWindow)
                DllCall("SendMessageW", "Ptr", targetWindow, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
            SetTimer(ShowSlowInterfaceLoading, 0)
            InterfaceUpdating := false
            ReleaseInterfaceFrame()
        }
        finally Critical(previousCritical)
    }
}


; A transient owned window preserves the last visible frame during layout updates.
; Its bitmap stays in memory and is released after the completed redraw.

CaptureInterfaceFrame(sourceWindow, showLoading := false)
{
    if !DllCall("IsWindowVisible", "Ptr", sourceWindow.Hwnd)
    {
        if showLoading
            LogLauncherEvent("EXPANSION | Native capture source window not visible.")
        return 0
    }
    rect := Buffer(16, 0)
    DllCall("GetClientRect", "Ptr", sourceWindow.Hwnd, "Ptr", rect)
    width := NumGet(rect, 8, "Int")
    height := NumGet(rect, 12, "Int")
    if width <= 0 || height <= 0
    {
        if showLoading
            LogLauncherEvent("EXPANSION | Native capture source window has no client area.")
        return 0
    }
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", sourceWindow.Hwnd, "Ptr", origin)
    x := NumGet(origin, 0, "Int")
    y := NumGet(origin, 4, "Int")
    screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
    memoryDC := DllCall("CreateCompatibleDC", "Ptr", screenDC, "Ptr")
    bitmap := DllCall("CreateCompatibleBitmap", "Ptr", screenDC, "Int", width, "Int", height, "Ptr")
    if !screenDC || !memoryDC || !bitmap
    {
        if showLoading
            LogLauncherEvent("EXPANSION | Native capture GDI allocation failed.")
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
        if showLoading
            LogLauncherEvent("EXPANSION | Native capture screen BitBlt failed.")
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
        if showLoading
        {
            ; Error type + first-party source line and operation are sufficient
            ; for diagnosis. Do not expose err.Message, paths or personal data.
            operation := SubStr(RegExReplace(err.What, "[^A-Za-z0-9_]", ""), 1, 70)
            LogLauncherEvent("EXPANSION | Native captured frame construction failed ("
                . Type(err) ", line " err.Line ", operation " operation ").")
        }
        ReportLoadingFailure(err)
        if IsObject(cover)
            cover.Destroy()
        DllCall("DeleteObject", "Ptr", bitmap)
        return 0
    }
}

ReleaseInterfaceFrame()
{
    global InterfaceFrameCover
    if !IsObject(InterfaceFrameCover)
        return
    frame := InterfaceFrameCover
    InterfaceFrameCover := 0
    ReleaseCapturedInterfaceFrame(frame)
}

ReleaseCapturedInterfaceFrame(frame)
{
    if !IsObject(frame)
        return
    if IsObject(frame.Panel)
    {
        DestroyBookControl(frame.Panel)
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
    ; Do not wait synchronously on DWM. The card is already painted and
    ; all three owned windows have been positioned before returning.
    return {Dim: dim, Card: card, Panel: panel}
}

ReportLoadingFailure(err)
{
    static reported := false
    ; Keep diagnostics free of credentials and personal file paths.
    DirCreate(AppDataDirectory)
    detail := "Error type: " Type(err)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " Loading overlay: " detail "`n",
        AppDataDirectory "\render-errors.log", "UTF-8")
    if !reported
    {
        reported := true
        TrayTip("The loading overlay could not be displayed. Details were written to render-errors.log.", "tes3np")
    }
}

; Protect only the native cancel button's pixels from progress blits.
; The panel and the button remain themed AHK sibling controls in one GUI,
; but the panel renderer never overwrites the clickable button rectangle.
ProtectExpansionLoadingCancel(frame, cancelButton)
{
    global ButtonFaces
    if !IsObject(frame) || !IsObject(frame.Panel) || !IsObject(cancelButton)
        return false
    panelHwnd := frame.Panel.Hwnd
    if !ButtonFaces.Has(panelHwnd) || !DllCall("IsWindow", "Ptr", cancelButton.Hwnd)
        return false
    ButtonFaces[panelHwnd].ProtectedButtonHwnd := cancelButton.Hwnd
    ButtonFaces[panelHwnd].DownloadText := frame.Panel.Text
    ; Paint both surfaces once in z-order after the registration, without
    ; forcing the button to reappear after each progress update.
    PaintButtonNow(panelHwnd)
    PaintButtonNow(cancelButton.Hwnd)
    return true
}

; Update the auto-download's native loading card through the same
; renderer and ButtonFaces map used by the transactional import UI.
; Keep presentation state in the UI module, not the early game include.
UpdateExpansionLoadingProgress(frame, label, percent)
{
    global ButtonFaces
    if !IsObject(frame) || !IsObject(frame.Panel)
        return
    hwnd := frame.Panel.Hwnd
    if !ButtonFaces.Has(hwnd)
        return
    face := ButtonFaces[hwnd]
    face.Progress := Max(0, Min(1, percent / 100))
    if face.HasOwnProp("ProtectedButtonHwnd")
    {
        ; Writing to a native Static's Text property triggers WM_SETTEXT,
        ; which invalidates the WHOLE full-height panel and briefly exposes
        ; the default white sibling Button before its custom painter runs.
        ; Preserve the caption in the existing face and blit ONLY the header
        ; containing text and progress. The footer and Cancel HWND stay still.
        face.DownloadText := label
        face.ProgressHeaderOnly := true
        try PaintButtonNow(hwnd)
        finally face.ProgressHeaderOnly := false
    }
    else
    {
        ; Keep all original loading overlays unchanged.
        frame.Panel.Text := label
        PaintButtonNow(hwnd)
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

; Reveal a loading card only when real work is still running after 120 ms.
; Fast transitions stay covered only by the captured frame and complete immediately;
; there is no minimum display duration or artificial wait.

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

