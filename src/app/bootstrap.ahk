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
global LauncherChatToggle := 0
global LauncherChatMenu := 0
global LauncherChatOpen := false
global LauncherKillAlertGui := 0

StartLauncher()
{
    global LauncherGui, HoverTimer, SetupComplete, DataFile, LauncherVersionLabel, LauncherSettingsButton, LauncherUpdateButton, LauncherExpansionToggle, LauncherUpdateDismissedVersion
    ; A dismissal only lasts for this launcher session. Recheck next launch.
    LauncherUpdateDismissedVersion := ""
    InitializePatchLogMirror()
    LogLauncherEvent("Launcher startup beginning.")
    for asset in ["backgrounds\launcher.png", "backgrounds\og-creatures-overlay.png", "controls\scroll-panel.png", "headings\quest.png",
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
    A_TrayMenu.Add("Optional Expansion Pack", OpenPatcher)
    InitializeHappyHourJiub()
    TraySetIcon(A_ScriptDir "\assets\icons\tes3np.ico")
    A_IconTip := "tes3np - Nerevarine Prophecies Launcher"
    LoadLauncherScale()
    InitializeLauncherMorrowindFont()
    ; Scheduled Daily Login can run before the Characters page has ever been
    ; opened, so its saved profiles must already exist in memory at startup.
    LoadProfiles()
    ; Recover a saved custom-client swap before launch buttons are available.
    RecoverCustomClientOverrides()
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
    if SetupComplete
    {
        savedTesFolder := IniRead(DataFile, "Patch", "TesFolder", "")
        savedMorrowindFolder := IniRead(DataFile, "Patch", "MorrowindFolder", "")
        savedConfig := IniRead(DataFile, "Patch", "ConfigFile", "")
        detectedTesFolder := FindTES3MPFolder()
        if savedTesFolder = "" || detectedTesFolder = ""
            || StrLower(RTrim(savedTesFolder, "\/")) != StrLower(RTrim(detectedTesFolder, "\/"))
            || !FileExist(savedTesFolder "\tes3mp.exe")
            || !FileExist(savedMorrowindFolder "\Data Files\Morrowind.esm")
            || !FileExist(savedConfig)
            SetupComplete := false
    }
    BuildFrontPage()
    LauncherGui.SetFont("s9 cC5A45C", "Segoe UI")
    LauncherVersionLabel := LauncherGui.Add("Text", "x12 y691 w300 h18 BackgroundTrans", "tes3np · v" AppConfig.Version)
    LauncherVersionLabel.OnEvent("Click", CheckForUpdates)
    LauncherSettingsButton := AddStyledButton(LauncherGui, 820, 684, 140, 32, "Launcher Settings", OpenLauncherSettingsV016)
    ; Global EP switch in the upper-left frame, away from the main scroll.
    LauncherExpansionToggle := AddStyledButton(LauncherGui, 0, 0, 190, 27, "Expansion Pack: Disabled", ToggleExpansionPack)
    RefreshExpansionPackToggle()
    ; Update notification replaces the version label in the lower-left frame.
    LauncherUpdateButton := AddStyledButton(LauncherGui, 12, 682, 300, 30, "Preview Latest Update!", CheckForUpdates)
    LauncherUpdateButton.Visible := false
    CreateLauncherChatToggle()
    ; Register Jiub's transparent Happy Hour expression as a NORMAL child
    ; control before capturing layout, so dragging/scaling stays synchronous.
    CreateHappyHourJiub()
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
    ; Expansion Pack setup is optional; never run patch verification at startup.
    SetTimer(ShowMissedScheduledEvents, -750)
    SetTimer(CheckForUpdateAvailability, -250)
    ; Offer the shortcut once after the first window is visible; never block startup.
    SetTimer(OfferDesktopShortcutOnFirstLaunch, -1800)
    ; Once per installation, find the actual Morrowind data directory without
    ; requiring or patching a separately installed TES3MP runtime.
    SetTimer(CheckFirstRunMorrowind, -2300)
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
    ; Route clicks through the control's native AHK event. WM_COMMAND
    ; interception can be swallowed by the launcher themed-button handlers.
    LauncherChatToggle.OnEvent("Click", ToggleLauncherChat)
    ; The chat host reports its actual open/closed state after every change.
    OnMessage(0x8332, LauncherChatStateChanged)
    OnMessage(0x8333, LauncherPickleKillAlert)
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
            "Int", -21, "Int", 0, "Int", 900, "Int", 900,
            "Int", 700, "UInt", 0, "UInt", 0, "UInt", 0,
            "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 0,
            "UInt", 0, "Str", "Segoe UI", "Ptr")
        oldFont := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        ; Positive 90-degree escapement runs text upward from the baseline.
        DllCall("gdi32\TextOutW", "Ptr", dc, "Int", Round(w * 0.53),
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
    ; Do not guess the new state: automatic mode can open/close chat itself.
    SendLauncherChatCommand(1)
}
LauncherPickleKillAlert(wParam, lParam, msg, hwnd)
{
    global LauncherGui, LauncherKillAlertGui
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd
        return
    alertFile := A_AppData "\TES3NP\Logs\last-kill-alert.txt"
    eventText := "A character was killed in Nerevarine Prophecies!"
    try {
        if FileExist(alertFile)
            eventText := Trim(FileRead(alertFile, "UTF-8"))
    }
    if !eventText
        eventText := "A character was killed in Nerevarine Prophecies!"
    ; A native launcher popup is reliable even when Windows suppresses tray toasts.
    try {
        if IsObject(LauncherKillAlertGui)
            LauncherKillAlertGui.Destroy()
        LauncherKillAlertGui := Gui("+AlwaysOnTop -Caption +ToolWindow", "TES3NP Kill Alert")
        LauncherKillAlertGui.BackColor := "261E14"
        LauncherKillAlertGui.SetFont("s11 Bold cE8C77C", "Segoe UI")
        LauncherKillAlertGui.Add("Text", "x14 y12 w400 h26", "TES3NP Kill Alert")
        LauncherKillAlertGui.SetFont("s10 Norm cFFFFFF", "Segoe UI")
        LauncherKillAlertGui.Add("Text", "x14 y42 w400 h64", eventText)
        LauncherKillAlertGui.Show("NoActivate w428 h115")
        SetTimer(CloseLauncherKillAlert, -6500)
    }
    catch as err {
        LogLauncherEvent("Kill alert popup error: " err.Message)
    }
    TrayTip(eventText, "TES3NP Kill Alert", 0x1)
    LogLauncherEvent("Game Chat kill alert: " eventText)
    return 0
}
CloseLauncherKillAlert()
{
    global LauncherKillAlertGui
    if IsObject(LauncherKillAlertGui) {
        try LauncherKillAlertGui.Destroy()
        LauncherKillAlertGui := 0
    }
}
LauncherChatStateChanged(wParam, lParam, msg, hwnd)
{
    global LauncherGui, LauncherChatToggle, LauncherChatOpen
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd
        return
    LauncherChatOpen := (wParam != 0)
    if IsObject(LauncherChatToggle)
        DllCall("user32\InvalidateRect", "Ptr", LauncherChatToggle.Hwnd, "Ptr", 0, "Int", 1)
    return 0
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

SetLauncherUpdateAvailable(isAvailable, latestVersion := "")
{
    global LauncherUpdateButton, LauncherVersionLabel, LauncherUpdateAvailable, LauncherUpdateDismissedVersion
    LauncherUpdateAvailable := isAvailable
    if !IsObject(LauncherUpdateButton) || !IsObject(LauncherVersionLabel)
        return
    if LauncherUpdateAvailable && latestVersion != "" {
        LauncherUpdateButton.Text := "Preview Latest v" latestVersion " Update!"
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
    ResizeEmbeddedInGameChat()
}

ShowLauncherWindow(reuseCached := false, *)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, LauncherControlLayout, LauncherCachedScale, LauncherCachedLayoutCount
    ; Returning from a child window should never expose a blank/transparent
    ; launcher while its scale and themed controls are being restored. Show the
    ; existing launcher immediately behind a loading cover, do the expensive
    ; resize/repaint work, then reveal the completed page.
    ; The Characters book keeps its controls alive. Returning from it can
    ; reuse the existing launcher geometry when the layout remains valid.
    if reuseCached && LauncherCachedScale > 0 && DllCall("IsWindow", "Ptr", LauncherGui.Hwnd)
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
                ResizeEmbeddedInGameChat()
                return
            }
            LogLauncherEvent("UI | Cached launcher geometry invalid; rebuilding under the existing frame cover.")
        }
    }
    LauncherGui.Show("w960 h716")
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
    global LauncherGui, HoverTimer, IconHandles, CharacterPage, LauncherDataResetting
    ; A confirmed full reset must not recreate logs or settings during OnExit.
    ; Normal shutdown keeps the established diagnostic/scheduler writes.
    if !LauncherDataResetting
    {
        SyncPatchLogToLauncherLog()
        LogLauncherEvent("Launcher shutting down.")
        SaveScheduledEventShutdownTime()
    }
    StopClient()
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
        CharacterPage.Destroy()
    LauncherGui.Destroy()
    DisposeButtonPainter()
    for icon in IconHandles
        DllCall("DestroyIcon", "Ptr", icon)
    IconHandles := []
}


OfferFirstRunSetup(*)
{
    global SetupComplete, LauncherGui, DataFile, GameDetectionActive
    static firstRunPromptShown := false
    static firstRunDetectionStarted := 0
    if SetupComplete
    {
        ; Verify returning players without showing the first-install dialog.
        config := IniRead(DataFile, "Patch", "ConfigFile", PatchConfigurationPath())
        morrowind := IniRead(DataFile, "Patch", "MorrowindFolder", "")
        tesFolder := FindTES3MPFolder()
        if tesFolder != "" && morrowind != "" && FileExist(config)
            StartPatchWorker("Verify", tesFolder, morrowind, config, LauncherGui, true)
        return
    }
    if firstRunPromptShown
        return
    ; Detect the actual TES3MP executable next to the launcher, not a stale
    ; saved installation path. Never leave first-time users waiting indefinitely.
    if !firstRunDetectionStarted
        firstRunDetectionStarted := A_TickCount
    ; Use the same TES3MP folder discovery as the patcher. The launcher may
    ; be installed in a sibling, parent, or nested TES3MP directory.
    tesFolder := FindTES3MPFolder()
    if tesFolder = ""
    {
        if A_TickCount - firstRunDetectionStarted < 5000
            return
        firstRunPromptShown := true
        SetTimer(OfferFirstRunSetup, 0)
        LogLauncherEvent("First-run TES3MP detection failed: no TES3MP executable was located.")
        EndGameDetectionDisplay()
        MsgBox("Tes3mp could not be detected in the launcher folder.`n`nPlace tes3np.exe in your Tes3mp installation folder, then click Patch Tes3mp to continue.", "Tes3mp folder not found", "Icon!")
        return
    }
    firstRunPromptShown := true
    SetTimer(OfferFirstRunSetup, 0)
    ; A missing setup flag does not prove the files are unpatched. Verify the
    ; existing installation first, without changing game files.
    config := PatchConfigurationPath()
    morrowind := FindMorrowindFolder(config)
    if morrowind != "" && FileExist(config)
    {
        LogLauncherEvent("First-run TES3MP folder detected; verifying existing installation before offering patches.")
        EndGameDetectionDisplay()
        if StartPatchWorker("Verify", tesFolder, morrowind, config, LauncherGui, true)
            return
    }
    LogLauncherEvent("First-run TES3MP folder detected at " tesFolder "; offering patch installation.")
    if MsgBox("Install Nerevarine Prophecies patches now? Your original files will be backed up.", "Nerevarine Prophecies", "YesNo Icon?") = "Yes"
    {
        EndGameDetectionDisplay()
        OpenPatcher()
    }
    else
        EndGameDetectionDisplay()
}

OfferDesktopShortcutOnFirstLaunch(forceAfterInstall := false, *)
{
    global DataFile, AppDataDirectory
    ; Only offer a shortcut for a complete compiled distribution. In particular,
    ; never create one to a source-tree launcher without its packaged client.
    if !A_IsCompiled || !FileExist(A_ScriptDir "\client\tes3mp.exe")
        return
    if IniRead(DataFile, "Launcher", "DesktopShortcutChoice", "") != ""
        return

    answer := MsgBox("Would you like a Nerevarine Prophecies shortcut on your desktop?", "tes3np", "YesNo Icon?")
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
            MsgBox("Could not create the desktop shortcut: " err.Message
                "`nThe launcher will respect your choice and will not ask again.", "tes3np", "Icon!")
    }
}
