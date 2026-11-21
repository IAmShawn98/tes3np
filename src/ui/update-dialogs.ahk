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

ShowUpdatePreview(installedVersion, latestVersion, channel, kind, reviewNotes := 0)
{
    ; The 600 x 556 compact composition follows the approved gold fantasy
    ; mockup. Keep existing player-facing text, version history, updater
    ; confirmation and download behavior untouched.
    notes := IsObject(reviewNotes) ? reviewNotes : ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion, true)
    response := {Download: false}
    ; Show the actual production popup at full launcher scale, with room
    ; for the final category and the pinned earlier-update summary.
    notesSpace := 100
    preview := CreateGoldNativePrompt(0, "tes3np — Update Preview", 600, 556 + notesSpace)
    closeNotes := 0
    try
    {
        preview.SetFont(kind = "hotfix" ? "s14 Bold cE7BE70" : "s12 Bold cE7BE70", "Georgia")
        releaseType := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Stable"
        title := kind = "hotfix" ? "Hotfix available" : "A New " releaseType " Is Available to Download, S'wit!"
        preview.Add("Text", "x22 y14 w555 h31 BackgroundTrans", title)

        ; Narrow gold metadata ribbon. Each natural-size label is measured so
        ; long future versions reflow rather than collide with Channel.
        metadataBorder := preview.Add("Text", "x20 y53 w560 h40 BackgroundC5A45C")
        metadataFill := preview.Add("Text", "x22 y55 w556 h36 Background21170F")
        rowExtra := AddUpdatePreviewMetadata(preview, installedVersion, latestVersion, channel, true)
        if rowExtra
        {
            metadataBorder.Move(, , , 40 + rowExtra)
            metadataFill.Move(, , , 36 + rowExtra)
            GrowGoldNativePrompt(preview, rowExtra)
        }

        preview.SetFont("s11 Bold cE7BE70", "Georgia")
        preview.Add("Text", "x21 y" (96 + rowExtra) " w558 h30 BackgroundTrans", "Changes in This Update")
        ; One continuous outer frame contains the latest hotfix, readable
        ; scrollable notes, a gold rule, and fixed earlier-update summary.
        preview.Add("Text", "x20 y" (131 + rowExtra) " w560 h" (365 + notesSpace) " BackgroundC5A45C")
        preview.Add("Text", "x22 y" (133 + rowExtra) " w556 h" (361 + notesSpace) " Background171008")

        if notes.Title != ""
        {
            preview.SetFont("s11 Bold cE7BE70", "Georgia")
            latestTitle := preview.Add("Text", "x40 y" (139 + rowExtra)
                . " BackgroundTrans +0x80", notes.Title)
            latestTitle.GetPos(, , &naturalTitleWidth)
            latestTitle.Move(40, 139 + rowExtra, Min(naturalTitleWidth + 4, 484), 28)
            ; Place the round notification immediately after the latest
            ; version, not at a fixed far-right position.
            latestBadge := preview.Add("Picture", "x" Min(537, 50 + naturalTitleWidth)
                . " y" (144 + rowExtra) " w20 h20 BackgroundTrans",
                A_ScriptDir "\assets\controls\update-badge.png")
        }

        noteSwitcher := {Update: 0}
        previewState := {Expanded: false}
        ; Published previews show this section only for genuinely missed versions.
        ; A local draft review keeps the section visible as an honest empty
        ; state so its layout can be reviewed without inventing hotfixes.
        showEarlierSummary := notes.EarlierCount > 0
            || (notes.HasOwnProp("ReviewEmptyEarlier") && notes.ReviewEmptyEarlier)
        if showEarlierSummary
        {
            preview.Add("Text", "x40 y" (376 + rowExtra + notesSpace) " w520 h2 BackgroundC5A45C")
            preview.SetFont("s12 Bold cE7BE70", "Georgia")
            preview.Add("Text", "x40 y" (388 + rowExtra + notesSpace) " w520 h25 BackgroundTrans", "Earlier updates included")
            preview.SetFont("s10 Norm cFFF0DC", "Segoe UI")
            if notes.EarlierCount > 0
            {
                preview.Add("Text", "x40 y" (420 + rowExtra + notesSpace) " w515 h20 BackgroundTrans",
                    "You also missed " notes.EarlierCount " earlier " (notes.EarlierCount = 1 ? "hotfix." : "hotfixes."))
                yLabel := 442 + rowExtra + notesSpace
                for label in notes.EarlierLabels
                {
                    if yLabel > 464 + rowExtra + notesSpace
                        break
                    preview.Add("Text", "x48 y" yLabel " w330 h20 BackgroundTrans", "• " label)
                    yLabel += 21
                }
                preview.SetFont("s9 Underline cF5C96E", "Segoe UI")
                showEarlier := preview.Add("Text", "x386 y" (454 + rowExtra + notesSpace)
                    . " w188 h25 BackgroundTrans +0x100", "View earlier changes")
                hideEarlier := preview.Add("Text", "x386 y" (454 + rowExtra + notesSpace)
                    . " w188 h25 BackgroundTrans +0x100", "Hide earlier changes")
                showEarlier.OnEvent("Click", (*) => TogglePublishedPreviewHistory())
                hideEarlier.OnEvent("Click", (*) => TogglePublishedPreviewHistory())
                hideEarlier.Visible := false
            }
            else
                preview.Add("Text", "x40 y" (420 + rowExtra + notesSpace)
                    . " w515 h20 BackgroundTrans", "No earlier missed updates for this draft.")
        }

        TogglePublishedPreviewHistory()
        {
            previewState.Expanded := !previewState.Expanded
            noteSwitcher.Update.Call(previewState.Expanded ? notes.Expanded : notes.Latest)
            showEarlier.Visible := !previewState.Expanded
            hideEarlier.Visible := previewState.Expanded
        }

        ; Both approved controls are centered below the gold history frame.
        actionY := 511 + rowExtra + notesSpace
        AddStyledButton(preview, 109, actionY, 181, 34, "Update Now",
            (*) => (response.Download := true, DestroyScaledMenu(preview)))
        AddStyledButton(preview, 313, actionY, 181, 34, "Not Now", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Close", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Escape", (*) => DestroyScaledMenu(preview))

        ; Do not shrink this dialog to a second miniature scale.
        scale := Min(GetOwnedMenuScale(), GetUpdatePromptFitScale(preview))
        ScaleOwnedMenuContent(preview, scale)
        closeNotes := AddUpdateNotesViewport(preview, notes.Latest, scale,
            noteSwitcher, rowExtra, notesSpace, true, true, showEarlierSummary)
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

; Text controls have one color each. Keep the three compact ribbon labels
; gold, but render their values separately in the reference's pale ivory.
; Both styles measure actual rendered widths before placing the controls.
AddUpdatePreviewMetadata(panel, installedVersion, latestVersion, channel, compact := false)
{
    if compact
        return AddCompactUpdatePreviewMetadata(panel, installedVersion, latestVersion, channel)

    ; Preserve the separate Version Status / legacy metadata layout.
    panel.SetFont("s10 Bold cEDE1C9", "Segoe UI")
    baseX := 30
    labelY := 80
    rightEdge := 770
    installed := panel.Add("Text", "x" baseX " y" labelY " BackgroundTrans +0x80", "Installed: v" installedVersion)
    latest := panel.Add("Text", "x" baseX " y" labelY " BackgroundTrans +0x80", "Latest: v" latestVersion)
    channelName := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Live Stable"
    channelText := panel.Add("Text", "x" baseX " y" labelY " BackgroundTrans +0x80", "Channel: " channelName)

    installed.GetPos(, , &installedWidth)
    latest.GetPos(, , &latestWidth)
    channelText.GetPos(, , &channelWidth)
    installedWidth += 6, latestWidth += 6, channelWidth += 6
    installed.Move(, , installedWidth, 26)
    latest.Move(, , latestWidth, 26)
    channelText.Move(, , channelWidth, 26)
    gap := 18
    fullWidth := installedWidth + latestWidth + channelWidth + 2 * gap
    latestX := baseX + installedWidth + gap
    channelX := latestX + latestWidth + gap
    if channelX + channelWidth <= rightEdge
    {
        installed.Move(baseX, labelY)
        latest.Move(latestX, labelY)
        channelText.Move(channelX, labelY)
        separatorOffset := Floor(gap / 2)
        panel.Add("Text", "x" (latestX - separatorOffset) " y" (labelY + 3) " w1 h18 BackgroundC5A45C")
        panel.Add("Text", "x" (channelX - separatorOffset) " y" (labelY + 3) " w1 h18 BackgroundC5A45C")
        return 0
    }
    latestX := baseX + installedWidth + gap
    if latestX + latestWidth <= rightEdge
    {
        installed.Move(baseX, labelY)
        latest.Move(latestX, labelY)
        channelText.Move(baseX, labelY + 32)
        panel.Add("Text", "x" (latestX - Floor(gap / 2)) " y" (labelY + 3) " w1 h18 BackgroundC5A45C")
        return 32
    }
    installed.Move(baseX, labelY)
    latest.Move(baseX, labelY + 32)
    channelText.Move(baseX, labelY + 64)
    return 64
}

AddCompactUpdatePreviewMetadata(panel, installedVersion, latestVersion, channel)
{
    ; Only the prefixes are gold: Installed:, Latest:, Channel:.
    ; The versions and channel values are pale ivory, just as in the reference.
    channelName := channel = "alpha" ? "alpha" : channel = "beta" ? "beta" : "live"
    captions := [
        {Label: "Installed:", Value: "v" installedVersion},
        {Label: "Latest:", Value: "v" latestVersion},
        {Label: "Channel:", Value: channelName}
    ]
    gap := 24
    sideLeft := 48
    sideRight := 552
    availableWidth := sideRight - sideLeft
    compactFontSize := 9
    ; Measure labels and values in their separate actual fonts. Adapt only
    ; when a long version cannot retain a centered single row.
    for fontSize in [9, 8, 7, 6]
    {
        probe := Gui("-DPIScale")
        measuredWidth := 2 * gap
        try
        {
            for item in captions
            {
                probe.SetFont("s" fontSize " Bold cE7BE70", "Segoe UI")
                labelProbe := probe.Add("Text", "x0 y0 BackgroundTrans +0x80", item.Label)
                labelProbe.GetPos(, , &labelWidth)
                probe.SetFont("s" fontSize " Norm cFFF0DC", "Segoe UI")
                valueProbe := probe.Add("Text", "x0 y0 BackgroundTrans +0x80", item.Value)
                valueProbe.GetPos(, , &valueWidth)
                measuredWidth += labelWidth + valueWidth + 7
            }
        }
        finally
            probe.Destroy()
        compactFontSize := fontSize
        if measuredWidth <= availableWidth
            break
    }

    pairs := []
    for item in captions
    {
        panel.SetFont("s" compactFontSize " Bold cE7BE70", "Segoe UI")
        labelControl := panel.Add("Text", "x0 y0 BackgroundTrans +0x80", item.Label)
        labelControl.GetPos(, , &labelWidth)
        panel.SetFont("s" compactFontSize " Norm cFFF0DC", "Segoe UI")
        valueControl := panel.Add("Text", "x0 y0 BackgroundTrans +0x80", item.Value)
        valueControl.GetPos(, , &valueWidth)
        labelWidth += 2
        valueWidth += 2
        pairs.Push({Label: labelControl, Value: valueControl,
            LabelWidth: labelWidth, ValueWidth: valueWidth,
            Width: labelWidth + valueWidth + 3})
    }

    fullWidth := pairs[1].Width + pairs[2].Width + pairs[3].Width + 2 * gap
    if fullWidth <= availableWidth
    {
        startX := Round((600 - fullWidth) / 2)
        latestX := startX + pairs[1].Width + gap
        channelX := latestX + pairs[2].Width + gap
        PositionCompactMetadataPair(pairs[1], startX, 61)
        PositionCompactMetadataPair(pairs[2], latestX, 61)
        PositionCompactMetadataPair(pairs[3], channelX, 61)
        panel.Add("Text", "x" (latestX - Floor(gap / 2)) " y64 w1 h18 BackgroundC5A45C")
        panel.Add("Text", "x" (channelX - Floor(gap / 2)) " y64 w1 h18 BackgroundC5A45C")
        return 0
    }
    pairWidth := pairs[1].Width + pairs[2].Width + gap
    if pairWidth <= availableWidth
    {
        startX := Round((600 - pairWidth) / 2)
        latestX := startX + pairs[1].Width + gap
        PositionCompactMetadataPair(pairs[1], startX, 61)
        PositionCompactMetadataPair(pairs[2], latestX, 61)
        PositionCompactMetadataPair(pairs[3], Round((600 - pairs[3].Width) / 2), 93)
        panel.Add("Text", "x" (latestX - Floor(gap / 2)) " y64 w1 h18 BackgroundC5A45C")
        return 32
    }
    for index, pair in pairs
        PositionCompactMetadataPair(pair, Round((600 - pair.Width) / 2), 61 + (index - 1) * 32)
    return 64
}

PositionCompactMetadataPair(pair, x, y)
{
    pair.Label.Move(x, y, pair.LabelWidth, 26)
    pair.Value.Move(x + pair.LabelWidth + 3, y, pair.ValueWidth, 26)
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
