; Public-alpha diagnostics and lightweight launcher logging.

global LauncherLogFile := AppDataDirectory "\launcher.log"
global PatchLogMirrorOffset := -1

TrimStoredDiagnosticLogs()
{
    for filename in ["launcher.log", "chat-host.log", "patch-all.log",
        "patch-errors.log", "render-errors.log"]
        TrimDiagnosticLog(AppDataDirectory "\" filename)
}

LogLauncherEvent(message)
{
    global LauncherLogFile
    static firstWriteChecked := false
    try
    {
        safe := SanitizeDiagnosticText(message)
        if safe = ""
            return
        DirCreate(AppDataDirectory)
        ; A prior privacy migration could leave an older log without a final
        ; newline. Check once on startup so the first new event never joins it.
        separator := ""
        if !firstWriteChecked
        {
            firstWriteChecked := true
            if FileExist(LauncherLogFile)
            {
                previous := FileOpen(LauncherLogFile, "r", "UTF-8")
                if IsObject(previous)
                {
                    if previous.Length > 0
                    {
                        previous.Pos := previous.Length - 1
                        lastCharacter := previous.Read(1)
                        if lastCharacter != "`n" && lastCharacter != "`r"
                            separator := "`n"
                    }
                    previous.Close()
                }
            }
        }
        FileAppend(separator FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " StrReplace(StrReplace(safe, "`r", " "), "`n", " ") "`n", LauncherLogFile, "UTF-8")
        TrimDiagnosticLog(LauncherLogFile)
    }
}

; Keep recent complete UTF-8 events in the same file used by Copy Logs.
TrimDiagnosticLog(path)
{
    temporary := path ".trim.tmp"
    try
    {
        if !FileExist(path) || FileGetSize(path) <= 2 * 1024 * 1024
            return false
        if InStr(FileGetAttrib(path), "L")
            return false
        file := FileOpen(path, "r", "UTF-8")
        try
        {
            file.Pos := file.Length - 1024 * 1024
            ; Find the first complete line by bytes, even inside a UTF-8 character.
            while !file.AtEOF && file.ReadUChar() != 10
                continue
            tail := file.Read()
        }
        finally file.Close()
        output := FileOpen(temporary, "w", "UTF-8")
        try output.Write(tail)
        finally output.Close()
        FileMove(temporary, path, true)
        return true
    }
    catch
    {
        try FileDelete(temporary)
        return false
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
    windowsUser := EnvGet("USERNAME")
    ; Repair older migration boundaries where the next timestamp was joined
    ; directly after a completed log sentence, before filtering or exporting.
    text := RegExReplace(text, "\.(?=\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| )", ".`n")
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
            ; Clear older privacy notes when migrating existing diagnostics.
            item := StrReplace(item, "Executable path omitted.", "")
            item := StrReplace(item, "Password value not logged.", "")
            item := StrReplace(item, "; local Windows event description omitted for privacy.", ".")
            ; Drop complete private identity/credential fields, including labels.
            item := RegExReplace(item, "i)\b(?:Account|User|Windows\s+User(?:name)?|Password|Token|Secret|Authorization|Cookie|Api[-_]?Key)\s*[:=].*$", "")
            item := RegExReplace(item, "i)%(?:LOCALAPPDATA|APPDATA|USERPROFILE)%(?:[\\/].*)?$", "")
            item := RegExReplace(item, "i)\b(?:https?|wss?)://\S+", "")
            item := RegExReplace(item, "i)\b[A-Z]:[\\/].*$", "")
            item := RegExReplace(item, "\\\\.*$", "")
            item := RegExReplace(item, "i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "")
            item := RegExReplace(item, "\b(?:\d{1,3}\.){3}\d{1,3}\b", "")
            item := RegExReplace(item, "\b\d{16,21}\b", "")
            ; Remove a standalone Windows account name in non-character fields.
            ; The "Character:" field is public gameplay information.
            if StrLen(windowsUser) >= 3 && !RegExMatch(item, "i)^Character\s*:")
                item := RegExReplace(item, "i)(?<![\p{L}\p{N}_])\Q" windowsUser "\E(?![\p{L}\p{N}_])", "")
            item := RegExReplace(item, "[ \t]{2,}", " ")
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
    if IniRead(DataFile, "Diagnostics", "PrivacyScrubVersion", "") = "4"
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
            ; A persisted diagnostic log must terminate its final event before
            ; a future append. Clipboard-only cleanup can omit the final EOL.
            if safe != ""
                safe := RTrim(safe, "`r`n") "`n"
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
        try IniWrite("4", DataFile, "Diagnostics", "PrivacyScrubVersion")
    }
}

OpenLauncherDataFolder(*)
{
    DirCreate(AppDataDirectory)
    Run('explorer.exe "' AppDataDirectory '"')
}
