; Reclaim only files and directories created by TES3NP's cache and staging code.

CleanupStaleLauncherData()
{
    global AppDataDirectory, BundledResourceRoot, MacroRoot, MacroImport, PatchJob
    global LauncherDataResetting, Client, DataFile
    global ExpansionAutoDownloadActive, ExpansionAutoInstallLocked, MorrowindPromptGui
    root := AppDataDirectory
    if LauncherDataResetting || !IsPlainLauncherFolder(root)
        return

    for filename in ["tes3mp-crash-query.ps1", "tes3mp-crash-query.txt",
        "expansion-toggle-result.txt",
        "launcher.log.trim.tmp", "chat-host.log.trim.tmp", "patch-all.log.trim.tmp",
        "patch-errors.log.trim.tmp", "render-errors.log.trim.tmp",
        "launcher.log.privacy.tmp", "chat-host.log.privacy.tmp", "patch-all.log.privacy.tmp",
        "patch-errors.log.privacy.tmp", "render-errors.log.privacy.tmp",
        "tes3mp-crash-query.txt.privacy.tmp"]
    {
        path := root "\" filename
        if IsOldLauncherFile(path, 1)
            try FileDelete(path)
    }
    Loop Files root "\expansion-toggle-result-*.txt", "F"
    {
        if RegExMatch(A_LoopFileName, "i)^expansion-toggle-result-[0-9a-f]{32}\.txt$")
            && IsOldLauncherFile(A_LoopFileFullPath, 1)
            try FileDelete(A_LoopFileFullPath)
    }
    for suffix in [".import.tmp", ".save.tmp"]
        if IsOldLauncherFile(DataFile suffix, 1)
            try FileDelete(DataFile suffix)

    archiveFolder := root "\Logs"
    if IsPlainLauncherFolder(archiveFolder)
        for filename in ["game-chat.log", "game-chat-index.json"]
        {
            path := archiveFolder "\" filename
            if FileExist(path) && IsOldLauncherFile(path ".tmp", 1)
                try FileDelete(path ".tmp")
        }
    if IsPlainLauncherFolder(archiveFolder)
        Loop Files archiveFolder "\*.tmp", "F"
        {
            if RegExMatch(A_LoopFileName, "i)^game-chat(\.log|-index\.json)\.[0-9a-f]{32}\.tmp$")
                && IsOldLauncherFile(A_LoopFileFullPath, 1)
                try FileDelete(A_LoopFileFullPath)
        }

    ; Only the uncommitted copy is disposable. Recovery owns overrides/previous.
    customClient := root "\custom-client"
    if IsPlainLauncherFolder(customClient) && IsOldLauncherFile(customClient "\incoming", 1)
        DeleteLauncherStagingTree(customClient "\incoming")

    portraits := root "\portraits"
    if IsPlainLauncherFolder(portraits)
        Loop Files portraits "\*.tmp", "F"
        {
            if RegExMatch(A_LoopFileName, "i)^[0-9a-f]{32}\.(png|jpg|jpeg|bmp)\.tmp$")
                && IsOldLauncherFile(A_LoopFileFullPath, 1)
                try FileDelete(A_LoopFileFullPath)
        }
    PruneExpansionToggleBackups(root "\expansion-backups")

    updateRoot := A_Temp "\tes3np-update"
    if IsPlainLauncherFolder(updateRoot)
        Loop Files updateRoot "\*", "D"
        {
            if RegExMatch(A_LoopFileName, "i)^[0-9a-f]{32}$")
                && IsOldLauncherFile(A_LoopFileFullPath, 7)
                DeleteLauncherStagingTree(A_LoopFileFullPath)
        }

    if IsPlainLauncherFolder(MacroRoot)
        Loop Files MacroRoot "\import-*", "D"
        {
            if !IsMacroImportFolderName(A_LoopFileName)
                || (IsObject(MacroImport) && MacroImport.Folder = A_LoopFileFullPath)
                continue
            if IsOldLauncherFile(A_LoopFileFullPath, 1)
                DeleteLauncherStagingTree(A_LoopFileFullPath)
        }

    downloads := root "\expansion-downloads"
    pendingZip := IsObject(MorrowindPromptGui) && MorrowindPromptGui.HasOwnProp("PendingExpansionPackage")
        ? MorrowindPromptGui.PendingExpansionPackage : ""
    if !IsObject(PatchJob) && !ExpansionAutoDownloadActive && !ExpansionAutoInstallLocked
        && IsPlainLauncherFolder(downloads)
        Loop Files downloads "\tes3np-*", "F"
        {
            if A_LoopFileFullPath != pendingZip && RegExMatch(A_LoopFileName, "i)^tes3np-[0-9a-f]{32}\.(partial|zip)$")
                && IsOldLauncherFile(A_LoopFileFullPath, 7)
                try FileDelete(A_LoopFileFullPath)
        }

    imports := root "\expansion-imports"
    if IsPlainLauncherFolder(imports)
        Loop Files imports "\*", "D"
        {
            job := A_LoopFileFullPath
            if !RegExMatch(A_LoopFileName, "i)^(\d{14}-\d+|[0-9a-f]{32})$")
                || !IsPlainLauncherFolder(job) || !IsOldLauncherFile(job, 7)
                || (IsObject(PatchJob) && PatchJob.Folder = job)
                continue
            CleanupFinishedExpansionImport(job)
        }

    if A_IsCompiled && IsSet(BundledResourceRoot)
    {
        try FileSetTime(, BundledResourceRoot "\resource-version.txt")
        PruneLauncherCache(root "\resources", "i)^v-[0-9a-f]{20}$", "resource-version.txt",
            [BundledResourceRoot], 30)
    }
    ; Game clients can outlive the launcher. Leave all runtimes alone while
    ; any TES3MP process may still read its DLLs, layouts, or configuration.
    if !Client.Enabled && !ProcessExist("tes3mp.exe")
    {
        keep := []
        for key in ["CustomExecutable", "Executable"]
        {
            SplitPath(IniRead(DataFile, "Launch", key, ""), , &folder)
            if folder != ""
                keep.Push(folder)
        }
        PruneLauncherCache(root "\client-cache", "i)^(merged-)?[0-9a-f]{8}(-[0-9a-f]{32})?$", ".ready", keep, 30)
    }
}

IsMacroImportFolderName(name)
{
    return RegExMatch(name, "i)^import-\d{14}-(\d+|[0-9a-f]{32})$")
}

PruneExpansionToggleBackups(root)
{
    if !IsPlainLauncherFolder(root)
        return
    backups := ""
    Loop Files root "\openmw-*.cfg", "F"
    {
        if RegExMatch(A_LoopFileName, "^openmw-\d{17}\.cfg$") && !InStr(A_LoopFileAttrib, "L")
            backups .= A_LoopFileName "`n"
    }
    ; Timestamped names sort newest first. Keep five and all recent backups.
    for index, filename in StrSplit(Sort(RTrim(backups, "`n"), "R"), "`n")
    {
        if index <= 5
            continue
        path := root "\" filename
        if IsOldLauncherFile(path, 30)
            try FileDelete(path)
    }
}

CleanupFinishedExpansionImport(job)
{
    if !IsPlainLauncherFolder(job)
        return
    DeleteLauncherStagingTree(job "\stage")
    for filename in ["prepared-openmw.cfg", "progress.ini", "stage-cleanup-warning.txt"]
    {
        path := job "\" filename
        try
            if FileExist(path) && !InStr(FileGetAttrib(path), "L")
                FileDelete(path)
    }
    ; Keep the rollback journal and backups if game files might need recovery.
    result := job "\result.ini"
    if (IniRead(result, "Result", "State", "") = "error"
        && IniRead(result, "Result", "Rollback", "") = "complete")
        || (!FileExist(job "\journal.json") && !FileExist(job "\backup"))
        DeleteLauncherStagingTree(job)
}

PruneLauncherCache(root, namePattern, marker, keep, minimumAgeDays)
{
    if !IsPlainLauncherFolder(root)
        return
    protected := Map()
    protected.CaseSense := "Off"
    for folder in keep
        protected[folder] := true
    newest := "", newestTime := 0
    Loop Files root "\*", "D"
    {
        if !RegExMatch(A_LoopFileName, namePattern) || InStr(A_LoopFileAttrib, "L")
            || protected.Has(A_LoopFileFullPath) || !FileExist(A_LoopFileFullPath "\" marker)
            continue
        stamp := Integer(A_LoopFileTimeModified)
        try stamp := Max(stamp, FileGetTime(A_LoopFileFullPath "\" marker, "M"))
        if stamp > newestTime
        {
            newest := A_LoopFileFullPath
            newestTime := stamp
        }
    }
    Loop Files root "\*", "D"
    {
        if RegExMatch(A_LoopFileName, namePattern) && !protected.Has(A_LoopFileFullPath)
            && A_LoopFileFullPath != newest && IsOldLauncherFile(A_LoopFileFullPath, minimumAgeDays)
            && (!FileExist(A_LoopFileFullPath "\" marker)
                || IsOldLauncherFile(A_LoopFileFullPath "\" marker, minimumAgeDays))
        {
            if marker = ".ready" && ProcessExist("tes3mp.exe")
                return
            DeleteLauncherStagingTree(A_LoopFileFullPath)
        }
    }
}

IsPlainLauncherFolder(path)
{
    attributes := DirExist(path)
    return attributes != "" && !InStr(attributes, "L")
}

IsOldLauncherFile(path, days)
{
    try return !InStr(FileGetAttrib(path), "L") && DateDiff(A_Now, FileGetTime(path, "M"), "Days") >= days
    catch
        return false
}

; Walk only within an owned tree and never follow reparse points.
DeleteLauncherStagingTree(path)
{
    if !IsPlainLauncherFolder(path)
        return
    Loop Files path "\*", "FD"
    {
        if InStr(A_LoopFileAttrib, "L")
            continue
        if InStr(A_LoopFileAttrib, "D")
            DeleteLauncherStagingTree(A_LoopFileFullPath)
        else
            try FileDelete(A_LoopFileFullPath)
    }
    try DirDelete(path)
}
