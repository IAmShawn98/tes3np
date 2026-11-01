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
    package := FileSelect(1, , "Choose the Expansion Pack downloaded from Nerevarine Prophecies", "Expansion files (*.zip; *.esp)")
    if package = ""
        return
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
