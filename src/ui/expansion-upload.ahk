; User-initiated import of an official NP download after a plugin mismatch.
; The file picker does not imply that Discord or the server was verified.
UploadExpansionFromFile(*)
{
    global LauncherGui, DataFile
    if PatchInProgress()
        return
    if ProcessExist("tes3mp.exe") || ProcessExist("openmw.exe") || ProcessExist("openmw-launcher.exe")
    {
        MsgBox("Close all TES3MP/OpenMW games before uploading the Expansion Pack.", "Expansion Pack", "Icon!")
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
    resultPath := A_Temp "\tes3np-expansion-source-" A_Pid "-" A_TickCount ".txt"
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
        MsgBox("Could not choose the Expansion Pack: " err.Message,
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

InstallSelectedExpansionPackage(package)
{
    global LauncherGui, DataFile
    if PatchInProgress()
        return
    if ProcessExist("tes3mp.exe") || ProcessExist("openmw.exe") || ProcessExist("openmw-launcher.exe")
    {
        MsgBox("Close all TES3MP/OpenMW games before uploading the Expansion Pack.", "Expansion Pack", "Icon!")
        return
    }
    config := PatchConfigurationPath()
    if !FileExist(config)
    {
        config := FileSelect(1, , "Select the active OpenMW configuration", "OpenMW configuration (*.cfg)")
        if config = ""
            return
    }
    SplitPath(config, &configName)
    if StrLower(configName) != "openmw.cfg"
    {
        MsgBox("Choose your active openmw.cfg file, not another configuration file.", "Expansion Pack", "Icon!")
        return
    }
    morrowind := FindMorrowindFolder(config)
    if morrowind = ""
    {
        morrowind := FileSelect("D", , "Choose your Morrowind GOTY installation folder")
        if morrowind = ""
            return
    }
    morrowind := RTrim(morrowind, "\/")
    SplitPath(morrowind, &selectedName, &parent)
    if StrLower(selectedName) = "data files"
        morrowind := parent
    for master in ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm"]
    {
        if !FileExist(morrowind "\Data Files\" master)
        {
            MsgBox("The selected Morrowind installation is missing " master ".", "Expansion Pack", "Icon!")
            return
        }
    }
    if MsgBox("Install the selected NP Expansion Pack into this Morrowind installation?"
        . Chr(10) Chr(10) "Existing files will be backed up before being replaced. "
        . "Choose only downloads from the official Nerevarine Prophecies Discord server. "
        . "TES3NP cannot guarantee the download matches the live server.", "Upload Expansion", "YesNo Icon?") != "Yes"
        return
    ShowLauncherWindow(true)
    StartExpansionImportWorker(package, morrowind, config)
}

StartExpansionImportWorker(package, morrowind, config)
{
    global AppDataDirectory, LauncherGui, PatchJob, PatchFrame, InterfaceLoadingText
    global BundledResourceRoot
    if PatchInProgress()
        return false
    resourceRoot := IsSet(BundledResourceRoot) && DirExist(BundledResourceRoot) ? BundledResourceRoot : A_ScriptDir
    helper := resourceRoot "\scripts\import-expansion-pack.ps1"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(helper) || !FileExist(powershell)
    {
        MsgBox("Expansion Pack import worker is unavailable. Rebuild TES3NP.", "Upload Expansion", "Icon!")
        return false
    }
    jobFolder := AppDataDirectory "\expansion-imports\" FormatTime(, "yyyyMMddHHmmss") "-" A_TickCount
    try
    {
        DirCreate(jobFolder)
        command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' helper '"'
            . ' -Package "' package '" -MorrowindFolder "' morrowind '" -ConfigFile "' config '" -JobFolder "' jobFolder '"'
        InterfaceLoadingText := "Waiting for Jiub..."
        PatchFrame := CaptureInterfaceFrame(LauncherGui, true)
        LauncherGui.Opt("+Disabled")
        Run(command, , "Hide", &pid)
        handle := DllCall("OpenProcess", "UInt", 0x1000, "Int", false, "UInt", pid, "Ptr")
        PatchJob := {PID: pid, Handle: handle, Folder: jobFolder, Action: "Import",
            Source: LauncherGui, Startup: false, TesFolder: "", MorrowindFolder: morrowind, ConfigFile: config}
        LogLauncherEvent("EXPANSION | Local Expansion Pack import started.")
        SetTimer(CheckPatchWorker, 50)
        return true
    }
    catch Error as err
    {
        LauncherGui.Opt("-Disabled")
        if IsObject(PatchFrame)
            ReleaseCapturedInterfaceFrame(PatchFrame)
        PatchFrame := 0
        LogLauncherEvent("EXPANSION | Import worker launch failed: " err.Message)
        MsgBox("Could not start Expansion Pack import: " err.Message, "Upload Expansion", "Icon!")
        return false
    }
}
