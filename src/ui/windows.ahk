; Hide construction paints and reveal completed windows without changing their controls.

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
    ; A DWM-staged page paints its child HWNDs exactly once at RevealPaintedPage.
    ; Preserve the original button prepaint for callers without a cloak.
    if paintButtons
        FinishButtonDisplay()
    ; The book retains its transparent outside area; the launcher is fully opaque.
    DllCall("SetLayeredWindowAttributes", "Ptr", gui.Hwnd, "UInt", book ? 0xFF00FF : 0,
        "UChar", 255, "UInt", book ? 3 : 2)
}

; WinSetTransColor resolves a WinTitle first, and AHK does not reliably
; match a DWM-cloaked window by ahk_id. Set the same RGB color key directly
; against the already-created HWND; no lookup or activation is required.
SetPageColorKey(gui, colorRef)
{
    if !IsObject(gui) || !DllCall("IsWindow", "Ptr", gui.Hwnd)
        return false
    gui.Opt("+E0x80000") ; WS_EX_LAYERED
    return DllCall("SetLayeredWindowAttributes", "Ptr", gui.Hwnd,
        "UInt", colorRef, "UChar", 255, "UInt", 1, "Int") != 0 ; LWA_COLORKEY
}

; An ordinary hidden Show/WinSetTransColor is not enough to guarantee the
; *first composited frame* is ready. DWM can publish the background before
; AHK's child controls have received their WM_PAINT callbacks. Cloak the
; page before showing it, force its complete native paint while cloaked, then
; reveal the finished page as one desktop frame.
;
; Unlike alpha-zero, this also works for the Settings parchment which uses
; its own 010101 transparent color key. Do not cloak the launcher or ChatHost:
; those are already live and must remain visible through page handoffs.
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
    ; RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW.
    ; One synchronous native child paint before uncloaking. Avoid ERASE and
    ; the redundant UpdateWindow/second paint: Settings and the cached
    ; Character Book otherwise remain unresponsive for multiple seconds.
    DllCall("RedrawWindow", "Ptr", gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0181)
    SetPageCompositorCloak(gui, false)
}

; Child pages always open relative to the CURRENT owner rectangle, not their
; last/default Windows position. Use HWND geometry rather than a WinTitle lookup:
; Settings and Characters are deliberately DWM-cloaked during first paint.
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
    ; Work-area bounds belong to the owner monitor even if the pointer
    ; happened to be over a different screen when the user clicked.
    monitor := MonitorFromPoint(ox + ow // 2, oy + oh // 2)
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    x := Max(left, Min(right - mw, ox + (ow - mw) // 2))
    y := Max(top, Min(bottom - mh, oy + (oh - mh) // 2))
    ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE: reposition the hidden page
    ; without activating it or bypassing the approved first-frame protection.
    return DllCall("SetWindowPos", "Ptr", menu.Hwnd, "Ptr", 0,
        "Int", x, "Int", y, "Int", 0, "Int", 0,
        "UInt", 0x0015, "Int") != 0
}

; The launcher is already scaled by ApplyLauncherScaleToWindow. Child pages
; take the same effective percentage, NOT an independent "readability scale".
; Never recompute Auto from the mouse's monitor: that may differ from the
; monitor containing the already-moved launcher.
GetOwnedMenuScale()
{
    global LauncherScale
    return Max(0.5, Min(1.0, LauncherScale / 100))
}

; Native GUI controls do not inherit arbitrary parent scale changes.
; Rescale their real rectangles and font handles together, before first
; presentation or while the owned page is DWM-cloaked. This preserves the
; custom Morrowind/Segoe families, weights, colors and existing hit targets.
; Fonts created here stay alive until the page is rescaled or destroyed.
ScaleOwnedMenuContent(gui, scale)
{
    if !IsObject(gui) || !DllCall("IsWindow", "Ptr", gui.Hwnd)
        return
    scale := Max(0.5, Min(1.0, scale))
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

DestroyScaledMenu(gui)
{
    fonts := gui.HasOwnProp("OwnedGeneratedFonts") ? gui.OwnedGeneratedFonts : []
    gui.Destroy()
    for font in fonts
        DllCall("gdi32\DeleteObject", "Ptr", font)
    gui.OwnedGeneratedFonts := []
}
