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
; Windows-only page presentation smoke: verify DWM really retains a
; staged native GUI out of desktop composition until its paint is complete.
; This uses a disposable window, not launcher profiles, Discord or files.
if A_Args.Length && A_Args[1] = "--check-page-compositor"
{
    testWindow := Gui("-Caption -Border", "TES3NP staged page smoke")
    testWindow.Add("Text", "x12 y12 w255 h35", "Paint-ready test page")
    if !SetPageCompositorCloak(testWindow, true)
        ExitApp(191)
    ; Reproduce Settings' exact hidden + DWM-cloaked color-key setup. AHK
    ; WinSetTransColor by window title failed in this state; by-HWND must work.
    testWindow.Show("Hide w280 h90")
    if !SetPageColorKey(testWindow, 0x010101)
        ExitApp(195)
    colorKey := Buffer(4, 0), colorAlpha := Buffer(1, 0), colorFlags := Buffer(4, 0)
    if !DllCall("GetLayeredWindowAttributes", "Ptr", testWindow.Hwnd,
        "Ptr", colorKey, "Ptr", colorAlpha, "Ptr", colorFlags, "Int")
        || NumGet(colorKey, 0, "UInt") != 0x010101
        || NumGet(colorFlags, 0, "UInt") != 1
        ExitApp(196)
    testWindow.Show()
    before := Buffer(4, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", testWindow.Hwnd,
        "UInt", 14, "Ptr", before, "UInt", 4, "Int") != 0
        || NumGet(before, 0, "Int") = 0
        ExitApp(192)
    RevealPaintedPage(testWindow)
    after := Buffer(4, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", testWindow.Hwnd,
        "UInt", 14, "Ptr", after, "UInt", 4, "Int") != 0
        || NumGet(after, 0, "Int") != 0
        ExitApp(193)
    if !DllCall("IsWindowVisible", "Ptr", testWindow.Hwnd)
        ExitApp(194)
    FileAppend("PASS: staged page hidden until native paint and then revealed" Chr(10), "*")
    testWindow.Destroy()
    ExitApp(0)
}
; CI-only fast return check: the full launcher is already visible beneath
; its owned Character Book. Closing the book must not repaint all registered
; themed controls or synchronously rebuild the parent menu.
if A_Args.Length && A_Args[1] = "--check-cached-character-return"
{
    global LauncherGui := Gui("-Caption -Border", "Cached return smoke")
    LauncherGui.Show("w560 h350")
    global LauncherScale := 100
    global LauncherScaleMode := "Manual"
    global LauncherCachedScale := 100
    global LauncherControlLayout := Map()
    global LauncherCachedLayoutCount := 0
    ; If ShowLauncherWindow accidentally invokes RepaintMenuButtons, its
    ; stale-handle sweep deletes this marker. The fast branch must not do so.
    probeHandle := 0x7E5A01
    ButtonFaces[probeHandle] := {State: "probe"}
    probeBook := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border", "Book")
    probeBook.Show("w220 h160")
    began := A_TickCount
    ShowLauncherWindow(true)
    probeBook.Hide()
    elapsed := A_TickCount - began
    if !ButtonFaces.Has(probeHandle)
        ExitApp(201)
    if !DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        || DllCall("IsWindowVisible", "Ptr", probeBook.Hwnd)
        ExitApp(202)
    if elapsed >= 750
        ExitApp(203)
    ButtonFaces.Delete(probeHandle)
    FileAppend("PASS: cached Character Book return avoids global repaint" Chr(10), "*")
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
