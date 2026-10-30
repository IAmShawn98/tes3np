; Skooma Vision: strictly presentational Happy Hour theme.
; ChatHost owns verification/expiry and posts 0x8334 ONLY while its real
; Happy Hour banner is shown. Never infer Happy Hour from timers or log text.
global SkoomaVisionEnabled := true
global SkoomaVisionBannerActive := false
global SkoomaVisionPreviewActive := false
global SkoomaVisionGui := 0
global SkoomaVisionPieces := []
global SkoomaVisionVisible := false
global SkoomaVisionPhase := 0
global SkoomaVisionLastWidth := 0
global SkoomaVisionLastHeight := 0

InitializeSkoomaVision()
{
    global DataFile, SkoomaVisionEnabled
    SkoomaVisionEnabled := IniRead(DataFile, "Launcher", "SkoomaVisionEnabled", "1") != "0"
    A_TrayMenu.Add("Skooma Vision during Happy Hour", ToggleSkoomaVision)
    A_TrayMenu.Add("Preview Skooma Vision (20 sec)", PreviewSkoomaVision)
    if SkoomaVisionEnabled
        A_TrayMenu.Check("Skooma Vision during Happy Hour")
    OnMessage(0x8334, LauncherSkoomaVisionStateChanged)
}

LauncherSkoomaVisionStateChanged(wParam, lParam, msg, hwnd)
{
    global LauncherGui, SkoomaVisionBannerActive
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd
        return 0
    SkoomaVisionBannerActive := wParam != 0
    RefreshSkoomaVision()
    return 0
}

ToggleSkoomaVision(*)
{
    global SkoomaVisionEnabled, DataFile
    SkoomaVisionEnabled := !SkoomaVisionEnabled
    DirCreate(AppDataDirectory)
    IniWrite(SkoomaVisionEnabled ? "1" : "0", DataFile,
        "Launcher", "SkoomaVisionEnabled")
    if SkoomaVisionEnabled
        A_TrayMenu.Check("Skooma Vision during Happy Hour")
    else
        A_TrayMenu.Uncheck("Skooma Vision during Happy Hour")
    RefreshSkoomaVision()
}

PreviewSkoomaVision(*)
{
    global SkoomaVisionPreviewActive, SkoomaVisionEnabled
    ; Visual-only preview. It does not fabricate a Discord snowflake, change
    ; the active banner, or post a fake ChatHost message.
    if !SkoomaVisionEnabled
        return
    SkoomaVisionPreviewActive := true
    RefreshSkoomaVision()
    SetTimer(EndSkoomaVisionPreview, -20000)
}

EndSkoomaVisionPreview(*)
{
    global SkoomaVisionPreviewActive
    SkoomaVisionPreviewActive := false
    RefreshSkoomaVision()
}

RefreshSkoomaVision()
{
    global SkoomaVisionEnabled, SkoomaVisionBannerActive, SkoomaVisionPreviewActive
    if !SkoomaVisionEnabled || (!SkoomaVisionBannerActive && !SkoomaVisionPreviewActive)
    {
        SetTimer(SkoomaVisionTick, 0)
        HideSkoomaVision()
        return
    }
    try
    {
        if !IsObject(SkoomaVisionGui)
            CreateSkoomaVision()
        SkoomaVisionTick()
        ; Quiet and low-frequency: no high-speed flashes or input hooks.
        SetTimer(SkoomaVisionTick, 750)
    }
    catch Error as err
    {
        SetTimer(SkoomaVisionTick, 0)
        HideSkoomaVision()
        try LogLauncherEvent("UI | Skooma Vision visual layer disabled: " err.Message)
    }
}

AddSkoomaPiece(gui, x, y, size, symbol, color := "CC8BFF", animated := true)
{
    global SkoomaVisionPieces
    gui.SetFont("s" size " c" color " Norm", "Segoe UI Symbol")
    control := gui.Add("Text", "x" x " y" y " w70 h55 BackgroundTrans Center", symbol)
    SkoomaVisionPieces.Push({Control: control, X: x, Y: y,
        Size: size, Color: color, Animated: animated})
}

CreateSkoomaVision()
{
    global SkoomaVisionGui, SkoomaVisionPieces, SkoomaVisionVisible
    global SkoomaVisionLastWidth, SkoomaVisionLastHeight, LauncherGui
    ; Owned nonactivating click-through window: all game/client/menu controls
    ; and the existing Game Chat stay completely interactive.
    layer := Gui("+Owner" LauncherGui.Hwnd
        " -Caption +ToolWindow -DPIScale +E0x08000020",
        "tes3np Skooma Vision")
    layer.BackColor := "010203"
    SkoomaVisionPieces := []
    ; Keep the central launcher menu, chat toggle, and both info-card text
    ; surfaces clear. Party accessories decorate the screenshot borders.
    AddSkoomaPiece(layer, 283, 1, 17, "✦", "B990EF")
    AddSkoomaPiece(layer, 345, 1, 13, "✧", "72D7BC")
    AddSkoomaPiece(layer, 688, 1, 17, "✦", "EFCA80")
    AddSkoomaPiece(layer, 740, 1, 13, "✧", "C89CE8")
    ; Decorative festival accessories/party hats. They belong to the
    ; transparent layer, never to the original screenshot or game files.
    AddSkoomaPiece(layer, 30, 64, 25, "🎉", "E9A2F3", false)
    AddSkoomaPiece(layer, 882, 64, 25, "🎉", "8BE2BB", false)
    AddSkoomaPiece(layer, 18, 352, 24, "🎊", "F4CE86", false)
    AddSkoomaPiece(layer, 906, 347, 24, "🎊", "B99EF9", false)
    AddSkoomaPiece(layer, 22, 601, 21, "✶", "B48EEF")
    AddSkoomaPiece(layer, 892, 600, 21, "✶", "80D8B5")
    AddSkoomaPiece(layer, 245, 670, 15, "✦", "F0B982")
    AddSkoomaPiece(layer, 715, 674, 15, "✦", "BE92DE")
    AddSkoomaPiece(layer, 51, 222, 14, "✧", "7ED5C3")
    AddSkoomaPiece(layer, 876, 223, 14, "✧", "F1BF87")
    AddSkoomaPiece(layer, 46, 480, 14, "✦", "C09BFA")
    AddSkoomaPiece(layer, 882, 470, 14, "✦", "83DBBC")
    ; A subdued indicator on the empty upper title strip. The official
    ; Happy Hour banner above the launcher remains unchanged.
    layer.SetFont("s10 Bold cA1E5CD", "Georgia")
    label := layer.Add("Text",
        "x380 y12 w218 h24 BackgroundTrans Center", "✦ SKOOMA VISION ✦")
    SkoomaVisionPieces.Push({Control: label, X: 380, Y: 12,
        Size: 10, Color: "A1E5CD", Animated: false, Width: 218, Height: 24})
    SkoomaVisionGui := layer
    SkoomaVisionVisible := false
    SkoomaVisionLastWidth := 0
    SkoomaVisionLastHeight := 0
    ; Color-key transparency retains per-pixel content from the launcher,
    ; without any separate fullscreen image or mouse intercept.
    layer.Show("Hide w960 h716")
    WinSetTransColor("010203", "ahk_id " layer.Hwnd)
}

SkoomaVisionMotionAllowed()
{
    ; Follow Windows' "Show animations in Windows" accessibility setting.
    reduced := Buffer(4, 0)
    if DllCall("SystemParametersInfoW", "UInt", 0x1042, "UInt", 0,
        "Ptr", reduced, "UInt", 0, "Int")
        return NumGet(reduced, 0, "Int") != 0
    return false
}

SkoomaVisionTick(*)
{
    global SkoomaVisionGui, SkoomaVisionPieces, SkoomaVisionVisible
    global SkoomaVisionBannerActive, SkoomaVisionPreviewActive, SkoomaVisionEnabled, SkoomaVisionPhase
    global SkoomaVisionLastWidth, SkoomaVisionLastHeight, LauncherGui, EmbeddedChatPid
    global CharacterPage, V016SettingsGuiHwnd
    ; If ChatHost disappears unexpectedly, do not leave a phantom visual
    ; mode behind. The next verified banner will post a fresh activation.
    if SkoomaVisionBannerActive && EmbeddedChatPid && !ProcessExist(EmbeddedChatPid)
    {
        SkoomaVisionBannerActive := false
        RefreshSkoomaVision()
        return
    }
    if !SkoomaVisionEnabled || (!SkoomaVisionBannerActive && !SkoomaVisionPreviewActive) ||
        !IsObject(LauncherGui) || !IsObject(SkoomaVisionGui)
        return
    ; Keep the book, Launcher Settings and their modal controls completely
    ; clear. Resume quietly when the user returns to the main launcher.
    if IsObject(CharacterPage) && DllCall("IsWindowVisible", "Ptr", CharacterPage.Hwnd)
        || (V016SettingsGuiHwnd && DllCall("IsWindowVisible", "Ptr", V016SettingsGuiHwnd))
    {
        HideSkoomaVision()
        return
    }
    owner := "ahk_id " LauncherGui.Hwnd
    if !DllCall("IsWindowVisible", "Ptr", LauncherGui.Hwnd) ||
        WinGetMinMax(owner) = -1
    {
        HideSkoomaVision()
        return
    }
    WinGetPos(&x, &y, &w, &h, owner)
    if w <= 0 || h <= 0
        return
    scaleX := w / 960, scaleY := h / 716
    if w != SkoomaVisionLastWidth || h != SkoomaVisionLastHeight
    {
        for piece in SkoomaVisionPieces
        {
            pw := piece.HasOwnProp("Width") ? piece.Width : 70
            ph := piece.HasOwnProp("Height") ? piece.Height : 55
            piece.Control.Move(Round(piece.X * scaleX),
                Round(piece.Y * scaleY), Round(pw * scaleX),
                Round(ph * scaleY))
            piece.Control.SetFont("s" Max(6, Round(piece.Size * Min(scaleX, scaleY))),
                piece.HasOwnProp("Width") ? "Georgia" : "Segoe UI Symbol")
        }
        SkoomaVisionLastWidth := w
        SkoomaVisionLastHeight := h
    }
    if !SkoomaVisionVisible
    {
        SkoomaVisionGui.Show("NA x" x " y" y " w" w " h" h)
        SkoomaVisionVisible := true
    }
    else
        DllCall("SetWindowPos", "Ptr", SkoomaVisionGui.Hwnd, "Ptr", 0,
            "Int", x, "Int", y, "Int", w, "Int", h, "UInt", 0x0014)
    if !SkoomaVisionMotionAllowed()
        return
    SkoomaVisionPhase := Mod(SkoomaVisionPhase + 1, 8)
    ; Gentle eight-step color drift; no rapid hue flashing or zoom effects.
    colors := ["B990EF", "AA99E7", "8FB5E8", "76CBCA",
        "7ED8AD", "ADD68E", "DEC18A", "DBA9D4"]
    for i, piece in SkoomaVisionPieces
    {
        if !piece.Animated
            continue
        color := colors[Mod(SkoomaVisionPhase + i - 1, colors.Length) + 1]
        piece.Control.SetFont("c" color)
    }
}

HideSkoomaVision()
{
    global SkoomaVisionGui, SkoomaVisionVisible
    if IsObject(SkoomaVisionGui) && SkoomaVisionVisible
        try SkoomaVisionGui.Hide()
    SkoomaVisionVisible := false
}

DisposeSkoomaVision()
{
    global SkoomaVisionGui, SkoomaVisionPieces, SkoomaVisionBannerActive, SkoomaVisionPreviewActive
    SetTimer(SkoomaVisionTick, 0)
    SetTimer(EndSkoomaVisionPreview, 0)
    HideSkoomaVision()
    if IsObject(SkoomaVisionGui)
        try SkoomaVisionGui.Destroy()
    SkoomaVisionGui := 0
    SkoomaVisionPieces := []
    SkoomaVisionBannerActive := false
    SkoomaVisionPreviewActive := false
    OnMessage(0x8334, LauncherSkoomaVisionStateChanged, 0)
}
