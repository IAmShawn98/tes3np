#Requires AutoHotkey v2.0
#SingleInstance Force

; Explicit dependency order: state, services, interface, application lifecycle.
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
#Include src\ui\macro-bindings.ahk
#Include src\ui\patcher.ahk
#Include src\ui\expansion-upload.ahk
#Include src\ui\launcher-settings.ahk
#Include src\ui\v016-refinements.ahk
#Include src\app\client-detection.ahk
#Include src\app\update-check.ahk
#Include src\app\diagnostics.ahk
#Include src\app\bootstrap.ahk

; Native paint notifications must remain eligible inside timer callbacks.
Thread("Interrupt", 0)
CoordMode("Mouse", "Screen")
if A_Args.Length && A_Args[1] = "--check"
    ExitApp(0)
; Noninteractive compiled-host probe. Verify native expansion progress can
; resolve its actual UI functions without starting any window or game.
if A_Args.Length && A_Args[1] = "--check-expansion-ui"
{
    for index, name in ["CaptureInterfaceFrame", "AddStyledButton",
        "DestroyBookControl", "ReleaseCapturedInterfaceFrame",
        "PaintButtonNow", "UpdateExpansionLoadingProgress",
        "UploadExpansionFromFile"]
    {
        try callback := %name%
        catch
            ExitApp(100 + index)
        if !HasMethod(callback, "Call")
            ExitApp(120 + index)
    }
    ; Execute the progress painting routine against a disposable in-memory
    ; panel. No visible window or game files are involved. This exercises the
    ; exact callback path that had previously warned only on a real click.
    try
    {
        probePanel := {Hwnd: 0, Text: ""}
        probeFrame := {Panel: probePanel}
        ButtonFaces[0] := {Progress: 0}
        painterName := "UpdateExpansionLoadingProgress"
        painter := %painterName%
        painter.Call(probeFrame, "Expansion progress probe", 37)
        if Abs(ButtonFaces[0].Progress - 0.37) > 0.0001
            || probePanel.Text != "Expansion progress probe"
            ExitApp(93)
        ButtonFaces.Delete(0)
    }
    catch
        ExitApp(94)
    ExitApp(0)
}
; CI-only Windows GUI smoke test: exercise the same real screenshot cover,
; native card, custom Cancel button and protected renderer as first enable.
; No Discord, user game files or installer are started.
if A_Args.Length && A_Args[1] = "--check-expansion-window"
{
    global LauncherGui := Gui("-Caption -Border", "Native Expansion download smoke")
    LauncherGui.BackColor := "1B140B"
    LauncherGui.Add("Text", "x20 y20 w500 h50", "Disposable launcher window")
    LauncherGui.Show("w960 h720")
    ; Real launcher buttons initialize this painter before first enable.
    ; Without it a synthetic window correctly raises UnsetError, which is
    ; a test-harness setup fault rather than the download-window defect.
    InitButtonPainter()
    ; Match the real flow: a cloaked owned Discord discovery window exists
    ; before the native download progress overlay is constructed.
    probeDialog := Gui("+Owner" LauncherGui.Hwnd " -MaximizeBox -MinimizeBox", "tes3np")
    TES3MPExpansionCloakDialog(probeDialog, true)
    probeDialog.Show("w660 h627")
    try
    {
        if !TES3MPExpansionBeginNativeProgress()
            throw Error("Native progress card creation returned false.")
        if !IsObject(ExpansionAutoProgressFrame)
            || !IsObject(ExpansionAutoCancelButton)
            || !DllCall("IsWindowVisible", "Ptr", ExpansionAutoCancelButton.Hwnd)
            throw Error("Native Cancel button or card is not visible.")
        TES3MPExpansionUpdateNativeProgress("Downloading Expansion Pack... 27%", 27)
        TES3MPExpansionUpdateNativeProgress("Downloading Expansion Pack... 65%", 65)
        TES3MPExpansionEndNativeProgress()
        FileAppend("PASS: native Expansion progress card and cancel UI" Chr(10), "*")
    }
    catch Error as err
    {
        ; Print only the type and first-party stage, never a path or secret.
        FileAppend("FAIL: native Expansion progress - " Type(err) Chr(10), "*")
        try
        {
            if FileExist(LauncherLogFile)
            {
                lines := StrSplit(FileRead(LauncherLogFile, "UTF-8"), Chr(10))
                count := 0
                for index, item in lines
                {
                    if InStr(item, "EXPANSION | Native")
                    {
                        FileAppend("DIAGNOSTIC: " Trim(item) Chr(10), "*")
                        count += 1
                        if count > 8
                            break
                    }
                }
            }
        }
        try TES3MPExpansionEndNativeProgress()
        ExitApp(181)
    }
    ExitApp(0)
}
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
    ; the updater's fixed temp-state path.
    if StrLower(GetFullPath(stateFile)) != StrLower(GetFullPath(expectedState))
        throw Error("Update confirmation state path is invalid.")
    if version != AppConfig.Version
        throw Error("Update confirmation version does not match installed launcher.")
    if !FileExist(stateFile)
        throw Error("Update confirmation state file is missing.")

    ; Publish confirmation as one complete file replacement. IniWrite uses the
    ; Windows profile API, while the PowerShell worker reads the file directly;
    ; replacing the complete file avoids cache/partial-write visibility problems
    ; between those two APIs.
    confirmTemp := stateFile ".confirm.tmp"
    try FileDelete(confirmTemp)
    confirmation := "[Update]`r`nState=CONFIRMED`r`nVersion=" AppConfig.Version
        . "`r`nUpdatedUtc=" FormatTime(A_NowUTC, "yyyy-MM-ddTHH:mm:ssZ") "`r`n"
    FileAppend(confirmation, confirmTemp, "UTF-8")
    FileMove(confirmTemp, stateFile, true)

    LogLauncherEvent("UPDATE | CONFIRMED | Updated launcher v" AppConfig.Version " confirmed successful startup.")
    return true
}
