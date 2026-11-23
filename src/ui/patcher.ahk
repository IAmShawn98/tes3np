; Shared Morrowind discovery, optional Expansion Pack toggle and import progress.
; The retired bundled v0.1 Install / Repair GUI and worker are deliberately absent.
global MorrowindPromptGui := 0
global ExpansionInstallPromptGui := 0
global ExpansionAutoFailurePromptGui := 0
global ExpansionFoundPromptGui := 0
global ExpansionCheckExistingPromptGui := 0

PatchInProgress()
{
    global PatchJob, ExpansionRecoveryRunning, ExpansionToggleRunning
    return IsObject(PatchJob) || ExpansionRecoveryRunning || ExpansionToggleRunning
}

RecoverExpansionImports()
{
    global AppDataDirectory, BundledResourceRoot, ExpansionRecoveryRunning, ExpansionRecoveryPending
    if PatchInProgress()
        return false
    history := AppDataDirectory "\expansion-imports"
    if !DirExist(history)
    {
        ExpansionRecoveryPending := false
        return true
    }
    resourceRoot := IsSet(BundledResourceRoot) && DirExist(BundledResourceRoot) ? BundledResourceRoot : A_ScriptDir
    worker := resourceRoot "\scripts\import-expansion-pack.ps1"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    ExpansionRecoveryRunning := true
    try
    {
        code := 3
        try code := RunWait('"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'
            . worker '" -RecoverHistory "' history '"', , "Hide")
        ExpansionRecoveryPending := code != 0 && code != 2
    }
    finally
        ExpansionRecoveryRunning := false
    if code = 0
        return true
    if code = 2
    {
        LogLauncherEvent("EXPANSION | Interrupted import rolled back.")
        MsgBox("TES3NP restored the files from an interrupted Expansion Pack import.", "Expansion Pack", "Iconi")
        return true
    }
    LogLauncherEvent("EXPANSION | Interrupted import recovery is pending.")
    MsgBox("TES3NP could not finish checking or recovering an earlier Expansion Pack import. Close any TES3MP/OpenMW clients and restart TES3NP to retry. If recovery is still pending, keep the import backups.", "Expansion Pack", "Icon!")
    return false
}

FindMorrowindFolder(config)
{
    global DataFile
    candidates := [IniRead(DataFile, "Patch", "MorrowindFolder", "")]
    if FileExist(config)
    {
        configText := ""
        try configText := FileRead(config, "UTF-8")
        for line in StrSplit(configText, "`n", "`r")
            if RegExMatch(line, '^\s*data\s*=\s*"?(.+?)"?\s*$', &match)
            {
                data := RTrim(StrReplace(match[1], "/", "\"), "\")
                SplitPath(data, &name, &parent)
                if StrLower(name) = "data files"
                    candidates.Push(parent)
            }
    }
    for registry in ["HKLM\SOFTWARE\WOW6432Node\Bethesda Softworks\Morrowind", "HKLM\SOFTWARE\Bethesda Softworks\Morrowind"]
        try candidates.Push(RegRead(registry, "Installed Path"))
    steamRoots := [EnvGet("ProgramFiles(x86)") "\Steam", EnvGet("ProgramFiles") "\Steam"]
    try steamRoots.InsertAt(1, RegRead("HKCU\Software\Valve\Steam", "SteamPath"))
    candidates.Push("C:\GOG Games\Morrowind")
    for steamRoot in steamRoots
    {
        if !DirExist(steamRoot)
            continue
        candidates.Push(steamRoot "\steamapps\common\Morrowind")
        libraryFile := steamRoot "\steamapps\libraryfolders.vdf"
        if !FileExist(libraryFile)
            continue
        try
        {
            libraryText := FileRead(libraryFile, "UTF-8")
            position := 1
            while RegExMatch(libraryText, 'i)"path"\s*"([^"]+)"', &match, position)
            {
                libraryPath := StrReplace(match[1], "\\", "\")
                candidates.Push(libraryPath "\steamapps\common\Morrowind")
                position := match.Pos(0) + match.Len(0)
            }
        }
    }
    for folder in candidates
        if folder != "" && FileExist(folder "\Data Files\Morrowind.esm")
            && FileExist(folder "\Data Files\Tribunal.esm")
            && FileExist(folder "\Data Files\Bloodmoon.esm")
            return folder
    return ""
}

DefaultOpenMWConfigurationPath() => A_MyDocuments "\My Games\OpenMW\openmw.cfg"

PatchConfigurationPath()
{
    global DataFile
    return IniRead(DataFile, "Patch", "ConfigFile", DefaultOpenMWConfigurationPath())
}

CreateVanillaOpenMWConfiguration(config, morrowind)
{
    if DirExist(config)
        throw Error("The OpenMW configuration path is a folder.")
    if FileExist(config)
        return
    SplitPath(config, , &folder)
    dataPath := StrReplace(RTrim(morrowind, "\/") "\Data Files", "\", "/")
    dataPath := StrReplace(StrReplace(dataPath, "@", "@a"), "#", "@h")
    contents := 'data="' dataPath '"`r`n'
    for master in ["Morrowind", "Tribunal", "Bloodmoon"]
    {
        contents .= "fallback-archive=" master ".bsa`r`n"
            . "content=" master ".esm`r`n"
    }

    ; Publish a complete first-run config without replacing one created by OpenMW.
    temp := config "." NewLauncherFileId() ".tmp"
    try
    {
        DirCreate(folder)
        FileAppend(contents, temp, "UTF-8-RAW")
        FileMove(temp, config, false)
    }
    catch Error as err
    {
        if !FileExist(config) || DirExist(config)
            throw err
    }
    finally
    {
        if FileExist(temp)
            try FileDelete(temp)
    }
}

EnsureOpenMWConfiguration(config, morrowind)
{
    try CreateVanillaOpenMWConfiguration(config, morrowind)
    catch Error as err
    {
        LogLauncherEvent("SETUP | Could not create the OpenMW configuration (" Type(err) ").")
        MsgBox("TES3NP could not create the OpenMW configuration for Morrowind GOTY."
            . "`n`nMake sure this location is writable, then try again.`n" config,
            "Morrowind GOTY Setup", "Icon!")
        return false
    }
    return true
}

PrepareExpansionOpenMWConfiguration(config, morrowind)
{
    if !FileExist(config) && config != DefaultOpenMWConfigurationPath()
    {
        if MsgBox("TES3NP could not find your saved OpenMW configuration.`n`n"
            . "Choose the openmw.cfg that TES3MP uses to manage the Expansion Pack load order.",
            "Locate OpenMW Configuration", "YesNo Icon?") != "Yes"
            return ""
        config := FileSelect(1, , "Locate your OpenMW configuration", "OpenMW configuration (*.cfg)")
        if config = ""
            return ""
    }
    SplitPath(config, &configName)
    if StrLower(configName) != "openmw.cfg" || DirExist(config)
    {
        MsgBox("Choose the openmw.cfg file that TES3MP uses.", "Expansion Pack", "Icon!")
        return ""
    }
    return EnsureOpenMWConfiguration(config, morrowind) ? config : ""
}

UpdatePatchProgress(label, percent)
{
    global PatchFrame
    return UpdateExpansionLoadingProgress(PatchFrame, label " (" percent "%)", percent)
}

CheckPatchWorker()
{
    global PatchJob, PatchFrame, DataFile, LauncherGui, ExpansionRecoveryPending
    if !IsObject(PatchJob)
        return
    job := PatchJob
    progress := job.Folder "\progress.ini"
    if FileExist(progress)
        try
        {
            label := IniRead(progress, "Progress", "Label", "Importing Expansion Pack")
            value := IniRead(progress, "Progress", "Percent", "0")
            UpdatePatchProgress(label, RegExMatch(value, "^\d+$") ? Integer(value) : 0)
        }
    running := job.Handle
        ? DllCall("WaitForSingleObject", "Ptr", job.Handle, "UInt", 0, "UInt") = 258
        : ProcessExist(job.PID)
    if running
        return
    SetTimer(CheckPatchWorker, 0)
    exitCode := "unknown"
    if job.Handle
    {
        code := 0
        if DllCall("GetExitCodeProcess", "Ptr", job.Handle, "UInt*", &code)
            exitCode := code
        DllCall("CloseHandle", "Ptr", job.Handle)
    }
    result := job.Folder "\result.ini"
    state := exitCode = 0 ? "success" : "error"
    try state := IniRead(result, "Result", "State", state)
    if state != "success" || (IsInteger(exitCode) && exitCode != 0)
        state := "error"
    ; If a worker stopped before confirming rollback, wait for recovery before launching.
    if state = "error" && FileExist(job.Folder "\journal.json")
    {
        ExpansionRecoveryPending := true
        try ExpansionRecoveryPending := IniRead(result, "Result", "Rollback", "") != "complete"
    }
    PatchJob := 0
    fallback := state = "success"
        ? "Expansion Pack import complete. Try connecting again."
        : "The Expansion Pack import exited without a result. Exit code: " exitCode ". Keep this attempt's backup files if copying had started."
    message := fallback
    try message := IniRead(result, "Result", "Message", fallback)
    try
    {
        if state = "success"
        {
            ; Record the validated import location, without claiming server compatibility.
            IniWrite(job.MorrowindFolder, DataFile, "Patch", "MorrowindFolder")
            IniWrite(job.ConfigFile, DataFile, "Patch", "ConfigFile")
            ; Record the installed file after the transactional import succeeded.
            installedEsp := RTrim(job.MorrowindFolder, "\/") "\Data Files\NP Expansion Pack.esp"
            installedHash := FileExist(installedEsp) ? SHA256File(installedEsp) : ""
            if !RegExMatch(installedHash, "i)^[0-9a-f]{64}$")
                throw Error("Could not verify the installed Expansion Pack ESP after import.")
            IniWrite(installedEsp, DataFile, "ExpansionPack", "VerifiedEspPath")
            IniWrite(installedHash, DataFile, "ExpansionPack", "VerifiedEspSHA256")
            checksum := ExpansionPackEspChecksum(installedEsp)
            if job.HasOwnProp("OfficialPack") && checksum = job.OfficialPack.Checksum
            {
                try RememberExpansionPackVersion(checksum, job.OfficialPack.Version, job.OfficialPack.Attachment)
            }
            else
            {
                try RememberExpansionPackVersion(checksum, IniRead(result, "Result", "ExpansionVersion", ""))
            }
            LogLauncherEvent("EXPANSION | User-supplied pack imported; live server compatibility not yet tested.")
        }
        RefreshExpansionPackToggle()
        UpdatePatchProgress(state = "success" ? "Waiting for Jiub" : "Expansion Pack needs attention", state = "success" ? 100 : 0)
    }
    catch Error as err
    {
        state := "error"
        message := PatchErrorDetails("Save completed import", "Launcher settings", err)
        LogPatchDiagnostic(message)
    }
    finally
    {
        LauncherGui.Opt("-Disabled")
        ReleaseCapturedInterfaceFrame(PatchFrame)
        PatchFrame := 0
    }
    message := SanitizeDiagnosticText(message)
    if message = ""
        message := "The Expansion Pack operation could not be completed."
    if state = "error"
        LogLauncherEvent("EXPANSION | Import failed | " message)
    ; The auto-downloaded ZIP is transient; the import journal and backups
    ; remain intact for recovery. Never delete user-selected packages.
    autoImport := job.AutoDownloadedZip != ""
    if autoImport
        try FileDelete(job.AutoDownloadedZip)
    ; A finished worker no longer needs extraction or progress files.
    try CleanupFinishedExpansionImport(job.Folder)
    ; Automatic failures get actionable retry/manual/cancel choices in the
    ; same gold-on-dark native card as the version/changelog dialogs.
    ; A local, manually chosen import retains its previous detailed result.
    if state = "error" && autoImport
        ShowExpansionAutoFailureDialog(message, "Install")
    else
        MsgBox(message, "Upload Expansion", state = "error" ? "Icon!" : "Iconi")
}

GuardPatchExit(*)
{
    if PatchInProgress()
    {
        MsgBox("Please wait for the current Expansion Pack operation to finish before closing tes3np.", "Patch Tes3mp")
        return 1
    }
}

CanUseNPLauncher(showMessage := true)
{
    global ExpansionRecoveryPending
    if PatchInProgress()
    {
        if showMessage
            MsgBox("Finish the current Expansion Pack operation before launching.", "tes3np")
        return false
    }
    if ExpansionRecoveryPending
    {
        if showMessage
            MsgBox("An Expansion Pack import still needs recovery. Close any TES3MP/OpenMW clients and restart TES3NP to retry.", "Expansion Pack", "Icon!")
        return false
    }
    return true
}

CleanupPatcher()
{
    global PatchFrame, PatchJob
    SetTimer(CheckPatchWorker, 0)
    if IsObject(PatchJob) && PatchJob.Handle
        DllCall("CloseHandle", "Ptr", PatchJob.Handle)
    PatchJob := 0
    ReleaseCapturedInterfaceFrame(PatchFrame)
    PatchFrame := 0
}

PatchErrorDetails(step, field, err)
{
    reason := SanitizeDiagnosticText(err.Message)
    if reason = ""
        reason := "The operation could not be completed."
    details := "Step: " step "`nField: " field "`nReason: " reason "`nError type: " Type(err)
    extra := SanitizeDiagnosticText(err.Extra)
    if extra != ""
        details .= "`nDetail: " extra
    SplitPath(err.File, &sourceFile)
    if sourceFile != ""
        details .= "`nSource: " sourceFile " — line " err.Line
    return details
}

LogPatchDiagnostic(message)
{
    try
    {
        DirCreate(AppDataDirectory)
        path := AppDataDirectory "\patch-errors.log"
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " " SanitizeDiagnosticText(message)
        FileAppend(StrReplace(StrReplace(line, "`r", ""), "`n", " | ") "`n", path, "UTF-8")
        TrimDiagnosticLog(path)
    }
    catch
    {
        ; A failed diagnostic write must not hide the original error.
    }
}

; Detect an installed NP Expansion Pack in Morrowind or a configured OpenMW data folder.
ExpansionPackInstalled(morrowind, config)
{
    global DataFile
    ; Verify the local import record before enabling a pack already on disk.
    ; Trust only a recorded ESP whose saved location and SHA-256 still match.
    ; The record comes from a completed import or fresh official ZIP check.
    ; This is local installation evidence, not server compatibility proof.
    verifiedPath := ExpansionPackFullPath(IniRead(DataFile, "ExpansionPack", "VerifiedEspPath", ""))
    verifiedHash := StrLower(IniRead(DataFile, "ExpansionPack", "VerifiedEspSHA256", ""))
    if verifiedPath = "" || !RegExMatch(verifiedHash, "i)^[0-9a-f]{64}$")
        return false
    for esp in ExpansionPackEspPaths(morrowind, config)
    {
        try
        {
            if ExpansionPackFullPath(esp) = verifiedPath && FileGetSize(esp) > 0
                && SHA256File(esp) = verifiedHash
                return true
        }
    }
    return false
}

; Recover a missing local record only after an authenticated, current
; official ZIP supplied its verified ESP checksum and release name.
; Existing copies must all agree; a cached historical checksum is insufficient.
RestoreExistingExpansionPackVerification(config, officialChecksum, officialVersion, attachment := "")
{
    global DataFile
    if !RegExMatch(officialChecksum, "i)^[0-9a-f]{8}$")
        || !RegExMatch(officialVersion, "i)^v\d{1,3}(?:\.\d{1,3}){1,3}[a-z]{0,3}$")
        return false
    checksum := StrUpper(officialChecksum)
    morrowind := FindMorrowindFolder(config)
    paths := ExpansionPackEspPaths(morrowind, config)
    if !paths.Length || InstalledExpansionPackChecksum(config) != checksum
        return false

    verifiedPath := ""
    verifiedHash := ""
    for esp in paths
    {
        try
        {
            if FileGetSize(esp) <= 0 || ExpansionPackEspChecksum(esp) != checksum
                return false
            ; A recognizable installed version must not contradict the
            ; current official attachment name.
            version := TES3MPReadExpansionHeaderVersion(esp)
            if version != "" && StrLower(version) != StrLower(officialVersion)
                return false
            hash := StrLower(SHA256File(esp))
            if !RegExMatch(hash, "i)^[0-9a-f]{64}$")
                || (verifiedHash != "" && verifiedHash != hash)
                return false
            fullPath := ExpansionPackFullPath(esp)
            if fullPath = ""
                return false
            if verifiedPath = ""
                verifiedPath := fullPath
            verifiedHash := hash
        }
        catch
            return false
    }
    ; Repeat checks before persisting, in case a game file changed mid-scan.
    if verifiedPath = "" || InstalledExpansionPackChecksum(config) != checksum
        return false
    for esp in paths
    {
        try
            if StrLower(SHA256File(esp)) != verifiedHash
                return false
        catch
            return false
    }
    try
    {
        IniWrite(verifiedPath, DataFile, "ExpansionPack", "VerifiedEspPath")
        IniWrite(verifiedHash, DataFile, "ExpansionPack", "VerifiedEspSHA256")
        if !ExpansionPackInstalled(morrowind, config)
            return false
        RememberExpansionPackVersion(checksum, officialVersion, attachment)
        RefreshExpansionPackToggle()
        LogLauncherEvent("EXPANSION | Existing official pack verified; local installation record restored.")
        return true
    }
    catch
        return false
}

ExpansionPackNeedsOfficialVerification(config)
{
    morrowind := FindMorrowindFolder(config)
    return ExpansionPackEspPaths(morrowind, config).Length
        && !ExpansionPackInstalled(morrowind, config)
}

ExpansionPackFullPath(path)
{
    if path = ""
        return ""
    length := DllCall("GetFullPathNameW", "WStr", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    if !length
        return ""
    fullPath := Buffer(length * 2)
    written := DllCall("GetFullPathNameW", "WStr", path, "UInt", length,
        "Ptr", fullPath.Ptr, "Ptr", 0, "UInt")
    return written && written < length ? StrGet(fullPath.Ptr, written, "UTF-16") : ""
}

ExpansionPackEspPaths(morrowind, config)
{
    folders := []
    if morrowind != "" && DirExist(morrowind)
        folders.Push(RTrim(morrowind, "\/") "\Data Files")
    if FileExist(config)
    {
        try
        {
            for line in StrSplit(FileRead(config, "UTF-8"), "`n", "`r")
            {
                if RegExMatch(Trim(line), 'i)^data\s*=\s*(.+?)\s*$', &match)
                {
                    configured := Trim(Trim(match[1]), Chr(34))
                    if configured != ""
                        folders.Push(configured)
                }
            }
        }
        catch
        {
            ; Unreadable config is not evidence of installation.
        }
    }
    candidates := Map()
    candidates.CaseSense := "Off"
    for folder in folders
    {
        esp := RTrim(StrReplace(folder, "/", "\"), "\") "\NP Expansion Pack.esp"
        if FileExist(esp)
            candidates[esp] := true
    }
    paths := []
    for esp in candidates
        paths.Push(esp)
    return paths
}

ExpansionPackEspChecksum(path)
{
    try
    {
        file := FileOpen(path, "r")
        try
        {
            if file.Length = 0
                return ""
            file.Pos := 0
            chunk := Buffer(65536)
            crc := 0
            while count := file.RawRead(chunk, chunk.Size)
                crc := DllCall("ntdll\RtlComputeCrc32", "UInt", crc, "Ptr", chunk.Ptr, "UInt", count, "UInt")
            return Format("{:08X}", crc)
        }
        finally file.Close()
    }
    return ""
}

InstalledExpansionPackChecksum(config)
{
    ; Several configured paths can expose the same copy. Identify its
    ; version only when every visible copy agrees.
    checksum := ""
    for path in ExpansionPackEspPaths(FindMorrowindFolder(config), config)
    {
        candidate := ExpansionPackEspChecksum(path)
        if candidate = "" || (checksum != "" && candidate != checksum)
            return ""
        checksum := candidate
    }
    return checksum
}

RememberExpansionPackVersion(checksum, version, attachment := "")
{
    global DataFile
    if !RegExMatch(checksum, "i)^[0-9a-f]{8}$") || !RegExMatch(version, "i)^v\d{1,3}(?:\.\d{1,3}){1,3}[a-z]{0,3}$")
        return
    IniWrite(version, DataFile, "ExpansionPackVersions", checksum)
    if RegExMatch(attachment, "^/attachments/\d+/(\d+)/", &match)
        IniWrite(checksum, DataFile, "ExpansionPackChecksums", match[1])
}

KnownExpansionAttachmentChecksum(attachment)
{
    global DataFile
    ; Key by the immutable Discord attachment ID. Signed URLs stay in memory.
    if !RegExMatch(attachment, "^/attachments/\d+/(\d+)/", &match)
        return ""
    checksum := IniRead(DataFile, "ExpansionPackChecksums", match[1], "")
    return RegExMatch(checksum, "i)^[0-9a-f]{8}$") ? checksum : ""
}

InstalledExpansionPackVersion(checksum)
{
    global DataFile
    if RegExMatch(checksum, "i)^[0-9a-f]{8}$")
    {
        version := ""
        try version := InstalledExpansionHeaderVersion(checksum)
        if version != ""
            return version

        version := IniRead(DataFile, "ExpansionPackVersions", checksum, "")
        if RegExMatch(version, "i)^v\d{1,3}(?:\.\d{1,3}){1,3}[a-z]{0,3}$")
            return version

        version := ""
        try version := RecoverExpansionImportVersion(checksum)
        if version != ""
        {
            try RememberExpansionPackVersion(checksum, version)
            return version
        }
    }
    return checksum != "" ? "Unrecognized copy" : "Could not verify"
}

InstalledExpansionHeaderVersion(checksum)
{
    config := PatchConfigurationPath()
    version := ""
    for path in ExpansionPackEspPaths(FindMorrowindFolder(config), config)
    {
        if ExpansionPackEspChecksum(path) != checksum
            return ""
        candidate := TES3MPReadExpansionHeaderVersion(path)
        if candidate = "" || (version != "" && candidate != version)
            return ""
        version := candidate
    }
    return version
}

RecoverExpansionImportVersion(checksum)
{
    global AppDataDirectory, BundledResourceRoot
    config := PatchConfigurationPath()
    paths := ExpansionPackEspPaths(FindMorrowindFolder(config), config)
    if !paths.Length || ExpansionPackEspChecksum(paths[1]) != checksum
        return ""
    history := AppDataDirectory "\expansion-imports"
    if !DirExist(history)
        return ""
    hashes := ""
    for path in paths
    {
        hash := SHA256File(path)
        if !RegExMatch(hash, "i)^[0-9a-f]{64}$")
            return ""
        hashes .= (hashes = "" ? "" : ",") hash
    }
    resourceRoot := IsSet(BundledResourceRoot) && DirExist(BundledResourceRoot) ? BundledResourceRoot : A_ScriptDir
    worker := resourceRoot "\scripts\import-expansion-pack.ps1"
    if !FileExist(worker)
        return ""
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    output := A_Temp "\tes3np-expansion-version-" NewLauncherFileId() ".txt"
    try
    {
        command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' worker '"'
            . ' -ImportHistory "' history '" -InstalledEspSHA256 ' hashes ' -VersionResult "' output '"'
        if RunWait(command, , "Hide") = 0 && FileExist(output)
        {
            version := Trim(FileRead(output, "UTF-8"))
            if RegExMatch(version, "i)^v\d{1,3}(?:\.\d{1,3}){1,3}[a-z]{0,3}$")
                && InstalledExpansionPackChecksum(config) = checksum
                return version
        }
    }
    finally
        try FileDelete(output)
    return ""
}

ExpansionPackInLoadOrder(config)
{
    if !FileExist(config)
        return false
    try
    {
        for line in StrSplit(FileRead(config, "UTF-8"), Chr(10), Chr(13))
            if RegExMatch(Trim(line), 'i)^content\s*=\s*"?NP Expansion Pack\.esp"?$')
                return true
    }
    return false
}

ExpansionPackIsEnabled(config := "")
{
    if config = ""
        config := PatchConfigurationPath()
    return ExpansionPackInLoadOrder(config)
        && ExpansionPackInstalled(FindMorrowindFolder(config), config)
}

RefreshExpansionPackToggle()
{
    global LauncherExpansionToggle
    if IsObject(LauncherExpansionToggle)
    {
        try
        {
            config := PatchConfigurationPath()
            status := "Disabled"
            if ExpansionPackInLoadOrder(config)
                status := ExpansionPackIsEnabled(config) ? "Enabled" : "Unverified"
            LauncherExpansionToggle.Text := "Expansion Pack: " status
            DllCall("InvalidateRect", "Ptr", LauncherExpansionToggle.Hwnd, "Ptr", 0, "Int", 1)
        }
    }
}

ToggleExpansionPack(*) => ApplyExpansionPackToggle()

ApplyExpansionPackToggle(checked := false, disableUnverified := false)
{
    global AppDataDirectory, DataFile, BundledResourceRoot, ExpansionToggleRunning, Client
    if PatchInProgress()
        return
    if !RecoverExpansionImports()
        return
    if ProcessExist("tes3mp.exe") || ProcessExist("openmw.exe") || ProcessExist("openmw-launcher.exe")
    {
        MsgBox("Close all TES3MP/OpenMW clients before switching the Expansion Pack. Running games will not be interrupted.", "Expansion Pack")
        return
    }
    cfg := PatchConfigurationPath()
    enable := !ExpansionPackInLoadOrder(cfg)
    morrowind := FindMorrowindFolder(cfg)
    ; First show the same missing-game prompt used by setup and game launch.
    ; The folder chooser is owned by that prompt; a valid selection resumes
    ; the Expansion Pack toggle rather than silently ending the action.
    if enable && morrowind = ""
    {
        LogLauncherEvent("EXPANSION | Morrowind GOTY not found; opening setup prompt.")
        CheckFirstRunMorrowind(true)
        return
    }
    if checked && !enable
        return
    if !enable && !checked && !disableUnverified && !ExpansionPackInstalled(morrowind, cfg)
        && ExpansionPackEspPaths(morrowind, cfg).Length
    {
        ShowUnverifiedExistingExpansionPackPrompt(cfg)
        return
    }
    if !enable && !ExpansionPackInstalled(morrowind, cfg)
    {
        if MsgBox("The Expansion Pack is in the OpenMW load order, but its installed file could not be verified."
            . "`n`nDisable this load-order entry?", "Expansion Pack", "YesNo Icon?") != "Yes"
            return
    }
    if enable && !checked && FileExist(cfg) && ExpansionPackEspPaths(morrowind, cfg).Length
        && TES3MPCheckExpansionBeforeAction(cfg, (*) => ApplyExpansionPackToggle(true))
        return
    if enable && !ExpansionPackInstalled(morrowind, cfg)
    {
        ShowExpansionInstallPrompt()
        return
    }
    originalConfig := cfg
    cfg := PrepareExpansionOpenMWConfiguration(cfg, morrowind)
    if cfg = ""
        return
    if cfg != originalConfig
    {
        IniWrite(cfg, DataFile, "Patch", "ConfigFile")
        RefreshExpansionPackToggle()
        if !ExpansionPackInLoadOrder(cfg)
            ApplyExpansionPackToggle()
        return
    }
    action := enable ? "Enable" : "Disable"
    resourceRoot := IsSet(BundledResourceRoot) && DirExist(BundledResourceRoot) ? BundledResourceRoot : A_ScriptDir
    script := resourceRoot "\scripts\toggle-expansion-pack.ps1"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(script)
    {
        MsgBox("Expansion Pack toggle helper missing. Rebuild TES3NP.", "Expansion Pack", "Icon!")
        return
    }
    backup := AppDataDirectory "\expansion-backups"
    DirCreate(backup)
    output := AppDataDirectory "\expansion-toggle-result-" NewLauncherFileId() ".txt"
    command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' script '" -Action ' action
        . ' -MorrowindFolder "' morrowind '" -ConfigFile "' cfg '"'
        . ' -BackupFolder "' backup '" -ResultFile "' output '"'
    ; Preflight can yield to another launcher action. Claim the shared worker slot before writing.
    previousCritical := Critical("On")
    try
    {
        if Client.Enabled || !CanUseNPLauncher(false)
            return
        ExpansionToggleRunning := true
    }
    finally Critical(previousCritical)
    try
    {
        ; RunWait yields to launcher callbacks while PowerShell edits the config.
        exitCode := RunWait(command, , "Hide")
        details := FileExist(output) ? SanitizeDiagnosticText(Trim(FileRead(output, "UTF-8"))) : ""
        ; The worker result message alone is not proof of failure or success.
        ; The user's screenshots showed 'Disable complete' incorrectly flagged
        ; as an error. Inspect the actual on-disk OpenMW load order instead.
        actualEnabled := ExpansionPackInLoadOrder(cfg)
        if actualEnabled != enable
        {
            if details = ""
                details := "The OpenMW configuration still has the previous Expansion Pack state. Worker exit code: " exitCode "."
            LogLauncherEvent("EXPANSION | Toggle failed | Exit code: " exitCode ".")
            MsgBox("Expansion Pack was not changed." Chr(10) Chr(10) SubStr(details, 1, 1200), "Expansion Pack", "Icon!")
            RefreshExpansionPackToggle()
            return
        }
        if exitCode
            LogLauncherEvent("EXPANSION | Worker exit code " exitCode " but verified target configuration state.")
        LogLauncherEvent("EXPANSION | " action " verified in openmw.cfg.")
        PruneExpansionToggleBackups(backup)
        RefreshExpansionPackToggle()
        MsgBox("Expansion Pack " (enable ? "enabled" : "disabled") " successfully.", "Expansion Pack", "Iconi")
    }
    catch Error as err
    {
        LogLauncherEvent("EXPANSION | Toggle exception type: " Type(err))
        reason := SanitizeDiagnosticText(err.Message)
        MsgBox(reason != "" ? reason : "Could not update the Expansion Pack.", "Expansion Pack", "Icon!")
    }
    finally
    {
        try FileDelete(output)
        ExpansionToggleRunning := false
    }
}


; Reuse the native gold card for the initial install and update choices.
ShowExpansionInstallPrompt(onDecision := 0, installedVersion := "", updateVersion := "", comparisonUnavailable := false)
{
    global LauncherGui, ExpansionInstallPromptGui
    if IsObject(ExpansionInstallPromptGui)
    {
        try
        {
            if DllCall("IsWindow", "Ptr", ExpansionInstallPromptGui.Hwnd)
            {
                if IsObject(onDecision)
                    return false
                WinActivate("ahk_id " ExpansionInstallPromptGui.Hwnd)
                return
            }
        }
        ExpansionInstallPromptGui := 0
    }
    prompt := CreateGoldNativePrompt(LauncherGui, "Install Expansion Pack", 680, 256)
    prompt.ExpansionDecision := onDecision
    SetAccessibleTextFont(prompt, "s17 Bold cC5A45C", "Georgia")
    extra := AddGoldPromptCopy(prompt, 30, 27, 620, 39,
        IsObject(onDecision) ? "Update Expansion Pack" : "Install Expansion Pack")
    SetAccessibleTextFont(prompt, "s11 Norm cEDE1C9", "Segoe UI")
    if IsObject(onDecision)
    {
        extra += AddGoldPromptCopy(prompt, 30, 82 + extra, 620, 28,
            comparisonUnavailable ? "Could not verify your installed pack. Install the official ZIP?"
                : "Install the latest Expansion Pack from Discord?")
        SetAccessibleTextFont(prompt, "s11 Bold cEDE1C9", "Segoe UI")
        extra += AddGoldPromptCopy(prompt, 30, 120 + extra, 620, 24, "Installed: " installedVersion)
        extra += AddGoldPromptCopy(prompt, 30, 148 + extra, 620, 24, "Available: " updateVersion)
        AddStyledButton(prompt, 30, 189 + extra, 165, 38, "Yes",
            CloseExpansionInstallPrompt.Bind(prompt, "Download"))
        AddStyledButton(prompt, 210, 189 + extra, 165, 38, "No",
            CloseExpansionInstallPrompt.Bind(prompt, "Cancel"))
        AddStyledButton(prompt, 390, 189 + extra, 260, 38, "Manual Install",
            CloseExpansionInstallPrompt.Bind(prompt, "Upload"))
    }
    else
    {
        extra += AddGoldPromptCopy(prompt, 30, 89 + extra, 620, 81,
            "Download and install the official Expansion Pack from Discord, or choose a ZIP or extracted folder you already downloaded.")
        AddStyledButton(prompt, 30, 189 + extra, 226, 38, "Download and Install",
            CloseExpansionInstallPrompt.Bind(prompt, "Download"))
        AddStyledButton(prompt, 271, 189 + extra, 220, 38, "Choose ZIP or Folder",
            CloseExpansionInstallPrompt.Bind(prompt, "Upload"))
        AddStyledButton(prompt, 506, 189 + extra, 144, 38, "Cancel",
            CloseExpansionInstallPrompt.Bind(prompt, "Cancel"))
    }
    GrowGoldNativePrompt(prompt, extra)
    prompt.OnEvent("Close", CloseExpansionInstallPrompt.Bind(prompt, "Cancel"))
    prompt.OnEvent("Escape", CloseExpansionInstallPrompt.Bind(prompt, "Cancel"))
    ExpansionInstallPromptGui := prompt
    ShowGoldNativePrompt(prompt)
    return true
}

; An enabled load-order entry without local verification should first
; offer a safe official check, while still allowing explicit removal.
ShowUnverifiedExistingExpansionPackPrompt(config)
{
    global LauncherGui, ExpansionCheckExistingPromptGui
    if IsObject(ExpansionCheckExistingPromptGui)
        return
    prompt := CreateGoldNativePrompt(LauncherGui, "Check Existing Expansion Pack", 680, 250)
    prompt.ExpansionCheckConfig := config
    SetAccessibleTextFont(prompt, "s17 Bold cC5A45C", "Georgia")
    extra := AddGoldPromptCopy(prompt, 30, 27, 620, 39, "Existing Expansion Pack Detected")
    SetAccessibleTextFont(prompt, "s11 Norm cEDE1C9", "Segoe UI")
    extra += AddGoldPromptCopy(prompt, 30, 80 + extra, 620, 82,
        "TES3NP found the Expansion Pack in your OpenMW load order, but its saved verification record is missing. Check it against the latest official Discord ZIP?")
    AddStyledButton(prompt, 30, 188 + extra, 245, 38, "Verify Existing",
        CloseUnverifiedExistingExpansionPackPrompt.Bind(prompt, "Verify"))
    AddStyledButton(prompt, 290, 188 + extra, 180, 38, "Disable Entry",
        CloseUnverifiedExistingExpansionPackPrompt.Bind(prompt, "Disable"))
    AddStyledButton(prompt, 485, 188 + extra, 165, 38, "Cancel",
        CloseUnverifiedExistingExpansionPackPrompt.Bind(prompt, "Cancel"))
    GrowGoldNativePrompt(prompt, extra)
    prompt.OnEvent("Close", CloseUnverifiedExistingExpansionPackPrompt.Bind(prompt, "Cancel"))
    prompt.OnEvent("Escape", CloseUnverifiedExistingExpansionPackPrompt.Bind(prompt, "Cancel"))
    ExpansionCheckExistingPromptGui := prompt
    ShowGoldNativePrompt(prompt)
}

CloseUnverifiedExistingExpansionPackPrompt(prompt, action := "Cancel", *)
{
    global ExpansionCheckExistingPromptGui
    if !IsObject(ExpansionCheckExistingPromptGui) || ExpansionCheckExistingPromptGui != prompt
        return
    ExpansionCheckExistingPromptGui := 0
    config := prompt.ExpansionCheckConfig
    CloseGoldNativePrompt(prompt)
    if action = "Verify"
    {
        continuation := (*) => RefreshExpansionPackToggle()
        SetTimer(() => TES3MPCheckExpansionBeforeAction(config, continuation, false, true), -1)
    }
    else if action = "Disable"
        SetTimer(() => ApplyExpansionPackToggle(false, true), -1)
}

; Only shown after a fresh authenticated official ZIP checksum matches
; an existing installed copy and its local SHA-256 record was restored.
ShowExistingExpansionPackFoundPrompt(onContinue, alreadyEnabled := false, reviewOnly := false)
{
    global LauncherGui, ExpansionFoundPromptGui
    if IsObject(ExpansionFoundPromptGui)
        return false
    ; A review-only check means the pack was already enabled before recovery.
    alreadyEnabled := alreadyEnabled || reviewOnly
    ; Keep controls inside the gold frame at all scale factors. Any extra
    ; wrapped text increases both the button offset and the dialog height.
    prompt := CreateGoldNativePrompt(LauncherGui, "Existing Expansion Pack Verified", 680, 328)
    prompt.ExpansionFoundContinue := onContinue
    SetAccessibleTextFont(prompt, "s17 Bold cC5A45C", "Georgia")
    extra := AddGoldPromptCopy(prompt, 30, 27, 620, 43, "Existing Expansion Pack Verified")
    SetAccessibleTextFont(prompt, "s11 Norm cEDE1C9", "Segoe UI")
    extra += AddGoldPromptCopy(prompt, 30, 91 + extra, 620, 76,
        "The installed Expansion Pack matches the latest official version. No download or reinstallation is necessary.")
    SetAccessibleTextFont(prompt, "s11 Bold cEDE1C9", "Segoe UI")
    extra += AddGoldPromptCopy(prompt, 30, 182 + extra, 620, 42,
        alreadyEnabled ? "Your Expansion Pack is already enabled."
            : "Would you like to enable it now?")
    if alreadyEnabled
    {
        ; Verification and trust recovery are complete: no redundant
        ; Not Now choice. OK retains the original continuation (game start
        ; or refreshing the enabled status).
        AddStyledButton(prompt, 240, 256 + extra, 200, 40, "OK",
            CloseExistingExpansionPackFoundPrompt.Bind(prompt, true))
    }
    else
    {
        ; The pack is installed but not yet enabled; this is a real choice.
        AddStyledButton(prompt, 88, 256 + extra, 303, 40, "Enable Expansion Pack",
            CloseExistingExpansionPackFoundPrompt.Bind(prompt, true))
        AddStyledButton(prompt, 409, 256 + extra, 183, 40, "Not Now",
            CloseExistingExpansionPackFoundPrompt.Bind(prompt, false))
    }
    GrowGoldNativePrompt(prompt, extra)
    prompt.OnEvent("Close", CloseExistingExpansionPackFoundPrompt.Bind(prompt, false))
    prompt.OnEvent("Escape", CloseExistingExpansionPackFoundPrompt.Bind(prompt, false))
    ExpansionFoundPromptGui := prompt
    ShowGoldNativePrompt(prompt)
    return true
}

CloseExistingExpansionPackFoundPrompt(prompt, proceed := false, *)
{
    global ExpansionFoundPromptGui
    if !IsObject(ExpansionFoundPromptGui) || ExpansionFoundPromptGui != prompt
        return
    ExpansionFoundPromptGui := 0
    onContinue := prompt.ExpansionFoundContinue
    CloseGoldNativePrompt(prompt)
    if proceed && IsObject(onContinue)
        SetTimer(() => onContinue.Call(true), -1)
}

CloseExpansionInstallPrompt(prompt, action := "Cancel", *)
{
    global ExpansionInstallPromptGui
    if !IsObject(ExpansionInstallPromptGui) || ExpansionInstallPromptGui != prompt
        return
    ExpansionInstallPromptGui := 0
    onDecision := prompt.ExpansionDecision
    CloseGoldNativePrompt(prompt)
    if IsObject(onDecision)
        onDecision.Call(action)
    else if action = "Download"
    {
        LogLauncherEvent("EXPANSION | User approved automatic official package discovery.")
        RequestDiscordExpansionPrompt(1)
    }
    else if action = "Upload"
        UploadExpansionFromFile()
}

; A failed Discord transfer (or failed automatic import) must never trap the
; user behind a generic Yes/No MessageBox or require restarting the launcher.
; Retry uses the same authenticated download pipeline; local selection goes
; through the existing verified ZIP/folder importer and backup/rollback path.
ShowExpansionAutoFailureDialog(reason := "", stage := "Download", retry := 0)
{
    global LauncherGui, ExpansionAutoFailurePromptGui
    if IsObject(ExpansionAutoFailurePromptGui)
    {
        try
        {
            if DllCall("IsWindow", "Ptr", ExpansionAutoFailurePromptGui.Hwnd)
            {
                WinActivate("ahk_id " ExpansionAutoFailurePromptGui.Hwnd)
                return
            }
        }
        ExpansionAutoFailurePromptGui := 0
    }
    title := stage = "Check" ? "Check Expansion Pack" : stage = "Install"
        ? "Expansion Pack Installation Failed" : "Expansion Pack Download Failed"
    explanation := stage = "Check"
        ? "Try the Discord check again or choose an official Expansion Pack ZIP or extracted folder from your computer."
        : stage = "Install"
        ? "Automatic installation could not be completed. Existing verified backups are preserved. Try the official download again, or choose your own Expansion Pack ZIP or extracted folder."
        : "The automatic download could not be completed. You can try again, or choose an Expansion Pack ZIP or extracted folder already on your computer."
    prompt := CreateGoldNativePrompt(LauncherGui, title, 700, 318)
    prompt.ExpansionRetry := retry
    SetAccessibleTextFont(prompt, "s17 Bold cC5A45C", "Georgia")
    extra := AddGoldPromptCopy(prompt, 30, 24, 640, 43, title)
    SetAccessibleTextFont(prompt, "s11 Norm cEDE1C9", "Segoe UI")
    extra += AddGoldPromptCopy(prompt, 30, 86 + extra, 640, 91, explanation)
    ; Preserve an informative but bounded sanitized failure reason. Never
    ; show signed CDN URLs or raw paths from a private transfer.
    if reason != ""
    {
        shortReason := SubStr(SanitizeDiagnosticText(reason), 1, 180)
        if shortReason != ""
        {
            SetAccessibleTextFont(prompt, "s9 Norm cD8C38C", "Segoe UI")
            extra += AddGoldPromptCopy(prompt, 30, 186 + extra, 640, 47, shortReason)
        }
    }
    AddStyledButton(prompt, 30, 254 + extra, 185, 38, "Try Again",
        CloseExpansionAutoFailureDialog.Bind(prompt, "Retry"))
    AddStyledButton(prompt, 230, 254 + extra, 270, 38, "Choose ZIP or Folder",
        CloseExpansionAutoFailureDialog.Bind(prompt, "Local"))
    AddStyledButton(prompt, 515, 254 + extra, 155, 38, "Cancel",
        CloseExpansionAutoFailureDialog.Bind(prompt, "Cancel"))
    prompt.OnEvent("Close", CloseExpansionAutoFailureDialog.Bind(prompt, "Cancel"))
    prompt.OnEvent("Escape", CloseExpansionAutoFailureDialog.Bind(prompt, "Cancel"))
    GrowGoldNativePrompt(prompt, extra)
    ExpansionAutoFailurePromptGui := prompt
    ShowGoldNativePrompt(prompt)
}

CloseExpansionAutoFailureDialog(prompt, action := "Cancel", *)
{
    global ExpansionAutoFailurePromptGui
    if !IsObject(ExpansionAutoFailurePromptGui) || ExpansionAutoFailurePromptGui != prompt
        return
    ExpansionAutoFailurePromptGui := 0
    retry := prompt.ExpansionRetry
    CloseGoldNativePrompt(prompt)
    if action = "Retry" && IsObject(retry)
        retry.Call()
    else if action = "Retry"
    {
        LogLauncherEvent("EXPANSION | User requested retry of official automatic Expansion Pack download.")
        RequestDiscordExpansionPrompt(1)
    }
    else if action = "Local"
        UploadExpansionFromFile()
}

; First-run discovery is informational and never installs optional patches.
; A missing Morrowind installation cannot be fixed by downloading TES3MP:
; TES3NP already bundles its own client.
CheckFirstRunMorrowind(resumeExpansion := false, *)
{
    global DataFile, LauncherGui, MorrowindPromptGui
    ; "Not Now" defers the prompt until the next action that needs the game.
    found := FindMorrowindFolder(PatchConfigurationPath())
    if found != ""
    {
        IniWrite(found, DataFile, "Patch", "MorrowindFolder")
        LogLauncherEvent("SETUP | Morrowind GOTY installation located.")
        return
    }
    if IsObject(MorrowindPromptGui)
    {
        if resumeExpansion
            MorrowindPromptGui.ResumeExpansionPack := true
        try
        {
            if DllCall("IsWindow", "Ptr", MorrowindPromptGui.Hwnd)
            {
                WinActivate("ahk_id " MorrowindPromptGui.Hwnd)
                return
            }
        }
        MorrowindPromptGui := 0
    }
    ; Match the native, titlebarless gold-on-dark changelog cards. The
    ; backdrop is owned by the launcher and remains alive during folder
    ; selection and optional automatic Expansion Pack resumption.
    prompt := CreateGoldNativePrompt(LauncherGui, "TES3NP - Morrowind Installation Not Found", 680, 350)
    prompt.ResumeExpansionPack := resumeExpansion
    SetAccessibleTextFont(prompt, "s17 Bold cC5A45C", "Georgia")
    extra := AddGoldPromptCopy(prompt, 30, 26, 620, 40, "Morrowind Installation Not Found")
    SetAccessibleTextFont(prompt, "s10 Norm cEDE1C9", "Segoe UI")
    extra += AddGoldPromptCopy(prompt, 30, 85 + extra, 620, 135,
        "TES3MP needs a legally purchased copy of Morrowind Game of the Year Edition (GOTY), or Morrowind with both Tribunal and Bloodmoon installed. Install the game if needed, then choose the folder that contains Data Files.")
    choose := AddStyledButton(prompt, 30, 268 + extra, 392, 42, "Choose Morrowind Folder",
        (*) => SelectFirstRunMorrowind(prompt))
    later := AddStyledButton(prompt, 438, 268 + extra, 212, 42, "Not Now",
        (*) => DismissFirstRunMorrowind(prompt))
    prompt.OnEvent("Close", (*) => DismissFirstRunMorrowind(prompt))
    prompt.OnEvent("Escape", (*) => DismissFirstRunMorrowind(prompt))
    GrowGoldNativePrompt(prompt, extra)
    MorrowindPromptGui := prompt
    ShowGoldNativePrompt(prompt)
}

; Do not launch TES3MP until all three GOTY master files are present.
EnsureMorrowindForGameLaunch()
{
    global DataFile
    found := FindMorrowindFolder(PatchConfigurationPath())
    if found != ""
    {
        IniWrite(found, DataFile, "Patch", "MorrowindFolder")
        if IniRead(DataFile, "Launch", "ClientMode", "Bundled") = "Bundled"
            return EnsureOpenMWConfiguration(DefaultOpenMWConfigurationPath(), found)
        return true
    }
    LogLauncherEvent("GAME | BLOCKED | Morrowind GOTY data missing; opening setup prompt.")
    CheckFirstRunMorrowind()
    return false
}

SelectFirstRunMorrowind(prompt, *)
{
    global DataFile, MorrowindPromptGui
    folder := FileSelect("D", , "Select Morrowind GOTY installation folder")
    if folder = ""
        return
    folder := RTrim(folder, "\/")
    SplitPath(folder, &folderName, &parent)
    if StrLower(folderName) = "data files"
        folder := parent
    for master in ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm"]
    {
        if !FileExist(folder "\Data Files\" master)
        {
            MsgBox("Could not find Data Files\" master ". Select the Morrowind GOTY folder (not an individual file).", "Morrowind folder", "Icon!")
            return
        }
    }
    IniWrite(folder, DataFile, "Patch", "MorrowindFolder")
    LogLauncherEvent("SETUP | User selected a valid Morrowind GOTY installation.")
    resumeExpansion := prompt.HasOwnProp("ResumeExpansionPack") && prompt.ResumeExpansionPack
    pendingPackage := prompt.HasOwnProp("PendingExpansionPackage") ? prompt.PendingExpansionPackage : ""
    pendingApproved := prompt.HasOwnProp("PendingExpansionApproved") && prompt.PendingExpansionApproved
    MorrowindPromptGui := 0
    CloseGoldNativePrompt(prompt)
    if pendingPackage != ""
        SetTimer(InstallSelectedExpansionPackage.Bind(pendingPackage, pendingApproved), -50)
    else if resumeExpansion
        SetTimer(ToggleExpansionPack, -50)
    else
        MsgBox("Morrowind folder saved. The Expansion Pack remains optional and disabled unless you enable it.", "TES3NP setup", "Iconi")
}

DismissFirstRunMorrowind(prompt, *)
{
    global MorrowindPromptGui
    ; A deferred automatic ZIP belongs to the prompt until it is resumed
    ; or dismissed. Clean it up on cancellation, not during active setup.
    if prompt.HasOwnProp("PendingExpansionApproved") && prompt.PendingExpansionApproved
        && prompt.HasOwnProp("PendingExpansionPackage")
    {
        package := prompt.PendingExpansionPackage
        SplitPath(package, &name, &folder)
        if StrLower(folder) = StrLower(A_AppData "\tes3np\expansion-downloads")
            && RegExMatch(name, "i)^tes3np-[0-9a-f]{32}\.zip$")
            try FileDelete(package)
    }
    ; Do not permanently suppress reminders for missing game files.
    MorrowindPromptGui := 0
    CloseGoldNativePrompt(prompt)
}
