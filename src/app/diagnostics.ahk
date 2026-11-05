; Public-alpha diagnostics and lightweight launcher logging.

global LauncherLogFile := AppDataDirectory "\launcher.log"
global PatchLogMirrorOffset := -1

LogLauncherEvent(message)
{
    global LauncherLogFile
    try
    {
        safe := SanitizeDiagnosticText(message)
        if safe = ""
            return
        DirCreate(AppDataDirectory)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " StrReplace(StrReplace(safe, "`r", " "), "`n", " ") "`n", LauncherLogFile, "UTF-8")
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
    ; Shareable diagnostics keep event context but never expose private values.
    ; Older placeholder-style entries are also cleaned up when copied or migrated.
    global Profiles
    text := RegExReplace(text, "i)\[(?:credential|user|identity|secret|url|path|network path|email|IP|identifier|Discord ID) omitted\]", "")
    for profile in Profiles
    {
        if IsObject(profile) && profile.HasOwnProp("Password") && profile.Password != ""
            text := StrReplace(text, profile.Password, "", false)
    }
    clean := ""
    for line in StrSplit(text, "`n", "`r")
    {
        outputLine := ""
        for item in StrSplit(line, "|")
        {
            item := Trim(item)
            ; Drop complete private identity/credential fields, including labels.
            item := RegExReplace(item, "i)\b(?:Account|User|Windows\s+User(?:name)?|Password|Token|Secret|Authorization|Cookie|Api[-_]?Key)\s*[:=].*$", "")
            item := RegExReplace(item, "i)%(?:LOCALAPPDATA|APPDATA|USERPROFILE)%[\\/].*$", "")
            item := RegExReplace(item, "i)\b(?:https?|wss?)://\S+", "")
            item := RegExReplace(item, "i)\b[A-Z]:[\\/].*$", "")
            item := RegExReplace(item, "\\\\.*$", "")
            item := RegExReplace(item, "i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "")
            item := RegExReplace(item, "\b(?:\d{1,3}\.){3}\d{1,3}\b", "")
            item := RegExReplace(item, "\b\d{16,21}\b", "")
            ; A removed value should not leave "Path:", "URL:", or extra pipes.
            item := RegExReplace(item, "i)\b(?:Executable(?:\s+path)?|Source\s+path|Destination|Install|Stage|Path|Folder|File|URL|Mail|Email)\s*[:=]\s*$", "")
            item := Trim(item, " `t:=")
            if item != ""
                outputLine .= (outputLine = "" ? "" : " | ") item
        }
        if outputLine != ""
            clean .= (clean = "" ? "" : "`n") outputLine
    }
    return clean
}

; One-time in-place cleanup of historical diagnostic logs created by older
; builds. This deliberately excludes the private Game Chat message archive,
; settings.ini, backups and WebView2 profile, which are application data.
SanitizeExistingDiagnosticLogs()
{
    global AppDataDirectory, DataFile
    if IniRead(DataFile, "Diagnostics", "PrivacyScrubVersion", "") = "2"
        return
    complete := true
    for filename in ["launcher.log", "chat-host.log", "patch-all.log",
        "patch-errors.log", "render-errors.log", "tes3mp-crash-query.txt"]
    {
        path := AppDataDirectory "\" filename
        if !FileExist(path)
            continue
        temporary := path ".privacy.tmp"
        try
        {
            original := FileRead(path, "UTF-8")
            safe := SanitizeDiagnosticText(original)
            if original = safe
                continue
            try FileDelete(temporary)
            FileAppend(safe, temporary, "UTF-8")
            FileMove(temporary, path, true)
        }
        catch
        {
            complete := false
            try FileDelete(temporary)
        }
    }
    if complete
    {
        try IniWrite("2", DataFile, "Diagnostics", "PrivacyScrubVersion")
    }
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
