; Stage first paint, position owned windows, and scale their native controls.

PrepareWindowDisplay(gui)
{
    ; Layered alpha hides construction paints while preserving the live controls.
    getter := A_PtrSize = 8 ? "GetWindowLongPtrW" : "GetWindowLongW"
    setter := A_PtrSize = 8 ? "SetWindowLongPtrW" : "SetWindowLongW"
    style := DllCall(getter, "Ptr", gui.Hwnd, "Int", -20, "Ptr")
    DllCall(setter, "Ptr", gui.Hwnd, "Int", -20, "Ptr", style | 0x80000, "Ptr")
    DllCall("SetLayeredWindowAttributes", "Ptr", gui.Hwnd, "UInt", 0, "UChar", 0, "UInt", 2)
}

RevealWindowDisplay(gui, book := false, paintButtons := true)
{
    ; DWM-staged pages paint their children in RevealPaintedPage.
    if paintButtons
        FinishButtonDisplay()
    ; The book retains its transparent outside area; the launcher is fully opaque.
    DllCall("SetLayeredWindowAttributes", "Ptr", gui.Hwnd, "UInt", book ? 0xFF00FF : 0,
        "UChar", 255, "UInt", book ? 3 : 2)
}

; Apply the color key by HWND so it works while the window is DWM-cloaked.
SetPageColorKey(gui, colorRef)
{
    if !IsObject(gui) || !DllCall("IsWindow", "Ptr", gui.Hwnd)
        return false
    gui.Opt("+E0x80000") ; WS_EX_LAYERED
    return DllCall("SetLayeredWindowAttributes", "Ptr", gui.Hwnd,
        "UInt", colorRef, "UChar", 255, "UInt", 1, "Int") != 0 ; LWA_COLORKEY
}

; Cloak pages while child controls paint so DWM presents the first frame complete.
; This preserves the Settings parchment's color key and keeps the launcher visible.
SetPageCompositorCloak(gui, cloak)
{
    if !IsObject(gui) || !DllCall("IsWindow", "Ptr", gui.Hwnd)
        return false
    value := Buffer(4, 0)
    NumPut("Int", cloak ? 1 : 0, value)
    try return DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", gui.Hwnd,
        "UInt", 13, "Ptr", value, "UInt", 4, "Int") = 0
    catch
        return false
}

RevealPaintedPage(gui)
{
    if !IsObject(gui) || !DllCall("IsWindow", "Ptr", gui.Hwnd)
        return
    ; RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW paints the controls before reveal.
    DllCall("RedrawWindow", "Ptr", gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0181)
    SetPageCompositorCloak(gui, false)
}

; Center the menu on its owner's current bounds, including while the menu is cloaked.
PositionOwnedMenuAtParent(menu, owner)
{
    if !IsObject(menu) || !DllCall("IsWindow", "Ptr", menu.Hwnd)
        return false
    ownerHwnd := IsObject(owner) ? owner.Hwnd : owner
    if !ownerHwnd || !DllCall("IsWindow", "Ptr", ownerHwnd)
        return false
    ownerRect := Buffer(16, 0), menuRect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", ownerHwnd, "Ptr", ownerRect)
        || !DllCall("GetWindowRect", "Ptr", menu.Hwnd, "Ptr", menuRect)
        return false
    ox := NumGet(ownerRect, 0, "Int"), oy := NumGet(ownerRect, 4, "Int")
    ow := NumGet(ownerRect, 8, "Int") - ox
    oh := NumGet(ownerRect, 12, "Int") - oy
    mw := NumGet(menuRect, 8, "Int") - NumGet(menuRect, 0, "Int")
    mh := NumGet(menuRect, 12, "Int") - NumGet(menuRect, 4, "Int")
    if mw <= 0 || mh <= 0 || ow <= 0 || oh <= 0
        return false
    ; Clamp to the owner's monitor work area.
    monitor := MonitorFromPoint(ox + ow // 2, oy + oh // 2)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    x := Max(left, Min(right - mw, ox + (ow - mw) // 2))
    y := Max(top, Min(bottom - mh, oy + (oh - mh) // 2))
    ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE.
    return DllCall("SetWindowPos", "Ptr", menu.Hwnd, "Ptr", 0,
        "Int", x, "Int", y, "Int", 0, "Int", 0,
        "UInt", 0x0015, "Int") != 0
}

; Owned menus inherit the scale already applied to the launcher.
GetOwnedMenuScale()
{
    global LauncherScale
    return Max(0.1, Min(1.0, LauncherScale / 100))
}

GetOwnedMenuFitScale(owner, width, height, horizontalMargin := 24, verticalMargin := 24)
{
    WinGetPos(&x, &y, &w, &h, "ahk_id " owner.Hwnd)
    monitor := MonitorFromPoint(x + w // 2, y + h // 2)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    return Max(0.1, Min(1.0, (right - left - horizontalMargin) / width,
        (bottom - top - verticalMargin) / height))
}

; Scale child bounds and fonts together to keep text aligned with hit targets.
; Keep generated fonts alive while the controls use them.

; Shared text measurement for future accessibility-aware layout passes.
; Uses the *current native font* instead of assuming a character/line count.
; Read-only: this helper never changes a window rectangle or font. A caller
; must first establish that the entire view can accommodate a reflow.
MeasureAccessibleWrappedText(control, caption, width)
{
    if !IsObject(control) || !DllCall("IsWindow", "Ptr", control.Hwnd)
        throw Error("Cannot measure a missing interface text control.")
    dc := DllCall("user32\GetDC", "Ptr", control.Hwnd, "Ptr")
    if !dc
        throw Error("Cannot acquire interface text metrics.")
    previous := 0
    try
    {
        font := DllCall("user32\SendMessageW", "Ptr", control.Hwnd,
            "UInt", 0x31, "Ptr", 0, "Ptr", 0)
        if font
            previous := DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
        bounds := Buffer(16, 0)
        NumPut("Int", 0, "Int", 0, "Int", Max(1, Round(width)), "Int", 0, bounds)
        ; DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX.
        if !DllCall("user32\DrawTextW", "Ptr", dc, "WStr", caption, "Int", -1,
            "Ptr", bounds, "UInt", 0xC10)
            throw Error("Failed to measure wrapped interface text.")
        return NumGet(bounds, 12, "Int")
    }
    finally
    {
        if previous
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", previous, "Ptr")
        DllCall("user32\ReleaseDC", "Ptr", control.Hwnd, "Ptr", dc)
    }
}


; Pure geometry preflight for text-aware native layouts. Callers provide
; actual measured text heights, then check Feasible BEFORE moving any HWND.
; Items: {Id, Height, MinimumHeight, GapAfter, MinimumTop}.
; This does NOT change any control, font, button face or cached book state.
PlanAccessibleVerticalStack(items, top, availableBottom)
{
    if top < 0 || availableBottom < top
        throw Error("Invalid accessible layout bounds.")
    result := []
    cursor := top
    for item in items
    {
        if !IsObject(item) || !item.HasOwnProp("Id") || !item.HasOwnProp("Height")
            throw Error("Missing accessible layout item fields.")
        minimum := item.HasOwnProp("MinimumHeight") ? item.MinimumHeight : 0
        gap := item.HasOwnProp("GapAfter") ? item.GapAfter : 0
        minimumTop := item.HasOwnProp("MinimumTop") ? item.MinimumTop : 0
        if item.Height < 0 || minimum < 0 || gap < 0 || minimumTop < 0
            throw Error("Negative accessible layout measurement.")
        cursor := Max(cursor, minimumTop)
        height := Max(item.Height, minimum)
        result.Push({Id: item.Id, Top: cursor, Bottom: cursor + height,
            Height: height})
        cursor += height + gap
    }
    neededBottom := top
    for entry in result
        neededBottom := Max(neededBottom, entry.Bottom)
    overflow := Max(0, neededBottom - availableBottom)
    return {Feasible: overflow = 0, Items: result, NeededBottom: neededBottom,
        AvailableBottom: availableBottom, Overflow: overflow}
}


; Pure native draft of the complete Character + Macro Book geometry. This
; matches the offline Python feasibility model; it never moves HWNDs.
; The caller must measure actual text heights first, and only APPLY a
; feasible plan after considering any additional editor/overlay controls.
PlanAccessibleBookGeometry(descriptionHeight, macroTextHeight,
    characterRowHeight, macroRowHeight, workWidth, workHeight,
    characterCount := 10, macroCount := 4, showLimitNotice := false)
{
    if Min(descriptionHeight, macroTextHeight, characterRowHeight,
        macroRowHeight, workWidth, workHeight, characterCount, macroCount) < 0
        throw Error("Invalid Character Book measurements.")
    if characterCount > 10 || macroCount > 4
        throw Error("Character Book has more rows than existing controls.")
    characterPitch := Max(24, characterRowHeight + 1)
    macroPitch := Max(70, macroRowHeight + 8)
    descriptionBottom := 80 + Max(81, descriptionHeight)
    characterTop := Max(164, descriptionBottom + 3)
    characterBottom := characterCount
        ? characterTop + (characterCount - 1) * characterPitch + characterRowHeight
        : characterTop
    noticeTop := showLimitNotice ? Max(429, characterBottom + 8) : 0
    noticeBottom := showLimitNotice ? noticeTop + 25 : 0
    addTop := characterCount ? Max(540, characterBottom + 10, noticeBottom + 10)
        : Max(164, descriptionBottom + 3)
    leftActionBottom := characterCount ? addTop + 30 : addTop + 65
    macroTextBottom := 87 + Max(48, macroTextHeight)
    macroTop := Max(140, macroTextBottom + 5)
    macroBottom := macroCount
        ? macroTop + (macroCount - 1) * macroPitch + macroRowHeight
        : macroTop
    uploadTop := Max(188, macroBottom + 8)
    footerTop := Max(575, leftActionBottom + 5, uploadTop + 37)
    pageHeight := Max(650, footerTop + 75)
    fits := workWidth >= 960 && workHeight >= pageHeight
    return {Feasible: fits, Width: 960, Height: fits ? pageHeight : 0,
        RequiredHeight: pageHeight, CharacterTop: characterTop,
        CharacterPitch: characterPitch, CharacterBottom: characterBottom,
        AddTop: addTop, ImportTop: characterCount ? 0 : addTop + 35,
        NoticeTop: noticeTop, NoticeBottom: noticeBottom,
        WipeTop: characterCount ? footerTop + 2 : 0,
        MacroTop: macroTop, MacroPitch: macroPitch,
        MacroBottom: macroBottom, UploadTop: uploadTop, FooterTop: footerTop}
}

ScaleOwnedMenuContent(gui, scale)
{
    if !IsObject(gui) || !DllCall("IsWindow", "Ptr", gui.Hwnd)
        return
    scale := Max(0.1, Min(1.0, scale))
    previous := gui.HasOwnProp("OwnedContentScale") ? gui.OwnedContentScale : 1.0
    if Abs(previous - scale) < 0.001
        return
    ratio := scale / previous
    previousFonts := gui.HasOwnProp("OwnedGeneratedFonts") ? gui.OwnedGeneratedFonts : []
    newFonts := [], fontCache := Map(), retainedFonts := Map()
    ; Record allocations before assigning them to native controls. A partial
    ; resize must still leave the page owning both generations of fonts.
    ownedFonts := previousFonts.Clone()
    gui.OwnedGeneratedFonts := ownedFonts
    ; Suppress intermediate parent paints while button geometry/fonts change.
    visible := DllCall("IsWindowVisible", "Ptr", gui.Hwnd)
    if visible
        DllCall("SendMessageW", "Ptr", gui.Hwnd, "UInt", 0x000B, "Ptr", 0, "Ptr", 0)
    try
    {
        for control in gui
        {
            if !DllCall("IsWindow", "Ptr", control.Hwnd)
                continue
            control.GetPos(&cx, &cy, &cw, &ch)
            control.Move(Round(cx * ratio), Round(cy * ratio),
                Max(1, Round(cw * ratio)), Max(1, Round(ch * ratio)))
            oldFont := DllCall("SendMessageW", "Ptr", control.Hwnd,
                "UInt", 0x0031, "Ptr", 0, "Ptr", 0, "Ptr") ; WM_GETFONT
            if !oldFont
                continue
            if !fontCache.Has(oldFont)
            {
                definition := Buffer(92, 0) ; LOGFONTW
                if DllCall("gdi32\GetObjectW", "Ptr", oldFont,
                    "Int", definition.Size, "Ptr", definition, "Int") < 92
                {
                    retainedFonts[oldFont] := true
                    continue
                }
                height := NumGet(definition, 0, "Int")
                if height = 0
                {
                    retainedFonts[oldFont] := true
                    continue
                }
                NumPut("Int", Round(height * ratio), definition, 0)
                NumPut("Int", 0, definition, 4) ; let GDI derive font width
                scaledFont := DllCall("gdi32\CreateFontIndirectW",
                    "Ptr", definition, "Ptr")
                if !scaledFont
                {
                    retainedFonts[oldFont] := true
                    continue
                }
                fontCache[oldFont] := scaledFont
                ownedFonts.Push(scaledFont)
                newFonts.Push(scaledFont)
            }
            ; WM_SETFONT, redraw=0; RevealPaintedPage handles one final paint.
            DllCall("SendMessageW", "Ptr", control.Hwnd, "UInt", 0x0030,
                "Ptr", fontCache[oldFont], "Ptr", 0)
        }
    }
    finally
    {
        if visible
            DllCall("SendMessageW", "Ptr", gui.Hwnd, "UInt", 0x000B,
                "Ptr", 1, "Ptr", 0)
    }
    for font in previousFonts
        if retainedFonts.Has(font)
            newFonts.Push(font)
        else
            DllCall("gdi32\DeleteObject", "Ptr", font)
    gui.OwnedGeneratedFonts := newFonts
    gui.OwnedContentScale := scale
}

; Character Book is cached after Close. A saved Interface Text change must
; also update this hidden menu when it is next opened, without rebuilding
; its macro/editor data or shifting any control rectangles.
RefreshCachedBookTextPreference(book)
{
    global AccessibilityTextSize
    if !IsObject(book) || !DllCall("IsWindow", "Ptr", book.Hwnd)
        return
    previous := book.HasOwnProp("InterfaceFontMode") ? book.InterfaceFontMode : AccessibilityTextSize
    if previous = AccessibilityTextSize
        return
    ratio := AccessibilityFontMultiplier() / AccessibilityFontMultiplier(previous)
    previousFonts := book.HasOwnProp("OwnedGeneratedFonts") ? book.OwnedGeneratedFonts : []
    generated := previousFonts.Clone()
    book.OwnedGeneratedFonts := generated
    nextFonts := [], retainedFonts := Map(), fontCache := Map()
    for control in book
    {
        if !DllCall("IsWindow", "Ptr", control.Hwnd)
            continue
        oldFont := DllCall("SendMessageW", "Ptr", control.Hwnd,
            "UInt", 0x0031, "Ptr", 0, "Ptr", 0, "Ptr")
        if !oldFont
            continue
        if !fontCache.Has(oldFont)
        {
            definition := Buffer(92, 0)
            if DllCall("gdi32\GetObjectW", "Ptr", oldFont, "Int", definition.Size,
                "Ptr", definition, "Int") < 92
            {
                retainedFonts[oldFont] := true
                continue
            }
            height := NumGet(definition, 0, "Int")
            if !height
            {
                retainedFonts[oldFont] := true
                continue
            }
            NumPut("Int", (height < 0 ? -1 : 1) * Max(1, Round(Abs(height) * ratio)),
                definition, 0)
            NumPut("Int", 0, definition, 4)
            nextFont := DllCall("gdi32\CreateFontIndirectW", "Ptr", definition, "Ptr")
            if !nextFont
            {
                retainedFonts[oldFont] := true
                continue
            }
            fontCache[oldFont] := nextFont
            generated.Push(nextFont)
            nextFonts.Push(nextFont)
        }
        if fontCache.Has(oldFont)
            DllCall("SendMessageW", "Ptr", control.Hwnd, "UInt", 0x0030,
                "Ptr", fontCache[oldFont], "Ptr", 0)
    }
    for font in previousFonts
    {
        if retainedFonts.Has(font)
            nextFonts.Push(font)
        else
            DllCall("gdi32\DeleteObject", "Ptr", font)
    }
    book.OwnedGeneratedFonts := nextFonts
    book.InterfaceFontMode := AccessibilityTextSize
}

DestroyScaledMenu(gui)
{
    fonts := gui.HasOwnProp("OwnedGeneratedFonts") ? gui.OwnedGeneratedFonts : []
    gui.Destroy()
    for font in fonts
        DllCall("gdi32\DeleteObject", "Ptr", font)
    gui.OwnedGeneratedFonts := []
}
