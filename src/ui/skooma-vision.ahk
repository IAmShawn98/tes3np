; Jiub-only Happy Hour portrait. NO top-level overlays, animations, particle
; windows, graphics timers or owner-follow calculations. The transparent PNG
; comes directly from the user's approved Jiub Happy Hour icon.
; It is a face-only cutout: original pixelated face, black shades with
; rainbow reflections, and the approved goofy grin. No hat or moon pixels.
; Original launcher art and UI controls stay untouched.
;
; The verified ChatHost Happy Hour banner remains the sole real activation
; source. A 20-second tray preview affects ONLY this cosmetic picture.
global SkoomaVisionEnabled := true
global SkoomaVisionBannerActive := false
global SkoomaVisionPreviewActive := false
global SkoomaVisionPicture := 0

InitializeSkoomaVision()
{
    global DataFile, SkoomaVisionEnabled
    SkoomaVisionEnabled := IniRead(DataFile, "Launcher", "SkoomaVisionEnabled", "1") != "0"
    A_TrayMenu.Add("Jiub's Happy Hour look", ToggleSkoomaVision)
    A_TrayMenu.Add("Preview Jiub Happy Hour (20 sec)", PreviewSkoomaVision)
    if SkoomaVisionEnabled
        A_TrayMenu.Check("Jiub's Happy Hour look")
    OnMessage(0x8334, LauncherSkoomaVisionStateChanged)
}

; Called once as part of constructing the ORIGINAL launcher GUI, BEFORE the
; existing CaptureLauncherControlLayout() call. Therefore its image position
; and dimensions scale with every other launcher control automatically, and
; the image moves synchronously with the launcher (same HWND).
CreateSkoomaVision()
{
    global LauncherGui, SkoomaVisionPicture
    asset := A_ScriptDir "\assets\happy-hour\jiub-happy-hour.png"
    if !FileExist(asset)
    {
        try LogLauncherEvent("HAPPY HOUR | Jiub portrait accessory missing: " asset)
        return
    }
    ; This asset contains only Jiub's cut-out head, never the original
    ; medallion/moon/background. Preserve that moon underneath unchanged.
    ; The new compact artwork is center-aligned to the existing portrait.
    ; Same HWND: no moving independent window or animation lag.
    SkoomaVisionPicture := LauncherGui.Add("Picture",
        "x438 y84 w120 h135 Hidden BackgroundTrans", asset)
}

LauncherSkoomaVisionStateChanged(wParam, lParam, msg, hwnd)
{
    global LauncherGui, SkoomaVisionBannerActive
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd
        return 0
    bannerVisible := wParam != 0
    if SkoomaVisionBannerActive != bannerVisible
    {
        SkoomaVisionBannerActive := bannerVisible
        ; A verified ChatHost banner is the source; this is diagnostic only.
        try LogLauncherEvent("HAPPY HOUR | Jiub face " (bannerVisible ? "shown" : "restored to normal") " by ChatHost banner.")
    }
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
        A_TrayMenu.Check("Jiub's Happy Hour look")
    else
        A_TrayMenu.Uncheck("Jiub's Happy Hour look")
    RefreshSkoomaVision()
}

PreviewSkoomaVision(*)
{
    global SkoomaVisionPreviewActive
    ; Does not forge a real banner, Discord message or timer.
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
    global SkoomaVisionEnabled, SkoomaVisionBannerActive
    global SkoomaVisionPreviewActive, SkoomaVisionPicture, EmbeddedChatPid
    if !IsObject(SkoomaVisionPicture)
        return
    ; A verified Happy Hour shows the portrait; the opt-in tray preview may
    ; show it even if the automatic mode is disabled.
    visible := (SkoomaVisionEnabled && SkoomaVisionBannerActive)
        || SkoomaVisionPreviewActive
    SkoomaVisionPicture.Visible := visible
    ; No frame updates. This lightweight timer only protects against a
    ; ChatHost crash leaving a stale Happy Hour flag active.
    SetTimer(CheckSkoomaVisionHost, SkoomaVisionBannerActive ? 1500 : 0)
}

CheckSkoomaVisionHost(*)
{
    global EmbeddedChatPid, SkoomaVisionBannerActive
    if SkoomaVisionBannerActive && EmbeddedChatPid && !ProcessExist(EmbeddedChatPid)
    {
        SkoomaVisionBannerActive := false
        RefreshSkoomaVision()
    }
}

DisposeSkoomaVision()
{
    global SkoomaVisionPicture, SkoomaVisionBannerActive
    global SkoomaVisionPreviewActive
    SetTimer(EndSkoomaVisionPreview, 0)
    SetTimer(CheckSkoomaVisionHost, 0)
    if IsObject(SkoomaVisionPicture)
        try SkoomaVisionPicture.Visible := false
    SkoomaVisionPicture := 0
    SkoomaVisionBannerActive := false
    SkoomaVisionPreviewActive := false
    OnMessage(0x8334, LauncherSkoomaVisionStateChanged, 0)
}
