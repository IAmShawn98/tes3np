; Public-alpha diagnostics and lightweight launcher logging.

global LauncherLogFile := AppDataDirectory "\launcher.log"
global PatchLogMirrorOffset := -1

LogLauncherEvent(message)
{
    global LauncherLogFile
    try
    {
        DirCreate(AppDataDirectory)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " StrReplace(StrReplace(SanitizeDiagnosticText(message), "`r", " "), "`n", " ") "`n", LauncherLogFile, "UTF-8")
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
    ; Central safe boundary for every launcher diagnostic and copied historical log.
    ; Never allow raw credential values, player identities, signed URLs or absolute
    ; machine paths to escape into a shareable diagnostic report.
    global Profiles
    for profile in Profiles
    {
        if !IsObject(profile)
            continue
        if profile.HasOwnProp("Password") && profile.Password != ""
            text := StrReplace(text, profile.Password, "[credential omitted]", false)
    }
    for entry in [[EnvGet("LOCALAPPDATA"), "%LOCALAPPDATA%"],
        [EnvGet("APPDATA"), "%APPDATA%"], [EnvGet("USERPROFILE"), "%USERPROFILE%"]]
    {
        if entry[1] != ""
            text := StrReplace(text, entry[1], entry[2], false)
    }
    userName := EnvGet("USERNAME")
    if userName != "" && StrLen(userName) >= 3
        text := StrReplace(text, userName, "[user omitted]", false)
    ; Field redaction also applies to older logs written before this change.
    text := RegExReplace(text, "i)\b(?:Account|User)\s*:\s*[^|`r`n]+", "[identity omitted]")
    text := RegExReplace(text, "i)\b(?:Password|Token|Secret|Authorization|Cookie|Api[-_]?Key)\s*[:=]\s*[^|`r`n ]+", "[secret omitted]")
    text := RegExReplace(text, "i)\b(?:https?|wss?)://[^ \t\r\n|]+", "[url omitted]")
    text := RegExReplace(text, "i)\b[A-Z]:[\\/][^|`r`n]+", "[path omitted]")
    text := RegExReplace(text, "\\\\[^|`r`n]+", "[network path omitted]")
    text := RegExReplace(text, "i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "[email omitted]")
    text := RegExReplace(text, "\b(?:\d{1,3}\.){3}\d{1,3}\b", "[IP omitted]")
    text := RegExReplace(text, "\b\d{16,21}\b", "[identifier omitted]")
    return text
}

// One-time in-place cleanup of historical diagnostic logs created by older
// builds. This deliberately excludes the private Game Chat message archive,
// settings.ini, backups and WebView2 profile, which are application data.
SanitizeExistingDiagnosticLogs()
{
    global AppDataDirectory, DataFile
    if IniRead(DataFile, "Diagnostics", "PrivacyScrubVersion", "") = "1"
        return
    complete := true
    for filename in ["launcher.log", "chat-host.log", "patch-all.log",
        "patch-errors.log", "render-errors.log"]
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
        try IniWrite("1", DataFile, "Diagnostics", "PrivacyScrubVersion")
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
