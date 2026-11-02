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
    ; ZIP is preferred because it carries the complete Data Files layout.
    ; A second native action accepts a folder already extracted from that ZIP.
    ShowLauncherWindow(true)
    sourceGui := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox",
        "tes3np — Expansion Pack Source")
    sourceGui.BackColor := "E2CEA2"
    sourceGui.SetFont("s13 Bold c382314", "Georgia")
    sourceGui.Add("Text", "x20 y15 w410 h28", "Install NP Expansion Pack")
    sourceGui.SetFont("s10 Norm c382314", "Segoe UI")
    sourceGui.Add("Text", "x20 y54 w410 h60",
        "Select the complete official download. ZIP is recommended, "
        . "or choose the folder containing its extracted Data Files.")
    zipButton := sourceGui.Add("Button", "x20 y123 w195 h42 Default", "Select ZIP (Recommended)")
    folderButton := sourceGui.Add("Button", "x225 y123 w205 h42", "Select Extracted Folder")
    cancelButton := sourceGui.Add("Button", "x320 y180 w110 h30", "Cancel")
    zipButton.OnEvent("Click", (*) => ChooseExpansionPackageSource(sourceGui, "zip"))
    folderButton.OnEvent("Click", (*) => ChooseExpansionPackageSource(sourceGui, "folder"))
    cancelButton.OnEvent("Click", (*) => sourceGui.Destroy())
    sourceGui.OnEvent("Close", (*) => sourceGui.Destroy())
    sourceGui.OnEvent("Escape", (*) => sourceGui.Destroy())
    sourceGui.Show("w450 h225")
}

ChooseExpansionPackageSource(sourceGui, sourceType)
{
    try sourceGui.Destroy()
    if sourceType = "zip"
        package := FileSelect(1, , "Choose the official NP Expansion Pack ZIP",
            "Expansion Pack archive (*.zip)")
    else if sourceType = "folder"
        package := DirSelect(, 0, "Choose the extracted Expansion Pack folder containing Data Files")
    else
        return
    if package = ""
        return
    InstallSelectedExpansionPackage(package)
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
