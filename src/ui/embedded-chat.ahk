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
    ; ChatHost owns its rectangle via chat.ini, avoiding stale AHK coordinates
    ; overriding live layout edits.
    return
}

StopEmbeddedInGameChat()
{
    global EmbeddedChatPid
    if EmbeddedChatPid && ProcessExist(EmbeddedChatPid)
        try ProcessClose(EmbeddedChatPid)
    EmbeddedChatPid := 0
}
