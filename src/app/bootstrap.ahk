; Application startup, quick-launch choice, tray wiring and shutdown.

StartLauncher()
{
    global LauncherGui, HoverTimer
    for asset in ["backgrounds\launcher.png", "controls\scroll-panel.png", "headings\quest.png",
        "headings\together.png", "controls\button.png", "backgrounds\character-book.png", "icons\tes3np.ico"]
    {
        if !FileExist(A_ScriptDir "\assets\" asset)
        {
            MsgBox("A required asset is missing: " asset "`nExtract the entire ZIP before running tes3np.", "tes3np")
            ExitApp()
        }
    }

    A_TrayMenu.Add("Open Launcher", ShowLauncherWindow)
    A_TrayMenu.Default := "Open Launcher"
    A_TrayMenu.Add("Stop game recovery", StopClient)
    A_TrayMenu.Add("Patch Tes3mp", OpenPatcher)
    TraySetIcon(A_ScriptDir "\assets\icons\tes3np.ico")
    A_IconTip := "tes3np - Nerevarine Prophecies Launcher"
    LauncherGui := Gui("-Caption -Border", A_IconTip)
    SetWindowIcons()
    BuildFrontPage()
    LauncherGui.SetFont("s9 cC5A45C", "Segoe UI")
    LauncherGui.Add("Text", "x12 y691 w180 h18 BackgroundTrans", "tes3np · v" AppConfig.Version)
    OnMessage(0x0201, HandleMouseDown)
    OnMessage(0x0202, ReleaseButton)
    OnMessage(0x0215, HandleCaptureLost)
    LauncherGui.OnEvent("Close", QuitLauncher)
    OnExit(GuardPatchExit)
    OnExit(CleanupLauncher)
    global SelectedProfile, Profiles
    SetTimer(HoverTimer, 30)
    ShowLauncherWindow()
    CheckModifiedClientFirstRun()
    BeginStartupPatchCheck()
}

ShowLauncherWindow(*)
{
    global LauncherGui
    PrepareWindowDisplay(LauncherGui)
    LauncherGui.Show("w960 h716")
    RevealWindowDisplay(LauncherGui)
}

ShowStartupChoice()
{
    global Profiles, SelectedProfile
    index := SelectedProfile > 0 && SelectedProfile <= Profiles.Length ? SelectedProfile : 1
    choice := Gui("-MinimizeBox -MaximizeBox", "tes3np — Ready to play")
    choice.BackColor := "E2CEA2"
    choice.SetFont("s11 c382314", "Segoe UI")
    choice.Add("Text", "x20 y20 w360 h30 Center", "How would you like to start?")
    launch := choice.Add("Button", "x20 y65 w360 h40 Default", "Launch " Profiles[index].Name)
    manage := choice.Add("Button", "x20 y115 w360 h40", "Manage Characters")
    open := choice.Add("Button", "x20 y165 w360 h40", "Open Launcher")
    launch.OnEvent("Click", LaunchFromStartup.Bind(choice, index))
    manage.OnEvent("Click", ManageFromStartup.Bind(choice))
    open.OnEvent("Click", OpenFromStartup.Bind(choice))
    choice.OnEvent("Close", QuitLauncher)
    choice.OnEvent("Escape", QuitLauncher)
    choice.Show("w400 h225")
}

LaunchFromStartup(choice, index, *)
{
    global Client
    choice.Opt("+OwnDialogs")
    LaunchProfileIndex(index)
    if Client.Enabled
        choice.Destroy()
}

OpenFromStartup(choice, *)
{
    choice.Destroy()
    ShowLauncherWindow()
}

ManageFromStartup(choice, *)
{
    choice.Destroy()
    OpenCharacterPage()
}

SetWindowIcons()
{
    global LauncherGui, IconHandles
    for entry in [[1, 32], [0, 16]]
    {
        icon := LoadPicture(A_ScriptDir "\assets\icons\tes3np.ico", "Icon1 w" entry[2] " h" entry[2], &imageType)
        IconHandles.Push(icon)
        ; Direct HWND messaging also works before the window becomes visible.
        DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x80,
            "UPtr", entry[1], "Ptr", icon, "Ptr")
    }
}

CleanupLauncher(*)
{
    global LauncherGui, HoverTimer, IconHandles, CharacterPage
    StopClient()
    CleanupMacros()
    CleanupPatcher()
    SetTimer(HoverTimer, 0)
    DllCall("ReleaseCapture")
    SetTimer(ShowSlowInterfaceLoading, 0)
    SetTimer(ReleaseInterfaceFrame, 0)
    ReleaseInterfaceFrame()
    if IsObject(CharacterPage)
        CharacterPage.Destroy()
    LauncherGui.Destroy()
    DisposeButtonPainter()
    for icon in IconHandles
        DllCall("DestroyIcon", "Ptr", icon)
    IconHandles := []
}
