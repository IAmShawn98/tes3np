; WebView2 is hosted by a small .NET Windows Forms helper. The helper
; runs as a child window of the launcher, not as an external Firefox instance.
global EmbeddedChatPid := 0

EnsureEmbeddedChatHostCurrent(host)
{
    ; Never run a compiler or network restore on the AHK GUI thread.
    ; A source-checkout launch previously waited for a full build here:
    ; a stalled .NET restore left the whole launcher Not Responding. The
    ; explicit Windows build publishes Chat Host before launching TES3NP.
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
    if EmbeddedChatPid && ProcessExist(EmbeddedChatPid)
        try ProcessClose(EmbeddedChatPid)
    EmbeddedChatPid := 0
}
