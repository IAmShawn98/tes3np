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
#Include src\ui\launcher-layout.ahk
#Include src\ui\update-notes.ahk
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
updateStatePath := GetPendingUpdateStatePath()

; The Windows packager replaces this marker with bundled resource initialization.
; @bundled-resource-setup@

if updateStatePath = ""
    RecoverInterruptedLauncherUpdate()
StartLauncher()
if updateStatePath != ""
    ConfirmUpdatedLauncherStartup(updateStatePath)
