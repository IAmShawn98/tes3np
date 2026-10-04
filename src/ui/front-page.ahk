; Front-page layout. Coordinates are logical pixels at 96 DPI.
BuildFrontPage()
{
    global LauncherGui, DragStrip, LauncherHeading
    global ButtonFaces, HoverButton, PressedButton
    ButtonFaces := Map()
    LauncherGui.Opt("+OwnDialogs")
    LauncherGui.BackColor := "272722"
    LauncherGui.Add("Picture", "x0 y-4 w960 h720", A_ScriptDir "\assets\backgrounds\launcher.png")
    ; SS_NOTIFY (+0x100) makes the top strip receive mouse input.
    ; Only this strip can initiate a drag; button clicks remain untouched.
    DragStrip := LauncherGui.Add("Text", "x0 y0 w960 h48 BackgroundTrans +0x100")
    ; The parchment is an independent UI picture, not baked into the background.
    LauncherGui.Add("Picture", "x321 y361 w318 h305 BackgroundTrans", A_ScriptDir "\assets\controls\scroll-panel.png")
    ; Each feature card paints its frame, heading and live text in one buffer.
    LauncherGui.SetFont("s10 Norm", "Palatino Linotype")
    AddInfoCard(82, 75, 280, 220, "Quest", "Experience Morrowind’s legendary main questline and epic DLC stories—the classic adventure you know and love, fully integrated into multiplayer!")
    AddInfoCard(598, 75, 280, 265, "Together", "Experience Morrowind like never before! Battle powerful enemies in camps across Vvardenfell and Solstheim, and team up to conquer formidable bosses. Master tradeskills such as fishing and crafting, secure a personal vault, and buy a home of your own. The path to godhood is never a lonely one!")
    LauncherGui.SetFont("s14 Bold", "Georgia")
    ; The heading is a native text control, not part of the background image.
    LauncherHeading := LauncherGui.Add("Text", "x340 y408 w280 h30 Center BackgroundTrans c382314", "Game Launcher")
    LauncherGui.SetFont("s11", "Segoe UI")
    HoverButton := 0
    PressedButton := 0
    BuildButtonViewport()
    global MenuRows, MenuEntries, CharacterMenuButton
    LoadProfiles()
    MenuEntries := []
    MenuRows := []
    Loop 4
        MenuRows.Push(AddLauncherButton(447 + (A_Index - 1) * 40, "", OpenCharacters))
    CharacterMenuButton := MenuRows[2]
    UpdateCharacterMenuLabel()
}

AddInfoCard(x, y, width, height, heading, text)
{
    global LauncherGui, ButtonFaces
    InitButtonPainter()
    control := LauncherGui.Add("Custom", "ClassStatic x" x " y" y " w" width " h" height, text)
    ButtonFaces[control.Hwnd] := {Control: control, Label: control, Gui: LauncherGui,
        Window: LauncherGui.Hwnd, IsLabel: true, IsInfo: true, X: x, Y: y,
        Heading: heading, State: "normal", Action: 0}
    AttachButtonPainter(control.Hwnd)
    return control
}

UpdateCharacterMenuLabel()
{
    global MenuEntries, MenuOffset, Profiles, SelectedProfile
    MenuEntries := []
    if !IsTES3MPSetupComplete()
    {
        MenuEntries.Push(["Patch Tes3mp", OpenPatcher], ["Our Wiki", OpenWiki], ["Quit Launcher", QuitLauncher])
        ScrollMenu(0)
        return
    }
    if SelectedProfile > 0 && SelectedProfile <= Profiles.Length
        MenuEntries.Push(["Launch " Profiles[SelectedProfile].Name, LaunchProfile])
    MenuEntries.Push(["Start New Adventure", StartNewAdventure],
        [Profiles.Length ? "Manage Characters" : "Returning Fetcher", OpenCharacters],
        ["Macros", OpenMacros], ["Our Wiki", OpenWiki], ["Quit Launcher", QuitLauncher])
    ScrollMenu(MenuOffset)
}

 ; Menu scrolling stays on the main GUI, avoiding child-window positioning.
BuildButtonViewport()
{
    global LauncherGui, MenuOffset, ScrollTrack, ScrollThumb, ScrollDragging
    MenuOffset := 0
    ScrollDragging := false
    ScrollTrack := LauncherGui.Add("Text", "x602 y435 w8 h175 Background704C27 +0x100")
    ScrollThumb := LauncherGui.Add("Text", "x603 y435 w6 h72 BackgroundC69951 +0x100")
    OnMessage(0x020A, ScrollMenuWheel)
    OnMessage(0x0200, DragMenuScroll)
}

ScrollMenu(offset)
{
    global MenuOffset, ButtonFaces, ScrollThumb, MenuRows, MenuEntries
    maximum := Max(0, (MenuEntries.Length - MenuRows.Length) * 20)
    MenuOffset := Max(0, Min(maximum, offset))
    ScrollThumb.Move(603, 435 + (maximum ? Round(MenuOffset / maximum * 103) : 0))
    global ScrollTrack
    ScrollTrack.Visible := maximum > 0
    ScrollThumb.Visible := maximum > 0
    first := 1 + Min(Max(0, MenuEntries.Length - MenuRows.Length), Floor(MenuOffset / 20))
    for index, button in MenuRows
    {
        face := ButtonFaces[button.Hwnd]
        face.Control.Visible := index <= MenuEntries.Length
        if index > MenuEntries.Length
            continue
        entry := MenuEntries[first + index - 1]
        if face.Label.Text != entry[1]
            face.Label.Text := entry[1]
        face.Action := entry[2]
    }
}

ScrollFromPointer()
{
    global LauncherGui, ScrollGrabOffset
    MouseGetPos(, &y)
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", LauncherGui.Hwnd, "Ptr", origin)
    logicalY := (y - NumGet(origin, 4, "Int")) / (A_ScreenDPI / 96)
    global MenuEntries, MenuRows
    ScrollMenu(Round((logicalY - 435 - ScrollGrabOffset) / 103 * Max(0, (MenuEntries.Length - MenuRows.Length) * 20)))
}

PressMenuScroll(hwnd)
{
    global LauncherGui, ScrollTrack, ScrollThumb, ScrollDragging, ScrollGrabOffset, MenuOffset
    if hwnd != ScrollTrack.Hwnd && hwnd != ScrollThumb.Hwnd
        return false
    MouseGetPos(, &pointerY)
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", LauncherGui.Hwnd, "Ptr", origin)
    localY := (pointerY - NumGet(origin, 4, "Int")) / (A_ScreenDPI / 96)
    global MenuEntries, MenuRows
    maximum := Max(1, (MenuEntries.Length - MenuRows.Length) * 20)
    ScrollGrabOffset := hwnd = ScrollThumb.Hwnd ? localY - (435 + Round(MenuOffset / maximum * 103)) : 36
    ScrollDragging := true
    DllCall("SetCapture", "Ptr", hwnd)
    ScrollFromPointer()
    return true
}

DragMenuScroll(*)
{
    DragEditorScroll()
    global ScrollDragging
    if ScrollDragging
        ScrollFromPointer()
}

ReleaseMenuScroll()
{
    global ScrollDragging
    if !ScrollDragging
        return false
    ScrollDragging := false
    DllCall("ReleaseCapture")
    return true
}

ScrollMenuWheel(wParam, lParam, msg, hwnd)
{
    if ScrollEditorWheel(wParam)
        return 0
    global LauncherGui, MenuOffset
    MouseGetPos(&x, &y, &window)
    if window != LauncherGui.Hwnd
        return
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", LauncherGui.Hwnd, "Ptr", origin)
    scale := A_ScreenDPI / 96
    x := (x - NumGet(origin, 0, "Int")) / scale
    y := (y - NumGet(origin, 4, "Int")) / scale
    if x < 340 || x > 618 || y < 435 || y > 610
        return
    delta := (wParam >> 16) << 48 >> 48
    ScrollMenu(MenuOffset + (delta > 0 ? -20 : 20))
    return 0
}
