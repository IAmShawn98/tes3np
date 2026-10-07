; v0.1.16 test-branch UI refinements.

global V016CharacterLayoutApplied := false
global V016SettingsGuiHwnd := 0
global V016SettingsScale := 1.0
global V016ReadabilityState := 0
global V016FollowWindowsState := 0
global V016DailyLoginControls := []

InitializeV016UiRefinements()
{
    SetTimer(ApplyV016CharacterLayout, 250)
    OnMessage(0x84, HandleV016SettingsHitTest)
}

V016S(value)
{
    global V016SettingsScale
    return Round(value * V016SettingsScale)
}

V016Font(value)
{
    global V016SettingsScale
    return Max(6, Round(value * V016SettingsScale))
}

HandleV016SettingsHitTest(wParam, lParam, msg, hwnd)
{
    global V016SettingsGuiHwnd
    if !V016SettingsGuiHwnd || hwnd != V016SettingsGuiHwnd || !DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd, "Int")
        return
    pt := Buffer(8, 0)
    NumPut("Int", lParam & 0xFFFF, pt, 0)
    NumPut("Int", (lParam >> 16) & 0xFFFF, pt, 4)
    DllCall("ScreenToClient", "Ptr", V016SettingsGuiHwnd, "Ptr", pt)
    localY := NumGet(pt, 4, "Int")
    if localY >= 0 && localY <= V016S(96)
        return 2
}

ApplyV016CharacterLayout(*)
{
    global CharacterPage, LaunchCharacterButton, ExecutableInput, V016CharacterLayoutApplied
    if V016CharacterLayoutApplied || !IsObject(CharacterPage)
        return
    try
    {
        LaunchCharacterButton.Visible := false
        ExecutableInput.GetPos(, &executableY, , &executableHeight)
        global LaunchSettingsControls
        global ScheduledEvents
        label := ScheduledEvents.Length ? "Scheduled Events (" ScheduledEvents.Length ")" : "Schedule Event"
        dailyButton := AddStyledButton(CharacterPage, 70, 510, 370, 25, label, OpenScheduledEventsMenu)
        ; Scheduled Events belongs to the character action stack, not Launch Settings.
        ; Keep it independent so opening the add/edit form does not hide it.
        global V016DailyLoginControls
        V016DailyLoginControls := [dailyButton]
        hasCharacters := Profiles.Length > 0
        for control in V016DailyLoginControls
            control.Visible := hasCharacters
        ; Keep the character actions contiguous: Add Character, Scheduled Events, then Wipe Character List.
        addY := Profiles.Length ? 505 : 185
        AddCharacterButton.Move(70, addY, 370, 30)
        ButtonFaces[AddCharacterButton.Hwnd].Y := addY
        dailyButton.Move(70, 540, 370, 30)
        ButtonFaces[dailyButton.Hwnd].Y := 540
        WipeCharacterButton.Move(70, 575, 370, 30)
        ButtonFaces[WipeCharacterButton.Hwnd].Y := 575
        V016CharacterLayoutApplied := true
    }
}

global LauncherMorrowindFont := "Georgia"
global LauncherMorrowindFontPath := ""
global LauncherMorrowindFontLoaded := false
global LauncherMagicCardsFnt := ""
global LauncherMagicCardsTex := ""
global LauncherMagicCardsData := false

InitializeLauncherMorrowindFont()
{
    global LauncherMorrowindFont, LauncherMorrowindFontPath, LauncherMorrowindFontLoaded
    global LauncherMagicCardsFnt, LauncherMagicCardsTex, LauncherMagicCardsData

    ; Do not substitute MysticCards/Georgia and call it the Morrowind journal font.
    ; Vanilla Morrowind's journal uses its own Magic_Cards_Regular bitmap glyphs.
    LauncherMorrowindFont := "Georgia"
    LauncherMorrowindFontPath := ""
    LauncherMorrowindFontLoaded := false
    LauncherMagicCardsFnt := ""
    LauncherMagicCardsTex := ""
    LauncherMagicCardsData := false

    fontPair := FindVanillaMagicCardsFont()
    if IsObject(fontPair)
    {
        LauncherMagicCardsFnt := fontPair.Fnt
        LauncherMagicCardsTex := fontPair.Tex
        LauncherMagicCardsData := LoadMagicCardsBitmapFont(fontPair.Fnt)
        try LogLauncherEvent("UI | Vanilla journal font found: " fontPair.Fnt)
        if IsObject(LauncherMagicCardsData)
        {
            try LogLauncherEvent("UI | Vanilla journal font parsed successfully. Glyphs: " LauncherMagicCardsData.Glyphs.Length ".")
            atlas := MagicCardsCreateGlyphAtlas()
            if IsObject(atlas)
            {
                try LogLauncherEvent("UI | Vanilla journal texture decoded: " atlas.Width "x" atlas.Height ".")
            }
            else
            {
                try LogLauncherEvent("UI | Vanilla journal texture decode failed; bitmap text will fall back.")
            }
        }
        else
            try LogLauncherEvent("UI | Vanilla journal font parser failed; using fallback text.")
    }
    else
        try LogLauncherEvent("UI | Vanilla journal font not found; using fallback text.")
}

FindVanillaMagicCardsFont()
{
    global Profiles
    candidates := []

    ; TES3MP installations normally sit beside the game's Data Files directory.
    try
    {
        executable := GetSharedExecutable()
        if executable != ""
        {
            SplitPath(executable, , &exeDir)
            candidates.Push(exeDir "\\Data Files\\Fonts")
            candidates.Push(exeDir "\\data\\Fonts")
            candidates.Push(exeDir "\\Fonts")
        }
    }

    ; Also check the standard Steam/GOG-style Morrowind locations without
    ; requiring the launcher to redistribute Bethesda's font assets.
    candidates.Push(A_ProgramFiles "\\Steam\\steamapps\\common\\Morrowind\\Data Files\\Fonts")
    if A_Is64bitOS
        candidates.Push(EnvGet("ProgramFiles(x86)") "\\Steam\\steamapps\\common\\Morrowind\\Data Files\\Fonts")
    candidates.Push(A_ProgramFiles "\\GOG Galaxy\\Games\\Morrowind\\Data Files\\Fonts")
    if A_Is64bitOS
        candidates.Push(EnvGet("ProgramFiles(x86)") "\\GOG Galaxy\\Games\\Morrowind\\Data Files\\Fonts")

    for dir in candidates
    {
        fnt := dir "\\Magic_Cards_Regular.fnt"
        if !FileExist(fnt)
            fnt := dir "\\magic_cards_regular.fnt"
        if !FileExist(fnt)
            continue

        ; The .fnt itself stores the exact texture basename used by Morrowind.
        ; Read it instead of assuming a particular _0_Lod_A filename.
        texName := ReadMagicCardsTextureName(fnt)
        if texName = ""
            continue
        tex := dir "\\" texName
        if !FileExist(tex) && !InStr(texName, ".")
            tex .= ".tex"
        if FileExist(tex)
            return {Fnt: fnt, Tex: tex}
    }
    return false
}


ReadMagicCardsTextureName(fntPath)
{
    ; Morrowind bitmap font header:
    ; float size, int 1, int 1, then a 284-byte NUL-terminated texture name.
    try
    {
        file := FileOpen(fntPath, "r")
        if !IsObject(file) || file.Length < 296
            return ""
        file.Pos := 12
        nameBytes := Buffer(284, 0)
        if file.RawRead(nameBytes, 284) < 1
            return ""
        name := StrGet(nameBytes, "CP0")
        name := Trim(name, " `t`r`n`0")
        if name = ""
            return ""
        SplitPath(name, &leaf)
        return leaf
    }
    return ""
}

LoadMagicCardsBitmapFont(fntPath)
{
    ; Parse the complete 256-glyph metrics table. The renderer uses these exact
    ; UV coordinates, widths, kerning and ascent values from vanilla Morrowind.
    try
    {
        file := FileOpen(fntPath, "r")
        if !IsObject(file) || file.Length < 296 + (256 * 40)
            return false
        sizeBuf := Buffer(4)
        file.RawRead(sizeBuf, 4)
        fontSize := NumGet(sizeBuf, 0, "Float")
        file.Pos := 296
        glyphs := []
        Loop 256
        {
            g := Buffer(40)
            if file.RawRead(g, 40) != 40
                return false
            glyphs.Push({
                TopLeftX: NumGet(g, 4, "Float"), TopLeftY: NumGet(g, 8, "Float"),
                TopRightX: NumGet(g, 12, "Float"), TopRightY: NumGet(g, 16, "Float"),
                BottomLeftX: NumGet(g, 20, "Float"), BottomLeftY: NumGet(g, 24, "Float"),
                BottomRightX: NumGet(g, 28, "Float"), BottomRightY: NumGet(g, 32, "Float"),
                Width: NumGet(g, 36, "Float")
            })
        }
        return {FontSize: fontSize, Glyphs: glyphs}
    }
    return false
}


MagicCardsMeasureText(text, scale := 1.0)
{
    global LauncherMagicCardsData
    if !IsObject(LauncherMagicCardsData)
        return 0
    width := 0.0
    Loop Parse text
    {
        code := Ord(A_LoopField)
        if code < 0 || code > 255
            code := 63
        width += LauncherMagicCardsData.Glyphs[code + 1].Width * scale
    }
    return Round(width)
}

MagicCardsGlyphRun(text, x, y, height)
{
    ; Produce exact per-glyph layout from the vanilla metrics. Keeping this
    ; independent of AHK's text controls prevents Windows font fallback from
    ; changing the journal lettering.
    global LauncherMagicCardsData
    if !IsObject(LauncherMagicCardsData) || LauncherMagicCardsData.FontSize <= 0
        return false
    scale := height / LauncherMagicCardsData.FontSize
    penX := x
    run := []
    Loop Parse text
    {
        code := Ord(A_LoopField)
        if code < 0 || code > 255
            code := 63
        glyph := LauncherMagicCardsData.Glyphs[code + 1]
        advance := glyph.Width * scale
        run.Push({
            Code: code, X: penX, Y: y, Height: height, Advance: advance,
            TopLeftX: glyph.TopLeftX, TopLeftY: glyph.TopLeftY,
            TopRightX: glyph.TopRightX, TopRightY: glyph.TopRightY,
            BottomLeftX: glyph.BottomLeftX, BottomLeftY: glyph.BottomLeftY,
            BottomRightX: glyph.BottomRightX, BottomRightY: glyph.BottomRightY
        })
        penX += advance
    }
    return run
}


MagicCardsCreateGlyphAtlas()
{
    ; Convert Morrowind's proprietary .tex atlas through the installed game's
    ; own texture data. The decoder is intentionally local-only: Bethesda's
    ; journal artwork is never bundled with tes3np.
    global LauncherMagicCardsTex
    if LauncherMagicCardsTex = "" || !FileExist(LauncherMagicCardsTex)
        return false

    file := FileOpen(LauncherMagicCardsTex, "r")
    if !IsObject(file) || file.Length < 8
        return false

    ; Vanilla font TEX layout, matching OpenMW's Morrowind font loader:
    ; int32 width, int32 height, immediately followed by width*height RGBA bytes.
    header := Buffer(8, 0)
    if file.RawRead(header, 8) != 8
        return false
    width := NumGet(header, 0, "Int")
    height := NumGet(header, 4, "Int")
    if width < 1 || height < 1 || width > 4096 || height > 4096
        return false

    pixelBytes := width * height * 4
    pixels := Buffer(pixelBytes, 0)
    bytesRead := file.RawRead(pixels, pixelBytes)
    if bytesRead <= 0
        return false
    ; Morrowind/OpenMW tolerate a short atlas read; the zero-filled remainder
    ; stays transparent rather than rejecting the entire font.

    return {Width: width, Height: height, Pixels: pixels}
}

MagicCardsGlyphSourceRect(glyph, atlasWidth, atlasHeight)
{
    ; UVs in the vanilla .fnt are normalized texture coordinates.
    left := Round(Min(glyph.TopLeftX, glyph.BottomLeftX) * atlasWidth)
    right := Round(Max(glyph.TopRightX, glyph.BottomRightX) * atlasWidth)
    top := Round(Min(glyph.TopLeftY, glyph.TopRightY) * atlasHeight)
    bottom := Round(Max(glyph.BottomLeftY, glyph.BottomRightY) * atlasHeight)
    return {X: left, Y: top, W: Max(1, right - left), H: Max(1, bottom - top)}
}


MagicCardsRenderText(text, width, height, fontHeight, color := 0xFF382314, center := false)
{
    ; Render the vanilla bitmap glyphs into a 32-bit DIB that an AHK Picture
    ; control can display. No Windows font rasterizer is involved.
    global LauncherMagicCardsData
    if !IsObject(LauncherMagicCardsData)
        return false
    atlas := MagicCardsCreateGlyphAtlas()
    if !IsObject(atlas)
        return false

    stride := width * 4
    out := Buffer(stride * height, 0)
    runWidth := MagicCardsMeasureText(text, fontHeight / LauncherMagicCardsData.FontSize)
    penX := center ? Max(0, Floor((width - runWidth) / 2)) : 0
    run := MagicCardsGlyphRun(text, penX, 0, fontHeight)
    if !IsObject(run)
        return false

    for item in run
    {
        glyph := LauncherMagicCardsData.Glyphs[item.Code + 1]
        src := MagicCardsGlyphSourceRect(glyph, atlas.Width, atlas.Height)
        dstW := Max(1, Round(src.W * (fontHeight / LauncherMagicCardsData.FontSize)))
        dstH := Max(1, Round(src.H * (fontHeight / LauncherMagicCardsData.FontSize)))
        Loop dstH
        {
            dy := A_Index - 1
            py := item.Y + dy
            if py < 0 || py >= height
                continue
            sy := src.Y + Min(src.H - 1, Floor(dy * src.H / dstH))
            Loop dstW
            {
                dx := A_Index - 1
                px := Round(item.X) + dx
                if px < 0 || px >= width
                    continue
                sx := src.X + Min(src.W - 1, Floor(dx * src.W / dstW))
                srcOff := (sy * atlas.Width + sx) * 4
                alpha := NumGet(atlas.Pixels, srcOff + 3, "UChar")
                if alpha = 0
                    continue
                dstOff := (py * width + px) * 4
                NumPut("UChar", (color >> 16) & 0xFF, out, dstOff)
                NumPut("UChar", (color >> 8) & 0xFF, out, dstOff + 1)
                NumPut("UChar", color & 0xFF, out, dstOff + 2)
                NumPut("UChar", alpha, out, dstOff + 3)
            }
        }
    }
    return MagicCardsBufferToHBitmap(out, width, height)
}

MagicCardsBufferToHBitmap(pixels, width, height)
{
    bmi := Buffer(40, 0)
    NumPut("UInt", 40, bmi, 0)
    NumPut("Int", width, bmi, 4)
    NumPut("Int", -height, bmi, 8)
    NumPut("UShort", 1, bmi, 12)
    NumPut("UShort", 32, bmi, 14)
    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    bits := 0
    hbm := DllCall("Gdi32.dll\CreateDIBSection", "Ptr", hdc, "Ptr", bmi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    if !hbm || !bits
        return false
    DllCall("RtlMoveMemory", "Ptr", bits, "Ptr", pixels.Ptr, "UPtr", pixels.Size)
    return hbm
}

AddMagicCardsText(gui, x, y, w, h, text, fontHeight, color := 0xFF382314, center := false)
{
    static failureLogged := false
    hbm := MagicCardsRenderText(text, w, h, fontHeight, color, center)
    if !hbm
    {
        if !failureLogged
        {
            failureLogged := true
            try LogLauncherEvent("UI | Vanilla journal bitmap render failed; controls are using fallback text.")
        }
        return false
    }
    pic := gui.Add("Picture", "x" x " y" y " w" w " h" h " BackgroundTrans", "HBITMAP:*" hbm)
    pic.OnEvent("Destroy", (*) => DllCall("Gdi32.dll\DeleteObject", "Ptr", hbm))
    return pic
}


AddMagicCardsInteractiveLabel(gui, x, y, w, h, prefix, text, fontHeight, callback, color := 0xFF382314)
{
    ; Keep the clickable checkbox symbol native, but render its label with the
    ; vanilla journal glyphs. The transparent hit target preserves interaction.
    gui.SetFont("s" V016Font(13) " c382314", "Segoe UI Symbol")
    symbol := gui.Add("Text", "x" x " y" y " w" V016S(30) " h" h " +0x100 BackgroundTrans", prefix)
    label := AddMagicCardsText(gui, x + V016S(38), y, w - V016S(38), h, text, fontHeight, color)
    hit := gui.Add("Text", "x" x " y" y " w" w " h" h " +0x100 BackgroundTrans", "")
    hit.OnEvent("Click", callback)
    return {Symbol: symbol, Label: label, Hit: hit}
}

ReleaseLauncherMorrowindFont()
{
    global LauncherMorrowindFontLoaded, LauncherMagicCardsFnt, LauncherMagicCardsTex, LauncherMagicCardsData
    LauncherMorrowindFontLoaded := false
    LauncherMagicCardsFnt := ""
    LauncherMagicCardsTex := ""
    LauncherMagicCardsData := false
}

OpenLauncherSettingsV016(*)
{
    global LauncherGui, LauncherScale, LauncherScaleMode, AccessibilityTextSize, EnhancedReadability, FollowWindowsAccessibility, LauncherMorrowindFont
    global V016SettingsGuiHwnd, V016SettingsScale, V016ReadabilityState, V016FollowWindowsState

    ; Launcher Settings is a single modal-style window. If it is already open,
    ; bring that instance forward instead of creating duplicates.
    if V016SettingsGuiHwnd && DllCall("IsWindow", "Ptr", V016SettingsGuiHwnd, "Int")
    {
        WinActivate("ahk_id " V016SettingsGuiHwnd)
        return
    }
    V016SettingsGuiHwnd := 0

    ; Use the same resolved launcher scale (automatic or manual) as the main window.
    ; AHK still handles monitor DPI; this factor handles tes3np's own 50-100% launcher scale.
    V016SettingsScale := LauncherScale / 100

    settings := Gui("+Owner" LauncherGui.Hwnd " -Caption -Border -MinimizeBox -MaximizeBox +ToolWindow", "tes3np — Launcher Settings")
    settings.MarginX := 0, settings.MarginY := 0
    settings.BackColor := "010101"
    V016SettingsGuiHwnd := settings.Hwnd
    V016ReadabilityState := EnhancedReadability ? 1 : 0
    V016FollowWindowsState := FollowWindowsAccessibility ? 1 : 0

    settings.Add("Picture", "x" V016S(-12) " y" V016S(-20) " w" V016S(544) " h" V016S(650), A_ScriptDir "\\assets\\controls\\scroll-panel.png")

    settings.SetFont("s" V016Font(16) " c241408", LauncherMorrowindFont)
    if !AddMagicCardsText(settings, V016S(32), V016S(76), V016S(448), V016S(34), "Launcher Settings", V016Font(24), 0xFF241408, true)
        settings.Add("Text", "x" V016S(32) " y" V016S(76) " w" V016S(448) " h" V016S(34) " Center BackgroundTrans", "Launcher Settings")

    settings.SetFont("s" V016Font(11) " c382314", LauncherMorrowindFont)
    if !AddMagicCardsText(settings, V016S(32), V016S(124), V016S(145), V016S(24), "Launcher size", V016Font(18), 0xFF382314)
        settings.Add("Text", "x" V016S(32) " y" V016S(124) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Launcher size")
    ; Native dropdowns cannot display the proprietary bitmap face directly.
    ; Keep their interactive chrome native, but use a neutral system font so
    ; they no longer inherit the old Georgia/MysticCards approximation.
    settings.SetFont("s" V016Font(10) " c382314", "Segoe UI")
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x" V016S(184) " y" V016S(119) " w" V016S(296) " Choose" choice, choices)
    settings.SetFont("s" V016Font(10) " c5A4027", LauncherMorrowindFont)
    if !AddMagicCardsText(settings, V016S(32), V016S(151), V016S(448), V016S(40), "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.", V016Font(15), 0xFF5A4027)
        settings.Add("Text", "x" V016S(32) " y" V016S(151) " w" V016S(448) " h" V016S(40) " BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s" V016Font(11) " c382314", LauncherMorrowindFont)
    if !AddMagicCardsText(settings, V016S(32), V016S(197), V016S(145), V016S(24), "Interface text", V016Font(18), 0xFF382314)
        settings.Add("Text", "x" V016S(32) " y" V016S(197) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Interface text")
    settings.SetFont("s" V016Font(10) " c382314", "Segoe UI")
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x" V016S(184) " y" V016S(192) " w" V016S(296) " Choose" textChoice, textChoices)
    settings.SetFont("s" V016Font(10) " c5A4027", LauncherMorrowindFont)
    if !AddMagicCardsText(settings, V016S(32), V016S(224), V016S(448), V016S(30), "Choose how big or small the launcher interface is for you.", V016Font(15), 0xFF5A4027)
        settings.Add("Text", "x" V016S(32) " y" V016S(224) " w" V016S(448) " h" V016S(30) " BackgroundTrans", "Choose how big or small the launcher interface is for you.")

    readabilityPrefix := V016ReadabilityState ? "☑" : "☐"
    readabilityParts := AddMagicCardsInteractiveLabel(settings, V016S(32), V016S(260), V016S(448), V016S(32), readabilityPrefix, "Enhanced readability", V016Font(19), ToggleV016ReadabilityParts.Bind())
    readability := readabilityParts.Hit
    settings.SetFont("s" V016Font(10) " c5A4027", LauncherMorrowindFont)
    if !AddMagicCardsText(settings, V016S(70), V016S(290), V016S(410), V016S(42), "Improves readability by providing stronger contrast and brighter button text.", V016Font(15), 0xFF5A4027)
        settings.Add("Text", "x" V016S(70) " y" V016S(290) " w" V016S(410) " h" V016S(42) " BackgroundTrans", "Improves readability by providing stronger contrast and brighter button text.")

    readabilityValue := {Value: V016ReadabilityState}
    followWindowsValue := {Value: FollowWindowsAccessibility ? 1 : 0}
    reduceMotionBox := {Value: 0}

    AddStyledButton(settings, V016S(32), V016S(338), V016S(214), V016S(38), "Preview Changes", ApplyV016LauncherSettings.Bind(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(266), V016S(338), V016S(214), V016S(38), "Close", CloseLauncherSettingsV016.Bind(settings))
    AddStyledButton(settings, V016S(32), V016S(400), V016S(448), V016S(38), "Reset Launcher Settings", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(32), V016S(450), V016S(448), V016S(38), "AppData Settings", OpenAppDataSettingsV016)

    settings.OnEvent("Escape", CloseLauncherSettingsV016.Bind(settings))
    settings.OnEvent("Close", CloseLauncherSettingsV016.Bind(settings))
    settings.OnEvent("Size", (*) => 0)
    settings.Show("w" V016S(512) " h" V016S(590))
    DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 0)
    WinSetTransColor("010101", "ahk_id " settings.Hwnd)
    FinishButtonDisplay()
}

CloseLauncherSettingsV016(settings, *)
{
    global LauncherGui, V016SettingsGuiHwnd
    hwnd := 0
    try hwnd := settings.Hwnd
    if hwnd && V016SettingsGuiHwnd = hwnd
        V016SettingsGuiHwnd := 0
    try settings.Destroy()
    if IsObject(LauncherGui) && DllCall("IsWindow", "Ptr", LauncherGui.Hwnd, "Int")
    {
        DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 1)
        WinActivate("ahk_id " LauncherGui.Hwnd)
    }
}

V016CheckLabel(state, label)
{
    return (state ? "☑" : "☐") "  " label
}

ToggleV016ReadabilityParts(*)
{
    global V016ReadabilityState
    V016ReadabilityState := !V016ReadabilityState
    ; Reopen settings to refresh the bitmap label and checkbox together.
    ; The saved value is still applied only by Preview Changes.
    try
    {
        global V016SettingsGuiHwnd
        hwnd := V016SettingsGuiHwnd
        if hwnd && DllCall("IsWindow", "Ptr", hwnd, "Int")
        {
            symbol := V016ReadabilityState ? "☑" : "☐"
            controls := WinGetControls("ahk_id " hwnd)
            for ctl in controls
                try if InStr(ControlGetText(ctl, "ahk_id " hwnd), "☐") || InStr(ControlGetText(ctl, "ahk_id " hwnd), "☑")
                    ControlSetText(symbol, ctl, "ahk_id " hwnd)
        }
    }
}

UpdateV016ReadabilityLabel(control, state)
{
    if !IsObject(control) || !DllCall("IsWindow", "Ptr", control.Hwnd, "Int")
        return
    try control.Text := V016CheckLabel(state, "Enhanced readability")
}

ToggleV016FollowWindows(control, *)
{
    global V016FollowWindowsState
    V016FollowWindowsState := !V016FollowWindowsState
    control.Text := V016CheckLabel(V016FollowWindowsState, "Follow Windows accessibility settings")
}

ApplyV016LauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue, *)
{
    global V016ReadabilityState, V016FollowWindowsState
    readabilityValue.Value := V016ReadabilityState
    followWindowsValue.Value := V016FollowWindowsState
    PreviewLauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue, "Applying launcher settings...")
}

ResetLauncherSettingsV016(settings, scaleList, textList, readability, readabilityValue, reduceMotionBox, followWindowsValue, *)
{
    global V016ReadabilityState, V016FollowWindowsState
    if MsgBox("Reset launcher settings to their defaults?", "tes3np — Reset Launcher Settings", "YesNo Icon?") != "Yes"
        return
    scaleList.Choose(1), textList.Choose(1)
    V016ReadabilityState := 0, V016FollowWindowsState := 1
    readability.Text := V016CheckLabel(0, "Enhanced readability")
    readabilityValue.Value := 0, reduceMotionBox.Value := 0, followWindowsValue.Value := 1
    PreviewLauncherSettings(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue, "Resetting launcher settings...")
}

OpenAppDataSettingsV016(*)
{
    global LauncherGui
    window := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — AppData")
    window.BackColor := "E2CEA2"
    window.SetFont("s11 Bold c241408", "Segoe UI")
    window.Add("Text", "x20 y18 w520 h26", "AppData")
    window.SetFont("s9 c382314", "Segoe UI")
    window.Add("Text", "x20 y48 w520 h92", "AppData stores the launcher's settings and all of your local characters you added to the launcher. Make sure before tampering with these files you export your character data under the 'Manage Characters' page. This way if something goes wrong you can fully restore all your set characters and preferences.")
    openFolder := window.Add("Button", "x20 y150 w520 h34", "Open AppData Folder")
    copyLauncher := window.Add("Button", "x20 y194 w255 h34", "Copy Launcher Log")
    copyRender := window.Add("Button", "x285 y194 w255 h34", "Copy Render Errors Log")
    copyPatch := window.Add("Button", "x20 y238 w255 h34", "Copy Patch Log")
    copyPatchErrors := window.Add("Button", "x285 y238 w255 h34", "Copy Patch Errors Log")
    reset := window.Add("Button", "x20 y292 w520 h34", "Reset AppData")
    close := window.Add("Button", "x20 y336 w520 h34 Default", "Close")
    openFolder.OnEvent("Click", OpenLauncherDataFolder)
    copyLauncher.OnEvent("Click", CopyAppDataLog.Bind("launcher.log", true))
    copyRender.OnEvent("Click", CopyAppDataLog.Bind("render-errors.log"))
    copyPatch.OnEvent("Click", CopyAppDataLog.Bind("patch-all.log"))
    copyPatchErrors.OnEvent("Click", CopyAppDataLog.Bind("patch-errors.log"))
    reset.OnEvent("Click", ShowResetAppDataActions)
    close.OnEvent("Click", (*) => window.Destroy())
    window.OnEvent("Escape", (*) => window.Destroy())
    window.Show("w560 h390")
}

CopyAppDataLog(filename, syncLauncher := false, *)
{
    global AppDataDirectory
    if syncLauncher
        SyncPatchLogToLauncherLog()
    path := AppDataDirectory "\" filename
    if !FileExist(path)
    {
        MsgBox(filename " does not exist yet.", "tes3np — AppData")
        return
    }
    try A_Clipboard := FileRead(path, "UTF-8")
    catch as err
    {
        MsgBox("Could not read " filename ".\n\n" err.Message, "tes3np — AppData")
        return
    }
    MsgBox(filename " copied to the clipboard.", "tes3np — AppData")
}

ShowLauncherLogActions(*)
{
    choice := MsgBox("Yes: Open the launcher log`nNo: Copy the launcher log to the clipboard`nCancel: More options", "tes3np — Launcher Logs", "YesNoCancel Icon?")
    if choice = "Yes"
        return OpenLauncherLog()
    if choice = "No"
    {
        global LauncherLogFile
        SyncPatchLogToLauncherLog()
        A_Clipboard := FileExist(LauncherLogFile) ? FileRead(LauncherLogFile, "UTF-8") : ""
        MsgBox("Launcher log copied to the clipboard.", "tes3np")
        return
    }
    if MsgBox("Delete the launcher log?", "tes3np — Launcher Logs", "YesNo Icon!") = "Yes"
        ClearLauncherLog()
}

ShowDiagnosticActions(*)
{
    choice := MsgBox("Yes: Open the AppData folder`nNo: Copy diagnostic information`nCancel: Return", "tes3np — Diagnostic Information", "YesNoCancel Icon?")
    if choice = "Yes"
        OpenLauncherDataFolder()
    else if choice = "No"
        CopyLauncherDiagnostics()
}

ShowResetAppDataActions(*)
{
    global AppDataDirectory
    choice := MsgBox("Yes: Open the AppData folder`nNo: Reset AppData`nCancel: Return", "tes3np — Reset AppData", "YesNoCancel Icon?")
    if choice = "Yes"
        return OpenLauncherDataFolder()
    if choice != "No"
        return
    warning := "This will delete all information inside tes3np AppData, including your saved characters and launcher settings.`n`nYou should export your character data before doing this.`n`nAre you sure you want to continue?"
    if MsgBox(warning, "tes3np — Reset AppData", "YesNo Icon!") != "Yes"
        return
    if MsgBox("This cannot be undone. Permanently reset tes3np AppData now?", "tes3np — Final Confirmation", "YesNo Icon!") != "Yes"
        return
    try DirDelete(AppDataDirectory, true)
    DirCreate(AppDataDirectory)
    MsgBox("AppData has been reset. Restart tes3np before continuing.", "tes3np — AppData Settings")
}
