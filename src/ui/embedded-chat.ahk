; Chat Host runs WebView2 in a child window of the launcher.
global EmbeddedChatPid := 0
global LauncherChatToggle := 0
global LauncherChatMenu := 0
global LauncherChatOpen := false
global LauncherDiscordName := 0
global LauncherDiscordPortrait := 0
global LauncherDiscordStatus := 0
global LauncherDiscordAvatar := 0
global LauncherDiscordAvatarStream := 0
global LauncherUpdatesSlot := 0

EnsureEmbeddedChatHostCurrent(host)
{
    ; Check freshness without blocking the launcher on a build or network restore.
    sourceDir := A_ScriptDir "\game-chat"
    if !FileExist(sourceDir "\Program.cs")
        return
    try
    {
        hostTime := FileExist(host) ? FileGetTime(host, "M") : "0"
        for pattern in ["\*.cs", "\tes3np.GameChat.csproj", "\web\*.*"]
        {
            Loop Files sourceDir pattern, "F"
            {
                if hostTime < A_LoopFileTimeModified
                {
                    LogLauncherEvent("CHAT | ChatHost source is newer than the executable. Use the Windows build script to update; startup will not block on compilation.")
                    return
                }
            }
        }
    }
    catch as err
        try LogLauncherEvent("CHAT | ChatHost freshness check failed (" Type(err) ").")
}

WebView2RuntimeAvailable()
{
    ; WebView2 Evergreen stores its version per-user or per-machine.
    ; Do not require developer tools or trigger an installer on startup.
    clientKey := "Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    for path in ["HKCU\SOFTWARE\" clientKey, "HKLM\SOFTWARE\WOW6432Node\" clientKey,
        "HKLM\SOFTWARE\" clientKey]
    {
        try
        {
            value := RegRead(path, "pv", "")
            if value != "" && value != "0.0.0.0"
                return true
        }
    }
    return false
}

StartEmbeddedInGameChat()
{
    global EmbeddedChatPid, LauncherGui, LauncherBaseWidth
    host := A_ScriptDir "\chat-host\tes3np.ChatHost.exe"
    EnsureEmbeddedChatHostCurrent(host)
    if !WebView2RuntimeAvailable()
        LogLauncherEvent("CHAT | WebView2 runtime not detected in standard registry locations. Attempting chat host launch; gameplay is unaffected.")
    if !FileExist(host)
    {
        try LogLauncherEvent("CHAT | Embedded host executable not installed.")
        ShowLauncherDiscordLoginIfLoading()
        return
    }
    if EmbeddedChatPid && ProcessExist(EmbeddedChatPid)
        return
    try
    {
        Run('"' host '" ' LauncherGui.Hwnd ' ' LauncherBaseWidth, A_ScriptDir, , &EmbeddedChatPid)
        ; Keep sign-in available if startup never receives a Discord account state.
        SetTimer(ShowLauncherDiscordLoginIfLoading, -60000)
        LogLauncherEvent("CHAT | Started WebView2 host (PID " EmbeddedChatPid ").")
    }
    catch as err
    {
        EmbeddedChatPid := 0
        try LogLauncherEvent("CHAT | Failed to start WebView2 host (" Type(err) ").")
        ShowLauncherDiscordLoginIfLoading()
    }
}

StopEmbeddedInGameChat()
{
    global EmbeddedChatPid
    SetLauncherServerUpdatesVisible(false)
    ReleaseLauncherDiscordAvatar()
    pid := EmbeddedChatPid
    if !pid
        return
    try
        if SendLauncherChatCommand(14)
            ProcessWaitClose(pid, 5)
    if ProcessExist(pid)
        try ProcessClose(pid)
    EmbeddedChatPid := 0
}

CreateLauncherDiscordAccount()
{
    global LauncherGui, LauncherDiscordName, LauncherDiscordPortrait, ButtonFaces
    LauncherDiscordName := AddStyledButton(LauncherGui, 794, 2, 122, 36, "Loading Profile...", OpenLauncherDiscordAccount)
    ButtonFaces[LauncherDiscordName.Hwnd].IsDiscordName := true
    LauncherDiscordPortrait := AddStyledButton(LauncherGui, 922, 2, 36, 36, "Log In to Discord", OpenLauncherDiscordAccount)
    ButtonFaces[LauncherDiscordPortrait.Hwnd].IsDiscordPortrait := true
    ; Run before the Expansion handler, which acknowledges its own COPYDATA.
    OnMessage(0x004A, ReceiveLauncherDiscordAccount, -1)
    OnMessage(0x833A, LauncherDiscordSignOutFailed)
}

IsLauncherDiscordMessage(sender, hwnd)
{
    global LauncherGui, EmbeddedChatPid
    if !sender || !EmbeddedChatPid || !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd
        return false
    pid := 0
    DllCall("user32\GetWindowThreadProcessId", "Ptr", sender, "UInt*", &pid, "UInt")
    return pid = EmbeddedChatPid
}

ReceiveLauncherDiscordAccount(sender, data, msg, hwnd)
{
    global LauncherDiscordPortrait, LauncherDiscordAvatar, LauncherDiscordAvatarStream
    if !data || NumGet(data, 0, "Ptr") != 0x8339
        return
    if !IsObject(LauncherDiscordPortrait) || !IsLauncherDiscordMessage(sender, hwnd)
        return 0
    size := NumGet(data, A_PtrSize, "UInt")
    payload := NumGet(data, A_PtrSize = 8 ? 16 : 8, "Ptr")
    if !payload || size < 8 || size > 33032
        return 0
    status := NumGet(payload, 0, "UInt")
    nameSize := NumGet(payload, 4, "UInt")
    if status > 3 || nameSize > 256 || Mod(nameSize, 2) || nameSize + 8 > size
        return 0
    imageSize := size - nameSize - 8
    if imageSize > 32768 || (status != 2 && (nameSize || imageSize))
        return 0

    Critical("On")
    name := nameSize ? StrGet(payload + 8, nameSize // 2, "UTF-16") : ""
    name := Trim(RegExReplace(name, "\p{Cc}+"))
    ReleaseLauncherDiscordAvatar()
    if imageSize >= 24
    {
        png := payload + 8 + nameSize
        if NumGet(png, 0, "UInt") = 0x474E5089 && NumGet(png, 4, "UInt") = 0x0A1A0A0D
            && NumGet(png, 16, "UInt") = 0x40000000 && NumGet(png, 20, "UInt") = 0x40000000
        {
            stream := DllCall("shlwapi\SHCreateMemStream", "Ptr", png, "UInt", imageSize, "Ptr")
            if stream
            {
                image := 0
                if !DllCall("gdiplus\GdipCreateBitmapFromStream", "Ptr", stream, "Ptr*", &image)
                {
                    LauncherDiscordAvatar := image
                    LauncherDiscordAvatarStream := stream
                }
                else ObjRelease(stream)
            }
        }
    }

    SetTimer(ShowLauncherDiscordLoginIfLoading, status = 0 ? -60000 : 0)
    UpdateLauncherDiscordAccountDisplay(status, name)
    return 1
}

ShowLauncherDiscordLoginIfLoading()
{
    global LauncherDiscordStatus
    previousCritical := A_IsCritical
    Critical("On")
    try
    {
        if LauncherDiscordStatus = 0
            UpdateLauncherDiscordAccountDisplay(1)
    }
    finally Critical(previousCritical)
}

UpdateLauncherDiscordAccountDisplay(status, name := "")
{
    global LauncherDiscordName, LauncherDiscordPortrait, LauncherDiscordStatus
    LauncherDiscordStatus := status
    LauncherDiscordName.Enabled := status <= 1
    LauncherDiscordPortrait.Enabled := status != 3
    if status <= 1
        label := status = 0 ? "Loading Profile..." : "Log In"
    else
        label := status = 3 ? "Signing out…" : name != "" ? name : "Discord account"
    SetPaintedLabelText(LauncherDiscordName, label)
    SetPaintedLabelText(LauncherDiscordPortrait, status <= 1 ? "Log In to Discord" : "Discord account")
    ; Resize/show the cross-process child after acknowledging WM_COPYDATA.
    SetTimer(RefreshLauncherServerUpdatesVisibility, -1)
}

CreateLauncherServerUpdates()
{
    global LauncherGui, LauncherUpdatesSlot
    ; This transparent control gives the host a position for its Game Updates window.
    ; Start below the Quest card's painted bounds, including its bottom fade.
    LauncherUpdatesSlot := LauncherGui.Add("Text",
        "x100 y298 w220 h342 BackgroundTrans Hidden")
    OnMessage(0x833B, ReceiveLauncherServerUpdatesVisibility)
}

SetLauncherServerUpdatesVisible(visible)
{
    global LauncherUpdatesSlot
    if !IsObject(LauncherUpdatesSlot) || !DllCall("IsWindow", "Ptr", LauncherUpdatesSlot.Hwnd)
        return
    if visible
    {
        LauncherUpdatesSlot.Visible := true
        RepaintLauncherServerUpdates()
    }
    else
        LauncherUpdatesSlot.Visible := false
    SetTimer(CheckServerUpdatesHost, visible ? 1500 : 0)
}

RefreshLauncherServerUpdatesVisibility()
{
    global LauncherDiscordStatus
    if LauncherDiscordStatus != 2
        SetLauncherServerUpdatesVisible(false)
}

ReceiveLauncherServerUpdatesVisibility(visible, sender, msg, hwnd)
{
    global LauncherDiscordStatus
    if IsLauncherDiscordMessage(sender, hwnd)
        SetLauncherServerUpdatesVisible(visible != 0 && LauncherDiscordStatus = 2)
}

LauncherServerUpdatesResized(gui, minMax, *)
{
    if minMax >= 0
        SetTimer(RepaintLauncherServerUpdates, -50)
}

RepaintLauncherServerUpdates()
{
    global LauncherGui, LauncherDiscordStatus, LauncherUpdatesSlot
    if LauncherDiscordStatus != 2 || !IsObject(LauncherUpdatesSlot) || !LauncherUpdatesSlot.Visible
        || DllCall("IsIconic", "Ptr", LauncherGui.Hwnd)
        return
    SendLauncherChatCommand(18, LauncherUpdatesSlot.Hwnd)
}

CheckServerUpdatesHost()
{
    global EmbeddedChatPid, LauncherDiscordStatus
    if LauncherDiscordStatus != 2 || !EmbeddedChatPid || !ProcessExist(EmbeddedChatPid)
    {
        SetLauncherServerUpdatesVisible(false)
        return
    }
    RepaintLauncherServerUpdates()
}

ReleaseLauncherDiscordAvatar()
{
    global LauncherDiscordAvatar, LauncherDiscordAvatarStream
    if LauncherDiscordAvatar
        DllCall("gdiplus\GdipDisposeImage", "Ptr", LauncherDiscordAvatar)
    if LauncherDiscordAvatarStream
        ObjRelease(LauncherDiscordAvatarStream)
    LauncherDiscordAvatar := 0
    LauncherDiscordAvatarStream := 0
}

PaintLauncherDiscordPortrait(graphics, face, width, height)
{
    global ButtonPaint, LauncherDiscordAvatar, LauncherDiscordStatus
    signedIn := LauncherDiscordStatus = 2
    image := signedIn ? LauncherDiscordAvatar : ButtonPaint.DiscordLogo
    size := Max(1, Min(width, height) - 4)
    x := (width - size) // 2
    y := (height - size) // 2
    if image
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", graphics, "Ptr", image,
            "Int", x, "Int", y, "Int", size, "Int", size)
    else if signedIn
    {
        ; Keep the account menu visible while the signed-in avatar loads.
        brush := 0
        if !DllCall("gdiplus\GdipCreateSolidFill", "UInt", 0xFFF4E2BE, "Ptr*", &brush)
        {
            DllCall("gdiplus\GdipFillEllipseI", "Ptr", graphics, "Ptr", brush,
                "Int", x + Round(size * 0.33), "Int", y + Round(size * 0.12), "Int", Round(size * 0.34), "Int", Round(size * 0.34))
            DllCall("gdiplus\GdipFillEllipseI", "Ptr", graphics, "Ptr", brush,
                "Int", x + Round(size * 0.18), "Int", y + Round(size * 0.53), "Int", Round(size * 0.64), "Int", Round(size * 0.40))
            DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
        }
    }
    if face.State = "normal" || !face.Control.Enabled
        return
    pen := 0
    if !DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFFF2D88E, "Float", 1.0, "Int", 2, "Ptr*", &pen)
    {
        DllCall("gdiplus\GdipDrawRectangleI", "Ptr", graphics, "Ptr", pen,
            "Int", x - 1, "Int", y - 1, "Int", size + 1, "Int", size + 1)
        DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    }
}

OpenLauncherDiscordAccount(*)
{
    global LauncherDiscordPortrait, LauncherDiscordStatus
    if LauncherDiscordStatus <= 1
    {
        SendLauncherDiscordAccountCommand(16)
        return
    }
    if LauncherDiscordStatus != 2
        return
    dropdown := Menu()
    dropdown.Add("Sign out", (*) => SendLauncherDiscordAccountCommand(17))
    rect := Buffer(16, 0)
    DllCall("user32\GetWindowRect", "Ptr", LauncherDiscordPortrait.Hwnd, "Ptr", rect)
    oldMode := A_CoordModeMenu
    CoordMode("Menu", "Screen")
    try dropdown.Show(NumGet(rect, 0, "Int"), NumGet(rect, 12, "Int"))
    finally CoordMode("Menu", oldMode)
}

SendLauncherDiscordAccountCommand(command)
{
    if !SendLauncherChatCommand(command)
        MsgBox("Discord is unavailable in the launcher. Reopen the launcher and try again.", "Discord account", "Icon!")
}

LauncherDiscordSignOutFailed(wParam, sender, msg, hwnd)
{
    if IsLauncherDiscordMessage(sender, hwnd)
        SetTimer(() => MsgBox("Couldn't sign out of Discord. Try again.", "Discord account", "Icon!"), -1)
}

SendLauncherChatCommand(command, targetHwnd := 0)
{
    global EmbeddedChatPid
    if !EmbeddedChatPid
        return false
    ; Hidden windows must remain addressable while chat is collapsed.
    oldHidden := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try
    {
        for chatHwnd in WinGetList("ahk_pid " EmbeddedChatPid)
        {
            try title := WinGetTitle("ahk_id " chatHwnd)
            catch
                continue
            if title = "tes3np Chat Host"
                return DllCall("PostMessageW", "Ptr", chatHwnd, "UInt", 0x8331, "Ptr", command, "Ptr", targetHwnd) != 0
        }
        LogLauncherEvent("Chat command " command " failed: tes3np Chat Host window not found.")
    }
    finally DetectHiddenWindows(oldHidden)
    return false
}

CreateLauncherChatToggle()
{
    global LauncherGui, LauncherChatToggle, LauncherChatMenu, ButtonFaces
    LauncherChatToggle := AddStyledButton(LauncherGui, 0, 294, 45, 112, "Game Chat", ToggleLauncherChat)
    ButtonFaces[LauncherChatToggle.Hwnd].IsChatTab := true

    ; Chat Host reports visibility and Expansion Pack download state.
    OnMessage(0x8332, LauncherChatStateChanged)
    ; WM_COPYDATA carries the signed ZIP URL to the native retry flow.
    OnMessage(0x004A, TES3MPExpansionZipAvailable)
    OnMessage(0x8338, TES3MPExpansionDownloadProgress)
    OnMessage(0x8336, DiscordExpansionPromptReady)

    LauncherChatMenu := Menu()
    LauncherChatMenu.Add("Automatic", (*) => SendLauncherChatCommand(2))
    LauncherChatMenu.Add("Always Shown", (*) => SendLauncherChatCommand(3))
    LauncherChatMenu.Add("Always Hidden", (*) => SendLauncherChatCommand(4))
    OnMessage(0x0204, LauncherChatRightClick)
}

PaintLauncherChatTab(dc, w, h, label, labelColor, shift)
{
    global LauncherScale, LauncherChatOpen
    ; The outer line covers the artwork's transparent edge. Keep both lines
    ; one pixel wide so the original double frame stays sharp at smaller sizes.
    frame := DllCall("gdi32\CreateSolidBrush", "UInt", 0x00FFFFFF, "Ptr")
    if frame
    {
        try
        {
            rect := Buffer(16, 0)
            NumPut("Int", 0, "Int", 0, "Int", w, "Int", h, rect)
            DllCall("user32\FrameRect", "Ptr", dc, "Ptr", rect, "Ptr", frame)
            NumPut("Int", 2, "Int", 2, "Int", w - 2, "Int", h - 2, rect)
            DllCall("user32\FrameRect", "Ptr", dc, "Ptr", rect, "Ptr", frame)
        }
        finally DllCall("gdi32\DeleteObject", "Ptr", frame)
    }
    ; Scale the rotated caption and arrow with the tab.
    paintScale := LauncherScale / 100
    fontHeight := -Max(9, Round(21 * paintScale))
    font := DllCall("gdi32\CreateFontW",
        "Int", fontHeight, "Int", 0, "Int", 900, "Int", 900,
        "Int", 700, "UInt", 0, "UInt", 0, "UInt", 0,
        "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 0,
        "UInt", 0, "Str", "Segoe UI", "Ptr")
    oldFont := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
    ; Positive 90-degree escapement runs text upward from the baseline.
    DllCall("gdi32\TextOutW", "Ptr", dc, "Int", Round(w * 0.53),
        "Int", Round(h * 0.87) + shift, "Str", label, "Int", StrLen(label))
    DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldFont, "Ptr")
    DllCall("gdi32\DeleteObject", "Ptr", font)
    pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", Max(1, Round(4 * paintScale)), "UInt", labelColor, "Ptr")
    oldPen := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
    cx := Round(w * 0.32), cy := Round(h * 0.50) + shift
    direction := LauncherChatOpen ? -1 : 1
    arrowHalf := Max(4, Round(9 * paintScale))
    arrowHeight := Max(4, Round(10 * paintScale))
    DllCall("gdi32\MoveToEx", "Ptr", dc, "Int", cx - direction * arrowHalf, "Int", cy, "Ptr", 0)
    DllCall("gdi32\LineTo", "Ptr", dc, "Int", cx + direction * arrowHalf, "Int", cy)
    DllCall("gdi32\LineTo", "Ptr", dc, "Int", cx, "Int", cy - arrowHeight)
    DllCall("gdi32\MoveToEx", "Ptr", dc, "Int", cx + direction * arrowHalf, "Int", cy, "Ptr", 0)
    DllCall("gdi32\LineTo", "Ptr", dc, "Int", cx, "Int", cy + arrowHeight)
    DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldPen, "Ptr")
    DllCall("gdi32\DeleteObject", "Ptr", pen)
}

ToggleLauncherChat(*)
{
    ; The host reports visibility after manual toggles and automatic changes.
    SendLauncherChatCommand(1)
}

LauncherChatStateChanged(wParam, lParam, msg, hwnd)
{
    global LauncherGui, LauncherChatToggle, LauncherChatOpen
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd
        return
    LauncherChatOpen := (wParam != 0)
    if IsObject(LauncherChatToggle)
        DllCall("user32\InvalidateRect", "Ptr", LauncherChatToggle.Hwnd, "Ptr", 0, "Int", 0)
    return 0
}

LauncherChatRightClick(wParam, lParam, msg, hwnd)
{
    global LauncherChatToggle, LauncherChatMenu
    if !IsObject(LauncherChatToggle)
        return
    MouseGetPos(,, &windowHwnd, &controlHwnd, 2)
    if controlHwnd = LauncherChatToggle.Hwnd
    {
        LauncherChatMenu.Show()
        return 0
    }
}
