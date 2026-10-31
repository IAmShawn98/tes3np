; Happy Hour face overlay, driven exclusively by the verified Discord banner.
; No dev replay, tray options, standalone window, or animation.
; Keep the approved transparency and the user's current positioning.
global HappyHourBannerVisible := false
global HappyHourJiubPicture := 0

InitializeHappyHourJiub()
{
    OnMessage(0x8334, LauncherHappyHourFaceStateChanged)
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
    global HappyHourBannerVisible, HappyHourJiubPicture
    if !IsObject(HappyHourJiubPicture)
        return
    HappyHourJiubPicture.Visible := HappyHourBannerVisible
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
    global HappyHourJiubPicture, HappyHourBannerVisible
    SetTimer(CheckHappyHourHost, 0)
    if IsObject(HappyHourJiubPicture)
        try HappyHourJiubPicture.Visible := false
    HappyHourJiubPicture := 0
    HappyHourBannerVisible := false
    OnMessage(0x8334, LauncherHappyHourFaceStateChanged, 0)
}
