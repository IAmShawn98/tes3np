; Shared Morrowind discovery, optional Expansion Pack toggle and import progress.
; The retired bundled v0.1 Install / Repair GUI and worker are deliberately absent.
global MorrowindPromptGui := 0
global ExpansionInstallPromptGui := 0
global ExpansionAutoFailurePromptGui := 0

PatchInProgress()
{
    global PatchJob
    return IsObject(PatchJob)
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

PatchConfigurationPath()
{
    global DataFile
    return IniRead(DataFile, "Patch", "ConfigFile", A_MyDocuments "\My Games\OpenMW\openmw.cfg")
}

UpdatePatchProgress(label, percent)
{
    global PatchFrame, ButtonFaces
    text := label " (" percent "%)"
    if IsObject(PatchFrame) && IsObject(PatchFrame.Panel)
    {
        PatchFrame.Panel.Text := text
        ButtonFaces[PatchFrame.Panel.Hwnd].Progress := Max(0, Min(1, percent / 100))
        PaintButtonNow(PatchFrame.Panel.Hwnd)
    }
}

CheckPatchWorker()
{
    global PatchJob, PatchFrame, DataFile, LauncherGui
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
    PatchJob := 0
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
        MsgBox("Please wait for the current Expansion Pack import to finish before closing tes3np.", "Patch Tes3mp")
        return 1
    }
}

CanUseNPLauncher()
{
    ; Expansion Pack installation is optional. Only block launch while files
    ; are actively being modified; game executable validation happens separately.
    if PatchInProgress()
    {
        MsgBox("Finish the current Expansion Pack operation before launching.", "tes3np")
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
    ; A leftover ESP and a stale content= line cannot prove an active pack.
    ; Trust only an imported ESP whose saved location and SHA-256 still match.
    ; This is local installation evidence, not server compatibility proof.
    verifiedPath := IniRead(DataFile, "ExpansionPack", "VerifiedEspPath", "")
    verifiedHash := StrLower(IniRead(DataFile, "ExpansionPack", "VerifiedEspSHA256", ""))
    if verifiedPath = "" || !RegExMatch(verifiedHash, "i)^[0-9a-f]{64}$")
        return false
    for esp in ExpansionPackEspPaths(morrowind, config)
    {
        try
        {
            if StrLower(esp) = StrLower(verifiedPath)
                && FileExist(esp) && FileGetSize(esp) > 0
                && SHA256File(esp) = verifiedHash
                return true
        }
    }
    return false
}

ExpansionPackEspPaths(morrowind, config)
{
    folders := []
    if morrowind != "" && DirExist(morrowind)
        folders.Push(morrowind "\Data Files")
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

ExpansionPackIsEnabled()
{
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
            LauncherExpansionToggle.Text := "Expansion Pack: " (ExpansionPackIsEnabled() ? "Enabled" : "Disabled")
            DllCall("InvalidateRect", "Ptr", LauncherExpansionToggle.Hwnd, "Ptr", 0, "Int", 1)
        }
    }
}

ToggleExpansionPack(*) => ApplyExpansionPackToggle()

ApplyExpansionPackToggle(checked := false)
{
    global AppDataDirectory, LauncherGui, DataFile, BundledResourceRoot
    if PatchInProgress()
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
    ; Offer a direct OpenMW configuration picker if the game itself exists.
    if !FileExist(cfg)
    {
        selectedConfig := FileSelect(1, , "Choose your active OpenMW configuration", "OpenMW configuration (*.cfg)")
        if selectedConfig = ""
            return
        SplitPath(selectedConfig, &configName)
        if StrLower(configName) != "openmw.cfg"
        {
            MsgBox("Choose the active openmw.cfg file.", "Expansion Pack", "Icon!")
            return
        }
        cfg := selectedConfig
        IniWrite(cfg, DataFile, "Patch", "ConfigFile")
        morrowind := FindMorrowindFolder(cfg)
        enable := !ExpansionPackInLoadOrder(cfg)
    }
    ; Installed packs may live under Morrowind or any configured OpenMW data folder.
    ; Never copy retired bundled Expansion Pack assets.
    if checked && !enable
        return
    if enable && !checked && ExpansionPackEspPaths(morrowind, cfg).Length
        && TES3MPCheckExpansionBeforeAction(cfg, (*) => ApplyExpansionPackToggle(true))
        return
    if enable && !ExpansionPackInstalled(morrowind, cfg)
    {
        ShowExpansionInstallPrompt()
        return
    }
    action := enable ? "Enable" : "Disable"
    if enable
    {
        question := "Are you sure you want to enable your installed expansion pack?"
        explanation := "Enabling the Nerevarine Prophecies expansion pack will activate it for future game clients. You can disable it again at any time without uninstalling it."
    }
    else
    {
        question := "Are you sure you want disable your installed expansion pack?"
        explanation := "Your installed files will stay available. When you turn the pack back on, the launcher will check for an update."
    }
    if MsgBox(question Chr(10) Chr(10) explanation, "Expansion Pack", "YesNo Icon?") != "Yes"
        return
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
    try
    {
        ; Invoke PowerShell directly. cmd.exe nested quoting previously lost
        ; stderr and gave users an empty "was not changed" error.
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
        MsgBox("Expansion Pack " (enable ? "enabled" : "disabled") " successfully for future launches.", "Expansion Pack", "Iconi")
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
    prompt.SetFont("s17 Bold cC5A45C", "Georgia")
    prompt.Add("Text", "x30 y27 w620 h39 BackgroundTrans",
        IsObject(onDecision) ? "Update Expansion Pack" : "Install Expansion Pack")
    prompt.SetFont("s11 Norm cEDE1C9", "Segoe UI")
    if IsObject(onDecision)
    {
        prompt.Add("Text", "x30 y82 w620 h28 BackgroundTrans",
            comparisonUnavailable ? "Could not verify your installed pack. Install the official ZIP?"
                : "Install the latest Expansion Pack from Discord?")
        prompt.SetFont("s11 Bold cEDE1C9", "Segoe UI")
        prompt.Add("Text", "x30 y120 w620 h24 BackgroundTrans", "Installed: " installedVersion)
        prompt.Add("Text", "x30 y148 w620 h24 BackgroundTrans", "Available: " updateVersion)
        AddStyledButton(prompt, 30, 189, 165, 38, "Yes",
            CloseExpansionInstallPrompt.Bind(prompt, "Download"))
        AddStyledButton(prompt, 210, 189, 165, 38, "No",
            CloseExpansionInstallPrompt.Bind(prompt, "Cancel"))
        AddStyledButton(prompt, 390, 189, 260, 38, "Manual Install",
            CloseExpansionInstallPrompt.Bind(prompt, "Upload"))
    }
    else
    {
        prompt.Add("Text", "x30 y89 w620 h81 BackgroundTrans +Wrap",
            "Click yes to automatically download and install the latest and greatest expansion pack listed on Discord.")
        AddStyledButton(prompt, 144, 189, 180, 38, "Yes",
            CloseExpansionInstallPrompt.Bind(prompt, "Download"))
        AddStyledButton(prompt, 356, 189, 180, 38, "No",
            CloseExpansionInstallPrompt.Bind(prompt, "Cancel"))
    }
    prompt.OnEvent("Close", CloseExpansionInstallPrompt.Bind(prompt, "Cancel"))
    prompt.OnEvent("Escape", CloseExpansionInstallPrompt.Bind(prompt, "Cancel"))
    ExpansionInstallPromptGui := prompt
    ShowGoldNativePrompt(prompt)
    return true
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
    prompt.SetFont("s17 Bold cC5A45C", "Georgia")
    prompt.Add("Text", "x30 y24 w640 h43 BackgroundTrans", title)
    prompt.SetFont("s11 Norm cEDE1C9", "Segoe UI")
    prompt.Add("Text", "x30 y86 w640 h91 BackgroundTrans +Wrap", explanation)
    ; Preserve an informative but bounded sanitized failure reason. Never
    ; show signed CDN URLs or raw paths from a private transfer.
    if reason != ""
    {
        shortReason := SubStr(SanitizeDiagnosticText(reason), 1, 180)
        if shortReason != ""
        {
            prompt.SetFont("s9 Norm cD8C38C", "Segoe UI")
            prompt.Add("Text", "x30 y186 w640 h47 BackgroundTrans +Wrap", shortReason)
        }
    }
    AddStyledButton(prompt, 30, 254, 185, 38, "Try Again",
        CloseExpansionAutoFailureDialog.Bind(prompt, "Retry"))
    AddStyledButton(prompt, 230, 254, 270, 38, "Choose ZIP or Folder",
        CloseExpansionAutoFailureDialog.Bind(prompt, "Local"))
    AddStyledButton(prompt, 515, 254, 155, 38, "Cancel",
        CloseExpansionAutoFailureDialog.Bind(prompt, "Cancel"))
    prompt.OnEvent("Close", CloseExpansionAutoFailureDialog.Bind(prompt, "Cancel"))
    prompt.OnEvent("Escape", CloseExpansionAutoFailureDialog.Bind(prompt, "Cancel"))
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
    prompt.SetFont("s17 Bold cC5A45C", "Georgia")
    prompt.Add("Text", "x30 y26 w620 h40 BackgroundTrans", "Morrowind Installation Not Found")
    prompt.SetFont("s10 Norm cEDE1C9", "Segoe UI")
    prompt.Add("Text", "x30 y85 w620 h135 BackgroundTrans",
        "You must locate, install and choose the valid file path of your legally purchased copy of Morrowind in order to play Nerevarine Prophecies. Please install Morrowind, then, click 'Choose Morrowind Folder' and locate your installation path to continue.")
    choose := AddStyledButton(prompt, 30, 268, 392, 42, "Choose Morrowind Folder",
        (*) => SelectFirstRunMorrowind(prompt))
    later := AddStyledButton(prompt, 438, 268, 212, 42, "Not Now",
        (*) => DismissFirstRunMorrowind(prompt))
    prompt.OnEvent("Close", (*) => DismissFirstRunMorrowind(prompt))
    prompt.OnEvent("Escape", (*) => DismissFirstRunMorrowind(prompt))
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
        return true
    }
    LogLauncherEvent("GAME | BLOCKED | Morrowind GOTY data missing; opening folder chooser.")
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
