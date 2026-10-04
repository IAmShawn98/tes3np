; Public-alpha diagnostics and lightweight launcher logging.

global LauncherLogFile := AppDataDirectory "\launcher.log"

LogLauncherEvent(message)
{
    global LauncherLogFile
    try
    {
        DirCreate(AppDataDirectory)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " message "`n", LauncherLogFile, "UTF-8")
    }
}

OpenTroubleshooting(*)
{
    global LauncherGui, LauncherLogFile
    window := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — Troubleshooting")
    window.BackColor := "E2CEA2"
    window.SetFont("s11 Bold c241408", "Segoe UI")
    window.Add("Text", "x20 y18 w360 h26", "Troubleshooting & Diagnostics")
    window.SetFont("s9 c382314", "Segoe UI")
    window.Add("Text", "x20 y48 w360 h42", "Tools for reporting launcher problems during the public alpha. Diagnostics never include passwords.")
    openData := window.Add("Button", "x20 y102 w175 h34", "Open AppData Folder")
    openLog := window.Add("Button", "x205 y102 w175 h34", "Open Launcher Log")
    copyInfo := window.Add("Button", "x20 y146 w360 h34", "Copy Diagnostic Information")
    clearLog := window.Add("Button", "x20 y190 w175 h34", "Clear Launcher Log")
    close := window.Add("Button", "x205 y190 w175 h34 Default", "Close")
    openData.OnEvent("Click", OpenLauncherDataFolder)
    openLog.OnEvent("Click", OpenLauncherLog)
    copyInfo.OnEvent("Click", CopyLauncherDiagnostics)
    clearLog.OnEvent("Click", ClearLauncherLog)
    close.OnEvent("Click", (*) => window.Destroy())
    window.OnEvent("Escape", (*) => window.Destroy())
    window.Show("w400 h244")
}

OpenLauncherDataFolder(*)
{
    DirCreate(AppDataDirectory)
    Run('explorer.exe "' AppDataDirectory '"')
}

OpenLauncherLog(*)
{
    global LauncherLogFile
    DirCreate(AppDataDirectory)
    if !FileExist(LauncherLogFile)
        FileAppend("tes3np launcher log`n", LauncherLogFile, "UTF-8")
    Run(LauncherLogFile)
}

ClearLauncherLog(*)
{
    global LauncherLogFile
    if MsgBox("Clear the launcher log?", "tes3np — Clear Log", "YesNo Icon?") != "Yes"
        return
    try FileDelete(LauncherLogFile)
    LogLauncherEvent("Launcher log cleared by user.")
    MsgBox("Launcher log cleared.", "tes3np")
}

CopyLauncherDiagnostics(*)
{
    A_Clipboard := BuildLauncherDiagnostics()
    LogLauncherEvent("Diagnostic information copied to clipboard.")
    MsgBox("Diagnostic information copied to the clipboard.`n`nYou can paste it into Discord or a bug report.", "tes3np — Diagnostics")
}

BuildLauncherDiagnostics()
{
    global AppConfig, AppDataDirectory, DataFile, LauncherScale, LauncherScaleMode
    global AccessibilityTextSize, EnhancedReadability, ReduceMotion, SetupComplete
    installPath := A_ScriptDir
    scaleText := LauncherScaleMode = "Auto" ? "Automatic (" LauncherScale "%)" : LauncherScale "%"
    dpiPercent := Round((A_ScreenDPI / 96) * 100)
    patchComplete := SetupComplete ? "Yes" : "No"
    settingsPresent := FileExist(DataFile) ? "Yes" : "No"
    return "tes3np Diagnostics`r`n"
        . "Launcher version: v" AppConfig.Version "`r`n"
        . "AutoHotkey: " A_AhkVersion "`r`n"
        . "Windows: " A_OSVersion " (" (A_Is64bitOS ? "64-bit" : "32-bit") ")`r`n"
        . "Screen: " A_ScreenWidth "x" A_ScreenHeight " @ " dpiPercent "% DPI`r`n"
        . "Launcher size: " scaleText "`r`n"
        . "Interface text: " AccessibilityTextSize "`r`n"
        . "Enhanced readability: " (EnhancedReadability ? "On" : "Off") "`r`n"
        . "Reduce motion: " (ReduceMotion ? "On" : "Off") "`r`n"
        . "Patch setup complete: " patchComplete "`r`n"
        . "Settings file present: " settingsPresent "`r`n"
        . "Install path: " installPath "`r`n"
        . "AppData path: " AppDataDirectory
}
