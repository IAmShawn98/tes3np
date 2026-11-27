; Local macro packages. Import extracts files; only Run executes a chosen script.

BuildMacroBookPanel()
{
    global CharacterPage, LauncherMorrowindFont, ButtonFaces
    global MacroPage, MacroList, MacroStatus, MacroEmptyNotice
    global MacroImportButton, MacroBookControls, MacroBookRows, MacroNameEdit
    global MacroScrollOffset
    MacroPage := CharacterPage
    MacroBookControls := []
    MacroBookRows := []
    MacroScrollOffset := 0
    SetAccessibleTextFont(CharacterPage, "s19 Norm c241408", LauncherMorrowindFont)
    heading := CharacterPage.Add("Text", "x525 y45 w355 h32 Center BackgroundTrans", "Manage Macros")
    SetAccessibleTextFont(CharacterPage, "s11 Norm c241408", LauncherMorrowindFont)
    explanation := CharacterPage.Add("Text", "x525 y87 w355 h48 BackgroundTrans",
        "Macros allow you to automate processes like fishing and training. The launcher contains some pre-built macros right out of the box for you to use right away. If you'd like, you can also write your own macros and upload them here for daily use.")
    MacroEmptyNotice := CharacterPage.Add("Text", "x525 y150 w355 h28 BackgroundTrans",
        "No macros were found.")
    ; The hidden ListView retains every imported item and all existing handlers.
    ; Four reusable rows per page, not a limit on the number of macros.
    MacroList := CharacterPage.Add("ListView", "x525 y144 w355 h226 Hidden -Multi",
        ["Name", "Status", "Type"])
    MacroList.OnEvent("ItemSelect", RefreshMacroButtons)
    MacroBookControls.Push(heading, explanation, MacroEmptyNotice, MacroList)
    Loop 4
    {
        position := A_Index
        ; Name, rename and state share a header; actions occupy the full lane.
        y := 140 + (position - 1) * 70
        SetAccessibleTextFont(CharacterPage, "s9 Norm c241408", LauncherMorrowindFont)
        status := CharacterPage.Add("Text",
            "x752 y" (y + 2) " w128 h22 BackgroundTrans c241408 +0x100", "")
        SetAccessibleTextFont(CharacterPage, "s12 Norm c241408", LauncherMorrowindFont)
        tick := AddBookTick(CharacterPage, 525, y + 2, SelectMacroBookRow.Bind(position))
        name := AddBookLabel(CharacterPage, 551, y, 125, 22, "")
        ButtonFaces[name.Hwnd].UseControlPosition := true
        rename := AddStyledButton(CharacterPage, 682, y, 21, 22,
            Chr(0x270E), EditMacroBookRow.Bind(position))
        ButtonFaces[rename.Hwnd].UseControlPosition := true
        SetAccessibleTextFont(rename, "s10 Bold", "Segoe UI Symbol")
        run := AddStyledButton(CharacterPage, 525, y + 29, 111, 24,
            "Run", RunMacroBookRow.Bind(position))
        stop := AddStyledButton(CharacterPage, 646, y + 29, 112, 24,
            "Stop", StopMacroBookRow.Bind(position))
        remove := AddStyledButton(CharacterPage, 768, y + 29, 112, 24,
            "Remove", RemoveMacroBookRow.Bind(position))
        MacroBookRows.Push({Tick: tick, Status: status, StatusError: false,
            Name: name, Rename: rename, Y: y, NameWidth: 125, NameScale: 0,
            Run: run, Stop: stop, Remove: remove})
        MacroBookControls.Push(tick, status, name, rename, run, stop, remove)
    }
    SetAccessibleTextFont(CharacterPage, "s10 c382314", LauncherThemeFont())
    MacroNameEdit := AddThemedEdit(CharacterPage, "x551 y140 w125 h22 Hidden Limit100 -Multi")
    MacroNameEdit.EditingItem := 0
    MacroNameEdit.ErrorText := ""
    ; Match the Character Book's Previous / Page N of M / Next navigation.
    CharacterPage.MacroPreviousPage := AddStyledButton(CharacterPage, 525, 424, 105, 30,
        "Previous", ChangeMacroBookPage.Bind(-1))
    CharacterPage.MacroNextPage := AddStyledButton(CharacterPage, 775, 424, 105, 30,
        "Next", ChangeMacroBookPage.Bind(1))
    SetAccessibleTextFont(CharacterPage, "s12 Norm c241408", LauncherMorrowindFont)
    CharacterPage.MacroPageLabel := CharacterPage.Add("Text", "x632 y424 w141 h30 Center BackgroundTrans Hidden", "")
    CharacterPage.MacroPreviousPage.Visible := false
    CharacterPage.MacroNextPage.Visible := false
    ; Keep the compact Upload action aligned with the introduction.
    MacroImportButton := AddStyledButton(CharacterPage, 525, 188, 150, 29,
        "Upload Macro", ImportMacroPackage)
    ; Progress and failure feedback for imports appears under Upload.
    SetAccessibleTextFont(CharacterPage, "s9 Norm c241408", LauncherMorrowindFont)
    MacroStatus := CharacterPage.Add("Text",
        "x525 y224 w355 h30 Hidden BackgroundTrans c241408", "")
    MacroBookControls.Push(CharacterPage.MacroPreviousPage, CharacterPage.MacroPageLabel,
        CharacterPage.MacroNextPage, MacroImportButton, MacroStatus)
    LoadMacroPackages()
    ShowMacroBookPanel()
}

ShowMacroBookPanel()
{
    global MacroBookControls, MacroList, MacroNameEdit
    ; The editor's hide path may run before the book has built its controls.
    if !IsObject(MacroList)
        return
    MacroNameEdit.EditingItem := 0
    MacroNameEdit.ErrorText := ""
    for control in MacroBookControls
        if control != MacroList
            control.Visible := true
    ; Retain the legacy ListView only as an invisible selection model.
    MacroList.Visible := false
    RefreshMacroButtons()
}

HideMacroBookPanel()
{
    global MacroBookControls, MacroNameEdit
    if IsObject(MacroNameEdit)
    {
        MacroNameEdit.EditingItem := 0
        MacroNameEdit.Visible := false
    }
    for control in MacroBookControls
        try control.Visible := false
}

MacroProcessRunning(item)
{
    return item.ProcessHandle
        && DllCall("WaitForSingleObject", "Ptr", item.ProcessHandle, "UInt", 0, "UInt") = 258
}

MacroItemDisplayState(item)
{
    if item.Kind = "App" && !ValidMacroApplication(item)
        return {Text: "Application missing", Error: true}
    if item.Kind != "App" && !ValidMacroEntry(item.Folder, item.Entry)
        return {Text: "Script missing", Error: true}
    if item.HasOwnProp("LastError") && item.LastError != ""
        return {Text: item.LastError, Error: true}
    if MacroProcessRunning(item)
        return {Text: "Running", Error: false}
    return {Text: "Ready", Error: false}
}

; A one-second macro-process refresh must not needlessly repaint a
; stationary text control. Positions are already in GUI pixels.
MoveMacroTextIfChanged(control, x, y, width, height)
{
    control.GetPos(&oldX, &oldY, &oldWidth, &oldHeight)
    if oldX != x || oldY != y || oldWidth != width || oldHeight != height
        control.Move(x, y, width, height)
}

; Coordinates are immutable Book design units. Keep native hitboxes and
; their separately painted Morrowind buttons synchronized without a timer
; repaint when the same arrangement is already visible.
MoveMacroStyledIfChanged(control, x, y, width, height)
{
    control.GetPos(&oldX, &oldY, &oldWidth, &oldHeight)
    if oldX != BookS(x) || oldY != BookS(y)
        || oldWidth != BookS(width) || oldHeight != BookS(height)
        MoveStyledButton(control, x, y, width, height)
}

; Cache name measurements for the entire collection, not just the four
; visible slots. Paging changes the visible labels, never the row pitch.
MeasureMacroNameCollection(sample, items, maxNameW)
{
    global CharacterPage, AccessibilityTextSize
    scale := GetCharacterBookScale()
    font := DllCall("SendMessageW", "Ptr", sample.Hwnd, "UInt", 0x31,
        "Ptr", 0, "Ptr", 0, "Ptr")
    previous := CharacterPage.HasOwnProp("MacroNameMetrics") ? CharacterPage.MacroNameMetrics : 0
    key := Format("{}|{}|{}|{}|{}", font, maxNameW, scale, A_ScreenDPI, AccessibilityTextSize)
    cache := Map()
    cache.CaseSense := true
    ordered := [], maxHeight := 22
    for item in items
    {
        if cache.Has(item.Name)
            metrics := cache[item.Name]
        else if IsObject(previous) && previous.Key == key && previous.Names.Has(item.Name)
            metrics := previous.Names[item.Name]
        else
        {
            extent := MeasureAccessibleSingleLineText(sample, item.Name)
            width := Min(maxNameW, Max(70, Ceil((extent.Width + BookS(8)) / scale)))
            displayName := PrepareAccessibleBookName(sample, item.Name, BookS(width - 8))
            height := Ceil((MeasureAccessibleWrappedText(sample, displayName,
                BookS(width - 8)) + BookS(4)) / scale)
            metrics := {Width: width, Display: displayName, Height: height}
        }
        cache[item.Name] := metrics
        ordered.Push(metrics)
        maxHeight := Max(maxHeight, metrics.Height)
    }
    CharacterPage.MacroNameMetrics := {Key: key, Names: cache}
    return {Items: ordered, Height: maxHeight}
}

; Measure Upload and its complete feedback copy before the shared height
; request. Keep the seven-pixel original gap below Upload and the approved
; Normal bottom of the four-row feedback stack (490), not the footer (570).
GetMacroUploadMetrics()
{
    global AccessibilityTextSize, MacroImportButton, MacroStatus, CharacterPage, MacroItems
    width := 150, height := 29, feedbackHeight := 30, navHeight := 30
    if AccessibilityTextSize != "Normal"
    {
        if IsSet(MacroImportButton) && IsObject(MacroImportButton)
        {
            metrics := BookActionMetrics(MacroImportButton, "Upload Macro", 150, 29)
            width := Min(355, metrics.Width), height := metrics.Height
        }
        if IsObject(CharacterPage) && CharacterPage.HasOwnProp("MacroPreviousPage")
        {
            for button in [CharacterPage.MacroPreviousPage, CharacterPage.MacroNextPage]
                navHeight := Max(navHeight, BookActionMetrics(button, button.Text, 105, 30).Height)
            label := CharacterPage.MacroPageLabel
            caption := "Page " Max(1, MacroItems.Length) " of " Max(1, MacroItems.Length)
            navHeight := Max(navHeight, Ceil((MeasureAccessibleWrappedText(label, caption,
                BookS(137)) + BookS(4)) / GetCharacterBookScale()))
        }
        if IsSet(MacroStatus) && IsObject(MacroStatus)
        {
            scale := GetCharacterBookScale()
            for caption in ["Extracting and checking macro package...", "The script could not be imported.", MacroStatus.Text]
                feedbackHeight := Max(feedbackHeight, Ceil((MeasureAccessibleWrappedText(
                    MacroStatus, caption, BookS(351)) + BookS(4)) / scale))
        }
    }
    return {UploadWidth: width, UploadHeight: height, FeedbackHeight: feedbackHeight,
        FeedbackOffset: height + 7, NavigationHeight: navHeight}
}

GetMacroVisibleSlots()
{
    global CharacterPage, MacroBookRows
    return IsObject(CharacterPage) && CharacterPage.HasOwnProp("MacroVisibleSlots")
        ? CharacterPage.MacroVisibleSlots : Max(1, MacroBookRows.Length)
}

; Prefer all four rows. On a constrained monitor retain the measured
; introduction and use fewer rows per page.
FitMacroViewport(offset, pitch, upload)
{
    global MacroItems, MacroBookRows
    Loop MacroBookRows.Length
    {
        slots := MacroBookRows.Length - A_Index + 1
        shownCount := Min(MacroItems.Length, slots)
        navigation := MacroItems.Length > slots ? upload.NavigationHeight + 8 : 0
        requiredExtra := Max(0, 144 + offset + shownCount * pitch + navigation + upload.FeedbackOffset + upload.FeedbackHeight - 490)
        if SetCharacterBookLayoutExtra("Macros", requiredExtra)
            return slots
    }
    return 0
}

; Recompute the introduction and viewport from immutable design anchors.
; Normal text also requires measurement for the longer introduction.
ReflowPopulatedMacroBook()
{
    global CharacterPage, MacroItems, MacroBookControls, MacroBookRows
    global AccessibilityTextSize
    global MacroScrollOffset, MacroNameEdit, ButtonFaces
    if !IsObject(CharacterPage) || !MacroItems.Length
        || MacroBookControls.Length < 2
        return 0
    scale := GetCharacterBookScale()
    explanation := MacroBookControls[2]
    copyY := BookHeadingCopyY(MacroBookControls[1], 525, 355, 32, 87)
    copyHeight := Max(BookS(48), MeasureAccessibleWrappedText(
        explanation, explanation.Text, Max(1, BookS(355) - BookS(4))) + BookS(4))
    offset := Max(0, copyY + Ceil(copyHeight / scale) + 10 - 140)
    statusH := 17, nameH := 22, actionH := 24, saveW := 49, pencilW := 21
    measured := true
    shownCount := Min(MacroItems.Length, MacroBookRows.Length)
    widths := [], displayNames := []
    if measured
    {
        sample := MacroBookRows[1]
        ; Reserve status/error lines before they appear so polling and
        ; entering rename mode do not shift a row for ordinary state changes.
        for caption in ["(Ready)", "(Running)", "Application missing", "Script missing",
            "Process tracking unavailable", "Runtime missing", "Launch failed",
            "Could not stop", "Enter a name (1–100 characters).", "Could not save the macro name."]
            statusH := Max(statusH, Ceil((MeasureAccessibleWrappedText(
                sample.Status, caption, BookS(124)) + BookS(2)) / scale))
        save := MeasureAccessibleSingleLineText(sample.Rename, "Save")
        pencil := MeasureAccessibleSingleLineText(sample.Rename, Chr(0x270E))
        saveW := Max(49, Ceil((save.Width + BookS(8)) / scale))
        pencilW := Max(21, Ceil((pencil.Width + BookS(8)) / scale))
        nameH := Max(nameH, Ceil((Max(save.Height, pencil.Height) + BookS(6)) / scale))
        if IsObject(MacroNameEdit)
        {
            editExtent := MeasureAccessibleSingleLineText(MacroNameEdit, "Ag")
            nameH := Max(nameH, Ceil((editExtent.Height + BookS(8)) / scale))
        }
        maxNameW := 329 - 14 - Max(saveW, pencilW) - 128
        if maxNameW < 64
            measured := false
        maxNameW := Max(32, maxNameW)
        collection := MeasureMacroNameCollection(sample.Name, MacroItems, maxNameW)
        nameH := Max(nameH, collection.Height)
        for position, row in MacroBookRows
        {
            if position > shownCount
                break
            for index, button in [row.Run, row.Stop, row.Remove]
            {
                extent := MeasureAccessibleSingleLineText(button, button.Text)
                if extent.Width + BookS(8) > BookS(index = 1 ? 111 : 112)
                    measured := false
                actionH := Max(actionH, Ceil((extent.Height + BookS(6)) / scale))
            }
        }
    }
    headerH := Max(nameH, statusH + 2)
    pitch := Max(70, headerH + 7 + actionH + 12)
    upload := GetMacroUploadMetrics()
    slots := (measured || AccessibilityTextSize = "Normal") ? FitMacroViewport(offset, pitch, upload) : 0
    if !slots
    {
        ; Keep the existing compact action-row fallback without clipping
        ; the longer introduction. Reduce visible slots before dropping copy.
        measured := false
        nameH := 22, actionH := 24, saveW := 49, pencilW := 21
        headerH := Max(nameH, statusH + 2)
        pitch := Max(70, headerH + 7 + actionH + 12)
        upload := {UploadWidth: upload.UploadWidth, UploadHeight: 29, FeedbackHeight: 30,
            FeedbackOffset: 36, NavigationHeight: upload.NavigationHeight}
        slots := FitMacroViewport(offset, pitch, upload)
        if !slots
        {
            SetCharacterBookLayoutExtra("Macros", 0)
            slots := 1
        }
    }
    CharacterPage.MacroVisibleSlots := slots
    pagePlan := GetMacroPagePlan(MacroItems.Length, slots, MacroScrollOffset)
    MacroScrollOffset := pagePlan.Offset
    if measured
    {
        Loop pagePlan.Count
        {
            position := A_Index
            metrics := collection.Items[MacroScrollOffset + position]
            widths.Push(metrics.Width)
            displayNames.Push(metrics.Display)
        }
    }
    CharacterPage.MacroUploadMetrics := upload
    CharacterPage.MacroRowsMeasured := measured
    CharacterPage.MacroRowPitch := pitch
    CharacterPage.MacroViewportHeight := slots * pitch - 12
    MoveMacroTextIfChanged(explanation, BookS(525), BookS(copyY),
        BookS(355), copyHeight)
    for position, row in MacroBookRows
    {
        targetY := 140 + (position - 1) * pitch + offset
        nameY := targetY
        actionY := nameY + headerH + 7
        if row.Y != nameY || !row.HasOwnProp("Measured") || row.Measured != measured
            row.NameScale := 0
        row.Y := nameY
        row.Measured := measured
        row.NameHeight := nameH
        row.StatusHeight := headerH - 2
        row.SaveWidth := saveW
        row.PencilWidth := pencilW
        if measured && position <= widths.Length
            row.NameWidth := widths[position]
        else if !measured && row.NameScale = 0
            row.NameWidth := 125
        if ButtonFaces.Has(row.Name.Hwnd)
        {
            face := ButtonFaces[row.Name.Hwnd]
            face.AccessibleWrappedName := measured
            if measured && position <= displayNames.Length
                face.AccessibleNameText := displayNames[position]
            else if face.HasOwnProp("AccessibleNameText")
                face.DeleteProp("AccessibleNameText")
        }
        for button in [row.Rename, row.Run, row.Stop, row.Remove]
            if ButtonFaces.Has(button.Hwnd)
                ButtonFaces[button.Hwnd].NoAccessibleDownfit := measured
        LayoutMacroRowStatus(row, row.HasOwnProp("Editing") && row.Editing)
        MoveMacroStyledIfChanged(row.Tick, 525, nameY + 2, 18, 18)
        MoveMacroStyledIfChanged(row.Name, 551, nameY, row.NameWidth, nameH)
        MoveMacroStyledIfChanged(row.Run, 525, actionY, 111, actionH)
        MoveMacroStyledIfChanged(row.Stop, 646, actionY, 112, actionH)
        MoveMacroStyledIfChanged(row.Remove, 768, actionY, 112, actionH)
    }
    CharacterPage.MacroViewportOffset := offset
    return offset
}

; The empty Macro Book shares the approved fixed parchment with Characters.
; Measure its complete copy and move the notice and Upload as a single stack.
; Populated rows have a separate pagination/rename layout and stay untouched.
ReflowEmptyMacroBook()
{
    global CharacterPage, MacroItems, MacroBookControls
    global MacroEmptyNotice, AccessibilityTextSize
    if !IsObject(CharacterPage) || MacroBookControls.Length < 2
        return 188
    upload := GetMacroUploadMetrics()
    CharacterPage.MacroUploadMetrics := upload
    explanation := MacroBookControls[2]
    copyY := BookHeadingCopyY(MacroBookControls[1], 525, 355, 32, 87)
    CharacterPage.MacroVisibleSlots := 4
    CharacterPage.MacroViewportOffset := 0
    CharacterPage.MacroRowPitch := 70
    CharacterPage.MacroViewportHeight := 268
    scale := GetCharacterBookScale()
    copyHeight := Max(BookS(48), MeasureAccessibleWrappedText(
        explanation, explanation.Text, Max(1, BookS(355) - BookS(4)))
        + BookS(4))
    emptyHeight := Max(BookS(28), MeasureAccessibleWrappedText(
        MacroEmptyNotice, MacroEmptyNotice.Text,
        Max(1, BookS(355) - BookS(4))) + BookS(4))
    copyHeightLogical := Ceil(copyHeight / scale)
    emptyHeightLogical := Ceil(emptyHeight / scale)
    noticeY := Max(150, copyY + copyHeightLogical + 15)
    uploadY := Max(188, noticeY + emptyHeightLogical + 10)
    ; Reserve room for existing upload-progress copy below Upload, even
    ; when this particular refresh has no visible error.
    if !SetCharacterBookLayoutExtra("Macros", Max(0, uploadY + upload.FeedbackOffset + upload.FeedbackHeight - 490))
    {
        SetCharacterBookLayoutExtra("Macros", 0)
        CharacterPage.MacroUploadMetrics := {UploadWidth: upload.UploadWidth, UploadHeight: 29,
            FeedbackHeight: 30, FeedbackOffset: 36, NavigationHeight: upload.NavigationHeight}
        ; Keep the measured introduction even if artwork cannot grow.
    }
    MoveMacroTextIfChanged(explanation, BookS(525), BookS(copyY),
        BookS(355), copyHeight)
    MoveMacroTextIfChanged(MacroEmptyNotice, BookS(525), BookS(noticeY),
        BookS(355), BookS(emptyHeightLogical))
    return uploadY
}

RefreshMacroBookRows()
{
    global MacroList, MacroItems, MacroBookRows, MacroScrollOffset, MacroImport
    global MacroEmptyNotice, MacroStatus
    global MacroImportButton, CharacterPage, InterfaceUpdating, MacroNameEdit
    global LaunchSettingsHeading, ButtonFaces, LauncherMorrowindFont, AccessibilityTextSize
    if !IsObject(MacroList) || !MacroBookRows.Length
        return
    count := MacroItems.Length
    shown := !LaunchSettingsHeading.Visible
    ; The visible editor owns the right column while macro process polling
    ; continues. Its geometry must not be replaced by a hidden macro stack.
    if !shown
        return
    selectedIndex := MacroList.GetNext()
    busy := IsObject(MacroImport)
    populatedOffset := count ? ReflowPopulatedMacroBook() : 0
    slots := count ? GetMacroVisibleSlots() : MacroBookRows.Length
    plan := GetMacroPagePlan(count, slots, MacroScrollOffset)
    MacroScrollOffset := plan.Offset
    rowPitch := count ? CharacterPage.MacroRowPitch : 70
    editVisible := false
    MacroList.Visible := false
    for position, itemRow in MacroBookRows
    {
        index := MacroScrollOffset + position
        visible := shown && position <= plan.Count && index <= count
        for control in [itemRow.Tick, itemRow.Status, itemRow.Rename,
            itemRow.Run, itemRow.Stop, itemRow.Remove]
            if control.Visible != visible
                control.Visible := visible
        if !visible
        {
            if itemRow.Name.Visible
                itemRow.Name.Visible := false
            continue
        }
        item := MacroItems[index]
        editing := IsObject(MacroNameEdit.EditingItem) && MacroNameEdit.EditingItem = item
        RefreshMacroNameRow(itemRow, item.Name, editing)
        editVisible := editVisible || editing
        selected := index = selectedIndex
        if ButtonFaces[itemRow.Tick.Hwnd].Checked != selected
            SetBookTick(itemRow.Tick, selected)
        state := editing && MacroNameEdit.ErrorText != ""
            ? {Text: MacroNameEdit.ErrorText, Error: true} : MacroItemDisplayState(item)
        displayState := state.Error ? state.Text : "(" state.Text ")"
        if itemRow.Status.Text != displayState
            itemRow.Status.Text := displayState
        if itemRow.StatusError != state.Error
        {
            ; Only the ink changes: preserve the measured scaled font.
            itemRow.Status.SetFont(state.Error ? "cB22222" : "c241408")
            itemRow.StatusError := state.Error
        }
        running := MacroProcessRunning(item)
        missing := !ValidMacroApplication(item)
            || (item.Kind != "App" && !ValidMacroEntry(item.Folder, item.Entry))
        canRun := !missing && !running && !busy
        canStop := !!running
        canRemove := !running && !busy
        if itemRow.Run.Enabled != canRun
            itemRow.Run.Enabled := canRun
        if itemRow.Stop.Enabled != canStop
            itemRow.Stop.Enabled := canStop
        if itemRow.Remove.Enabled != canRemove
            itemRow.Remove.Enabled := canRemove
    }
    if MacroNameEdit.Visible != editVisible
        MacroNameEdit.Visible := editVisible
    MacroEmptyNotice.Visible := shown && count = 0
    ; Keep empty-state content close to the introduction, then follow
    ; paginated rows. Keep navigation and Upload stationary across pages.
    visibleCount := Min(count, slots)
    emptyUploadY := count = 0 ? ReflowEmptyMacroBook() : 188
    desiredUploadY := count = 0 ? emptyUploadY
        : 144 + visibleCount * rowPitch + populatedOffset
    upload := CharacterPage.MacroUploadMetrics
    if PositionMacroBookNavigation(CharacterPage, plan, desiredUploadY, upload.NavigationHeight)
        desiredUploadY += upload.NavigationHeight + 8
    MacroImportButton.GetPos(, &oldUploadY, &oldUploadWidth, &oldUploadHeight)
    if ButtonFaces.Has(MacroImportButton.Hwnd)
        ButtonFaces[MacroImportButton.Hwnd].NoAccessibleDownfit := AccessibilityTextSize != "Normal"
    if oldUploadY != BookS(desiredUploadY) || oldUploadWidth != BookS(upload.UploadWidth)
        || oldUploadHeight != BookS(upload.UploadHeight)
    {
        ; Move the themed hit target and painted face together. Hide while
        ; relocating to avoid leaving stale button artwork on parchment.
        wasVisible := MacroImportButton.Visible
        if wasVisible
            MacroImportButton.Visible := false
        MoveStyledButton(MacroImportButton, 525, desiredUploadY, upload.UploadWidth, upload.UploadHeight)
        if wasVisible
        {
            MacroImportButton.Visible := true
            if !InterfaceUpdating
                DllCall("RedrawWindow", "Ptr", CharacterPage.Hwnd,
                    "Ptr", 0, "Ptr", 0, "UInt", 0x385)
        }
    }
    ; Follow Upload when its stack changes, but do not move/repaint this
    ; native HWND every one-second macro process polling refresh.
    MoveMacroTextIfChanged(MacroStatus, BookS(525), BookS(desiredUploadY + upload.FeedbackOffset),
        BookS(355), BookS(upload.FeedbackHeight))
    ; Only import failures/progress use the message area below Upload.
    ; Regular Ready/Running/Missing appears beside each macro's name.
    feedback := MacroStatus.Text
    showFeedback := busy || RegExMatch(feedback,
        "i)^(Import failed:|The script could not be imported)")
    if MacroStatus.Visible != (shown && showFeedback)
        MacroStatus.Visible := shown && showFeedback
}

SelectMacroBookRow(position, *)
{
    global MacroList, MacroScrollOffset, MacroItems
    plan := GetMacroPagePlan(MacroItems.Length, GetMacroVisibleSlots(), MacroScrollOffset)
    if position < 1 || position > plan.Count
        return false
    index := plan.Offset + position
    MacroList.Modify(index, "Select Focus")
    RefreshMacroButtons()
    return true
}

LayoutMacroRowStatus(row, editing)
{
    width := editing ? row.SaveWidth : row.PencilWidth
    MoveMacroStyledIfChanged(row.Rename, 557 + row.NameWidth, row.Y, width, row.NameHeight)
    x := 557 + row.NameWidth + width + 8
    MoveMacroTextIfChanged(row.Status, BookS(x), BookS(row.Y + 2),
        BookS(Max(1, 880 - x)), BookS(row.StatusHeight))
}

RefreshMacroNameRow(row, name, editing)
{
    global MacroNameEdit
    scale := GetCharacterBookScale()
    if !(row.Name.Text == name) || row.NameScale != scale
    {
        if !row.Measured
        {
        ; Measure the current font so the pencil follows short names, and
        ; reserve room for Save on long names at every launcher scale.
        handle := row.Name.Hwnd
        dc := DllCall("GetDC", "Ptr", handle, "Ptr")
        if dc
        {
            font := DllCall("SendMessageW", "Ptr", handle, "UInt", 0x0031, "Ptr", 0, "Ptr", 0, "Ptr")
            oldFont := font ? DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", font, "Ptr") : 0
            size := Buffer(8, 0)
            try
                if DllCall("gdi32\GetTextExtentPoint32W", "Ptr", dc, "WStr", name,
                    "Int", StrLen(name), "Ptr", size, "Int")
                    row.NameWidth := Min(138, Max(70, Ceil(NumGet(size, 0, "Int") / (scale * A_ScreenDPI / 96)) + 4))
            finally
            {
                if oldFont
                    DllCall("gdi32\SelectObject", "Ptr", dc, "Ptr", oldFont, "Ptr")
                DllCall("ReleaseDC", "Ptr", handle, "Ptr", dc)
            }
        }
        }
        row.NameScale := scale
        MoveMacroStyledIfChanged(row.Name, 551, row.Y, row.NameWidth, row.NameHeight)
        ; WM_SETREDRAW must only be used on a visible control.
        if !(row.Name.Text == name)
        {
            if row.Name.Visible
                SetPaintedLabelText(row.Name, name)
            else
                row.Name.Text := name
        }
    }
    x := 557 + row.NameWidth
    if editing
    {
        MacroNameEdit.GetPos(, &fieldY, &fieldWidth, &fieldHeight)
        if fieldY != BookS(row.Y) || fieldWidth != BookS(x - 557)
            || fieldHeight != BookS(row.NameHeight)
            MacroNameEdit.Move(BookS(551), BookS(row.Y), BookS(x - 557), BookS(row.NameHeight))
    }
    caption := editing ? "Save" : Chr(0x270E)
    if row.Rename.Text != caption
        SetPaintedLabelText(row.Rename, caption)
    row.Editing := editing
    LayoutMacroRowStatus(row, editing)
    if row.Name.Visible = editing
        row.Name.Visible := !editing
}

EditMacroBookRow(position, *)
{
    global MacroPage, MacroScrollOffset, MacroItems, MacroNameEdit
    plan := GetMacroPagePlan(MacroItems.Length, GetMacroVisibleSlots(), MacroScrollOffset)
    if position < 1 || position > plan.Count
        return
    index := plan.Offset + position
    item := MacroItems[index]
    if IsObject(MacroNameEdit.EditingItem) && MacroNameEdit.EditingItem = item
    {
        SaveMacroName()
        return
    }
    BeginInterfaceUpdate(MacroPage)
    try
    {
        MacroNameEdit.EditingItem := item
        MacroNameEdit.ErrorText := ""
        MacroNameEdit.Value := item.Name
        SelectMacroBookRow(position)
    }
    finally EndInterfaceUpdate()
    MacroNameEdit.Focus()
    DllCall("SendMessageW", "Ptr", MacroNameEdit.Hwnd, "UInt", 0x00B1, "Ptr", 0, "Ptr", -1)
}

SaveMacroName()
{
    previousCritical := Critical("On")
    try
        CommitMacroName()
    finally Critical(previousCritical)
}

CommitMacroName()
{
    global MacroList, MacroItems, MacroNameEdit
    item := MacroNameEdit.EditingItem
    if !IsObject(item)
        return
    index := 0
    for row, candidate in MacroItems
        if candidate = item
        {
            index := row
            break
        }
    if !index
        return FinishMacroNameEdit()

    name := Trim(MacroNameEdit.Value)
    if name = "" || StrLen(name) > 100
    {
        MacroNameEdit.ErrorText := "Enter a name (1–100 characters)."
        RefreshMacroButtons()
        MacroNameEdit.Focus()
        return
    }
    if name == item.Name
        return FinishMacroNameEdit()
    metadata := item.Folder "\.tes3np-package.ini"
    try
    {
        if !FileExist(metadata)
            throw Error("Macro package metadata is missing.")
        ; The INI reader strips the outer quotes, preserving quotes in the name.
        IniWrite(Chr(34) name Chr(34), metadata, "Macro", "Name")
    }
    catch
    {
        MacroNameEdit.ErrorText := "Could not save the macro name."
        RefreshMacroButtons()
        MacroNameEdit.Focus()
        return
    }
    item.Name := name
    MacroList.Modify(index, , name)
    FinishMacroNameEdit()
}

FinishMacroNameEdit()
{
    global MacroPage, MacroNameEdit
    BeginInterfaceUpdate(MacroPage)
    try
    {
        MacroNameEdit.EditingItem := 0
        MacroNameEdit.ErrorText := ""
        RefreshMacroButtons()
    }
    finally EndInterfaceUpdate()
}

MacroNameEditorFocused()
{
    global MacroPage, MacroNameEdit
    return IsObject(MacroNameEdit) && IsObject(MacroNameEdit.EditingItem)
        && IsObject(MacroPage) && MacroNameEdit.Visible && WinActive("ahk_id " MacroPage.Hwnd)
        && MacroNameEdit.Focused
}

; Restrict macro editing shortcuts to the focused name field.
#HotIf MacroNameEditorFocused()
Enter::SaveMacroName()
NumpadEnter::SaveMacroName()
Escape::FinishMacroNameEdit()
#HotIf

; Row actions update the existing ListView selection before delegating to
; the tested macro execution, stop and removal callbacks.
RunMacroBookRow(position, *)
{
    if SelectMacroBookRow(position)
        RunSelectedMacro()
}

StopMacroBookRow(position, *)
{
    if SelectMacroBookRow(position)
        StopSelectedMacro()
}

RemoveMacroBookRow(position, *)
{
    if SelectMacroBookRow(position)
        RemoveSelectedMacro()
}

; The offset is the first item of a non-overlapping page, never a sliding
; last viewport. Reuse the same fixed-capacity planner as Manage Characters.
GetMacroPagePlan(count, slots, offset)
{
    pages := PlanFixedBookPages(count, slots)
    pageNumber := Max(1, Min(pages.Length, Floor(Max(0, offset) / Max(1, slots)) + 1))
    current := pages[pageNumber]
    return {Number: pageNumber, Total: pages.Length, Offset: current.First - 1, Count: current.Count}
}

PositionMacroBookNavigation(page, plan, y, height)
{
    if !page.HasOwnProp("MacroPreviousPage")
        return false
    showNav := plan.Total > 1
    if showNav
    {
        MoveMacroStyledIfChanged(page.MacroPreviousPage, 525, y, 105, height)
        MoveMacroStyledIfChanged(page.MacroNextPage, 775, y, 105, height)
        MoveMacroTextIfChanged(page.MacroPageLabel, BookS(632), BookS(y), BookS(141), BookS(height))
        caption := "Page " plan.Number " of " plan.Total
        if page.MacroPageLabel.Text != caption
            page.MacroPageLabel.Text := caption
        if page.MacroPreviousPage.Enabled != (plan.Number > 1)
            page.MacroPreviousPage.Enabled := plan.Number > 1
        if page.MacroNextPage.Enabled != (plan.Number < plan.Total)
            page.MacroNextPage.Enabled := plan.Number < plan.Total
    }
    for control in [page.MacroPreviousPage, page.MacroPageLabel, page.MacroNextPage]
        if control.Visible != showNav
            control.Visible := showNav
    return showNav
}

ChangeMacroBookPage(delta, *)
{
    global MacroScrollOffset, MacroItems, MacroBookRows, LaunchSettingsHeading
    if !IsObject(MacroBookRows) || !MacroBookRows.Length || LaunchSettingsHeading.Visible
        return
    slots := GetMacroVisibleSlots()
    plan := GetMacroPagePlan(MacroItems.Length, slots, MacroScrollOffset)
    nextPage := Max(1, Min(plan.Total, plan.Number + delta))
    if nextPage = plan.Number
        return
    MacroScrollOffset := (nextPage - 1) * slots
    RefreshMacroButtons()
}

CloseMacroPage(*)
{
    SetTimer(RefreshMacroProcesses, 0)
}


LoadMacroPackages()
{
    global MacroRoot, MacroItems, MacroList, MacroScrollOffset
    MacroScrollOffset := 0
    DirCreate(MacroRoot)
    ; Transfer process handles when the character book is rebuilt.
    tracked := Map()
    tracked.CaseSense := "Off"
    for item in MacroItems
        if MacroProcessRunning(item)
            tracked[item.Folder] := item.ProcessHandle
        else if item.ProcessHandle
            DllCall("CloseHandle", "Ptr", item.ProcessHandle)
    MacroItems := []
    MacroList.Delete()
    Loop Files MacroRoot "\*", "D"
    {
        if IsMacroImportFolderName(A_LoopFileName) || InStr(A_LoopFileAttrib, "L")
            continue
        folder := A_LoopFileFullPath
        metadata := folder "\.tes3np-package.ini"
        if !FileExist(metadata)
            continue
        kind := IniRead(metadata, "Macro", "Kind", "Macro")
        entry := IniRead(metadata, "Macro", "Entry", "")
        target := kind = "App" ? IniRead(metadata, "Macro", "Target", "") : ""
        if kind != "App" && (kind != "Macro" || !ValidMacroEntry(folder, entry))
            continue
        name := IniRead(metadata, "Macro", "Name", "Macro")
        description := IniRead(metadata, "Macro", "Description", "")
        handle := tracked.Has(folder) ? tracked.Delete(folder) : 0
        item := {Folder: folder, Entry: entry, Name: name, Description: description,
            Kind: kind, Target: target, ProcessHandle: handle}
        MacroItems.Push(item)
        MacroList.Add(, name, kind = "App" && !ValidMacroApplication(item) ? "Missing"
            : (handle ? "Running" : "Ready"), MacroTypeLabel(item))
    }
    for folder, handle in tracked
        DllCall("CloseHandle", "Ptr", handle)
    ; Make the first installed tool immediately available for Run.
    if MacroItems.Length
        MacroList.Modify(1, "Select Focus")
    RefreshMacroButtons()
}

MacroTypeLabel(item)
{
    return item.Kind = "App" ? "App" : "Macro"
}

ValidMacroApplication(item)
{
    if item.Kind != "App"
        return true
    if item.Target = "" || !RegExMatch(item.Target, "i)\.exe$")
        return false
    attributes := FileExist(item.Target)
    return attributes != "" && !InStr(attributes, "D")
}

ValidMacroEntry(folder, entry)
{
    if entry = "" || !RegExMatch(entry, "i)\.ahk$") || RegExMatch(entry, "[:\r\n]") || SubStr(entry, 1, 1) = "\" || SubStr(entry, 1, 1) = "/"
        return false
    for part in StrSplit(StrReplace(entry, "/", "\"), "\")
        if part = ".."
            return false
    attributes := FileExist(folder "\" entry)
    return attributes != "" && !InStr(attributes, "D")
}

RefreshMacroButtons(*)
{
    global MacroList
    ; The selected macro and its row are driven by the existing invisible
    ; ListView, without restoring either crossed-out footer control.
    if !IsObject(MacroList)
        return
    RefreshMacroBookRows()
}

ImportMacroPackage(*)
{
    global MacroImport, MacroImportButton, MacroStatus, MacroRoot
    if IsObject(MacroImport)
        return
    archive := FileSelect(1, , "Upload Macro",
        "AutoHotkey scripts, ZIPs and applications (*.ahk;*.zip;*.exe)")
    if archive = "" || IsObject(MacroImport)
        return
    MacroStatus.Text := ""
    RefreshMacroButtons()
    if RegExMatch(archive, "i)\.ahk$")
    {
        ImportMacroScript(archive)
        return
    }
    if RegExMatch(archive, "i)\.exe$")
    {
        ImportMacroApplication(archive)
        return
    }
    if !RegExMatch(archive, "i)\.zip$")
    {
        MsgBox("Choose an .ahk script, ZIP containing scripts, or installed .exe.", "Upload Macro")
        return
    }
    try
    {
        signature := FileOpen(archive, "r")
        try magic := signature.Length >= 4 ? signature.ReadUInt() : 0
        finally signature.Close()
    }
    catch
    {
        MsgBox("The archive could not be read. Check that it is available on this computer.", "Import Macro")
        return
    }
    if magic != 0x04034B50 && magic != 0x06054B50
    {
        MsgBox("This file is not a ZIP archive. Create a ZIP containing your .ahk script.", "Import Macro")
        return
    }
    staging := ""
    try
    {
        staging := MacroRoot "\import-" FormatTime(, "yyyyMMddHHmmss") "-" NewLauncherFileId()
        DirCreate(staging)
        helper := A_ScriptDir "\scripts\import-macro.ps1"
        powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
        Run('"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' helper '" -Archive "' archive '" -Destination "' staging '"', , "Hide", &pid)
    }
    catch
    {
        if staging != ""
            DeleteLauncherStagingTree(staging)
        MsgBox("Could not start ZIP import. Windows PowerShell is required.", "Import Macro")
        return
    }
    handle := DllCall("OpenProcess", "UInt", 0x100001, "Int", 0, "UInt", pid, "Ptr")
    MacroImport := {PID: pid, ProcessHandle: handle, Folder: staging, Archive: archive, Started: A_TickCount}
    SetTimer(CheckMacroImport, 200)
    try
    {
        MacroImportButton.Enabled := false
        MacroStatus.Text := "Extracting and checking macro package..."
        RefreshMacroButtons()
    }
}

StopMacroImportWorker(pending)
{
    handle := pending.ProcessHandle
    if !handle
        return !ProcessExist(pending.PID)
    try
    {
        if MacroProcessRunning(pending)
            DllCall("TerminateProcess", "Ptr", handle, "UInt", 1)
        return DllCall("WaitForSingleObject", "Ptr", handle, "UInt", 1000, "UInt") = 0
    }
    finally
    {
        DllCall("CloseHandle", "Ptr", handle)
        pending.ProcessHandle := 0
    }
}

CheckMacroImport()
{
    global MacroImport, MacroImportButton, MacroStatus
    if !IsObject(MacroImport)
        return
    pending := MacroImport
    timedOut := pending.ProcessHandle ? MacroProcessRunning(pending) : ProcessExist(pending.PID)
    if timedOut && A_TickCount - pending.Started < 120000
        return
    SetTimer(CheckMacroImport, 0)
    workerClosed := false
    try
    {
        workerClosed := StopMacroImportWorker(pending)
        if timedOut
            throw Error("ZIP extraction timed out after 120 seconds.")
        if !workerClosed
            throw Error("Could not confirm the ZIP extractor closed.")
        if !FileExist(pending.Folder "\.import-success") || FileExist(pending.Folder "\.import-error")
        {
            detail := FileExist(pending.Folder "\.import-error") ? SubStr(FileRead(pending.Folder "\.import-error", "UTF-8"), 1, 200) : "ZIP extraction helper did not complete. Check that scripts/import-macro.ps1 is present and PowerShell can run."
            throw Error(detail)
        }
        FinishMacroImport(pending)
    }
    catch Error as err
    {
        if workerClosed
            DeleteLauncherStagingTree(pending.Folder)
        detail := SanitizeDiagnosticText(err.Message)
        if detail = ""
            detail := "The macro ZIP could not be imported."
        MacroStatus.Text := "Import failed: " detail
        MsgBox("The ZIP could not be imported.`n`n" detail, "Import Macro")
    }
    finally
    {
        MacroImport := 0
        MacroImportButton.Enabled := true
        RefreshMacroButtons()
    }
}

FinishMacroImport(pending)
{
    global MacroRoot
    scripts := []
    Loop Files pending.Folder "\*.ahk", "R"
        scripts.Push(SubStr(A_LoopFileFullPath, StrLen(pending.Folder) + 2))
    if !scripts.Length
        throw Error("No AutoHotkey script")
    entry := "", manifest := pending.Folder "\macro.ini"
    if FileExist(manifest)
        entry := IniRead(manifest, "Macro", "Entry", "")
    if entry != "" && !ValidMacroEntry(pending.Folder, entry)
        throw Error("Invalid entry script")
    if entry = ""
        entry := scripts.Length = 1 ? scripts[1] : ChooseMacroScript(scripts)
    if entry = ""
    {
        DeleteLauncherStagingTree(pending.Folder)
        return
    }
    SplitPath(pending.Archive, , , , &defaultName)
    name := IniRead(manifest, "Macro", "Name", defaultName)
    description := IniRead(manifest, "Macro", "Description", "")
    name := SubStr(Trim(name), 1, 100)
    if name = ""
        name := "Macro"
    metadata := pending.Folder "\.tes3np-package.ini"
    IniWrite(name, metadata, "Macro", "Name")
    IniWrite(SubStr(description, 1, 500), metadata, "Macro", "Description")
    IniWrite(entry, metadata, "Macro", "Entry")
    if FileExist(pending.Folder "\.import-success")
        FileDelete(pending.Folder "\.import-success")
    ; Immutable unique install folders allow ZIPs with the same display name.
    destination := MacroRoot "\package-" FormatTime(, "yyyyMMddHHmmss") "-" NewLauncherFileId()
    DirMove(pending.Folder, destination)
    AddImportedMacro(destination, name, description, entry)
}

AddImportedMacro(folder, name, description, entry, kind := "Macro", target := "")
{
    global MacroPage, MacroItems, MacroList, MacroScrollOffset
    try
    {
        try
        {
            BeginInterfaceUpdate(MacroPage, "Updating macro list...")
            row := MacroList.Add(, name, "Ready", kind = "App" ? "App" : "Macro")
            MacroItems.Push({Folder: folder, Entry: entry, Name: name, Description: description,
                Kind: kind, Target: target, ProcessHandle: 0})
            MacroList.Modify(row, "Select Focus")
            MacroScrollOffset := Max(0, row - 1)
            RefreshMacroButtons()
        }
        finally EndInterfaceUpdate()
    }
    catch
    {
        try LoadMacroPackages()
        LogLauncherEvent("MACRO | Package saved. Installed macro list refresh needed recovery.")
    }
}

; An installed EXE is linked by path. Copying only its EXE would break apps
; with side-by-side resources and would make launcher removal destructive.
ImportMacroApplication(source)
{
    global MacroRoot
    if !ValidMacroApplication({Kind: "App", Target: source})
        return
    SplitPath(source, &filename, , , &name)
    name := SubStr(Trim(name), 1, 100)
    if name = ""
        name := filename
    staging := ""
    try
    {
        id := FormatTime(, "yyyyMMddHHmmss") "-" NewLauncherFileId()
        staging := MacroRoot "\import-" id
        folder := MacroRoot "\app-" id
        DirCreate(staging)
        manifest := staging "\.tes3np-package.ini"
        IniWrite(name, manifest, "Macro", "Name")
        IniWrite("App", manifest, "Macro", "Kind")
        IniWrite(filename, manifest, "Macro", "Entry")
        IniWrite(source, manifest, "Macro", "Target")
        IniWrite("Linked local application", manifest, "Macro", "Description")
        DirMove(staging, folder)
    }
    catch
    {
        if staging != ""
            DeleteLauncherStagingTree(staging)
        MsgBox("Could not register that application.", "Upload Macro")
        return
    }
    AddImportedMacro(folder, name, "Linked local application", filename, "App", source)
}

ChooseMacroScript(scripts)
{
    global MacroPage
    result := {Entry: ""}
    chooser := Gui("+Owner" MacroPage.Hwnd " -MinimizeBox -MaximizeBox", "Choose macro script")
    chooser.BackColor := "E2CEA2"
    SetAccessibleTextFont(chooser, "s10 c382314", LauncherThemeFont())
    chooser.Add("Text", "x20 y20 w460 h40", "This package has more than one script. Choose the main .ahk file to run.")
    list := chooser.Add("DropDownList", "x20 y70 w460 Choose1", scripts)
    button := chooser.Add("Button", "x260 y115 w100 h30 Default", "Import")
    cancel := chooser.Add("Button", "x380 y115 w100 h30", "Cancel")
    button.OnEvent("Click", AcceptMacroScript.Bind(chooser, list, scripts, result))
    cancel.OnEvent("Click", (*) => chooser.Hide())
    chooser.OnEvent("Close", (*) => chooser.Hide())
    chooser.OnEvent("Escape", (*) => chooser.Hide())
    MacroPage.Opt("+Disabled")
    try
    {
        chooserScale := GetOwnedMenuScale()
        ScaleOwnedMenuContent(chooser, chooserScale)
        chooser.Show("Hide w" Round(500 * chooserScale) " h" Round(165 * chooserScale))
        PositionOwnedMenuAtParent(chooser, MacroPage)
        chooser.Show()
        WinWaitClose("ahk_id " chooser.Hwnd)
    }
    finally
    {
        MacroPage.Opt("-Disabled")
        DestroyScaledMenu(chooser)
    }
    return result.Entry
}

AcceptMacroScript(chooser, list, scripts, result, *)
{
    result.Entry := scripts[list.Value]
    chooser.Hide()
}

RunSelectedMacro(*)
{
    global MacroItems, MacroList, MacroImport
    row := MacroList.GetNext()
    if !row || row > MacroItems.Length || IsObject(MacroImport)
        return
    macro := MacroItems[row]
    if MacroProcessRunning(macro)
        return
    if !ValidMacroApplication(macro)
        || (macro.Kind != "App" && !ValidMacroEntry(macro.Folder, macro.Entry))
    {
        RefreshMacroButtons()
        return
    }
    if MsgBox("Run " macro.Name "? This tool executes code on your computer. Only run files you trust.", "Run macro / app", 0x124) != "Yes"
        return
    try
    {
        if macro.Kind = "App"
        {
            if !ValidMacroApplication(macro)
                throw Error("App executable is missing")
            SplitPath(macro.Target, , &directory)
            Run('"' macro.Target '"', directory, , &pid)
        }
        else
        {
            interpreter := A_IsCompiled ? A_ScriptDir "\runtime\AutoHotkey64.exe" : A_AhkPath
            if !FileExist(interpreter)
                throw Error("Bundled AutoHotkey macro runtime missing")
            entry := macro.Folder "\" macro.Entry
            if !ValidMacroEntry(macro.Folder, macro.Entry)
                throw Error("Script no longer exists")
            SplitPath(entry, , &directory)
            ; Macro-specific shortcuts and settings belong to the script.
            Run('"' interpreter '" "' entry '"', directory, , &pid)
        }
        if macro.ProcessHandle
            DllCall("CloseHandle", "Ptr", macro.ProcessHandle)
        ; SYNCHRONIZE and PROCESS_TERMINATE bind Stop to this exact process.
        macro.ProcessHandle := DllCall("OpenProcess", "UInt", 0x100001, "Int", 0, "UInt", pid, "Ptr")
        if !macro.ProcessHandle
        {
            if ProcessExist(pid)
            {
                macro.LastError := "Process tracking unavailable"
                RefreshMacroButtons()
                return
            }
            macro.LastError := ""
            RefreshMacroButtons()
            return
        }
        macro.LastError := ""
        MacroList.Modify(row, , macro.Name, "Running", MacroTypeLabel(macro))
        RefreshMacroButtons()
    }
    catch Error as err
    {
        ; A missing package runtime is a launcher installation problem, not
        ; a request for an arbitrary interpreter selected by the user.
        missingRuntime := InStr(err.Message, "Bundled AutoHotkey macro runtime missing") > 0
        macro.LastError := missingRuntime ? "Runtime missing" : "Launch failed"
        RefreshMacroButtons()
        MsgBox(missingRuntime
            ? "TES3NP's bundled AutoHotkey runtime is missing.`n`nRebuild or re-extract the complete TES3NP Windows package, keeping the runtime folder beside tes3np.exe."
            : "Could not run this tool. Check its installation.",
            "Run macro / app", "Icon!")
    }
}


StopSelectedMacro(*)
{
    global MacroItems, MacroList
    row := MacroList.GetNext()
    if !row || row > MacroItems.Length
        return
    macro := MacroItems[row]
    if MacroProcessRunning(macro)
    {
        if !DllCall("TerminateProcess", "Ptr", macro.ProcessHandle, "UInt", 0)
        {
            macro.LastError := "Could not stop"
            RefreshMacroButtons()
            return
        }
    }
    macro.LastError := ""
    RefreshMacroProcesses()
}

RefreshMacroProcesses()
{
    global MacroItems, MacroList
    if !IsObject(MacroList)
        return
    for row, macro in MacroItems
        if macro.ProcessHandle && !MacroProcessRunning(macro)
        {
            DllCall("CloseHandle", "Ptr", macro.ProcessHandle)
            macro.ProcessHandle := 0
            MacroList.Modify(row, , macro.Name,
                ValidMacroApplication(macro) ? "Ready" : "Missing", MacroTypeLabel(macro))
        }
    RefreshMacroButtons()
}

RemoveSelectedMacro(*)
{
    global MacroPage, MacroItems, MacroList, MacroScrollOffset, MacroNameEdit
    row := MacroList.GetNext()
    if !row || row > MacroItems.Length
        return
    macro := MacroItems[row]
    if MacroProcessRunning(macro)
        return
    if MsgBox("Remove " macro.Name " from Installed Macros? This does not uninstall linked applications.", "Remove macro / app", 0x124) != "Yes"
        return
    try
        DirDelete(macro.Folder, true)
    catch
    {
        MsgBox("Could not remove this macro package. Check that its files are not in use.", "Remove macro")
        return
    }
    BeginInterfaceUpdate(MacroPage, "Updating macro list...")
    try
    {
        if IsObject(MacroNameEdit.EditingItem) && MacroNameEdit.EditingItem = macro
            MacroNameEdit.EditingItem := 0
        if macro.ProcessHandle
            DllCall("CloseHandle", "Ptr", macro.ProcessHandle)
        MacroItems.RemoveAt(row)
        MacroList.Delete(row)
        if MacroItems.Length
            MacroList.Modify(Min(row, MacroItems.Length), "Select Focus")
        MacroScrollOffset := GetMacroPagePlan(MacroItems.Length, GetMacroVisibleSlots(), MacroScrollOffset).Offset
        RefreshMacroButtons()
    }
    finally EndInterfaceUpdate()
}

CleanupMacros()
{
    global MacroImport, MacroItems
    SetTimer(CheckMacroImport, 0)
    SetTimer(RefreshMacroProcesses, 0)
    if IsObject(MacroImport)
    {
        try
            if StopMacroImportWorker(MacroImport)
                DeleteLauncherStagingTree(MacroImport.Folder)
        MacroImport := 0
    }
    ; Macro scripts remain launcher-owned; linked apps should remain running
    ; if the user closes TES3NP instead of being forcibly terminated.
    for macro in MacroItems
    {
        if macro.Kind != "App" && MacroProcessRunning(macro)
            DllCall("TerminateProcess", "Ptr", macro.ProcessHandle, "UInt", 0)
        if macro.ProcessHandle
        {
            DllCall("CloseHandle", "Ptr", macro.ProcessHandle)
            macro.ProcessHandle := 0
        }
    }
}

; Single scripts need no archive or manifest. Supporting files belong in a ZIP.
ImportMacroScript(source)
{
    global MacroRoot, MacroStatus
    staging := ""
    try
    {
        staging := MacroRoot "\import-" FormatTime(, "yyyyMMddHHmmss") "-" NewLauncherFileId()
        DirCreate(staging)
        SplitPath(source, &filename)
        FileCopy(source, staging "\" filename)
        FinishMacroImport({Folder: staging, Archive: source})
    }
    catch
    {
        if staging != ""
            DeleteLauncherStagingTree(staging)
        MacroStatus.Text := "The script could not be imported."
        RefreshMacroButtons()
        MsgBox("Could not copy this AutoHotkey script. Check that the file is readable.", "Import Macro")
    }
}
