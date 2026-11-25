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
global LoginProgressTracking := 0
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
    global LoginProgressGui, LoginProgressShown
    LoginProgressShown := false
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
}

DismissGameLoginProgress()
{
    global LoginProgressMode, LoginProgressCloseAt, LoginProgressPid, LoginProgressHwnd
    SetTimer(UpdateGameLoginProgress, 0)
    LoginProgressMode := ""
    LoginProgressCloseAt := 0
    LoginProgressPid := 0
    LoginProgressHwnd := 0
    StopGameLoginProgressTracking()
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
    ; independently from the bundled race ICOs. Missing files fall back.
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

GetGameLoginProgressWindow(hwnd)
{
    WinGetPos(&x, &y, &width, &height, "ahk_id " hwnd)
    return {X: x, Y: y, Width: width, Height: height}
}

GetGameLoginProgressLayout(hwnd, gameWindow)
{
    WinGetClientPos(&x, &y, &width, &height, "ahk_id " hwnd)
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
    global AccessibilityTextSize, LoginProgressName
    layout := FitGameLoginProgress({X: x, Y: y, Width: width, Height: height}, gameWindow, A_ScreenDPI / 96)
    if IsObject(layout) && AccessibilityTextSize != "Normal"
        layout := FitAccessibleGameLoginProgress({X: x, Y: y, Width: width, Height: height},
            gameWindow, A_ScreenDPI / 96, LoginProgressName)
    if IsObject(layout)
        layout.GameWindow := gameWindow
    return layout
}

TranslateGameLoginProgress(layout, gameWindow)
{
    anchor := layout.GameWindow
    if gameWindow.Width != anchor.Width || gameWindow.Height != anchor.Height
        return 0
    translated := layout.Clone()
    translated.X := gameWindow.X + (layout.X - anchor.X)
    translated.Y := gameWindow.Y + (layout.Y - anchor.Y)
    translated.GameWindow := gameWindow
    return translated
}

TrackGameLoginProgressWindow(hwnd)
{
    global LoginProgressTracking
    static callback := 0
    if IsObject(LoginProgressTracking) && LoginProgressTracking.Hwnd = hwnd
        return
    StopGameLoginProgressTracking()
    pid := 0
    threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid, "UInt")
    if !threadId || !pid
        return
    tracking := {Hwnd: hwnd, ThreadId: threadId, Hook: 0}
    LoginProgressTracking := tracking
    try
    {
        ; One callback for the lifetime of the launcher. Only the validated
        ; game's thread is subscribed, and the hook runs in our message loop.
        if !callback
            callback := CallbackCreate(OnGameLoginProgressLocationChange)
        locationChange := 0x800B ; EVENT_OBJECT_LOCATIONCHANGE
        tracking.Hook := DllCall("SetWinEventHook", "UInt", locationChange, "UInt", locationChange,
            "Ptr", 0, "Ptr", callback, "UInt", pid, "UInt", threadId, "UInt", 0, "Ptr") ; WINEVENT_OUTOFCONTEXT
    }
}

StopGameLoginProgressTracking()
{
    global LoginProgressTracking
    tracking := LoginProgressTracking
    LoginProgressTracking := 0
    if IsObject(tracking) && tracking.Hook
        DllCall("UnhookWinEvent", "Ptr", tracking.Hook, "Int")
}

GameLoginProgressIsDragging(tracking, hwnd)
{
    if !IsObject(tracking) || tracking.Hwnd != hwnd
        return false
    info := Buffer(8 + 6 * A_PtrSize + 16, 0) ; GUITHREADINFO
    NumPut("UInt", info.Size, info)
    return DllCall("GetGUIThreadInfo", "UInt", tracking.ThreadId, "Ptr", info, "Int")
        && (NumGet(info, 4, "UInt") & 0x2) && NumGet(info, 8 + 4 * A_PtrSize, "Ptr") = hwnd
}

OnGameLoginProgressLocationChange(hook, event, hwnd, objectId, childId, threadId, eventTime)
{
    Critical("On")
    global LoginProgressTracking, LoginProgressShown, LoginProgressGui
    tracking := LoginProgressTracking
    if !LoginProgressShown || !IsObject(tracking) || tracking.Hook != hook
        || event != 0x800B || tracking.Hwnd != hwnd || objectId || childId
        || DllCall("IsIconic", "Ptr", hwnd) || !DllCall("IsWindowVisible", "Ptr", hwnd)
        return
    ; Read the current rectangle even if several move events were queued.
    ; The fast path keeps the painted card and its original game offset.
    try
    {
        previous := LoginProgressGui.ProgressLayout
        layout := TranslateGameLoginProgress(previous, GetGameLoginProgressWindow(hwnd))
        if IsObject(layout) && (layout.X != previous.X || layout.Y != previous.Y)
            && PositionGameLoginProgress(LoginProgressGui.Hwnd, hwnd, layout, false, true)
            LoginProgressGui.ProgressLayout := layout
    }
}

GameLoginProgressFontSize(points, scale)
{
    normalScale := A_ScreenDPI / 96
    return scale >= normalScale ? points : Max(1, Floor(points * scale / normalScale))
}

; Measure the same fonts used by the production card in physical pixels.
; Reserve both the circle and either overlaid symbol, including the larger
; active exclamation mark. The complete stack is planned before first paint.
MeasureGameLoginProgressPlan(scale, name)
{
    p := (value) => Max(1, Round(value * scale))
    panel := Gui("-DPIScale")
    try
    {
        sample := panel.Add("Text", "x0 y0 w1 h1", "")
        font := (points, style, family) => SetAccessibleTextFont(sample,
            "s" GameLoginProgressFontSize(points, scale) " " style, family)
        width := p(420)
        font(15, "Bold", LauncherThemeFont())
        titleH := Max(p(38), MeasureAccessibleWrappedText(sample, "Logging in...", p(380)) + p(4))
        font(13, "Bold", LauncherThemeFont())
        nameDisplay := PrepareAccessibleBookName(sample, name, Max(1, p(372) - p(8)))
        nameH := Max(p(30), MeasureAccessibleWrappedText(sample, nameDisplay, Max(1, p(372) - p(4))) + p(4))
        font(11, "Norm", LauncherThemeFont())
        labelH := p(22)
        for caption in ["Loading Name Screen...", "Typing Name...", "Loading Password Screen...", "Typing Password..."]
            labelH := Max(labelH, MeasureAccessibleWrappedText(sample, caption, p(360)) + p(4))
        font(13, "Norm", "Segoe UI Symbol")
        dot := MeasureAccessibleSingleLineText(sample, "●")
        font(12, "Bold", "Segoe UI Symbol")
        check := MeasureAccessibleSingleLineText(sample, "✔")
        font(14, "Bold", LauncherThemeFont())
        active := MeasureAccessibleSingleLineText(sample, "!")
        dotW := Max(p(30), Max(dot.Width, check.Width, active.Width) + p(6))
        dotH := Max(p(21), Max(dot.Height, check.Height, active.Height) + p(6))
        font(10, "Bold", LauncherThemeFont())
        footerH := p(25)
        for caption in ["Loading name screen...", "Typing name...", "Loading password screen...", "Typing password...", "Login Complete!"]
            footerH := Max(footerH, MeasureAccessibleWrappedText(sample, caption, p(372)) + p(4))
        font(18, "Norm", "Segoe UI Symbol")
        circle := MeasureAccessibleSingleLineText(sample, "●")
        font(15, "Bold", "Segoe UI Symbol")
        check := MeasureAccessibleSingleLineText(sample, "✔")
        font(17, "Bold", LauncherThemeFont())
        active := MeasureAccessibleSingleLineText(sample, "!")
        summaryW := Max(p(28), Max(circle.Width, check.Width, active.Width) + p(6))
        summaryH := Max(p(27), Max(circle.Height, check.Height, active.Height) + p(6))
        summaryPitch := Max(p(42), summaryW + p(10))
        portraitY := p(21) + titleH + p(4)
        nameY := portraitY + p(72) + p(11)
        topLineY := nameY + nameH + p(8)
        rows := [], y := topLineY + p(16)
        Loop 4
        {
            dotY := y + labelH + p(1)
            rows.Push({LabelY: y, LabelH: labelH, DotY: dotY, DotW: dotW, DotH: dotH})
            y := dotY + dotH + p(4)
        }
        bottomLineY := y + p(5)
        footerY := bottomLineY + p(12)
        summaryY := footerY + footerH + p(12)
        height := Max(p(481), summaryY + summaryH + p(14))
        return {Width: width, Height: height, TitleH: titleH, PortraitY: portraitY,
            NameY: nameY, NameH: nameH, NameDisplay: nameDisplay, TopLineY: topLineY,
            Rows: rows, BottomLineY: bottomLineY, FooterY: footerY, FooterH: footerH,
            SummaryY: summaryY, SummaryW: summaryW, SummaryH: summaryH, SummaryPitch: summaryPitch}
    }
    finally panel.Destroy()
}

FitAccessibleGameLoginProgress(area, gameWindow, normalScale, name)
{
    global AccessibilityTextSize
    ; The timer and game movement must not repeatedly create measurement
    ; windows. Cache the geometry, not the absolute screen position.
    static cached := 0
    if area.Width < 1 || area.Height < 1
        return 0
    if !IsObject(cached) || cached.W != area.Width || cached.H != area.Height
        || cached.Dpi != normalScale || cached.Mode != AccessibilityTextSize || !(cached.Name == name)
    {
        scale := Min(normalScale, area.Width / 420, area.Height / 481)
        plan := 0
        Loop 12
        {
            plan := MeasureGameLoginProgressPlan(scale, name)
            if plan.Width <= area.Width && plan.Height <= area.Height
                break
            scale *= Min(0.97, area.Width / plan.Width, area.Height / plan.Height)
        }
        if !IsObject(plan) || plan.Width > area.Width || plan.Height > area.Height
            return 0
        cached := {W: area.Width, H: area.Height, Dpi: normalScale,
            Mode: AccessibilityTextSize, Name: name, Scale: scale, Plan: plan}
    }
    plan := cached.Plan, scale := cached.Scale
    anchor := scale < normalScale ? area : gameWindow
    x := anchor.X + Round((anchor.Width - plan.Width) / 2)
    y := anchor.Y + Round((anchor.Height - plan.Height) / 2)
    return {Scale: scale, Width: plan.Width, Height: plan.Height, Plan: plan,
        X: Max(area.X, Min(area.X + area.Width - plan.Width, x)),
        Y: Max(area.Y, Min(area.Y + area.Height - plan.Height, y))}
}

CreateGameLoginProgress(layout)
{
    global LoginProgressGui, LoginProgressRows
    global LoginProgressFooter
    global LoginProgressCharacterName, LoginProgressSummaryDots, LoginProgressSpecies, LoginProgressPortraitFile
    p := (value) => Round(value * layout.Scale)
    fontSize := (points) => GameLoginProgressFontSize(points, layout.Scale)
    ; Nonactivating, click-through window: preserve TES3MP mouse and keyboard.
    window := Gui("-Caption +ToolWindow -DPIScale +E0x08000020", "tes3np Login Progress")
    ; Register the window before adding controls so partial setup is disposable.
    LoginProgressGui := window
    window.ProgressScale := layout.Scale
    plan := layout.HasOwnProp("Plan") ? layout.Plan : 0
    enlarged := IsObject(plan)
    window.ProgressPlan := plan
    window.BackColor := "28241F"

    ; Four 4px gold strips are always visible in the production card.
    ; They are inset, so none are clipped by the native client bounds.
    border := Max(1, p(4))
    for line in [[0, 0, layout.Width, border], [0, layout.Height - border, layout.Width, border],
        [0, 0, border, layout.Height], [layout.Width - border, 0, border, layout.Height]]
        window.Add("Text", "x" line[1] " y" line[2]
            " w" line[3] " h" line[4] " BackgroundD1AE67", "")
    SetAccessibleTextFont(window, "s" fontSize(15) " Bold cF2E4D0", LauncherThemeFont())
    ; SS_CENTER already wraps. Explicit +Wrap selects the left-aligned static type.
    window.ProgressTitle := window.Add("Text", "x" p(20) " y" p(21) " w" p(380)
        " h" (enlarged ? plan.TitleH : p(38)) " Center BackgroundTrans" (enlarged ? "" : " +0x4000"), "Logging in...")
    portraitPath := GetCharacterLoginIconPath(LoginProgressSpecies, LoginProgressPortraitFile)
    pictureOptions := "x" p(174) " y" (enlarged ? plan.PortraitY : p(60)) " w" p(72) " h" p(72)
    ; Icon1 applies to ICO resources, but not to custom PNG/JPG/BMP portraits.
    if RegExMatch(portraitPath, "i)\.ico$")
        pictureOptions .= " Icon1"
    window.ProgressPortrait := window.Add("Picture", pictureOptions, portraitPath)
    SetAccessibleTextFont(window, "s" fontSize(13) " Bold cF2E4D0", LauncherThemeFont())
    LoginProgressCharacterName := window.Add("Text", "x" p(24) " y" (enlarged ? plan.NameY : p(143))
        " w" p(372) " h" (enlarged ? plan.NameH : p(30)) " Center BackgroundTrans", "")
    window.ProgressTopLine := window.Add("Text", "x" p(27) " y" (enlarged ? plan.TopLineY : p(181)) " w" p(366) " h" p(2) " Background806B51", "")
    steps := ["Loading Name Screen...", "Typing Name...",
        "Loading Password Screen...", "Typing Password..."]
    LoginProgressRows := []
    for index, labelText in steps
    {
        y := enlarged ? plan.Rows[index].LabelY : p(197 + (index - 1) * 46)
        labelH := enlarged ? plan.Rows[index].LabelH : p(22)
        dotY := enlarged ? plan.Rows[index].DotY : y + p(23)
        dotW := enlarged ? plan.Rows[index].DotW : p(30)
        dotH := enlarged ? plan.Rows[index].DotH : p(21)
        dotX := enlarged ? Round((layout.Width - dotW) / 2) : p(195)
        SetAccessibleTextFont(window, "s" fontSize(11) " cC8BFB4", LauncherThemeFont())
        label := window.Add("Text", "x" p(30) " y" y " w" p(360)
            " h" labelH " Center BackgroundTrans", labelText)
        SetAccessibleTextFont(window, "s" fontSize(13) " cFFFFFF", "Segoe UI Symbol")
        dot := window.Add("Text", "x" dotX " y" dotY
            " w" dotW " h" dotH " Center BackgroundTrans" (enlarged ? " +0x200" : ""), "●")
        SetAccessibleTextFont(window, "s" fontSize(12) " Bold c173C2A", "Segoe UI Symbol")
        symbol := window.Add("Text", "x" dotX " y" dotY
            " w" dotW " h" dotH " Center BackgroundTrans +0x200 Hidden", "✔")
        LoginProgressRows.Push({Dot: dot, Label: label, Symbol: symbol,
            BaseText: labelText, SymbolText: "", DotColor: "", LabelColor: ""})
    }
    window.ProgressBottomLine := window.Add("Text", "x" p(27) " y" (enlarged ? plan.BottomLineY : p(391)) " w" p(366) " h" p(2) " Background806B51", "")
    SetAccessibleTextFont(window, "s" fontSize(10) " Bold cD3B687", LauncherThemeFont())
    LoginProgressFooter := window.Add("Text", "x" p(24) " y" (enlarged ? plan.FooterY : p(403))
        " w" p(372) " h" (enlarged ? plan.FooterH : p(25)) " Center BackgroundTrans" (enlarged ? "" : " +0x4000"), "")
    LoginProgressSummaryDots := []
    Loop 4
    {
        x := enlarged ? Round((layout.Width - plan.SummaryW - 3 * plan.SummaryPitch) / 2) + (A_Index - 1) * plan.SummaryPitch : p(135 + (A_Index - 1) * 42)
        summaryY := enlarged ? plan.SummaryY : p(440)
        summaryW := enlarged ? plan.SummaryW : p(28)
        summaryH := enlarged ? plan.SummaryH : p(27)
        SetAccessibleTextFont(window, "s" fontSize(18) " cFFFFFF", "Segoe UI Symbol")
        circle := window.Add("Text", "x" x " y" summaryY
            " w" summaryW " h" summaryH " Center BackgroundTrans" (enlarged ? " +0x200" : " +0x4000"), "●")
        SetAccessibleTextFont(window, "s" fontSize(15) " Bold c173C2A", "Segoe UI Symbol")
        symbol := window.Add("Text", "x" x " y" (enlarged ? summaryY : p(442))
            " w" summaryW " h" summaryH " Center BackgroundTrans +0x200 Hidden", "✔")
        LoginProgressSummaryDots.Push({Circle: circle, Symbol: symbol, Color: "", SymbolText: ""})
    }
    window.Show("Hide x" layout.X " y" layout.Y " w" layout.Width " h" layout.Height)
}

RenderGameLoginProgress()
{
    global LoginProgressGui, LoginProgressCharacterName, LoginProgressRows
    global LoginProgressFooter, LoginProgressSummaryDots, LoginProgressName
    global LoginProgressMode, LoginProgressStage, LoginProgressStageStarted
    scale := LoginProgressGui.ProgressScale
    dirty := false
    displayName := IsObject(LoginProgressGui.ProgressPlan) ? LoginProgressGui.ProgressPlan.NameDisplay : LoginProgressName
    if LoginProgressCharacterName.Text != displayName
    {
        LoginProgressCharacterName.Text := displayName
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
            SetAccessibleTextFont(row.Dot, "c" color)
            row.DotColor := color
            dirty := true
        }
        if row.LabelColor != labelColor
        {
            SetAccessibleTextFont(row.Label, "c" labelColor)
            row.LabelColor := labelColor
            dirty := true
        }
        symbol := finished ? "✔" : active ? "!" : ""
        if row.SymbolText != symbol
        {
            row.Symbol.Text := symbol
            if symbol = "✔"
                SetAccessibleTextFont(row.Symbol, "s" GameLoginProgressFontSize(12, scale) " Bold c173C2A", "Segoe UI Symbol")
            else if symbol = "!"
                SetAccessibleTextFont(row.Symbol, "s" GameLoginProgressFontSize(14, scale) " Bold c173C2A", LauncherThemeFont())
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
            SetAccessibleTextFont(marker.Circle, "c" color)
            marker.Color := color
            dirty := true
        }
        symbol := finished ? "✔" : active ? "!" : ""
        if marker.SymbolText != symbol
        {
            marker.Symbol.Text := symbol
            if symbol = "✔"
                SetAccessibleTextFont(marker.Symbol, "s" GameLoginProgressFontSize(15, scale) " Bold c173C2A", "Segoe UI Symbol")
            else if symbol = "!"
                SetAccessibleTextFont(marker.Symbol, "s" GameLoginProgressFontSize(17, scale) " Bold c173C2A", LauncherThemeFont())
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

PositionGameLoginProgress(cardHwnd, gameHwnd, layout, show, moved)
{
    exStyle := -20 ; GWL_EXSTYLE
    topmost := 0x0008 ; WS_EX_TOPMOST
    above := DllCall("GetWindow", "Ptr", gameHwnd, "UInt", 3, "Ptr") ; GW_HWNDPREV
    gameTopmost := (DllCall("GetWindowLongW", "Ptr", gameHwnd, "Int", exStyle, "UInt") & topmost) != 0
    cardTopmost := (DllCall("GetWindowLongW", "Ptr", cardHwnd, "Int", exStyle, "UInt") & topmost) != 0
    flags := 0x0010 ; SWP_NOACTIVATE
    if above = cardHwnd && cardTopmost = gameTopmost
    {
        if !show && !moved
            return true
        flags |= 0x0004 ; SWP_NOZORDER
    }
    else if !gameTopmost && (!above || (DllCall("GetWindowLongW", "Ptr", above, "Int", exStyle, "UInt") & topmost))
    {
        ; At the top of the normal band, stay below the taskbar and other
        ; topmost windows. Inserting after one of them would promote the card.
        above := cardTopmost ? -2 : 0 ; HWND_NOTOPMOST or HWND_TOP
    }
    else if !above
        above := -1 ; HWND_TOPMOST, when the game is itself the topmost window.
    if show
        flags |= 0x0040 ; SWP_SHOWWINDOW
    else
        flags |= moved ? 0x0001 : 0x0003 ; SWP_NOSIZE, and SWP_NOMOVE if stationary.
    return DllCall("SetWindowPos", "Ptr", cardHwnd, "Ptr", above,
        "Int", layout.X, "Int", layout.Y, "Int", layout.Width, "Int", layout.Height, "UInt", flags, "Int") != 0
}

PresentGameLoginProgress(gameHwnd, layout)
{
    global LoginProgressGui, LoginProgressMode, LoginProgressShown
    previousCritical := Critical("On")
    previous := LoginProgressGui
    try
    {
        if LoginProgressMode = ""
            return
        plan := layout.HasOwnProp("Plan") ? layout.Plan : 0
        if !IsObject(previous) || previous.ProgressScale != layout.Scale
            || previous.ProgressPlan != plan
        {
            ; Construct the new size while hidden and paint current state.
            ; Keep the same login stage, generation, and dismissal deadline.
            CreateGameLoginProgress(layout)
            LoginProgressShown := false
        }
        RenderGameLoginProgress()
        moved := !LoginProgressShown || layout.X != previous.ProgressLayout.X || layout.Y != previous.ProgressLayout.Y
        if PositionGameLoginProgress(LoginProgressGui.Hwnd, gameHwnd, layout, !LoginProgressShown, moved)
        {
            LoginProgressGui.ProgressLayout := layout
            LoginProgressShown := true
            TrackGameLoginProgressWindow(gameHwnd)
        }
    }
    finally
    {
        if IsObject(previous) && previous != LoginProgressGui
            try previous.Destroy()
        Critical(previousCritical)
    }
}

UpdateGameLoginProgress(*)
{
    global Client, LoginProgressMode, LoginProgressCloseAt
    global LoginProgressDisabled, LoginProgressPid, LoginProgressHwnd
    global LoginProgressHardDeadline, LoginProgressGui, LoginProgressShown, LoginProgressTracking
    if LoginProgressMode = ""
    {
        ; A stale native overlay must never survive a completed dismissal.
        HideGameLoginProgress()
        SetTimer(UpdateGameLoginProgress, 0)
        return
    }
    ; If the login never reaches its expected visual-completion callback,
    ; avoid leaving the card covering part of a playable game forever.
    ; Never stop the client or alter credentials from a UI timeout.
    if LoginProgressMode = "login" && LoginProgressHardDeadline
        && A_TickCount >= LoginProgressHardDeadline
    {
        DismissGameLoginProgress()
        LogLauncherEvent("UI | Login progress exceeded its display deadline; game session unchanged.")
        return
    }
    ; Independently monitor the game process so an externally closed TES3MP
    ; console cannot strand its login card while ClientTick
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
        ; A game on another virtual desktop can still have WS_VISIBLE.
        cloaked := 0
        try DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "UInt*", &cloaked, "UInt", 4, "Int")
        if WinGetPID(target) != pid || !InStr(WinGetClass(target), "SDL")
            || WinGetMinMax(target) = -1 || cloaked
        {
            HideGameLoginProgress()
            return
        }
        ; Do not let the timer overwrite a newer position from a move callback.
        previousCritical := Critical("On")
        try
        {
            gameWindow := GetGameLoginProgressWindow(hwnd)
            layout := 0
            ; Preserve the card's offset across monitor edges during a drag.
            ; A true resize or the end of the move resumes normal fitting.
            if LoginProgressShown && GameLoginProgressIsDragging(LoginProgressTracking, hwnd)
                layout := TranslateGameLoginProgress(LoginProgressGui.ProgressLayout, gameWindow)
            if !IsObject(layout)
                layout := GetGameLoginProgressLayout(hwnd, gameWindow)
            if !IsObject(layout)
            {
                HideGameLoginProgress()
                return
            }
            PresentGameLoginProgress(hwnd, layout)
        }
        finally Critical(previousCritical)
    }
    catch Error as err
    {
        LoginProgressDisabled := true
        DisposeGameLoginProgress()
        try LogLauncherEvent("UI | Login progress disabled for this session (" Type(err) ").")
    }
}
