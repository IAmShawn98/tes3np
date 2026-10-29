; WebView2 is hosted by a small .NET Windows Forms helper. The helper
; runs as a child window of the launcher, not as an external Firefox instance.
global EmbeddedChatPid := 0

EnsureEmbeddedChatHostCurrent(host)
{
    ; Development check: source pulls must update the running ChatHost binary.
    project := A_ScriptDir "\chat-host\tes3np.ChatHost.csproj"
    source := A_ScriptDir "\chat-host\Program.cs"
    if !FileExist(project) || !FileExist(source)
        return
    try
    {
        sourceTime := FileGetTime(source, "M")
        hostTime := FileExist(host) ? FileGetTime(host, "M") : "0"
        if (hostTime >= sourceTime)
            return
        LogLauncherEvent("CHAT | ChatHost source is newer than executable; checking .NET SDK.")
        dotnet := ""
        try dotnet := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedhost", "Path")
        catch
            dotnet := ""
        ; Resolve the SDK through PATH, not a hard-coded machine location.
        check := RunWait(A_ComSpec ' /d /c "where dotnet >nul 2>nul"', , "Hide")
        if (check != 0)
        {
            LogLauncherEvent("CHAT | ChatHost rebuild needed, but dotnet is unavailable. Existing executable retained.")
            return
        }
        command := A_ComSpec ' /d /c dotnet publish "' project '" -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:DebugType=None -o "' A_ScriptDir '\chat-host"'
        LogLauncherEvent("CHAT | Rebuilding ChatHost after git pull.")
        result := RunWait(command, A_ScriptDir, "Hide")
        LogLauncherEvent("CHAT | ChatHost rebuild exit code: " result)
    }
    catch as err
        try LogLauncherEvent("CHAT | ChatHost freshness check failed: " err.Message)
}

WebView2RuntimeAvailable()
{
    ; WebView2 Evergreen stores its version per-user or per-machine.
    ; Do not require developer tools or trigger an installer on startup.
    clientKey := "SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7A3F5-28A5-4FBC-9A6A-6F7F8D17E7F0}"
    for root in ["HKCU\", "HKLM\", "HKLM\SOFTWARE\WOW6432Node\"]
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
