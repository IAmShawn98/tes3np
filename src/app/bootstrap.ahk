; Application startup, quick-launch choice, tray wiring and shutdown.

global LauncherControlLayout := Map()
global LauncherVersionLabel := 0
global LauncherSettingsButton := 0
global LauncherUpdateButton := 0

StartLauncher()
{
    global LauncherGui, HoverTimer, SetupComplete, DataFile, LauncherVersionLabel, LauncherSettingsButton, LauncherUpdateButton
    InitializePatchLogMirror()
    LogLauncherEvent("Launcher startup beginning.")
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
    A_TrayMenu.Add("Open Launcher", ShowLauncherWindow)
    A_TrayMenu.Default := "Open Launcher"
    A_TrayMenu.Add("Stop game recovery", StopClient)
    A_TrayMenu.Add("Patch Tes3mp", OpenPatcher)
    TraySetIcon(A_ScriptDir "\assets\icons\tes3np.ico")
    A_IconTip := "tes3np - Nerevarine Prophecies Launcher"
    LoadLauncherScale()
    LoadDailyLoginSchedule()
    LauncherGui := Gui("-Caption -Border", A_IconTip)
    SetWindowIcons()
    SetupComplete := IniRead(DataFile, "Patch", "Complete", "0") = "1"
    BuildFrontPage()
    LauncherGui.SetFont("s9 cC5A45C", "Segoe UI")
    LauncherVersionLabel := LauncherGui.Add("Text", "x12 y691 w180 h18 BackgroundTrans", "tes3np · v" AppConfig.Version)
    LauncherSettingsButton := AddStyledButton(LauncherGui, 805, 675, 140, 32, "Launcher Settings", OpenLauncherSettingsV016)
    LauncherUpdateButton := AddStyledButton(LauncherGui, 650, 675, 140, 32, "Update Available", CheckForUpdates)
    LauncherUpdateButton.Visible := false
    CaptureLauncherControlLayout()
    ApplyAccessibilityTextSize()
    ApplyEnhancedReadability()
    InitializeV016UiRefinements()
    OnMessage(0x0201, HandleMouseDown)
    OnMessage(0x0202, ReleaseButton)
    OnMessage(0x0100, HandleThemedButtonKey)
    OnMessage(0x0007, HandleThemedButtonFocus)
    OnMessage(0x0008, HandleThemedButtonFocus)
    OnMessage(0x0215, HandleCaptureLost)
    LauncherGui.OnEvent("Close", QuitLauncher)
    OnExit(GuardPatchExit)
    OnExit(CleanupLauncher)
    global SelectedProfile, Profiles
    SetTimer(HoverTimer, 30)
    ShowLauncherWindow()
    FinishLauncherStartup()
    SetTimer(CheckForUpdateAvailability, -250)
    LogLauncherEvent("Launcher startup completed. Version v" AppConfig.Version ".")
}

SetLauncherUpdateAvailable(isAvailable)
{
    global LauncherSettingsButton, LauncherUpdateButton, LauncherControlLayout
    if !IsObject(LauncherSettingsButton) || !IsObject(LauncherUpdateButton)
        return
    ; The right-most slot always belongs to Launcher Settings. When an update is
    ; available, Update Available appears immediately to its left.
    LauncherSettingsButton.Move(805, 675, 140, 32)
    LauncherUpdateButton.Move(650, 675, 140, 32)
    LauncherUpdateButton.Visible := isAvailable
    if LauncherControlLayout.Has(LauncherSettingsButton.Hwnd) {
        LauncherControlLayout[LauncherSettingsButton.Hwnd].X := 805
        LauncherControlLayout[LauncherSettingsButton.Hwnd].Y := 675
    }
    if LauncherControlLayout.Has(LauncherUpdateButton.Hwnd) {
        LauncherControlLayout[LauncherUpdateButton.Hwnd].X := 650
        LauncherControlLayout[LauncherUpdateButton.Hwnd].Y := 675
    }
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
    global LauncherGui, LauncherScale, LauncherControlLayout, ButtonFaces, LauncherHeading, LauncherVersionLabel
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
            LauncherHeading.SetFont("s" Max(9, Round(14 * scale)) " Bold", "Georgia")
        if IsObject(LauncherVersionLabel)
            LauncherVersionLabel.SetFont("s" Max(7, Round(9 * scale)), "Segoe UI")
    }
    finally DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x000B, "Ptr", 1, "Ptr", 0)
    DllCall("RedrawWindow", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0085 | 0x0100 | 0x0001 | 0x0004)
    RepaintMenuButtons()
}

ShowLauncherWindow(*)
{
    global LauncherGui, LauncherScale, LauncherScaleMode
    ; Returning from a child window should never expose a blank/transparent
    ; launcher while its scale and themed controls are being restored. Show the
    ; existing launcher immediately behind a loading cover, do the expensive
    ; resize/repaint work, then reveal the completed page.
    LauncherGui.Show("w960 h716")
    BeginInterfaceUpdate(LauncherGui, "Returning to launcher...", true)
    try
    {
        if LauncherScaleMode = "Auto"
            LauncherScale := GetAutomaticLauncherScale()
        ApplyLauncherScaleToWindow()
        ApplyLauncherControlScale()
        CenterLauncherWithoutResizing()
    }
    finally EndInterfaceUpdate()
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
        DllCall("SendMessageW", "Ptr", LauncherGui.Hwnd, "UInt", 0x80,
            "UPtr", entry[1], "Ptr", icon, "Ptr")
    }
}

CleanupLauncher(*)
{
    global LauncherGui, HoverTimer, IconHandles, CharacterPage
    SyncPatchLogToLauncherLog()
    LogLauncherEvent("Launcher shutting down.")
    StopClient()
    CleanupMacros()
    CleanupPatcher()
    SetTimer(HoverTimer, 0)
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
