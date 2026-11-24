; Display update status, release previews, and download and install confirmations.

; These per-preview HWND entries are removed when the modal closes.
global MissedUpdateCursorTargets := Map()

ShowGoldUpdateConfirmation(title, message, confirmLabel)
{
    response := {Accepted: false}
    window := CreateGoldNativePrompt(0, "tes3np — Update Confirmation", 640, 258)
    try {
        SetAccessibleTextFont(window, "s15 Bold cC5A45C", "Georgia")
        extra := AddGoldPromptCopy(window, 32, 26, 588, 32, title)
        SetAccessibleTextFont(window, "s10 cFFFFFF", "Segoe UI")
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
    ; Keep the upper changelog scrollable and reserve four missed-release
    ; rows within the same fixed-height production card.
    notesSpace := 100
    ; Reserve extra height only when there are missed releases. The measured
    ; Windows 10pt link controls need more vertical space than the nominal
    ; 29px estimate; do not squeeze the upper changelog or its scrollbar.
    missedVersions := notes.HasOwnProp("MissedVersions") ? notes.MissedVersions : []
    hasMissed := missedVersions.Length > 0
    previewState := {Offered: latestVersion}
    ; Opening marks only the offered published release read. Earlier releases
    ; remain visible and retain independent read receipts.
    MarkPublishedVersionRead(latestVersion, true)
    ; Only a successfully parsed release history may replace the cached list.
    ; An unavailable history is not proof that there are zero older updates.
    verifiedHistory := notes.HasOwnProp("HistoryVerified") && notes.HistoryVerified
    RefreshLauncherPublishedUnreadCount(verifiedHistory ? missedVersions : 0, latestVersion)
    missedSpace := hasMissed ? 64 : 0
    preview := CreateGoldNativePrompt(0, "tes3np — Update Preview",
        600, 556 + notesSpace + missedSpace)
    closeNotes := 0
    closeMissed := 0
    try
    {
        SetAccessibleTextFont(preview, kind = "hotfix" ? "s14 Bold cE7BE70" : "s12 Bold cE7BE70", "Georgia")
        releaseType := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Stable Release"
        title := kind = "hotfix" ? "A Patch Is Available For v" installedVersion : "A New " releaseType " Is Available to Download, S'wit!"
        titleControl := preview.Add("Text", "x22 y14 w555 h31 BackgroundTrans", title)
        ; Preserve the approved one-line heading at every supported version
        ; length. Let actual Windows text metrics determine a smaller font.
        for fontSize in (kind = "hotfix" ? [14, 13, 12, 11, 10] : [12, 11, 10, 9])
        {
            SetAccessibleTextFont(titleControl, "s" fontSize " Bold cE7BE70", "Georgia")
            if ReleaseNoteFits(titleControl, title, 548)
                break
        }

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

        SetAccessibleTextFont(preview, "s11 Bold cE7BE70", "Georgia")
        preview.Add("Text", "x21 y" (96 + rowExtra) " w558 h30 BackgroundTrans", "Changes in This Update")
        ; One continuous outer frame contains the latest hotfix, readable
        ; scrollable notes, a gold rule, and fixed earlier-update summary.
        preview.Add("Text", "x20 y" (131 + rowExtra) " w560 h" (365 + notesSpace + missedSpace) " BackgroundC5A45C")
        preview.Add("Text", "x22 y" (133 + rowExtra) " w556 h" (361 + notesSpace + missedSpace) " Background171008")

        if notes.Title != ""
        {
            SetAccessibleTextFont(preview, "s11 Bold cE7BE70", "Georgia")
            latestTitle := preview.Add("Text", "x40 y" (139 + rowExtra)
                . " BackgroundTrans +0x80", notes.Title)
            latestTitle.GetPos(, , &naturalTitleWidth)
            latestTitle.Move(40, 139 + rowExtra, Min(naturalTitleWidth + 4, 484), 28)
            ; Place the round notification immediately after the latest
            ; version, not at a fixed far-right position.
            ; This offered release is already marked read on opening.
            ; Its notification is part of the footer count, not a permanent
            ; red marker in the already-viewed modal title.
        }

        ; List every genuinely missed published version, including the
        ; newest, with its own GitHub changelog. No fake released versions
        ; are inserted into the production history.
        missedHeading := 0
        if hasMissed
        {
            preview.Add("Text", "x40 y" (312 + rowExtra + notesSpace) " w520 h2 BackgroundC5A45C")
            SetAccessibleTextFont(preview, "s12 Bold cE7BE70", "Georgia")
            missedHeading := preview.Add("Text", "x40 y" (324 + rowExtra + notesSpace)
                . " w520 h28 BackgroundTrans", "Updates You Missed")
            ; A second fine gold rule separates the heading from the actual
            ; version entries, without covering the lettering.
            preview.Add("Text", "x40 y" (354 + rowExtra + notesSpace)
                . " w520 h1 BackgroundC5A45C")
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
            closeMissed := AddMissedUpdateLinks(preview, missedVersions, scale,
                rowExtra, notesSpace, missedHeading, 0, previewState)
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

; Four visible linked versions plus a fixed lower-left Mark Read action.
; Reading a release hides only its red (1); links remain in the list.
AddMissedUpdateLinks(panel, versions, scale, topExtra := 0, bottomExtra := 0, heading := 0, observer := 0, state := 0)
{
    if !versions.Length
        return 0
    if !IsObject(state)
        state := {Offered: ""}
    px := (value) => Round(value * scale)
    ; Leave the final 32px of the gold card for the always-visible Mark Read
    ; action. Scrolling may never cover or push this button out of view.
    bottomLimit := px(522 + topExtra + bottomExtra)
    ; Leave a visible gap beneath the second gold heading divider.
    rowTop := px(362 + topExtra + bottomExtra)
    if IsObject(heading)
    {
        heading.GetPos(, &headingY, , &headingHeight)
        rowTop := Max(rowTop, headingY + headingHeight + Max(3, px(10)))
    }
    if rowTop >= bottomLimit
        throw Error("Missed-update viewport has no space below its heading.")

    rowStep := px(24)
    rowHeight := px(29)
    left := px(48)
    rowWidth := px(496)
    viewport := panel.Add("Text", "x" px(40) " y" rowTop
        . " w" px(531) " h" (bottomLimit - rowTop) " Background171008")
    page := {Items: versions, Offset: 1, VisibleRows: 4,
        Total: versions.Length, MaxOffset: 1, State: state, Refresh: 0,
        Closed: false}
    rows := [], badges := []
    for slot in [1, 2, 3, 4]
    {
        SetAccessibleTextFont(panel, "s" Max(4, Round(10 * scale)) " Underline cFFF0DC", "Segoe UI")
        link := panel.Add("Text", "Hidden x" left " y" (rowTop + (slot - 1) * rowStep)
            . " w" rowWidth " h" rowHeight " BackgroundTrans +0x100", "")
        link.OnEvent("Click", OpenMissedUpdateVersion.Bind(page, slot))
        rowHeight := Max(rowHeight, ReleaseNoteLineHeight(link) + px(8))
        rows.Push(link)

        badge := panel.Add("Picture", "Hidden x0 y0 w" px(20) " h" px(20)
            . " BackgroundTrans", A_ScriptDir "\assets\controls\update-badge.png")
        badge.OnEvent("Click", OpenMissedUpdateVersion.Bind(page, slot))
        badges.Push(badge)
    }
    rowStep := Max(rowStep, rowHeight + Max(1, px(2)))
    for slot, link in rows
        link.Move(left, rowTop + (slot - 1) * rowStep, rowWidth, rowHeight)
    page.VisibleRows := Max(1, Min(4,
        1 + Floor((bottomLimit - rowTop - rowHeight) / Max(1, rowStep))))
    page.MaxOffset := Max(1, page.Total - page.VisibleRows + 1)

    ; This control stays in its own fixed footer area, independent from the
    ; missed-release scroll offset and scrollbar thumb position.
    SetAccessibleTextFont(panel, "s9 Bold cFFF0DC", "Segoe UI")
    markReadY := px(528 + topExtra + bottomExtra)
    clearButton := AddStyledButton(panel, px(34), markReadY, px(118), px(26),
        "Mark Read", ClearMissedUpdateBadges.Bind(page))
    page.ClearButton := clearButton

    arrowX := px(558)
    arrowTop := rowTop
    arrowBottom := bottomLimit - px(22)
    trackY := arrowTop + px(25)
    trackHeight := Max(1, arrowBottom - px(3) - trackY)
    thumbX := px(565), thumbWidth := px(8)
    track := panel.Add("Text", "x" px(561) " y" trackY " w" px(16)
        . " h" trackHeight " Background704C27 +0x100")
    thumb := panel.Add("Text", "x" thumbX " y" trackY " w" thumbWidth
        . " h" px(22) " BackgroundC69951 +0x100")
    drag := {Active: false, StartY: 0, StartOffset: 1, Timer: 0, PanelHwnd: panel.Hwnd}

    refresh(*)
    {
        page.Offset := Max(1, Min(page.MaxOffset, page.Offset))
        for slot, row in rows
        {
            idx := page.Offset + slot - 1
            badge := badges[slot]
            row.Visible := false
            badge.Visible := false
            if slot > page.VisibleRows || idx > page.Total
                continue
            y := rowTop + (slot - 1) * rowStep
            item := page.Items[idx]
            caption := "v" item.Version
            SetAccessibleTextFont(row, "s" Max(4, Round(10 * scale))
                . (item.Url != "" ? " Underline cFFF0DC" : " Norm cFFF0DC"),
                "Segoe UI")
            while StrLen(caption) > 2
                && !ReleaseNoteFits(row, caption, rowWidth - px(36))
                caption := SubStr(caption, 1, -2) "…"
            row.Move(left, y, rowWidth, rowHeight)
            row.Text := caption
            row.Visible := true
            badgeX := left + Min(rowWidth - px(23),
                MeasureMissedUpdateTextWidth(row, caption) + px(6))
            badge.Move(badgeX, y + Max(0, Floor((rowHeight - px(20)) / 2)),
                px(20), px(20))
            badge.Visible := !IsMissedUpdateRead(page, item)
        }
        thumbHeight := Min(trackHeight, Max(px(22),
            Round(trackHeight * Min(1, page.VisibleRows / page.Total))))
        thumbY := trackY + Round((trackHeight - thumbHeight) * (page.Offset - 1)
            / Max(1, page.MaxOffset - 1))
        thumb.Move(thumbX, thumbY, thumbWidth, thumbHeight)
        scrolling := page.MaxOffset > 1
        track.Visible := scrolling, thumb.Visible := scrolling
        up.Visible := scrolling, down.Visible := scrolling
        UpdateMissedUpdateMarkReadLabel(page)
    }
    page.Refresh := refresh

    up := AddStyledButton(panel, arrowX, arrowTop, px(20), px(22),
        "↑", (*) => (page.Offset -= 1, refresh()))
    down := AddStyledButton(panel, arrowX, arrowBottom, px(20), px(22),
        "↓", (*) => (page.Offset += 1, refresh()))
    for arrow in [up, down]
        SetAccessibleTextFont(arrow, UpdateNoteFont("heading", true, true, scale), "Segoe UI")
    refresh()
    if IsObject(observer)
    {
        observer.Page := page
        observer.RowHeight := rowHeight
        observer.RowStep := rowStep
        observer.BottomLimit := bottomLimit
        observer.Viewport := viewport
        observer.Rows := rows
        observer.Badges := badges
        observer.Clear := clearButton
        observer.Track := track
        observer.Thumb := thumb
        observer.Up := up
        observer.Down := down
        observer.Refresh := refresh
    }
    wheelCallback := UpdateNotesMouseWheel.Bind(viewport.Hwnd, page, refresh)
    dragStartCallback := StartUpdateNotesDrag.Bind(panel.Hwnd, thumb.Hwnd, track.Hwnd, drag, page, refresh)
    OnMessage(0x0201, dragStartCallback, 1)
    try OnMessage(0x020A, wheelCallback, 1)
    catch
    {
        OnMessage(0x0201, dragStartCallback, 0)
        throw
    }
    track.OnEvent("Click", JumpMissedUpdateList.Bind(page, track, refresh))
    cursorHandles := []
    for slot in [1, 2, 3, 4]
    {
        for control in [rows[slot], badges[slot]]
        {
            RegisterMissedUpdateCursorTarget(control, page, slot)
            cursorHandles.Push(control.Hwnd)
        }
    }
    unregister()
    {
        page.Closed := true
        ; Clean the numeric HWND keys without reading a destroyed control.
        for handle in cursorHandles
            UnregisterMissedUpdateCursorTarget(handle)
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

RegisterMissedUpdateCursorTarget(control, page, slot)
{
    global MissedUpdateCursorTargets
    MissedUpdateCursorTargets[control.Hwnd] := {Page: page, Slot: slot}
}

UnregisterMissedUpdateCursorTarget(handle)
{
    global MissedUpdateCursorTargets
    if MissedUpdateCursorTargets.Has(handle)
        MissedUpdateCursorTargets.Delete(handle)
}

IsMissedUpdateCursorTarget(handle)
{
    global MissedUpdateCursorTargets
    if !MissedUpdateCursorTargets.Has(handle)
        return false
    target := MissedUpdateCursorTargets[handle]
    page := target.Page
    if page.Closed
        return false
    index := page.Offset + target.Slot - 1
    if target.Slot > page.VisibleRows || index < 1 || index > page.Total
        return false
    item := page.Items[index]
    if !item.HasOwnProp("Url") || item.Url = ""
        return false
    ; Only the exact authoritative per-version destination is clickable.
    return RegExMatch(item.Version, "^\d+\.\d+\.\d+(?:-(?:alpha|beta|live)(?:\.\d+)?|\.\d+)?$")
        && item.Url = GetPublishedVersionNotesUrl(item.Version)
}

IsMissedUpdateRead(page, item)
{
    ; Native smoke tests supply isolated read callbacks. Production uses the
    ; normal per-version INI receipt; test callbacks are isolated.
    if page.State.HasOwnProp("IsRead")
        return page.State.IsRead.Call(item.Version)
    return IsPublishedVersionRead(item.Version)
}

UpdateMissedUpdateMarkReadLabel(page)
{
    if !page.HasOwnProp("ClearButton") || !IsObject(page.ClearButton)
        return
    unread := 0
    for item in page.Items
        if !IsMissedUpdateRead(page, item)
            unread += 1
    label := unread > 1 ? "Mark All Read" : "Mark Read"
    if page.ClearButton.Text != label
    {
        page.ClearButton.Text := label
        ; This is a custom-painted native button: repaint the new caption.
        PaintButtonNow(page.ClearButton.Hwnd)
    }
}

RefreshMissedUpdateReadState(page)
{
    if page.State.HasOwnProp("RefreshCount")
        page.State.RefreshCount.Call()
    else
        RefreshLauncherPublishedUnreadCount(page.Items, page.State.Offered)
    page.Refresh.Call()
}

MarkMissedUpdateItemRead(page, item)
{
    if page.State.HasOwnProp("MarkRead")
        page.State.MarkRead.Call(item.Version)
    else
        MarkPublishedVersionRead(item.Version)
}

ClearMissedUpdateBadges(page, *)
{
    ; Mark Read / Mark All Read clears the unread notifications for all releases
    ; without removing a single entry, regardless of scroll position.
    for item in page.Items
        if !IsMissedUpdateRead(page, item)
            MarkMissedUpdateItemRead(page, item)
    RefreshMissedUpdateReadState(page)
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
    expected := GetPublishedVersionNotesUrl(version)
    if item.Url != expected
        return
    try
        Run(expected)
    catch Error as err
    {
        MsgBox("Could not open the published changelog: " err.Message, "tes3np", "Icon!")
        return
    }
    ; Clicking a published link (or its red 1) reads only that version.
    ; The entry stays visible and the footer is recalculated immediately.
    if !IsMissedUpdateRead(page, item)
        MarkMissedUpdateItemRead(page, item)
    RefreshMissedUpdateReadState(page)
}

; Text controls have one color each. Keep the three compact ribbon labels
; gold, but render their values separately in the reference's pale ivory.
; Both styles measure actual rendered widths before placing the controls.
AddUpdatePreviewMetadata(panel, installedVersion, latestVersion, channel, compact := false)
{
    if compact
        return AddCompactUpdatePreviewMetadata(panel, installedVersion, latestVersion, channel)

    ; Preserve the separate Version Status / legacy metadata layout.
    SetAccessibleTextFont(panel, "s10 Bold cEDE1C9", "Segoe UI")
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
                SetAccessibleTextFont(probe, "s" fontSize " Bold cE7BE70", "Segoe UI")
                labelProbe := probe.Add("Text", "x0 y0 BackgroundTrans +0x80", item.Label)
                labelProbe.GetPos(, , &labelWidth)
                SetAccessibleTextFont(probe, "s" fontSize " Norm cFFF0DC", "Segoe UI")
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
        SetAccessibleTextFont(panel, "s" compactFontSize " Bold cE7BE70", "Segoe UI")
        labelControl := panel.Add("Text", "x0 y0 BackgroundTrans +0x80", item.Label)
        labelControl.GetPos(, , &labelWidth)
        SetAccessibleTextFont(panel, "s" compactFontSize " Norm cFFF0DC", "Segoe UI")
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

; Version Status uses physical-pixel GUI bounds. Measure the native
; header before building the existing scroll viewport. Keep the footer
; and window scale; the existing scroll region starts below the metadata.
ReflowVersionStatusHeader(title, message, heading, build)
{
    global AccessibilityTextSize
    if AccessibilityTextSize = "Normal"
        return 0
    titleH := Max(38, MeasureAccessibleWrappedText(title, title.Text, 732) + 4)
    messageY := Max(65, 20 + titleH + 7)
    messageH := Max(30, MeasureAccessibleWrappedText(message, message.Text, 732) + 4)
    headingY := Max(123, messageY + messageH + 12)
    headingH := Max(30, MeasureAccessibleWrappedText(heading, heading.Text, 422) + 4)
    buildH := Max(22, MeasureAccessibleWrappedText(build, build.Text, 280) + 4)
    title.Move(30, 20, 740, titleH)
    message.Move(30, messageY, 740, messageH)
    heading.Move(30, headingY, 430, headingH)
    build.Move(482, headingY + 6, 288, buildH)
    return Max(0, headingY + Max(headingH, 6 + buildH) + 5 - 158)
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
        SetAccessibleTextFont(panel, "s14 Bold cC5A45C", "Georgia")
        titleControl := panel.Add("Text", "x30 y20 w740 h38 BackgroundTrans", title)
        SetAccessibleTextFont(panel, "s10 cEDE1C9", "Segoe UI")
        messageControl := panel.Add("Text", "x30 y65 w740 h30 BackgroundTrans", message)
        SetAccessibleTextFont(panel, "s12 Bold cC5A45C", "Georgia")
        notesHeading := panel.Add("Text", "x30 y123 w430 h30 BackgroundTrans", "Release Notes")
        SetAccessibleTextFont(panel, "s9 cC5A45C", "Segoe UI")
        buildLabel := panel.Add("Text", "x482 y129 w288 h22 BackgroundTrans", "Build: v" notesVersion)
        topExtra := ReflowVersionStatusHeader(titleControl, messageControl, notesHeading, buildLabel)
        AddStyledButton(panel, 178, 544, 212, 34, "Check For Updates", (*) => (state.Retry := true, DestroyScaledMenu(panel)))
        AddStyledButton(panel, 410, 544, 212, 34, "Close", (*) => DestroyScaledMenu(panel))
        panel.OnEvent("Close", (*) => DestroyScaledMenu(panel))
        panel.OnEvent("Escape", (*) => DestroyScaledMenu(panel))
        scale := GetUpdatePromptFitScale(panel)
        ScaleOwnedMenuContent(panel, scale)
        closeNotes := AddUpdateNotesViewport(panel, releaseNotes, scale, 0, topExtra)
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
