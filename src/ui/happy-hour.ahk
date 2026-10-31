; Happy Hour face overlay, driven exclusively by the verified Discord banner.
; No dev replay, tray options, standalone window, or animation.
; Keep the approved transparency and the user's current positioning.
global HappyHourBannerVisible := false
global HappyHourJiubPicture := 0
global HappyHourDustPicture := 0

InitializeHappyHourJiub()
{
    OnMessage(0x8334, LauncherHappyHourFaceStateChanged)
}

; Static, sparse RGB pixie dust overlays ONLY the original launcher artwork.
; Its child picture is created immediately after the background and before all
; interactive controls. Disabled + WS_EX_TRANSPARENT ensures no mouse capture.
; No animation timers, separate windows or outside-desktop drawing.
CreateHappyHourDust()
{
    global LauncherGui, HappyHourDustPicture
    asset := A_ScriptDir "\assets\happy-hour\pixie-dust.png"
    if !FileExist(asset)
    {
        try LogLauncherEvent("HAPPY HOUR | Pixie dust artwork missing: " asset)
        return
    }
    HappyHourDustPicture := LauncherGui.Add("Picture",
        "x0 y-4 w960 h720 Hidden Disabled BackgroundTrans +E0x20", asset)
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
    global HappyHourBannerVisible, HappyHourJiubPicture, HappyHourDustPicture
    if IsObject(HappyHourJiubPicture)
        HappyHourJiubPicture.Visible := HappyHourBannerVisible
    if IsObject(HappyHourDustPicture)
        HappyHourDustPicture.Visible := HappyHourBannerVisible
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
    global HappyHourJiubPicture, HappyHourDustPicture, HappyHourBannerVisible
    SetTimer(CheckHappyHourHost, 0)
    if IsObject(HappyHourJiubPicture)
        try HappyHourJiubPicture.Visible := false
    HappyHourJiubPicture := 0
    if IsObject(HappyHourDustPicture)
        try HappyHourDustPicture.Visible := false
    HappyHourDustPicture := 0
    HappyHourBannerVisible := false
    OnMessage(0x8334, LauncherHappyHourFaceStateChanged, 0)
}
