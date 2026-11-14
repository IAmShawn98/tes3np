; Safe update client. Installation remains an explicit user action.

global UpdateReleasePage := "https://github.com/IAmShawn98/tes3np-releases/releases/tag/latest-alpha"
global UpdateManifestUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-update.json"
global UpdatePackageUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-windows.zip"
global UpdateBusy := false
global UpdateStartupRequest := 0
global UpdateStartupStarted := 0

CheckForUpdateAvailability(*)
{
    global UpdateManifestUrl, UpdateStartupRequest, UpdateStartupStarted
    ; The automatic startup check must not block the AHK GUI thread while
    ; waiting for GitHub. Manual checks still use the existing trusted flow.
    if IsObject(UpdateStartupRequest)
        return
    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(5000, 5000, 10000, 10000)
        request.Open("GET", UpdateManifestUrl, true)
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
        manifest := ParseAndValidateUpdateManifest(request.ResponseText)
        available := manifest.updateEnabled && CompareTes3npVersions(manifest.version, AppConfig.Version) > 0
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
    if !IsObject(LauncherGui) || !DllCall("user32\\IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        return
    CheckForUpdates()
}

CheckForUpdates(*)
{
    global AppConfig, UpdateManifestUrl, UpdateBusy, LauncherGui, DataFile
    if UpdateBusy {
        LogLauncherEvent("UPDATE | Check ignored because another update operation is active.")
        return
    }
    UpdateBusy := true
    staged := ""
    handedOff := false
    LogLauncherEvent("UPDATE | Checking trusted update manifest. Current: v" AppConfig.Version ".")
    try {
        manifest := ParseAndValidateUpdateManifest(DownloadUpdateText(UpdateManifestUrl))
        latest := manifest.version
        LogLauncherEvent("UPDATE | Manifest validated. Current: v" AppConfig.Version " | Latest: v" latest ".")
        if !manifest.updateEnabled {
            SetLauncherUpdateAvailable(false)
            LogLauncherEvent("UPDATE | Automatic installation disabled by release metadata.")
            ShowUpdateStatusPanel("disabled", AppConfig.Version, latest)
            return
        }
        if CompareTes3npVersions(latest, AppConfig.Version) <= 0 {
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
        ; Viewing the gold preview never downloads, stages, or installs files.
        choice := ShowUpdatePreview(AppConfig.Version, latest, manifest.channel)
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
            LogLauncherEvent("UPDATE | User deferred update v" latest "; clickable version label restored.")
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

CreateUpdateBackdrop(owner := 0)
{
    global LauncherGui
    ; Shared native-card backdrop: changelogs use the launcher; child setup
    ; dialogs can dim their actual owner without covering the entire desktop.
    ; Physical HWND rectangles avoid mixed-DPI clipping of scaled windows.
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
    dim.Show("NA x" lx " y" ly " w" lw " h" lh)
    WinSetTransparent(165, "ahk_id " dim.Hwnd)
    return dim
}

ShowCenteredUpdateCard(dialog, backdrop, width, height)
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

; The version/changelog cards already establish the native dark-and-gold
; prompt visual system. Use that exact frame/dim centering for settings/setup
; instead of another tan, title-barred secondary GUI.
CreateGoldNativePrompt(owner, title, width, height)
{
    backdrop := CreateUpdateBackdrop(owner)
    try
    {
        panel := Gui("-Caption -Border -DPIScale +Owner" backdrop.Hwnd, title)
        panel.MarginX := 0, panel.MarginY := 0
        panel.BackColor := "C5A45C"
        ; Keep the dark interior's HWND so dynamic cards can resize it
        ; together with their outer frame, without exposing a white strip.
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

ShowGoldNativePrompt(panel)
{
    if !IsObject(panel) || !panel.HasOwnProp("NativePromptBackdrop")
        return
    scale := GetOwnedMenuScale()
    ScaleOwnedMenuContent(panel, scale)
    ShowCenteredUpdateCard(panel, panel.NativePromptBackdrop,
        Round(panel.NativePromptWidth * scale), Round(panel.NativePromptHeight * scale))
}

CloseGoldNativePrompt(panel)
{
    if !IsObject(panel)
        return
    backdrop := panel.HasOwnProp("NativePromptBackdrop") ? panel.NativePromptBackdrop : 0
    try panel.Destroy()
    if IsObject(backdrop)
        try backdrop.Destroy()
}

ShowGoldUpdateConfirmation(title, message, confirmLabel)
{
    global LauncherGui
    response := {Accepted: false}
    backdrop := CreateUpdateBackdrop()
    window := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Update Confirmation")
    window.BackColor := "C5A45C"
    window.Add("Text", "x2 y2 w636 h254 Background171008")
    window.SetFont("s15 Bold cC5A45C", "Georgia")
    window.Add("Text", "x32 y26 w588 h32 BackgroundTrans", title)
    window.SetFont("s10 cFFFFFF", "Segoe UI")
    window.Add("Text", "x32 y86 w588 h67 BackgroundTrans", message)
    confirm := AddStyledButton(window, 221, 203, 185, 34, confirmLabel, (*) => (response.Accepted := true, window.Destroy()))
    cancel := AddStyledButton(window, 422, 203, 185, 34, "Not Now", (*) => window.Destroy())
    window.OnEvent("Escape", (*) => window.Destroy())
    window.OnEvent("Close", (*) => window.Destroy())
    ShowCenteredUpdateCard(window, backdrop, 640, 258)
    hwnd := window.Hwnd
    WinWaitClose("ahk_id " hwnd)
    backdrop.Destroy()
    return response.Accepted
}

ShowUpdatePreview(installedVersion, latestVersion, channel)
{
    global UpdateReleasePage
    notes := ReadPublishedVersionNotes(latestVersion)
    response := {Download: false}
    backdrop := CreateUpdateBackdrop()
    preview := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Update Preview")
    preview.BackColor := "C5A45C"
    preview.Add("Text", "x2 y2 w796 h626 Background171008")
    preview.SetFont("s15 Bold cC5A45C", "Georgia")
    releaseType := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Stable"
    preview.Add("Text", "x30 y20 w740 h38 BackgroundTrans", "A New " releaseType " Is Available to Download, S'wit!")
    preview.SetFont("s10 cEDE1C9", "Segoe UI")
    preview.Add("Text", "x30 y62 w740 h24 BackgroundTrans", "You can review the changes below before deciding to update.")
    preview.Add("Text", "x30 y94 w195 h24 BackgroundTrans", "Installed: v" installedVersion)
    preview.Add("Text", "x238 y94 w195 h24 BackgroundTrans", "Latest: v" latestVersion)
    preview.Add("Text", "x446 y94 w324 h24 BackgroundTrans", "Channel: " (channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Live Stable"))
    preview.SetFont("s10 Bold cC5A45C", "Segoe UI")
    preview.Add("Text", "x30 y125 w740 h25 BackgroundTrans", "v" latestVersion " Release Notes")
    closeNotes := AddUpdateNotesViewport(preview, notes)
    preview.SetFont("s10 cC5A45C", "Segoe UI")
    preview.Add("Text", "x30 y529 w740 h22 BackgroundTrans", "A newer version is available. Review the release details before choosing to download.")
    preview.Add("Text", "x30 y551 w740 h22 BackgroundTrans", "Preview only — nothing has been downloaded or installed.")
    AddStyledButton(preview, 32, 582, 230, 34, "Continue to Download", (*) => (response.Download := true, preview.Destroy()))
    AddStyledButton(preview, 330, 582, 140, 34, "Not Now", (*) => preview.Destroy())
    AddStyledButton(preview, 590, 582, 178, 34, "Release Notes", (*) => Run(UpdateReleasePage))
    preview.OnEvent("Close", (*) => preview.Destroy())
    preview.OnEvent("Escape", (*) => preview.Destroy())
    try {
        hwnd := preview.Hwnd
        ShowCenteredUpdateCard(preview, backdrop, 800, 630)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        closeNotes()
        backdrop.Destroy()
    }
    return response.Download ? "Yes" : "No"
}

ReadBundledVersionNotes(version)
{
    changelog := A_ScriptDir "\RELEASE_NOTES.md"
    try content := StrReplace(FileRead(changelog, "UTF-8"), "`r", "")
    catch
        return ""
    collecting := false
    notes := ""
    for line in StrSplit(content, "`n") {
        if RegExMatch(line, "^##[ \t]+") {
            if collecting
                break
            collecting := RegExMatch(line, "^##[ \t]+v(\S+)", &heading) && heading[1] = version
            continue
        }
        if collecting
            notes .= line "`n"
    }
    return Trim(notes, " `t`n")
}

ReadVersionReleaseNotes(version)
{
    bundled := ReadBundledVersionNotes(version)
    return bundled != "" ? bundled : ReadPublishedVersionNotes(version)
}

ReadPublishedVersionNotes(version)
{
    global BundledResourceRoot
    script := (A_IsCompiled ? BundledResourceRoot : A_ScriptDir) "\scripts\fetch-release-notes.ps1"
    unavailable := "Release notes for v" version " are currently unavailable. Check GitHub Releases for details."
    if !FileExist(script)
        return unavailable
    output := A_Temp "\tes3np-notes-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount ".txt"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' script
        . '" -Version "' version '" -OutputPath "' output '"'
    try {
        if RunWait(command, A_ScriptDir, "Hide") != 0 || !FileExist(output)
            return unavailable
        return FileRead(output, "UTF-8")
    } catch Error {
        return unavailable
    } finally {
        try FileDelete(output)
    }
}

ReleaseNoteFits(control, text, maxWidth)
{
    ; Measure against the actual Windows font on this label, not a guessed
    ; character count (proportional glyphs and DPI affect the pixel width).
    if text = ""
        return true
    hFont := SendMessage(0x31, 0, 0, , "ahk_id " control.Hwnd) ; WM_GETFONT
    dc := DllCall("user32\GetDC", "Ptr", control.Hwnd, "Ptr")
    if !dc
        return false
    oldFont := hFont ? DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", hFont, "Ptr") : 0
    size := Buffer(8, 0)
    success := DllCall("gdi32\GetTextExtentPoint32W", "Ptr", dc, "Str", text,
        "Int", StrLen(text), "Ptr", size, "Int")
    if oldFont
        DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldFont)
    DllCall("user32\ReleaseDC", "Ptr", control.Hwnd, "Ptr", dc)
    return success && NumGet(size, 0, "Int") <= maxWidth
}

WrapReleaseNoteLines(line, control, maxWidth)
{
    parts := []
    remaining := Trim(line)
    while remaining != "" {
        if ReleaseNoteFits(control, remaining, maxWidth) {
            parts.Push(remaining)
            break
        }
        ; Break on the last word boundary which actually fits on screen.
        splitAt := 0
        pos := 1
        while (pos := InStr(remaining, " ", , pos)) {
            if !ReleaseNoteFits(control, SubStr(remaining, 1, pos - 1), maxWidth)
                break
            splitAt := pos
            pos += 1
        }
        if splitAt > 0 {
            parts.Push(RTrim(SubStr(remaining, 1, splitAt - 1)))
            remaining := LTrim(SubStr(remaining, splitAt + 1))
            continue
        }
        ; Even exceptionally long unbroken tokens must not be clipped.
        cut := 1
        while cut < StrLen(remaining) && ReleaseNoteFits(control, SubStr(remaining, 1, cut + 1), maxWidth)
            cut += 1
        parts.Push(SubStr(remaining, 1, cut))
        remaining := LTrim(SubStr(remaining, cut + 1))
    }
    return parts
}

; Render plain category headings and bullet points, as shown in RELEASE_NOTES.md.
; Each on-screen row is measured in the real control font before scrolling.
BuildStyledReleaseNoteRows(content, measureRow, maxWidth)
{
    rows := []
    for entry in StrSplit(StrReplace(content, "`r", ""), "`n") {
        line := Trim(entry)
        if line = "" {
            if rows.Length && rows[rows.Length].Kind != "space"
                rows.Push({Text: "", Kind: "space"})
            continue
        }
        kind := "body"
        if RegExMatch(line, "^#{1,6}\s+") {
            line := RegExReplace(line, "^#{1,6}\s+", "")
            if rows.Length && rows[rows.Length].Kind != "space"
                rows.Push({Text: "", Kind: "space"})
            kind := "heading"
        } else if RegExMatch(line, "^[-*+]\s+") {
            line := "• " RegExReplace(line, "^[-*+]\s+", "")
            line := StrReplace(line, "**", "")
        }
        measureRow.SetFont(kind = "heading" ? "s11 Bold cE7BE70" : "s10 cF4E9D6", "Segoe UI")
        for part in WrapReleaseNoteLines(line, measureRow, maxWidth)
            rows.Push({Text: part, Kind: kind})
    }
    measureRow.SetFont("s10 cF4E9D6", "Segoe UI")
    if !rows.Length
        rows.Push({Text: "No release notes available.", Kind: "body"})
    return rows
}

UpdateNotesMouseWheel(dialog, page, refresh, wParam, lParam, msg, hwnd)
{
    ; The Windows wheel coordinates are physical screen pixels. Compare with
    ; the actual dialog window rectangle to avoid mixed-DPI hit-test errors.
    if !DllCall("user32\IsWindow", "Ptr", dialog.Hwnd, "Int")
        return
    mx := (lParam & 0xFFFF) << 48 >> 48
    my := ((lParam >> 16) & 0xFFFF) << 48 >> 48
    bounds := Buffer(16, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", dialog.Hwnd, "Ptr", bounds)
        return
    if mx < NumGet(bounds, 0, "Int") || mx >= NumGet(bounds, 8, "Int")
        || my < NumGet(bounds, 4, "Int") || my >= NumGet(bounds, 12, "Int")
        return
    delta := (wParam >> 16) << 48 >> 48
    page.Offset += delta > 0 ? -3 : 3
    refresh()
    return 0
}

UpdateNotesDragMove(drag, page, refresh)
{
    if !drag.Active
        return
    if !GetKeyState("LButton", "P") {
        drag.Active := false
        SetTimer(drag.Timer, 0)
        DllCall("user32\ReleaseCapture")
        return
    }
    cursor := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "Ptr", cursor)
    mouseY := NumGet(cursor, 4, "Int")
    maxOffset := Max(1, page.Lines.Length - page.Visible + 1)
    ; Mouse coordinates are physical pixels; use the actual on-screen track size.
    travel := Max(1, drag.TrackPixels - drag.ThumbPixels)
    page.Offset := 1 + Round((mouseY - drag.StartY) * (maxOffset - 1) / travel) + drag.StartOffset - 1
    refresh()
}

StartUpdateNotesDrag(panel, thumb, track, drag, page, refresh, wParam, lParam, msg, hwnd)
{
    if page.Lines.Length <= page.Visible
        return
    ; Static text controls do not reliably receive WM_LBUTTONDOWN themselves.
    ; Detect a press over the thumb by screen position, regardless of whether
    ; Windows delivers it to the thumb, its track, or the dialog.
    if DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != panel.Hwnd
        && hwnd != panel.Hwnd
        return
    cursor := Buffer(8, 0)
    if !DllCall("user32\GetCursorPos", "Ptr", cursor)
        return
    mouseX := NumGet(cursor, 0, "Int")
    mouseY := NumGet(cursor, 4, "Int")
    trackRect := Buffer(16, 0)
    thumbRect := Buffer(16, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", track.Hwnd, "Ptr", trackRect)
        || !DllCall("user32\GetWindowRect", "Ptr", thumb.Hwnd, "Ptr", thumbRect)
        return
    ; Make the slender gold handle easier to grab without changing its design.
    if mouseX < NumGet(trackRect, 0, "Int") - 5
        || mouseX > NumGet(trackRect, 8, "Int") + 5
        || mouseY < NumGet(thumbRect, 4, "Int") - 3
        || mouseY > NumGet(thumbRect, 12, "Int") + 3
        return
    drag.Active := true
    drag.StartY := mouseY
    drag.StartOffset := page.Offset
    drag.TrackPixels := NumGet(trackRect, 12, "Int") - NumGet(trackRect, 4, "Int")
    drag.ThumbPixels := NumGet(thumbRect, 12, "Int") - NumGet(thumbRect, 4, "Int")
    DllCall("user32\SetCapture", "Ptr", panel.Hwnd)
    drag.Timer := UpdateNotesDragMove.Bind(drag, page, refresh)
    SetTimer(drag.Timer, 16)
    return 0
}

AddUpdateNotesViewport(panel, notes)
{
    panel.SetFont("s10 cEDE1C9", "Segoe UI")
    ; Gold-framed notes with the same vertical gold-on-brown scrollbar used
    ; by the launcher parchment. Arrows live at the ends of the track.
    panel.Add("Text", "x28 y158 w744 h367 BackgroundC5A45C")
    panel.Add("Text", "x30 y160 w740 h363 Background171008")
    page := {Offset: 1, Lines: [], Visible: 13}
    noteRows := []
    rowStyles := []
    Loop page.Visible {
        panel.SetFont("s10 cF4E9D6", "Segoe UI")
        noteRows.Push(panel.Add("Text", "x42 y" (176 + (A_Index - 1) * 26) " w686 h24 Background171008 +0x80", ""))
        rowStyles.Push("body")
    }
    ; Leave an extra pixel gutter for font rasterization and scroll safety.
    page.Lines := BuildStyledReleaseNoteRows(notes, noteRows[1], 674)
    track := panel.Add("Text", "x746 y188 w16 h309 Background704C27")
    thumb := panel.Add("Text", "x750 y188 w8 h32 +0x100 BackgroundC69951")
    drag := {Active: false, StartY: 0, StartOffset: 1, ThumbHeight: 32, Timer: 0}
    refresh(*) {
        maxOffset := Max(1, page.Lines.Length - page.Visible + 1)
        page.Offset := Min(maxOffset, Max(1, page.Offset))
        for index, row in noteRows {
            rowIndex := index + page.Offset - 1
            entry := rowIndex <= page.Lines.Length ? page.Lines[rowIndex] : {Text: "", Kind: "body"}
            if rowStyles[index] != entry.Kind {
                row.SetFont(entry.Kind = "heading" ? "s11 Bold cE7BE70" : "s10 cF4E9D6", "Segoe UI")
                rowStyles[index] := entry.Kind
            }
            row.Text := entry.Text
        }
        thumbHeight := Max(22, Round(309 * Min(1, page.Visible / Max(1, page.Lines.Length))))
        drag.ThumbHeight := thumbHeight
        thumb.Move(750, 188 + Round((309 - thumbHeight) * (page.Offset - 1) / Max(1, maxOffset - 1)), 8, thumbHeight)
        track.Visible := page.Lines.Length > page.Visible
        thumb.Visible := page.Lines.Length > page.Visible
    }
    dragStartCallback := StartUpdateNotesDrag.Bind(panel, thumb, track, drag, page, refresh)
    OnMessage(0x0201, dragStartCallback, 1)
    scrollUp := AddStyledButton(panel, 744, 163, 20, 22, "↑", (*) => (page.Offset -= 1, refresh()))
    scrollDown := AddStyledButton(panel, 744, 500, 20, 22, "↓", (*) => (page.Offset += 1, refresh()))
    refresh()
    ; Register an additional wheel callback only for this dialog's lifetime.
    ; It consumes wheel input solely inside the release-notes viewport.
    wheelCallback := UpdateNotesMouseWheel.Bind(panel, page, refresh)
    OnMessage(0x020A, wheelCallback, 1)
    unregister() {
        OnMessage(0x020A, wheelCallback, 0)
        OnMessage(0x0201, dragStartCallback, 0)
        if drag.Active {
            drag.Active := false
            SetTimer(drag.Timer, 0)
            DllCall("user32\ReleaseCapture")
        }
    }
    return unregister
}

ShowUpdateStatusPanel(mode, installedVersion, latestVersion := "")
{
    newer := mode = "disabled" && CompareTes3npVersions(latestVersion, installedVersion) > 0
    notesVersion := newer ? latestVersion : installedVersion
    title := "You're All Caught Up, Fetcher!"
    message := "You are running the latest and greatest version of the tes3np launcher! If an update is published, you will be notified."
    if mode = "error" {
        title := "Could Not Check for Updates"
        message := "Showing release notes for your installed version."
    } else if mode = "disabled" {
        title := "Automatic Updates Are Unavailable"
        message := "Check GitHub Releases for download options."
    }
    notes := newer ? ReadPublishedVersionNotes(notesVersion) : ReadVersionReleaseNotes(installedVersion)
    state := {Retry: false}
    backdrop := CreateUpdateBackdrop()
    panel := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Version Status")
    panel.BackColor := "C5A45C"
    panel.Add("Text", "x2 y2 w796 h596 Background171008")
    panel.SetFont("s14 Bold cC5A45C", "Georgia")
    panel.Add("Text", "x30 y20 w740 h38 BackgroundTrans", title)
    panel.SetFont("s10 cEDE1C9", "Segoe UI")
    panel.Add("Text", "x30 y65 w740 h55 BackgroundTrans", message)
    panel.SetFont("s10 Bold cC5A45C", "Segoe UI")
    panel.Add("Text", "x30 y125 w740 h25 BackgroundTrans", "Build: v" notesVersion " Release Notes -")
    closeNotes := AddUpdateNotesViewport(panel, notes)
    AddStyledButton(panel, 178, 544, 212, 34, "Check For Updates", (*) => (state.Retry := true, panel.Destroy()))
    AddStyledButton(panel, 410, 544, 212, 34, "Close", (*) => panel.Destroy())
    panel.OnEvent("Close", (*) => panel.Destroy())
    panel.OnEvent("Escape", (*) => panel.Destroy())
    try {
        hwnd := panel.Hwnd
        ShowCenteredUpdateCard(panel, backdrop, 800, 600)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        closeNotes()
        backdrop.Destroy()
    }
    if state.Retry
        SetTimer(CheckForUpdates, -100)
}

StartTransactionalUpdate(version, staged)
{
    worker := A_ScriptDir "\scripts\tes3np-updater.ps1"
    stateFile := staged "\update-state.ini"

    if PatchInProgress()
        throw Error("Finish the Expansion Pack import before updating.")
    if !FileExist(worker)
        throw Error("Updater worker is missing from this installation.")
    if !FileExist(stateFile)
        throw Error("Update state file is missing.")

    pid := DllCall("GetCurrentProcessId", "UInt")

    psArgs := '-NoProfile -ExecutionPolicy Bypass -File "' worker
        . '" -InstallDir "' A_ScriptDir
        . '" -StageDir "' staged '\staged'
        . '" -StateFile "' stateFile
        . '" -Version "' version
        . '" -ManagedStage -ParentPid ' pid

    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    Run('"' powershell '" ' psArgs, A_ScriptDir, "Hide")

    ; Give the detached updater worker time to start before tes3np exits.
    Sleep(500)
}

RecoverInterruptedLauncherUpdate()
{
    if !A_IsCompiled || !FileExist(A_ScriptDir ".tes3np-recovery\pending.txt")
        return
    worker := A_ScriptDir "\scripts\tes3np-updater.ps1"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    pid := DllCall("GetCurrentProcessId", "UInt")
    Run('"' powershell '" -NoProfile -ExecutionPolicy Bypass -File "' worker
        . '" -InstallDir "' A_ScriptDir '" -Version "' AppConfig.Version
        . '" -RecoverOnly -ParentPid ' pid, A_ScriptDir, "Hide")
    ExitApp(0)
}

GetFullPath(path)
{
    size := DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    if !size
        throw Error("Unable to resolve the full file path.")
    pathBuffer := Buffer(size * 2, 0)
    if !DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", size, "Ptr", pathBuffer, "Ptr", 0, "UInt")
        throw Error("Unable to resolve the full file path.")
    return StrGet(pathBuffer)
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

DownloadAndStageUpdate(manifest)
{
    global UpdatePackageUrl
    root := A_Temp "\tes3np-update\" NewLauncherFileId()
    part := root "\tes3np-windows.zip.part"
    stage := root "\staged"
    DirCreate(root)
    try {
        SetInterfaceLoadingText("Downloading update...")
        LogLauncherEvent("UPDATE | Download started | v" manifest.version ".")
        Download(UpdatePackageUrl, part)
        if !FileExist(part)
            throw Error("Downloaded update package is missing.")
        SetInterfaceLoadingText("Checking download size...")
        if FileGetSize(part) != manifest.size
            throw Error("Downloaded update size does not match trusted metadata.")
        SetInterfaceLoadingText("Verifying update...")
        if SHA256File(part) != StrLower(manifest.sha256)
            throw Error("Downloaded update failed SHA-256 verification.")
        LogLauncherEvent("UPDATE | Download verified | SHA-256 and size match trusted metadata.")
        SetInterfaceLoadingText("Preparing update...")
        ValidateUpdateArchive(part, stage)
        FileDelete(part)
        SetInterfaceLoadingText("Saving update state...")
        state := root "\update-state.ini"
        IniWrite("STAGED", state, "Update", "State")
        IniWrite(manifest.version, state, "Update", "Version")
        return root
    } catch {
        DeleteLauncherStagingTree(root)
        throw
    }
}

ValidateUpdateArchive(package, stage)
{
    SplitPath(package, , &root)
    scriptPath := root "\validate-update.ps1"
    script := "$ErrorActionPreference='Stop'`r`n" .
        "Add-Type -AssemblyName System.IO.Compression.FileSystem`r`n" .
        "$package='" PsQuote(package) "'`r`n" .
        "$stage='" PsQuote(stage) "'`r`n" .
        "$z=[IO.Compression.ZipFile]::OpenRead($package)`r`n" .
        "$root=[IO.Path]::GetFullPath($stage+[IO.Path]::DirectorySeparatorChar)`r`n" .
        "try {`r`n" .
        "  foreach($e in $z.Entries){`r`n" .
        "    $p=[IO.Path]::GetFullPath([IO.Path]::Combine($root,$e.FullName))`r`n" .
        "    if(-not $p.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe archive path'}`r`n" .
        "  }`r`n" .
        "} finally { $z.Dispose() }`r`n" .
        "[IO.Compression.ZipFile]::ExtractToDirectory($package,$stage)`r`n" .
        "$exe=Get-ChildItem -LiteralPath $stage -Filter tes3np.exe -Recurse | Select-Object -First 1`r`n" .
        "if(-not $exe){throw 'tes3np.exe missing from staged package'}`r`n"
    try {
        FileAppend(script, scriptPath, "UTF-8")
        shell := ComObject("WScript.Shell")
        command := 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' scriptPath '"'
        exitCode := shell.Run(command, 0, true)
        if exitCode != 0
            throw Error("Update package failed safe staging validation.")
    } finally {
        try FileDelete(scriptPath)
    }
    LogLauncherEvent("UPDATE | Package staged and structure validated.")
}

PsQuote(value) => StrReplace(value, "'", "''")

ParseAndValidateUpdateManifest(text)
{
    manifest := {}
    manifest.manifestVersion := RequireManifestInteger(text, "manifestVersion")
    manifest.product := RequireManifestString(text, "product")
    manifest.channel := RequireManifestString(text, "channel")
    manifest.version := RequireManifestString(text, "version")
    manifest.releaseId := RequireManifestString(text, "releaseId")
    manifest.platform := RequireManifestString(text, "platform")
    manifest.architecture := RequireManifestString(text, "architecture")
    ; The public metadata generator nests the package fields under "package".
    ; Keep support for the older flat manifest layout for prior alpha builds.
    if RegExMatch(text, 's)"package"\s*:\s*\{([^}]*)\}', &packageMatch) {
        packageText := packageMatch[1]
        manifest.fileName := RequireManifestString(packageText, "fileName")
        manifest.size := RequireManifestInteger(packageText, "size")
        manifest.sha256 := RequireManifestString(packageText, "sha256")
    } else {
        manifest.fileName := RequireManifestString(text, "fileName")
        manifest.size := RequireManifestInteger(text, "size")
        manifest.sha256 := RequireManifestString(text, "sha256")
    }
    manifest.updateEnabled := RequireManifestBoolean(text, "updateEnabled")
    if manifest.manifestVersion != 1
        throw Error("Unsupported update manifest version.")
    if manifest.product != "tes3np" || manifest.channel != "alpha"
        throw Error("Update manifest identity/channel mismatch.")
    if manifest.platform != "windows" || manifest.architecture != "x64"
        throw Error("Update package is not for this platform.")
    if !RegExMatch(manifest.version, "^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")
        throw Error("Update manifest contains an invalid version.")
    if manifest.releaseId != "v" manifest.version
        throw Error("Update manifest release identity mismatch.")
    if manifest.fileName != "tes3np-windows.zip"
        throw Error("Update manifest contains an unexpected package name.")
    if manifest.size <= 0
        throw Error("Update manifest contains an invalid package size.")
    if !RegExMatch(manifest.sha256, "i)^[0-9a-f]{64}$")
        throw Error("Update manifest contains an invalid SHA-256 value.")
    return manifest
}

RequireManifestString(text, name) {
    if !RegExMatch(text, '"' name '"\s*:\s*"([^"\\]*)"', &m)
        throw Error("Update manifest is missing or has invalid " name ".")
    return m[1]
}
RequireManifestInteger(text, name) {
    if !RegExMatch(text, '"' name '"\s*:\s*(\d+)', &m)
        throw Error("Update manifest is missing or has invalid " name ".")
    return Integer(m[1])
}
RequireManifestBoolean(text, name) {
    if !RegExMatch(text, 'i)"' name '"\s*:\s*(true|false)', &m)
        throw Error("Update manifest is missing or has invalid " name ".")
    return StrLower(m[1]) = "true"
}

CompareTes3npVersions(left, right)
{
    left := RegExReplace(left, "i)^v"), right := RegExReplace(right, "i)^v")
    leftBase := StrSplit(StrSplit(left, "-")[1], "."), rightBase := StrSplit(StrSplit(right, "-")[1], ".")
    Loop 3 {
        a := A_Index <= leftBase.Length ? Integer(leftBase[A_Index]) : 0
        b := A_Index <= rightBase.Length ? Integer(rightBase[A_Index]) : 0
        if a != b
            return a > b ? 1 : -1
    }
    leftPre := InStr(left, "-") ? SubStr(left, InStr(left, "-") + 1) : ""
    rightPre := InStr(right, "-") ? SubStr(right, InStr(right, "-") + 1) : ""
    if leftPre = rightPre
        return 0
    if leftPre = ""
        return 1
    if rightPre = ""
        return -1
    return StrCompare(leftPre, rightPre, false)
}
