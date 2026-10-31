; Happy Hour face overlay, driven exclusively by the verified Discord banner.
; No dev replay, tray options, standalone window, or animation.
; Keep the approved transparency and the user's current positioning.
global HappyHourBannerVisible := false
global HappyHourJiubPicture := 0
global HappyHourDustPictures := []

InitializeHappyHourJiub()
{
    OnMessage(0x8334, LauncherHappyHourFaceStateChanged)
}

; Static and lightweight: the original image's bright speckles are ~1
; logical pixel. Four one-pixel-offset impressions make them readable at
; normal launcher scale without animation or a more aggressive dust pattern.
; These native child pictures stay inside the launcher, beneath the UI.
; Disabled + WS_EX_TRANSPARENT keep them completely non-interactive.
CreateHappyHourDust()
{
    global LauncherGui, HappyHourDustPictures
    asset := A_ScriptDir "\assets\happy-hour\pixie-dust.png"
    if !FileExist(asset)
    {
        try LogLauncherEvent("HAPPY HOUR | Pixie dust artwork missing: " asset)
        return
    }
    HappyHourDustPictures := []
    for offset in [[0, 0], [1, 0], [0, 1], [1, 1]]
    {
        opts := "x" offset[1] " y" (offset[2] - 4) " w960 h720 Hidden Disabled BackgroundTrans +E0x20"
        HappyHourDustPictures.Push(LauncherGui.Add("Picture", opts, asset))
    }
}

; One child of the original launcher, created before layout capture.
; Dragging and scaling the launcher moves the face synchronously.
CreateHappyHourJiub()
{
    global LauncherGui, HappyHourJiubPicture
    asset := A_ScriptDir "\assets\happy-hour\jiub-happy-hour.png"
    if !FileExist(asset)
    {
        try LogLauncherEvent("HAPPY HOUR | Jiub image missing: " asset)
        return
    }
    HappyHourJiubPicture := LauncherGui.Add("Picture",
        "x438 y84 w120 h135 Hidden BackgroundTrans", asset)
}

LauncherHappyHourFaceStateChanged(wParam, lParam, msg, hwnd)
{
    global LauncherGui, HappyHourBannerVisible
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd
        return 0
    visible := wParam != 0
    if HappyHourBannerVisible != visible
    {
        HappyHourBannerVisible := visible
        try LogLauncherEvent("HAPPY HOUR | Jiub " (visible ? "visible" : "normal") " with banner")
    }
    RefreshHappyHourJiub()
    return 0
}

RefreshHappyHourJiub()
{
    global HappyHourBannerVisible, HappyHourJiubPicture, HappyHourDustPictures
    if IsObject(HappyHourJiubPicture)
        HappyHourJiubPicture.Visible := HappyHourBannerVisible
    for dust in HappyHourDustPictures
        dust.Visible := HappyHourBannerVisible
    ; Safety: restore Jiub if ChatHost crashes while the banner is active.
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
    global HappyHourJiubPicture, HappyHourDustPictures, HappyHourBannerVisible
    SetTimer(CheckHappyHourHost, 0)
    if IsObject(HappyHourJiubPicture)
        try HappyHourJiubPicture.Visible := false
    HappyHourJiubPicture := 0
    for dust in HappyHourDustPictures
        try dust.Visible := false
    HappyHourDustPictures := []
    HappyHourBannerVisible := false
    OnMessage(0x8334, LauncherHappyHourFaceStateChanged, 0)
}
