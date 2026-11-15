; Application startup, quick-launch choice, tray wiring and shutdown.

global LauncherControlLayout := Map()
global LauncherCachedScale := 0
global LauncherCachedLayoutCount := 0
global LauncherVersionLabel := 0
global LauncherSettingsButton := 0
global LauncherUpdateButton := 0
global LauncherExpansionToggle := 0
global LauncherUpdateAvailable := false
global LauncherUpdateDismissedVersion := ""

StartLauncher()
{
    global HoverTimer, LauncherUpdateDismissedVersion

    LauncherUpdateDismissedVersion := ""
    LogLauncherEvent("Launcher startup beginning.")
    RequireLauncherAssets()
    ConfigureLauncherTrayMenu()
    InitializeHappyHourJiub()
    TraySetIcon(A_ScriptDir "\assets\icons\tes3np.ico")
    A_IconTip := "tes3np - Nerevarine Prophecies Launcher"

    LoadLauncherScale()
    InitializeLauncherMorrowindFont()
    LoadProfiles()
    TrimStoredDiagnosticLogs()
    SanitizeExistingDiagnosticLogs()
    ; Restore any saved client override before the launch controls are available.
    RecoverCustomClientOverrides()

    BuildLauncherWindow()
    RegisterLauncherEventHandlers()
    SetTimer(HoverTimer, 30)
    ShowLauncherWindow()

    ; Start chat after the launcher is visible so it can attach to the painted window.
    SetTimer(StartEmbeddedInGameChat, -75)
    SetTimer(CleanupStaleLauncherData, -1000)
    SetTimer(CheckForUpdateAvailability, -250)
    SetTimer(OfferDesktopShortcutOnFirstLaunch, -1800)
    LogLauncherEvent("Launcher startup completed. Version v" AppConfig.Version ".")
}

RequireLauncherAssets()
{
    for asset in ["backgrounds\launcher.png", "controls\scroll-panel.png", "headings\quest.png",
        "headings\together.png", "controls\button.png", "backgrounds\character-book.png", "icons\tes3np.ico"]
    {
        if !FileExist(A_ScriptDir "\assets\" asset)
        {
            LogLauncherEvent("Startup failed: missing asset " asset)
            MsgBox("A required asset is missing: " asset "`nExtract the entire ZIP before running tes3np.", "tes3np")
            ExitApp()
        }
    }
}

ConfigureLauncherTrayMenu()
{
    A_TrayMenu.Add("Open Launcher", ShowLauncherWindow)
    A_TrayMenu.Default := "Open Launcher"
    A_TrayMenu.Add("Stop game recovery", StopGameRecovery)
    A_TrayMenu.Add("Enable / Disable Expansion Pack", ToggleExpansionPack)
    A_TrayMenu.Add("Open Expansion Pack Downloads", (*) => ShowTES3MPExpansionMismatchDialog("Browse"))
}

BuildLauncherWindow()
{
    global LauncherGui, LauncherVersionLabel, LauncherSettingsButton
    global LauncherExpansionToggle, LauncherUpdateButton

    LauncherGui := Gui("-Caption -Border", A_IconTip)
    ; WS_CLIPCHILDREN keeps launcher repaints from drawing over the embedded chat window.
    styleGetter := A_PtrSize = 8 ? "GetWindowLongPtrW" : "GetWindowLongW"
    styleSetter := A_PtrSize = 8 ? "SetWindowLongPtrW" : "SetWindowLongW"
    launcherStyle := DllCall("user32\" styleGetter, "Ptr", LauncherGui.Hwnd, "Int", -16, "Ptr")
    DllCall("user32\" styleSetter, "Ptr", LauncherGui.Hwnd, "Int", -16, "Ptr", launcherStyle | 0x02000000, "Ptr")

    SetWindowIcons()
    BuildFrontPage()
    LauncherGui.SetFont("s9 cC5A45C", "Segoe UI")
    LauncherVersionLabel := LauncherGui.Add("Text", "x12 y691 w300 h18 BackgroundTrans", "tes3np · v" AppConfig.Version)
    LauncherVersionLabel.OnEvent("Click", CheckForUpdates)
    LauncherSettingsButton := AddStyledButton(LauncherGui, 820, 684, 140, 32, "Launcher Settings", OpenLauncherSettingsV016)
    LauncherExpansionToggle := AddStyledButton(LauncherGui, 0, 0, 190, 27, "Expansion Pack: Disabled", ToggleExpansionPack)
    RefreshExpansionPackToggle()
    ; The update button shares the version label's space.
    LauncherUpdateButton := AddStyledButton(LauncherGui, 12, 682, 300, 30, "Preview Latest Update!", CheckForUpdates)
    LauncherUpdateButton.Visible := false
    CreateLauncherChatToggle()
    ; Include Jiub in the layout snapshot so it scales with the other controls.
    CreateHappyHourJiub()
    CaptureLauncherControlLayout()
    ApplyAccessibilityTextSize()
    ApplyEnhancedReadability()
    InitializeV016UiRefinements()
}

RegisterLauncherEventHandlers()
{
    global LauncherGui

    OnMessage(0x0201, HandleMouseDown)
    OnMessage(0x0202, ReleaseButton)
    OnMessage(0x0100, HandleThemedButtonKey)
    OnMessage(0x0007, HandleThemedButtonFocus)
    OnMessage(0x0008, HandleThemedButtonFocus)
    OnMessage(0x0215, HandleCaptureLost)
    LauncherGui.OnEvent("Close", QuitLauncher)
    OnExit(GuardPatchExit)
    OnExit(CleanupLauncher)
}


SetLauncherUpdateAvailable(isAvailable, latestVersion := "")
{
    global AppConfig, LauncherUpdateButton, LauncherVersionLabel, LauncherUpdateAvailable, LauncherUpdateDismissedVersion
    LauncherUpdateAvailable := isAvailable
    if !IsObject(LauncherUpdateButton) || !IsObject(LauncherVersionLabel)
        return
    if LauncherUpdateAvailable && latestVersion != "" {
        kind := GetLauncherUpdateKind(AppConfig.Version, latestVersion)
        LauncherUpdateButton.Text := kind = "hotfix" ? "Hotfix available" : "Preview Latest v" latestVersion " Update!"
        DllCall("user32\InvalidateRect", "Ptr", LauncherUpdateButton.Hwnd, "Ptr", 0, "Int", 1)
    }
    showUpdate := LauncherUpdateAvailable && latestVersion != LauncherUpdateDismissedVersion
    LauncherUpdateButton.Visible := showUpdate
    LauncherVersionLabel.Visible := !showUpdate
}

DismissLauncherUpdate(latestVersion)
{
    global LauncherUpdateDismissedVersion
    LauncherUpdateDismissedVersion := latestVersion
    SetLauncherUpdateAvailable(true, latestVersion)
}


CaptureLauncherControlLayout()
{
    global LauncherGui, LauncherControlLayout
    LauncherControlLayout := Map()
    for control in LauncherGui
    {
        try
        {
            control.GetPos(&x, &y, &width, &height)
            LauncherControlLayout[control.Hwnd] := {Control: control, X: x, Y: y, Width: width, Height: height}
        }
    }
}

ApplyLauncherControlScale()
{
    global LauncherGui, LauncherScale, LauncherControlLayout, ButtonFaces, LauncherHeading, LauncherVersionLabel, LauncherMorrowindFont
    if !IsObject(LauncherGui) || LauncherControlLayout.Count = 0
        return
    scale := LauncherScale / 100
    DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
    try
    {
        for hwnd, item in LauncherControlLayout
        {
            if !DllCall("IsWindow", "Ptr", hwnd)
                continue
            item.Control.Move(Round(item.X * scale), Round(item.Y * scale), Round(item.Width * scale), Round(item.Height * scale))
        }
        for hwnd, face in ButtonFaces
        {
            if !DllCall("IsWindow", "Ptr", hwnd) || face.Window != LauncherGui.Hwnd
                continue
            if face.HasOwnProp("IsInfo")
                face.Control.SetFont("s" Max(7, Round(10 * scale)) " Norm", "Palatino Linotype")
            else if !face.HasOwnProp("IsLabel")
                face.Control.SetFont("s" Max(7, Round(AccessibilityFontSize(10) * scale)) " Bold", "Segoe UI")
        }
        if IsObject(LauncherHeading)
            ; Preserve the Morrowind-style heading after startup/scaling.
            LauncherHeading.SetFont("s" Max(12, Round(19 * scale)) " Norm c241408", LauncherMorrowindFont)
        if IsObject(LauncherVersionLabel)
            LauncherVersionLabel.SetFont("s" Max(7, Round(9 * scale)), "Segoe UI")
    }
    finally DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0085 | 0x0100 | 0x0001 | 0x0004)
    RepaintMenuButtons()
}

ShowLauncherWindow(reuseCached := false, *)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, LauncherControlLayout, LauncherCachedScale, LauncherCachedLayoutCount
    ; Returning from a child window should never expose a blank/transparent
    ; launcher while its scale and themed controls are being restored. Show the
    ; existing launcher immediately behind a loading cover, do the expensive
    ; resize/repaint work, then reveal the completed page.
    ; Manage Characters is an OWNED book above a launcher that is already
    ; fully visible and painted. When its stored scale/layout are unchanged,
    ; there is nothing to rebuild or repaint on Close. The older return path
    ; needlessly walked every control and synchronously painted all themed
    ; buttons (including those still in the book), delaying its Hide() by
    ; more than a second in the user's 60-fps recording.
    ;
    ; Keep the original rebuild path for changed scale/layout or a hidden
    ; launcher. This fast path does NOT reveal an incomplete launcher: it is
    ; used only when the current parent window is already visible behind
    ; its owned Character Book.
    if reuseCached && LauncherCachedScale > 0
        && DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        && LauncherControlLayout.Count = LauncherCachedLayoutCount
    {
        desiredCachedScale := LauncherScaleMode = "Auto" ? GetAutomaticLauncherScale() : LauncherScale
        if desiredCachedScale = LauncherCachedScale
            return
    }
    ; The Characters book keeps its controls alive. Returning from it can
    ; reuse the existing launcher geometry when the layout remains valid.
    if LauncherCachedScale > 0 && DllCall("IsWindow", "Ptr", LauncherGui.Hwnd)
        && LauncherControlLayout.Count = LauncherCachedLayoutCount
    {
        desiredScale := LauncherScaleMode = "Auto" ? GetAutomaticLauncherScale() : LauncherScale
        if desiredScale = LauncherCachedScale
        {
            healthy := true
            for hwnd, item in LauncherControlLayout
            {
                if !DllCall("IsWindow", "Ptr", hwnd)
                {
                    healthy := false
                    break
                }
                item.Control.GetPos(&x, &y, &w, &h)
                ratio := desiredScale / 100
                if Abs(x - Round(item.X * ratio)) > 2 || Abs(y - Round(item.Y * ratio)) > 2
                    || Abs(w - Round(item.Width * ratio)) > 2 || Abs(h - Round(item.Height * ratio)) > 2
                {
                    healthy := false
                    break
                }
            }
            if healthy
            {
                LauncherGui.Show()
                RepaintMenuButtons()
                return
            }
            LogLauncherEvent("UI | Cached launcher geometry invalid; rebuilding under the existing frame cover.")
        }
    }
    ; Initial window geometry is calculated while hidden. Otherwise every
    ; fresh process launch paints a full-size 960x716 window and visibly
    ; shrinks it, even when the user has the same saved display settings.
    if !LauncherCachedScale
    {
        LauncherGui.Show("Hide w960 h716")
        ApplyLauncherScaleToWindow()
        CenterLauncherWithoutResizing()
        LauncherCachedScale := LauncherScale
        LauncherCachedLayoutCount := LauncherControlLayout.Count
        LauncherGui.Show()
        RepaintMenuButtons()
        return
    }
    ; Preserve the current window size while an existing layout is repaired.
    LauncherGui.Show()
    ; Capture the last frame immediately to hide repaint jank, but only show
    ; the Jiub card if the transition actually takes more than 120 ms.
    startedAt := A_TickCount
    BeginInterfaceUpdate(LauncherGui, "Waiting for Jiub...", false)
    coverMs := A_TickCount - startedAt
    scaleMs := 0, windowMs := 0, controlsMs := 0, centerMs := 0
    try
    {
        stepAt := A_TickCount
        if LauncherScaleMode = "Auto"
            LauncherScale := GetAutomaticLauncherScale()
        scaleMs := A_TickCount - stepAt
        stepAt := A_TickCount
        ApplyLauncherScaleToWindow()
        windowMs := A_TickCount - stepAt
        stepAt := A_TickCount
        ApplyLauncherControlScale()
        controlsMs := A_TickCount - stepAt
        stepAt := A_TickCount
        CenterLauncherWithoutResizing()
        centerMs := A_TickCount - stepAt
    }
    finally
    {
        EndInterfaceUpdate()
        LauncherCachedScale := LauncherScale
        LauncherCachedLayoutCount := LauncherControlLayout.Count
        totalMs := A_TickCount - startedAt
        if totalMs >= 250
            LogLauncherEvent("UI | Launcher transition " totalMs "ms | Cover " coverMs "ms | Scale " scaleMs "ms | Window " windowMs "ms | Controls " controlsMs "ms | Center " centerMs "ms | Final paint " (totalMs - coverMs - scaleMs - windowMs - controlsMs - centerMs) "ms.")
    }
}

SetWindowIcons()
{
    global LauncherGui, IconHandles
    for entry in [[1, 32], [0, 16]]
    {
        icon := LoadPicture(A_ScriptDir "\assets\icons\tes3np.ico", "Icon1 w" entry[2] " h" entry[2], &imageType)
        IconHandles.Push(icon)
        DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x80,
            "UPtr", entry[1], "Ptr", icon, "Ptr")
    }
}

CleanupLauncher(*)
{
    ReleaseLauncherMorrowindFont()
    global LauncherGui, HoverTimer, IconHandles, CharacterPage, LauncherDataResetting
    ; A confirmed full reset must not recreate logs or settings during OnExit.
    ; Normal shutdown records diagnostics; a full reset must not recreate user data.
    if !LauncherDataResetting
    {
        LogLauncherEvent("Launcher shutting down.")
    }
    StopGameRecovery()
    ReleaseTES3NPGameClients()
    DisposeGameLoginProgress()
    DisposeHappyHourJiub()
    StopEmbeddedInGameChat()
    CleanupMacros()
    CleanupPatcher()
    SetTimer(HoverTimer, 0)
    SetTimer(ShowSlowInterfaceLoading, 0)
    SetTimer(ReleaseInterfaceFrame, 0)
    ReleaseInterfaceFrame()
    if IsObject(CharacterPage)
        DestroyScaledMenu(CharacterPage)
    LauncherGui.Destroy()
    DisposeButtonPainter()
    for icon in IconHandles
        DllCall("DestroyIcon", "Ptr", icon)
    IconHandles := []
}



OfferDesktopShortcutOnFirstLaunch(*)
{
    global DataFile, AppDataDirectory
    ; Prompt once for a complete compiled distribution, never for source-tree
    ; tests and never again after either answer has been saved.
    if !A_IsCompiled || !FileExist(A_ScriptDir "\client\tes3mp.exe")
        return
    if IniRead(DataFile, "Launcher", "DesktopShortcutChoice", "") != ""
        return

    answer := MsgBox("Would you like a desktop shortcut for Nerevarine Prophecies?", "tes3np", "YesNo Icon?")
    ; Record the choice before attempting filesystem operations. Otherwise an
    ; unwritable desktop re-prompts at every startup despite the user's answer.
    DirCreate(AppDataDirectory)
    IniWrite(answer = "Yes" ? "Yes" : "No", DataFile, "Launcher", "DesktopShortcutChoice")
    if answer = "Yes"
    {
        try
        {
            FileCreateShortcut(A_ScriptFullPath, A_Desktop "\Nerevarine Prophecies.lnk",
                A_ScriptDir, "", "Launch Nerevarine Prophecies", A_ScriptFullPath)
        }
        catch Error as err
        {
            reason := SanitizeDiagnosticText(err.Message)
            if reason = ""
                reason := "Windows could not create the shortcut."
            MsgBox("Could not create the desktop shortcut: " reason
                "`nThe launcher will respect your choice and will not ask again.", "tes3np", "Icon!")
        }
    }
}
