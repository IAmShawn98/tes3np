#Requires AutoHotkey v2.0
#SingleInstance Force

; Shared state is initialized before the modules and launcher lifecycle.
#Include src\state.ahk
#Include src\data\settings.ahk
#Include src\data\backup.ahk
#Include src\game\session.ahk
#Include src\game\expansion-mismatch.ahk
#Include src\ui\renderer.ahk
#Include src\ui\windows.ahk
#Include src\ui\controls.ahk
#Include src\ui\loading.ahk
#Include src\ui\login-progress.ahk
#Include src\ui\front-page.ahk
#Include src\ui\actions.ahk
#Include src\ui\embedded-chat.ahk
#Include src\ui\happy-hour.ahk
#Include src\ui\characters.ahk
#Include src\ui\macros.ahk
#Include src\ui\patcher.ahk
#Include src\ui\expansion-upload.ahk
#Include src\ui\launcher-settings.ahk
#Include src\ui\v016-refinements.ahk
#Include src\ui\bug-report.ahk
#Include src\app\client-detection.ahk
#Include src\app\update-metadata.ahk
#Include src\app\update-check.ahk
#Include src\app\diagnostics.ahk
#Include src\data\cleanup.ahk
#Include src\app\bootstrap.ahk
#Include scripts\launcher-smoke-tests.ahk

; Native paint notifications must remain eligible inside timer callbacks.
Thread("Interrupt", 0)
CoordMode("Mouse", "Screen")
RunLauncherChecks(A_Args)

; An updater restart validates its pending state and confirms only after startup.
; The Windows packager inserts bundled resource setup before recovery or startup.
updateStateFile := GetPendingUpdateStateFile()
if updateStateFile = ""
    RecoverInterruptedLauncherUpdate()
StartLauncher()
if updateStateFile != ""
    ConfirmUpdatedLauncherStartup(updateStateFile)

GetPendingUpdateStateFile()
{
    global AppConfig
    if A_Args.Length < 3 || A_Args[1] != "--update-confirm"
        return ""

    version := A_Args[2]
    stateFile := A_Args[3]
    updateRoot := GetFullPath(A_Temp "\tes3np-update")
    stateFile := GetFullPath(stateFile)
    SplitPath(stateFile, &name, &folder)
    ; Accept the published v0.1.20 worker's path as well as isolated jobs.
    SplitPath(folder, &jobId, &jobParent)
    if name != "update-state.ini" || (folder != updateRoot
        && (jobParent != updateRoot || !RegExMatch(jobId, "i)^[0-9a-f]{32}$")))
        throw Error("Update confirmation state path is invalid.")
    if version != AppConfig.Version
        throw Error("Update confirmation version does not match installed launcher.")
    if !FileExist(stateFile)
        throw Error("Update confirmation state file is missing.")
    ; Windows PowerShell 5.1 writes a UTF-8 BOM, which IniRead cannot decode.
    ; Read the worker record directly, as the worker does for our acknowledgement.
    lines := StrSplit(FileRead(stateFile, "UTF-8"), "`n", "`r")
    if lines.Length < 3 || lines[1] != "[Update]"
        || lines[2] != "State=AWAITING_CONFIRMATION" || lines[3] != "Version=" AppConfig.Version
        throw Error("Update confirmation does not match a pending installation.")
    return stateFile
}

ConfirmUpdatedLauncherStartup(stateFile)
{
    global AppConfig
    ; The worker polls this file directly. Replace it atomically so the worker
    ; cannot read a partially written confirmation.
    confirmTemp := stateFile ".confirm.tmp"
    try FileDelete(confirmTemp)
    confirmation := "[Update]`r`nState=CONFIRMED`r`nVersion=" AppConfig.Version
        . "`r`nUpdatedUtc=" FormatTime(A_NowUTC, "yyyy-MM-ddTHH:mm:ssZ") "`r`n"
    FileAppend(confirmation, confirmTemp, "UTF-8")
    FileMove(confirmTemp, stateFile, true)

    LogLauncherEvent("UPDATE | CONFIRMED | Updated launcher v" AppConfig.Version " confirmed successful startup.")
}

; Restrict macro editing shortcuts to the focused name field.
#HotIf MacroNameEditorFocused()
Enter::SaveMacroName()
NumpadEnter::SaveMacroName()
Escape::FinishMacroNameEdit()
#HotIf
