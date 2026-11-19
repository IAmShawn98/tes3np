; Owner dimming, centering, and cleanup for the launcher's gold prompts.

CreateGoldPromptBackdrop(owner := 0)
{
    global LauncherGui
    ; Use the owner's physical bounds so the dimmer stays aligned at mixed DPI.
    if !owner
        owner := LauncherGui
    ownerHwnd := IsObject(owner) ? owner.Hwnd : owner
    bounds := Buffer(16, 0)
    if !ownerHwnd || !DllCall("user32\GetWindowRect", "Ptr", ownerHwnd, "Ptr", bounds)
        throw Error("Unable to locate owner for native prompt backdrop.")
    lx := NumGet(bounds, 0, "Int")
    ly := NumGet(bounds, 4, "Int")
    lw := NumGet(bounds, 8, "Int") - lx
    lh := NumGet(bounds, 12, "Int") - ly
    dim := Gui("-Caption -Border -DPIScale +ToolWindow +Owner" ownerHwnd, "tes3np Native Prompt Backdrop")
    dim.BackColor := "000000"
    try {
        dim.Show("NA x" lx " y" ly " w" lw " h" lh)
        WinSetTransparent(165, "ahk_id " dim.Hwnd)
        return dim
    } catch {
        try dim.Destroy()
        throw
    }
}

ShowCenteredGoldPrompt(dialog, backdrop, width, height)
{
    rect := Buffer(16, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", backdrop.Hwnd, "Ptr", rect)
        throw Error("Unable to center update dialog.")
    left := NumGet(rect, 0, "Int")
    top := NumGet(rect, 4, "Int")
    dw := NumGet(rect, 8, "Int") - left
    dh := NumGet(rect, 12, "Int") - top
    monitor := MonitorFromPoint(left + dw // 2, top + dh // 2)
    MonitorGetWorkArea(monitor, &workLeft, &workTop, &workRight, &workBottom)
    x := Max(workLeft, Min(workRight - width, left + Round((dw - width) / 2)))
    y := Max(workTop, Min(workBottom - height, top + Round((dh - height) / 2)))
    dialog.Show("w" width " h" height " x" x " y" y)
}

CreateGoldNativePrompt(owner, title, width, height)
{
    backdrop := CreateGoldPromptBackdrop(owner)
    try
    {
        panel := Gui("-Caption -Border -DPIScale +Owner" backdrop.Hwnd, title)
        panel.MarginX := 0, panel.MarginY := 0
        panel.BackColor := "C5A45C"
        ; Keep the interior control so prompts that change height can resize the frame and fill together.
        panel.NativePromptBackground := panel.Add("Text",
            "x2 y2 w" (width - 4) " h" (height - 4) " Background171008")
        panel.NativePromptBackdrop := backdrop
        panel.NativePromptWidth := width
        panel.NativePromptHeight := height
        return panel
    }
    catch
    {
        backdrop.Destroy()
        throw
    }
}

AddGoldPromptCopy(panel, x, y, width, reservedHeight, text)
{
    label := panel.Add("Text", "x" x " y" y " w" width " BackgroundTrans +Wrap", text)
    label.GetPos(, , , &measuredHeight)
    ; Leave a little room for independent font and control rounding when scaled.
    height := Max(reservedHeight, measuredHeight + 4)
    label.Move(, , , height)
    return height - reservedHeight
}

GrowGoldNativePrompt(panel, extraHeight)
{
    if extraHeight <= 0
        return
    panel.NativePromptHeight += extraHeight
    panel.NativePromptBackground.Move(, , , panel.NativePromptHeight - 4)
}

ShowGoldNativePrompt(panel, scale := unset)
{
    if !IsObject(panel) || !panel.HasOwnProp("NativePromptBackdrop")
        return
    if !IsSet(scale)
        scale := Min(GetOwnedMenuScale(), GetOwnedMenuFitScale(panel.NativePromptBackdrop,
            panel.NativePromptWidth, panel.NativePromptHeight))
    ScaleOwnedMenuContent(panel, scale)
    ShowCenteredGoldPrompt(panel, panel.NativePromptBackdrop,
        Round(panel.NativePromptWidth * scale), Round(panel.NativePromptHeight * scale))
}

CloseGoldNativePrompt(panel)
{
    if !IsObject(panel)
        return
    backdrop := panel.HasOwnProp("NativePromptBackdrop") ? panel.NativePromptBackdrop : 0
    try DestroyScaledMenu(panel)
    if IsObject(backdrop)
        try backdrop.Destroy()
}
