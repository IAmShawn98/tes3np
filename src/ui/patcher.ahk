; Shared Morrowind discovery, optional Expansion Pack toggle and import progress.
; The retired bundled v0.1 Install / Repair GUI and worker are deliberately absent.
global MorrowindPromptGui := 0

PatchInProgress()
{
    global PatchJob
    return IsObject(PatchJob)
}

FindTES3MPFolder()
{
    global DataFile
    ; Prefer the user's verified choice, then common installs and Steam libraries.
    ; Detection is read-only: do not change or replace the vanilla executable.
    candidates := [IniRead(DataFile, "Patch", "TesFolder", ""),
        IniRead(DataFile, "Launch", "Executable", ""),
        A_ScriptDir, A_ScriptDir "\..", A_ScriptDir "\..\..",
        A_MyDocuments, A_Desktop, A_MyDocuments "\TES3MP",
        A_MyDocuments "\My Games\TES3MP",
        EnvGet("USERPROFILE") "\Downloads",
        EnvGet("USERPROFILE") "\Desktop",
        EnvGet("LOCALAPPDATA") "\Programs",
        EnvGet("ProgramFiles") "\TES3MP",
        EnvGet("ProgramFiles(x86)") "\TES3MP",
        "C:\Games", "C:\TES3MP", "C:\OpenMW"]
    steamRoots := []
    for key in ["HKCU\Software\Valve\Steam", "HKLM\SOFTWARE\WOW6432Node\Valve\Steam",
        "HKLM\SOFTWARE\Valve\Steam"]
        for valueName in ["SteamPath", "InstallPath"]
            try
            {
                steamRoot := RegRead(key, valueName)
                if DirExist(steamRoot)
                    steamRoots.Push(steamRoot)
            }
    for folder in [EnvGet("ProgramFiles(x86)") "\Steam", EnvGet("ProgramFiles") "\Steam"]
        if DirExist(folder)
            steamRoots.Push(folder)
    for steam in steamRoots
    {
        candidates.Push(steam "\steamapps\common")
        libraryFile := steam "\steamapps\libraryfolders.vdf"
        if FileExist(libraryFile)
        {
            try
            {
                libraryText := FileRead(libraryFile, "UTF-8")
                position := 1
                while RegExMatch(libraryText, 'i)"path"\s*"([^"]+)"', &match, position)
                {
                    libraryPath := StrReplace(match[1], "\\", "\")
                    candidates.Push(libraryPath "\steamapps\common")
                    position := match.Pos(0) + match.Len(0)
                }
            }
        }
    }
    visited := Map()
    for base in candidates
    {
        if base = ""
            continue
        if FileExist(base) && !DirExist(base)
            SplitPath(base, , &base)
        if !DirExist(base)
            continue
        ; Check selected folder and immediate children only; avoid a blocking
        ; full-drive crawl on launcher startup.
        paths := [base, base "\TES3MP", base "\tes3mp.Win64.release.0.8.1",
            base "\tes3mp.Win64.release.0.8.1\tes3mp.Win64.release.0.8.1"]
        try
        {
            Loop Files, base "\*", "D"
                if InStr(StrLower(A_LoopFileName), "tes3mp")
                    paths.Push(A_LoopFileFullPath)
        }
        for path in paths
        {
            normalized := StrLower(RTrim(path, "\/"))
            if visited.Has(normalized)
                continue
            visited[normalized] := true
            if normalized = StrLower(RTrim(A_ScriptDir "\client", "\/"))
                continue
            if FileExist(path "\tes3mp.exe") && FileExist(path "\openmw.cfg")
                return path
        }
    }
    return ""
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
    ; A secondary Steam library can live on another drive. Read Steam's
    ; registered library paths rather than guessing drive letters.
    for steamRoot in [EnvGet("ProgramFiles(x86)") "\Steam", EnvGet("ProgramFiles") "\Steam"]
    {
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
    global PatchJob, PatchFrame, DataFile
    if !IsObject(PatchJob)
        return
    job := PatchJob
    progress := job.Folder "\progress.ini"
    if FileExist(progress)
    {
        label := IniRead(progress, "Progress", "Label", "Importing Expansion Pack")
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
    message := IniRead(result, "Result", "Message", "The Expansion Pack import exited without a result. Exit code: " exitCode ". Check scripts/import-expansion-pack.ps1. Keep this attempt's backup files if copying had started.")
    try
    {
        if job.Action != "Import"
            throw Error("Unsupported retired installer operation.")
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
            IniWrite("1", DataFile, "ExpansionPack", "GlobalEnabled")
            LogLauncherEvent("EXPANSION | User-supplied pack imported; live server compatibility not yet tested.")
        }
        UpdateCharacterMenuLabel()
        RefreshExpansionPackToggle()
        UpdatePatchProgress(state = "success" ? "Waiting for Jiub" : "Expansion Pack needs attention", state = "success" ? 100 : 0)
    }
    catch Error as err
    {
        state := "error"
        message := PatchErrorDetails("Save completed import", "Launcher settings", err)
        LogPatchDiagnostic(message)
        UpdateCharacterMenuLabel()
    }
    finally
    {
        job.Source.Opt("-Disabled")
        ReleaseCapturedInterfaceFrame(PatchFrame)
        PatchFrame := 0
    }
    message := SanitizeDiagnosticText(message)
    if message = ""
        message := "The Expansion Pack operation could not be completed."
    ; The auto-downloaded ZIP is transient; the import journal and backups
    ; remain intact for recovery. Never delete user-selected packages.
    autoImport := job.HasOwnProp("AutoDownloadedZip") && job.AutoDownloadedZip != ""
    if autoImport
        try FileDelete(job.AutoDownloadedZip)
    MsgBox(message, "Upload Expansion", state = "error" ? "Icon!" : "Iconi")
    if state = "error" && autoImport
    {
        if MsgBox("Automatic Expansion Pack installation did not complete."
            . Chr(10) "Would you like to repair it using your own ZIP or extracted folder?"
            . Chr(10) Chr(10) "Existing verified backups remain available.", "Expansion Pack Repair",
            "YesNo Icon?") = "Yes"
            UploadExpansionFromFile()
    }
}

FinishLauncherStartup()
{
    UpdateCharacterMenuLabel()
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
    global PatchFrame
    SetTimer(CheckPatchWorker, 0)
    ReleaseCapturedInterfaceFrame(PatchFrame)
    PatchFrame := 0
}

SanitizePatchDiagnostic(text)
{
    ; Use the same clean-field sanitizer for dialogs and file-backed logs.
    return SanitizeDiagnosticText(text)
}

PatchErrorDetails(step, field, err)
{
    reason := SanitizePatchDiagnostic(err.Message)
    if reason = ""
        reason := "The operation could not be completed."
    details := "Step: " step "`nField: " field "`nReason: " reason "`nError type: " Type(err)
    extra := SanitizePatchDiagnostic(err.Extra)
    if extra != ""
        details .= "`nDetail: " extra
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
    for folder in folders
    {
        esp := RTrim(folder, "\/") "\NP Expansion Pack.esp"
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

ExpansionPackIsEnabled()
{
    config := PatchConfigurationPath()
    if !FileExist(config)
        return false
    ; A stale load-order entry is not proof the optional ESP is installed.
    morrowind := FindMorrowindFolder(config)
    if !ExpansionPackInstalled(morrowind, config)
        return false
    try
    {
        for line in StrSplit(FileRead(config, "UTF-8"), Chr(10), Chr(13))
            if RegExMatch(Trim(line), 'i)^content\s*=\s*"?NP Expansion Pack\.esp"?$')
                return true
    }
    return false
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

ToggleExpansionPack(*)
{
    global AppDataDirectory, LauncherGui, DataFile, BundledResourceRoot
    if PatchInProgress()
        return
    if ProcessExist("tes3mp.exe") || ProcessExist("openmw.exe") || ProcessExist("openmw-launcher.exe")
    {
        MsgBox("Close all TES3MP/OpenMW clients before switching the Expansion Pack. Running games will not be interrupted.", "Expansion Pack")
        return
    }
    enable := !ExpansionPackIsEnabled()
    cfg := PatchConfigurationPath()
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
    }
    ; Installed packs may live under Morrowind or any configured OpenMW data folder.
    ; Never copy retired bundled Expansion Pack assets.
    if enable && !ExpansionPackInstalled(morrowind, cfg)
    {
        choice := MsgBox("NP Expansion Pack is not installed."
            . Chr(10) Chr(10) "Download and install the latest available package from the official"
            . " Discord channel automatically?"
            . Chr(10) Chr(10) "Yes: Download and install (with backup and rollback)."
            . Chr(10) "No: Repair / install from your own ZIP or folder."
            . Chr(10) "Cancel: Leave everything unchanged.", "Install Expansion Pack",
            "YesNoCancel Icon?")
        if choice = "Yes"
        {
            LogLauncherEvent("EXPANSION | User approved automatic official package discovery.")
            RequestDiscordExpansionPrompt(1)
        }
        else if choice = "No"
            UploadExpansionFromFile()
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
        explanation := "Disabling the Nerevarine Prophecies expansion pack will not uninstall it. If you decide to turn it back on, it will immediately enable again."
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
    output := AppDataDirectory "\expansion-toggle-result.txt"
    if FileExist(output)
        FileDelete(output)
    command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' script '" -Action ' action
        . ' -MorrowindFolder "' morrowind '" -ConfigFile "' cfg '"'
        . ' -BackupFolder "' backup '" -ResultFile "' output '"'
    try
    {
        ; Invoke PowerShell directly. cmd.exe nested quoting previously lost
        ; stderr and gave users an empty "was not changed" error.
        RunWait(command, , "Hide", &exitCode)
        details := FileExist(output) ? SanitizeDiagnosticText(Trim(FileRead(output, "UTF-8"))) : ""
        ; The worker result message alone is not proof of failure or success.
        ; The user's screenshots showed 'Disable complete' incorrectly flagged
        ; as an error. Inspect the actual on-disk OpenMW load order instead.
        actualEnabled := ExpansionPackIsEnabled()
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
        IniWrite(enable ? "1" : "0", DataFile, "ExpansionPack", "GlobalEnabled")
        LogLauncherEvent("EXPANSION | " action " verified in openmw.cfg.")
        RefreshExpansionPackToggle()
        MsgBox("Expansion Pack " (enable ? "enabled" : "disabled") " successfully for future launches.", "Expansion Pack", "Iconi")
    }
    catch Error as err
    {
        LogLauncherEvent("EXPANSION | Toggle exception type: " Type(err))
        reason := SanitizeDiagnosticText(err.Message)
        MsgBox(reason != "" ? reason : "Could not update the Expansion Pack.", "Expansion Pack", "Icon!")
    }
}


; First-run discovery is informational and never installs optional patches.
; A missing Morrowind installation cannot be fixed by downloading TES3MP:
; TES3NP already bundles its own client.
CheckFirstRunMorrowind(resumeExpansion := false, *)
{
    global DataFile, LauncherGui, MorrowindPromptGui
    ; "Not Now" only defers until the next startup or game launch.
    found := FindMorrowindFolder(PatchConfigurationPath())
    if found != ""
    {
        IniWrite(found, DataFile, "Patch", "MorrowindFolder")
        IniWrite("1", DataFile, "Install", "MorrowindPromptDismissed")
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
    prompt := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox", "TES3NP - Morrowind Installation Not Found")
    prompt.ResumeExpansionPack := resumeExpansion
    prompt.BackColor := "E2CEA2"
    prompt.SetFont("s13 Bold c241408", "Segoe UI")
    prompt.Add("Text", "x20 y18 w440 h32", "Morrowind Installation Not Found")
    prompt.SetFont("s10 Norm c382314", "Segoe UI")
    prompt.Add("Text", "x20 y57 w440 h108", "You must locate, install and choose the valid file path of your legally purchased copy of Morrowind in order to play Nerevarine Prophecies. Please install Morrowind, then, click 'Choose Morrowind Folder' and locate your installation path to continue.")
    choose := prompt.Add("Button", "x20 y175 w440 h39", "Choose Morrowind Folder")
    later := prompt.Add("Button", "x20 y224 w440 h34", "Not Now")
    choose.OnEvent("Click", (*) => SelectFirstRunMorrowind(prompt))
    later.OnEvent("Click", (*) => DismissFirstRunMorrowind(prompt))
    prompt.OnEvent("Close", (*) => DismissFirstRunMorrowind(prompt))
    prompt.OnEvent("Escape", (*) => DismissFirstRunMorrowind(prompt))
    MorrowindPromptGui := prompt
    promptScale := GetOwnedMenuScale()
    ScaleOwnedMenuContent(prompt, promptScale)
    prompt.Show("Hide w" Round(480 * promptScale) " h" Round(280 * promptScale))
    PositionOwnedMenuAtParent(prompt, LauncherGui)
    prompt.Show()
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
    IniWrite("1", DataFile, "Install", "MorrowindPromptDismissed")
    LogLauncherEvent("SETUP | User selected a valid Morrowind GOTY installation.")
    resumeExpansion := prompt.HasOwnProp("ResumeExpansionPack") && prompt.ResumeExpansionPack
    MorrowindPromptGui := 0
    prompt.Destroy()
    if resumeExpansion
        SetTimer(ToggleExpansionPack, -50)
    else
        MsgBox("Morrowind folder saved. The Expansion Pack remains optional and disabled unless you enable it.", "TES3NP setup", "Iconi")
}

DismissFirstRunMorrowind(prompt, *)
{
    global MorrowindPromptGui
    ; Do not permanently suppress reminders for missing game files.
    MorrowindPromptGui := 0
    prompt.Destroy()
}
