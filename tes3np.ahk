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
#Include src\app\diagnostics.ahk
#Include src\app\bootstrap.ahk

Thread("Interrupt", 0)
CoordMode("Mouse", "Screen")
if A_Args.Length && A_Args[1] = "--check"
    ExitApp(0)
if A_Args.Length >= 3 && A_Args[1] = "--update-confirm"
    ConfirmInstalledUpdate(A_Args[2], A_Args[3])
StartLauncher()
