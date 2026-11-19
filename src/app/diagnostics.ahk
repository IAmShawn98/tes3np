; Launcher logging, log retention, and diagnostic privacy.

global LauncherLogFile := AppDataDirectory "\launcher.log"

GetDiagnosticLogNames()
{
    return ["launcher.log", "chat-host.log", "patch-all.log",
        "patch-errors.log", "render-errors.log"]
}

ReadBugReportLog()
{
    global AppDataDirectory
    ; Keep the existing report attachment budget. Reserve a tail for each
    ; supplemental log and give the remaining space to the launcher log.
    report := ""
    for filename in GetDiagnosticLogNames()
    {
        if filename = "launcher.log"
            continue
        content := ReadBugReportDiagnosticTail(AppDataDirectory "\" filename, 16 * 1024)
        if content != ""
            report .= "`n`n===== " filename " =====`n" content
    }
    launcherHeader := "===== launcher.log =====`n"
    launcherBudget := 96 * 1024 - (StrPut(launcherHeader report, "UTF-8") - 1)
    launcher := ReadBugReportDiagnosticTail(AppDataDirectory "\launcher.log", launcherBudget)
    return launcher = "" ? LTrim(report, "`n") : launcherHeader launcher report
}

ReadBugReportDiagnosticTail(path, byteLimit)
{
    try
    {
        if InStr(FileGetAttrib(path), "L")
            return ""
        file := FileOpen(path, "r", "UTF-8")
        try
        {
            start := file.Length - byteLimit
            if start > 0
            {
                ; Start after a complete line boundary, even if the byte
                ; offset is inside a UTF-8 character.
                file.Pos := start - 1
                while !file.AtEOF && file.ReadUChar() != 10
                    continue
            }
            content := SanitizeDiagnosticText(file.Read(byteLimit))
        }
        finally file.Close()
    }
    catch
        return ""

    if StrPut(content, "UTF-8") - 1 <= byteLimit
        return content
    ; The sanitizer can insert spaces around separators. Cap the resulting
    ; attachment by UTF-8 bytes while keeping the newest complete lines.
    lines := StrSplit(content, "`n")
    tail := ""
    Loop lines.Length
    {
        line := lines[lines.Length - A_Index + 1]
        length := StrPut(line, "UTF-8") - 1 + (tail = "" ? 0 : 1)
        if length > byteLimit
            break
        tail := line (tail = "" ? "" : "`n" tail)
        byteLimit -= length
    }
    return tail
}

TrimStoredDiagnosticLogs()
{
    for filename in GetDiagnosticLogNames()
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

; Scrub older shareable diagnostics in place, keeping private app data separate.
SanitizeExistingDiagnosticLogs()
{
    global AppDataDirectory, DataFile
    if IniRead(DataFile, "Diagnostics", "PrivacyScrubVersion", "") = "4"
        return
    complete := true
    filenames := GetDiagnosticLogNames()
    ; The legacy crash-query output needs privacy cleanup alongside the logs.
    filenames.Push("tes3mp-crash-query.txt")
    for filename in filenames
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
