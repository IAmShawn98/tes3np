; Stage a verified update and coordinate installation, startup confirmation, and recovery.

DownloadAndStageUpdate(manifest, &failureMode)
{
    failureMode := "download"
    root := A_Temp "\tes3np-update\" NewLauncherFileId()
    part := root "\tes3np-windows.zip.part"
    stage := root "\staged"
    DirCreate(root)
    try {
        ; The caller already started the shared loading card's download phase.
        LogLauncherEvent("UPDATE | Download started | v" manifest.version ".")
        Download(manifest.PackageUrl, part)
        if !FileExist(part)
            throw Error("Downloaded update package is missing.")
        failureMode := "verification"
        SetInterfaceLoadingText("Checking download integrity...")
        if FileGetSize(part) != manifest.size
            throw Error("Downloaded update size does not match trusted metadata.")
        SetInterfaceLoadingText("Verifying update...")
        if SHA256File(part) != StrLower(manifest.sha256)
            throw Error("Downloaded update failed SHA-256 verification.")
        LogLauncherEvent("UPDATE | Download verified | SHA-256 and size match trusted metadata.")
        failureMode := "prepare"
        SetInterfaceLoadingText("Preparing installation...")
        ValidateUpdateArchive(part, stage)
        FileDelete(part)
        SetInterfaceLoadingText("Preparing for restart...")
        state := root "\update-state.ini"
        IniWrite("STAGED", state, "Update", "State")
        IniWrite(manifest.version, state, "Update", "Version")
        return root
    } catch {
        DeleteLauncherStagingTree(root)
        throw
    }
}

ValidateUpdateArchive(package, stage)
{
    SplitPath(package, , &root)
    scriptPath := root "\validate-update.ps1"
    script := "$ErrorActionPreference='Stop'`r`n" .
        "Add-Type -AssemblyName System.IO.Compression.FileSystem`r`n" .
        "$package='" PsQuote(package) "'`r`n" .
        "$stage='" PsQuote(stage) "'`r`n" .
        "$z=[IO.Compression.ZipFile]::OpenRead($package)`r`n" .
        "$root=[IO.Path]::GetFullPath($stage+[IO.Path]::DirectorySeparatorChar)`r`n" .
        "try {`r`n" .
        "  foreach($e in $z.Entries){`r`n" .
        "    $p=[IO.Path]::GetFullPath([IO.Path]::Combine($root,$e.FullName))`r`n" .
        "    if(-not $p.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe archive path'}`r`n" .
        "  }`r`n" .
        "} finally { $z.Dispose() }`r`n" .
        "[IO.Compression.ZipFile]::ExtractToDirectory($package,$stage)`r`n" .
        "$exe=Get-ChildItem -LiteralPath $stage -Filter tes3np.exe -Recurse | Select-Object -First 1`r`n" .
        "if(-not $exe){throw 'tes3np.exe missing from staged package'}`r`n"
    try {
        FileAppend(script, scriptPath, "UTF-8")
        shell := ComObject("WScript.Shell")
        powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
        command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' scriptPath '"'
        exitCode := shell.Run(command, 0, true)
        if exitCode != 0
            throw Error("Update package failed safe staging validation.")
    } finally {
        try FileDelete(scriptPath)
    }
    LogLauncherEvent("UPDATE | Package staged and structure validated.")
}

PsQuote(value) => StrReplace(value, "'", "''")

StartTransactionalUpdate(version, staged)
{
    worker := A_ScriptDir "\scripts\tes3np-updater.ps1"
    stateFile := staged "\update-state.ini"

    if PatchInProgress()
        throw Error("Finish the current Expansion Pack operation before updating.")
    if !FileExist(worker)
        throw Error("Updater worker is missing from this installation.")
    if !FileExist(stateFile)
        throw Error("Update state file is missing.")

    pid := DllCall("GetCurrentProcessId", "UInt")

    psArgs := '-NoProfile -ExecutionPolicy Bypass -File "' worker
        . '" -InstallDir "' A_ScriptDir
        . '" -StageDir "' staged '\staged'
        . '" -StateFile "' stateFile
        . '" -Version "' version
        . '" -ManagedStage -ParentPid ' pid

    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    Run('"' powershell '" ' psArgs, A_ScriptDir, "Hide")

    ; Give the detached updater worker time to start before tes3np exits.
    Sleep(500)
}

GetPendingUpdateStatePath()
{
    global AppConfig
    if A_Args.Length < 3 || A_Args[1] != "--update-confirm"
        return ""

    version := A_Args[2]
    statePath := A_Args[3]
    updateRoot := GetFullPath(A_Temp "\tes3np-update")
    statePath := GetFullPath(statePath)
    SplitPath(statePath, &name, &folder)
    ; The legacy updater uses the shared directory. New jobs use individual subdirectories.
    SplitPath(folder, &jobId, &jobParent)
    if name != "update-state.ini" || (folder != updateRoot
        && (jobParent != updateRoot || !RegExMatch(jobId, "i)^[0-9a-f]{32}$")))
        throw Error("Update confirmation state path is invalid.")
    if version != AppConfig.Version
        throw Error("Update confirmation version does not match installed launcher.")
    if !FileExist(statePath)
        throw Error("Update confirmation state file is missing.")
    ; Read UTF-8 directly so a byte-order mark cannot hide the [Update] section.
    lines := StrSplit(FileRead(statePath, "UTF-8"), "`n", "`r")
    if lines.Length < 3 || lines[1] != "[Update]"
        || lines[2] != "State=AWAITING_CONFIRMATION" || lines[3] != "Version=" AppConfig.Version
        throw Error("Update confirmation does not match a pending installation.")
    return statePath
}

ConfirmUpdatedLauncherStartup(statePath)
{
    global AppConfig
    ; The worker polls this file directly. Replace it atomically so the worker
    ; cannot read a partially written confirmation.
    tempConfirmationPath := statePath ".confirm.tmp"
    try FileDelete(tempConfirmationPath)
    confirmation := "[Update]`r`nState=CONFIRMED`r`nVersion=" AppConfig.Version
        . "`r`nUpdatedUtc=" FormatTime(A_NowUTC, "yyyy-MM-ddTHH:mm:ssZ") "`r`n"
    FileAppend(confirmation, tempConfirmationPath, "UTF-8")
    FileMove(tempConfirmationPath, statePath, true)

    LogLauncherEvent("UPDATE | CONFIRMED | Updated launcher v" AppConfig.Version " confirmed successful startup.")
}

RecoverInterruptedLauncherUpdate()
{
    if !A_IsCompiled || !FileExist(A_ScriptDir ".tes3np-recovery\pending.txt")
        return
    worker := A_ScriptDir "\scripts\tes3np-updater.ps1"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    pid := DllCall("GetCurrentProcessId", "UInt")
    Run('"' powershell '" -NoProfile -ExecutionPolicy Bypass -File "' worker
        . '" -InstallDir "' A_ScriptDir '" -Version "' AppConfig.Version
        . '" -RecoverOnly -ParentPid ' pid, A_ScriptDir, "Hide")
    ExitApp(0)
}

GetFullPath(path)
{
    size := DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    if !size
        throw Error("Unable to resolve the full file path.")
    pathBuffer := Buffer(size * 2, 0)
    if !DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", size, "Ptr", pathBuffer, "Ptr", 0, "UInt")
        throw Error("Unable to resolve the full file path.")
    return StrGet(pathBuffer)
}
