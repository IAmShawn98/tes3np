; Safe update client. Installation remains an explicit user action.

global UpdateBusy := false
global UpdateStartupRequest := 0
global UpdateStartupStarted := 0
global LauncherVersionLabel := 0
global LauncherUpdateBadge := 0
global LauncherUpdateNumber := 0
global LauncherUnreadReleaseJob := 0
global LauncherObservedUpdateVersion := ""
global LauncherPublishedVersions := []
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
    global LauncherGui, LauncherVersionLabel, LauncherUpdateBadge, LauncherUpdateNumber
    x := GetLauncherUnreadBadgeX(LauncherVersionLabel, 1)
    ; A blank alpha-transparent red disk supplies a genuinely circular edge.
    ; The white number sits entirely inside the circle with no baked-in "1".
    LauncherUpdateBadge := LauncherGui.Add("Picture",
        "x" x " y689 w22 h22 +0x40 BackgroundTrans",
        A_ScriptDir "\assets\controls\update-unread-circle.png")
    LauncherUpdateNumber := LauncherGui.Add("Text",
        "x" (x + 4) " y694 w14 h11 Center +0x200 BackgroundD63232", "1")
    LauncherUpdateNumber.SetFont("s10 Bold cFFFFFF", "Segoe UI")
    LauncherUpdateBadge.OnEvent("Click", CheckForUpdates)
    LauncherUpdateNumber.OnEvent("Click", CheckForUpdates)
    LauncherUpdateNumber.Visible := false
    LauncherUpdateBadge.Visible := false
}

ScaleLauncherVersionLabel(scale)
{
    global LauncherVersionLabel, LauncherUpdateBadge, LauncherUpdateNumber
    if IsObject(LauncherVersionLabel)
        LauncherVersionLabel.SetFont("s" Max(5, Round(9 * scale)), "Segoe UI")
    ApplyLauncherBadgeFont(scale)
    if IsObject(LauncherUpdateBadge)
        ShapeCircularUpdateBadge(LauncherUpdateBadge)
    if IsObject(LauncherUpdateNumber)
        SetLauncherUnreadBadgeNumber(LauncherUpdateNumber.Text)
}

; Preserve the red unread notification at the saved launcher scale.
ApplyLauncherBadgeFont(scale, sample := 0)
{
    global LauncherUpdateNumber
    number := IsObject(sample) ? sample : LauncherUpdateNumber
    if !IsObject(number)
        return
    ; Use more of the existing red circle for visibly larger white digits.
    ; Measure the actual native glyphs and back off only if they would clip.
    size := Max(6, Round(16 * scale / GetLauncherBadgeDpiScale()))
    bounds := Buffer(16, 0)
    if !DllCall("user32\GetClientRect", "Ptr", number.Hwnd,
        "Ptr", bounds, "Int")
    {
        number.SetFont("s" size " Bold cFFFFFF", "Segoe UI")
        return
    }
    availableWidth := Max(1, NumGet(bounds, 8, "Int") - 1)
    availableHeight := Max(1, NumGet(bounds, 12, "Int"))
    Loop 12
    {
        number.SetFont("s" size " Bold cFFFFFF", "Segoe UI")
        try
        {
            if ReleaseNoteFits(number, number.Text,
                availableWidth) && ReleaseNoteLineHeight(number) <= availableHeight
                break
        }
        catch Error
            break
        if size <= 3
            break
        size -= 1
    }
}

; Clip both the red Picture and its numeral Text overlay to true circles.
; Windows owns the transferred GDI region lifetime.
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
    ; Always preserve a true circle at every unread count.
    region := DllCall("gdi32\CreateEllipticRgn", "Int", 0, "Int", 0,
        "Int", diameter, "Int", diameter, "Ptr")
    if region && !DllCall("user32\SetWindowRgn", "Ptr", control.Hwnd,
        "Ptr", region, "Int", 1, "Int")
        DllCall("gdi32\DeleteObject", "Ptr", region)
}

SetLauncherUpdateAvailable(isAvailable, latestVersion := "", unreadCount := 1)
{
    global AppConfig, LauncherUpdateBadge, LauncherUpdateNumber, LauncherVersionLabel
    global LauncherScale, LauncherObservedUpdateVersion
    if !IsObject(LauncherUpdateBadge) || !IsObject(LauncherUpdateNumber)
        return
    LauncherVersionLabel.Visible := true
    available := isAvailable && latestVersion != "" && unreadCount > 0
        && GetLauncherUpdateKind(AppConfig.Version, latestVersion) != ""
    ; Keep this reference even when the offered release is read: an earlier
    ; missed version may remain unread and the background scan may finish.
    LauncherObservedUpdateVersion := isAvailable ? latestVersion : ""
    wasVisible := LauncherUpdateBadge.Visible
    if !available
    {
        if wasVisible
        {
            LauncherUpdateNumber.Visible := false
            LauncherUpdateBadge.Visible := false
            RedrawLauncherUpdateBadge()
        }
        return
    }
    SetLauncherUnreadBadgeNumber(unreadCount)
    if !wasVisible
    {
        LauncherUpdateBadge.Visible := true
        LauncherUpdateNumber.Visible := true
        RedrawLauncherUpdateBadge()
    }
}

GetLauncherBadgeDpiScale()
{
    global LauncherGui
    ; GuiControl.Move/GetPos apply Windows DPI scaling automatically.
    ; The old code requested 25 logical px, producing a roughly 52px
    ; circle on the user's high-DPI launcher. Convert the desired *screen*
    ; pixels back to GUI coordinates before requesting the bitmap.
    try
    {
        if IsObject(LauncherGui)
        {
            dpi := DllCall("user32\GetDpiForWindow", "Ptr", LauncherGui.Hwnd, "UInt")
            if dpi >= 96
                return dpi / 96
        }
    }
    catch Error
    {
        ; GetDpiForWindow is unavailable on older Windows versions.
    }
    return Max(1, A_ScreenDPI / 96)
}

; Anchor to the actual RENDERED end of the version label, not the
; deliberately padded Text-control width (which created the large gap).
; GetTextExtentPoint32W returns device pixels; GUI GetPos uses DPI-aware
; coordinates, so convert before composing the adjacent X position.
GetLauncherUnreadBadgeX(label, scale)
{
    label.GetPos(&labelX, , &labelWidth)
    dpi := GetLauncherBadgeDpiScale()
    try
    {
        textPixels := MeasureMissedUpdateTextWidth(label, label.Text)
        textWidth := Ceil(textPixels / dpi)
        if textWidth > 0
            return labelX + Min(labelWidth, textWidth + 1) + Max(1, Round(3 * scale))
    }
    catch Error
    {
        ; A missing device context must not keep the launcher from loading.
    }
    ; Fall back to the unpadded original width, not the 12.5%-extended box.
    return labelX + Round(Max(1, labelWidth - 4) / 1.125) + Max(1, Round(3 * scale))
}

LauncherUnreadBadgeDiameter(count, scale)
{
    digits := StrLen("" Max(1, count))
    ; At full launcher scale, "24" gets ~23 PHYSICAL pixels, not the
    ; image's 48px native size. Smaller launcher scales retain a readable 20px min.
    physical := Max(20, Round((21 + 6 * (digits - 1)) * scale))
    return Max(1, Round(physical / GetLauncherBadgeDpiScale()))
}

SetLauncherUnreadBadgeNumber(count)
{
    global LauncherUpdateBadge, LauncherUpdateNumber, LauncherVersionLabel, LauncherScale
    if !IsObject(LauncherUpdateBadge) || !IsObject(LauncherUpdateNumber)
        || !IsObject(LauncherVersionLabel)
        return
    value := "" Max(1, Integer(count))
    scale := LauncherScale / 100
    diameter := LauncherUnreadBadgeDiameter(count, scale)
    LauncherUpdateBadge.GetPos(&oldX, , &oldWidth, &oldHeight)
    x := GetLauncherUnreadBadgeX(LauncherVersionLabel, scale)
    if LauncherUpdateNumber.Text = value && oldWidth = diameter
        && oldHeight = diameter && oldX = x
        return
    wasVisible := LauncherUpdateBadge.Visible
    if wasVisible
    {
        LauncherUpdateNumber.Visible := false
        LauncherUpdateBadge.Visible := false
        RedrawLauncherUpdateBadge()
    }
    baseY := Round(689 * scale)
    baseDiameter := LauncherUnreadBadgeDiameter(1, scale)
    ; The small circle was sitting slightly above the visible letterforms.
    ; Apply a modest physical-pixel offset, independent of Windows DPI.
    centeredY := baseY - Floor((diameter - baseDiameter) / 2) + Max(1, Round(5 / GetLauncherBadgeDpiScale()))
    ; Explicit bitmap size plus SS_REALSIZECONTROL keeps the 48px PNG from
    ; showing at its native size. Load first, then set final control bounds:
    ; replacing Picture.Value must never re-expand the resized circle.
    bitmapPixels := Max(1, Round(diameter * GetLauncherBadgeDpiScale()))
    LauncherUpdateBadge.Value := "*w" bitmapPixels " *h" bitmapPixels " "
        . A_ScriptDir "\assets\controls\update-unread-circle.png"
    LauncherUpdateBadge.Move(x, centeredY, diameter, diameter)
    ; Give the numeral a larger, concentric circular overlay. Clip its red
    ; background too, so there are no square corners around the PNG circle.
    innerWidth := Max(1, Round(diameter * 0.90))
    innerHeight := innerWidth
    LauncherUpdateNumber.Move(x + Floor((diameter - innerWidth) / 2),
        centeredY + Floor((diameter - innerHeight) / 2), innerWidth, innerHeight)
    LauncherUpdateNumber.Text := value
    ShapeCircularUpdateBadge(LauncherUpdateNumber)
    ApplyLauncherBadgeFont(scale)
    ShapeCircularUpdateBadge(LauncherUpdateBadge)
    if wasVisible
    {
        LauncherUpdateBadge.Visible := true
        LauncherUpdateNumber.Visible := true
        RedrawLauncherUpdateBadge()
    }
}

; Demo rows have per-row, in-memory IDs. They never write player settings.
SetLauncherDemoUnreadCount(count)
{
    global LauncherUpdateBadge, LauncherUpdateNumber
    if !IsObject(LauncherUpdateBadge)
        return
    if count <= 0
    {
        LauncherUpdateNumber.Visible := false
        LauncherUpdateBadge.Visible := false
        RedrawLauncherUpdateBadge()
        return
    }
    SetLauncherUnreadBadgeNumber(count)
    LauncherUpdateBadge.Visible := true
    LauncherUpdateNumber.Visible := true
    RedrawLauncherUpdateBadge()
}

ShowDevelopmentUnreadBadgeSample(count)
{
    SetLauncherDemoUnreadCount(count)
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
        SetLauncherUpdateAvailable(available, manifest.version,
            IsPublishedVersionRead(manifest.version) ? 0 : 1)
        if available
        {
            ; The currently offered update might already be read while
            ; earlier missed versions still contribute to the footer count.
            StartLauncherUnreadReleaseCount(AppConfig.Version, manifest.version)
            if !HasSeenUpdateAutoPreview(manifest.version)
                SetTimer(AutoPreviewNewUpdate.Bind(manifest.version), -4000)
        }
        LogLauncherEvent("UPDATE | Startup availability check | Current: v" AppConfig.Version " | Latest: v" manifest.version " | Available: " (available ? "yes" : "no") " | Elapsed: " elapsed "ms.")
    } catch Error as err {
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        SetLauncherUpdateAvailable(false)
        LogLauncherEvent("UPDATE | Startup availability check unavailable (" Type(err) ") after " elapsed "ms.")
    }
}

; Run the existing, verified published-history reader off the GUI thread.
; Only genuine GitHub releases (not draft tags or local notes) contribute to
; this unread count. This uses the same safe, bounded five-page feed as the
; full update preview and never installs or downloads a launcher build.
StartLauncherUnreadReleaseCount(installed, latest)
{
    global BundledResourceRoot, LauncherUnreadReleaseJob
    if IsObject(LauncherUnreadReleaseJob)
        return
    ParseTes3npVersion(installed)
    ParseTes3npVersion(latest)
    script := (A_IsCompiled ? BundledResourceRoot : A_ScriptDir) "\scripts\fetch-release-notes.ps1"
    if !FileExist(script)
        return
    prefix := A_Temp "\tes3np-unread-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount
    releaseFile := prefix "-releases.txt"
    hotfixFile := prefix "-hotfixes.txt"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' script
        . '" -InstalledVersion "' installed '" -LatestVersion "' latest
        . '" -ReleaseOutputPath "' releaseFile '" -HotfixOutputPath "' hotfixFile '"'
    try
    {
        Run(command, A_ScriptDir, "Hide", &pid)
        LauncherUnreadReleaseJob := {Pid: pid, Start: A_TickCount,
            Installed: installed, Latest: latest,
            ReleaseFile: releaseFile, HotfixFile: hotfixFile}
        SetTimer(PollLauncherUnreadReleaseCount, 200)
    }
    catch Error as err
        LogLauncherEvent("UPDATE | Unread published-release count unavailable (" Type(err) ").")
}

; Read the subprocess result only after it exits; never block the GUI or
; guess how many hotfix tags were published.
PollLauncherUnreadReleaseCount(*)
{
    global LauncherUnreadReleaseJob, LauncherObservedUpdateVersion, LauncherPublishedVersions
    job := LauncherUnreadReleaseJob
    if !IsObject(job)
    {
        SetTimer(PollLauncherUnreadReleaseCount, 0)
        return
    }
    if A_TickCount - job.Start > 60000
    {
        SetTimer(PollLauncherUnreadReleaseCount, 0)
        LauncherUnreadReleaseJob := 0
        try ProcessClose(job.Pid)
        CleanupUnreadReleaseCountFiles(job)
        LogLauncherEvent("UPDATE | Unread published-release count timed out.")
        return
    }
    if ProcessExist(job.Pid)
        return
    SetTimer(PollLauncherUnreadReleaseCount, 0)
    LauncherUnreadReleaseJob := 0
    try
    {
        if !FileExist(job.ReleaseFile) || !FileExist(job.HotfixFile)
            throw Error("GitHub published-history scan did not complete.")
        records := []
        AddPublishedNoteRecords(FileRead(job.ReleaseFile, "UTF-8"), records)
        AddPublishedNoteRecords(FileRead(job.HotfixFile, "UTF-8"), records)
        latestFound := false
        for record in records
            if record.Version = job.Latest
                latestFound := true
        if !latestFound
            throw Error("Unread count did not include the verified latest release.")
        if LauncherObservedUpdateVersion = job.Latest
        {
            LauncherPublishedVersions := records
            unread := CountUnseenPublishedUpdateRecords(records, job.Installed)
            SetLauncherUpdateAvailable(true, job.Latest, unread.Count)
            LogLauncherEvent("UPDATE | Verified " unread.Count " unread published release(s).")
        }
    }
    catch Error as err
        LogLauncherEvent("UPDATE | Unread published-release count unavailable (" Type(err) ").")
    finally
        CleanupUnreadReleaseCountFiles(job)
}

CleanupUnreadReleaseCountFiles(job)
{
    try FileDelete(job.ReleaseFile)
    try FileDelete(job.HotfixFile)
}

; Per-version receipts persist in settings.ini without removing the
; release entry. Reading the current offered version does not clear older
; unread versions. The legacy scalar is used only for the *exact* old receipt.
IsPublishedVersionRead(version, fixturePath := "")
{
    global DataFile
    ParseTes3npVersion(version)
    path := fixturePath != "" ? fixturePath : DataFile
    if IniRead(path, "ReadPublishedVersions", version, "") = "1"
        return true
    return IniRead(path, "Updates", "LastAutoPreviewVersion", "") = version
}

MarkPublishedVersionRead(version, offered := false, fixturePath := "")
{
    global DataFile, AppDataDirectory
    ParseTes3npVersion(version)
    if fixturePath = ""
        DirCreate(AppDataDirectory)
    path := fixturePath != "" ? fixturePath : DataFile
    IniWrite("1", path, "ReadPublishedVersions", version)
    if offered
        IniWrite(version, path, "Updates", "LastAutoPreviewVersion")
}

; A Map of read versions may be supplied by native offline regression tests.
CountUnseenPublishedUpdateRecords(records, installed, seenState := 0)
{
    unique := Map()
    unread := 0
    for record in records
    {
        version := record.Version
        if unique.Has(version) || GetLauncherUpdateKind(installed, version) = ""
            continue
        unique[version] := true
        read := IsObject(seenState) ? seenState.Has(version) : IsPublishedVersionRead(version)
        if !read
            unread += 1
    }
    return {Count: unread}
}

; Recount the same verified records that remain visible in the menu.
; A delayed background scan also checks the latest read receipts before it
; can repaint the footer, so it cannot resurrect cleared notifications.
RefreshLauncherPublishedUnreadCount(versions := 0, latest := "")
{
    global AppConfig, LauncherPublishedVersions, LauncherObservedUpdateVersion
    ; A temporarily unavailable changelog must not discard previously
    ; verified history or make older unread notifications disappear.
    if IsObject(versions) && versions.Length
        LauncherPublishedVersions := versions
    if latest = ""
        latest := LauncherObservedUpdateVersion
    if latest = ""
        return
    count := CountUnseenPublishedUpdateRecords(LauncherPublishedVersions, AppConfig.Version).Count
    SetLauncherUpdateAvailable(true, latest, count)
}

HasSeenUpdateAutoPreview(version)
{
    global DataFile
    if IsPublishedVersionRead(version)
        return true
    ; Automatic popup suppression stays monotonic if a stale manifest
    ; temporarily advertises an older release. This does NOT mark older
    ; historical versions read or subtract them from the footer count.
    seen := IniRead(DataFile, "Updates", "LastAutoPreviewVersion", "")
    if seen = ""
        return false
    try
    {
        if ParseTes3npVersion(seen).Channel = ParseTes3npVersion(version).Channel
            return CompareUpdateNoteVersions(seen, version) >= 0
    }
    catch Error
        return false
    return false
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
        ; Entering the preview marks only the offered release as read.
        ; Older published versions stay unread until individually clicked
        ; or cleared by the user's explicit Clear action.
        LogLauncherEvent("UPDATE | Update available: v" latest ".")
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
