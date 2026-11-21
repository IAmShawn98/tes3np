; Display update status, release previews, and download and install confirmations.

ShowGoldUpdateConfirmation(title, message, confirmLabel)
{
    response := {Accepted: false}
    window := CreateGoldNativePrompt(0, "tes3np — Update Confirmation", 640, 258)
    try {
        window.SetFont("s15 Bold cC5A45C", "Georgia")
        extra := AddGoldPromptCopy(window, 32, 26, 588, 32, title)
        window.SetFont("s10 cFFFFFF", "Segoe UI")
        extra += AddGoldPromptCopy(window, 32, 86 + extra, 588, 67, message)
        AddStyledButton(window, 221, 203 + extra, 185, 34, confirmLabel, (*) => (response.Accepted := true, DestroyScaledMenu(window)))
        AddStyledButton(window, 422, 203 + extra, 185, 34, "Not Now", (*) => DestroyScaledMenu(window))
        GrowGoldNativePrompt(window, extra)
        window.OnEvent("Escape", (*) => DestroyScaledMenu(window))
        window.OnEvent("Close", (*) => DestroyScaledMenu(window))
        hwnd := window.Hwnd
        ShowGoldNativePrompt(window, GetUpdatePromptFitScale(window))
        WinWaitClose("ahk_id " hwnd)
    } finally {
        CloseGoldNativePrompt(window)
    }
    return response.Accepted
}

ShowUpdatePreview(installedVersion, latestVersion, channel, kind)
{
    ; Show only published changes missed since this installed build. The
    ; latest published release is prominent; earlier missed changes expand
    ; on demand without hiding any published notes or changing updater gates.
    notes := ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion, true)
    response := {Download: false}
    preview := CreateGoldNativePrompt(0, "tes3np — Update Preview", 800, 620)
    closeNotes := 0
    try {
        preview.SetFont("s14 Bold cC5A45C", "Georgia")
        releaseType := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Stable"
        title := kind = "hotfix" ? "Hotfix available" : "A New " releaseType " Is Available to Download, S'wit!"
        preview.Add("Text", "x30 y20 w740 h42 BackgroundTrans", title)
        ; Add the mockup's gold box behind the existing Installed / Latest /
        ; Channel captions. Resize it together with the verified metadata
        ; row-wrap logic instead of moving any original wording.
        metadataBorder := preview.Add("Text", "x28 y74 w744 h34 BackgroundC5A45C")
        metadataFill := preview.Add("Text", "x30 y76 w740 h30 Background171008")
        rowExtra := AddUpdatePreviewMetadata(preview, installedVersion, latestVersion, channel)
        if rowExtra
        {
            metadataBorder.Move(, , , 34 + rowExtra)
            metadataFill.Move(, , , 30 + rowExtra)
            GrowGoldNativePrompt(preview, rowExtra)
        }
        preview.SetFont("s12 Bold cC5A45C", "Georgia")
        preview.Add("Text", "x30 y" (118 + rowExtra) " w490 h30 BackgroundTrans", "Changes in This Update")
        noteSwitcher := {Update: 0}
        previewState := {Expanded: false}
        if notes.Title != ""
        {
            preview.SetFont("s12 Bold cE7BE70", "Georgia")
            preview.Add("Text", "x42 y" (161 + rowExtra) " w650 h30 BackgroundTrans", notes.Title)
            preview.SetFont("s10 Bold cFFFFFF", "Segoe UI")
            latestBadge := preview.Add("Text", "x716 y" (163 + rowExtra)
                . " w22 h22 Center +0x200 BackgroundD63232", "1")
        }
        if notes.EarlierCount > 0
        {
            showEarlier := AddStyledButton(preview, 536, 118 + rowExtra, 225, 29,
                "View earlier changes", (*) => TogglePublishedPreviewHistory())
            hideEarlier := AddStyledButton(preview, 536, 118 + rowExtra, 225, 29,
                "Hide earlier changes", (*) => TogglePublishedPreviewHistory())
            hideEarlier.Visible := false
        }
        TogglePublishedPreviewHistory()
        {
            previewState.Expanded := !previewState.Expanded
            ; Object-property function calls pass the object as an extra implicit
            ; argument in AHK v2. Call the stored callback explicitly instead.
            noteSwitcher.Update.Call(previewState.Expanded ? notes.Expanded : notes.Compact)
            showEarlier.Visible := !previewState.Expanded
            hideEarlier.Visible := previewState.Expanded
            PaintGoldUpdateDialogButtons(preview)
        }
        ; Keep both actions together at the lower left, aligned with the
        ; notes panel. The real Update Now action still enters the existing
        ; download and install confirmation flow outside this window.
        actionY := 568 + rowExtra
        AddStyledButton(preview, 32, actionY, 185, 34, "Update Now",
            (*) => (response.Download := true, DestroyScaledMenu(preview)))
        AddStyledButton(preview, 233, actionY, 155, 34, "Not Now", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Close", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Escape", (*) => DestroyScaledMenu(preview))
        scale := GetUpdatePromptFitScale(preview)
        ScaleOwnedMenuContent(preview, scale)
        closeNotes := AddUpdateNotesViewport(preview, notes.Compact, scale,
            noteSwitcher, 44 + rowExtra, 28 + rowExtra)
        if notes.Title != ""
            ShapeCircularUpdateBadge(latestBadge)
        hwnd := preview.Hwnd
        ShowGoldNativePrompt(preview, scale)
        PaintGoldUpdateDialogButtons(preview)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        if IsObject(closeNotes)
            try closeNotes()
        CloseGoldNativePrompt(preview)
    }
    return response.Download ? "Yes" : "No"
}

; Place the preview metadata from the real rendered Text-control widths. The
; installed and latest build strings vary (especially for hotfix versions),
; so hard-coded text-box widths otherwise clip or overlap their neighbors.
; Return the extra vertical space needed if a narrow display requires wrapping.
AddUpdatePreviewMetadata(panel, installedVersion, latestVersion, channel)
{
    panel.SetFont("s10 Bold cEDE1C9", "Segoe UI")
    ; AHK only auto-sizes a Text control reliably to its caption when
    ; neither width nor height is specified. Setting h26 at creation made
    ; GetPos return a narrow default width and truncated Installed metadata.
    ; Capture natural widths first, then apply the fixed one-line height.
    installed := panel.Add("Text", "x30 y80 BackgroundTrans +0x80", "Installed: v" installedVersion)
    latest := panel.Add("Text", "x30 y80 BackgroundTrans +0x80", "Latest: v" latestVersion)
    channelName := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Live Stable"
    channelText := panel.Add("Text", "x30 y80 BackgroundTrans +0x80", "Channel: " channelName)

    installed.GetPos(, , &installedWidth)
    latest.GetPos(, , &latestWidth)
    channelText.GetPos(, , &channelWidth)
    ; Include a little font/DPI rounding tolerance before positioning the
    ; next group, so the final glyph cannot touch the following label.
    installedWidth += 6, latestWidth += 6, channelWidth += 6
    installed.Move(, , installedWidth, 26)
    latest.Move(, , latestWidth, 26)
    channelText.Move(, , channelWidth, 26)
    gap := 18
    latestX := 30 + installedWidth + gap
    channelX := latestX + latestWidth + gap
    if channelX + channelWidth <= 770
    {
        latest.Move(latestX, 80)
        channelText.Move(channelX, 80)
        return 0
    }
    if latestX + latestWidth <= 770
    {
        latest.Move(latestX, 80)
        channelText.Move(30, 112)
        return 32
    }
    latest.Move(30, 112)
    channelText.Move(30, 144)
    return 64
}

ShowUpdateStatusPanel(mode, installedVersion, latestVersion := "")
{
    ; The version-status screen describes the installed package, never an
    ; uninstalled update advertised by a disabled feed.
    notesVersion := installedVersion
    title := "You're All Caught Up, Fetcher!"
    message := "If an update is published, you will be notified."
    if mode = "error" {
        title := "Could Not Check for Updates"
        message := "Showing release notes for your installed version."
    } else if mode = "disabled" {
        title := "Automatic Updates Are Unavailable"
        message := "Check GitHub Releases for download options."
    }
    releaseNotes := ReadInstalledCumulativeNotes(notesVersion)
    state := {Retry: false}
    panel := CreateGoldNativePrompt(0, "tes3np — Version Status", 800, 600)
    closeNotes := 0
    try {
        panel.SetFont("s14 Bold cC5A45C", "Georgia")
        panel.Add("Text", "x30 y20 w740 h38 BackgroundTrans", title)
        panel.SetFont("s10 cEDE1C9", "Segoe UI")
        panel.Add("Text", "x30 y65 w740 h30 BackgroundTrans", message)
        panel.SetFont("s12 Bold cC5A45C", "Georgia")
        panel.Add("Text", "x30 y123 w430 h30 BackgroundTrans", "Release Notes")
        panel.SetFont("s9 cC5A45C", "Segoe UI")
        panel.Add("Text", "x482 y129 w288 h22 BackgroundTrans", "Build: v" notesVersion)
        AddStyledButton(panel, 178, 544, 212, 34, "Check For Updates", (*) => (state.Retry := true, DestroyScaledMenu(panel)))
        AddStyledButton(panel, 410, 544, 212, 34, "Close", (*) => DestroyScaledMenu(panel))
        panel.OnEvent("Close", (*) => DestroyScaledMenu(panel))
        panel.OnEvent("Escape", (*) => DestroyScaledMenu(panel))
        scale := GetUpdatePromptFitScale(panel)
        ScaleOwnedMenuContent(panel, scale)
        closeNotes := AddUpdateNotesViewport(panel, releaseNotes, scale)
        hwnd := panel.Hwnd
        ShowGoldNativePrompt(panel, scale)
        PaintGoldUpdateDialogButtons(panel)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        if IsObject(closeNotes)
            try closeNotes()
        CloseGoldNativePrompt(panel)
    }
    if state.Retry
        SetTimer(CheckForUpdates, -100)
}

; Release dialogs create dynamically painted ClassButton controls while hidden.
; A direct paint after showing them covers the Windows first-exposure race where
; the controls look blank until hovered or the window is minimized/restored.
; Restrict the pass to controls owned by this dialog; no launcher/UI rebuild.
PaintGoldUpdateDialogButtons(panel)
{
    global ButtonFaces
    if !IsObject(panel) || !DllCall("user32\IsWindowVisible", "Ptr", panel.Hwnd, "Int")
        return
    ; ShowGoldNativePrompt already paints the background and ordinary text.
    ; Do not invalidate the entire visible parent here: that repaints the
    ; backdrop over its newly exposed children and causes an opening flash.
    ; Only paint our buffered button faces to repair the missed first WM_PAINT.
    for handle, face in ButtonFaces
        if face.Window = panel.Hwnd && !face.HasOwnProp("IsLabel")
            && DllCall("user32\IsWindowVisible", "Ptr", handle, "Int")
            PaintButtonNow(handle)
}

GetUpdatePromptFitScale(panel)
{
    ; The backdrop uses screen pixels and matches the launcher. Keep the
    ; original dialog layout whenever it fits, with a margin at each edge.
    panel.NativePromptBackdrop.GetClientPos(, , &width, &height)
    return Max(0.5, Min(1.0, (width - 32) / panel.NativePromptWidth,
        (height - 32) / panel.NativePromptHeight))
}
