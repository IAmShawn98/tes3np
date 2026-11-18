; Non-activating TES3MP login progress card. ClientTick owns inputs and timing.
global LoginProgressGui := 0
global LoginProgressRows := []
global LoginProgressFooter := 0
global LoginProgressCharacterName := 0
global LoginProgressSpecies := ""
global LoginProgressPortraitFile := ""
global LoginProgressSummaryDots := []
global LoginProgressStageStarted := 0
global LoginProgressMode := ""
global LoginProgressStage := 1
global LoginProgressName := ""
global LoginProgressPid := 0
global LoginProgressHwnd := 0
global LoginProgressCloseAt := 0
global LoginProgressDisabled := false
global LoginProgressShown := false
global LoginProgressLastX := -1
global LoginProgressLastY := -1
global LoginProgressGeneration := 0
global LoginProgressHardDeadline := 0

BeginGameLoginProgress(name, species := "", portraitFile := "")
{
    global LoginProgressGui, LoginProgressSpecies, LoginProgressPortraitFile
    global LoginProgressMode, LoginProgressStage, LoginProgressName
    global LoginProgressPid, LoginProgressHwnd, LoginProgressCloseAt, LoginProgressDisabled
    global LoginProgressStageStarted
    global LoginProgressGeneration, LoginProgressHardDeadline
    ; Recreate the visual only between logins so its portrait follows the
    ; selected character. This never restarts ClientTick or the game.
    if IsObject(LoginProgressGui)
        DisposeGameLoginProgress()
    LoginProgressSpecies := NormalizeCharacterSpecies(species)
    LoginProgressPortraitFile := NormalizeCustomPortraitFile(portraitFile)
    LoginProgressGeneration += 1
    LoginProgressHardDeadline := 0
    LoginProgressMode := "login"
    LoginProgressStage := 1
    LoginProgressStageStarted := A_TickCount
    LoginProgressName := name
    LoginProgressPid := 0
    LoginProgressHwnd := 0
    LoginProgressCloseAt := 0
    LoginProgressDisabled := false
    HideGameLoginProgress()
    ToolTip(, , , 1)
}

SetGameLoginProgressStage(stage)
{
    global LoginProgressMode, LoginProgressStage, LoginProgressStageStarted
    global LoginProgressHardDeadline, Client
    if LoginProgressMode != "login" || stage < 1 || stage > 4
        return
    if LoginProgressStage != stage
    {
        LoginProgressStage := stage
        LoginProgressStageStarted := A_TickCount
    }
    if stage = 1 && !LoginProgressHardDeadline
    {
        ; Presentation-only failsafe. The main watchdog still owns login
        ; attempts, retries and the running TES3MP process.
        expectedMs := Round((Client.UsernameDelay + Client.PasswordDelay
            + Client.LoadDelay + 15) * 1000)
        LoginProgressHardDeadline := A_TickCount + Max(60000, expectedMs)
    }
    UpdateGameLoginProgress()
}

CompleteGameLoginProgress(name, pid, hwnd)
{
    global LoginProgressMode, LoginProgressStage, LoginProgressName
    global LoginProgressPid, LoginProgressHwnd, LoginProgressCloseAt, AppConfig
    global LoginProgressGeneration
    if LoginProgressMode != "login"
        return
    LoginProgressMode := "complete"
    LoginProgressStage := 5
    LoginProgressName := name
    LoginProgressPid := pid
    LoginProgressHwnd := hwnd
    LoginProgressCloseAt := A_TickCount + 3000
    ; Independently dismiss the native card after three seconds even if
    ; the repainting timer is interrupted. The session token prevents an old
    ; callback from closing a later character's login overlay.
    SetTimer(DismissCompletedLoginProgress.Bind(LoginProgressGeneration), -3100)
    SetTimer(UpdateGameLoginProgress, AppConfig.TooltipMs)
    UpdateGameLoginProgress()
}

DismissCompletedLoginProgress(generation)
{
    global LoginProgressGeneration, LoginProgressMode, LoginProgressCloseAt
    if generation != LoginProgressGeneration || LoginProgressMode != "complete"
        return
    if A_TickCount < LoginProgressCloseAt
    {
        SetTimer(DismissCompletedLoginProgress.Bind(generation),
            -Max(50, LoginProgressCloseAt - A_TickCount + 50))
        return
    }
    DismissGameLoginProgress()
}

HideGameLoginProgress()
{
    global LoginProgressGui, LoginProgressShown, LoginProgressLastX, LoginProgressLastY
    ; The cached visibility flag can become stale if the game disappears
    ; while the nonactivating overlay is being repainted. Always hide the
    ; actual native window, even if LoginProgressShown was already cleared.
    if IsObject(LoginProgressGui)
    {
        try LoginProgressGui.Hide()
        try
        {
            hwnd := LoginProgressGui.Hwnd
            if DllCall("IsWindow", "Ptr", hwnd) && DllCall("IsWindowVisible", "Ptr", hwnd)
                DllCall("ShowWindow", "Ptr", hwnd, "Int", 0)
        }
    }
    LoginProgressShown := false
    LoginProgressLastX := -1
    LoginProgressLastY := -1
}

DismissGameLoginProgress()
{
    global LoginProgressMode, LoginProgressCloseAt, LoginProgressPid, LoginProgressHwnd
    SetTimer(UpdateGameLoginProgress, 0)
    LoginProgressMode := ""
    LoginProgressCloseAt := 0
    LoginProgressPid := 0
    LoginProgressHwnd := 0
    HideGameLoginProgress()
}

DisposeGameLoginProgress()
{
    global LoginProgressGui, LoginProgressRows, LoginProgressFooter
    global LoginProgressCharacterName, LoginProgressSummaryDots
    DismissGameLoginProgress()
    if IsObject(LoginProgressGui)
        try LoginProgressGui.Destroy()
    LoginProgressGui := 0
    LoginProgressRows := []
    LoginProgressFooter := 0
    LoginProgressCharacterName := 0
    LoginProgressSummaryDots := []
}

GetCharacterLoginIconPath(species, portraitFile := "")
{
    ; Per-character images live in roaming AppData and can be replaced
    ; independently from the bundled species ICOs. Missing files fall back.
    customPath := GetCustomPortraitPath(portraitFile)
    if customPath != "" && FileExist(customPath)
        return customPath
    species := NormalizeCharacterSpecies(species)
    slugs := Map("Argonian", "argonian", "Breton", "breton",
        "Dark Elf", "dark-elf", "High Elf", "high-elf", "Imperial", "imperial",
        "Khajiit", "khajiit", "Nord", "nord", "Orc", "orc",
        "Redguard", "redguard", "Wood Elf", "wood-elf")
    if species != "" && slugs.Has(species)
    {
        specific := A_ScriptDir "\assets\icons\species\" slugs[species] ".ico"
        if FileExist(specific)
            return specific
    }
    return A_ScriptDir "\assets\icons\tes3np.ico"
}

FitGameLoginProgress(area, gameWindow, normalScale)
{
    if area.Width < 1 || area.Height < 1
        return 0
    scale := Min(normalScale, area.Width / 420, area.Height / 481)
    width := Round(420 * scale), height := Round(481 * scale)
    if width < 1 || height < 1
        return 0
    ; Keep the original anchor when the standard card fits. A constrained
    ; card centers within the visible game client instead.
    anchor := scale < normalScale ? area : gameWindow
    x := anchor.X + Round((anchor.Width - width) / 2)
    y := anchor.Y + Round((anchor.Height - height) / 2)
    return {Scale: scale, Width: width, Height: height,
        X: Max(area.X, Min(area.X + area.Width - width, x)),
        Y: Max(area.Y, Min(area.Y + area.Height - height, y))}
}

GetGameLoginProgressLayout(hwnd)
{
    target := "ahk_id " hwnd
    WinGetPos(&x, &y, &width, &height, target)
    gameWindow := {X: x, Y: y, Width: width, Height: height}
    WinGetClientPos(&x, &y, &width, &height, target)
    ; A windowed game can straddle a monitor edge. Fit within the visible
    ; client on its monitor, leaving fullscreen placement unchanged.
    info := Buffer(40, 0) ; MONITORINFO
    NumPut("UInt", info.Size, info)
    monitor := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
    if monitor && DllCall("GetMonitorInfoW", "Ptr", monitor, "Ptr", info, "Int")
    {
        right := Min(x + width, NumGet(info, 12, "Int"))
        bottom := Min(y + height, NumGet(info, 16, "Int"))
        x := Max(x, NumGet(info, 4, "Int")), y := Max(y, NumGet(info, 8, "Int"))
        width := right - x, height := bottom - y
    }
    return FitGameLoginProgress({X: x, Y: y, Width: width, Height: height}, gameWindow, A_ScreenDPI / 96)
}

GameLoginProgressFontSize(points, scale)
{
    normalScale := A_ScreenDPI / 96
    return scale >= normalScale ? points : Max(1, Floor(points * scale / normalScale))
}

CreateGameLoginProgress(layout)
{
    global LoginProgressGui, LoginProgressRows
    global LoginProgressFooter
    global LoginProgressCharacterName, LoginProgressSummaryDots, LoginProgressSpecies, LoginProgressPortraitFile
    p := (value) => Round(value * layout.Scale)
    fontSize := (points) => GameLoginProgressFontSize(points, layout.Scale)
    ; Nonactivating, click-through window: preserve TES3MP mouse and keyboard.
    window := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x08000020", "tes3np Login Progress")
    ; Register the window before adding controls so partial setup is disposable.
    LoginProgressGui := window
    window.ProgressScale := layout.Scale
    window.BackColor := "28241F"

    ; Four 4px gold strips are always visible in the production card.
    ; They are inset, so none are clipped by the native client bounds.
    for line in [[0, 0, 420, 4], [0, 477, 420, 4], [0, 0, 4, 481], [416, 0, 4, 481]]
        window.Add("Text", "x" p(line[1]) " y" p(line[2])
            " w" p(line[3]) " h" p(line[4]) " BackgroundD1AE67", "")
    window.SetFont("s" fontSize(15) " Bold cF2E4D0", "Georgia")
    window.Add("Text", "x" p(20) " y" p(21) " w" p(380)
        " h" p(38) " Center BackgroundTrans +0x4000", "Logging in...")
    portraitPath := GetCharacterLoginIconPath(LoginProgressSpecies, LoginProgressPortraitFile)
    pictureOptions := "x" p(174) " y" p(60) " w" p(72) " h" p(72)
    ; Icon1 applies to ICO resources, but not to custom PNG/JPG/BMP portraits.
    if RegExMatch(portraitPath, "i)\.ico$")
        pictureOptions .= " Icon1"
    window.Add("Picture", pictureOptions, portraitPath)
    window.SetFont("s" fontSize(13) " Bold cF2E4D0", "Georgia")
    LoginProgressCharacterName := window.Add("Text", "x" p(24) " y" p(143)
        " w" p(372) " h" p(30) " Center BackgroundTrans", "")
    window.Add("Text", "x" p(27) " y" p(181) " w" p(366) " h" p(2) " Background806B51", "")
    steps := ["Loading Name Screen...", "Typing Name...",
        "Loading Password Screen...", "Typing Password..."]
    LoginProgressRows := []
    for index, labelText in steps
    {
        y := p(197 + (index - 1) * 46)
        window.SetFont("s" fontSize(11) " cC8BFB4", "Segoe UI")
        label := window.Add("Text", "x" p(30) " y" y " w" p(360)
            " h" p(22) " Center BackgroundTrans", labelText)
        window.SetFont("s" fontSize(13) " cFFFFFF", "Segoe UI Symbol")
        dot := window.Add("Text", "x" p(195) " y" (y + p(23))
            " w" p(30) " h" p(21) " Center BackgroundTrans", "●")
        window.SetFont("s" fontSize(12) " Bold c173C2A", "Segoe UI Symbol")
        symbol := window.Add("Text", "x" p(195) " y" (y + p(23))
            " w" p(30) " h" p(21) " Center BackgroundTrans +0x200 Hidden", "✔")
        LoginProgressRows.Push({Dot: dot, Label: label, Symbol: symbol,
            BaseText: labelText, SymbolText: "", DotColor: "", LabelColor: ""})
    }
    window.Add("Text", "x" p(27) " y" p(391) " w" p(366) " h" p(2) " Background806B51", "")
    window.SetFont("s" fontSize(10) " Bold cD3B687", "Segoe UI")
    LoginProgressFooter := window.Add("Text", "x" p(24) " y" p(403)
        " w" p(372) " h" p(25) " Center BackgroundTrans +0x4000", "")
    LoginProgressSummaryDots := []
    Loop 4
    {
        x := p(135 + (A_Index - 1) * 42)
        window.SetFont("s" fontSize(18) " cFFFFFF", "Segoe UI Symbol")
        circle := window.Add("Text", "x" x " y" p(440)
            " w" p(28) " h" p(27) " Center BackgroundTrans +0x4000", "●")
        window.SetFont("s" fontSize(15) " Bold c173C2A", "Segoe UI Symbol")
        symbol := window.Add("Text", "x" x " y" p(442)
            " w" p(28) " h" p(27) " Center BackgroundTrans +0x200 Hidden", "✔")
        LoginProgressSummaryDots.Push({Circle: circle, Symbol: symbol, Color: "", SymbolText: ""})
    }
    window.Show("Hide w" layout.Width " h" layout.Height)
}

RenderGameLoginProgress()
{
    global LoginProgressGui, LoginProgressCharacterName, LoginProgressRows
    global LoginProgressFooter, LoginProgressSummaryDots, LoginProgressName
    global LoginProgressMode, LoginProgressStage, LoginProgressStageStarted
    scale := LoginProgressGui.ProgressScale
    dirty := false
    if LoginProgressCharacterName.Text != LoginProgressName
    {
        LoginProgressCharacterName.Text := LoginProgressName
        dirty := true
    }
    complete := LoginProgressMode = "complete"
    stage := LoginProgressStage
    dots := SubStr("...", 1, 1 + Mod(Floor(Max(0, A_TickCount - LoginProgressStageStarted) / 350), 3))
    for index, row in LoginProgressRows
    {
        finished := complete || index < stage
        active := !finished && index = stage
        color := finished ? "6EE29B" : active ? "62AFFF" : "FFFFFF"
        labelColor := finished ? "95D5AC" : active ? "F2E4D0" : "C8BFB4"
        ending := finished ? "!" : active ? dots : "..."
        labelText := RTrim(row.BaseText, ".") ending
        if row.Label.Text != labelText
        {
            row.Label.Text := labelText
            dirty := true
        }
        if row.DotColor != color
        {
            row.Dot.SetFont("c" color)
            row.DotColor := color
            dirty := true
        }
        if row.LabelColor != labelColor
        {
            row.Label.SetFont("c" labelColor)
            row.LabelColor := labelColor
            dirty := true
        }
        symbol := finished ? "✔" : active ? "!" : ""
        if row.SymbolText != symbol
        {
            row.Symbol.Text := symbol
            if symbol = "✔"
                row.Symbol.SetFont("s" GameLoginProgressFontSize(12, scale) " Bold c173C2A", "Segoe UI Symbol")
            else if symbol = "!"
                row.Symbol.SetFont("s" GameLoginProgressFontSize(14, scale) " Bold c173C2A", "Segoe UI")
            row.SymbolText := symbol
            dirty := true
        }
        if row.Symbol.Visible != (symbol != "")
        {
            row.Symbol.Visible := symbol != ""
            dirty := true
        }
    }
    for index, marker in LoginProgressSummaryDots
    {
        finished := complete || index < stage
        active := !finished && index = stage
        color := finished ? "6EE29B" : active ? "62AFFF" : "FFFFFF"
        if marker.Color != color
        {
            marker.Circle.SetFont("c" color)
            marker.Color := color
            dirty := true
        }
        symbol := finished ? "✔" : active ? "!" : ""
        if marker.SymbolText != symbol
        {
            marker.Symbol.Text := symbol
            if symbol = "✔"
                marker.Symbol.SetFont("s" GameLoginProgressFontSize(15, scale) " Bold c173C2A", "Segoe UI Symbol")
            else if symbol = "!"
                marker.Symbol.SetFont("s" GameLoginProgressFontSize(17, scale) " Bold c173C2A", "Segoe UI")
            marker.SymbolText := symbol
            dirty := true
        }
        if marker.Symbol.Visible != (symbol != "")
        {
            marker.Symbol.Visible := symbol != ""
            dirty := true
        }
    }
    if complete
        status := "Login Complete!"
    else
        status := ["Loading name screen...", "Typing name...",
            "Loading password screen...", "Typing password..."][stage]
    if LoginProgressFooter.Text != status
    {
        LoginProgressFooter.Text := status
        dirty := true
    }
    if dirty
        ; Repaint child HWNDs as well as the parent: checkmarks must not
        ; remain visually stale after a new login resets its progress stage.
        DllCall("RedrawWindow", "Ptr", LoginProgressGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
}

PresentGameLoginProgress(layout)
{
    global LoginProgressGui, LoginProgressMode, LoginProgressShown, LoginProgressLastX, LoginProgressLastY
    previousCritical := Critical("On")
    previous := LoginProgressGui
    try
    {
        if LoginProgressMode = ""
            return
        if !IsObject(previous) || previous.ProgressScale != layout.Scale
        {
            ; Construct the new size while hidden and paint current state.
            ; Keep the same login stage, generation, and dismissal deadline.
            CreateGameLoginProgress(layout)
            LoginProgressShown := false
        }
        RenderGameLoginProgress()
        if !LoginProgressShown
        {
            LoginProgressGui.Show("NA x" layout.X " y" layout.Y " w" layout.Width " h" layout.Height)
            LoginProgressShown := true
        }
        else if layout.X != LoginProgressLastX || layout.Y != LoginProgressLastY
            DllCall("SetWindowPos", "Ptr", LoginProgressGui.Hwnd, "Ptr", 0,
                "Int", layout.X, "Int", layout.Y, "Int", 0, "Int", 0, "UInt", 0x15)
        LoginProgressLastX := layout.X
        LoginProgressLastY := layout.Y
    }
    finally
    {
        if IsObject(previous) && previous != LoginProgressGui
            try previous.Destroy()
        Critical(previousCritical)
    }
}

CanShowGameLoginProgress(gameHwnd)
{
    global LoginProgressShown
    foregroundHwnd := DllCall("GetForegroundWindow", "Ptr")
    if foregroundHwnd = gameHwnd
        return true
    ; Keep a visible card through the Win key or taskbar focus handoff.
    ; A game behind another app must first regain focus to show it again.
    if !LoginProgressShown
        return false
    if !foregroundHwnd
        return true
    foreground := "ahk_id " foregroundHwnd
    try
    {
        processName := WinGetProcessName(foreground)
        if processName = "StartMenuExperienceHost.exe" || processName = "ShellExperienceHost.exe"
            return true
        if processName = "explorer.exe"
        {
            className := WinGetClass(foreground)
            return className = "Shell_TrayWnd" || className = "Shell_SecondaryTrayWnd"
        }
    }
    catch Error
        return false ; The foreground window may close while Windows transfers focus.
    return false
}

UpdateGameLoginProgress(*)
{
    global Client, LoginProgressMode, LoginProgressCloseAt
    global LoginProgressDisabled, LoginProgressPid, LoginProgressHwnd
    global LoginProgressHardDeadline
    if LoginProgressMode = ""
    {
        ; A stale native overlay must never survive a completed dismissal.
        HideGameLoginProgress()
        SetTimer(UpdateGameLoginProgress, 0)
        return
    }
    ; If the login never reaches its expected visual-completion callback,
    ; avoid leaving an always-on-top card covering a playable game forever.
    ; Never stop the client or alter credentials from a UI timeout.
    if LoginProgressMode = "login" && LoginProgressHardDeadline
        && A_TickCount >= LoginProgressHardDeadline
    {
        DismissGameLoginProgress()
        LogLauncherEvent("UI | Login progress exceeded its display deadline; game session unchanged.")
        return
    }
    ; Independently monitor the game process so an externally closed TES3MP
    ; console cannot strand its always-on-top login card while ClientTick
    ; gathers any final plugin-mismatch log lines.
    abandoned := (LoginProgressMode = "login" && !Client.Enabled)
        || (LoginProgressMode = "login" && Client.PID && !ProcessExist(Client.PID))
        || (LoginProgressMode = "complete" && LoginProgressPid && !ProcessExist(LoginProgressPid))
    if abandoned
    {
        DisposeGameLoginProgress()
        LogLauncherEvent("UI | Login progress closed after game exit or cancelled recovery.")
        return
    }
    if LoginProgressMode = "complete" && A_TickCount >= LoginProgressCloseAt
    {
        DismissGameLoginProgress()
        return
    }
    if LoginProgressDisabled
        return
    try
    {
        hwnd := LoginProgressMode = "login" ? Client.HWND : LoginProgressHwnd
        pid := LoginProgressMode = "login" ? Client.PID : LoginProgressPid
        if !hwnd || !pid || !ProcessExist(pid) || !DllCall("IsWindowVisible", "Ptr", hwnd)
        {
            HideGameLoginProgress()
            return
        }
        target := "ahk_id " hwnd
        if WinGetPID(target) != pid || !InStr(WinGetClass(target), "SDL")
            || WinGetMinMax(target) = -1 || !CanShowGameLoginProgress(hwnd)
        {
            HideGameLoginProgress()
            return
        }
        layout := GetGameLoginProgressLayout(hwnd)
        if !IsObject(layout)
        {
            HideGameLoginProgress()
            return
        }
        PresentGameLoginProgress(layout)
    }
    catch Error as err
    {
        LoginProgressDisabled := true
        DisposeGameLoginProgress()
        try LogLauncherEvent("UI | Login progress disabled for this session (" Type(err) ").")
    }
}
