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

RevealWindowDisplay(gui, book := false)
{
    FinishButtonDisplay()
    ; The book retains its transparent outside area; the launcher is fully opaque.
    DllCall("SetLayeredWindowAttributes", "Ptr", gui.Hwnd, "UInt", book ? 0xFF00FF : 0,
        "UChar", 255, "UInt", book ? 3 : 2)
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
    ; RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW.
    ; Complete the native and themed paints before removing DWM's cloak.
    DllCall("RedrawWindow", "Ptr", gui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0185)
    DllCall("UpdateWindow", "Ptr", gui.Hwnd)
    SetPageCompositorCloak(gui, false)
}
