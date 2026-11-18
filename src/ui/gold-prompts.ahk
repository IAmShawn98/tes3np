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
    dialog.Show("w" width " h" height " x" (left + Round((dw - width) / 2))
        " y" (top + Round((dh - height) / 2)))
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

ShowGoldNativePrompt(panel, scale := unset)
{
    if !IsObject(panel) || !panel.HasOwnProp("NativePromptBackdrop")
        return
    if !IsSet(scale)
        scale := GetOwnedMenuScale()
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
