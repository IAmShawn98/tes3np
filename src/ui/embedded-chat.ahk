; WebView2 is hosted by a small .NET Windows Forms helper. The helper
; runs as a child window of the launcher, not as an external Firefox instance.
global EmbeddedChatPid := 0

StartEmbeddedInGameChat()
{
    global EmbeddedChatPid, LauncherGui
    host := A_ScriptDir "\chat-host\tes3np.ChatHost.exe"
    if !FileExist(host)
    {
        try LogLauncherEvent("CHAT | Embedded host not installed: " host)
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
        try LogLauncherEvent("CHAT | Failed to start WebView2 host: " err.Message)
    }
}

ResizeEmbeddedInGameChat()
{
    global LauncherGui, LauncherScale
    ; The companion is a Win32 child of the launcher, so the launcher controls
    ; its logical viewport. Find by executable PID to avoid moving other windows.
    global EmbeddedChatPid
    if !EmbeddedChatPid || !ProcessExist(EmbeddedChatPid)
        return
    hwnd := WinExist("ahk_pid " EmbeddedChatPid)
    if !hwnd
        return
    scale := LauncherScale / 100
    try DllCall("MoveWindow", "Ptr", hwnd, "Int", Round(125 * scale),
        "Int", Round(315 * scale), "Int", Round(260 * scale),
        "Int", Round(330 * scale), "Int", 1)
}

StopEmbeddedInGameChat()
{
    global EmbeddedChatPid
    if EmbeddedChatPid && ProcessExist(EmbeddedChatPid)
        try ProcessClose(EmbeddedChatPid)
    EmbeddedChatPid := 0
}
