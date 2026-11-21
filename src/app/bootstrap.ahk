; Application startup, quick-launch choice, tray wiring and shutdown.

global LauncherExpansionToggle := 0

StartLauncher()
{
    global HoverTimer, LauncherBadgeTestMode

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
    RecoverExpansionImports()

    BuildLauncherWindow()
    RegisterLauncherEventHandlers()
    SetTimer(HoverTimer, 30)
    ShowLauncherWithGameUpdates()

    SetTimer(CleanupStaleLauncherData, -1000)
    ; The opt-in cosmetic preview stays on the real launcher, but cannot
    ; contact the updater or show first-run prompts during this test.
    if !LauncherBadgeTestMode
    {
        SetTimer(CheckForUpdateAvailability, -250)
        SetTimer(OfferDesktopShortcutOnFirstLaunch, -1800)
    }
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
    global LauncherGui, LauncherExpansionToggle, LauncherBadgeTestMode, LauncherBadgeTestWindowHwnd

    LauncherGui := Gui("-Caption -Border", A_IconTip)
    ; Borderless launcher looks exactly like normal, while PowerShell can
    ; target only this opted-in test instance by its distinct window title.
    if LauncherBadgeTestMode
    {
        LauncherGui.Title := A_IconTip " [Badge Test]"
        LauncherBadgeTestWindowHwnd := LauncherGui.Hwnd
    }
    ; WS_CLIPCHILDREN keeps launcher repaints from drawing over the embedded chat window.
    styleGetter := A_PtrSize = 8 ? "GetWindowLongPtrW" : "GetWindowLongW"
    styleSetter := A_PtrSize = 8 ? "SetWindowLongPtrW" : "SetWindowLongW"
    launcherStyle := DllCall("user32\" styleGetter, "Ptr", LauncherGui.Hwnd, "Int", -16, "Ptr")
    DllCall("user32\" styleSetter, "Ptr", LauncherGui.Hwnd, "Int", -16, "Ptr", launcherStyle | 0x02000000, "Ptr")

    SetWindowIcons()
    BuildFrontPage()
    CreateLauncherVersionLabel()
    AddStyledButton(LauncherGui, 820, 684, 140, 32, "Launcher Settings", OpenLauncherSettingsV016)
    LauncherExpansionToggle := AddStyledButton(LauncherGui, 0, 0, 190, 27, "Expansion Pack: Disabled", ToggleExpansionPack)
    RefreshExpansionPackToggle()
    CreateLauncherUpdateBadge()
    CreateLauncherChatToggle()
    CreateLauncherDiscordAccount()
    CreateLauncherServerUpdates()
    ; Include Jiub in the layout snapshot so it scales with the other controls.
    CreateHappyHourJiub()
    CaptureLauncherControlLayout()
    ApplyAccessibilityTextSize()
    ApplyEnhancedReadability()
    InitializeV016UiRefinements()
}

RegisterLauncherEventHandlers()
{
    global LauncherGui, LauncherBadgeTestMode

    if LauncherBadgeTestMode
        OnMessage(0x8041, HandleLauncherBadgeTestMessage)
    OnMessage(0x0201, HandleMouseDown)
    OnMessage(0x0202, ReleaseButton)
    OnMessage(0x0100, HandleThemedButtonKey)
    OnMessage(0x0007, HandleThemedButtonFocus)
    OnMessage(0x0008, HandleThemedButtonFocus)
    OnMessage(0x0215, HandleCaptureLost)
    LauncherGui.OnEvent("Close", QuitLauncher)
    LauncherGui.OnEvent("Size", LauncherServerUpdatesResized)
    OnExit(GuardPatchExit)
    OnExit(CleanupLauncher)
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
