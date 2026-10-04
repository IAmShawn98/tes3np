; Themed control builders, pointer state and event routing.

DragLauncher(wParam, lParam, msg, hwnd)
{
    global LauncherGui, DragStrip
    if hwnd != DragStrip.Hwnd
        return
    DllCall("ReleaseCapture")
    SendMessage(0xA1, 2, 0, , "ahk_id " LauncherGui.Hwnd)
    return 0
}

AddLauncherButton(y, name, action)
{
    global LauncherGui, ButtonFaces
    InitButtonPainter()
    LauncherGui.SetFont("s10 Bold", "Segoe UI")
    button := LauncherGui.Add("Custom", "ClassButton x370 y" (y - 11) " w220 h48 +0xB +Tabstop", name)
    DllCall("uxtheme\SetWindowTheme", "Ptr", button.Hwnd, "WStr", "", "WStr", "")
    face := {Control: button, Label: button, Action: action, Y: y, Gui: LauncherGui, Window: LauncherGui.Hwnd, Book: false, State: "normal"}
    ButtonFaces[button.Hwnd] := face
    AttachButtonPainter(button.Hwnd)
    return button
}

AddStyledButton(gui, x, y, width, height, text, action)
{
    global ButtonFaces
    InitButtonPainter()
    gui.SetFont("s10 Bold", "Segoe UI")
    button := gui.Add("Custom", "ClassButton x" x " y" y " w" width " h" height " +0xB +Tabstop", text)
    DllCall("uxtheme\SetWindowTheme", "Ptr", button.Hwnd, "WStr", "", "WStr", "")
    ButtonFaces[button.Hwnd] := {Control: button, Label: button, Action: action,
        Y: y, X: x, Gui: gui, Window: gui.Hwnd, Book: true, State: "normal"}
    AttachButtonPainter(button.Hwnd)
    return button
}

AddBookLabel(gui, x, y, width, height, text)
{
    global ButtonFaces
    label := gui.Add("Text", "x" x " y" y " w" width " h" height, text)
    ButtonFaces[label.Hwnd] := {Control: label, Label: label, Action: 0, IsLabel: true,
        Y: y, X: x, Gui: gui, Window: gui.Hwnd, Book: true, State: "normal"}
    AttachButtonPainter(label.Hwnd)
    return label
}

AddBookTick(gui, x, y, action)
{
    global ButtonFaces
    tick := AddBookLabel(gui, x, y, 18, 18, "")
    tick.Opt("+0x100")
    ButtonFaces[tick.Hwnd].IsTick := true
    ButtonFaces[tick.Hwnd].Checked := false
    tick.OnEvent("Click", action)
    return tick
}

SetBookTick(tick, checked)
{
    global ButtonFaces
    ButtonFaces[tick.Hwnd].Checked := checked
    DllCall("InvalidateRect", "Ptr", tick.Hwnd, "Ptr", 0, "Int", 0)
}

ShowButtonFace(handle)
{
    global ButtonFaces, HoverButton, PressedButton
    if !ButtonFaces.Has(handle) || !DllCall("IsWindow", "Ptr", handle)
        return
    face := ButtonFaces[handle]
    focused := DllCall("GetFocus", "Ptr") = handle
    state := PressedButton && HoverButton && ButtonFaces[PressedButton] = face && ButtonFaces[HoverButton] = face ? "down" : HoverButton && ButtonFaces[HoverButton] = face ? "hover" : focused ? "focus" : "normal"
    if face.State = state
        return
    face.State := state
    DllCall("RedrawWindow", "Ptr", face.Control.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0121)
}

RepaintMenuButtons(*)
{
    global ButtonFaces
    for handle, face in ButtonFaces
        if DllCall("IsWindow", "Ptr", handle)
            PaintButtonNow(handle)
}

FinishButtonDisplay()
{
    global InterfaceUpdating
    if IsSet(InterfaceUpdating) && InterfaceUpdating
        return
    RepaintMenuButtons()
}

UpdateButtonHover()
{
    global LauncherGui, ButtonFaces, HoverButton, PressedButton, MenuRows
    MouseGetPos(&x, &y, &window)
    nextHover := 0
    if window
    {
        rect := Buffer(16, 0)
        for handle, face in ButtonFaces
        {
            button := face.Control
            if !DllCall("IsWindow", "Ptr", handle) || face.HasOwnProp("IsLabel") || window != face.Window || !button.Visible || !button.Enabled
                continue
            DllCall("GetWindowRect", "Ptr", button.Hwnd, "Ptr", rect)
            if x >= NumGet(rect, 0, "Int") && x < NumGet(rect, 8, "Int")
                && y >= NumGet(rect, 4, "Int") && y < NumGet(rect, 12, "Int")
            {
                nextHover := button.Hwnd
                break
            }
        }
    }
    previous := HoverButton
    previousPress := PressedButton
    HoverButton := nextHover
    if PressedButton && !GetKeyState("LButton", "P")
    {
        PressedButton := 0
        DllCall("ReleaseCapture")
    }
    for handle in [previous, nextHover, previousPress, DllCall("GetFocus", "Ptr")]
        if handle
            ShowButtonFace(handle)
}

PressButton(wParam, lParam, msg, hwnd)
{
    global ButtonFaces, PressedButton, HoverButton
    if !ButtonFaces.Has(hwnd) || ButtonFaces[hwnd].HasOwnProp("IsLabel") || !ButtonFaces[hwnd].Control.Enabled
        return
    DllCall("SetFocus", "Ptr", hwnd)
    PressedButton := hwnd
    HoverButton := hwnd
    DllCall("SetCapture", "Ptr", hwnd)
    ShowButtonFace(hwnd)
    return 0
}

ReleaseButton(wParam, lParam, msg, hwnd)
{
    global ButtonFaces, PressedButton, HoverButton
    if ReleaseEditorScroll()
        return 0
    if ReleaseMenuScroll()
        return 0
    if !PressedButton
        return
    handle := PressedButton
    face := ButtonFaces[handle]
    x := (lParam & 0xFFFF) << 48 >> 48
    y := ((lParam >> 16) & 0xFFFF) << 48 >> 48
    GuiCtrlFromHwnd(handle).GetPos(, , &width, &height)
    inside := x >= 0 && y >= 0 && x < width * A_ScreenDPI / 96 && y < height * A_ScreenDPI / 96
    PressedButton := 0
    DllCall("ReleaseCapture")
    HoverButton := inside ? handle : 0
    ShowButtonFace(handle)
    if inside
        ActivateThemedButton(handle)
    return 0
}

ActivateThemedButton(handle)
{
    global ButtonFaces
    if !ButtonFaces.Has(handle)
        return
    face := ButtonFaces[handle]
    if face.HasOwnProp("IsLabel") || !face.Control.Enabled || !face.Control.Visible
        return
    if ButtonNeedsRenderCover(face)
    {
        BeginInterfaceUpdate(face.Gui, LoadingMessageForButton(face), ButtonLoadsContent(face), LoadingStepsForButton(face))
        try face.Action.Call()
        finally EndInterfaceUpdate()
    }
    else
        face.Action.Call()
}

HandleThemedButtonKey(wParam, lParam, msg, hwnd)
{
    global ButtonFaces
    if !ButtonFaces.Has(hwnd) || ButtonFaces[hwnd].HasOwnProp("IsLabel")
        return
    if wParam = 0x0D || wParam = 0x20
    {
        ActivateThemedButton(hwnd)
        return 0
    }
}

HandleThemedButtonFocus(wParam, lParam, msg, hwnd)
{
    global ButtonFaces
    if ButtonFaces.Has(hwnd)
    {
        ShowButtonFace(hwnd)
        if lParam && ButtonFaces.Has(lParam)
            ShowButtonFace(lParam)
    }
}

HandleMouseDown(wParam, lParam, msg, hwnd)
{
    global DragStrip, BookDragStrip, CharacterPage
    if IsSet(BookDragStrip) && hwnd = BookDragStrip.Hwnd
    {
        DllCall("ReleaseCapture")
        SendMessage(0xA1, 2, 0, , "ahk_id " CharacterPage.Hwnd)
        return 0
    }
    if PressEditorScroll(hwnd)
        return 0
    if PressMenuScroll(hwnd)
        return 0
    if hwnd = DragStrip.Hwnd
        return DragLauncher(wParam, lParam, msg, hwnd)
    return PressButton(wParam, lParam, msg, hwnd)
}

HandleCaptureLost(*)
{
    global PressedButton
    if !PressedButton
        return
    previous := PressedButton
    PressedButton := 0
    ShowButtonFace(previous)
}
