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
    ; Keep the upper changelog scrollable and reserve four missed-release
    ; rows within the same fixed-height production card.
    notesSpace := 100
    ; Reserve extra height only when there are missed releases. The measured
    ; Windows 10pt link controls need more vertical space than the nominal
    ; 29px estimate; do not squeeze the upper changelog or its scrollbar.
    missedVersions := notes.HasOwnProp("MissedVersions") ? notes.MissedVersions : []
    hasMissed := missedVersions.Length > 0
    missedSpace := hasMissed ? 64 : 0
    preview := CreateGoldNativePrompt(0, "tes3np — Update Preview",
        600, 556 + notesSpace + missedSpace)
    closeNotes := 0
    closeMissed := 0
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
        preview.Add("Text", "x20 y" (131 + rowExtra) " w560 h" (365 + notesSpace + missedSpace) " BackgroundC5A45C")
        preview.Add("Text", "x22 y" (133 + rowExtra) " w556 h" (361 + notesSpace + missedSpace) " Background171008")

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

        ; List every genuinely missed published version, including the
        ; newest, with its own GitHub changelog. No fake released versions
        ; are inserted into the production history.
        missedHeading := 0
        if hasMissed
        {
            preview.Add("Text", "x40 y" (312 + rowExtra + notesSpace) " w520 h2 BackgroundC5A45C")
            preview.SetFont("s12 Bold cE7BE70", "Georgia")
            missedHeading := preview.Add("Text", "x40 y" (324 + rowExtra + notesSpace)
                . " w520 h28 BackgroundTrans", "Updates You Missed")
        }

        ; Both approved controls are centered below the gold history frame.
        actionY := 511 + rowExtra + notesSpace + missedSpace
        AddStyledButton(preview, 109, actionY, 181, 34, "Update Now",
            (*) => (response.Download := true, DestroyScaledMenu(preview)))
        AddStyledButton(preview, 313, actionY, 181, 34, "Not Now", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Close", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Escape", (*) => DestroyScaledMenu(preview))

        ; Do not shrink this dialog to a second miniature scale.
        scale := Min(GetOwnedMenuScale(), GetUpdatePromptFitScale(preview))
        ScaleOwnedMenuContent(preview, scale)
        closeNotes := AddUpdateNotesViewport(preview, notes.Latest, scale,
            0, rowExtra, notesSpace, true, true, hasMissed)
        if hasMissed
            closeMissed := AddMissedUpdateLinks(preview, missedVersions, scale, rowExtra, notesSpace, missedHeading)
        hwnd := preview.Hwnd
        ShowGoldNativePrompt(preview, scale)
        PaintGoldUpdateDialogButtons(preview)
        WinWaitClose("ahk_id " hwnd)
    }
    finally
    {
        if IsObject(closeMissed)
            try closeMissed()
        if IsObject(closeNotes)
            try closeNotes()
        CloseGoldNativePrompt(preview)
    }
    return response.Download ? "Yes" : "No"
}

; Four-row published version list with its own themed arrowed scrollbar.
; Fixed bounds stay inside the gold frame and above the update buttons.
AddMissedUpdateLinks(panel, versions, scale, topExtra := 0, bottomExtra := 0, heading := 0, observer := 0)
{
    if !versions.Length
        return 0
    px := (value) => Round(value * scale)
    ; The clipping was caused by the opaque list viewport painting over the
    ; lower part of the 'Updates You Missed' heading. Position its top below
    ; the *measured scaled heading control*, not above its text baseline.
    ; A 64px history extension is reserved in the real missed-update
    ; preview card, allowing four measured-font rows without clipping.
    bottomLimit := px(554 + topExtra + bottomExtra)
    rowTop := px(356 + topExtra + bottomExtra)
    if IsObject(heading)
    {
        heading.GetPos(, &headingY, , &headingHeight)
        rowTop := Max(rowTop, headingY + headingHeight + Max(2, px(4)))
    }
    if rowTop >= bottomLimit
        throw Error("Missed-update viewport has no space below its heading.")
    rowStep := px(24)
    rowHeight := px(29)
    left := px(48)
    rowWidth := px(496)
    viewport := panel.Add("Text", "x" px(40) " y" rowTop
        . " w" px(531) " h" (bottomLimit - rowTop) " Background171008")
    page := {Items: versions, Offset: 1, VisibleRows: 4, MaxOffset: Max(1, versions.Length - 3)}
    rows := []
    badges := []
    for slot in [1, 2, 3, 4]
    {
        panel.SetFont("s" Max(4, Round(10 * scale)) " Underline cF5C96E", "Segoe UI")
        link := panel.Add("Text", "Hidden x" left " y" (rowTop + (slot - 1) * rowStep)
            . " w" rowWidth " h" rowHeight " BackgroundTrans +0x100", "")
        link.OnEvent("Click", OpenMissedUpdateVersion.Bind(page, slot))
        ; Use the native font height rather than assuming a 20px Text box
        ; can display the entire glyph (it clipped the draft version).
        rowHeight := Max(rowHeight, ReleaseNoteLineHeight(link) + px(8))
        rows.Push(link)
        ; The same genuine red (1) artwork used beside Latest Hotfix.
        ; Each visible missed version gets its own badge, even in the
        ; developer stress preview. The badge shares the link's click action.
        badge := panel.Add("Picture", "Hidden x0 y0 w" px(20) " h" px(20)
            . " BackgroundTrans", A_ScriptDir "\assets\controls\update-badge.png")
        badge.OnEvent("Click", OpenMissedUpdateVersion.Bind(page, slot))
        badges.Push(badge)
    }
    ; Never overlap native Text controls: a later transparent sibling can
    ; erase the previous row's descenders during Windows repaint.
    rowStep := Max(rowStep, rowHeight + Max(1, px(2)))
    for slot, link in rows
        link.Move(left, rowTop + (slot - 1) * rowStep, rowWidth, rowHeight)
    ; Preserve the frame even at unusual Windows DPI settings: if the font
    ; needs more height, show fewer rows and let the scrollbar reach the rest.
    page.VisibleRows := Max(1, Min(4,
        1 + Floor((bottomLimit - rowTop - rowHeight) / Max(1, rowStep))))
    page.MaxOffset := Max(1, versions.Length - page.VisibleRows + 1)
    ; The missed-version scrollbar shares the parent changelog's geometry,
    ; gold texture, themed arrow buttons and draggable thumb.
    arrowX := px(558)
    arrowTop := rowTop
    arrowBottom := bottomLimit - px(22)
    trackY := arrowTop + px(25)
    trackHeight := Max(1, arrowBottom - px(3) - trackY)
    thumbX := px(565)
    thumbWidth := px(8)
    track := panel.Add("Text", "x" px(561) " y" trackY " w" px(16)
        . " h" trackHeight " Background704C27 +0x100")
    thumb := panel.Add("Text", "x" thumbX " y" trackY " w" thumbWidth
        . " h" px(22) " BackgroundC69951 +0x100")
    drag := {Active: false, StartY: 0, StartOffset: 1, Timer: 0}
    refresh(*)
    {
        page.Offset := Max(1, Min(page.MaxOffset, page.Offset))
        for slot, row in rows
        {
            idx := page.Offset + slot - 1
            if slot > page.VisibleRows || idx > page.Items.Length
            {
                row.Visible := false
                badges[slot].Visible := false
                continue
            }
            item := page.Items[idx]
            linked := item.Url != ""
            row.SetFont("s" Max(4, Round(10 * scale))
                . (linked ? " Underline cF5C96E" : " Norm cAFA78B"), "Segoe UI")
            caption := item.Label
            ; Leave room for the full-size red (1), aligned beside the
            ; measured version rather than the full-width click target.
            while StrLen(caption) > 2 && !ReleaseNoteFits(row, caption, rowWidth - px(36))
                caption := SubStr(caption, 1, -2) "…"
            row.Text := caption
            badgeX := left + Min(rowWidth - px(25),
                MeasureMissedUpdateTextWidth(row, caption) + px(6))
            row.GetPos(, &rowY)
            badges[slot].Move(badgeX, rowY + Max(0, Floor((rowHeight - px(20)) / 2)),
                px(20), px(20))
            row.Visible := true
            badges[slot].Visible := true
        }
        thumbHeight := Max(px(22), Round(trackHeight * Min(1, page.VisibleRows / page.Items.Length)))
        thumbY := trackY + Round((trackHeight - thumbHeight) * (page.Offset - 1)
            / Max(1, page.MaxOffset - 1))
        thumb.Move(thumbX, thumbY, thumbWidth, thumbHeight)
        track.Visible := page.MaxOffset > 1
        thumb.Visible := page.MaxOffset > 1
        up.Visible := page.MaxOffset > 1
        down.Visible := page.MaxOffset > 1
    }
    up := AddStyledButton(panel, arrowX, arrowTop, px(20), px(22),
        "↑", (*) => (page.Offset -= 1, refresh()))
    down := AddStyledButton(panel, arrowX, arrowBottom, px(20), px(22),
        "↓", (*) => (page.Offset += 1, refresh()))
    for arrow in [up, down]
        arrow.SetFont(UpdateNoteFont("heading", true, true, scale), "Segoe UI")
    refresh()
    ; Disposable native smoke tests can inspect page bounds and scroll state
    ; without opening URLs or touching installed launcher data.
    if IsObject(observer)
    {
        observer.Page := page
        observer.RowHeight := rowHeight
        observer.RowStep := rowStep
        observer.BottomLimit := bottomLimit
        observer.Viewport := viewport
        observer.Rows := rows
        observer.Badges := badges
        observer.Track := track
        observer.Thumb := thumb
        observer.Up := up
        observer.Down := down
        observer.Refresh := refresh
    }
    wheelCallback := UpdateNotesMouseWheel.Bind(viewport, page, refresh)
    dragStartCallback := StartUpdateNotesDrag.Bind(panel, thumb, track, drag, page, refresh)
    OnMessage(0x0201, dragStartCallback, 1)
    try OnMessage(0x020A, wheelCallback, 1)
    catch
    {
        OnMessage(0x0201, dragStartCallback, 0)
        throw
    }
    track.OnEvent("Click", JumpMissedUpdateList.Bind(page, track, refresh))
    unregister()
    {
        OnMessage(0x020A, wheelCallback, 0)
        OnMessage(0x0201, dragStartCallback, 0)
        if drag.Active
        {
            drag.Active := false
            SetTimer(drag.Timer, 0)
            DllCall("user32\ReleaseCapture")
        }
    }
    return unregister
}

; Return native rendered text width; static Text controls are deliberately
; much wider than their captions to keep the entire row clickable.
MeasureMissedUpdateTextWidth(control, value)
{
    font := DllCall("SendMessageW", "Ptr", control.Hwnd, "UInt", 0x31,
        "Ptr", 0, "Ptr", 0, "Ptr")
    dc := DllCall("user32\GetDC", "Ptr", control.Hwnd, "Ptr")
    if !dc
        throw OSError()
    previous := font ? DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr") : 0
    try
    {
        extent := Buffer(8, 0)
        if !DllCall("gdi32\GetTextExtentPoint32W", "Ptr", dc,
            "Str", value, "Int", StrLen(value), "Ptr", extent, "Int")
            throw OSError()
        return NumGet(extent, 0, "Int")
    }
    finally
    {
        if previous
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", previous)
        DllCall("user32\ReleaseDC", "Ptr", control.Hwnd, "Ptr", dc)
    }
}

JumpMissedUpdateList(page, track, refresh, *)
{
    if page.MaxOffset <= 1
        return
    rect := Buffer(16, 0)
    mouse := Buffer(8, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", track.Hwnd, "Ptr", rect)
        || !DllCall("user32\GetCursorPos", "Ptr", mouse)
        return
    y := NumGet(mouse, 4, "Int") - NumGet(rect, 4, "Int")
    height := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
    page.Offset := 1 + Round((page.MaxOffset - 1) * y / Max(1, height))
    refresh()
}

OpenMissedUpdateVersion(page, slot, *)
{
    idx := page.Offset + slot - 1
    if idx > page.Items.Length
        return
    item := page.Items[idx]
    if item.Url = ""
        return ; An unreleased local draft has no GitHub changelog yet.
    version := item.Version
    if !RegExMatch(version,
        "^\d+\.\d+\.\d+(?:-(?:alpha|beta|live)(?:\.\d+)?|\.\d+)?$")
        return
    expected := "https://github.com/IAmShawn98/tes3np/releases/tag/v" version
    if item.Url != expected
        return
    try Run(expected)
    catch Error as err
        MsgBox("Could not open the GitHub changelog: " err.Message, "tes3np", "Icon!")
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
