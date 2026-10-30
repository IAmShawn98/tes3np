; Non-activating TES3MP login progress card. ClientTick owns inputs and timing.
global LoginProgressGui := 0
global LoginProgressHeading := 0
global LoginProgressRows := []
global LoginProgressFooter := 0
global LoginProgressSeparator := 0
global LoginProgressTopSeparator := 0
global LoginProgressIcon := 0
global LoginProgressSummaryDots := []
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
    global LoginProgressGui, LoginProgressRows, LoginProgressHeading, LoginProgressFooter, LoginProgressSeparator
    global LoginProgressTopSeparator, LoginProgressIcon, LoginProgressSummaryDots
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
    LoginProgressSummaryDots := []
}

CreateGameLoginProgress()
{
    global LoginProgressGui, LoginProgressHeading, LoginProgressRows
    global LoginProgressFooter, LoginProgressSeparator, LoginProgressWidth, LoginProgressHeight
    global LoginProgressTopSeparator, LoginProgressIcon, LoginProgressSummaryDots
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
    LoginProgressTopSeparator := window.Add("Text", "x" p(27) " y" p(68) " w" p(366) " h" p(2) " Background806B51", "")
    ; Center the visible favicon artwork between the title and upper rule.
    ; The ICO has internal transparent margins, so optical center sits above
    ; the raw control-box midpoint. It remains hidden in real logins.
    LoginProgressIcon := window.Add("Picture", "x" p(174) " y" p(60) " w" p(72) " h" p(72)
        " Icon1 Hidden", A_ScriptDir "\assets\icons\tes3np.ico")
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
        LoginProgressRows.Push({Dot: dot, Label: label, BaseText: labelText, DotColor: "", LabelColor: ""})
    }
    LoginProgressSeparator := window.Add("Text", "x" p(27) " y" p(329) " w" p(366) " h" p(2) " Background806B51", "")
    window.SetFont("s10 Bold cD3B687", "Segoe UI")
    LoginProgressFooter := window.Add("Text", "x" p(24) " y" p(343) " w" p(372) " h" p(25) " Center BackgroundTrans +0x4000", "")
    ; Four independent preview-only status dots below the existing gold status.
    ; The active blue circle overlays a bold !, and a finished green circle
    ; overlays a heavy, vertically centered checkmark. Pending dots stay empty.
    LoginProgressSummaryDots := []
    Loop 4
    {
        x := p(135 + (A_Index - 1) * 42)
        window.SetFont("s18 cFFFFFF", "Segoe UI Symbol")
        circle := window.Add("Text", "x" x " y" p(410) " w" p(28) " h" p(27)
            " Center BackgroundTrans +0x4000 Hidden", "●")
        ; SS_CENTERIMAGE (+0x200) centers glyphs vertically rather than
        ; leaving the checkmark above its circle's middle.
        window.SetFont("s15 Bold c173C2A", "Segoe UI Symbol")
        check := window.Add("Text", "x" x " y" p(412) " w" p(28) " h" p(27)
            " Center BackgroundTrans +0x200 Hidden", "✔")
        LoginProgressSummaryDots.Push({Circle: circle, Check: check, Color: "", Symbol: ""})
    }
    window.Show("Hide w" LoginProgressWidth " h" LoginProgressHeight)
    LoginProgressGui := window
}

RenderGameLoginProgress()
{
    global LoginProgressGui, LoginProgressHeading, LoginProgressRows, LoginProgressFooter
    global LoginProgressName, LoginProgressMode, LoginProgressStage, Client
    global LoginProgressSeparator, LoginProgressHeight, LoginProgressPreviewStarted
    global LoginProgressTopSeparator, LoginProgressIcon, LoginProgressSummaryDots
    header := "Logging In " LoginProgressName "..."
    dirty := false
    if LoginProgressHeading.Text != header
    {
        LoginProgressHeading.Text := header
        dirty := true
    }
    preview := LoginProgressMode = "preview"
    isComplete := LoginProgressMode = "complete" || (preview && LoginProgressStage = 6)
    if preview
    {
        ; Only the dev preview expands for the favicon and the lower tracker.
        previewHeight := Round(451 * A_ScreenDPI / 96)
        if LoginProgressHeight != previewHeight
        {
            LoginProgressHeight := previewHeight
            p := (value) => Round(value * A_ScreenDPI / 96)
            LoginProgressTopSeparator.Move(p(27), p(151), p(366), p(2))
            for index, row in LoginProgressRows
            {
                y := p(167 + (index - 1) * 46)
                row.Label.Move(p(30), y, p(360), p(22))
                row.Dot.Move(p(195), y + p(23), p(30), p(21))
            }
            LoginProgressSeparator.Move(p(27), p(361), p(366), p(2))
            LoginProgressFooter.Move(p(24), p(373), p(372), p(25))
            dirty := true
        }
    }
    else
    {
        ; The live five-step login card keeps its original size and layout.
        normalHeight := Round(386 * A_ScreenDPI / 96)
        if LoginProgressHeight != normalHeight
        {
            LoginProgressHeight := normalHeight
            p := (value) => Round(value * A_ScreenDPI / 96)
            LoginProgressTopSeparator.Move(p(27), p(68), p(366), p(2))
            for index, row in LoginProgressRows
            {
                y := p(86 + (index - 1) * 46)
                row.Label.Move(p(30), y, p(360), p(22))
                row.Dot.Move(p(195), y + p(23), p(30), p(21))
            }
            LoginProgressSeparator.Move(p(27), p(329), p(366), p(2))
            LoginProgressFooter.Move(p(24), p(343), p(372), p(25))
            dirty := true
        }
    }
    if LoginProgressIcon.Visible != preview
    {
        LoginProgressIcon.Visible := preview
        dirty := true
    }
    for index, row in LoginProgressRows
    {
        shouldShow := !preview || index <= 4
        if row.Label.Visible != shouldShow
        {
            row.Label.Visible := shouldShow
            row.Dot.Visible := shouldShow
            dirty := true
        }
        done := isComplete || index < LoginProgressStage
        if preview && shouldShow
        {
            if done
                ending := "!"
            else if index = LoginProgressStage
            {
                ; Cycle one, two and three dots until the stage turns green.
                startAt := index = 1 ? 0 : index = 2 ? 1500 : index = 3 ? 2500 : 4000
                phaseElapsed := Max(0, A_TickCount - LoginProgressPreviewStarted - startAt)
                ending := SubStr("...", 1, 1 + Mod(Floor(phaseElapsed / 350), 3))
            }
            else
                ending := "..."
            labelText := RTrim(row.BaseText, ".") ending
        }
        else
            labelText := row.BaseText
        if row.Label.Text != labelText
        {
            row.Label.Text := labelText
            dirty := true
        }
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
    ; The four bottom dots mirror the step state, independently from the
    ; label-level dots. White = pending, blue = active, green/check = finished.
    for index, marker in LoginProgressSummaryDots
    {
        if marker.Circle.Visible != preview
        {
            marker.Circle.Visible := preview
            dirty := true
        }
        if !preview
        {
            if marker.Check.Visible
            {
                marker.Check.Visible := false
                dirty := true
            }
            continue
        }
        finished := isComplete || index < LoginProgressStage
        active := !finished && index = LoginProgressStage
        color := finished ? "6EE29B" : active ? "62AFFF" : "FFFFFF"
        if marker.Color != color
        {
            marker.Circle.SetFont("c" color)
            marker.Color := color
            dirty := true
        }
        symbol := finished ? "✔" : active ? "!" : ""
        if marker.Symbol != symbol
        {
            marker.Check.Text := symbol
            if symbol = "✔"
                marker.Check.SetFont("s15 Bold c173C2A", "Segoe UI Symbol")
            else if symbol = "!"
                marker.Check.SetFont("s17 Bold c173C2A", "Segoe UI")
            marker.Symbol := symbol
            dirty := true
        }
        showSymbol := symbol != ""
        if marker.Check.Visible != showSymbol
        {
            marker.Check.Visible := showSymbol
            dirty := true
        }
    }
    if isComplete
        status := "Login Complete!"
    else if preview
        status := ["Loading name screen...", "Typing name...", "Loading password screen...",
            "Typing password..."][LoginProgressStage]
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
        if elapsed >= 8000
        {
            DismissGameLoginProgress()
            if !Client.Enabled
                SetTimer(UpdateGameLoginProgress, 0)
            return
        }
        ; Finish immediately after password typing and show success for 3s.
        LoginProgressStage := elapsed < 1500 ? 1 : elapsed < 2500 ? 2
            : elapsed < 4000 ? 3 : elapsed < 5000 ? 4 : 6
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
