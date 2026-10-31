; Explicit opt-in: production runs never replay expired announcements.
HappyHourDevModeEnabled()
{
    for arg in A_Args
        if arg = "--happy-hour-dev"
            return true
    return false
}

; Happy Hour Jiub portrait. NO top-level overlays, animations, particle
; windows, graphics timers or owner-follow calculations. The transparent PNG
; comes directly from the user's approved Jiub Happy Hour icon.
; It is a face-only cutout: original pixelated face, black shades with
; rainbow reflections, and the approved goofy grin. No hat or moon pixels.
; Original launcher art and UI controls stay untouched.
;
; The verified ChatHost Happy Hour banner remains the sole real activation
; source. A 20-second tray preview affects ONLY this cosmetic picture.
global HappyHourJiubEnabled := true
global HappyHourBannerVisible := false
global HappyHourJiubPreviewActive := false
global HappyHourJiubPicture := 0

InitializeHappyHourJiub()
{
    global DataFile, HappyHourJiubEnabled
    ; Retain the existing user's choice on upgrade, then use the clear name.
    saved := IniRead(DataFile, "Launcher", "HappyHourJiubEnabled",
        IniRead(DataFile, "Launcher", "SkoomaVisionEnabled", "1"))
    HappyHourJiubEnabled := saved != "0"
    A_TrayMenu.Add("Happy Hour: Jiub face", ToggleHappyHourJiub)
    A_TrayMenu.Add("Preview Happy Hour face (20 sec)", PreviewHappyHourJiub)
    if HappyHourJiubEnabled
        A_TrayMenu.Check("Happy Hour: Jiub face")
    OnMessage(0x8334, LauncherHappyHourFaceStateChanged)
}

; Called once as part of constructing the ORIGINAL launcher GUI, BEFORE the
; existing CaptureLauncherControlLayout() call. Therefore its image position
; and dimensions scale with every other launcher control automatically, and
; the image moves synchronously with the launcher (same HWND).
CreateHappyHourJiub()
{
    global LauncherGui, HappyHourJiubPicture
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
    HappyHourJiubPicture := LauncherGui.Add("Picture",
        "x438 y84 w120 h135 Hidden BackgroundTrans", asset)
}

LauncherHappyHourFaceStateChanged(wParam, lParam, msg, hwnd)
{
    global LauncherGui, HappyHourBannerVisible
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd
        return 0
    bannerVisible := wParam != 0
    if HappyHourBannerVisible != bannerVisible
    {
        HappyHourBannerVisible := bannerVisible
        ; A genuine ChatHost banner is authoritative; this is diagnostic only.
        try LogLauncherEvent("HAPPY HOUR | Jiub face " (bannerVisible ? "shown" : "restored to normal") " by ChatHost banner.")
    }
    RefreshHappyHourJiub()
    return 0
}

ToggleHappyHourJiub(*)
{
    global HappyHourJiubEnabled, DataFile
    HappyHourJiubEnabled := !HappyHourJiubEnabled
    DirCreate(AppDataDirectory)
    IniWrite(HappyHourJiubEnabled ? "1" : "0", DataFile,
        "Launcher", "HappyHourJiubEnabled")
    if HappyHourJiubEnabled
        A_TrayMenu.Check("Happy Hour: Jiub face")
    else
        A_TrayMenu.Uncheck("Happy Hour: Jiub face")
    RefreshHappyHourJiub()
}

PreviewHappyHourJiub(*)
{
    global HappyHourJiubPreviewActive
    ; Does not forge a real banner, Discord message or timer.
    HappyHourJiubPreviewActive := true
    RefreshHappyHourJiub()
    SetTimer(EndHappyHourJiubPreview, -20000)
}

EndHappyHourJiubPreview(*)
{
    global HappyHourJiubPreviewActive
    HappyHourJiubPreviewActive := false
    RefreshHappyHourJiub()
}

RefreshHappyHourJiub()
{
    global HappyHourJiubEnabled, HappyHourBannerVisible
    global HappyHourJiubPreviewActive, HappyHourJiubPicture, EmbeddedChatPid
    if !IsObject(HappyHourJiubPicture)
        return
    ; A verified Happy Hour shows the portrait; the opt-in tray preview may
    ; show it even if the automatic mode is disabled.
    visible := (HappyHourJiubEnabled && HappyHourBannerVisible)
        || HappyHourJiubPreviewActive
    HappyHourJiubPicture.Visible := visible
    ; No frame updates. This lightweight timer only protects against a
    ; ChatHost crash leaving a stale Happy Hour flag active.
    SetTimer(CheckHappyHourHost, HappyHourBannerVisible ? 1500 : 0)
}

CheckHappyHourHost(*)
{
    global EmbeddedChatPid, HappyHourBannerVisible
    if HappyHourBannerVisible && EmbeddedChatPid && !ProcessExist(EmbeddedChatPid)
    {
        HappyHourBannerVisible := false
        RefreshHappyHourJiub()
    }
}

DisposeHappyHourJiub()
{
    global HappyHourJiubPicture, HappyHourBannerVisible
    global HappyHourJiubPreviewActive
    SetTimer(EndHappyHourJiubPreview, 0)
    SetTimer(CheckHappyHourHost, 0)
    if IsObject(HappyHourJiubPicture)
        try HappyHourJiubPicture.Visible := false
    HappyHourJiubPicture := 0
    HappyHourBannerVisible := false
    HappyHourJiubPreviewActive := false
    OnMessage(0x8334, LauncherHappyHourFaceStateChanged, 0)
}
