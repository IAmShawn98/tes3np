; Chat Host runs WebView2 in a child window of the launcher.
global EmbeddedChatPid := 0
global LauncherChatToggle := 0
global LauncherChatMenu := 0
global LauncherChatOpen := false

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
        return
    }
    if EmbeddedChatPid && ProcessExist(EmbeddedChatPid)
        return
    try
    {
        Run('"' host '" ' LauncherGui.Hwnd ' ' LauncherBaseWidth, A_ScriptDir, , &EmbeddedChatPid)
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
    global LauncherGui, LauncherChatToggle, LauncherChatMenu, ButtonFaces
    LauncherChatToggle := AddStyledButton(LauncherGui, 3, 294, 45, 112, "Game Chat", ToggleLauncherChat)
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

PaintLauncherChatCaption(dc, w, h, label, labelColor, shift)
{
    global LauncherScale, LauncherChatOpen
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
    DllCall("gdi32\TextOutW", "Ptr", dc, "Int", Round(w * 0.53) + shift,
        "Int", Round(h * 0.87), "Str", label, "Int", StrLen(label))
    DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldFont, "Ptr")
    DllCall("gdi32\DeleteObject", "Ptr", font)
    pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", Max(1, Round(4 * paintScale)), "UInt", labelColor, "Ptr")
    oldPen := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
    cx := Round(w * 0.32) + shift, cy := Round(h * 0.50)
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
