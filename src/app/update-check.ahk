; Safe update client. Installation remains an explicit user action.

global UpdateBusy := false
global UpdateStartupRequest := 0
global UpdateStartupStarted := 0
global LauncherVersionLabel := 0
global LauncherUpdateBadge := 0
global LauncherUpdateDismissedVersion := ""
; Only enabled by the explicit --test-update-badge command line switch.
; Windows messages then adjust the real launcher's cosmetic badge in memory.
; This mode never changes the published update feed or saved preview history.
global LauncherBadgeTestMode := false
global LauncherBadgeTestState := "none"
global LauncherBadgeTestWindowHwnd := 0

CreateLauncherVersionLabel()
{
    global AppConfig, LauncherGui, LauncherVersionLabel, LauncherUpdateDismissedVersion

    LauncherUpdateDismissedVersion := ""
    LauncherGui.SetFont("s9 cC5A45C", "Segoe UI")
    ; Let the Text control size itself to the rendered caption, not a 300px
    ; click target. Its DPI-aware width is also the badge's alignment anchor.
    LauncherVersionLabel := LauncherGui.Add("Text", "x12 y691 h18 BackgroundTrans", "tes3np · v" AppConfig.Version)
    LauncherVersionLabel.OnEvent("Click", CheckForUpdates)
}

; The version remains visible, even when an update has been deferred.
; A small (1) means an unseen published update; a subdued dot means viewed.
CreateLauncherUpdateBadge()
{
    global LauncherGui, LauncherVersionLabel, LauncherUpdateBadge

    ; GetPos returns GUI coordinates with AHK's DPI conversion already
    ; accounted for. Re-measuring text with GDI and passing physical pixels
    ; into Gui.Add would apply DPI scaling again and leave a large gap.
    LauncherVersionLabel.GetPos(&labelX, , &labelWidth)
    x := labelX + labelWidth + 4
    ; Left alignment keeps a single viewed dot as close to the caption as (1).
    LauncherUpdateBadge := LauncherGui.Add("Text", "x" x " y689 w28 h22 BackgroundTrans", "(1)")
    LauncherUpdateBadge.SetFont("s10 Bold cD63232", "Segoe UI")
    LauncherUpdateBadge.OnEvent("Click", CheckForUpdates)
    LauncherUpdateBadge.Visible := false
}

ScaleLauncherVersionLabel(scale)
{
    global LauncherVersionLabel, LauncherUpdateBadge

    if IsObject(LauncherVersionLabel)
        LauncherVersionLabel.SetFont("s" Max(5, Round(9 * scale)), "Segoe UI")
    ApplyLauncherBadgeFont(scale)
}

; Keep unread (1) red, but make the viewed indicator visible on the
; dark, textured footer. The solid circle needs no centering offset.
ApplyLauncherBadgeFont(scale)
{
    global LauncherUpdateBadge
    if !IsObject(LauncherUpdateBadge)
        return
    unread := LauncherUpdateBadge.Text = "(1)"
    size := Max(6, Round((unread ? 10 : 12) * scale))
    color := unread ? "D63232" : "E0C27F"
    LauncherUpdateBadge.SetFont("s" size " Bold c" color, "Segoe UI")
}

SetLauncherUpdateAvailable(isAvailable, latestVersion := "")
{
    global AppConfig, LauncherUpdateBadge, LauncherVersionLabel, LauncherUpdateDismissedVersion
    global LauncherBadgeTestMode, LauncherBadgeTestState, LauncherScale

    if !IsObject(LauncherUpdateBadge) || !IsObject(LauncherVersionLabel)
        return
    LauncherVersionLabel.Visible := true
    available := isAvailable && latestVersion != ""
        && GetLauncherUpdateKind(AppConfig.Version, latestVersion) != ""
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
    unseen := LauncherBadgeTestMode ? LauncherBadgeTestState = "unread"
        : latestVersion != LauncherUpdateDismissedVersion && !HasSeenUpdateAutoPreview(latestVersion)
    nextText := unseen ? "(1)" : Chr(0x25CF)
    if !wasVisible || LauncherUpdateBadge.Text != nextText
    {
        LauncherUpdateBadge.Text := nextText
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

DismissLauncherUpdate(latestVersion)
{
    global LauncherUpdateDismissedVersion
    LauncherUpdateDismissedVersion := latestVersion
    SetLauncherUpdateAvailable(true, latestVersion)
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
    global LauncherGui, UpdateBusy, LauncherUpdateDismissedVersion
    if UpdateBusy || LauncherUpdateDismissedVersion = version || HasSeenUpdateAutoPreview(version)
        return
    if !IsObject(LauncherGui) || !DllCall("user32\IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        return
    CheckForUpdates()
}

CheckForUpdates(*)
{
    global AppConfig, UpdateBusy, LauncherGui, DataFile, LauncherBadgeTestMode
    if LauncherBadgeTestMode
    {
        MsgBox("This is a cosmetic update-indicator test. Use scripts\test-update-badge.ps1 to change its state.`nNo update has been published or installed.", "TES3NP Update Badge Test", "Iconi")
        return
    }
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
        ; The startup check owns the footer notification. Opening a preview
        ; from the version text must not re-show a dismissed banner.
        LogLauncherEvent("UPDATE | Update available: v" latest ".")
        ; The first preview of this published version is remembered across restarts,
        ; regardless of whether it opened automatically or the user opened it.
        ; Store before showing the modal so Cancel/Not Now does not repeat next launch.
        if !HasSeenUpdateAutoPreview(latest)
            IniWrite(latest, DataFile, "Updates", "LastAutoPreviewVersion")
        SetLauncherUpdateAvailable(true, latest)
        ; Viewing the gold preview never downloads, stages, or installs files.
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
            DismissLauncherUpdate(latest)
            LogLauncherEvent("UPDATE | User deferred update v" latest "; notification remains accessible beside version.")
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

; WM_APP + 0x41: one numeric state sent from the local PowerShell test helper.
; The handler is registered ONLY when the launcher started with the test flag.
; No real update feed, profile or INI state is changed by these messages.
HandleLauncherBadgeTestMessage(state, unused, msg, hwnd)
{
    global LauncherBadgeTestMode, LauncherBadgeTestState, LauncherBadgeTestWindowHwnd
    ; Compare a stored numeric HWND, not Gui.Hwnd: a destroyed Gui object
    ; still exists, but reading its Hwnd raises "Gui has no window".
    if !LauncherBadgeTestMode || hwnd != LauncherBadgeTestWindowHwnd
        || !DllCall("user32\IsWindow", "Ptr", hwnd)
        return 0
    switch state
    {
        case 1:
            LauncherBadgeTestState := "unread"
        case 2:
            LauncherBadgeTestState := "viewed"
        case 3:
            LauncherBadgeTestState := "none"
        default:
            return 0
    }
    if LauncherBadgeTestState = "none"
        SetLauncherUpdateAvailable(false)
    else
        SetLauncherUpdateAvailable(true, "0.1.22-alpha")
    return 1
}
