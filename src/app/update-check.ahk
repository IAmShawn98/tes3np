; Safe update client. Installation remains an explicit user action.

global UpdateBusy := false
global UpdateStartupRequest := 0
global UpdateStartupStarted := 0
global LauncherVersionLabel := 0
global LauncherUpdateBadge := 0
CreateLauncherVersionLabel()
{
    global AppConfig, LauncherGui, LauncherVersionLabel
    LauncherGui.SetFont("s9 cC5A45C", "Segoe UI")
    ; AHK only auto-sizes a Text control to its full caption when neither
    ; dimension is specified at creation. Giving it h18 here used a narrow
    ; default width and cut the version number off at 50% launcher scale.
    LauncherVersionLabel := LauncherGui.Add("Text", "x12 y691 BackgroundTrans", "tes3np · v" AppConfig.Version)
    LauncherVersionLabel.GetPos(, , &naturalWidth)
    ; The launcher scales bounds by 50%, but keeps this text at least 5pt
    ; (9pt at 100%); reserve enough width for that font-size floor.
    ; The badge uses the final width as its adjacent alignment anchor.
    LauncherVersionLabel.Move(, , Ceil(naturalWidth * 1.125) + 4, 18)
    LauncherVersionLabel.OnEvent("Click", CheckForUpdates)
}

; Keep the installed version visible. Show a red (1) only for a newer
; published update that has not yet been viewed.
CreateLauncherUpdateBadge()
{
    global LauncherGui, LauncherVersionLabel, LauncherUpdateBadge

    ; GetPos returns GUI coordinates with AHK's DPI conversion already
    ; accounted for. Re-measuring text with GDI and passing physical pixels
    ; into Gui.Add would apply DPI scaling again and leave a large gap.
    LauncherVersionLabel.GetPos(&labelX, , &labelWidth)
    x := labelX + labelWidth + 4
    LauncherUpdateBadge := LauncherGui.Add("Text", "x" x " y689 w22 h22 Center +0x200 BackgroundD63232", "1")
    LauncherUpdateBadge.SetFont("s10 Bold cFFFFFF", "Segoe UI")
    ShapeCircularUpdateBadge(LauncherUpdateBadge)
    LauncherUpdateBadge.OnEvent("Click", CheckForUpdates)
    LauncherUpdateBadge.Visible := false
}

ScaleLauncherVersionLabel(scale)
{
    global LauncherVersionLabel, LauncherUpdateBadge

    if IsObject(LauncherVersionLabel)
        LauncherVersionLabel.SetFont("s" Max(5, Round(9 * scale)), "Segoe UI")
    ApplyLauncherBadgeFont(scale)
    if IsObject(LauncherUpdateBadge)
        ShapeCircularUpdateBadge(LauncherUpdateBadge)
}

; Preserve the red unread notification at the saved launcher scale.
ApplyLauncherBadgeFont(scale)
{
    global LauncherUpdateBadge
    if !IsObject(LauncherUpdateBadge)
        return
    size := Max(6, Round(10 * scale))
    LauncherUpdateBadge.SetFont("s" size " Bold cFFFFFF", "Segoe UI")
}

; Clip the native red Text control to a circle after its final DPI/launcher
; scale has been applied. Windows owns the transferred GDI region lifetime.
ShapeCircularUpdateBadge(control)
{
    if !IsObject(control) || !DllCall("user32\IsWindow", "Ptr", control.Hwnd, "Int")
        return
    bounds := Buffer(16, 0)
    if !DllCall("user32\GetClientRect", "Ptr", control.Hwnd, "Ptr", bounds, "Int")
        return
    width := NumGet(bounds, 8, "Int"), height := NumGet(bounds, 12, "Int")
    diameter := Min(width, height)
    if diameter < 1
        return
    circle := DllCall("gdi32\CreateEllipticRgn", "Int", 0, "Int", 0,
        "Int", diameter, "Int", diameter, "Ptr")
    if circle && !DllCall("user32\SetWindowRgn", "Ptr", control.Hwnd,
        "Ptr", circle, "Int", 1, "Int")
        DllCall("gdi32\DeleteObject", "Ptr", circle)
}

SetLauncherUpdateAvailable(isAvailable, latestVersion := "")
{
    global AppConfig, LauncherUpdateBadge, LauncherVersionLabel
    global LauncherScale

    if !IsObject(LauncherUpdateBadge) || !IsObject(LauncherVersionLabel)
        return
    LauncherVersionLabel.Visible := true
    available := isAvailable && latestVersion != ""
        && GetLauncherUpdateKind(AppConfig.Version, latestVersion) != ""
        && !HasSeenUpdateAutoPreview(latestVersion)
    ; Transparent static text leaves old glyph pixels behind when updated
    ; without the picture underneath being redrawn. Refresh the *footer*
    ; rectangle after changing state; never invalidate the whole launcher.
    wasVisible := LauncherUpdateBadge.Visible
    if !available
    {
        if wasVisible
        {
            LauncherUpdateBadge.Visible := false
            RedrawLauncherUpdateBadge()
        }
        return
    }
    if !wasVisible
    {
        ApplyLauncherBadgeFont(LauncherScale / 100)
        LauncherUpdateBadge.Visible := true
        RedrawLauncherUpdateBadge()
    }
}

; Repaint the existing backdrop and all children only underneath the
; badge (including when hidden). Screen-to-client mapping uses *physical*
; Win32 pixels, so scaling is not applied a second time.
RedrawLauncherUpdateBadge()
{
    global LauncherGui, LauncherUpdateBadge
    if !IsObject(LauncherGui) || !IsObject(LauncherUpdateBadge)
        return
    rect := Buffer(16, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", LauncherUpdateBadge.Hwnd, "Ptr", rect, "Int")
        return
    DllCall("user32\MapWindowPoints", "Ptr", 0, "Ptr", LauncherGui.Hwnd,
        "Ptr", rect, "UInt", 2, "Int")
    ; RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW
    DllCall("user32\RedrawWindow", "Ptr", LauncherGui.Hwnd,
        "Ptr", rect, "Ptr", 0, "UInt", 0x0185, "Int")
}

CheckForUpdateAvailability(*)
{
    global AppConfig, UpdateStartupRequest, UpdateStartupStarted
    ; The automatic startup check must not block the AHK GUI thread while
    ; waiting for GitHub. Manual checks still use the existing trusted flow.
    if IsObject(UpdateStartupRequest)
        return
    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(5000, 5000, 10000, 10000)
        request.Open("GET", GetUpdateManifestUrl(AppConfig.Version), true)
        request.SetRequestHeader("User-Agent", "tes3np updater")
        UpdateStartupRequest := request
        UpdateStartupStarted := A_TickCount
        request.Send()
        SetTimer(PollStartupUpdateAvailability, 100)
        LogLauncherEvent("UPDATE | Nonblocking startup availability request started.")
    } catch Error as err {
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        SetLauncherUpdateAvailable(false)
        LogLauncherEvent("UPDATE | Startup availability check unavailable (" Type(err) ").")
    }
}

PollStartupUpdateAvailability(*)
{
    global AppConfig, UpdateStartupRequest, UpdateStartupStarted
    request := UpdateStartupRequest
    if !IsObject(request) {
        SetTimer(PollStartupUpdateAvailability, 0)
        return
    }
    elapsed := A_TickCount - UpdateStartupStarted
    ; WinHTTP's individual timeouts are bounded, but abort a stalled whole
    ; request too. Checking completion with 0 seconds never waits on WinHTTP.
    if elapsed > 30000 {
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        try request.Abort()
        SetLauncherUpdateAvailable(false)
        LogLauncherEvent("UPDATE | Startup availability check timed out after " elapsed "ms.")
        return
    }
    try {
        if !request.WaitForResponse(0)
            return
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        if request.Status != 200
            throw Error("Update metadata returned HTTP " request.Status ".")
        manifest := ParseAndValidateUpdateManifest(request.ResponseText, AppConfig.Version)
        available := manifest.UpdateEnabled && GetLauncherUpdateKind(AppConfig.Version, manifest.Version) != ""
        SetLauncherUpdateAvailable(available, manifest.version)
        if available && !HasSeenUpdateAutoPreview(manifest.version)
            SetTimer(AutoPreviewNewUpdate.Bind(manifest.version), -4000)
        LogLauncherEvent("UPDATE | Startup availability check | Current: v" AppConfig.Version " | Latest: v" manifest.version " | Available: " (available ? "yes" : "no") " | Elapsed: " elapsed "ms.")
    } catch Error as err {
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        SetLauncherUpdateAvailable(false)
        LogLauncherEvent("UPDATE | Startup availability check unavailable (" Type(err) ") after " elapsed "ms.")
    }
}

HasSeenUpdateAutoPreview(version)
{
    global DataFile
    return IniRead(DataFile, "Updates", "LastAutoPreviewVersion", "") = version
}

AutoPreviewNewUpdate(version, *)
{
    global LauncherGui, UpdateBusy
    if UpdateBusy || HasSeenUpdateAutoPreview(version)
        return
    if !IsObject(LauncherGui) || !DllCall("user32\IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        return
    CheckForUpdates()
}

CheckForUpdates(*)
{
    global AppConfig, UpdateBusy, LauncherGui, DataFile
    if UpdateBusy {
        LogLauncherEvent("UPDATE | Check ignored because another update operation is active.")
        return
    }
    UpdateBusy := true
    staged := ""
    handedOff := false
    LogLauncherEvent("UPDATE | Checking trusted update manifest. Current: v" AppConfig.Version ".")
    try {
        manifest := ParseAndValidateUpdateManifest(DownloadUpdateText(GetUpdateManifestUrl(AppConfig.Version)), AppConfig.Version)
        latest := manifest.version
        kind := GetLauncherUpdateKind(AppConfig.Version, latest)
        LogLauncherEvent("UPDATE | Manifest validated. Current: v" AppConfig.Version " | Latest: v" latest ".")
        if !manifest.updateEnabled {
            SetLauncherUpdateAvailable(false)
            LogLauncherEvent("UPDATE | Automatic installation disabled by release metadata.")
            ShowUpdateStatusPanel("disabled", AppConfig.Version, latest)
            return
        }
        if kind = "" {
            SetLauncherUpdateAvailable(false)
            LogLauncherEvent("UPDATE | SUCCESS | Launcher is up to date.")
            ShowUpdateStatusPanel("current", AppConfig.Version)
            return
        }
        ; Update notifications are stored by published version. Viewing the
        ; preview clears (1); a newly published version shows it again.
        LogLauncherEvent("UPDATE | Update available: v" latest ".")
        ; The first preview of this published version is remembered across restarts,
        ; regardless of whether it opened automatically or the user opened it.
        ; Store before showing the modal so Cancel/Not Now does not repeat next launch.
        if !HasSeenUpdateAutoPreview(latest)
            IniWrite(latest, DataFile, "Updates", "LastAutoPreviewVersion")
        SetLauncherUpdateAvailable(true, latest)
        ; Viewing the update preview never downloads, stages, or installs files.
        choice := ShowUpdatePreview(AppConfig.Version, latest, manifest.channel, kind)
        if choice = "Yes" && ShowGoldUpdateConfirmation("Download Update?", "Download and verify v" latest "?`nThe installed launcher will not be changed.", "Download") {
            BeginInterfaceUpdate(LauncherGui, "Downloading update...", true, 5)
            try {
                staged := DownloadAndStageUpdate(manifest)
                SetInterfaceLoadingText("Update ready to install...")
            } finally EndInterfaceUpdate()
            LogLauncherEvent("UPDATE | READY | Verified update staged for v" latest ".")
            if ShowGoldUpdateConfirmation("Install Verified Update?", "v" latest " is verified and ready.`nInstalling will restart tes3np. Rollback is available if startup fails.", "Install Update") {
                StartTransactionalUpdate(manifest.version, staged)
                handedOff := true
                LogLauncherEvent("UPDATE | Transactional installer started for v" latest ".")
                ExitApp(0)
            }
            LogLauncherEvent("UPDATE | Installation deferred for verified update v" latest ".")
        } else {
            LogLauncherEvent("UPDATE | User deferred update v" latest "; unread indicator remains hidden until a newer update.")
        }
    } catch Error as err {
        LogLauncherEvent("ERROR | UPDATE | " Type(err))
        ShowUpdateStatusPanel("error", AppConfig.Version)
    } finally {
        if staged != "" && !handedOff
            DeleteLauncherStagingTree(staged)
        UpdateBusy := false
    }
}

DownloadUpdateText(url)
{
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetTimeouts(5000, 5000, 10000, 10000)
    request.Open("GET", url, false)
    request.SetRequestHeader("User-Agent", "tes3np updater")
    request.Send()
    if request.Status != 200
        throw Error("Update metadata returned HTTP " request.Status ".")
    return request.ResponseText
}
