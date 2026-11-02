; Public-alpha diagnostics and lightweight launcher logging.

global LauncherLogFile := AppDataDirectory "\launcher.log"
global PatchLogMirrorOffset := -1

LogLauncherEvent(message)
{
    global LauncherLogFile
    try
    {
        DirCreate(AppDataDirectory)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " message "`n", LauncherLogFile, "UTF-8")
    }
}

; The PowerShell patch worker owns patch-all.log. Mirror only new worker events into
; launcher.log so public-alpha reports have one useful timeline without changing the
; worker's existing dedicated diagnostic logs.
SyncPatchLogToLauncherLog(includeExisting := false)
{
    global PatchLogMirrorOffset, LauncherLogFile
    patchLog := AppDataDirectory "\patch-all.log"
    if !FileExist(patchLog)
    {
        PatchLogMirrorOffset := 0
        return
    }
    try
    {
        file := FileOpen(patchLog, "r", "UTF-8")
        if !IsObject(file)
            return
        size := file.Length
        if PatchLogMirrorOffset < 0
        {
            PatchLogMirrorOffset := includeExisting ? 0 : size
            file.Close()
            return
        }
        if size < PatchLogMirrorOffset
            PatchLogMirrorOffset := 0
        if size = PatchLogMirrorOffset
        {
            file.Close()
            return
        }
        file.Pos := PatchLogMirrorOffset
        newText := file.Read()
        PatchLogMirrorOffset := file.Pos
        file.Close()
        for rawLine in StrSplit(newText, "`n", "`r")
        {
            line := Trim(rawLine)
            if line = ""
                continue
            ; patch-all.log already begins with its own timestamp. Keep it as worker
            ; detail while launcher.log supplies the unified event timestamp.
            if RegExMatch(line, "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s+(.*)$", &match)
                line := match[1]
            LogLauncherEvent("PATCH | " SanitizeDiagnosticText(line))
        }
    }
    catch
    {
        ; Mirroring is best-effort and must never interfere with patching.
    }
}

InitializePatchLogMirror()
{
    global PatchLogMirrorOffset
    PatchLogMirrorOffset := -1
    SyncPatchLogToLauncherLog(false)
}

SanitizeDiagnosticText(text)
{
    appData := EnvGet("APPDATA")
    localAppData := EnvGet("LOCALAPPDATA")
    userProfile := EnvGet("USERPROFILE")
    if localAppData != ""
        text := StrReplace(text, localAppData, "%LOCALAPPDATA%", false)
    if appData != ""
        text := StrReplace(text, appData, "%APPDATA%", false)
    if userProfile != ""
        text := StrReplace(text, userProfile, "%USERPROFILE%", false)
    return text
}

OpenLauncherDataFolder(*)
{
    DirCreate(AppDataDirectory)
    Run('explorer.exe "' AppDataDirectory '"')
}

SanitizeDiagnosticPath(path)
{
    return SanitizeDiagnosticText(path)
}
