; Front-page layout. Coordinates are logical pixels at 96 DPI.
global GameDetectionActive := false
global LauncherHelpText := 0
BuildFrontPage()
{
    global LauncherGui, DragStrip, LauncherHeading, LauncherMorrowindFont
    global ButtonFaces, HoverButton, PressedButton
    ButtonFaces := Map()
    LauncherGui.Opt("+OwnDialogs")
    LauncherGui.BackColor := "272722"
    LauncherGui.Add("Picture", "x0 y-4 w960 h720", A_ScriptDir "\assets\backgrounds\launcher.png")
    ; Static Happy Hour dust is behind buttons/text and shares this HWND.
    ; The existing banner signal toggles visibility alongside Jiub's face.
    CreateHappyHourDust()
    ; Reserve the upper-left corner for the Expansion Pack toggle. The old
    ; full-width drag strip intercepted mouse clicks in that button area.
    DragStrip := LauncherGui.Add("Text", "x205 y0 w755 h48 BackgroundTrans +0x100")
    LauncherGui.Add("Picture", "x321 y361 w318 h305 BackgroundTrans", A_ScriptDir "\assets\controls\scroll-panel.png")
    LauncherGui.SetFont("s10 Norm", "Palatino Linotype")
    AddInfoCard(82, 75, 280, 220, "Quest", "Experience Morrowind’s legendary main questline and epic DLC stories—the classic adventure you know and love, fully integrated into multiplayer!")
    AddInfoCard(598, 75, 280, 265, "Together", "Experience Morrowind like never before! Battle powerful enemies in camps across Vvardenfell and Solstheim, and team up to conquer formidable bosses. Master tradeskills such as fishing and crafting, secure a personal vault, and buy a home of your own. The path to godhood is never a lonely one!")
    ; Match the native Morrowind-style typography used by Launcher Settings
    ; and Characters. A slightly larger, darker regular face keeps the
    ; handwritten lettering readable against the parchment.
    LauncherGui.SetFont("s19 Norm c241408", LauncherMorrowindFont)
    LauncherHeading := LauncherGui.Add("Text", "x330 y414 w300 h38 Center BackgroundTrans", "Game Launcher")
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
        BaseWidth: width, BaseHeight: height,
        Heading: heading, State: "normal", Action: 0}
    AttachButtonPainter(control.Hwnd)
    return control
}

UpdateCharacterMenuLabel()
{
    global MenuEntries, MenuOffset, Profiles, SelectedProfile, GameDetectionActive, LauncherHelpText, LauncherHeading
    MenuEntries := []
    ; The Expansion Pack is optional and must never hide the launch menu.
    if IsObject(LauncherHelpText)
        LauncherHelpText.Visible := false
    if SelectedProfile > 0 && SelectedProfile <= Profiles.Length
    {
        MenuEntries.Push(["Launch " Profiles[SelectedProfile].Name, LaunchProfile])
        MenuEntries.Push([Profiles.Length ? "Manage Characters" : "Returning Fetcher", OpenCharacters])
        MenuEntries.Push(["Start New Adventure", StartNewAdventure])
    }
    else
    {
        MenuEntries.Push(["Start New Adventure", StartNewAdventure])
        MenuEntries.Push([Profiles.Length ? "Manage Characters" : "Returning Fetcher", OpenCharacters])
    }
    MenuEntries.Push(["Our Wiki", OpenWiki], ["Macros", OpenMacros], ["Quit Launcher", QuitLauncher])
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



; First-run detection status occupies the same scroll panel as the normal menu.
BeginGameDetectionDisplay()
{
    global LauncherGui, LauncherHeading, LauncherHelpText, GameDetectionActive, LauncherControlLayout
    GameDetectionActive := true
    LauncherHeading.Text := "Game Launcher"
    LauncherGui.SetFont("s10 Norm c241408", "Segoe UI")
    LauncherHelpText := LauncherGui.Add("Text", "x345 y529 w265 h98 Center BackgroundTrans",
        "Please wait while tes3np verifies your tes3mp folder data...")
    LauncherControlLayout[LauncherHelpText.Hwnd] := {Control: LauncherHelpText, X: 345, Y: 529, Width: 265, Height: 98}
    UpdateCharacterMenuLabel()
    RefreshGameDetectionText()
}

EndGameDetectionDisplay()
{
    global GameDetectionActive, LauncherHeading, LauncherHelpText, LauncherGui
    GameDetectionActive := false
    LauncherHeading.Text := "Game Launcher"
    if IsObject(LauncherHelpText)
    {
        ; Transparent Win32 text controls retain old glyphs unless the parent
        ; repaints the full status rectangle after changing the text.
        LauncherHelpText.Visible := false
        LauncherHelpText.Text := ""
        LauncherHelpText.Visible := true
        LauncherHelpText.GetPos(&x, &y, &w, &h)
        rect := Buffer(16, 0)
        NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, rect)
        DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", rect.Ptr, "Ptr", 0, "UInt", 0x0185)
    }
    UpdateCharacterMenuLabel()
    RefreshGameDetectionText()
}

; Transparent STATIC controls need their parent repainted when their text changes.
RefreshGameDetectionText()
{
    global LauncherGui
    ; A transparent STATIC cannot erase its previous glyphs. Repaint the
    ; heading rectangle on the parent, including the background and heading.
    global LauncherHeading
    if !IsObject(LauncherHeading)
        return
    LauncherHeading.GetPos(&x, &y, &w, &h)
    rect := Buffer(16, 0)
    NumPut("Int", x, "Int", y, "Int", x + w, "Int", y + h, rect)
    DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", rect.Ptr, "Ptr", 0, "UInt", 0x0185)
}
