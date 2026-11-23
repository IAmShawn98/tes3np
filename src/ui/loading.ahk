; Buffered interface updates and loading feedback.

BeginInterfaceUpdate(gui := 0, message := "", showLoading := false, totalSteps := 0)
{
    global CharacterPage, InterfaceUpdating, InterfaceUpdateDepth, InterfaceFrameCover, InterfaceUpdateGui, InterfaceCompletedSteps, InterfaceTotalSteps
    global V016SettingsGuiHwnd, InterfaceParentRedrawSuppressed
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
        InterfaceParentRedrawSuppressed := false
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
        ; Settings already has a captured cover. WM_SETREDRAW(FALSE) removes
        ; WS_VISIBLE on top-level windows, disturbing presentation of the
        ; layered parchment/owned cover. Change Settings controls behind the
        ; cover without suppressing the entire owner's visibility.
        settingsCovered := IsObject(InterfaceFrameCover) && V016SettingsGuiHwnd
            && InterfaceUpdateGui.Hwnd = V016SettingsGuiHwnd
        if !settingsCovered && IsObject(InterfaceUpdateGui)
            && DllCall("IsWindow", "Ptr", InterfaceUpdateGui.Hwnd)
        {
            DllCall("SendMessageW", "Ptr", InterfaceUpdateGui.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
            InterfaceParentRedrawSuppressed := true
        }
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
    global InterfaceParentRedrawSuppressed, V016SettingsGuiHwnd
    ; Be defensive about mismatched cleanup. A stray EndInterfaceUpdate must not
    ; drive the depth negative or dereference a GUI that has already been closed.
    if InterfaceUpdateDepth <= 0
    {
        InterfaceUpdateDepth := 0
        InterfaceUpdating := false
        InterfaceParentRedrawSuppressed := false
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
        InterfaceParentRedrawSuppressed := false
        ReleaseInterfaceFrame()
        return
    }
    previousCritical := Critical("On")
    redrawEnabled := !InterfaceParentRedrawSuppressed
    isCharacterBook := InterfaceUpdateGui = CharacterPage
    isCoveredSettings := IsObject(InterfaceFrameCover) && V016SettingsGuiHwnd
        && targetWindow = V016SettingsGuiHwnd
    try
    {
        if InterfaceParentRedrawSuppressed
        {
            DllCall("SendMessageW", "Ptr", targetWindow, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
            redrawEnabled := true
        }
        if !isCharacterBook && !isCoveredSettings
            DllCall("RedrawWindow", "Ptr", targetWindow, "Ptr", 0, "Ptr", 0, "UInt", 0x0081)
        ; Commit geometry and pointer state while the captured frame still
        ; covers the real window. This makes the first click after loading use
        ; the final controls even if the pointer never moved during the update.
        SyncDynamicButtonGeometry()
        ResetThemedPointerState()
        UpdateButtonHover()
        if isCharacterBook || isCoveredSettings
        {
            ; Complete every Settings control paint behind the snapshot cover
            ; without toggling Settings' top-level WS_VISIBLE state.
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
            InterfaceParentRedrawSuppressed := false
            ReleaseInterfaceFrame()
        }
        finally Critical(previousCritical)
    }
}


; A transient owned window preserves the last visible frame during layout updates.
; Its bitmap stays in memory and is released after the completed redraw.

CaptureInterfaceFrame(sourceWindow, showLoading := false, destination := unset)
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
    ; Source bounds anchor the progress card. The optional target is used ONLY
    ; for display Preview/Restore: capture the full union from the desktop
    ; BEFORE any owned image, dim or loading card is shown. This avoids
    ; recapturing our own overlay and avoids a synthetic black filler.
    sourceX := x, sourceY := y, sourceWidth := width, sourceHeight := height
    expanded := false
    if IsSet(destination)
    {
        left := Min(x, destination.X)
        top := Min(y, destination.Y)
        right := Max(x + width, destination.X + destination.Width)
        bottom := Max(y + height, destination.Y + destination.Height)
        x := left, y := top, width := right - left, height := bottom - top
        expanded := x != sourceX || y != sourceY
            || width != sourceWidth || height != sourceHeight
    }
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
        frame := {Gui: cover, Face: face, Bitmap: bitmap, Dim: 0, Card: 0, Panel: 0,
            X: x, Y: y, Width: width, Height: height, Expanded: expanded}
        if showLoading
        {
            ; Keep progress over the old, complete launcher rather than
            ; moving it to the center of a much larger desktop union.
            loading := CreateLoadingCard(cover, sourceX, sourceY, sourceWidth, sourceHeight)
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
        if IsObject(cover)
            try cover.Destroy()
        DllCall("DeleteObject", "Ptr", bitmap)
        try ReportLoadingFailure(err)
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
    try
    {
        if IsObject(frame.Panel)
        {
            DestroyLoadingCard(frame)
        }
        try frame.Gui.Hide()
        ; Detach before deletion: the native Static control does not own our bitmap.
        try DllCall("SendMessageW", "Ptr", frame.Face.Hwnd, "UInt", 0x172, "Ptr", 0, "Ptr", 0)
        try frame.Gui.Destroy()
    }
    finally DllCall("DeleteObject", "Ptr", frame.Bitmap)
}

; Keep the proven screenshot cover unmodified. Native windows supply dimming
; and the status card, so bitmap alpha cannot erase the card text or progress bar.

CreateLoadingCard(owner, x, y, width, height, message := unset)
{
    global ButtonFaces, InterfaceLoadingText
    dim := 0, card := 0, panel := 0
    try
    {
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
        panel := card.Add("Custom", "ClassStatic x0 y0 w" cw " h" ch, IsSet(message) ? message : InterfaceLoadingText)
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
    catch as err
    {
        if IsObject(panel)
            try DestroyBookControl(panel)
        if IsObject(card)
            try card.Destroy()
        if IsObject(dim)
            try dim.Destroy()
        throw err
    }
}

DestroyLoadingCard(loading)
{
    try DestroyBookControl(loading.Panel)
    try loading.Card.Destroy()
    try loading.Dim.Destroy()
}

SetLoadingCardProgress(panel, message, progress)
{
    global ButtonFaces
    panel.Text := message
    ButtonFaces[panel.Hwnd].Progress := progress
    PaintButtonNow(panel.Hwnd)
}

ReportLoadingFailure(err)
{
    static reported := false
    ; Keep diagnostics free of credentials and personal file paths.
    detail := "Error type: " Type(err)
    try
    {
        DirCreate(AppDataDirectory)
        path := AppDataDirectory "\render-errors.log"
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " Loading overlay: " detail "`n", path, "UTF-8")
        TrimDiagnosticLog(path)
    }
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
    ButtonFaces[panelHwnd].ProgressText := frame.Panel.Text
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
        return false
    hwnd := frame.Panel.Hwnd
    if !ButtonFaces.Has(hwnd)
        return false
    face := ButtonFaces[hwnd]
    progress := Max(0, Min(1, percent / 100))
    if face.HasOwnProp("ProgressText") && face.ProgressText == label && face.Progress = progress
        return false
    ; WM_SETTEXT can briefly expose the default Static background. Keep
    ; updates in the paint state so the caption and bar draw in one blit.
    face.ProgressText := label
    face.Progress := progress
    face.ProgressHeaderOnly := face.HasOwnProp("ProtectedButtonHwnd")
    try PaintButtonNow(hwnd)
    finally face.ProgressHeaderOnly := false
    return true
}

SetInterfaceLoadingText(message)
{
    global InterfaceLoadingText, InterfaceFrameCover, InterfaceUpdating, InterfaceCompletedSteps, InterfaceTotalSteps
    InterfaceLoadingText := message
    if InterfaceUpdating && !InStr(message, "Waiting for Jiub")
        InterfaceCompletedSteps += 1
    if IsObject(InterfaceFrameCover) && IsObject(InterfaceFrameCover.Panel)
    {
        progress := message = "Waiting for Jiub" ? 1 : Min(0.99, InterfaceCompletedSteps / InterfaceTotalSteps)
        SetLoadingCardProgress(InterfaceFrameCover.Panel, message, progress)
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
    try loading := CreateLoadingCard(frame.Gui, frame.X, frame.Y, frame.Width, frame.Height)
    catch Error as err
    {
        try ReportLoadingFailure(err)
        return
    }
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

