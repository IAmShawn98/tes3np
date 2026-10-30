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
global LoginProgressPreviewStarted := 0
global LoginProgressPreviewOwner := 0

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
    global LoginProgressPreviewStarted, LoginProgressPreviewOwner
    LoginProgressMode := ""
    LoginProgressPreviewStarted := 0
    LoginProgressPreviewOwner := 0
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
    LoginProgressHeight := p(386)
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
        ; A centered label followed by its dot one line below.
        y := p(86 + (index - 1) * 46)
        window.SetFont("s11 cC8BFB4", "Segoe UI")
        label := window.Add("Text", "x" p(30) " y" y " w" p(360) " h" p(22) " Center BackgroundTrans", labelText)
        window.SetFont("s13 cFFFFFF", "Segoe UI Symbol")
        dot := window.Add("Text", "x" p(195) " y" (y + p(23)) " w" p(30) " h" p(21) " Center BackgroundTrans", "●")
        LoginProgressRows.Push({Dot: dot, Label: label, DotColor: "", LabelColor: ""})
    }
    window.Add("Text", "x" p(27) " y" p(329) " w" p(366) " h" p(2) " Background806B51", "")
    window.SetFont("s10 Bold cD3B687", "Segoe UI")
    LoginProgressFooter := window.Add("Text", "x" p(24) " y" p(343) " w" p(372) " h" p(25) " Center BackgroundTrans +0x4000", "")
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
    isComplete := LoginProgressMode = "complete" || (LoginProgressMode = "preview" && LoginProgressStage = 6)
    for index, row in LoginProgressRows
    {
        done := isComplete || index < LoginProgressStage
        typing := (LoginProgressMode = "login" || LoginProgressMode = "preview") && index = LoginProgressStage && (index = 2 || index = 4)
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
    if isComplete
        status := "Login Complete!"
    else if LoginProgressMode = "preview"
        status := ["Loading name screen...", "Typing name...", "Loading password screen...",
            "Typing password...", "Loading character..."][LoginProgressStage]
    else
        status := Client.HasOwnProp("Status") ? Client.Status : "Preparing game..."
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
    global LoginProgressWidth, LoginProgressHeight, LoginProgressStage
    global LoginProgressPreviewStarted, LoginProgressPreviewOwner
    if LoginProgressMode = ""
        return
    ; The dev preview changes only presentation state, not the game controller.
    if LoginProgressMode = "preview"
    {
        elapsed := A_TickCount - LoginProgressPreviewStarted
        if elapsed >= 9500
        {
            DismissGameLoginProgress()
            if !Client.Enabled
                SetTimer(UpdateGameLoginProgress, 0)
            return
        }
        LoginProgressStage := elapsed < 1500 ? 1 : elapsed < 2500 ? 2
            : elapsed < 4000 ? 3 : elapsed < 5000 ? 4
            : elapsed < 6500 ? 5 : 6
    }
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
        if LoginProgressMode = "preview"
        {
            hwnd := LoginProgressPreviewOwner
            if !hwnd || !DllCall("IsWindow", "Ptr", hwnd)
            {
                DismissGameLoginProgress()
                SetTimer(UpdateGameLoginProgress, 0)
                return
            }
            target := "ahk_id " hwnd
            if !WinActive(target) || WinGetMinMax(target) = -1
            {
                HideGameLoginProgress()
                return
            }
        }
        else
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
        if LoginProgressMode = "preview"
        {
            DismissGameLoginProgress()
            SetTimer(UpdateGameLoginProgress, 0)
        }
    }
}

; No TES3MP launch, password access, profile writes or simulated ClientTick.
PreviewGameLoginProgress(*)
{
    global Client, CharacterPage, Profiles, SelectedProfile
    global LoginProgressMode, LoginProgressStage, LoginProgressName
    global LoginProgressDisabled, LoginProgressPreviewOwner, LoginProgressPreviewStarted
    if Client.Enabled || !IsObject(CharacterPage) || !DllCall("IsWindow", "Ptr", CharacterPage.Hwnd)
        return
    SetTimer(UpdateGameLoginProgress, 0)
    DismissGameLoginProgress()
    previewIndex := SelectedProfile >= 1 && SelectedProfile <= Profiles.Length ? SelectedProfile : 1
    LoginProgressName := Profiles.Length ? Profiles[previewIndex].Name : "Test Character"
    LoginProgressMode := "preview"
    LoginProgressStage := 1
    LoginProgressDisabled := false
    LoginProgressPreviewOwner := CharacterPage.Hwnd
    LoginProgressPreviewStarted := A_TickCount
    SetTimer(UpdateGameLoginProgress, 100)
    UpdateGameLoginProgress()
}

CancelGameLoginProgressPreview()
{
    global LoginProgressMode
    if LoginProgressMode != "preview"
        return
    DismissGameLoginProgress()
    SetTimer(UpdateGameLoginProgress, 0)
}
