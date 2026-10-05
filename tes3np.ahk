#Requires AutoHotkey v2.0
#SingleInstance Force

; Explicit dependency order: state, services, interface, application lifecycle.
#Include src\state.ahk
#Include src\data\settings.ahk
#Include src\data\backup.ahk
#Include src\game\session.ahk
#Include src\ui\renderer.ahk
#Include src\ui\windows.ahk
#Include src\ui\controls.ahk
#Include src\ui\loading.ahk
#Include src\ui\front-page.ahk
#Include src\ui\actions.ahk
#Include src\ui\characters.ahk
#Include src\ui\macros.ahk
#Include src\ui\macro-bindings.ahk
#Include src\ui\patcher.ahk
#Include src\ui\launcher-settings.ahk
#Include src\app\client-detection.ahk
#Include src\app\update-check.ahk
#Include src\app\daily-login-scheduler.ahk
#Include src\app\diagnostics.ahk
#Include src\app\bootstrap.ahk

; Native paint notifications must remain eligible inside timer callbacks.
Thread("Interrupt", 0)
CoordMode("Mouse", "Screen")
if A_Args.Length && A_Args[1] = "--check"
    ExitApp(0)
HandleUpdaterStartupMode()
StartLauncher()

HandleUpdaterStartupMode() {
    global AppConfig
    if A_Args.Length < 3 || A_Args[1] != "--update-confirm"
        return false

    version := A_Args[2]
    stateFile := A_Args[3]
    expectedState := A_Temp "\tes3np-update\update-state.ini"

    ; The newly installed executable is the authority for its own compiled version.
    ; Confirm only when the worker requested this exact build and the state file is
    ; the updater's fixed temp-state path. This avoids depending on a second copy of
    ; the version value inside the state file during the startup handshake.
    if StrLower(GetFullPath(stateFile)) != StrLower(GetFullPath(expectedState))
        throw Error("Update confirmation state path is invalid.")
    if version != AppConfig.Version
        throw Error("Update confirmation version does not match installed launcher.")
    if !FileExist(stateFile)
        throw Error("Update confirmation state file is missing.")

    IniWrite("CONFIRMED", stateFile, "Update", "State")
    LogLauncherEvent("UPDATE | CONFIRMED | Updated launcher v" AppConfig.Version " confirmed successful startup.")
    return true
}
