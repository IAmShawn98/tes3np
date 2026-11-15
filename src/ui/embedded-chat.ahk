; Chat Host runs WebView2 in a child window of the launcher.
global EmbeddedChatPid := 0
global LauncherChatToggle := 0
global LauncherChatMenu := 0
global LauncherChatOpen := false

EnsureEmbeddedChatHostCurrent(host)
{
    ; Check freshness without blocking the launcher on a build or network restore.
    source := A_ScriptDir "\chat-host\Program.cs"
    if !FileExist(source)
        return
    try
    {
        sourceTime := FileGetTime(source, "M")
        hostTime := FileExist(host) ? FileGetTime(host, "M") : "0"
        if hostTime < sourceTime
            LogLauncherEvent("CHAT | ChatHost source is newer than the executable. Use the Windows build script to update; startup will not block on compilation.")
    }
    catch as err
        try LogLauncherEvent("CHAT | ChatHost freshness check failed (" Type(err) ").")
}

WebView2RuntimeAvailable()
{
    ; WebView2 Evergreen stores its version per-user or per-machine.
    ; Do not require developer tools or trigger an installer on startup.
    clientKey := "SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7A3F5-28A5-4FBC-9A6A-6F7F8D17E7F0}"
    for root in ["HKCU\", "HKLM\"]
    {
        try
        {
            value := RegRead(root clientKey, "pv", "")
            if value != "" && value != "0.0.0.0"
                return true
        }
    }
    return false
}

StartEmbeddedInGameChat()
{
    global EmbeddedChatPid, LauncherGui
    host := A_ScriptDir "\chat-host\tes3np.ChatHost.exe"
    EnsureEmbeddedChatHostCurrent(host)
    if !WebView2RuntimeAvailable()
        LogLauncherEvent("CHAT | WebView2 runtime not detected in standard registry locations. Attempting chat host launch; gameplay is unaffected.")
    if !FileExist(host)
    {
        try LogLauncherEvent("CHAT | Embedded host executable not installed.")
        return
    }
    if EmbeddedChatPid && ProcessExist(EmbeddedChatPid)
        return
    try
    {
        Run('"' host '" ' LauncherGui.Hwnd, A_ScriptDir, , &EmbeddedChatPid)
        LogLauncherEvent("CHAT | Started WebView2 host (PID " EmbeddedChatPid ").")
    }
    catch as err
    {
        EmbeddedChatPid := 0
        try LogLauncherEvent("CHAT | Failed to start WebView2 host (" Type(err) ").")
    }
}

StopEmbeddedInGameChat()
{
    global EmbeddedChatPid
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
    global LauncherGui, LauncherChatToggle, LauncherChatMenu
    LauncherGui.SetFont("s11 Bold cFFFFFF", "Segoe UI")
    LauncherChatToggle := LauncherGui.Add("Text",
        "x3 y294 w45 h112 +0x100 BackgroundA77C3A", "")
    OnMessage(0x000F, PaintLauncherChatToggle)
    ; The themed-button handlers can intercept WM_COMMAND, so use the control's Click event.
    LauncherChatToggle.OnEvent("Click", ToggleLauncherChat)

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

PaintLauncherChatToggle(wParam, lParam, msg, hwnd)
{
    global LauncherChatToggle, LauncherScale, LauncherChatOpen
    if !IsObject(LauncherChatToggle) || hwnd != LauncherChatToggle.Hwnd
        return
    ; Paint the rotated caption directly to avoid clipping inside the static control.
    ps := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
    dc := DllCall("user32\BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
    if !dc
        return
    try
    {
        rect := Buffer(16, 0)
        DllCall("user32\GetClientRect", "Ptr", hwnd, "Ptr", rect)
        w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
        gold := DllCall("gdi32\CreateSolidBrush", "UInt", 0x003A7CA7, "Ptr")
        DllCall("user32\FillRect", "Ptr", dc, "Ptr", rect, "Ptr", gold)
        DllCall("gdi32\DeleteObject", "Ptr", gold)
        frame := DllCall("gdi32\CreateSolidBrush", "UInt", 0x0078C7ED, "Ptr")
        DllCall("user32\FrameRect", "Ptr", dc, "Ptr", rect, "Ptr", frame)
        NumPut("Int", 2, rect, 0)
        NumPut("Int", 2, rect, 4)
        NumPut("Int", w - 2, rect, 8)
        NumPut("Int", h - 2, rect, 12)
        DllCall("user32\FrameRect", "Ptr", dc, "Ptr", rect, "Ptr", frame)
        DllCall("gdi32\DeleteObject", "Ptr", frame)
        DllCall("gdi32\SetBkMode", "Ptr", dc, "Int", 1)
        DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", 0x00FFFFFF)
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
            "Int", Round(h * 0.87), "Str", "Game Chat", "Int", 9)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldFont, "Ptr")
        DllCall("gdi32\DeleteObject", "Ptr", font)
        pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", Max(1, Round(4 * paintScale)), "UInt", 0x00FFFFFF, "Ptr")
        oldPen := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
        cx := Round(w * 0.32), cy := Round(h * 0.50)
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
    finally DllCall("user32\EndPaint", "Ptr", hwnd, "Ptr", ps)
    return 0
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
        DllCall("user32\InvalidateRect", "Ptr", LauncherChatToggle.Hwnd, "Ptr", 0, "Int", 1)
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
