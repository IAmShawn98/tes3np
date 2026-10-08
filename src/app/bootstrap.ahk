; Application startup, quick-launch choice, tray wiring and shutdown.

global LauncherControlLayout := Map()
global LauncherVersionLabel := 0
global LauncherSettingsButton := 0
global LauncherUpdateButton := 0
global LauncherUpdateAvailable := false
global LauncherChatToggle := 0
global LauncherChatMenu := 0
global LauncherChatOpen := false

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
    InitializeLauncherMorrowindFont()
    ; Scheduled Daily Login can run before the Characters page has ever been
    ; opened, so its saved profiles must already exist in memory at startup.
    LoadProfiles()
    LoadDailyLoginSchedule()
    LauncherGui := Gui("-Caption -Border", A_IconTip)
    ; Set WS_CLIPCHILDREN before the launcher is ever shown. ChatHost is a
    ; native child HWND; parent background painting must not overwrite it.
    styleGetter := A_PtrSize = 8 ? "GetWindowLongPtrW" : "GetWindowLongW"
    styleSetter := A_PtrSize = 8 ? "SetWindowLongPtrW" : "SetWindowLongW"
    launcherStyle := DllCall("user32\" styleGetter, "Ptr", LauncherGui.Hwnd, "Int", -16, "Ptr")
    DllCall("user32\" styleSetter, "Ptr", LauncherGui.Hwnd, "Int", -16, "Ptr", launcherStyle | 0x02000000, "Ptr")

    SetWindowIcons()
    SetupComplete := IniRead(DataFile, "Patch", "Complete", "0") = "1"
    ; A completion flag from another TES3MP directory must not suppress setup.
    ; Do not rely on the flag when the saved installation is unavailable.
    if A_IsCompiled && SetupComplete
    {
        savedTesFolder := IniRead(DataFile, "Patch", "TesFolder", "")
        savedMorrowindFolder := IniRead(DataFile, "Patch", "MorrowindFolder", "")
        savedConfig := IniRead(DataFile, "Patch", "ConfigFile", "")
        if savedTesFolder = "" || StrLower(RTrim(savedTesFolder, "\/")) != StrLower(RTrim(A_ScriptDir, "\/"))
            || !FileExist(A_ScriptDir "\tes3mp.exe")
            || !FileExist(savedMorrowindFolder "\Data Files\Morrowind.esm")
            || !FileExist(savedConfig)
            SetupComplete := false
    }
    BuildFrontPage()
    LauncherGui.SetFont("s9 cC5A45C", "Segoe UI")
    LauncherVersionLabel := LauncherGui.Add("Text", "x12 y691 w180 h18 BackgroundTrans", "tes3np · v" AppConfig.Version)
    LauncherSettingsButton := AddStyledButton(LauncherGui, 805, 675, 140, 32, "Launcher Settings", OpenLauncherSettingsV016)
    ; Keep update notifications centered along the bottom edge, directly below the launcher scroll.
    LauncherUpdateButton := AddStyledButton(LauncherGui, 410, 675, 140, 32, "Update Available", CheckForUpdates)
    LauncherUpdateButton.Visible := false
    CreateLauncherChatToggle()
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
    ; Start the embedded HWND only after the layered launcher has been shown
    ; and its first paint has completed. Previously it was parented while hidden.
    SetTimer(StartEmbeddedInGameChat, -75)
    SetTimer(OfferFirstRunSetup, -1000)
    SetTimer(ShowMissedScheduledEvents, -750)
    SetTimer(CheckForUpdateAvailability, -250)
    LogLauncherEvent("Launcher startup completed. Version v" AppConfig.Version ".")
}


; The gold Game Chat tab belongs to the launcher, not the Discord/WebView2 host.
CreateLauncherChatToggle()
{
    global LauncherGui, LauncherChatToggle, LauncherChatMenu
    ; Draw the original vertical label ourselves: a STATIC control clips rotated
    ; text, whereas painting directly to its DC gives us the full 168px area.
    LauncherGui.SetFont("s11 Bold cFFFFFF", "Segoe UI")
    LauncherChatToggle := LauncherGui.Add("Text",
        "x3 y294 w45 h112 +0x100 BackgroundA77C3A", "")
    OnMessage(0x000F, PaintLauncherChatToggle)
    ; STATIC sends STN_CLICKED as WM_COMMAND to its parent.
    OnMessage(0x0111, LauncherChatCommandClick)
    LauncherChatMenu := Menu()
    LauncherChatMenu.Add("Automatic", (*) => SendLauncherChatCommand(2))
    LauncherChatMenu.Add("Always Shown", (*) => SendLauncherChatCommand(3))
    LauncherChatMenu.Add("Always Hidden", (*) => SendLauncherChatCommand(4))
    OnMessage(0x0204, LauncherChatRightClick)
}
PaintLauncherChatToggle(wParam, lParam, msg, hwnd)
{
    global LauncherChatToggle
    if !IsObject(LauncherChatToggle) || hwnd != LauncherChatToggle.Hwnd
        return
    ; WM_PAINT is handled here rather than letting STATIC clip the rotated font.
    ps := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
    dc := DllCall("user32\BeginPaint", "Ptr", hwnd, "Ptr", ps, "Ptr")
    if !dc
        return
    try
    {
        rect := Buffer(16, 0)
        DllCall("user32\GetClientRect", "Ptr", hwnd, "Ptr", rect)
        w := NumGet(rect, 8, "Int"), h := NumGet(rect, 12, "Int")
        gold := DllCall("gdi32\CreateSolidBrush", "UInt", 0x003A7CA7, "Ptr")
        DllCall("user32\FillRect", "Ptr", dc, "Ptr", rect, "Ptr", gold)
        DllCall("gdi32\DeleteObject", "Ptr", gold)
        frame := DllCall("gdi32\CreateSolidBrush", "UInt", 0x0078C7ED, "Ptr")
        DllCall("user32\FrameRect", "Ptr", dc, "Ptr", rect, "Ptr", frame)
        ; The original tab has a thicker pale-gold inset frame.
        NumPut("Int", 2, rect, 0)
        NumPut("Int", 2, rect, 4)
        NumPut("Int", w - 2, rect, 8)
        NumPut("Int", h - 2, rect, 12)
        DllCall("user32\FrameRect", "Ptr", dc, "Ptr", rect, "Ptr", frame)
        DllCall("gdi32\DeleteObject", "Ptr", frame)
        DllCall("gdi32\SetBkMode", "Ptr", dc, "Int", 1)
        DllCall("gdi32\SetTextColor", "Ptr", dc, "UInt", 0x00FFFFFF)
        font := DllCall("gdi32\CreateFontW",
            "Int", -19, "Int", 0, "Int", 900, "Int", 900,
            "Int", 700, "UInt", 0, "UInt", 0, "UInt", 0,
            "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 0,
            "UInt", 0, "Str", "Segoe UI", "Ptr")
        oldFont := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        ; Positive 90-degree escapement runs text upward from the baseline.
        DllCall("gdi32\TextOutW", "Ptr", dc, "Int", Round(w * 0.52),
            "Int", Round(h * 0.87), "Str", "Game Chat", "Int", 9)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldFont, "Ptr")
        DllCall("gdi32\DeleteObject", "Ptr", font)
        ; Arrow pointing left, matching the original toggle.
        pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 4, "UInt", 0x00FFFFFF, "Ptr")
        oldPen := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", pen, "Ptr")
        cx := Round(w * 0.32), cy := Round(h * 0.50)
        global LauncherChatOpen
        direction := LauncherChatOpen ? -1 : 1
        DllCall("gdi32\MoveToEx", "Ptr", dc, "Int", cx - direction * 9, "Int", cy, "Ptr", 0)
        DllCall("gdi32\LineTo", "Ptr", dc, "Int", cx + direction * 9, "Int", cy)
        DllCall("gdi32\LineTo", "Ptr", dc, "Int", cx, "Int", cy - 10)
        DllCall("gdi32\MoveToEx", "Ptr", dc, "Int", cx + direction * 9, "Int", cy, "Ptr", 0)
        DllCall("gdi32\LineTo", "Ptr", dc, "Int", cx, "Int", cy + 10)
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldPen, "Ptr")
        DllCall("gdi32\DeleteObject", "Ptr", pen)
    }
    finally DllCall("user32\EndPaint", "Ptr", hwnd, "Ptr", ps)
    return 0
}
LauncherChatCommandClick(wParam, lParam, msg, hwnd)
{
    global LauncherGui, LauncherChatToggle
    if !IsObject(LauncherChatToggle) || hwnd != LauncherGui.Hwnd
        return
    if lParam = LauncherChatToggle.Hwnd && (wParam >> 16) = 0
    {
        ToggleLauncherChat()
        return 0
    }
}
ToggleLauncherChat(*)
{
    global LauncherChatOpen
    LauncherChatOpen := !LauncherChatOpen
    SendLauncherChatCommand(1)
    DllCall("user32\InvalidateRect", "Ptr", LauncherChatToggle.Hwnd, "Ptr", 0, "Int", 1)
}
LauncherChatRightClick(wParam, lParam, msg, hwnd)
{
    global LauncherChatToggle, LauncherChatMenu
    if !IsObject(LauncherChatToggle)
        return
    MouseGetPos(,, &windowHwnd, &controlHwnd, 2)
    if controlHwnd = LauncherChatToggle.Hwnd
    {
        LauncherChatMenu.Show()
        return 0
    }
}
SendLauncherChatCommand(command)
{
    ; Hidden chat windows must also be addressable when the panel is closed.
    oldHidden := A_DetectHiddenWindows
    oldMatchMode := A_TitleMatchMode
    DetectHiddenWindows(true)
    try
    {
        SetTitleMatchMode(2)
        chatHwnd := WinExist("tes3np Chat Host")
        if chatHwnd
            DllCall("PostMessageW", "Ptr", chatHwnd, "UInt", 0x8331, "Ptr", command, "Ptr", 0)
        else
            LogLauncherEvent("Chat command " command " failed: tes3np Chat Host window not found.")
    }
    finally {
        DetectHiddenWindows(oldHidden)
        SetTitleMatchMode(oldMatchMode)
    }
}

SetLauncherUpdateAvailable(isAvailable)
{
    global LauncherSettingsButton, LauncherUpdateButton, LauncherControlLayout, LauncherUpdateAvailable
    LauncherUpdateAvailable := isAvailable
    if !IsObject(LauncherSettingsButton) || !IsObject(LauncherUpdateButton)
        return
    ; Positions are owned by LauncherControlLayout and scaled by
    ; ApplyLauncherControlScale(). Do not move these controls back to
    ; unscaled coordinates when update availability changes.
    LauncherUpdateButton.Visible := LauncherUpdateAvailable
    if LauncherControlLayout.Has(LauncherSettingsButton.Hwnd) {
        LauncherControlLayout[LauncherSettingsButton.Hwnd].X := 805
        LauncherControlLayout[LauncherSettingsButton.Hwnd].Y := 675
    }
    if LauncherControlLayout.Has(LauncherUpdateButton.Hwnd) {
        LauncherControlLayout[LauncherUpdateButton.Hwnd].X := 410
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
    ResizeEmbeddedInGameChat()
}

ShowLauncherWindow(*)
{
    global LauncherGui, LauncherScale, LauncherScaleMode
    ; Returning from a child window should never expose a blank/transparent
    ; launcher while its scale and themed controls are being restored. Show the
    ; existing launcher immediately behind a loading cover, do the expensive
    ; resize/repaint work, then reveal the completed page.
    LauncherGui.Show("w960 h716")
    BeginInterfaceUpdate(LauncherGui, "Waiting for Jiub...", true)
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
    ReleaseLauncherMorrowindFont()
    global LauncherGui, HoverTimer, IconHandles, CharacterPage
    SyncPatchLogToLauncherLog()
    LogLauncherEvent("Launcher shutting down.")
    SaveScheduledEventShutdownTime()
    StopClient()
    StopEmbeddedInGameChat()
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

OfferFirstRunSetup(*)
{
    global SetupComplete, LauncherGui, DataFile
    if A_IsCompiled
    {
        if SetupComplete
        {
            ; Verify managed files and OpenMW load order in the background worker.
            ; Verification is read-only and only prompts when repair is required.
            config := PatchConfigurationPath()
            morrowind := IniRead(DataFile, "Patch", "MorrowindFolder", "")
            if morrowind != "" && FileExist(config)
                StartPatchWorker("Verify", A_ScriptDir, morrowind, config, LauncherGui, true)
            return
        }
        ; Detection has finished once we are ready to offer installation.
        EndGameDetectionDisplay()
        if !FileExist(A_ScriptDir "\tes3mp.exe")
        {
            MsgBox("Place tes3np.exe in the folder containing tes3mp.exe and launch it again.", "Nerevarine Prophecies", "Icon!")
            return
        }
        if MsgBox("Install Nerevarine Prophecies patches now? Your original files will be backed up.", "Nerevarine Prophecies", "YesNo Icon?") != "Yes"
            return
        config := PatchConfigurationPath()
        morrowind := FindMorrowindFolder(config)
        if morrowind = ""
        {
            MsgBox("The Morrowind GOTY installation could not be detected. Select its location to complete setup.", "Nerevarine Prophecies", "Icon!")
            OpenPatcher()
            return
        }
        ; Run the same client compatibility check as manual installation.
        ; If setup cannot start, open the guided repair page with detected paths.
        if !CheckModifiedClientForPatch(A_ScriptDir, "Apply")
        {
            OpenPatcher()
            return
        }
        if !StartPatchWorker("Apply", A_ScriptDir, morrowind, config, LauncherGui, true)
        {
            MsgBox("Automatic installation could not start. Check the detected folders in Repair Game Install and try again.", "Nerevarine Prophecies", "Icon!")
            OpenPatcher()
        }
        return
    }
    OfferDesktopShortcutOnFirstLaunch()
}

OfferDesktopShortcutOnFirstLaunch(forceAfterInstall := false, *)
{
    global DataFile
    if forceAfterInstall && IniRead(DataFile, "Launcher", "PostInstallShortcutOffered", "0") = "1"
        return
    if !forceAfterInstall && IniRead(DataFile, "Launcher", "DesktopShortcutChoice", "") != ""
        return

    answer := MsgBox("Create a tes3np desktop shortcut?", "tes3np", "YesNo Icon?")
    IniWrite(answer = "Yes" ? "Yes" : "No", DataFile, "Launcher", "DesktopShortcutChoice")
    if forceAfterInstall
        IniWrite("1", DataFile, "Launcher", "PostInstallShortcutOffered")
    if answer != "Yes"
        return

    try
    {
        target := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
        arguments := A_IsCompiled ? "" : '"' A_ScriptFullPath '"'
        iconPath := A_IsCompiled ? target : A_ScriptDir "\assets\icons\tes3np.ico"
        FileCreateShortcut(target, A_Desktop "\Nerevarine Prophecies.lnk", A_ScriptDir, arguments, "Launch tes3np", iconPath)
    }
    catch as err
        MsgBox("Could not create the shortcut: " err.Message, "tes3np", "Icon!")
}
