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
    ; The 600 x 556 compact composition follows the approved gold fantasy
    ; mockup. Keep existing player-facing text, version history, updater
    ; confirmation and download behavior untouched.
    notes := ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion, true)
    response := {Download: false}
    preview := CreateGoldNativePrompt(0, "tes3np — Update Preview", 600, 556)
    closeNotes := 0
    try
    {
        preview.SetFont(kind = "hotfix" ? "s13 Bold cE7BE70" : "s11 Bold cE7BE70", "Georgia")
        releaseType := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Stable"
        title := kind = "hotfix" ? "Hotfix available" : "A New " releaseType " Is Available to Download, S'wit!"
        preview.Add("Text", "x22 y14 w555 h31 BackgroundTrans", title)

        ; Narrow gold metadata ribbon. Each natural-size label is measured so
        ; long future versions reflow rather than collide with Channel.
        metadataBorder := preview.Add("Text", "x20 y53 w560 h36 BackgroundC5A45C")
        metadataFill := preview.Add("Text", "x22 y55 w556 h32 Background21170F")
        rowExtra := AddUpdatePreviewMetadata(preview, installedVersion, latestVersion, channel, true)
        if rowExtra
        {
            metadataBorder.Move(, , , 36 + rowExtra)
            metadataFill.Move(, , , 32 + rowExtra)
            GrowGoldNativePrompt(preview, rowExtra)
        }

        preview.SetFont("s11 Bold cE7BE70", "Georgia")
        preview.Add("Text", "x21 y" (96 + rowExtra) " w558 h30 BackgroundTrans", "Changes in This Update")
        ; One continuous outer frame contains the latest hotfix, readable
        ; scrollable notes, a gold rule, and fixed earlier-update summary.
        preview.Add("Text", "x20 y" (131 + rowExtra) " w560 h365 BackgroundC5A45C")
        preview.Add("Text", "x22 y" (133 + rowExtra) " w556 h361 Background171008")

        if notes.Title != ""
        {
            preview.SetFont("s11 Bold cE7BE70", "Georgia")
            latestTitle := preview.Add("Text", "x40 y" (139 + rowExtra)
                . " BackgroundTrans +0x80", notes.Title)
            latestTitle.GetPos(, , &naturalTitleWidth)
            latestTitle.Move(40, 139 + rowExtra, Min(naturalTitleWidth + 4, 484), 28)
            ; Place the round notification immediately after the latest
            ; version, not at a fixed far-right position.
            preview.SetFont("s10 Bold cFFFFFF", "Segoe UI")
            latestBadge := preview.Add("Text", "x" Min(537, 50 + naturalTitleWidth)
                . " y" (144 + rowExtra) " w20 h20 Center +0x200 BackgroundD63232", "1")
        }

        noteSwitcher := {Update: 0}
        previewState := {Expanded: false}
        if notes.EarlierCount > 0
        {
            preview.Add("Text", "x40 y" (376 + rowExtra) " w520 h2 BackgroundC5A45C")
            preview.SetFont("s10 Bold cE7BE70", "Georgia")
            preview.Add("Text", "x40 y" (388 + rowExtra) " w520 h25 BackgroundTrans", "Earlier updates included")
            preview.SetFont("s8 Norm cFFF0DC", "Segoe UI")
            preview.Add("Text", "x40 y" (420 + rowExtra) " w515 h20 BackgroundTrans",
                "You also missed " notes.EarlierCount " earlier " (notes.EarlierCount = 1 ? "hotfix." : "hotfixes."))
            yLabel := 442 + rowExtra
            for label in notes.EarlierLabels
            {
                if yLabel > 464 + rowExtra
                    break
                preview.Add("Text", "x48 y" yLabel " w330 h20 BackgroundTrans", "• " label)
                yLabel += 21
            }
            preview.SetFont("s8 Underline cF5C96E", "Segoe UI")
            showEarlier := preview.Add("Text", "x386 y" (454 + rowExtra)
                . " w188 h25 BackgroundTrans +0x100", "View earlier changes")
            hideEarlier := preview.Add("Text", "x386 y" (454 + rowExtra)
                . " w188 h25 BackgroundTrans +0x100", "Hide earlier changes")
            showEarlier.OnEvent("Click", (*) => TogglePublishedPreviewHistory())
            hideEarlier.OnEvent("Click", (*) => TogglePublishedPreviewHistory())
            hideEarlier.Visible := false
        }

        TogglePublishedPreviewHistory()
        {
            previewState.Expanded := !previewState.Expanded
            noteSwitcher.Update.Call(previewState.Expanded ? notes.Expanded : notes.Latest)
            showEarlier.Visible := !previewState.Expanded
            hideEarlier.Visible := previewState.Expanded
        }

        ; Both approved controls are centered below the gold history frame.
        actionY := 511 + rowExtra
        AddStyledButton(preview, 109, actionY, 181, 34, "Update Now",
            (*) => (response.Download := true, DestroyScaledMenu(preview)))
        AddStyledButton(preview, 313, actionY, 181, 34, "Not Now", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Close", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Escape", (*) => DestroyScaledMenu(preview))

        scale := GetUpdatePromptFitScale(preview)
        ScaleOwnedMenuContent(preview, scale)
        closeNotes := AddUpdateNotesViewport(preview, notes.Latest, scale,
            noteSwitcher, rowExtra, 0, true, true, notes.EarlierCount > 0)
        if notes.Title != ""
            ShapeCircularUpdateBadge(latestBadge)
        hwnd := preview.Hwnd
        ShowGoldNativePrompt(preview, scale)
        PaintGoldUpdateDialogButtons(preview)
        WinWaitClose("ahk_id " hwnd)
    }
    finally
    {
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
AddUpdatePreviewMetadata(panel, installedVersion, latestVersion, channel, compact := false)
{
    panel.SetFont(compact ? "s8 Norm cFFF0DC" : "s10 Bold cEDE1C9", "Segoe UI")
    baseX := compact ? 40 : 30
    labelY := compact ? 61 : 80
    rightEdge := compact ? 568 : 770
    ; AHK only auto-sizes a Text control reliably to its caption when
    ; neither width nor height is specified. Setting h26 at creation made
    ; GetPos return a narrow default width and truncated Installed metadata.
    ; Capture natural widths first, then apply the fixed one-line height.
    installed := panel.Add("Text", "x" baseX " y" labelY " BackgroundTrans +0x80", "Installed: v" installedVersion)
    latest := panel.Add("Text", "x" baseX " y" labelY " BackgroundTrans +0x80", "Latest: v" latestVersion)
    channelName := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Live Stable"
    channelText := panel.Add("Text", "x" baseX " y" labelY " BackgroundTrans +0x80", "Channel: " channelName)

    installed.GetPos(, , &installedWidth)
    latest.GetPos(, , &latestWidth)
    channelText.GetPos(, , &channelWidth)
    ; Include a little font/DPI rounding tolerance before positioning the
    ; next group, so the final glyph cannot touch the following label.
    installedWidth += 6, latestWidth += 6, channelWidth += 6
    installed.Move(, , installedWidth, 26)
    latest.Move(, , latestWidth, 26)
    channelText.Move(, , channelWidth, 26)
    gap := compact ? 14 : 18
    latestX := baseX + installedWidth + gap
    channelX := latestX + latestWidth + gap
    if channelX + channelWidth <= rightEdge
    {
        latest.Move(latestX, labelY)
        channelText.Move(channelX, labelY)
        panel.Add("Text", "x" (latestX - 9) " y" (labelY + 3) " w1 h18 BackgroundC5A45C")
        panel.Add("Text", "x" (channelX - 9) " y" (labelY + 3) " w1 h18 BackgroundC5A45C")
        return 0
    }
    if latestX + latestWidth <= rightEdge
    {
        latest.Move(latestX, labelY)
        channelText.Move(baseX, labelY + 32)
        panel.Add("Text", "x" (latestX - 9) " y" (labelY + 3) " w1 h18 BackgroundC5A45C")
        return 32
    }
    latest.Move(baseX, labelY + 32)
    channelText.Move(baseX, labelY + 64)
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
