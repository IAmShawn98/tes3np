; Front-page layout. Coordinates are logical pixels at 96 DPI.
BuildFrontPage()
{
    global LauncherGui, DragStrip, LauncherHeading, LauncherMorrowindFont
    global ButtonFaces, HoverButton, PressedButton
    ButtonFaces := Map()
    LauncherGui.Opt("+OwnDialogs")
    LauncherGui.BackColor := "272722"
    ; The approved vintage creature artwork is baked into this background.
    ; Draw it only once: no second beast picture or alignment seam.
    background := LauncherGui.Add("Picture", "x0 y-4 w960 h720", A_ScriptDir "\assets\backgrounds\launcher.png")
    ; Static Happy Hour dust is behind buttons/text and shares this HWND.
    ; The existing banner signal toggles visibility alongside Jiub's face.
    CreateHappyHourDust()
    ; Leave both corner controls outside the draggable area.
    SetAccessibleTextFont(LauncherGui, "s14 Bold cD5D5D5", LauncherMorrowindFont)
    DragStrip := LauncherGui.Add("Text", "x205 y0 w589 h48 Center BackgroundTrans +0x100 +0x200", "Server Status Unknown")
    InitializeLauncherServerStatus(background)
    parchment := LauncherGui.Add("Picture", "x321 y361 w318 h305 BackgroundTrans", A_ScriptDir "\assets\controls\scroll-panel.png")
    CreateLauncherCarousel(background, parchment)
    SetAccessibleTextFont(LauncherGui, "s10 Norm", "Palatino Linotype")
    ; Keep the Quest copy clear of the updates panel over the bottom of the backdrop.
    AddInfoCard(82, 75, 280, 220, "Quest", "Experience Morrowind’s legendary main questline and epic DLC stories—the classic adventure you know and love, fully integrated into multiplayer!", 151)
    AddInfoCard(598, 75, 280, 265, "Together", "Experience Morrowind like never before! Join dozens of fetchers in the most popular, feature-rich Morrowind multiplayer experience ever crafted. Shape your character build with class masteries, take on enemy camps, face unique bosses, and enjoy fishing, crafting, housing, and events. The road to godhood is never a lonely one!")
    ; Match the native Morrowind-style typography used by Launcher Settings
    ; and Characters. A slightly larger, darker regular face keeps the
    ; handwritten lettering readable against the parchment.
    SetAccessibleTextFont(LauncherGui, "s19 Norm c241408", LauncherMorrowindFont)
    LauncherHeading := LauncherGui.Add("Text", "x330 y414 w300 h34 Center BackgroundTrans", "Game Launcher")
    SetAccessibleTextFont(LauncherGui, "s11", "Segoe UI")
    HoverButton := 0
    PressedButton := 0
    BuildButtonViewport()
    global MenuRows
    MenuRows := []
    Loop 4
        MenuRows.Push(AddLauncherButton(447 + (A_Index - 1) * 40, "", OpenCharacters, A_Index = 1 ? 10 : 0))
    UpdateCharacterMenuLabel()
}

AddInfoCard(x, y, width, height, heading, text, bodyBottom := 0)
{
    global LauncherGui, ButtonFaces
    InitButtonPainter()
    control := LauncherGui.Add("Custom", "ClassStatic x" x " y" y " w" width " h" height, text)
    ButtonFaces[control.Hwnd] := {Control: control, Label: control, Gui: LauncherGui,
        Window: LauncherGui.Hwnd, IsLabel: true, IsInfo: true, X: x, Y: y,
        BaseWidth: width, BaseHeight: height, BodyBottom: bodyBottom,
        Heading: heading, State: "normal", Action: 0}
    AttachButtonPainter(control.Hwnd)
    return control
}

UpdateCharacterMenuLabel()
{
    global MenuEntries, MenuOffset, Profiles, SelectedProfile
    MenuEntries := []
    ; The Expansion Pack is optional and must never hide the launch menu.
    if SelectedProfile > 0 && SelectedProfile <= Profiles.Length
    {
        MenuEntries.Push(["Launch " Profiles[SelectedProfile].Name, LaunchProfile])
        MenuEntries.Push(["Manage Characters", OpenCharacters])
        MenuEntries.Push(["Start New Adventure", StartNewAdventure])
    }
    else
    {
        MenuEntries.Push(["Start New Adventure", StartNewAdventure])
        MenuEntries.Push([Profiles.Length ? "Manage Characters" : "Returning Fetcher", OpenCharacters])
    }
    MenuEntries.Push(["Our Wiki", OpenWiki], ["Quit Launcher", QuitLauncher])
    ScrollMenu(MenuOffset)
}

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
    global ScrollTrack
    ScrollTrack.GetPos(&trackX, &trackY, &trackWidth, &trackHeight)
    thumbWidth := Max(1, Round(trackWidth * 6 / 8))
    thumbHeight := Max(1, Round(trackHeight * 72 / 175))
    thumbX := trackX + Round(trackWidth / 8)
    thumbTravel := Max(0, trackHeight - thumbHeight)
    thumbY := trackY + (maximum ? Round(MenuOffset / maximum * thumbTravel) : 0)
    ScrollThumb.Move(thumbX, thumbY, thumbWidth, thumbHeight)
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
    global LauncherGui, ScrollGrabOffset, LauncherScale
    MouseGetPos(, &y)
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", LauncherGui.Hwnd, "Ptr", origin)
    logicalY := (y - NumGet(origin, 4, "Int")) / ((A_ScreenDPI / 96) * LauncherScale / 100)
    global MenuEntries, MenuRows
    ScrollMenu(Round((logicalY - 435 - ScrollGrabOffset) / 103 * Max(0, (MenuEntries.Length - MenuRows.Length) * 20)))
}

PressMenuScroll(hwnd)
{
    global LauncherGui, ScrollTrack, ScrollThumb, ScrollDragging, ScrollGrabOffset, MenuOffset, LauncherScale
    if hwnd != ScrollTrack.Hwnd && hwnd != ScrollThumb.Hwnd
        return false
    MouseGetPos(, &pointerY)
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", LauncherGui.Hwnd, "Ptr", origin)
    localY := (pointerY - NumGet(origin, 4, "Int")) / ((A_ScreenDPI / 96) * LauncherScale / 100)
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
    DragMacroScroll()
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
    if ScrollMacroWheel(wParam)
        return 0
    global LauncherGui, MenuOffset, LauncherScale
    MouseGetPos(&x, &y, &window)
    if window != LauncherGui.Hwnd
        return
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", LauncherGui.Hwnd, "Ptr", origin)
    scale := (A_ScreenDPI / 96) * LauncherScale / 100
    x := (x - NumGet(origin, 0, "Int")) / scale
    y := (y - NumGet(origin, 4, "Int")) / scale
    if x < 340 || x > 618 || y < 435 || y > 610
        return
    delta := (wParam >> 16) << 48 >> 48
    ScrollMenu(MenuOffset + (delta > 0 ? -20 : 20))
    return 0
}
