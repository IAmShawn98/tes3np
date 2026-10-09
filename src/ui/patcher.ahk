; Bundled NP setup. PowerShell performs transactional copying off the GUI thread.

IsTES3MPSetupComplete()
{
    global SetupComplete
    return SetupComplete
}

PatchInProgress()
{
    global PatchJob
    return IsObject(PatchJob)
}

FindTES3MPFolder()
{
    global DataFile
    ; Support launchers alongside TES3MP, in its parent folder, or with
    ; TES3MP installed in a child folder.
    for folder in [A_ScriptDir, A_ScriptDir "\..", A_ScriptDir "\tes3mp", A_ScriptDir "\TES3MP", A_ScriptDir "\tes3mp.Win64.release.0.8.1"]
        if FileExist(folder "\tes3mp.exe")
            return folder
    path := IniRead(DataFile, "Patch", "TesFolder", "")
    if FileExist(path "\tes3mp.exe")
        return path
    executable := GetSharedExecutable()
    SplitPath(executable, , &folder)
    return FileExist(executable) ? folder : ""
}

FindMorrowindFolder(config)
{
    global DataFile
    candidates := [IniRead(DataFile, "Patch", "MorrowindFolder", "")]
    if FileExist(config)
        for line in StrSplit(FileRead(config, "UTF-8"), "`n", "`r")
            if RegExMatch(line, '^\s*data\s*=\s*"?(.+?)"?\s*$', &match)
            {
                data := RTrim(StrReplace(match[1], "/", "\"), "\")
                SplitPath(data, &name, &parent)
                if StrLower(name) = "data files"
                    candidates.Push(parent)
            }
    for registry in ["HKLM\SOFTWARE\WOW6432Node\Bethesda Softworks\Morrowind", "HKLM\SOFTWARE\Bethesda Softworks\Morrowind"]
        try candidates.Push(RegRead(registry, "Installed Path"))
    try
    {
        steam := RegRead("HKCU\Software\Valve\Steam", "SteamPath")
        candidates.Push(steam "\steamapps\common\Morrowind")
    }
    candidates.Push(EnvGet("ProgramFiles(x86)") "\Steam\steamapps\common\Morrowind", "C:\GOG Games\Morrowind")
    for folder in candidates
        if folder != "" && FileExist(folder "\Data Files\Morrowind.esm")
            return folder
    return ""
}

PatchConfigurationPath()
{
    global DataFile
    return IniRead(DataFile, "Patch", "ConfigFile", A_MyDocuments "\My Games\OpenMW\openmw.cfg")
}

OpenPatcher(*)
{
    if PatchInProgress()
        return
    global PatchPage, PatchTesInput, PatchMorrowindInput, PatchConfigInput, PatchStatus
    global LauncherGui
    if !IsObject(PatchPage)
    {
        PatchPage := Gui("+Owner" LauncherGui.Hwnd " -MaximizeBox", "tes3np — Patch Tes3mp")
        PatchPage.BackColor := "E2CEA2"
        PatchPage.SetFont("s16 Bold c382314", "Georgia")
        PatchPage.Add("Text", "x20 y15 w720 h30", "Patch Tes3mp")
        PatchPage.SetFont("s10 Norm c382314", "Segoe UI")
        PatchPage.Add("Text", "x20 y55 w720 h70", "Install the supplied markerless client and NP Expansion Pack v0.1. Close the game and OpenMW Launcher first. Existing files are backed up before replacement. Use TES3MP 0.8.1 for 64-bit Windows and Morrowind GOTY.")
        config := PatchConfigurationPath()
        PatchPage.Add("Text", "x20 y130 w720 h22", "TES3MP folder (detected when tes3np is placed inside it)")
        PatchTesInput := PatchPage.Add("Edit", "x20 y155 w620 h25", FindTES3MPFolder())
        browseTes := PatchPage.Add("Button", "x650 y155 w90 h25", "Browse")
        browseTes.OnEvent("Click", BrowsePatchFolder.Bind(PatchTesInput, "Choose the TES3MP folder"))
        PatchPage.Add("Text", "x20 y190 w720 h22", "Morrowind installation folder (contains Data Files)")
        PatchMorrowindInput := PatchPage.Add("Edit", "x20 y215 w620 h25", FindMorrowindFolder(config))
        browseMorrowind := PatchPage.Add("Button", "x650 y215 w90 h25", "Browse")
        browseMorrowind.OnEvent("Click", BrowsePatchFolder.Bind(PatchMorrowindInput, "Choose the Morrowind GOTY folder"))
        PatchPage.Add("Text", "x20 y250 w720 h22", "OpenMW user configuration (EP is enabled at the bottom of this load order)")
        PatchConfigInput := PatchPage.Add("Edit", "x20 y275 w620 h25", config)
        browseConfig := PatchPage.Add("Button", "x650 y275 w90 h25", "Browse")
        browseConfig.OnEvent("Click", BrowsePatchConfiguration)
        license := PatchPage.Add("Button", "x20 y320 w140 h30", "Read EP License")
        license.OnEvent("Click", (*) => Run(A_ScriptDir "\patches\expansion-pack\LICENSE.txt"))
        PatchApplyButton := PatchPage.Add("Button", "x175 y320 w145 h30 Default", "Install / Repair")
        PatchVerifyButton := PatchPage.Add("Button", "x335 y320 w100 h30", "Verify")
        PatchRestoreButton := PatchPage.Add("Button", "x450 y320 w145 h30", "Restore Backup")
        close := PatchPage.Add("Button", "x610 y320 w130 h30", "Close")
        PatchApplyButton.OnEvent("Click", StartPatchAction.Bind("Apply"))
        PatchVerifyButton.OnEvent("Click", StartPatchAction.Bind("Verify"))
        PatchRestoreButton.OnEvent("Click", StartPatchAction.Bind("Restore"))
        close.OnEvent("Click", ClosePatcher)
        PatchPage.OnEvent("Close", ClosePatcher)
        PatchPage.OnEvent("Escape", ClosePatcher)
        PatchPage.Opt("+OwnDialogs")
        PatchStatus := PatchPage.Add("Text", "x20 y370 w720 h75", "Choose the detected folders, read the license, then Install / Repair. The launcher connects directly to NP after setup.")
    }
    PatchPage.Show("w760 h465")
}

ClosePatcher(*)
{
    global PatchPage
    if PatchInProgress()
        return
    PatchPage.Hide()
    ShowLauncherWindow()
}

BrowsePatchFolder(control, title, *)
{
    folder := DirSelect(control.Value, 3, title)
    if folder != ""
        control.Value := folder
}

BrowsePatchConfiguration(*)
{
    global PatchConfigInput
    path := FileSelect(1, PatchConfigInput.Value, "Choose the active OpenMW user configuration", "OpenMW configuration (*.cfg)")
    if path != ""
        PatchConfigInput.Value := path
}

StartPatchAction(action, *)
{
    global PatchTesInput, PatchMorrowindInput, PatchConfigInput, PatchPage, DataFile
    if PatchInProgress()
        return
    tesFolder := Trim(PatchTesInput.Value)
    if action != "Restore" && !CheckModifiedClientForPatch(tesFolder, action)
        return
    if action = "Restore" && MsgBox("Restore files replaced by the most recent patch? Files changed afterward will be protected and may prevent restore.", "Restore Backup", 0x124) != "Yes"
        return
    if action = "Apply" && MsgBox("Install the markerless client, copy the NP Expansion Pack into Morrowind, and enable NP Expansion Pack.esp last in the selected load order? Replaced files will be backed up.", "Patch Tes3mp", 0x124) != "Yes"
        return
    StartPatchWorker(action, tesFolder, Trim(PatchMorrowindInput.Value), Trim(PatchConfigInput.Value), PatchPage)
}

StartPatchWorker(action, tesFolder, morrowindFolder, configFile, sourceGui, startup := false)
{
    global PatchJob, PatchFrame, DataFile, Client, InterfaceLoadingText
    if PatchInProgress()
        return false
    if action != "Verify" && Client.Enabled
    {
        MsgBox("Stop game recovery from the tray, then close TES3MP before patching.", "Patch Tes3mp")
        return false
    }
    selectedField := "TES3MP folder"
    try
    {
        for entry in [["TES3MP folder", tesFolder], ["Morrowind folder", morrowindFolder], ["OpenMW configuration", configFile]]
        {
            selectedField := entry[1]
            if entry[2] = ""
                throw Error("This field is empty. Browse to its location.")
            if RegExMatch(entry[2], '["\r\n]')
                throw Error("The field contains a quote or line break. Choose the location using Browse.")
        }
        selectedField := "TES3MP folder"
        tesFolder := FullPatchPath(tesFolder)
        if !DirExist(tesFolder)
            throw Error("The selected folder does not exist.")
        if !FileExist(tesFolder "\tes3mp.exe")
            throw Error("Missing tes3mp.exe. Choose the folder containing that executable, rather than the launcher folder.")
        selectedField := "Morrowind folder"
        morrowindFolder := FullPatchPath(morrowindFolder)
        if !DirExist(morrowindFolder)
            throw Error("The selected folder does not exist.")
        if !DirExist(morrowindFolder "\Data Files")
            throw Error("Missing Data Files folder. Choose the Morrowind installation folder, rather than Data Files itself.")
        if action != "Restore"
            for master in ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm"]
                if !FileExist(morrowindFolder "\Data Files\" master)
                    throw Error("Missing Data Files\" master ". This patch requires Morrowind GOTY with both expansions installed.")
        selectedField := "OpenMW configuration"
        configFile := FullPatchPath(configFile)
        SplitPath(configFile, &filename)
        if StrLower(filename) != "openmw.cfg"
            throw Error("Choose openmw.cfg. settings.cfg and the configuration folder itself are different items.")
        if DirExist(configFile)
            throw Error("This is a folder; choose the openmw.cfg file inside the active configuration folder.")
    }
    catch Error as err
    {
        ReportPatchError("Validate selected locations", selectedField, err, startup)
        return false
    }
    jobFolder := AppDataDirectory "\patch-jobs\" FormatTime(, "yyyyMMddHHmmss") "-" A_TickCount
    backup := IniRead(DataFile, "Patch", "LastBackup", "")
    if action != "Restore" && (StrLower(IniRead(DataFile, "Patch", "TesFolder", "")) != StrLower(tesFolder)
        || StrLower(IniRead(DataFile, "Patch", "MorrowindFolder", "")) != StrLower(morrowindFolder)
        || StrLower(IniRead(DataFile, "Patch", "ConfigFile", "")) != StrLower(configFile))
        backup := ""
    if action = "Restore" && !FileExist(backup "\journal.json")
    {
        MsgBox("No saved patch backup is available.", "Restore Backup")
        return false
    }
    startStep := "Create patch backup folder"
    try
    {
        DirCreate(jobFolder)
        powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
        helper := A_ScriptDir "\scripts\patch-tes3mp.ps1"
        startStep := "Find patch worker"
        if !FileExist(powershell)
            throw Error("Windows PowerShell was not found. This installer requires Windows PowerShell 5.1.")
        if !FileExist(helper)
            throw Error("Missing scripts\patch-tes3mp.ps1. Extract the entire launcher ZIP.")
        if !FileExist(A_ScriptDir "\patches\manifest.json")
            throw Error("Missing patches\manifest.json. Extract the entire launcher ZIP, including patches.")
        command := QuotePatchArgument(powershell) " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " QuotePatchArgument(helper) " -Action " action
            . " -TesFolder " QuotePatchArgument(tesFolder) " -MorrowindFolder " QuotePatchArgument(morrowindFolder) " -ConfigFile " QuotePatchArgument(configFile)
            . " -PayloadFolder " QuotePatchArgument(A_ScriptDir "\patches") " -JobFolder " QuotePatchArgument(jobFolder)
        if backup != ""
            command .= " -RestoreFolder " QuotePatchArgument(backup) " -PreviousBackup " QuotePatchArgument(backup)
        startStep := "Show patch progress"
        InterfaceLoadingText := "Waiting for Jiub..."
        PatchFrame := CaptureInterfaceFrame(sourceGui, true)
        sourceGui.Opt("+Disabled")
        startStep := "Start Windows PowerShell patch worker"
        Run(command, , "Hide", &pid)
        processHandle := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
        PatchJob := {PID: pid, Handle: processHandle, Folder: jobFolder, Action: action, TesFolder: tesFolder,
            MorrowindFolder: morrowindFolder, ConfigFile: configFile, Source: sourceGui, Startup: startup}
        SetTimer(CheckPatchWorker, 50)
        return true
    }
    catch Error as err
    {
        sourceGui.Opt("-Disabled")
        ReleaseCapturedInterfaceFrame(PatchFrame)
        PatchFrame := 0
        ReportPatchError(startStep, "Patch worker", err, startup)
        return false
    }
}

UpdatePatchProgress(label, percent)
{
    global PatchFrame, ButtonFaces, PatchStatus
    text := label " (" percent "%)"
    if IsSet(PatchStatus)
        PatchStatus.Text := text
    if IsObject(PatchFrame) && IsObject(PatchFrame.Panel)
    {
        PatchFrame.Panel.Text := text
        ButtonFaces[PatchFrame.Panel.Hwnd].Progress := Max(0, Min(1, percent / 100))
        PaintButtonNow(PatchFrame.Panel.Hwnd)
    }
}

CheckPatchWorker()
{
    global PatchJob, PatchFrame, DataFile, SetupComplete, PatchStatus, ExecutableInput
    if !IsObject(PatchJob)
        return
    job := PatchJob
    progress := job.Folder "\progress.ini"
    if FileExist(progress)
    {
        label := IniRead(progress, "Progress", "Label", "Checking setup")
        value := IniRead(progress, "Progress", "Percent", "0")
        UpdatePatchProgress(label, RegExMatch(value, "^\d+$") ? Integer(value) : 0)
    }
    if ProcessExist(job.PID)
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
    state := IniRead(result, "Result", "State", "error")
    message := IniRead(result, "Result", "Message", "Step: Run patch worker | Reason: The worker exited without a result. Exit code: " exitCode ". Check that Windows PowerShell can run scripts/patch-tes3mp.ps1. Keep this attempt's backup files if copying had started.")
    try
    {
        ; Verification must not erase an existing successful installation. 
        ; Only a successful Apply establishes setup; Restore clears it.
        if job.Action = "Apply"
            SetupComplete := state = "success"
        else if job.Action = "Verify" && state = "success"
            SetupComplete := true
        else if job.Action = "Restore" && state = "success"
            SetupComplete := false
        DirCreate(AppDataDirectory)
        IniWrite(SetupComplete ? "1" : "0", DataFile, "Patch", "Complete")
        if state = "success" && (job.Action = "Apply" || job.Action = "Verify")
        {
            for entry in [["TesFolder", job.TesFolder], ["MorrowindFolder", job.MorrowindFolder], ["ConfigFile", job.ConfigFile], ["LastBackup", IniRead(result, "Result", "Backup", "")]]
                IniWrite(entry[2], DataFile, "Patch", entry[1])
            if SetupComplete
            {
                executable := job.TesFolder "\tes3mp.exe"
                IniWrite(executable, DataFile, "Launch", "Executable")
                if IsSet(ExecutableInput)
                    ExecutableInput.Value := executable
            }
        }
        UpdateCharacterMenuLabel()
        UpdatePatchProgress(state = "success" ? "Waiting for Jiub" : "Setup requires attention", state = "success" ? 100 : 0)
    }
    catch Error as err
    {
        SetupComplete := false
        state := "error"
        message := PatchErrorDetails("Save completed setup", "Launcher settings", err)
        LogPatchDiagnostic(message)
        UpdateCharacterMenuLabel()
    }
    finally
    {
        job.Source.Opt("-Disabled")
        ReleaseCapturedInterfaceFrame(PatchFrame)
        PatchFrame := 0
    }
    if IsSet(PatchStatus)
        PatchStatus.Text := message
    ; Show the completion message first. Do not schedule the shortcut dialog
    ; while the completion dialog is still open.
    if job.Startup
    {
        FinishLauncherStartup()
        if state != "success"
        {
            if job.Action = "Verify" && state = "needs_setup"
            {
                if MsgBox("Some Nerevarine Prophecies game files or configuration entries are missing or different. Open Repair Game Install now? Verification did not change any files.", "Game installation needs repair", "YesNo Icon!") = "Yes"
                    OpenPatcher()
            }
            else
            {
                MsgBox(message, "Installation needs attention", "Icon!")
                OpenPatcher()
            }
        }
    }
    else
        MsgBox(message, state = "needs_setup" ? "Setup needed" : "Patch Tes3mp", state = "error" ? "Icon!" : "Iconi")

    if state = "success" && job.Action = "Apply"
    {
        if IsSet(PatchPage) && IsObject(PatchPage)
            PatchPage.Hide()
        ShowLauncherWindow()
        OfferDesktopShortcutOnFirstLaunch(true)
    }
}

BeginStartupPatchCheck()
{
    ; Startup deliberately does not inspect or verify game files. Verification only happens
    ; after the user explicitly chooses Verify or Install / Repair from Patch Tes3mp.
    FinishLauncherStartup()
}

FinishLauncherStartup()
{
    UpdateCharacterMenuLabel()
}

GuardPatchExit(*)
{
    if PatchInProgress()
    {
        MsgBox("Please wait for the current patch operation to finish before closing tes3np.", "Patch Tes3mp")
        return 1
    }
}

CanUseNPLauncher()
{
    if PatchInProgress() || !IsTES3MPSetupComplete()
    {
        MsgBox("Complete Patch Tes3mp setup before launching characters or macros.", "tes3np")
        return false
    }
    return true
}

CleanupPatcher()
{
    global PatchPage, PatchFrame
    SetTimer(CheckPatchWorker, 0)
    ReleaseCapturedInterfaceFrame(PatchFrame)
    PatchFrame := 0
    if IsObject(PatchPage)
        PatchPage.Destroy()
    ; Cleanup runs during launcher shutdown. Do not leave a destroyed GUI object
    ; in shared state in case later cleanup/status code checks PatchPage.
    PatchPage := 0
}

FullPatchPath(path)
{
    pathBuffer := Buffer(65536, 0)
    length := DllCall("GetFullPathNameW", "WStr", path, "UInt", 32768, "Ptr", pathBuffer, "Ptr", 0, "UInt")
    windowsError := A_LastError
    if !length
        throw Error("Windows could not resolve this path. Win32 error " windowsError ". " WindowsPatchError(windowsError))
    if length >= 32768
        throw Error("The resolved path exceeds the Windows path buffer (32768 characters).")
    return StrGet(pathBuffer, "UTF-16")
}

QuotePatchArgument(value)
{
    return '"' RegExReplace(value, "(\\+)$", "$1$1") '"'
}

WindowsPatchError(code)
{
    textBuffer := Buffer(4096, 0)
    length := DllCall("FormatMessageW", "UInt", 0x1200, "Ptr", 0, "UInt", code, "UInt", 0,
        "Ptr", textBuffer, "UInt", 2048, "Ptr", 0, "UInt")
    return length ? Trim(StrGet(textBuffer, "UTF-16"), "`r`n ") : "No Windows error description is available."
}

SanitizePatchDiagnostic(text)
{
    ; Keep detailed reasons while excluding personal paths from dialogs and logs.
    text := RegExReplace(text, 'i)"[A-Z]:\\[^"\r\n]*"', "[path omitted]")
    text := RegExReplace(text, "i)[A-Z]:\\[^`r`n]+", "[path omitted]")
    return RegExReplace(text, "\\\\[^`r`n]+", "[network path omitted]")
}

PatchErrorDetails(step, field, err)
{
    reason := SanitizePatchDiagnostic(err.Message)
    details := "Step: " step "`nField: " field "`nReason: " reason "`nError type: " Type(err)
    if err.Extra != ""
        details .= "`nDetail: " SanitizePatchDiagnostic(err.Extra)
    SplitPath(err.File, &sourceFile)
    if sourceFile != ""
        details .= "`nSource: " sourceFile " — line " err.Line
    return details
}

LogPatchDiagnostic(message)
{
    folder := AppDataDirectory
    try
    {
        DirCreate(folder)
        line := FormatTime(, "yyyy-MM-dd HH:mm:ss") " " StrReplace(StrReplace(SanitizePatchDiagnostic(message), "`r", ""), "`n", " | ") "`n"
        for filename in ["patch-all.log", "patch-errors.log"]
            FileAppend(line, folder "\" filename, "UTF-8")
    }
    catch
    {
        ; An unwritable diagnostic log must not hide the original error dialog.
    }
}

ReportPatchError(step, field, err, startup := false)
{
    global PatchStatus
    details := PatchErrorDetails(step, field, err)
    LogPatchDiagnostic(details)
    if IsSet(PatchStatus)
        PatchStatus.Text := details
    ; Startup errors must never disappear silently behind the launcher.
    MsgBox(details, "Repair Game Install — Error", "Icon!")
}
