; Non-activating TES3MP login progress card. ClientTick owns inputs and timing.
global LoginProgressGui := 0
global LoginProgressRows := []
global LoginProgressCompletion := 0
global LoginProgressCharacterName := 0
global LoginProgressSpecies := ""
global LoginProgressPortraitFile := ""
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
    ; Collapse all three credential-entry events into one visual section.
    visualStage := stage = 1 ? 1 : 2
    if LoginProgressStage != visualStage
    {
        LoginProgressStage := visualStage
        LoginProgressStageStarted := A_TickCount
    }
    if stage = 1 && !LoginProgressHardDeadline
    {
        LoginProgressStageStarted := A_TickCount
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
    global LoginProgressGeneration, LoginProgressStageStarted
    if LoginProgressMode != "login"
        return
    LoginProgressMode := "complete"
    LoginProgressStage := 3
    LoginProgressStageStarted := A_TickCount
    LoginProgressName := name
    LoginProgressPid := pid
    LoginProgressHwnd := hwnd
    ; Two seconds of character-loading fill, then two seconds of green
    ; completion. Neither interval delays the actual client watchdog.
    LoginProgressCloseAt := LoginProgressStageStarted + 4000
    ; Generation-safe independent dismissal if repainting is interrupted.
    SetTimer(DismissCompletedLoginProgress.Bind(LoginProgressGeneration), -4100)
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
    global LoginProgressGui, LoginProgressRows, LoginProgressCompletion
    global LoginProgressCharacterName
    DismissGameLoginProgress()
    if IsObject(LoginProgressGui)
        try LoginProgressGui.Destroy()
    LoginProgressGui := 0
    LoginProgressRows := []
    LoginProgressCompletion := 0
    LoginProgressCharacterName := 0
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
    scale := Min(normalScale, area.Width / 960, area.Height / 132)
    margin := Max(0, Round(8 * scale))
    width := area.Width - 2 * margin, height := Round(112 * scale)
    if width < 1 || height < 1 || height + margin > area.Height
        return 0
    return {Scale: scale, Width: width, Height: height,
        X: area.X + margin, Y: area.Y + area.Height - height - margin}
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
MeasureGameLoginProgressPlan(scale, name, width)
{
    p := (value) => Max(1, Round(value * scale))
    panel := Gui("-DPIScale")
    try
    {
        sample := panel.Add("Text", "x0 y0 w1 h1", "")
        rim := p(15), divider := p(2), pad := p(5)
        portrait := p(68)
        SetAccessibleTextFont(sample, "s" GameLoginProgressFontSize(24, scale) " Bold", "Segoe UI Symbol")
        check := MeasureAccessibleSingleLineText(sample, "✔")
        finishW := Max(p(54), check.Width + 2 * pad)
        SetAccessibleTextFont(sample, "s" GameLoginProgressFontSize(18, scale) " Bold", LauncherThemeFont())
        nameExtent := MeasureAccessibleSingleLineText(sample, name)
        nameW := Max(p(48), Min(p(142), nameExtent.Width + p(6)))
        profileW := portrait + 3 * pad + nameW
        stageW := Floor((width - 2 * rim - 4 * divider - profileW - finishW) / 3)
        if stageW <= 2 * pad || profileW <= portrait + 3 * pad
            return 0
        display := PrepareAccessibleBookName(sample, name, nameW)
        nameH := MeasureAccessibleWrappedText(sample, display, nameW) + p(4)
        SetAccessibleTextFont(sample, "s" GameLoginProgressFontSize(15, scale) " Norm", LauncherThemeFont())
        labelH := 0
        for caption in GameLoginProgressCaptions()
            labelH := Max(labelH, MeasureAccessibleWrappedText(sample, caption, stageW - 2 * pad) + p(4))
        bodyH := Max(p(82), portrait + 2 * pad, nameH + 2 * pad, labelH + 2 * pad, check.Height + 2 * pad)
        height := bodyH + 2 * rim
        cells := [], x := rim + profileW + divider
        Loop 3
        {
            cells.Push({X: x, Y: rim, W: stageW, H: bodyH})
            x += stageW + divider
        }
        return {Width: width, Height: height, Rim: rim, Pad: pad, Divider: divider, BodyH: bodyH,
            ProfileW: profileW, Portrait: portrait, NameW: nameW, NameH: nameH, NameDisplay: display,
            Cells: cells, FinishX: x, FinishW: width - rim - x, LabelH: labelH}
    }
    finally panel.Destroy()
}

GameLoginProgressCaptions()
{
    return ["Waiting For Game Client...", "Querying Character Data...", "Character Loading..."]
}

FitAccessibleGameLoginProgress(area, gameWindow, normalScale, name)
{
    global AccessibilityTextSize
    static cached := 0
    base := FitGameLoginProgress(area, gameWindow, normalScale)
    if !IsObject(base)
        return 0
    if !IsObject(cached) || cached.W != area.Width || cached.H != area.Height
        || cached.Dpi != normalScale || cached.Mode != AccessibilityTextSize || !(cached.Name == name)
    {
        scale := base.Scale, plan := 0
        Loop 12
        {
            plan := MeasureGameLoginProgressPlan(scale, name, base.Width)
            if IsObject(plan) && plan.Height + (base.X - area.X) <= area.Height
                break
            scale *= 0.85
        }
        if !IsObject(plan) || plan.Height + (base.X - area.X) > area.Height
            return 0
        cached := {W: area.Width, H: area.Height, Dpi: normalScale,
            Mode: AccessibilityTextSize, Name: name, Scale: scale, Plan: plan}
    }
    plan := cached.Plan
    return {Scale: cached.Scale, Width: plan.Width, Height: plan.Height, Plan: plan,
        X: base.X, Y: area.Y + area.Height - plan.Height - (base.X - area.X)}
}

; A stage can approach completion, but only the real stage transition can
; make it full. Typing events are synchronous and must not be delayed for UI.
GameLoginProgressFill(index, stage, complete, elapsedMs, durationMs)
{
    if complete || index < stage
        return 100
    if index > stage
        return 0
    return Min(95, Max(0, Floor(100 * elapsedMs / Max(1, durationMs))))
}

GameLoginProgressDuration(stage)
{
    global Client
    if stage = 3
        return 2000
    if stage = 1 && IsObject(Client) && Client.HasOwnProp("UsernameDelay")
        return Max(1, Round(Client.UsernameDelay * 1000))
    if stage = 2 && IsObject(Client) && Client.HasOwnProp("PasswordDelay")
        return Max(1, Round(Client.PasswordDelay * 1000) + 350)
    return 350
}

GameLoginProgressFinished(mode, elapsed)
{
    return mode = "complete" && elapsed >= 2000
}

GameLoginProgressCaption(index, caption, stage, complete, elapsed)
{
    if index != 1 || stage != 1 || complete
        return caption
    return "Waiting For Game Client" SubStr("...", 1, Mod(Floor(Max(0, elapsed) / 350), 4))
}

CreateGameLoginProgress(layout)
{
    global LoginProgressGui, LoginProgressRows, LoginProgressCompletion
    global LoginProgressCharacterName, LoginProgressSpecies, LoginProgressPortraitFile
    window := Gui("-Caption +ToolWindow -DPIScale +E0x08000020", "tes3np Login Progress")
    LoginProgressGui := window
    window.ProgressScale := layout.Scale
    window.ProgressPlan := layout.Plan
    window.MarginX := 0, window.MarginY := 0
    window.BackColor := "18120B"
    plan := layout.Plan
    framePath := A_ScriptDir "\assets\controls\map-frame.png"
    ; Use the same file-backed Picture construction and subsequent bitmap
    ; assignment as the accepted native Server Map. Never pass a generated
    ; HBITMAP descriptor to Gui.Add, or create an uninitialized Picture.
    window.ProgressFrame := CreateGameLoginProgressPicture(window, framePath, 0, 0,
        layout.Width, layout.Height, "frame")
    frame := RenderLauncherMapFrame(framePath, layout.Width, layout.Height, layout.Scale, 13, 0xFF18120B)
    try window.ProgressFrame.Value := "*w0 *h0 HBITMAP:*" frame
    catch Error as err
        throw Error("Login strip frame bitmap assignment failed.", -1, Type(err))
    finally DllCall("gdi32\DeleteObject", "Ptr", frame)
    window.ProgressFrame.Move(0, 0, layout.Width, layout.Height)
    portraitPath := GetCharacterLoginIconPath(LoginProgressSpecies, LoginProgressPortraitFile)
    portraitY := plan.Rim + Floor((plan.BodyH - plan.Portrait) / 2)
    pictureOptions := "x" (plan.Rim + plan.Pad) " y" portraitY " w" plan.Portrait " h" plan.Portrait
    if RegExMatch(portraitPath, "i)\.ico$")
        pictureOptions .= " Icon1"
    try window.ProgressPortrait := window.Add("Picture", pictureOptions, portraitPath)
    catch Error as err
        throw Error("Login strip portrait control creation failed.", -1, Type(err))
    SetAccessibleTextFont(window, "s" GameLoginProgressFontSize(18, layout.Scale) " Bold cF2E4D0", LauncherThemeFont())
    nameX := plan.Rim + plan.Portrait + 2 * plan.Pad
    nameY := plan.Rim + Floor((plan.BodyH - plan.NameH) / 2)
    LoginProgressCharacterName := window.Add("Text", "x" nameX " y" nameY " w" plan.NameW
        " h" plan.NameH " Center Background18120B", plan.NameDisplay)
    SetAccessibleTextFont(window, "s" GameLoginProgressFontSize(15, layout.Scale) " Norm", LauncherThemeFont())
    window.ProgressStageFont := window.Add("Text", "x0 y0 w1 h1 Hidden", "")
    SetAccessibleTextFont(window, "s" GameLoginProgressFontSize(24, layout.Scale) " Bold", "Segoe UI Symbol")
    window.ProgressCheckFont := window.Add("Text", "x0 y0 w1 h1 Hidden", "")
    LoginProgressRows := []
    for index, caption in GameLoginProgressCaptions()
    {
        cell := plan.Cells[index]
        window.Add("Text", "x" (cell.X - plan.Divider) " y" cell.Y " w" plan.Divider " h" cell.H " BackgroundB8975C", "")
        picture := CreateGameLoginProgressPicture(window, framePath, cell.X, cell.Y,
            cell.W, cell.H, "stage " index)
        LoginProgressRows.Push({Picture: picture, Caption: caption, Cell: cell, Fill: -1, RenderedCaption: ""})
    }
    window.Add("Text", "x" (plan.FinishX - plan.Divider) " y" plan.Rim " w" plan.Divider " h" plan.BodyH " BackgroundB8975C", "")
    LoginProgressCompletion := CreateGameLoginProgressPicture(window, framePath, plan.FinishX, plan.Rim,
        plan.FinishW, plan.BodyH, "completion")
    window.ProgressComplete := -1
    window.Show("Hide x" layout.X " y" layout.Y " w" layout.Width " h" layout.Height)
}

CreateGameLoginProgressPicture(window, seedPath, x, y, width, height, role)
{
    ; The real bitmap is painted before the hidden window is revealed.
    ; Seed from the already bundled texture; no extra assets or disk cache.
    if width < 1 || height < 1
        throw Error("Login strip " role " has invalid dimensions.")
    try
    {
        picture := window.Add("Picture", "x0 y0 w1 h1", seedPath)
        picture.Move(x, y, width, height)
        return picture
    }
    catch Error as err
        throw Error("Login strip " role " Picture creation failed.", -1, Type(err))
}

; Native bitmap per section: the fill covers its entire cell, with the
; caption painted last into the same surface, centered on both axes.
; Picture owns a copy; all temporary DC/bitmap/brush resources are released.
PaintGameLoginProgressCell(picture, sample, caption, width, height, pad, fill, textColor)
{
    screen := 0, dc := 0, bitmap := 0, oldBitmap := 0, oldFont := 0
    dark := 0, gold := 0
    try
    {
        screen := DllCall("GetDC", "Ptr", 0, "Ptr")
        if !screen
            throw Error("Login progress screen DC unavailable.")
        dc := DllCall("CreateCompatibleDC", "Ptr", screen, "Ptr")
        bitmap := DllCall("CreateCompatibleBitmap", "Ptr", screen, "Int", width, "Int", height, "Ptr")
        if !dc || !bitmap
            throw Error("Login progress bitmap unavailable.")
        oldBitmap := DllCall("SelectObject", "Ptr", dc, "Ptr", bitmap, "Ptr")
        if !oldBitmap || oldBitmap = -1
            throw Error("Login progress bitmap selection failed.")
        dark := DllCall("CreateSolidBrush", "UInt", 0x000B1218, "Ptr")
        ; Active cells use the existing gold; completed cells become green.
        gold := DllCall("CreateSolidBrush", "UInt", fill = 100 ? 0x003B6437 : 0x0034618A, "Ptr")
        if !dark || !gold
            throw Error("Login progress brush unavailable.")
        rect := Buffer(16, 0)
        NumPut("Int", width, "Int", height, rect, 8)
        DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", dark)
        fillWidth := Round(width * fill / 100)
        if fillWidth > 0
        {
            NumPut("Int", fillWidth, rect, 8)
            DllCall("FillRect", "Ptr", dc, "Ptr", rect, "Ptr", gold)
        }
        font := DllCall("SendMessageW", "Ptr", sample.Hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
        if font
            oldFont := DllCall("SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        if !font || !oldFont || oldFont = -1
            throw Error("Login progress font selection failed.")
        DllCall("SetBkMode", "Ptr", dc, "Int", 1)
        DllCall("SetTextColor", "Ptr", dc, "UInt", textColor)
        textH := MeasureAccessibleWrappedText(sample, caption, Max(1, width - 2 * pad))
        top := Max(0, Floor((height - textH) / 2))
        NumPut("Int", pad, "Int", top, "Int", width - pad, "Int", height, rect)
        DllCall("DrawTextW", "Ptr", dc, "WStr", caption, "Int", -1, "Ptr", rect, "UInt", 0x811)
        DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
        oldFont := 0
        DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
        oldBitmap := 0
        try picture.Value := "*w0 *h0 HBITMAP:*" bitmap
        catch Error as err
            throw Error("Login strip cell bitmap assignment failed.", -1, Type(err))
    }
    finally
    {
        if oldFont && oldFont != -1
            DllCall("SelectObject", "Ptr", dc, "Ptr", oldFont)
        if oldBitmap && oldBitmap != -1
            DllCall("SelectObject", "Ptr", dc, "Ptr", oldBitmap)
        for brush in [dark, gold]
            if brush
                DllCall("DeleteObject", "Ptr", brush)
        if bitmap
            DllCall("DeleteObject", "Ptr", bitmap)
        if dc
            DllCall("DeleteDC", "Ptr", dc)
        if screen
            DllCall("ReleaseDC", "Ptr", 0, "Ptr", screen)
    }
}

RenderGameLoginProgress()
{
    global LoginProgressGui, LoginProgressRows, LoginProgressCompletion
    global LoginProgressMode, LoginProgressStage, LoginProgressStageStarted
    stage := LoginProgressStage
    elapsed := Max(0, A_TickCount - LoginProgressStageStarted)
    complete := GameLoginProgressFinished(LoginProgressMode, elapsed)
    duration := GameLoginProgressDuration(stage)
    plan := LoginProgressGui.ProgressPlan
    dirty := false
    for index, row in LoginProgressRows
    {
        fill := GameLoginProgressFill(index, stage, complete, elapsed, duration)
        caption := GameLoginProgressCaption(index, row.Caption, stage, complete, elapsed)
        if row.Fill != fill || row.RenderedCaption != caption
        {
            PaintGameLoginProgressCell(row.Picture, LoginProgressGui.ProgressStageFont, caption,
                row.Cell.W, row.Cell.H, plan.Pad, fill, 0x00D0E4F2)
            row.Fill := fill
            row.RenderedCaption := caption
            dirty := true
        }
    }
    if LoginProgressGui.ProgressComplete != complete
    {
        PaintGameLoginProgressCell(LoginProgressCompletion, LoginProgressGui.ProgressCheckFont, "✔",
            plan.FinishW, plan.BodyH, plan.Pad, complete ? 100 : 0, complete ? 0x00D0E4F2 : 0x0053606A)
        LoginProgressGui.ProgressComplete := complete
        dirty := true
    }
    if dirty
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
