; v0.1.16 test-branch UI refinements.

global V016CharacterLayoutApplied := false
global V016SettingsGuiHwnd := 0
global V016SettingsScale := 1.0
global V016ReadabilityState := 0
global V016FollowWindowsState := 0
global V016DailyLoginControls := []

InitializeV016UiRefinements()
{
    ; Character layout is applied explicitly when the Character Book is built or
    ; refreshed. Do not wake the launcher four times per second just to discover
    ; that the layout has already been applied.
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

    ; Standard Windows controls cannot use Morrowind's .fnt/.tex bitmap face.
    ; Load the bundled OpenMW-compatible TrueType face for native controls so
    ; the settings page uses one font instead of mixing bitmap, Georgia and Segoe UI.
    nativeFontPath := A_ScriptDir "\\assets\\fonts\\MysticCards.ttf"
    LauncherMorrowindFontPath := nativeFontPath
    if FileExist(nativeFontPath)
    {
        try
        {
            if DllCall("Gdi32.dll\AddFontResourceExW", "Str", nativeFontPath, "UInt", 0x10, "Ptr", 0, "Int") > 0
            {
                LauncherMorrowindFont := "Mystic Cards"
                LauncherMorrowindFontLoaded := true
            }
        }
    }

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
        if !IsObject(file) || file.Length < 296 + (256 * 56)
            return false
        sizeBuf := Buffer(4)
        file.RawRead(sizeBuf, 4)
        fontSize := NumGet(sizeBuf, 0, "Float")
        file.Pos := 296
        glyphs := []
        Loop 256
        {
            g := Buffer(56)
            if file.RawRead(g, 56) != 56
                return false
            glyphs.Push({
                TopLeftX: NumGet(g, 4, "Float"), TopLeftY: NumGet(g, 8, "Float"),
                TopRightX: NumGet(g, 12, "Float"), TopRightY: NumGet(g, 16, "Float"),
                BottomLeftX: NumGet(g, 20, "Float"), BottomLeftY: NumGet(g, 24, "Float"),
                BottomRightX: NumGet(g, 28, "Float"), BottomRightY: NumGet(g, 32, "Float"),
                Width: NumGet(g, 36, "Float"),
                Height: NumGet(g, 40, "Float"),
                KerningLeft: NumGet(g, 44, "Float"),
                KerningRight: NumGet(g, 48, "Float"),
                Ascent: NumGet(g, 52, "Float")
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
        glyph := LauncherMagicCardsData.Glyphs[code + 1]
        width += (glyph.Width + glyph.KerningRight) * scale
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
        advance := (glyph.Width + glyph.KerningRight) * scale
        run.Push({
            Code: code,
            X: penX + (glyph.KerningLeft * scale),
            Y: y + ((LauncherMagicCardsData.FontSize - glyph.Ascent) * scale),
            Height: height, Advance: advance,
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


MagicCardsWrapText(text, maxWidth, fontHeight)
{
    global LauncherMagicCardsData
    if !IsObject(LauncherMagicCardsData)
        return [text]

    scale := fontHeight / LauncherMagicCardsData.FontSize
    words := StrSplit(text, " ")
    lines := []
    line := ""
    for word in words
    {
        candidate := line = "" ? word : line " " word
        if line != "" && MagicCardsMeasureText(candidate, scale) > maxWidth
        {
            lines.Push(line)
            line := word
        }
        else
            line := candidate
    }
    if line != ""
        lines.Push(line)
    return lines.Length ? lines : [""]
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
    scale := fontHeight / LauncherMagicCardsData.FontSize
    lines := MagicCardsWrapText(text, width, fontHeight)
    lineHeight := Max(1, Round(fontHeight * 1.15))
    run := []
    lineY := 0
    for line in lines
    {
        if lineY >= height
            break
        runWidth := MagicCardsMeasureText(line, scale)
        penX := center ? Max(0, Floor((width - runWidth) / 2)) : 0
        lineRun := MagicCardsGlyphRun(line, penX, lineY, fontHeight)
        if IsObject(lineRun)
            for item in lineRun
                run.Push(item)
        lineY += lineHeight
    }

    for item in run
    {
        glyph := LauncherMagicCardsData.Glyphs[item.Code + 1]
        src := MagicCardsGlyphSourceRect(glyph, atlas.Width, atlas.Height)
        scale := fontHeight / LauncherMagicCardsData.FontSize
        dstW := Max(1, Round(glyph.Width * scale))
        dstH := Max(1, Round(glyph.Height * scale))
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
                ; Windows 32-bit DIB pixels are BGRA.
                NumPut("UChar", color & 0xFF, out, dstOff)
                NumPut("UChar", (color >> 8) & 0xFF, out, dstOff + 1)
                NumPut("UChar", (color >> 16) & 0xFF, out, dstOff + 2)
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
    try
        pic := gui.Add("Picture", "x" x " y" y " w" w " h" h " BackgroundTrans", "HBITMAP:*" hbm)
    finally
        ; The Picture control copies the supplied HBITMAP. The temporary bitmap
        ; returned by the vanilla-font renderer remains ours and must be released.
        DllCall("DeleteObject", "Ptr", hbm)
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
    global LauncherMorrowindFontLoaded, LauncherMorrowindFontPath, LauncherMagicCardsFnt, LauncherMagicCardsTex, LauncherMagicCardsData
    if LauncherMorrowindFontLoaded && LauncherMorrowindFontPath != ""
        try DllCall("Gdi32.dll\RemoveFontResourceExW", "Str", LauncherMorrowindFontPath, "UInt", 0x10, "Ptr", 0)
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

    settings.SetFont("s" V016Font(19) " Norm c241408", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(70) " y" V016S(121) " w" V016S(370) " h" V016S(34) " Center BackgroundTrans", "Launcher Settings")

    settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(169) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Launcher size")
    ; Native dropdowns cannot display the proprietary bitmap face directly.
    ; Keep their interactive chrome native, but use a neutral system font so
    ; they no longer inherit the old Georgia/MysticCards approximation.
    settings.SetFont("s" V016Font(12) " Norm c241408", LauncherMorrowindFont)
    choices := ["Automatic (Recommended)", "50%", "60%", "70%", "80%", "90%", "100%"]
    choice := LauncherScaleMode = "Auto" ? 1 : ScaleChoiceIndex(LauncherScale) + 1
    scaleList := settings.Add("DropDownList", "x" V016S(184) " y" V016S(164) " w" V016S(296) " Choose" choice, choices)
    settings.SetFont("s" V016Font(11) " Norm c382314", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(196) " w" V016S(448) " h" V016S(40) " BackgroundTrans", "Automatic scaling is recommended. tes3np stays at full size when possible and shrinks only when needed.")

    settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(242) " w" V016S(145) " h" V016S(24) " BackgroundTrans", "Interface text")
    settings.SetFont("s" V016Font(12) " Norm c241408", LauncherMorrowindFont)
    textChoices := ["Normal", "Large", "Extra Large"]
    textChoice := AccessibilityTextSize = "Large" ? 2 : AccessibilityTextSize = "Extra Large" ? 3 : 1
    textList := settings.Add("DropDownList", "x" V016S(184) " y" V016S(237) " w" V016S(296) " Choose" textChoice, textChoices)
    settings.SetFont("s" V016Font(11) " Norm c382314", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(32) " y" V016S(269) " w" V016S(448) " h" V016S(30) " BackgroundTrans", "Choose how big or small the launcher interface is for you.")

    settings.SetFont("s" V016Font(13) " Norm c241408", LauncherMorrowindFont)
    readabilityPrefix := V016ReadabilityState ? "☑" : "■"
    readability := settings.Add("Text", "x" V016S(32) " y" V016S(305) " w" V016S(448) " h" V016S(32) " +0x100 BackgroundTrans", readabilityPrefix "  Enhanced readability")
    readability.OnEvent("Click", ToggleV016ReadabilityControl.Bind(readability))
    settings.SetFont("s" V016Font(11) " Norm c382314", LauncherMorrowindFont)
    settings.Add("Text", "x" V016S(70) " y" V016S(335) " w" V016S(410) " h" V016S(42) " BackgroundTrans", "Improves readability by providing stronger contrast and brighter button text.")

    readabilityValue := {Value: V016ReadabilityState}
    followWindowsValue := {Value: FollowWindowsAccessibility ? 1 : 0}
    reduceMotionBox := {Value: 0}

    AddStyledButton(settings, V016S(32), V016S(387), V016S(214), V016S(30), "Preview Changes", ApplyV016LauncherSettings.Bind(settings, scaleList, textList, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(266), V016S(387), V016S(214), V016S(30), "Reset Changes", ResetLauncherSettingsV016.Bind(settings, scaleList, textList, readability, readabilityValue, reduceMotionBox, followWindowsValue))
    AddStyledButton(settings, V016S(32), V016S(435), V016S(214), V016S(30), "Launcher Data", OpenAppDataSettingsV016.Bind(settings))
    AddStyledButton(settings, V016S(266), V016S(435), V016S(214), V016S(30), "Game Client Settings", OpenClientSelectionSettings)
    AddStyledButton(settings, V016S(32), V016S(483), V016S(448), V016S(30), "Close Settings", CloseLauncherSettingsV016.Bind(settings))

    ; Keep both parchment views in the same GUI. The common backdrop is never
    ; destroyed, and all data controls are created only once per settings window.
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    V016SettingsMainControls := []
    for control in settings
        V016SettingsMainControls.Push(control)
    V016SettingsDataControls := []
    V016SettingsDataActive := false

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
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    V016SettingsDataActive := false
    V016SettingsMainControls := []
    V016SettingsDataControls := []
    try settings.Destroy()
    if IsObject(LauncherGui) && DllCall("IsWindow", "Ptr", LauncherGui.Hwnd, "Int")
    {
        DllCall("EnableWindow", "Ptr", LauncherGui.Hwnd, "Int", 1)
        WinActivate("ahk_id " LauncherGui.Hwnd)
    }
}

V016CheckLabel(state, label)
{
    return (state ? "☑" : "■") "  " label
}

ToggleV016ReadabilityControl(control, *)
{
    global V016ReadabilityState
    V016ReadabilityState := !V016ReadabilityState
    UpdateV016ReadabilityLabel(control, V016ReadabilityState)
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
            symbol := V016ReadabilityState ? "☑" : "■"
            controls := WinGetControls("ahk_id " hwnd)
            for ctl in controls
                try if InStr(ControlGetText(ctl, "ahk_id " hwnd), "■") || InStr(ControlGetText(ctl, "ahk_id " hwnd), "☑")
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

OpenAppDataSettingsV016(settings, *)
{
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    global LauncherMorrowindFont
    if !IsObject(settings) || !DllCall("IsWindow", "Ptr", settings.Hwnd)
        return
    if V016SettingsDataActive
        return
    ; Snapshot the current parchment and suspend redraw while controls change.
    ; Quick cached transitions keep the old frame, without a loading card.
    BeginInterfaceUpdate(settings, "Opening Launcher Data...", false)
    try
    {
    ; Create the second view once. A return visit simply toggles visibility.
    if V016SettingsDataControls.Length = 0
    {
        before := Map()
        for control in settings
            before[control.Hwnd] := true
        settings.SetFont("s" V016Font(17) " Norm c241408", LauncherMorrowindFont)
        settings.Add("Text", "x" V016S(32) " y" V016S(126) " w" V016S(448) " h" V016S(32) " Center BackgroundTrans", "Launcher Data & Diagnostics")
        settings.SetFont("s" V016Font(10) " Norm c382314", LauncherMorrowindFont)
        settings.Add("Text", "x" V016S(42) " y" V016S(168) " w" V016S(428) " h" V016S(91) " BackgroundTrans",
            "Your characters and preferences are stored in AppData. Export your characters from Manage Characters before resetting anything. If the game closes unexpectedly, copy the launcher log and share the lines around the failure.")
        AddStyledButton(settings, V016S(32), V016S(268), V016S(448), V016S(30), "Open Launcher AppData Folder", OpenLauncherDataFolder)
        AddStyledButton(settings, V016S(32), V016S(309), V016S(448), V016S(30), "Copy Launcher Logs", CopyAppDataLog.Bind("launcher.log", true))
        settings.SetFont("s" V016Font(11) " Norm c241408", LauncherMorrowindFont)
        settings.Add("Text", "x" V016S(32) " y" V016S(353) " w" V016S(448) " h" V016S(24) " BackgroundTrans", "Advanced Diagnostic Logs")
        AddStyledButton(settings, V016S(32), V016S(385), V016S(448), V016S(30), "Reset Launcher AppData", ShowResetAppDataActions)
        AddStyledButton(settings, V016S(32), V016S(426), V016S(214), V016S(30), "Copy Expansion Pack Logs", CopyExpansionPackLogs)
        AddStyledButton(settings, V016S(266), V016S(426), V016S(214), V016S(30), "Copy Render Errors", CopyAppDataLog.Bind("render-errors.log"))
        AddStyledButton(settings, V016S(32), V016S(483), V016S(448), V016S(30), "Go Back", CloseLauncherDataV016.Bind(settings))
        for control in settings
            if !before.Has(control.Hwnd)
                V016SettingsDataControls.Push(control)
    }
    ; Hide only the main view; keep the shared parchment picture visible.
    V016SettingsDataActive := true
    for index, control in V016SettingsMainControls
        if index > 1
            SetBookControlVisible(control, false)
    for control in V016SettingsDataControls
        SetBookControlVisible(control, true)
    ; EndInterfaceUpdate performs the single final redraw under the frame cover.
    }
    finally EndInterfaceUpdate()
}

CloseLauncherDataV016(settings, *)
{
    global V016SettingsMainControls, V016SettingsDataControls, V016SettingsDataActive
    if !V016SettingsDataActive || !DllCall("IsWindow", "Ptr", settings.Hwnd)
        return
    BeginInterfaceUpdate(settings, "Returning to Launcher Settings...", false)
    try
    {
    for control in V016SettingsDataControls
        SetBookControlVisible(control, false)
    for index, control in V016SettingsMainControls
        if index > 1
            SetBookControlVisible(control, true)
    V016SettingsDataActive := false
    ; EndInterfaceUpdate performs the single final redraw under the frame cover.
    }
    finally EndInterfaceUpdate()
}

CopyExpansionPackLogs(*)
{
    global AppDataDirectory
    ; Both logs are retained separately on disk. The clipboard gets a
    ; clearly labeled combined report, including any missing-file notices.
    try SyncPatchLogToLauncherLog()
    report := ""
    found := false
    for filename in ["patch-all.log", "patch-errors.log"]
    {
        path := AppDataDirectory "\" filename
        report .= "===== " filename " =====`r`n"
        if FileExist(path)
        {
            try
            {
                content := FileRead(path, "UTF-8")
                if Trim(content) != ""
                {
                    report .= content "`r`n`r`n"
                    found := true
                    continue
                }
            }
            catch Error as err
            {
                report .= "Could not read file: " err.Message "`r`n`r`n"
                continue
            }
        }
        report .= "(No entries available)`r`n`r`n"
    }
    if !found
    {
        MsgBox("No Expansion Pack log entries are available yet.", "tes3np — Diagnostics")
        return
    }
    A_Clipboard := report
    MsgBox("Expansion Pack logs copied to your clipboard. Review personal paths before sharing.", "tes3np — Diagnostics")
}

CopyAppDataLog(filename, syncLauncher := false, *)
{
    global AppDataDirectory
    if syncLauncher
        SyncPatchLogToLauncherLog()
    path := AppDataDirectory "\" filename
    if !FileExist(path)
    {
        MsgBox("No " filename " has been created yet. This usually means there are no recorded events of that type.", "tes3np — Diagnostics")
        return
    }
    try
    {
        content := FileRead(path, "UTF-8")
        if Trim(content) = ""
        {
            MsgBox("The diagnostic log is empty.", "tes3np — Diagnostics")
            return
        }
        if filename = "launcher.log"
        {
            ; Put the most recent game exit at the top, but retain the full
            ; original chronological log below for developer investigation.
            recentExit := ""
            for line in StrSplit(content, "`n", "`r")
                if InStr(line, "GAME | EXIT |")
                    recentExit := line
            if recentExit != ""
            {
                ; Query only the Windows crash event around this specific exit,
                ; never unrelated recent Application Error entries.
                eventDetails := FindTes3mpWindowsCrash(recentExit)
                content := "===== MOST RECENT TES3MP EXIT =====`r`n" recentExit
                    . "`r`n`r`n===== WINDOWS TES3MP CRASH DETAILS =====`r`n" eventDetails
                    . "`r`n`r`n===== COMPLETE LAUNCHER LOG =====`r`n" content
            }

        }
        A_Clipboard := content
    }
    catch Error as err
    {
        MsgBox("Could not read " filename ".`n`n" err.Message, "tes3np — Diagnostics", "Icon!")
        return
    }
    MsgBox("Diagnostic log copied to your clipboard.`n`nYou can paste it into a bug report. Review the contents first in case paths or character names are private.", "tes3np — Diagnostics")
}

FindTes3mpWindowsCrash(exitLine)
{
    global AppDataDirectory
    ; Windows writes Event ID 1000 asynchronously. This query is performed
    ; only on Copy Launcher Logs, not on the UI watchdog's timing-critical path.
    if StrLen(exitLine) < 19
        return "Crash event unavailable: missing exit timestamp."
    timestamp := SubStr(exitLine, 1, 19)
    scriptPath := AppDataDirectory "\tes3mp-crash-query.ps1"
    resultPath := AppDataDirectory "\tes3mp-crash-query.txt"
    script := "
    (
param([string]$Stamp, [string]$OutputFile)
try {
    $target = [datetime]::ParseExact($Stamp, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    $events = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$target.AddMinutes(-1); EndTime=$target.AddMinutes(2)} -ErrorAction Stop
    $match = $events | Where-Object { $_.Message -match '(?i)(^|[^a-z0-9_-])tes3mp[.]exe([^a-z0-9_-]|$)' } | Sort-Object TimeCreated -Descending | Select-Object -First 1
    if ($match) {
        $lines = @('Windows Application Error (Event ID 1000)', 'Recorded: ' + $match.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), 'Source: ' + $match.ProviderName, $match.Message)
        [IO.File]::WriteAllText($OutputFile, ($lines -join [Environment]::NewLine), [Text.Encoding]::UTF8)
    } else {
        [IO.File]::WriteAllText($OutputFile, 'No matching Windows Application Error (Event ID 1000) was found for this TES3MP exit. A normal exit or an exception handled by the process may not create one.', [Text.Encoding]::UTF8)
    }
} catch {
    [IO.File]::WriteAllText($OutputFile, 'Windows crash details unavailable: ' + $_.Exception.Message, [Text.Encoding]::UTF8)
}
    )"
    try
    {
        DirCreate(AppDataDirectory)
        if FileExist(resultPath)
            FileDelete(resultPath)
        if FileExist(scriptPath)
            FileDelete(scriptPath)
        FileAppend(script, scriptPath, "UTF-8")
        ; No shell interpolation: quote the time and paths as separate arguments.
        command := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' scriptPath '" "' timestamp '" "' resultPath '"'
        RunWait(command, , "Hide")
        if FileExist(resultPath)
            return Trim(FileRead(resultPath, "UTF-8"))
        return "Windows crash diagnostics could not be retrieved."
    }
    catch Error as err
        return "Windows crash diagnostics unavailable: " err.Message
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

OpenClientSelectionSettings(*)
{
    global DataFile, AppDataDirectory, ExecutableInput
    mode := IniRead(DataFile, "Launch", "ClientMode", "Bundled")
    savedOverrides := FileExist(GetCustomOverrideFolder() "\tes3mp.exe")
    question := "Current client: " mode Chr(10) Chr(10)
        . "Yes - Use original bundled runtime" Chr(10)
        . "No - Configure custom EXE and optional dependencies" Chr(10)
        . "Cancel - More options / keep current client"
    answer := MsgBox(question, "Game Client Settings", "YesNoCancel Icon?")
    if answer = "Cancel"
    {
        if savedOverrides
        {
            reuse := MsgBox("Previously saved custom EXE and dependencies were found." Chr(10) Chr(10)
                . "Yes - Reactivate saved custom overrides" Chr(10)
                . "No - Keep current selection", "Saved Custom Client", "YesNo Icon?")
            if reuse = "Yes"
            {
                IniWrite("CustomOverrides", DataFile, "Launch", "ClientMode")
                try ExecutableInput.Value := GetCustomOverrideFolder() "\tes3mp.exe (custom overrides)"
                LogLauncherEvent("GAME | Saved custom runtime overrides reactivated.")
            }
        }
        return
    }
    if answer = "Yes"
    {
        ; Do not delete overrides. Restoring the original is reversible.
        IniWrite("Bundled", DataFile, "Launch", "ClientMode")
        try ExecutableInput.Value := A_ScriptDir "\client\tes3mp.exe"
        LogLauncherEvent("GAME | Original bundled runtime restored as active client.")
        MsgBox("The original bundled runtime is active again. Custom override files are preserved separately.", "Game Client")
        return
    }
    source := FileSelect(1, , "Choose custom tes3mp.exe", "Executable (*.exe)")
    if source = ""
        return
    SplitPath(source, &filename)
    if StrLower(filename) != "tes3mp.exe" || !FileExist(source)
    {
        MsgBox("Please choose a file named tes3mp.exe.", "Game Client", "Icon!")
        return
    }
    choice := MsgBox("Include additional custom DLLs, configuration files, or resources?" Chr(10)
        . "Yes - Choose a dependencies folder" Chr(10)
        . "No - Use the custom EXE with bundled dependencies" Chr(10)
        . "Cancel - Keep current settings", "Optional Dependencies", "YesNoCancel Icon?")
    if choice = "Cancel"
        return
    folder := ""
    if choice = "Yes"
    {
        folder := DirSelect(, 3, "Choose optional dependencies folder")
        if folder = ""
            return
    }
    if !PrepareMarkerlessClientRuntime()
        return
    if !InstallCustomClientOverrides(source, folder)
        return
    DirCreate(AppDataDirectory)
    IniWrite("CustomOverrides", DataFile, "Launch", "ClientMode")
    try ExecutableInput.Value := GetCustomOverrideFolder() "\tes3mp.exe (custom overrides)"
    MsgBox("Custom EXE and optional dependencies are now authoritative in a separate managed folder. TES3NP will merge them into a disposable copy of the bundled runtime at launch." Chr(10) Chr(10)
        . "The original runtime remains untouched; Restore Original switches back immediately.", "Game Client")
}
