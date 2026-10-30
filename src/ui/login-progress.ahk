; Non-activating TES3MP login progress card. ClientTick owns inputs and timing.
global LoginProgressGui := 0
global LoginProgressHeading := 0
global LoginProgressRows := []
global LoginProgressFooter := 0
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
    LoginProgressMode := "login"
    LoginProgressStage := 1
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
    global LoginProgressMode, LoginProgressStage
    if LoginProgressMode != "login"
        return
    LoginProgressStage := stage
    UpdateGameLoginProgress()
}

CompleteGameLoginProgress(name, pid, hwnd)
{
    global LoginProgressMode, LoginProgressStage, LoginProgressName
    global LoginProgressPid, LoginProgressHwnd, LoginProgressCloseAt, AppConfig
    LoginProgressMode := "complete"
    LoginProgressStage := 6
    LoginProgressName := name
    LoginProgressPid := pid
    LoginProgressHwnd := hwnd
    LoginProgressCloseAt := A_TickCount + 5000
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
    LoginProgressMode := ""
    LoginProgressCloseAt := 0
    LoginProgressPid := 0
    LoginProgressHwnd := 0
    HideGameLoginProgress()
}

DisposeGameLoginProgress()
{
    global LoginProgressGui, LoginProgressRows, LoginProgressHeading, LoginProgressFooter
    DismissGameLoginProgress()
    if IsObject(LoginProgressGui)
        try LoginProgressGui.Destroy()
    LoginProgressGui := 0
    LoginProgressRows := []
    LoginProgressHeading := 0
    LoginProgressFooter := 0
}

CreateGameLoginProgress()
{
    global LoginProgressGui, LoginProgressHeading, LoginProgressRows
    global LoginProgressFooter, LoginProgressWidth, LoginProgressHeight
    if IsObject(LoginProgressGui)
        return
    scale := A_ScreenDPI / 96
    p := (value) => Round(value * scale)
    LoginProgressWidth := p(420)
    LoginProgressHeight := p(352)
    ; WS_EX_NOACTIVATE | WS_EX_TRANSPARENT: keep TES3MP input and clicks working.
    window := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x08000020", "tes3np Login Progress")
    window.BackColor := "28241F"
    window.SetFont("s15 Bold cF2E4D0", "Georgia")
    LoginProgressHeading := window.Add("Text", "x" p(20) " y" p(21) " w" p(380) " h" p(38) " Center BackgroundTrans +0x4000", "")
    window.Add("Text", "x" p(27) " y" p(68) " w" p(366) " h" p(2) " Background806B51", "")
    steps := ["Loading Name Screen...", "Typing Name...", "Loading Password Screen...",
        "Typing Password...", "Loading Character..."]
    LoginProgressRows := []
    for index, labelText in steps
    {
        y := p(88 + (index - 1) * 42)
        window.SetFont("s17 cFFFFFF", "Segoe UI Symbol")
        dot := window.Add("Text", "x" p(35) " y" y " w" p(35) " h" p(29) " Center BackgroundTrans", "●")
        window.SetFont("s11 cC8BFB4", "Segoe UI")
        label := window.Add("Text", "x" p(69) " y" y " w" p(305) " h" p(29) " Center BackgroundTrans", labelText)
        LoginProgressRows.Push({Dot: dot, Label: label, DotColor: "", LabelColor: ""})
    }
    window.Add("Text", "x" p(27) " y" p(304) " w" p(366) " h" p(2) " Background806B51", "")
    window.SetFont("s10 Bold cD3B687", "Segoe UI")
    LoginProgressFooter := window.Add("Text", "x" p(24) " y" p(316) " w" p(372) " h" p(25) " Center BackgroundTrans +0x4000", "")
    window.Show("Hide w" LoginProgressWidth " h" LoginProgressHeight)
    LoginProgressGui := window
}

RenderGameLoginProgress()
{
    global LoginProgressGui, LoginProgressHeading, LoginProgressRows, LoginProgressFooter
    global LoginProgressName, LoginProgressMode, LoginProgressStage, Client
    header := "Logging In " LoginProgressName "..."
    dirty := false
    if LoginProgressHeading.Text != header
    {
        LoginProgressHeading.Text := header
        dirty := true
    }
    for index, row in LoginProgressRows
    {
        done := LoginProgressMode = "complete" || index < LoginProgressStage
        typing := LoginProgressMode = "login" && index = LoginProgressStage && (index = 2 || index = 4)
        dotColor := done ? "6EE29B" : typing ? "62AFFF" : "FFFFFF"
        labelColor := done ? "95D5AC" : index = LoginProgressStage ? "F2E4D0" : "C8BFB4"
        if row.DotColor != dotColor
        {
            row.Dot.SetFont("c" dotColor)
            row.DotColor := dotColor
            dirty := true
        }
        if row.LabelColor != labelColor
        {
            row.Label.SetFont("c" labelColor)
            row.LabelColor := labelColor
            dirty := true
        }
    }
    status := LoginProgressMode = "complete" ? "Login Complete!" : Client.HasOwnProp("Status") ? Client.Status : "Preparing game..."
    if LoginProgressFooter.Text != status
    {
        LoginProgressFooter.Text := status
        dirty := true
    }
    ; Force the short-lived blue typing indication to paint before SendText().
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
