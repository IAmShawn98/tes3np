; Themed control builders, pointer state and event routing.

global KeyboardFocusButton := 0

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
    face := {Control: button, Label: button, Action: action, Y: y, Gui: LauncherGui, Window: LauncherGui.Hwnd, Book: false, State: "normal", BaseX: 370, BaseWidth: 220, BaseHeight: 48}
    ButtonFaces[button.Hwnd] := face
    AttachButtonPainter(button.Hwnd)
    return button
}

AddStyledButton(gui, x, y, width, height, text, action)
{
    global ButtonFaces
    InitButtonPainter()
    ; Settings parchment controls are sized by V016S. Its button fonts must
    ; use that same scale instead of remaining 10pt at 50/60 percent.
    ; Other books are scaled together later by ScaleOwnedMenuContent.
    buttonScale := gui.HasOwnProp("MenuButtonScale") ? gui.MenuButtonScale : 1.0
    gui.SetFont("s" Max(7, Round(10 * buttonScale)) " Bold", "Segoe UI")
    button := gui.Add("Custom", "ClassButton x" x " y" y " w" width " h" height " +0xB +Tabstop", text)
    DllCall("uxtheme\SetWindowTheme", "Ptr", button.Hwnd, "WStr", "", "WStr", "")
    ButtonFaces[button.Hwnd] := {Control: button, Label: button, Action: action, Y: y, X: x, Gui: gui, Window: gui.Hwnd, Book: true, State: "normal", BaseX: x, BaseWidth: width, BaseHeight: height}
    AttachButtonPainter(button.Hwnd)
    return button
}

AddBookLabel(gui, x, y, width, height, text)
{
    global ButtonFaces
    label := gui.Add("Text", "x" x " y" y " w" width " h" height, text)
    ButtonFaces[label.Hwnd] := {Control: label, Label: label, Action: 0, IsLabel: true, Y: y, X: x, Gui: gui, Window: gui.Hwnd, Book: true, State: "normal"}
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

UnregisterThemedControl(control)
{
    global ButtonFaces, ButtonPaintCallback, HoverButton, PressedButton, KeyboardFocusButton
    if !IsObject(control)
        return
    handle := 0
    try handle := control.Hwnd
    if !handle || !ButtonFaces.Has(handle)
        return
    if PressedButton = handle
    {
        PressedButton := 0
        DllCall("ReleaseCapture")
    }
    if HoverButton = handle
        HoverButton := 0
    if KeyboardFocusButton = handle
        KeyboardFocusButton := 0
    if IsSet(ButtonPaintCallback) && DllCall("IsWindow", "Ptr", handle)
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", handle, "Ptr", ButtonPaintCallback, "UPtr", 1)
    ButtonFaces.Delete(handle)
}

DestroyBookControl(control)
{
    ; Dynamic book controls may participate in custom painting. Unregister their
    ; HWND before Destroy() so no queued paint/input message can see stale state.
    UnregisterThemedControl(control)
    try control.Destroy()
}

ShowButtonFace(handle)
{
    global ButtonFaces, HoverButton, PressedButton, KeyboardFocusButton
    if !ButtonFaces.Has(handle) || !DllCall("IsWindow", "Ptr", handle)
    {
        if ButtonFaces.Has(handle)
            ButtonFaces.Delete(handle)
        return
    }
    face := ButtonFaces[handle]
    state := PressedButton = handle ? "down" : (HoverButton = handle || KeyboardFocusButton = handle) ? "hover" : "normal"
    if face.State = state
        return
    face.State := state
    DllCall("RedrawWindow", "Ptr", handle, "Ptr", 0, "Ptr", 0, "UInt", 0x0121)
}

SyncKeyboardFocus(*)
{
    global ButtonFaces, KeyboardFocusButton
    focused := DllCall("GetFocus", "Ptr")
    nextFocus := ButtonFaces.Has(focused) && DllCall("IsWindow", "Ptr", focused) && !ButtonFaces[focused].HasOwnProp("IsLabel") ? focused : 0
    previous := KeyboardFocusButton
    KeyboardFocusButton := nextFocus
    if previous && previous != nextFocus
        ShowButtonFace(previous)
    if nextFocus
        ShowButtonFace(nextFocus)
}

RepaintMenuButtons(*)
{
    global ButtonFaces
    stale := []
    for handle, face in ButtonFaces
    {
        if !DllCall("IsWindow", "Ptr", handle)
        {
            stale.Push(handle)
            continue
        }
        PaintButtonNow(handle)
    }
    for handle in stale
        ButtonFaces.Delete(handle)
}

SyncDynamicButtonGeometry()
{
    global ButtonFaces, LauncherGui
    stale := []
    for handle, face in ButtonFaces
    {
        if !DllCall("IsWindow", "Ptr", handle)
        {
            stale.Push(handle)
            continue
        }
        if face.HasOwnProp("IsLabel")
            continue
        ; Launcher controls keep their original base geometry for display scaling.
        ; Other windows can intentionally resize/move controls while refreshing,
        ; so make that live geometry the new themed-button baseline.
        if IsObject(LauncherGui) && face.Window = LauncherGui.Hwnd
            continue
        face.Control.GetPos(&x, &y, &width, &height)
        face.X := x
        face.Y := y
        face.BaseX := x
        face.BaseWidth := width
        face.BaseHeight := height
    }
    for handle in stale
        ButtonFaces.Delete(handle)
}

FinishButtonDisplay()
{
    global InterfaceUpdating
    if IsSet(InterfaceUpdating) && InterfaceUpdating
        return
    SyncDynamicButtonGeometry()
    RepaintMenuButtons()
}

ResetThemedPointerState()
{
    global ButtonFaces, HoverButton, PressedButton, KeyboardFocusButton
    ; Controls can be destroyed/recreated under a loading cover. Never carry a
    ; press, hover, capture, or keyboard-focus handle across that transition.
    oldHover := HoverButton
    oldPress := PressedButton
    oldFocus := KeyboardFocusButton
    PressedButton := 0
    HoverButton := 0
    KeyboardFocusButton := 0
    DllCall("ReleaseCapture")
    for handle in [oldHover, oldPress, oldFocus]
        if handle && ButtonFaces.Has(handle) && DllCall("IsWindow", "Ptr", handle)
            ShowButtonFace(handle)
}

UpdateButtonHover()
{
    global ButtonFaces, HoverButton, PressedButton, KeyboardFocusButton
    MouseGetPos(&x, &y, &window)
    nextHover := 0
    stale := []
    if window
    {
        rect := Buffer(16, 0)
        for handle, face in ButtonFaces
        {
            if !DllCall("IsWindow", "Ptr", handle)
            {
                stale.Push(handle)
                continue
            }
            button := face.Control
            if face.HasOwnProp("IsLabel") || window != face.Window || !button.Visible || !button.Enabled
                continue
            DllCall("GetWindowRect", "Ptr", handle, "Ptr", rect)
            if x >= NumGet(rect, 0, "Int") && x < NumGet(rect, 8, "Int") && y >= NumGet(rect, 4, "Int") && y < NumGet(rect, 12, "Int")
            {
                nextHover := handle
                break
            }
        }
    }
    for handle in stale
        ButtonFaces.Delete(handle)
    previous := HoverButton
    previousPress := PressedButton
    HoverButton := nextHover
    ; Do not let the hover timer clear a real button press. WM_LBUTTONUP owns
    ; PressedButton/capture lifetime; polling GetKeyState here could race the release
    ; message and swallow the activation, causing the intermittent "click twice" bug.
    if PressedButton && (!ButtonFaces.Has(PressedButton) || !DllCall("IsWindow", "Ptr", PressedButton))
    {
        PressedButton := 0
        DllCall("ReleaseCapture")
    }
    for handle in [previous, nextHover, previousPress, KeyboardFocusButton]
        if handle
            ShowButtonFace(handle)
}

PressButton(wParam, lParam, msg, hwnd)
{
    global ButtonFaces, PressedButton, HoverButton
    if !ButtonFaces.Has(hwnd) || !DllCall("IsWindow", "Ptr", hwnd) || ButtonFaces[hwnd].HasOwnProp("IsLabel") || !ButtonFaces[hwnd].Control.Enabled
        return
    DllCall("SetFocus", "Ptr", hwnd)
    SetTimer(SyncKeyboardFocus, -1)
    PressedButton := hwnd
    HoverButton := hwnd
    DllCall("SetCapture", "Ptr", hwnd)
    ShowButtonFace(hwnd)
    return 0
}

ReleaseButton(wParam, lParam, msg, hwnd)
{
    global ButtonFaces, PressedButton, HoverButton
    if ReleaseMacroScroll()
        return 0
    if ReleaseEditorScroll()
        return 0
    if ReleaseMenuScroll()
        return 0
    ; Mouse capture/focus changes can deliver mouse-up to a parent HWND even
    ; when the pointer is over a live themed button. Verify the actual child
    ; beneath the pointer before deciding the click was lost.
    if !PressedButton
    {
        target := hwnd
        if !ButtonFaces.Has(target)
        {
            MouseGetPos(, , &pointerWindow, &pointerControl, 2)
            if ButtonFaces.Has(pointerControl) && pointerWindow = ButtonFaces[pointerControl].Window
                && (hwnd = pointerWindow || DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = pointerWindow)
                target := pointerControl
        }
        if ButtonFaces.Has(target) && DllCall("IsWindow", "Ptr", target)
        {
            face := ButtonFaces[target]
            if !face.HasOwnProp("IsLabel") && face.Control.Enabled && face.Control.Visible
            {
                HoverButton := target
                ShowButtonFace(target)
                ActivateThemedButton(target)
                return 0
            }
        }
        return
    }
    handle := PressedButton
    if !ButtonFaces.Has(handle) || !DllCall("IsWindow", "Ptr", handle)
    {
        if ButtonFaces.Has(handle)
            ButtonFaces.Delete(handle)
        PressedButton := 0
        HoverButton := 0
        DllCall("ReleaseCapture")
        return 0
    }
    MouseGetPos(&screenX, &screenY)
    rect := Buffer(16, 0)
    DllCall("GetWindowRect", "Ptr", handle, "Ptr", rect)
    inside := screenX >= NumGet(rect, 0, "Int") && screenX < NumGet(rect, 8, "Int")
        && screenY >= NumGet(rect, 4, "Int") && screenY < NumGet(rect, 12, "Int")
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
    if !ButtonFaces.Has(handle) || !DllCall("IsWindow", "Ptr", handle)
    {
        if ButtonFaces.Has(handle)
            ButtonFaces.Delete(handle)
        return
    }
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
    if wParam = 0x09 ; Tab: let Windows/AHK move focus, then read the final focused control.
    {
        SetTimer(SyncKeyboardFocus, -1)
        return
    }
    if !ButtonFaces.Has(hwnd) || !DllCall("IsWindow", "Ptr", hwnd) || ButtonFaces[hwnd].HasOwnProp("IsLabel")
        return
    if wParam = 0x0D || wParam = 0x20
    {
        ActivateThemedButton(hwnd)
        return 0
    }
}

HandleThemedButtonFocus(wParam, lParam, msg, hwnd)
{
    ; Focus notifications happen during Windows' focus transition. Defer reading
    ; GetFocus until the transition has completed so visual state always matches reality.
    SetTimer(SyncKeyboardFocus, -1)
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
    if PressMacroScroll(hwnd)
        return 0
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
