; Load release notes and display them in the update dialogs' scrollable viewport.

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


; Build separate original-release and dated-hotfix tabs from actual GitHub
; publications. Missing history is never presented as if it were complete.
ReadPublishedUpdateHistory(installedVersion, latestVersion)
{
    global BundledResourceRoot
    script := (A_IsCompiled ? BundledResourceRoot : A_ScriptDir) "\scripts\fetch-release-notes.ps1"
    unavailable := "Published release history is unavailable. See GitHub Releases for complete details."
    result := {Release: unavailable, Hotfix: unavailable}
    if !FileExist(script)
        return result
    prefix := A_Temp "\tes3np-history-" DllCall("GetCurrentProcessId", "UInt") "-" A_TickCount
    featureFile := prefix "-releases.txt"
    hotfixFile := prefix "-hotfixes.txt"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' script
        . '" -InstalledVersion "' installedVersion '" -LatestVersion "' latestVersion
        . '" -ReleaseOutputPath "' featureFile '" -HotfixOutputPath "' hotfixFile '"'
    try
    {
        if RunWait(command, A_ScriptDir, "Hide") != 0 || !FileExist(featureFile) || !FileExist(hotfixFile)
            return result
        result.Release := FileRead(featureFile, "UTF-8")
        result.Hotfix := FileRead(hotfixFile, "UTF-8")
        return result
    }
    catch Error
        return result
    finally
    {
        try FileDelete(featureFile)
        try FileDelete(hotfixFile)
    }
}


; An update preview includes only the missed published versions.
ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion)
{
    history := ReadPublishedUpdateHistory(installedVersion, latestVersion)
    unavailable := "Published release history is unavailable. See GitHub Releases for complete details."
    if InStr(history.Release, unavailable) || InStr(history.Hotfix, unavailable)
        return unavailable
    try {
        records := []
        AddPublishedNoteRecords(history.Release, records)
        AddPublishedNoteRecords(history.Hotfix, records)
        if !records.Length
            return unavailable
        ; Merge the two published lists newest-first without changing content.
        Loop records.Length {
            index := 1
            while index < records.Length {
                if CompareUpdateNoteVersions(records[index].Version, records[index + 1].Version) < 0 {
                    current := records[index]
                    records[index] := records[index + 1]
                    records[index + 1] := current
                }
                index += 1
            }
        }
        return BuildCategorizedUpdateNotes(records)
    } catch Error {
        return unavailable
    }
}

AddPublishedNoteRecords(history, records)
{
    active := 0
    for line in StrSplit(StrReplace(history, "`r", ""), "`n") {
        if RegExMatch(line, "^###[ `t]+v(\S+)", &match) {
            version := match[1]
            info := ParseTes3npVersion(version)
            active := {Version: version, Label: Trim(SubStr(line, 5)),
                Hotfix: info.Hotfix > 0, Notes: ""}
            records.Push(active)
        } else if IsObject(active) {
            active.Notes .= line "`n"
        }
    }
}

CompareUpdateNoteVersions(left, right)
{
    a := ParseTes3npVersion(left)
    b := ParseTes3npVersion(right)
    for index, number in a.Feature {
        if number != b.Feature[index]
            return number > b.Feature[index] ? 1 : -1
    }
    return a.Hotfix = b.Hotfix ? 0 : a.Hotfix > b.Hotfix ? 1 : -1
}

; Use the bundled changelog for the installed base release and every installed
; hotfix. Do not show an uninstalled version or rely on GitHub when offline.
ReadInstalledCumulativeNotes(version)
{
    base := GetTes3npOriginalVersion(version)
    info := ParseTes3npVersion(version)
    records := []
    Loop info.Hotfix + 1 {
        number := A_Index - 1
        entryVersion := number = 0 ? base : base "." number
        notes := ReadBundledVersionNotes(entryVersion)
        if notes = "" {
            if number = 0
                notes := ReadPublishedVersionNotes(base)
            if notes = "" || InStr(notes, "currently unavailable")
                return "Complete release notes for v" version " are unavailable. See GitHub Releases."
        }
        records.Push({Version: entryVersion, Label: "v" entryVersion,
            Hotfix: number > 0, Notes: notes})
    }
    return BuildCategorizedUpdateNotes(records)
}

NoteCategoryName(heading, isHotfix)
{
    switch heading {
        case "New Features", "Improvements", "Removed Features", "Hotfixes":
            return heading
        case "Bug Fixes", "Fixed":
            return isHotfix ? "Hotfixes" : "Bug Fixes"
        case "Install":
            return ""
        default:
            return "Other Changes"
    }
}

; Preserve each change's original category and show its source version/date.
BuildCategorizedUpdateNotes(records)
{
    order := ["New Features", "Improvements", "Bug Fixes", "Hotfixes",
        "Removed Features", "Other Changes"]
    combined := Map()
    for category in order
        combined[category] := []
    for record in records {
        current := ""
        sections := Map()
        for category in order
            sections[category] := []
        for rawLine in StrSplit(StrReplace(record.Notes, "`r", ""), "`n") {
            line := Trim(rawLine)
            if RegExMatch(line, "^###[ `t]+(.+)$", &heading) {
                current := NoteCategoryName(heading[1], record.Hotfix)
                continue
            }
            if current = ""
                continue
            if RegExMatch(line, "^[-*+][ `t]+(.+)$", &bullet)
                sections[current].Push("- " bullet[1])
            else if line != "" && current = "Other Changes"
                sections[current].Push(line)
        }
        for category in order {
            if !sections[category].Length
                continue
            part := "#### " record.Label
            for bullet in sections[category]
                part .= "`n" bullet
            combined[category].Push(part)
        }
    }
    output := ""
    for category in order {
        if !combined[category].Length
            continue
        if output != ""
            output .= "`n`n"
        output .= "### " category
        for part in combined[category]
            output .= "`n`n" part
    }
    return output != "" ? output : "Release notes are unavailable. See GitHub Releases."
}

GetTes3npOriginalVersion(version)
{
    info := ParseTes3npVersion(version)
    feature := info.Feature[1] "." info.Feature[2] "." info.Feature[3]
    ; Legacy live builds used unsuffixed base release tags.
    return info.Channel = "live" && !InStr(version, "-live") ? feature : feature "-" info.Channel
}

ReleaseNoteFits(control, text, maxWidth)
{
    ; Measure in the label's font so wrapping follows the rendered width.
    if text = ""
        return true
    hFont := DllCall("SendMessageW", "Ptr", control.Hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr") ; WM_GETFONT
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
    paragraphBreak := false
    for entry in StrSplit(StrReplace(content, "`r", ""), "`n") {
        line := Trim(entry)
        if line = "" {
            paragraphBreak := true
            continue
        }
        kind := "body"
        if RegExMatch(line, "^#{1,6}\s+") {
            line := RegExReplace(line, "^#{1,6}\s+", "")
            kind := "heading"
        } else if RegExMatch(line, "^[-*+]\s+") {
            line := "• " RegExReplace(line, "^[-*+]\s+", "")
            line := StrReplace(line, "**", "")
        }
        measureRow.SetFont(UpdateNoteFont(kind), "Segoe UI")
        for index, part in WrapReleaseNoteLines(line, measureRow, maxWidth) {
            gapBefore := index = 1 && rows.Length > 0 && (paragraphBreak || kind != rows[rows.Length].Kind)
            rows.Push({Text: part, Kind: kind, GapBefore: gapBefore})
        }
        paragraphBreak := false
    }
    measureRow.SetFont(UpdateNoteFont("body"), "Segoe UI")
    if !rows.Length
        rows.Push({Text: "No release notes available.", Kind: "body", GapBefore: false})
    return rows
}

UpdateNotesMouseWheel(viewport, page, refresh, wParam, lParam, msg, hwnd)
{
    ; Use the viewport's HWND bounds because the wheel message uses screen pixels.
    if !DllCall("user32\IsWindow", "Ptr", viewport.Hwnd, "Int")
        return
    mx := (lParam & 0xFFFF) << 48 >> 48
    my := ((lParam >> 16) & 0xFFFF) << 48 >> 48
    bounds := Buffer(16, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", viewport.Hwnd, "Ptr", bounds)
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
    maxOffset := page.MaxOffset
    ; Mouse coordinates are physical pixels; use the actual on-screen track size.
    travel := Max(1, drag.TrackPixels - drag.ThumbPixels)
    page.Offset := 1 + Round((mouseY - drag.StartY) * (maxOffset - 1) / travel) + drag.StartOffset - 1
    refresh()
}

StartUpdateNotesDrag(panel, thumb, track, drag, page, refresh, wParam, lParam, msg, hwnd)
{
    if page.MaxOffset <= 1
        return
    ; Hit-test the thumb by screen position because the press can reach its parent.
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

UpdateNoteFont(kind)
{
    return kind = "heading" ? "s12 Bold cE7BE70" : "s11 Norm cF4E9D6"
}

ReleaseNoteLineHeight(control)
{
    hwnd := control.Hwnd
    font := DllCall("SendMessageW", "Ptr", hwnd, "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
    dc := DllCall("user32\GetDC", "Ptr", hwnd, "Ptr")
    if !dc
        throw OSError()
    previous := font ? DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr") : 0
    try {
        metrics := Buffer(60, 0) ; TEXTMETRICW
        if !DllCall("gdi32\GetTextMetricsW", "Ptr", dc, "Ptr", metrics, "Int")
            throw OSError()
        return NumGet(metrics, 0, "Int") ; tmHeight
    } finally {
        if previous
            DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", previous)
        DllCall("user32\ReleaseDC", "Ptr", hwnd, "Ptr", dc)
    }
}

AddUpdateNotesViewport(panel, notes, scale, switcher := 0, topExtra := 0, bottomExtra := 0)
{
    ; The taller update preview reflows the same existing viewport without
    ; changing the verified Version Status geometry (both extras default 0).
    px := (value) => Round(value * scale)
    viewport := panel.Add("Text", "x" px(28) " y" px(158 + topExtra)
        . " w" px(744) " h" px(367 + bottomExtra - topExtra) " BackgroundC5A45C")
    panel.Add("Text", "x" px(30) " y" px(160 + topExtra)
        . " w" px(740) " h" px(363 + bottomExtra - topExtra) " Background171008")
    ; Measure the actual Windows font before allocating rows. Launcher scale
    ; sizes the card, and the text keeps its normal size and wraps as needed.
    firstY := px(170 + topExtra), bottomY := px(516 + bottomExtra)
    left := px(42), width := px(686)
    panel.SetFont(UpdateNoteFont("body"), "Segoe UI")
    sample := panel.Add("Text", "Hidden x" left " y" firstY " w" width " h1 Background171008 +0x80", "")
    bodyHeight := ReleaseNoteLineHeight(sample)
    sample.SetFont(UpdateNoteFont("heading"), "Segoe UI")
    rowHeight := Max(bodyHeight, ReleaseNoteLineHeight(sample)) + 1
    ; The measurement row becomes the first displayed row. Restore its body
    ; style after measuring the heading font, including on empty history tabs.
    sample.SetFont(UpdateNoteFont("body"), "Segoe UI")
    lineGap := Max(1, px(2)), sectionGap := Max(1, px(4))
    stride := rowHeight + lineGap
    lines := BuildStyledReleaseNoteRows(notes, sample, width - Max(2, px(10)))
    capacity := Max(1, (bottomY - firstY + lineGap) // stride)
    ; Find the first row of the last page so the final notes fill the viewport.
    lastOffset := lines.Length
    used := rowHeight
    while lastOffset > 1 {
        nextHeight := used + stride + (lines[lastOffset].GapBefore ? sectionGap : 0)
        if nextHeight > bottomY - firstY
            break
        used := nextHeight
        lastOffset -= 1
    }
    page := {Offset: 1, Lines: lines, MaxOffset: lastOffset}
    noteRows := [sample]
    rowStyles := ["body"]
    ; Allocate the whole viewport so switching from short to long notes fills it.
    Loop capacity - 1 {
        noteRows.Push(panel.Add("Text", "Hidden x" left " y" firstY " w" width " h" rowHeight " Background171008 +0x80", ""))
        rowStyles.Push("body")
    }
    trackY := px(188 + topExtra), trackHeight := px(309 + bottomExtra - topExtra)
    thumbX := px(750), thumbWidth := px(8)
    track := panel.Add("Text", "x" px(746) " y" trackY " w" px(16) " h" trackHeight " Background704C27")
    thumb := panel.Add("Text", "x" thumbX " y" trackY " w" thumbWidth " h" px(32) " +0x100 BackgroundC69951")
    drag := {Active: false, StartY: 0, StartOffset: 1, Timer: 0}
    refresh(*) {
        page.Offset := Min(page.MaxOffset, Max(1, page.Offset))
        y := firstY
        for index, row in noteRows {
            rowIndex := index + page.Offset - 1
            if rowIndex > page.Lines.Length {
                row.Visible := false
                continue
            }
            entry := page.Lines[rowIndex]
            if index > 1 && entry.GapBefore
                y += sectionGap
            if y + rowHeight > bottomY {
                row.Visible := false
                continue
            }
            if rowStyles[index] != entry.Kind {
                row.SetFont(UpdateNoteFont(entry.Kind), "Segoe UI")
                rowStyles[index] := entry.Kind
            }
            row.Move(left, y, width, rowHeight)
            row.Text := entry.Text
            row.Visible := true
            y += stride
        }
        thumbHeight := Max(px(22), Round(trackHeight * Min(1, capacity / page.Lines.Length)))
        thumbY := trackY + Round((trackHeight - thumbHeight) * (page.Offset - 1) / Max(1, page.MaxOffset - 1))
        thumb.Move(thumbX, thumbY, thumbWidth, thumbHeight)
        track.Visible := page.MaxOffset > 1
        thumb.Visible := page.MaxOffset > 1
    }
    updateNotes(newNotes)
    {
        page.Lines := BuildStyledReleaseNoteRows(newNotes, sample, width - Max(2, px(10)))
        page.Offset := 1
        lastOffset := page.Lines.Length
        used := rowHeight
        while lastOffset > 1
        {
            nextHeight := used + stride + (page.Lines[lastOffset].GapBefore ? sectionGap : 0)
            if nextHeight > bottomY - firstY
                break
            used := nextHeight
            lastOffset -= 1
        }
        page.MaxOffset := lastOffset
        refresh()
    }
    if IsObject(switcher)
        switcher.Update := updateNotes
    dragStartCallback := StartUpdateNotesDrag.Bind(panel, thumb, track, drag, page, refresh)
    up := AddStyledButton(panel, px(744), px(163 + topExtra), px(20), px(22), "↑", (*) => (page.Offset -= 1, refresh()))
    down := AddStyledButton(panel, px(744), px(500 + bottomExtra), px(20), px(22), "↓", (*) => (page.Offset += 1, refresh()))
    for arrow in [up, down]
        arrow.SetFont(UpdateNoteFont("heading"), "Segoe UI")
    refresh()
    wheelCallback := UpdateNotesMouseWheel.Bind(viewport, page, refresh)
    OnMessage(0x0201, dragStartCallback, 1)
    try OnMessage(0x020A, wheelCallback, 1)
    catch {
        OnMessage(0x0201, dragStartCallback, 0)
        throw
    }
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
