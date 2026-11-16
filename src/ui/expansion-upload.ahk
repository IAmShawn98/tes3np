; User-initiated import of an official NP download after a plugin mismatch.
; The file picker does not imply that Discord or the server was verified.
UploadExpansionFromFile(args*)
{
    if PatchInProgress()
        return
    if ProcessExist("tes3mp.exe") || ProcessExist("openmw.exe") || ProcessExist("openmw-launcher.exe")
    {
        MsgBox("Close all TES3MP/OpenMW games before uploading the Expansion Pack.", "Expansion Pack", "Icon!")
        return
    }
    ; This trusted auto path is validated a second time after the native
    ; sender-PID and private ZIP-path checks in expansion-mismatch.ahk.
    ; Ordinary button/event callbacks still use the unchanged file picker.
    if args.Length = 2 && Type(args[1]) = "String" && args[2] = true
    {
        package := args[1]
        SplitPath(package, &filename, &folder)
        if StrLower(folder) != StrLower(A_AppData "\tes3np\expansion-downloads")
            || !RegExMatch(filename, "i)^tes3np-[0-9a-f]{32}\.zip$")
            || !FileExist(package)
        {
            LogLauncherEvent("EXPANSION | Rejected invalid automatic import source.")
            return
        }
        InstallSelectedExpansionPackage(package, true)
        return
    }
    ; One native Explorer-style picker handles both kinds of complete pack.
    ; Standard Open selects ZIPs; "Use This Folder" returns the extracted
    ; package folder from the same dialog, without a second selector.
    ShowLauncherWindow(true)
    package := SelectExpansionPackagePath()
    if package != ""
        InstallSelectedExpansionPackage(package)
}

SelectExpansionPackagePath()
{
    global LauncherGui, BundledResourceRoot
    resourceRoot := IsSet(BundledResourceRoot) && DirExist(BundledResourceRoot) ? BundledResourceRoot : A_ScriptDir
    helper := resourceRoot "\scripts\select-expansion-package.ps1"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(helper) || !FileExist(powershell)
    {
        MsgBox("The Expansion Pack browser is unavailable. Rebuild TES3NP.",
            "Upload Expansion", "Icon!")
        return ""
    }
    resultPath := A_Temp "\tes3np-expansion-source-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount ".txt"
    errorPath := resultPath ".error"
    package := ""
    try
    {
        command := '"' powershell '" -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'
            . helper '" -ResultFile "' resultPath '" -OwnerHwnd ' LauncherGui.Hwnd
        exitCode := RunWait(command, , "Hide")
        if exitCode != 0
        {
            detail := FileExist(errorPath) ? FileRead(errorPath, "UTF-8") : "The native browser could not be opened."
            throw Error(detail)
        }
        if FileExist(resultPath)
        {
            package := Trim(FileRead(resultPath, "UTF-8"), Chr(13) Chr(10))
            SplitPath(package, , , &extension)
            if !DirExist(package) && !(FileExist(package) && StrLower(extension) = "zip")
                throw Error("Choose an existing Expansion Pack ZIP or extracted folder.")
        }
    }
    catch Error as err
    {
        LogLauncherEvent("EXPANSION | Native package picker failed (" Type(err) ").")
        reason := SanitizeDiagnosticText(err.Message)
        if reason = ""
            reason := "The native browser could not be opened."
        MsgBox("Could not choose the Expansion Pack: " reason,
            "Upload Expansion", "Icon!")
        package := ""
    }
    finally
    {
        try FileDelete(resultPath)
        try FileDelete(errorPath)
    }
    return package
}

InstallSelectedExpansionPackage(package, autoApproved := false)
{
    ; Revalidate the approved automatic download after any deferred setup.
    if autoApproved
    {
        SplitPath(package, &downloadName, &downloadFolder)
        if StrLower(downloadFolder) != StrLower(A_AppData "\tes3np\expansion-downloads")
            || !RegExMatch(downloadName, "i)^tes3np-[0-9a-f]{32}\.zip$")
            || !FileExist(package)
        {
            LogLauncherEvent("EXPANSION | Deferred ZIP validation failed.")
            return
        }
    }
    if PatchInProgress()
        return
    if ProcessExist("tes3mp.exe") || ProcessExist("openmw.exe") || ProcessExist("openmw-launcher.exe")
    {
        MsgBox("Close all TES3MP/OpenMW games before uploading the Expansion Pack.", "Expansion Pack", "Icon!")
        return
    }
    config := PatchConfigurationPath()
    ; Morrowind may have been removed while Discord was downloading.
    morrowind := FindMorrowindFolder(config)
    if morrowind = ""
    {
        DeferExpansionInstallForMissingMorrowind(package, autoApproved)
        return
    }
    if !autoApproved && MsgBox("Install the selected NP Expansion Pack into this Morrowind installation?"
        . Chr(10) Chr(10) "Existing files will be backed up before being replaced. "
        . "Choose only downloads from the official Nerevarine Prophecies Discord server. "
        . "TES3NP cannot guarantee the download matches the live server.", "Upload Expansion", "YesNo Icon?") != "Yes"
        return
    config := PrepareExpansionOpenMWConfiguration(config, morrowind)
    if config = ""
    {
        if autoApproved
            try FileDelete(package)
        return
    }
    ShowLauncherWindow(true)
    if autoApproved
    {
        if !StartExpansionImportWorker(package, morrowind, config, package)
            try FileDelete(package)
    }
    else
        StartExpansionImportWorker(package, morrowind, config)
}

DeferExpansionInstallForMissingMorrowind(package, autoApproved)
{
    global MorrowindPromptGui
    LogLauncherEvent("EXPANSION | Missing Morrowind after ZIP download; opening setup prompt.")
    CheckFirstRunMorrowind()
    if IsObject(MorrowindPromptGui)
    {
        MorrowindPromptGui.PendingExpansionPackage := package
        MorrowindPromptGui.PendingExpansionApproved := autoApproved
    }
}

StartExpansionImportWorker(package, morrowind, config, autoDownloadedZip := "")
{
    global AppDataDirectory, LauncherGui, PatchJob, PatchFrame, InterfaceLoadingText, Client
    global BundledResourceRoot
    if Client.Enabled || PatchInProgress()
        return false
    if !RecoverExpansionImports()
        return false
    resourceRoot := IsSet(BundledResourceRoot) && DirExist(BundledResourceRoot) ? BundledResourceRoot : A_ScriptDir
    helper := resourceRoot "\scripts\import-expansion-pack.ps1"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(helper) || !FileExist(powershell)
    {
        MsgBox("Expansion Pack import worker is unavailable. Rebuild TES3NP.", "Upload Expansion", "Icon!")
        return false
    }
    jobFolder := ""
    previousCritical := Critical("On")
    failure := 0
    try
    {
        ; Keep the launch check and worker registration together.
        if Client.Enabled || !CanUseNPLauncher(false)
            return false
        jobFolder := AppDataDirectory "\expansion-imports\" NewLauncherFileId()
        DirCreate(jobFolder)
        command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' helper '"'
            . ' -Package "' package '" -MorrowindFolder "' morrowind '" -ConfigFile "' config '" -JobFolder "' jobFolder '"'
        InterfaceLoadingText := "Waiting for Jiub..."
        PatchFrame := CaptureInterfaceFrame(LauncherGui, true)
        LauncherGui.Opt("+Disabled")
        Run(command, , "Hide", &pid)
        handle := DllCall("OpenProcess", "UInt", 0x101000, "Int", false, "UInt", pid, "Ptr")
        PatchJob := {PID: pid, Handle: handle, Folder: jobFolder,
            MorrowindFolder: morrowind, ConfigFile: config,
            AutoDownloadedZip: autoDownloadedZip}
        SetTimer(CheckPatchWorker, 50)
    }
    catch Error as err
    {
        if jobFolder != "" && !IsObject(PatchJob)
            try DirDelete(jobFolder)
        LauncherGui.Opt("-Disabled")
        if IsObject(PatchFrame)
            ReleaseCapturedInterfaceFrame(PatchFrame)
        PatchFrame := 0
        failure := err
    }
    finally Critical(previousCritical)
    if IsObject(failure)
    {
        LogLauncherEvent("EXPANSION | Import worker launch failed (" Type(failure) ").")
        reason := SanitizeDiagnosticText(failure.Message)
        MsgBox("Could not start Expansion Pack import: " (reason != "" ? reason : Type(failure)), "Upload Expansion", "Icon!")
        return false
    }
    LogLauncherEvent("EXPANSION | Local Expansion Pack import started.")
    return true
}
