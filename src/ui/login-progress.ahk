; Non-activating TES3MP login progress card. ClientTick owns inputs and timing.
global LoginProgressGui := 0
global LoginProgressHeading := 0
global LoginProgressRows := []
global LoginProgressFooter := 0
global LoginProgressSeparator := 0
global LoginProgressTopSeparator := 0
global LoginProgressIcon := 0
global LoginProgressCharacterName := 0
global LoginProgressBorder := []
global LoginProgressSummaryDots := []
global LoginProgressStageStarted := 0
global LoginProgressFinished := false
global LoginProgressWidth := 0
global LoginProgressHeight := 0
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

BeginGameLoginProgress(name)
{
    global LoginProgressMode, LoginProgressStage, LoginProgressName
    global LoginProgressPid, LoginProgressHwnd, LoginProgressCloseAt, LoginProgressDisabled
    global LoginProgressStageStarted, LoginProgressFinished
    LoginProgressMode := "login"
    LoginProgressStage := 1
    LoginProgressStageStarted := A_TickCount
    LoginProgressFinished := false
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
    if LoginProgressMode != "login" || stage < 1 || stage > 4
        return
    if LoginProgressStage != stage
    {
        LoginProgressStage := stage
        LoginProgressStageStarted := A_TickCount
    }
    UpdateGameLoginProgress()
}

CompleteGameLoginProgress(name, pid, hwnd)
{
    global LoginProgressMode, LoginProgressStage, LoginProgressName
    global LoginProgressPid, LoginProgressHwnd, LoginProgressCloseAt, AppConfig, LoginProgressFinished
    if LoginProgressFinished
        return
    LoginProgressFinished := true
    LoginProgressMode := "complete"
    LoginProgressStage := 5
    LoginProgressName := name
    LoginProgressPid := pid
    LoginProgressHwnd := hwnd
    LoginProgressCloseAt := A_TickCount + 3000
    ; Continue only the existing presentation timer, never the game watchdog.
    SetTimer(UpdateGameLoginProgress, AppConfig.TooltipMs)
    UpdateGameLoginProgress()
}

HideGameLoginProgress()
{
    global LoginProgressGui, LoginProgressShown, LoginProgressLastX, LoginProgressLastY
    if IsObject(LoginProgressGui) && LoginProgressShown
        try LoginProgressGui.Hide()
    LoginProgressShown := false
    LoginProgressLastX := -1
    LoginProgressLastY := -1
}

DismissGameLoginProgress()
{
    global LoginProgressMode, LoginProgressCloseAt, LoginProgressPid, LoginProgressHwnd
    ; Do not clear LoginProgressFinished: the real game load delay
    ; can elapse after the three-second visual has already closed.
    LoginProgressMode := ""
    LoginProgressCloseAt := 0
    LoginProgressPid := 0
    LoginProgressHwnd := 0
    HideGameLoginProgress()
}

DisposeGameLoginProgress()
{
    global LoginProgressGui, LoginProgressRows, LoginProgressHeading, LoginProgressFooter, LoginProgressSeparator
    global LoginProgressTopSeparator, LoginProgressIcon, LoginProgressSummaryDots
    global LoginProgressCharacterName, LoginProgressBorder
    DismissGameLoginProgress()
    if IsObject(LoginProgressGui)
        try LoginProgressGui.Destroy()
    LoginProgressGui := 0
    LoginProgressRows := []
    LoginProgressHeading := 0
    LoginProgressFooter := 0
    LoginProgressSeparator := 0
    LoginProgressTopSeparator := 0
    LoginProgressIcon := 0
    LoginProgressCharacterName := 0
    LoginProgressBorder := []
    LoginProgressSummaryDots := []
}

CreateGameLoginProgress()
{
    global LoginProgressGui, LoginProgressHeading, LoginProgressRows
    global LoginProgressFooter, LoginProgressWidth, LoginProgressHeight
    global LoginProgressIcon, LoginProgressCharacterName, LoginProgressSummaryDots
    if IsObject(LoginProgressGui)
        return
    scale := A_ScreenDPI / 96
    p := (value) => Round(value * scale)
    LoginProgressWidth := p(420)
    LoginProgressHeight := p(481)
    ; Nonactivating, click-through window: preserve TES3MP mouse and keyboard.
    window := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x08000020", "tes3np Login Progress")
    window.BackColor := "28241F"

    ; Four 4px gold strips are always visible in the production card.
    ; They are inset, so none are clipped by the native client bounds.
    for line in [[0, 0, 420, 4], [0, 477, 420, 4], [0, 0, 4, 481], [416, 0, 4, 481]]
        window.Add("Text", "x" p(line[1]) " y" p(line[2])
            " w" p(line[3]) " h" p(line[4]) " BackgroundD1AE67", "")
    window.SetFont("s15 Bold cF2E4D0", "Georgia")
    LoginProgressHeading := window.Add("Text", "x" p(20) " y" p(21) " w" p(380)
        " h" p(38) " Center BackgroundTrans +0x4000", "Logging in...")
    LoginProgressIcon := window.Add("Picture", "x" p(174) " y" p(60) " w" p(72)
        " h" p(72) " Icon1", A_ScriptDir "\assets\icons\tes3np.ico")
    window.SetFont("s13 Bold cF2E4D0", "Georgia")
    LoginProgressCharacterName := window.Add("Text", "x" p(24) " y" p(143)
        " w" p(372) " h" p(30) " Center BackgroundTrans", "")
    window.Add("Text", "x" p(27) " y" p(181) " w" p(366) " h" p(2) " Background806B51", "")
    steps := ["Loading Name Screen...", "Typing Name...",
        "Loading Password Screen...", "Typing Password..."]
    LoginProgressRows := []
    for index, labelText in steps
    {
        y := p(197 + (index - 1) * 46)
        window.SetFont("s11 cC8BFB4", "Segoe UI")
        label := window.Add("Text", "x" p(30) " y" y " w" p(360)
            " h" p(22) " Center BackgroundTrans", labelText)
        window.SetFont("s13 cFFFFFF", "Segoe UI Symbol")
        dot := window.Add("Text", "x" p(195) " y" (y + p(23))
            " w" p(30) " h" p(21) " Center BackgroundTrans", "●")
        window.SetFont("s12 Bold c173C2A", "Segoe UI Symbol")
        symbol := window.Add("Text", "x" p(195) " y" (y + p(23))
            " w" p(30) " h" p(21) " Center BackgroundTrans +0x200 Hidden", "✔")
        LoginProgressRows.Push({Dot: dot, Label: label, Symbol: symbol,
            BaseText: labelText, SymbolText: "", DotColor: "", LabelColor: ""})
    }
    window.Add("Text", "x" p(27) " y" p(391) " w" p(366) " h" p(2) " Background806B51", "")
    window.SetFont("s10 Bold cD3B687", "Segoe UI")
    LoginProgressFooter := window.Add("Text", "x" p(24) " y" p(403)
        " w" p(372) " h" p(25) " Center BackgroundTrans +0x4000", "")
    LoginProgressSummaryDots := []
    Loop 4
    {
        x := p(135 + (A_Index - 1) * 42)
        window.SetFont("s18 cFFFFFF", "Segoe UI Symbol")
        circle := window.Add("Text", "x" x " y" p(440)
            " w" p(28) " h" p(27) " Center BackgroundTrans +0x4000", "●")
        window.SetFont("s15 Bold c173C2A", "Segoe UI Symbol")
        symbol := window.Add("Text", "x" x " y" p(442)
            " w" p(28) " h" p(27) " Center BackgroundTrans +0x200 Hidden", "✔")
        LoginProgressSummaryDots.Push({Circle: circle, Symbol: symbol, Color: "", SymbolText: ""})
    }
    window.Show("Hide w" LoginProgressWidth " h" LoginProgressHeight)
    LoginProgressGui := window
}

RenderGameLoginProgress()
{
    global LoginProgressGui, LoginProgressCharacterName, LoginProgressRows
    global LoginProgressFooter, LoginProgressSummaryDots, LoginProgressName
    global LoginProgressMode, LoginProgressStage, LoginProgressStageStarted
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
                row.Symbol.SetFont("s12 Bold c173C2A", "Segoe UI Symbol")
            else if symbol = "!"
                row.Symbol.SetFont("s14 Bold c173C2A", "Segoe UI")
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
                marker.Symbol.SetFont("s15 Bold c173C2A", "Segoe UI Symbol")
            else if symbol = "!"
                marker.Symbol.SetFont("s17 Bold c173C2A", "Segoe UI")
            marker.SymbolText := symbol
            dirty := true
        }
        if marker.Symbol.Visible != (symbol != "")
        {
            marker.Symbol.Visible := symbol != ""
            dirty := true
        }
    }
    status := complete ? "Login Complete!" :
        ["Loading name screen...", "Typing name...",
            "Loading password screen...", "Typing password..."][stage]
    if LoginProgressFooter.Text != status
    {
        LoginProgressFooter.Text := status
        dirty := true
    }
    if dirty
        DllCall("RedrawWindow", "Ptr", LoginProgressGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x105)
}

UpdateGameLoginProgress(*)
{
    global Client, LoginProgressMode, LoginProgressCloseAt, LoginProgressGui
    global LoginProgressDisabled, LoginProgressPid, LoginProgressHwnd
    global LoginProgressShown, LoginProgressLastX, LoginProgressLastY
    global LoginProgressWidth, LoginProgressHeight
    if LoginProgressMode = ""
        return
    if LoginProgressMode = "complete" && A_TickCount >= LoginProgressCloseAt
    {
        DismissGameLoginProgress()
        if !Client.Enabled
            SetTimer(UpdateGameLoginProgress, 0)
        return
    }
    if LoginProgressDisabled
        return
    try
    {
        hwnd := LoginProgressMode = "login" ? Client.HWND : LoginProgressHwnd
        pid := LoginProgressMode = "login" ? Client.PID : LoginProgressPid
        if !hwnd || !pid || !ProcessExist(pid) || !DllCall("IsWindow", "Ptr", hwnd)
        {
            HideGameLoginProgress()
            return
        }
        target := "ahk_id " hwnd
        if WinGetPID(target) != pid || !InStr(WinGetClass(target), "SDL")
            || WinGetMinMax(target) = -1 || !WinActive(target)
        {
            HideGameLoginProgress()
            return
        }
        CreateGameLoginProgress()
        RenderGameLoginProgress()
        WinGetPos(&gx, &gy, &gw, &gh, target)
        x := gx + Round((gw - LoginProgressWidth) / 2)
        y := gy + Round((gh - LoginProgressHeight) / 2)
        if !LoginProgressShown
        {
            LoginProgressGui.Show("NA x" x " y" y " w" LoginProgressWidth " h" LoginProgressHeight)
            LoginProgressShown := true
        }
        else if x != LoginProgressLastX || y != LoginProgressLastY
            DllCall("SetWindowPos", "Ptr", LoginProgressGui.Hwnd, "Ptr", 0,
                "Int", x, "Int", y, "Int", 0, "Int", 0, "UInt", 0x15)
        LoginProgressLastX := x
        LoginProgressLastY := y
    }
    catch Error as err
    {
        LoginProgressDisabled := true
        HideGameLoginProgress()
        try LogLauncherEvent("UI | Login progress disabled for this session: " err.Message ".")
    }
}
