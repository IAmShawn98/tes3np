; Character book, profile editor and favorite-selection interactions.

; Character Book is the launcher-owned second page, not an independent
; unscaled 960x650 window. Dynamic editor/macro controls still use their
; approved 100%-layout coordinates; convert them at the native boundary.
GetCharacterBookScale()
{
    global CharacterPage
    return IsObject(CharacterPage) && CharacterPage.HasOwnProp("OwnedContentScale")
        ? CharacterPage.OwnedContentScale : 1.0
}

BookS(value)
{
    return Round(value * GetCharacterBookScale())
}

; Reuse the actual cached book and its editor/macro state. The common native
; scaling routine moves both visible control rectangles and matching fonts;
; reload the one parchment bitmap to fit the new Picture rectangle.
ApplyCharacterBookScale(scale)
{
    global CharacterPage, ButtonPaint
    if !IsObject(CharacterPage)
        return
    previous := GetCharacterBookScale()
    if Abs(scale - previous) < 0.001
        return
    BumpBookFaceArtworkRevision(CharacterPage)
    try
    {
        ScaleOwnedMenuContent(CharacterPage, scale)
        if CharacterPage.HasOwnProp("BookBackground")
        {
            if CharacterPage.HasOwnProp("BookExtra") && CharacterPage.BookExtra
                ApplyExtendedBookArtwork(CharacterPage, CharacterPage.BookExtra)
            else
            {
                if !TryLoadBookPicture(CharacterPage, ButtonPaint.Book)
                    CharacterPage.BookBackground.Value := A_ScriptDir "\assets\backgrounds\character-book.png"
            }
        }
    }
    finally BumpBookFaceArtworkRevision(CharacterPage)
}

; Measure the actual requested button font, not the renderer's fitted
; fallback. Keep every original rectangle as a minimum in non-Normal modes.
BookActionMetrics(control, caption, width, height)
{
    global AccessibilityTextSize
    if AccessibilityTextSize = "Normal" || !IsObject(control)
        return {Width: width, Height: height}
    extent := MeasureAccessibleSingleLineText(control, caption)
    scale := GetCharacterBookScale()
    return {Width: Max(width, Ceil((extent.Width + BookS(8)) / scale)),
        Height: Max(height, Ceil((extent.Height + Max(2, BookS(4))) / scale))}
}

GetBookFooterMetrics(page)
{
    global Profiles, AddCharacterButton, WipeCharacterButton, DataTransferButton
    close := BookActionMetrics(page.HasOwnProp("BookCloseButton") ? page.BookCloseButton : 0, "Close", 90, 30)
    add := {Width: 370, Height: 30}, wipe := add, transfer := add
    if Profiles.Length
    {
        add := BookActionMetrics(AddCharacterButton, "Add character", 370, 30)
        wipe := BookActionMetrics(WipeCharacterButton, "Reset Character List", 370, 30)
        transfer := BookActionMetrics(DataTransferButton, "Export Character List", 370, 30)
    }
    return {CloseWidth: close.Width, TransferHeight: transfer.Height,
        AddHeight: add.Height, FooterHeight: Max(close.Height, wipe.Height),
        Fits: add.Width <= 370 && wipe.Width <= 370 && transfer.Width <= 370 && close.Width <= 370}
}

; Reserve the complete left action stack in both footer placement and page planning.
PlanCharacterBookActionStack(footerY, footer)
{
    transferY := footerY - 5 - footer.TransferHeight
    return {AddY: transferY - 5 - footer.AddHeight, TransferY: transferY, ResetY: footerY}
}

MoveMeasuredBookAction(control, x, y, width, height)
{
    global ButtonFaces, AccessibilityTextSize
    if ButtonFaces.Has(control.Hwnd)
        ButtonFaces[control.Hwnd].NoAccessibleDownfit := AccessibilityTextSize != "Normal"
    MoveMacroStyledIfChanged(control, x, y, width, height)
}

; Each column requests only the extra space it actually needs. The common
; parent takes the larger request, retains the approved footer gaps, and
; never silently reduces text or launcher scale to fit the monitor.
SetCharacterBookLayoutExtra(side, required)
{
    global CharacterPage, LauncherGui, Profiles, AddCharacterButton
    global WipeCharacterButton, DataTransferButton
    if !IsObject(CharacterPage) || !CharacterPage.HasOwnProp("BookBackground")
        return required = 0
    page := CharacterPage
    if required > 0
        page.BookExpansionFailure := ""
    ; The bitmap generator already rounds its native scanline count.
    ; Do not inflate logical window height: an otherwise fitting layout
    ; must not be rejected solely by an arbitrary eight-pixel increment.
    required := Max(0, Ceil(required))
    leftExtra := page.HasOwnProp("BookCharacterExtra") ? page.BookCharacterExtra : 0
    rightExtra := page.HasOwnProp("BookMacroExtra") ? page.BookMacroExtra : 0
    if side = "Characters"
        leftExtra := required
    else
        rightExtra := required
    footer := GetBookFooterMetrics(page)
    if !footer.Fits
    {
        page.BookExpansionFailure := "Measured footer captions exceed the available width."
        return false
    }
    ; Reserve footer growth separately from the content budget.
    extra := Max(leftExtra, rightExtra) + footer.FooterHeight - 30
    oldExtra := page.HasOwnProp("BookExtra") ? page.BookExtra : 0
    if extra
    {
        if !IsObject(LauncherGui)
            return false
        ; The owner may be hidden or have redraw suppressed during staging.
        ; Use its actual HWND rectangle, just like PositionOwnedMenuAtParent.
        ownerRect := Buffer(16, 0)
        if !DllCall("GetWindowRect", "Ptr", LauncherGui.Hwnd, "Ptr", ownerRect)
            return false
        monitor := MonitorFromPoint((NumGet(ownerRect, 0, "Int") + NumGet(ownerRect, 8, "Int")) // 2,
            (NumGet(ownerRect, 4, "Int") + NumGet(ownerRect, 12, "Int")) // 2)
        MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
        dpi := A_ScreenDPI / 96
        availableWidth := right - left - 16, availableHeight := bottom - top - 16
        ; Disposable native layout fixtures can supply a fixed test work area.
        ; Production Book construction never sets this property; real monitor
        ; rejection is exercised separately with no override.
        if page.HasOwnProp("BookLayoutFixtureWorkArea") && !DllCall("IsWindowVisible", "Ptr", page.Hwnd)
        {
            availableWidth := page.BookLayoutFixtureWorkArea.Width - 16
            availableHeight := page.BookLayoutFixtureWorkArea.Height - 16
        }
        if Round(BookS(960) * dpi) > availableWidth
            || Round(BookS(650 + extra) * dpi) > availableHeight
        {
            page.BookExpansionFailure := Format("Required {}x{} pixels; available {}x{} at scale {}",
                BookS(960) * dpi, BookS(650 + extra) * dpi,
                availableWidth, availableHeight, GetCharacterBookScale())
            return false
        }
    }
    if extra != oldExtra
    {
        try ApplyExtendedBookArtwork(page, extra)
        catch Error as err
        {
            page.BookExpansionFailure := "Artwork extension failed: " err.Message
            return false
        }
        ; WM_SETREDRAW(FALSE) removes WS_VISIBLE during the existing
        ; character refresh transaction. Resize even then, otherwise the
        ; larger Picture is clipped by the stale 650px parent after reveal.
        ; SetWindowPos neither activates nor reveals a hidden/cached page.
        DllCall("SetWindowPos", "Ptr", page.Hwnd, "Ptr", 0,
            "Int", 0, "Int", 0, "Int", Round(BookS(960) * A_ScreenDPI / 96),
            "Int", Round(BookS(650 + extra) * A_ScreenDPI / 96), "UInt", 0x16)
        PositionOwnedMenuAtParent(page, LauncherGui)
    }
    page.BookCharacterExtra := leftExtra
    page.BookMacroExtra := rightExtra
    ; RefreshProfiles can restore its normal positions before this call.
    ; Reconcile all shared footer controls even when the height is unchanged.
    footerY := 605 + extra - footer.FooterHeight
    if IsObject(page.BookCloseButton)
        MoveMeasuredBookAction(page.BookCloseButton, 515, footerY,
            footer.CloseWidth, footer.FooterHeight)
    if Profiles.Length
    {
        stack := PlanCharacterBookActionStack(footerY, footer)
        MoveMeasuredBookAction(AddCharacterButton, 70, stack.AddY, 370, footer.AddHeight)
        MoveMeasuredBookAction(DataTransferButton, 70, stack.TransferY, 370, footer.TransferHeight)
        MoveMeasuredBookAction(WipeCharacterButton, 70, stack.ResetY, 370, footer.FooterHeight)
    }
    return true
}

GetCharacterBookExtra()
{
    global CharacterPage
    return IsObject(CharacterPage) && CharacterPage.HasOwnProp("BookExtra")
        ? CharacterPage.BookExtra : 0
}

; Measure headings before positioning their dependent introductory copy.
; Normal retains the exact original heading height and copy anchor.
BookHeadingCopyY(heading, x, width, originalHeight, originalCopyY)
{
    global AccessibilityTextSize
    height := originalHeight
    if AccessibilityTextSize != "Normal"
        height := Max(originalHeight, Ceil((MeasureAccessibleWrappedText(
            heading, heading.Text, BookS(width - 4)) + BookS(4)) / GetCharacterBookScale()))
    MoveMacroTextIfChanged(heading, BookS(x), BookS(45), BookS(width), BookS(height))
    return originalCopyY + height - originalHeight
}

CharacterBookDescriptionY()
{
    global CharacterPage
    if !IsObject(CharacterPage) || !CharacterPage.HasOwnProp("BookCharacterHeading")
        return 80
    return BookHeadingCopyY(CharacterPage.BookCharacterHeading, 70, 380, 30, 80)
}

OpenCharacterPage(*)
{
    global CharacterPage, LauncherGui, CharacterHeading, LaunchSettingsHeading, DataTransferButton, WipeCharacterButton, CharacterDescription, AddCharacterButton, CharacterRows, BookDragStrip, CharacterLimitNotice, ButtonFaces, EditorControls, V016CharacterLayoutApplied
    global AccessibilityTextSize, Profiles
    if IsObject(CharacterPage) && DllCall("IsWindow", "Ptr", CharacterPage.Hwnd)
    {
        ; Cached book is already fully painted and layered with its correct
        ; magenta transparency. Reapplying alpha=0 on every visit caused a
        ; visible blank-to-opaque flash before RevealWindowDisplay().
        ; The cached book already contains all the correct controls, but
        ; the first re-Show can publish its empty background before Windows
        ; repaints child HWNDs. Keep the existing bitmap/controls intact and
        ; reveal only after the entire cached page has been repainted.
        staged := SetPageCompositorCloak(CharacterPage, true)
        try
        {
            ; A cached book can predate the new Interface Text preference.
            cachedTextChanged := CharacterPage.HasOwnProp("InterfaceFontMode")
                && CharacterPage.InterfaceFontMode != AccessibilityTextSize
            RefreshCachedBookTextPreference(CharacterPage)
            bookScale := GetOwnedMenuScale()
            scaleChanged := Abs(GetCharacterBookScale() - bookScale) >= 0.001
            ApplyCharacterBookScale(bookScale)
            ; Both empty and populated Character Book rows depend on the
            ; selected native font. Recompute only after a cached text-choice
            ; change; ordinary reopen keeps its previously accepted fast path.
            if cachedTextChanged || scaleChanged
            {
                RefreshProfiles()
                RefreshMacroProcesses()
            }
            CharacterPage.Show("Hide w" Round(960 * bookScale)
                " h" Round((650 + GetCharacterBookExtra()) * bookScale))
            PositionOwnedMenuAtParent(CharacterPage, LauncherGui)
            CharacterPage.Show()
            if staged
                RevealPaintedPage(CharacterPage)
        }
        finally
        {
            if staged
                SetPageCompositorCloak(CharacterPage, false)
        }
        RefreshMacroProcesses()
        if MacroItems.Length
            SetTimer(RefreshMacroProcesses, 1000)
        return
    }
    SetInterfaceLoadingText("Loading saved characters...")
    LoadProfiles()
    SetInterfaceLoadingText("Building character menu...")
    ; A rebuilt book must start with fresh control collections. The previous
    ; GUI's controls are destroyed with the window, but AHK arrays still retain
    ; those object references unless explicitly cleared.
    CharacterRows := []
    global MacroPage, MacroList, MacroBookControls
    MacroPage := 0
    MacroList := 0
    MacroBookControls := []
    EditorControls := []
    ; A rebuilt character book needs its canonical button layout reapplied.
    V016CharacterLayoutApplied := false
    CharacterPage := CreateAccessibleLayoutGui("-Caption -Border +Owner" LauncherGui.Hwnd, "tes3np — Characters")
    CharacterPage.BackColor := "FF00FF"
    CharacterPage.BookExtra := 0
    CharacterPage.BookFaceArtworkRevision := 0
    CharacterPage.BookCharacterExtra := 0
    CharacterPage.BookMacroExtra := 0
    CharacterPage.BookBackground := CharacterPage.Add("Picture", "x0 y0 w960 h650",
        A_ScriptDir "\assets\backgrounds\character-book.png")
    BookDragStrip := CharacterPage.Add("Text", "x45 y25 w800 h32 BackgroundTrans +0x100")
    ; Use the same native Morrowind-style face as Launcher Settings. Keep
    ; interactive buttons in their existing button font for readability.
    SetAccessibleTextFont(CharacterPage, "s19 Norm c241408", LauncherMorrowindFont)
    CharacterHeading := CharacterPage.Add("Text", "x70 y45 w380 h30 Center BackgroundTrans", "Manage Characters")
    CharacterPage.BookCharacterHeading := CharacterHeading
    ; Retain a hidden heading for the character editor.
    LaunchSettingsHeading := CharacterPage.Add("Text", "x525 y45 w360 h30 Center BackgroundTrans Hidden", "")
    SetAccessibleTextFont(CharacterPage, "s12 Norm c241408", LauncherMorrowindFont)
    AddCharacterButton := AddStyledButton(CharacterPage, 70, 164, 370, 30, "Add character", (*) => EditProfile(0))
    ; The approved copy fits in a compact description block. Do not leave
    ; a full extra paragraph of empty control space above the first row.
    SetAccessibleTextFont(CharacterPage, "s11 Norm c241408", LauncherMorrowindFont)
    CharacterDescription := CharacterPage.Add("Text", "x70 y80 w390 h81 BackgroundTrans", "")
    Loop 10
    {
        SetAccessibleTextFont(CharacterPage, "s12 Norm c241408", LauncherMorrowindFont)
        index := A_Index
        ; Start just below the instructions; retain all ten 24px-spaced
        ; rows and their aligned painted buttons and hit targets.
        y := 164 + (index - 1) * 24
        SetInterfaceLoadingText("Loading character checkbox " index "...")
        tick := AddBookTick(CharacterPage, 70, y + 2, ChooseProfile.Bind(index))
        SetInterfaceLoadingText("Loading character name " index "...")
        name := AddBookLabel(CharacterPage, 95, y, 140, 23, "")
        SetInterfaceLoadingText("Loading Play button " index "...")
        play := AddStyledButton(CharacterPage, 240, y, 55, 22, "Play", PlayVisibleProfile.Bind(index))
        SetInterfaceLoadingText("Loading Edit button " index "...")
        edit := AddStyledButton(CharacterPage, 300, y, 60, 22, "Edit", EditVisibleProfile.Bind(index))
        SetInterfaceLoadingText("Loading Remove button " index "...")
        remove := AddStyledButton(CharacterPage, 365, y, 75, 22, "Remove", RemoveVisibleProfile.Bind(index))
        CharacterRows.Push({Tick: tick, Name: name, Play: play, Edit: edit, Remove: remove})
    }
    SetAccessibleTextFont(CharacterPage, "s12 Norm c241408", LauncherMorrowindFont)
    CharacterLimitNotice := AddBookLabel(CharacterPage, 70, 429, 370, 25, "* You have reached the server character limit.")
    ButtonFaces[CharacterLimitNotice.Hwnd].TextColor := 0x0000FF
    CharacterLimitNotice.Visible := false
    CharacterPage.BookPreviousPage := AddStyledButton(CharacterPage, 70, 490, 112, 30,
        "Previous", ChangeCharacterBookPage.Bind(-1))
    CharacterPage.BookNextPage := AddStyledButton(CharacterPage, 328, 490, 112, 30,
        "Next", ChangeCharacterBookPage.Bind(1))
    SetAccessibleTextFont(CharacterPage, "s12 Norm c241408", LauncherMorrowindFont)
    CharacterPage.BookPageLabel := CharacterPage.Add("Text", "x184 y490 w142 h30 Center BackgroundTrans Hidden", "")
    CharacterPage.BookPreviousPage.Visible := false
    CharacterPage.BookNextPage.Visible := false
    SetAccessibleTextFont(CharacterPage, "s12 Norm c241408", LauncherMorrowindFont)
    WipeCharacterButton := AddStyledButton(CharacterPage, 70, 577, 370, 25, "Reset Character List", WipeCharacterData)
    CharacterPage.BookCloseButton := AddStyledButton(CharacterPage, 515, 575, 90, 30, "Close", CloseCharacterPage)
    DataTransferButton := AddStyledButton(CharacterPage, 70, 540, 370, 30, "Export Character List", TransferLauncherData)
    CharacterPage.OnEvent("Close", CloseCharacterPage)
    CharacterPage.OnEvent("Escape", CloseCharacterPage)
    SetInterfaceLoadingText("Loading character editor... ")
    CreateProfileEditor()
    ; HideProfileEditor restores the macro panel: create that panel first.
    ; Otherwise MacroList is still its integer zero placeholder.
    BuildMacroBookPanel()
    HideProfileEditor()
    ; Apply the canonical Character Book positions once after controls exist;
    ; this preserves the compact two-button action stack.
    ApplyV016CharacterLayout()
    RefreshProfiles()
    CharacterPage.InterfaceFontMode := AccessibilityTextSize
    PrepareWindowDisplay(CharacterPage)
    staged := SetPageCompositorCloak(CharacterPage, true)
    try
    {
        bookScale := GetOwnedMenuScale()
        scaleChanged := Abs(GetCharacterBookScale() - bookScale) >= 0.001
        ApplyCharacterBookScale(bookScale)
        if scaleChanged
        {
            RefreshProfiles()
            RefreshMacroProcesses()
        }
        CharacterPage.Show("Hide w" Round(960 * bookScale)
            " h" Round((650 + GetCharacterBookExtra()) * bookScale))
        ; The initial 100% path does not trigger ApplyCharacterBookScale.
        ; Prepare the native bitmap before the first reveal in that case too.
        if !scaleChanged && !GetCharacterBookExtra()
        {
            global ButtonPaint
            if TryLoadBookPicture(CharacterPage, ButtonPaint.Book)
                BumpBookFaceArtworkRevision(CharacterPage)
        }
        PositionOwnedMenuAtParent(CharacterPage, LauncherGui)
        CharacterPage.Show()
        ; Preserve the original magenta color key and custom button faces.
        RevealWindowDisplay(CharacterPage, true, !staged)
        if staged
            RevealPaintedPage(CharacterPage)
    }
    finally
    {
        if staged
            SetPageCompositorCloak(CharacterPage, false)
    }
    if MacroItems.Length
        SetTimer(RefreshMacroProcesses, 1000)
}

RefreshProfiles()
{
    global CharacterRows, Profiles, SelectedProfile, CharacterListPage, ButtonFaces, DataTransferButton, WipeCharacterButton, CharacterDescription, AddCharacterButton, MaxCharacters, CharacterLimitNotice
    BeginInterfaceUpdate(0, "Refreshing character list...")
    try
    {
        descriptionText := "This is a list of all your characters. You can add, edit, or delete your character details at any time. Please note that adding, editing, and deleting characters on this list does not impact them in-game!"
        CharacterDescription.Text := descriptionText
        CharacterDescription.Visible := true
        ; Start every refresh from immutable approved Normal geometry.
        ; When the list is empty, there are no rows to collide with: measure
        ; the COMPLETE instructions and push Add/Import together only if the
        ; book's unchanged parchment/footers can contain them. The populated
        ; ten-row state needs its own all-control transaction.
        actionY := Profiles.Length ? 505 : 164
        addMetrics := BookActionMetrics(AddCharacterButton, "Add character", 370, 30)
        importMetrics := BookActionMetrics(DataTransferButton, "Import Data", 370, 30)
        transferMetrics := Profiles.Length
            ? BookActionMetrics(DataTransferButton, "Export Character List", 370, 30) : importMetrics
        if Profiles.Length
            actionY := PlanCharacterBookActionStack(575, GetBookFooterMetrics(CharacterPage)).AddY
        copyY := CharacterBookDescriptionY()
        CharacterDescription.Move(BookS(70), BookS(copyY), BookS(390), BookS(81))
        if !Profiles.Length
        {
            captionHeight := Max(BookS(81),
                MeasureAccessibleWrappedText(CharacterDescription, descriptionText,
                    Max(1, BookS(390) - BookS(4))) + BookS(4))
            proposedAddY := Max(164, Ceil((BookS(copyY) + captionHeight
                + BookS(3)) / GetCharacterBookScale()))
            ; Keep Import above the original footer: no new scrolling, no
            ; bitmap stretching, and no partial move if text cannot fit.
            if proposedAddY + addMetrics.Height + 5 + importMetrics.Height <= 570
                && addMetrics.Width <= 370 && importMetrics.Width <= 370
            {
                CharacterDescription.Move(BookS(70), BookS(copyY),
                    BookS(390), captionHeight)
                actionY := proposedAddY
            }
        }
        MoveMeasuredBookAction(AddCharacterButton, 70, actionY, 370, addMetrics.Height)
        transferY := actionY + addMetrics.Height + 5
        ; The transfer action shares the full-width left lane in both states.
        ; MoveStyledButton updates both the native and painted face.
        ; Hide the existing painted face while the single transfer control moves.
        ; Otherwise its old location can remain drawn as a second (ghost) button.
        if ButtonFaces.Has(DataTransferButton.Hwnd)
        {
            transferFace := ButtonFaces[DataTransferButton.Hwnd]
            try transferFace.Control.Visible := false
            try transferFace.Label.Visible := false
        }
        MoveMeasuredBookAction(DataTransferButton, 70, transferY, 370, transferMetrics.Height)
        if ButtonFaces.Has(DataTransferButton.Hwnd)
        {
            transferFace := ButtonFaces[DataTransferButton.Hwnd]
            try transferFace.Control.Visible := true
            try transferFace.Label.Visible := true
        }
        ; EndInterfaceUpdate repaints the old and new button positions together.
        WipeCharacterButton.Visible := Profiles.Length > 0
        if Profiles.Length > 0
            MoveStyledButton(WipeCharacterButton, 70, 575, 370, 30)
        CharacterLimitNotice.Visible := Profiles.Length >= MaxCharacters
        DataTransferButton.Text := Profiles.Length ? "Export Character List" : "Import Data"
        ; Changing the native control text does not update the separately painted
        ; Morrowind button face. Keep both layers synchronized after Import Data.
        if ButtonFaces.Has(DataTransferButton.Hwnd)
            ButtonFaces[DataTransferButton.Hwnd].Text := DataTransferButton.Text
        AddCharacterButton.Enabled := Profiles.Length < MaxCharacters
        ; A populated book needs coordinated text/row/action geometry.
        ; This keeps the fixed 960x650 art and all macro/editor controls intact.
        if !ReflowAccessiblePopulatedCharacters()
            BindCharacterBookRows(PlanCharacterBookPages([], 0, 10))
    }
    finally EndInterfaceUpdate()
}

; The original character rows remain the immutable Normal baseline. For
; larger text, use a two-line row: full name above accessible-width buttons.
; Preflight the entire visible page and request additional parent height
; when needed. If the monitor cannot fit the complete arrangement, preserve
; the previous baseline; never partially move a row or distort the parchment.
ReflowAccessiblePopulatedCharacters()
{
    global CharacterPage, CharacterRows, CharacterDescription, Profiles
    global AddCharacterButton, AccessibilityTextSize, ButtonFaces
    global CharacterLimitNotice, MaxCharacters, CharacterListPage
    if !IsObject(CharacterPage) || !CharacterRows.Length
        return false
    scale := GetCharacterBookScale()
    if AccessibilityTextSize = "Normal" || !Profiles.Length
    {
        RestoreAccessibleCharacterRowBaseline()
        BindCharacterBookRows(PlanCharacterBookPages([], 0, 10))
        return false
    }
    copyY := CharacterBookDescriptionY()
    paragraph := CharacterDescription.Text
    paragraphHeight := Max(BookS(81),
        MeasureAccessibleWrappedText(CharacterDescription, paragraph,
            Max(1, BookS(390) - BookS(4))) + BookS(4))
    firstY := Max(164, Ceil((BookS(copyY) + paragraphHeight + BookS(5)) / scale))
    ; Every profile is measured against the same full-width name lane.
    ; Use all names, not just the current page, for a stable page partition.
    controls := CharacterRows[1]
    widths := [], buttonHeight := 23
    for button in [controls.Play, controls.Edit, controls.Remove]
    {
        extent := MeasureAccessibleSingleLineText(button, button.Text)
        widths.Push(Max(84, Ceil((extent.Width + BookS(12)) / scale)))
        buttonHeight := Max(buttonHeight, Ceil((extent.Height + BookS(6)) / scale))
    }
    if widths[1] + widths[2] + widths[3] + 12 > 345
    {
        CharacterPage.BookExpansionFailure := "Character actions exceed the full name lane."
        RestoreAccessibleCharacterRowBaseline()
        return false
    }
    metrics := [], pitches := []
    for profile in Profiles
    {
        name := profile.Name
        displayName := PrepareAccessibleBookName(controls.Name, name, BookS(338))
        nameHeight := Max(23, Ceil((
            MeasureAccessibleWrappedText(controls.Name, displayName, BookS(338))
            + BookS(4)) / scale))
        pitch := nameHeight + 4 + buttonHeight + 8
        metrics.Push({DisplayName: displayName, NameHeight: nameHeight, Pitch: pitch})
        pitches.Push(pitch)
    }
    noticeVisible := Profiles.Length >= MaxCharacters
    noticeHeight := noticeVisible ? Max(25, Ceil((
        MeasureAccessibleWrappedText(CharacterLimitNotice,
            CharacterLimitNotice.Text, BookS(362)) + BookS(4)) / scale)) : 0
    footer := GetBookFooterMetrics(CharacterPage)
    addY := PlanCharacterBookActionStack(575, footer).AddY
    navHeight := 30
    if CharacterPage.HasOwnProp("BookPreviousPage")
    {
        navHeight := Max(navHeight,
            BookActionMetrics(CharacterPage.BookPreviousPage, "Previous", 112, 30).Height,
            BookActionMetrics(CharacterPage.BookNextPage, "Next", 112, 30).Height,
            Ceil((MeasureAccessibleWrappedText(CharacterPage.BookPageLabel,
                "Page 10 of 10", BookS(138)) + BookS(4)) / scale))
    }
    ; Prefer the approved 650px book, reserving the complete footer/notice.
    ; Reserve navigation only if the first no-navigation plan needs pages.
    limitY := addY - 8 - (noticeVisible ? noticeHeight + 8 : 0)
    pages := PlanCharacterBookPages(pitches, limitY - firstY)
    if pages.Length > 1
    {
        limitY -= navHeight + 8
        pages := PlanCharacterBookPages(pitches, limitY - firstY)
    }
    ; Exceptional single rows may need the existing reversible expansion.
    required := 0
    for pitch in pitches
        required := Max(required, firstY + pitch - limitY)
    CharacterPage.BookRequiredCharacterExtra := required
    if !SetCharacterBookLayoutExtra("Characters", required)
    {
        RestoreAccessibleCharacterRowBaseline()
        return false
    }
    BindCharacterBookRows(pages)
    current := pages[CharacterListPage]
    layouts := [], rowY := firstY
    Loop current.Count
    {
        position := A_Index
        item := metrics[current.First + position - 1]
        layouts.Push({Controls: CharacterRows[position], Y: rowY, NameWidth: 345,
            NameHeight: item.NameHeight, DisplayName: item.DisplayName,
            ButtonX: 95, ButtonY: rowY + item.NameHeight + 4,
            ButtonHeight: buttonHeight, Widths: widths, Gap: 6})
        rowY += item.Pitch
    }
    noticeY := limitY + required + 4
    if pages.Length > 1
        PositionCharacterBookNavigation(limitY + required + (noticeVisible ? noticeHeight + 8 : 0), navHeight)
    ; Grouped update: all coordinates are newly calculated from approved
    ; anchors, never accumulated from the previously scaled/reflowed positions.
    ; Mark rollback as armed *before* the first move: if a native HWND fails
    ; halfway through, restore all row faces/hitboxes and Add's original slot.
    CharacterPage.AccessibleRowsReflowed := true
    try
    {
        CharacterDescription.Move(BookS(70), BookS(copyY),
            BookS(390), paragraphHeight)
        for layout in layouts
        {
            controls := layout.Controls
            y := layout.Y
            MoveStyledButton(controls.Tick, 70, y + 2, 18, 18)
            MoveStyledButton(controls.Name, 95, y,
                layout.NameWidth, layout.NameHeight)
            if ButtonFaces.Has(controls.Name.Hwnd)
            {
                ButtonFaces[controls.Name.Hwnd].AccessibleWrappedName := true
                ButtonFaces[controls.Name.Hwnd].AccessibleNameText := layout.DisplayName
            }
            x := layout.ButtonX
            for index, button in [controls.Play, controls.Edit, controls.Remove]
            {
                width := layout.Widths[index]
                MoveStyledButton(button, x, layout.ButtonY, width,
                    layout.ButtonHeight)
                ; Text is already measured at its requested accessible font.
                ; The GDI painter must not independently shrink that font.
                if ButtonFaces.Has(button.Hwnd)
                    ButtonFaces[button.Hwnd].NoAccessibleDownfit := true
                x += width + layout.Gap
            }
        }
        if noticeVisible
        {
            MoveStyledButton(CharacterLimitNotice, 70, noticeY, 370,
                noticeHeight)
            if ButtonFaces.Has(CharacterLimitNotice.Hwnd)
                ButtonFaces[CharacterLimitNotice.Hwnd].AccessibleWrappedName := true
        }
        ; The shared parent has already committed the measured Add/footer.
        return true
    }
    catch Error as err
    {
        RestoreAccessibleCharacterRowBaseline()
        CharacterDescription.Move(BookS(70), BookS(80),
            BookS(390), BookS(81))
        throw err
    }
}

; Shared fixed-capacity pagination for both halves of the Character Book.
PlanFixedBookPages(itemCount, pageSize)
{
    pages := [], first := 1
    pageSize := Max(1, pageSize)
    while first <= itemCount
    {
        count := Min(pageSize, itemCount - first + 1)
        pages.Push({First: first, Count: count})
        first += count
    }
    if !pages.Length
        pages.Push({First: 1, Count: 0})
    return pages
}

PlanCharacterBookPages(pitches, budget, fixedSize := 0)
{
    global Profiles
    pages := [], first := 1, count := 0, used := 0
    if fixedSize
        return PlanFixedBookPages(Profiles.Length, fixedSize)
    else
    {
        for index, pitch in pitches
        {
            if count && (used + pitch > budget || count >= 10)
            {
                pages.Push({First: first, Count: count})
                first := index, count := 0, used := 0
            }
            used += pitch
            count += 1
        }
        if count
            pages.Push({First: first, Count: count})
    }
    if !pages.Length
        pages.Push({First: 1, Count: 0})
    return pages
}

BindCharacterBookRows(pages)
{
    global CharacterPage, CharacterRows, Profiles, SelectedProfile, CharacterListPage, ButtonFaces
    CharacterListPage := Max(1, Min(CharacterListPage, pages.Length))
    CharacterPage.BookPages := pages
    current := pages[CharacterListPage]
    CharacterPage.BookVisibleFirst := current.First
    CharacterPage.BookVisibleCount := current.Count
    for position, controls in CharacterRows
    {
        visible := position <= current.Count
        index := current.First + position - 1
        for control in [controls.Tick, controls.Name, controls.Play, controls.Edit, controls.Remove]
            control.Visible := visible
        if visible
        {
            if controls.Name.Text != Profiles[index].Name
                controls.Name.Text := Profiles[index].Name
            if ButtonFaces.Has(controls.Tick.Hwnd)
                SetBookTick(controls.Tick, SelectedProfile = index)
        }
    }
    if CharacterPage.HasOwnProp("BookPreviousPage")
    {
        showNav := pages.Length > 1
        CharacterPage.BookPreviousPage.Visible := showNav
        CharacterPage.BookNextPage.Visible := showNav
        CharacterPage.BookPageLabel.Visible := showNav
        CharacterPage.BookPreviousPage.Enabled := CharacterListPage > 1
        CharacterPage.BookNextPage.Enabled := CharacterListPage < pages.Length
        CharacterPage.BookPageLabel.Text := "Page " CharacterListPage " of " pages.Length
    }
}

PositionCharacterBookNavigation(y, height)
{
    global CharacterPage
    if !CharacterPage.HasOwnProp("BookPreviousPage")
        return
    MoveMeasuredBookAction(CharacterPage.BookPreviousPage, 70, y, 112, height)
    MoveMeasuredBookAction(CharacterPage.BookNextPage, 328, y, 112, height)
    CharacterPage.BookPageLabel.Move(BookS(184), BookS(y), BookS(142), BookS(height))
}

ChangeCharacterBookPage(delta, *)
{
    global CharacterPage, CharacterListPage
    if !IsObject(CharacterPage) || !CharacterPage.HasOwnProp("BookPages")
        return
    nextPage := Max(1, Min(CharacterPage.BookPages.Length, CharacterListPage + delta))
    if nextPage = CharacterListPage
        return
    CharacterListPage := nextPage
    RefreshProfiles()
}

VisibleCharacterProfileIndex(position)
{
    global CharacterPage, CharacterListPage, Profiles
    if IsObject(CharacterPage) && CharacterPage.HasOwnProp("BookVisibleFirst")
    {
        if position < 1 || position > CharacterPage.BookVisibleCount
            return 0
        return CharacterPage.BookVisibleFirst + position - 1
    }
    index := (CharacterListPage - 1) * 10 + position
    return index >= 1 && index <= Profiles.Length ? index : 0
}

RestoreAccessibleCharacterRowBaseline()
{
    global CharacterPage, CharacterRows, ButtonFaces, CharacterLimitNotice
    SetCharacterBookLayoutExtra("Characters", 0)
    if !IsObject(CharacterPage)
        || !CharacterPage.HasOwnProp("AccessibleRowsReflowed")
        || !CharacterPage.AccessibleRowsReflowed
        return
    for index, controls in CharacterRows
    {
        y := 164 + (index - 1) * 24
        MoveStyledButton(controls.Tick, 70, y + 2, 18, 18)
        MoveStyledButton(controls.Name, 95, y, 140, 23)
        if ButtonFaces.Has(controls.Name.Hwnd)
        {
            nameFace := ButtonFaces[controls.Name.Hwnd]
            if nameFace.HasOwnProp("AccessibleWrappedName")
                nameFace.DeleteProp("AccessibleWrappedName")
            if nameFace.HasOwnProp("AccessibleNameText")
                nameFace.DeleteProp("AccessibleNameText")
        }
        for entry in [{Control: controls.Play, X: 240, Width: 55},
            {Control: controls.Edit, X: 300, Width: 60},
            {Control: controls.Remove, X: 365, Width: 75}]
        {
            button := entry.Control
            MoveStyledButton(button, entry.X, y, entry.Width, 22)
            if ButtonFaces.Has(button.Hwnd)
            {
                face := ButtonFaces[button.Hwnd]
                if face.HasOwnProp("NoAccessibleDownfit")
                    face.DeleteProp("NoAccessibleDownfit")
            }
        }
    }
    MoveStyledButton(CharacterLimitNotice, 70, 429, 370, 25)
    if ButtonFaces.Has(CharacterLimitNotice.Hwnd)
        ButtonFaces[CharacterLimitNotice.Hwnd].AccessibleWrappedName := false
    CharacterPage.AccessibleRowsReflowed := false
}

MoveStyledButton(control, x, y, width, height)
{
    global ButtonFaces, CharacterPage
    if IsObject(CharacterPage) && control.Gui.Hwnd = CharacterPage.Hwnd
    {
        x := BookS(x), y := BookS(y)
        width := BookS(width), height := BookS(height)
    }
    control.Move(x, y, width, height)
    if ButtonFaces.Has(control.Hwnd)
    {
        face := ButtonFaces[control.Hwnd]
        face.X := x
        face.Y := y
        face.W := width
        face.H := height
        ; AddStyledButton uses a separate painted face over the native button.
        ; Move that face too; updating metadata alone leaves the old artwork behind.
        if face.HasOwnProp("Control") && IsObject(face.Control)
            face.Control.Move(x, y, width, height)
    }
}

EditVisibleProfile(position, *)
{
    global CharacterListPage
    index := VisibleCharacterProfileIndex(position)
    if index
        EditProfile(index)
}

ChooseProfile(position, control, *)
{
    global Profiles, SelectedProfile, CharacterListPage, CharacterPage, DataFile
    index := VisibleCharacterProfileIndex(position)
    if index < 1 || index > Profiles.Length || SelectedProfile = index
        return
    ; Explain favorite switching only once per launcher profile. Remember the
    ; acknowledgment after either answer, but never change the favorite on No.
    if SelectedProfile > 0 && IniRead(DataFile, "Launcher", "HideFavoriteSwitchExplanation", "0") != "1"
    {
        CharacterPage.Opt("+OwnDialogs")
        prompt := "Clicking this checkbox will mark this as your main / favorite character. Doing so will set you up for auto launching on the launchers main page. You can change this anytime by simply clicking the checkbox on another character instead. Are you sure you want to favorite this character? (Yes/No)"
        result := MsgBox(prompt, "Favorite character", 0x124)
        DirCreate(AppDataDirectory)
        IniWrite("1", DataFile, "Launcher", "HideFavoriteSwitchExplanation")
        if result != "Yes"
            return
    }
    try SaveDefaultProfile(index)
    catch
    {
        MsgBox("Could not save your favorite character. Check launcher data permissions.", "tes3np", "Icon!")
        return
    }
    RefreshProfiles()
}

HideProfileEditor()
{
    global EditorControls, LaunchSettingsHeading
    for control in EditorControls
        try control.Visible := false
    try LaunchSettingsHeading.Visible := false
    ShowMacroBookPanel()
}

CloseCharacterPage(*)
{
    global CharacterPage
    ; The visible parent is already painted behind this owned book. Use the
    ; cached launcher's no-repaint return, then hide the book immediately.
    ; A real scale/layout change still uses the existing protected rebuild.
    startedAt := A_TickCount
    ShowLauncherWindow(true)
    preparedMs := A_TickCount - startedAt
    CharacterPage.Hide()
    hiddenMs := A_TickCount - startedAt
    ; Capture only slow transitions, with no character names or file paths.
    ; The video showed a visibly persistent book after Close, so measure the
    ; time spent preparing the parent separately from the actual Hide call.
    if hiddenMs >= 150
        LogLauncherEvent("UI | Character Book close " hiddenMs "ms | Parent " preparedMs "ms | Hide " (hiddenMs - preparedMs) "ms.")
    ; Reset dormant controls only AFTER hiding, avoiding a visible flash of
    ; the editor/list while navigating back to the launcher.
    HideProfileEditor()
    CloseMacroPage()
}

EditProfile(index, *)
{
    global Profiles, CharacterPage, MaxCharacters, EditorControls, EditorSpeciesDropDown, LaunchSettingsHeading
    global EditorOriginalSpecies, EditorOriginalPortraitFile, EditorOriginalPortraitSource, EditorPreviousSpeciesChoice, EditorOriginalMode
    global EditorReconnectTick
    if !index && Profiles.Length >= MaxCharacters
    {
        MsgBox("You can save up to 10 characters. Remove one before adding another.", "tes3np")
        return
    }
    layoutReady := false
    BeginInterfaceUpdate(0, "Loading character settings...", true)
    try
    {
        profile := index ? Profiles[index] : NewCharacterProfile()
        CharacterPage.BookEditorHeadingText := index ? "Editing " profile.Name : "Add New Character"
        LaunchSettingsHeading.Text := CharacterPage.BookEditorHeadingText
        CharacterPage.BookEditorControls.AccountHeading.Text := GetBookEditorAccountHeading(index)
        LaunchSettingsHeading.Visible := true
        HideMacroBookPanel()
        SetAccessibleTextFont(CharacterPage, "s10 c382314", LauncherThemeFont())
        global EditorFields
        entries := [["Name", "Username", profile.Name], ["Password", "Password", profile.Password],
            ["UsernameDelay", "Username screen delay (sec)", profile.UsernameDelay],
            ["PasswordDelay", "Password screen delay (sec)", profile.PasswordDelay],
            ["LoadDelay", "Character loading delay (sec)", profile.LoadDelay]]
        EditorFields := Map()
        for entry in entries
            EditorFields[entry[1]] := {Value: entry[3]}
        EditorFields["AutoReconnect"] := profile.AutoReconnect
        ; Legacy characters remain editable without an invented race.
        species := profile.HasOwnProp("Species") ? NormalizeCharacterSpecies(profile.Species) : ""
        speciesIndex := 1
        for optionIndex, option in CharacterSpeciesOptions()
            if option = species
                speciesIndex := optionIndex + 1
        EditorOriginalPortraitFile := profile.HasOwnProp("PortraitFile") ? NormalizeCustomPortraitFile(profile.PortraitFile) : ""
        EditorOriginalPortraitSource := ""
        EditorOriginalSpecies := species
        EditorOriginalMode := EditorOriginalPortraitFile != ""
        ; An OC portrait stays selected in its own state, while the visible
        ; dropdown always shows the character's race at a glance.
        EditorSpeciesDropDown.Choose(speciesIndex)
        EditorPreviousSpeciesChoice := speciesIndex
        PopulateProfileEditorRows(entries)
        SetBookTick(EditorReconnectTick, EditorFields["AutoReconnect"])
        global EditorSaveButton, ButtonFaces
        EditorSaveButton.Text := index ? "Save changes" : "Add character"
        ButtonFaces[EditorSaveButton.Hwnd].LoadingText := "Saving character..."
        ButtonFaces[EditorSaveButton.Hwnd].Action := SaveProfileEditor.Bind(index, EditorFields)
        for control in EditorControls
            control.Visible := true
        layoutReady := UpdateOriginalSpeciesHint()
        if !layoutReady
            HideProfileEditor()
    }
    finally EndInterfaceUpdate()
    if !layoutReady
        MsgBox("The character editor needs more room. Choose a smaller Launcher Scale and try again.", "tes3np")
}

GetBookEditorAccountHeading(index)
{
    return index ? "Registered Account" : "Register Existing Account"
}

; Build once while the book is hidden; later actions only populate these controls.
CreateProfileEditor()
{
    global CharacterPage, EditorControls, EditorRows, EditorSaveButton, EditorSpeciesDropDown, EditorOCSpeciesHint, EditorReconnectTick
    global ButtonFaces
    SetAccessibleTextFont(CharacterPage, "s13 Bold c241408", LauncherThemeFont())
    accountHeading := AddBookLabel(CharacterPage, 525, 82, 355, 24, GetBookEditorAccountHeading(0))
    accountHeading.Visible := false
    ButtonFaces[accountHeading.Hwnd].TextColor := 0x081424
    EditorControls.Push(accountHeading)
    EditorRows := []
    Loop 5
    {
        position := A_Index
        ; Credentials sit above the dedicated auto-login settings section.
        y := 118 + (position - 1) * 50 + (position >= 2 ? 8 : 0) + (position >= 3 ? 46 : 0)
        if position = 3
        {
            SetAccessibleTextFont(CharacterPage, "s13 Bold c241408", LauncherThemeFont())
            autoLoginHeading := AddBookLabel(CharacterPage, 525, 236, 355, 24, "Auto Login")
            autoLoginHeading.Visible := false
            ButtonFaces[autoLoginHeading.Hwnd].TextColor := 0x081424
            EditorControls.Push(autoLoginHeading)
        }
        SetAccessibleTextFont(CharacterPage, "s10 Bold c382314", LauncherThemeFont())
        SetInterfaceLoadingText("Loading setting label " position "...")
        label := AddBookLabel(CharacterPage, 525, y, 355, 22, "")
        SetInterfaceLoadingText("Loading setting field " position "...")
        input := AddThemedEdit(CharacterPage, "x525 y" (y + 23) " w355 h25 Hidden")
        input.OnEvent("Change", UpdateEditorField.Bind(position))
        EditorRows.Push({Label: label, Input: input, Key: ""})
        EditorControls.Push(label)
        EditorControls.Push(input)
    }
    SetInterfaceLoadingText("Loading race selector...")
    SetAccessibleTextFont(CharacterPage, "s13 Bold c241408", LauncherThemeFont())
    speciesLabel := AddBookLabel(CharacterPage, 525, 432, 355, 24, "Race Info")
    speciesLabel.Visible := false
    ButtonFaces[speciesLabel.Hwnd].TextColor := 0x081424
    SetAccessibleTextFont(CharacterPage, "s10 Bold c382314", LauncherThemeFont())
    speciesOptions := ["Select race..."]
    for item in CharacterSpeciesOptions()
        speciesOptions.Push(item)
    speciesOptions.Push("Original Character")
    EditorSpeciesDropDown := CharacterPage.Add("DropDownList",
        "x525 y468 w355 h240 Choose1 Hidden BackgroundE2CEA2 c382314", speciesOptions)
    EditorSpeciesDropDown.OnEvent("Change", (*) => ChooseOriginalCharacterPortrait(EditorSpeciesDropDown))
    SetAccessibleTextFont(CharacterPage, "s9 Norm c382314", LauncherThemeFont())
    ; The hint must remain below the collapsed native race selector,
    ; so its text could remain invisible until the book was reconstructed.
    EditorOCSpeciesHint := CharacterPage.Add("Text",
        "x525 y499 w355 h19 Hidden BackgroundTrans c382314 +0x100", "")
    ; A selected DDL item cannot trigger Change twice: allow editing an OC
    ; by clicking the persistent race line without changing the layout.
    EditorOCSpeciesHint.OnEvent("Click", (*) => ChooseOriginalCharacterPortrait(EditorSpeciesDropDown, true))
    SetAccessibleTextFont(CharacterPage, "s10 Bold c382314", LauncherThemeFont())
    EditorControls.Push(speciesLabel, EditorSpeciesDropDown, EditorOCSpeciesHint)
    EditorReconnectTick := AddBookTick(CharacterPage, 525, 527, ToggleEditorReconnect)
    reconnectLabel := AddBookLabel(CharacterPage, 551, 524, 329, 24, "Auto reconnect on crash")
    reconnectLabel.Opt("+0x100")
    reconnectLabel.OnEvent("Click", ToggleEditorReconnect)
    EditorControls.Push(EditorReconnectTick, reconnectLabel)
    SetAccessibleTextFont(CharacterPage, "s10 Norm c382314", LauncherThemeFont())
    SetInterfaceLoadingText("Loading Save button...")
    EditorSaveButton := AddStyledButton(CharacterPage, 635, 557, 140, 30, "Save changes", (*) => 0)
    EditorControls.Push(EditorSaveButton)
    dismiss := AddStyledButton(CharacterPage, 685, 599, 30, 24, "X", CloseProfileEditor)
    EditorControls.Push(dismiss)
    CharacterPage.BookEditorControls := {Rows: EditorRows, AccountHeading: accountHeading,
        AutoLoginHeading: autoLoginHeading, SpeciesLabel: speciesLabel,
        Species: EditorSpeciesDropDown, Hint: EditorOCSpeciesHint, Tick: EditorReconnectTick,
        Reconnect: reconnectLabel, Save: EditorSaveButton, Dismiss: dismiss}
}

; The right-hand column is either the editor or the Macro Book, never
; both. Compute its entire stack using the native font already attached
; to each HWND, preserving the title and first-field anchors.
; Conservative inner contour of the right-hand parchment in the original
; 960x650 artwork. Extension rows above the taper move its boundary down.
; Use the outermost horizontal edge of each control, not just its center.
BookEditorSafeBottom(x, width)
{
    distance := Max(Abs(x - 705), Abs(x + width - 705))
    return 445 + Floor(Max(0, 180 - distance) * 120 / 180)
}

PlanBookEditorGeometry(heading, originalTitle, controls, measured, compact := false)
{
    scale := GetCharacterBookScale()
    title := measured ? PrepareAccessibleBookName(heading, originalTitle, BookS(352)) : originalTitle
    titleH := measured ? Max(30, Ceil((MeasureAccessibleWrappedText(
        heading, title, BookS(352)) + BookS(4)) / scale)) : 30
    accountY := 45 + titleH + 7
    accountH := measured ? Max(24, Ceil((MeasureAccessibleWrappedText(
        controls.AccountHeading, controls.AccountHeading.Text, BookS(351)) + BookS(4)) / scale)) : 24
    sectionGap := compact ? 8 : 12
    rowY := accountY + accountH + sectionGap
    sectionY := 0
    sectionH := measured ? Max(24, Ceil((MeasureAccessibleWrappedText(
        controls.AutoLoginHeading, controls.AutoLoginHeading.Text, BookS(351)) + BookS(4)) / scale)) : 24
    rows := []
    ; Compact rows keep measured captions beside their fields.
    labelW := compact ? 205 : 355
    inputX := compact ? 738 : 525
    inputW := 880 - inputX
    for index, row in controls.Rows
    {
        if index = 3
        {
            ; Separate the heading from the password field and delay labels.
            sectionY := rowY + sectionGap - 2
            rowY := sectionY + sectionH + sectionGap
        }
        labelH := measured ? Max(22, Ceil((MeasureAccessibleWrappedText(
            row.Label, row.Label.Text, BookS(labelW - 4)) + BookS(4)) / scale)) : 22
        inputH := measured ? Max(25, Ceil((MeasureAccessibleSingleLineText(
            row.Input, "Ag").Height + BookS(8)) / scale)) : 25
        inputY := compact ? rowY : rowY + labelH + 1
        rows.Push({Y: rowY, LabelHeight: labelH, LabelWidth: labelW,
            InputX: inputX, InputY: inputY, InputWidth: inputW, InputHeight: inputH})
        ; Give the credential pairs a clear separation without changing delay spacing.
        rowGap := index = 1 ? (compact ? 9 : 10) : (compact ? 5 : 2)
        rowY := Max(rowY + labelH, inputY + inputH) + rowGap
    }
    raceY := rowY + sectionGap - 2
    raceH := measured ? Max(24, Ceil((MeasureAccessibleWrappedText(
        controls.SpeciesLabel, controls.SpeciesLabel.Text, BookS(351)) + BookS(4)) / scale)) : 24
    ddlY := raceY + raceH + sectionGap
    ; CB_GETITEMHEIGHT(-1) reports the selection field, not the full
    ; drop-down list. Preserve the native combo's own font/list sizing.
    nativeSelectionH := DllCall("SendMessageW", "Ptr", controls.Species.Hwnd,
        "UInt", 0x154, "Ptr", -1, "Ptr", 0, "Ptr")
    ddlH := measured ? Max(26, Ceil(nativeSelectionH / (scale * A_ScreenDPI / 96)) + 8) : 26
    hintY := ddlY + ddlH + 5
    hintH := measured ? Max(19, Ceil((MeasureAccessibleWrappedText(
        controls.Hint, controls.Hint.Text, BookS(351)) + BookS(4)) / scale)) : 19
    ; Do not reserve the unused portrait hint line for ordinary races.
    reconnectY := controls.Hint.Text = "" ? ddlY + ddlH + 12 : hintY + hintH + 6
    reconnectH := measured ? Max(24, Ceil((MeasureAccessibleWrappedText(
        controls.Reconnect, controls.Reconnect.Text, BookS(325)) + BookS(4)) / scale)) : 24
    saveY := reconnectY + reconnectH + 9
    saveH := 30, saveW := 140, dismissH := 24, dismissW := 30
    if measured
    {
        saveExtent := MeasureAccessibleSingleLineText(controls.Save, controls.Save.Text)
        dismissExtent := MeasureAccessibleSingleLineText(controls.Dismiss, controls.Dismiss.Text)
        saveH := Max(saveH, Ceil((saveExtent.Height + BookS(8)) / scale))
        saveW := Max(saveW, Ceil((saveExtent.Width + BookS(12)) / scale))
        dismissH := Max(dismissH, Ceil((dismissExtent.Height + BookS(8)) / scale))
        dismissW := Max(dismissW, Ceil((dismissExtent.Width + BookS(12)) / scale))
    }
    ; If the monitor cannot accommodate the extended book, use one action
    ; row instead of squeezing the headings against their fields.
    dismissY := compact ? saveY : saveY + saveH + 12
    saveX := compact ? 705 - (saveW + 12 + dismissW) // 2 : 705 - saveW // 2
    dismissX := compact ? saveX + saveW + 12 : 700 - dismissW // 2
    extra := Max(0, reconnectY + reconnectH + 5 - BookEditorSafeBottom(525, 355),
        saveY + saveH + 5 - BookEditorSafeBottom(saveX, saveW),
        dismissY + dismissH + 5 - BookEditorSafeBottom(dismissX, dismissW))
    return {Title: title, TitleHeight: titleH, Rows: rows,
        AccountY: accountY, AccountHeight: accountH, SaveX: saveX, DismissX: dismissX,
        SectionY: sectionY, SectionHeight: sectionH, RaceY: raceY,
        RaceHeight: raceH, DropdownY: ddlY, HintY: hintY, HintHeight: hintH,
        ReconnectY: reconnectY, ReconnectHeight: reconnectH, SaveY: saveY,
        SaveHeight: saveH, SaveWidth: saveW, DismissY: dismissY,
        DismissHeight: dismissH, DismissWidth: dismissW,
        Extra: extra,
        FitsWidth: compact ? saveW + 12 + dismissW <= 355 : saveW <= 355 && dismissW <= 355}
}

ReflowProfileEditor()
{
    global CharacterPage, LaunchSettingsHeading, AccessibilityTextSize, ButtonFaces
    if !IsObject(CharacterPage) || !CharacterPage.HasOwnProp("BookEditorControls")
        || !CharacterPage.HasOwnProp("BookEditorHeadingText")
        return false
    controls := CharacterPage.BookEditorControls
    measured := AccessibilityTextSize != "Normal"
    plan := PlanBookEditorGeometry(LaunchSettingsHeading,
        CharacterPage.BookEditorHeadingText, controls, measured)
    ; Reuse the right-column allocation because Macro Book is hidden.
    if !plan.FitsWidth || !SetCharacterBookLayoutExtra("Macros", plan.Extra)
    {
        ; Try measured compact rows before revealing any clipped layout.
        ; Never apply a plan whose artwork extension could not be allocated.
        measured := true
        plan := PlanBookEditorGeometry(LaunchSettingsHeading,
            CharacterPage.BookEditorHeadingText, controls, measured, true)
        if !plan.FitsWidth || !SetCharacterBookLayoutExtra("Macros", plan.Extra)
            return false
    }
    LaunchSettingsHeading.Text := plan.Title
    MoveMacroTextIfChanged(LaunchSettingsHeading, BookS(525), BookS(45),
        BookS(360), BookS(plan.TitleHeight))
    for section in [controls.AccountHeading, controls.AutoLoginHeading, controls.SpeciesLabel]
        ButtonFaces[section.Hwnd].AccessibleWrappedName := measured
    MoveMacroStyledIfChanged(controls.AccountHeading, 525, plan.AccountY, 355, plan.AccountHeight)
    MoveMacroStyledIfChanged(controls.AutoLoginHeading, 525, plan.SectionY, 355, plan.SectionHeight)
    for index, row in controls.Rows
    {
        metrics := plan.Rows[index]
        ButtonFaces[row.Label.Hwnd].AccessibleWrappedName := measured
        MoveMacroStyledIfChanged(row.Label, 525, metrics.Y, metrics.LabelWidth, metrics.LabelHeight)
        MoveMacroTextIfChanged(row.Input, BookS(metrics.InputX), BookS(metrics.InputY),
            BookS(metrics.InputWidth), BookS(metrics.InputHeight))
    }
    ButtonFaces[controls.Reconnect.Hwnd].AccessibleWrappedName := measured
    MoveMacroStyledIfChanged(controls.SpeciesLabel, 525, plan.RaceY, 355, plan.RaceHeight)
    ; Move the native combo without changing the height of its drop-down.
    controls.Species.GetPos(, &oldDropdownY)
    if oldDropdownY != BookS(plan.DropdownY)
        controls.Species.Move(BookS(525), BookS(plan.DropdownY))
    MoveMacroTextIfChanged(controls.Hint, BookS(525), BookS(plan.HintY),
        BookS(355), BookS(plan.HintHeight))
    MoveMacroStyledIfChanged(controls.Tick, 525, plan.ReconnectY + 3, 18, 18)
    MoveMacroStyledIfChanged(controls.Reconnect, 551, plan.ReconnectY, 329, plan.ReconnectHeight)
    for button in [controls.Save, controls.Dismiss]
        ButtonFaces[button.Hwnd].NoAccessibleDownfit := measured
    MoveMacroStyledIfChanged(controls.Save, plan.SaveX,
        plan.SaveY, plan.SaveWidth, plan.SaveHeight)
    MoveMacroStyledIfChanged(controls.Dismiss, plan.DismissX,
        plan.DismissY, plan.DismissWidth, plan.DismissHeight)
    return true
}

ToggleEditorReconnect(*)
{
    global EditorReconnectTick, EditorFields
    EditorFields["AutoReconnect"] := !EditorFields["AutoReconnect"]
    SetBookTick(EditorReconnectTick, EditorFields["AutoReconnect"])
}

; Keep the existing race list intact. "Original Character" is the only
; presentation-only entry; the race is chosen in a separate dialog.
UpdateOriginalSpeciesHint()
{
    global EditorOCSpeciesHint, EditorOriginalSpecies, EditorOriginalMode, LaunchSettingsHeading
    isOriginal := EditorOriginalMode
    oldText := EditorOCSpeciesHint.Text
    EditorOCSpeciesHint.Text := isOriginal && EditorOriginalSpecies != ""
        ? "Race: " EditorOriginalSpecies "  |  Change portrait" : ""
    if IsObject(LaunchSettingsHeading) && LaunchSettingsHeading.Visible
        && !ReflowProfileEditor()
    {
        EditorOCSpeciesHint.Text := oldText
        return false
    }
    EditorOCSpeciesHint.Visible := isOriginal && EditorOriginalSpecies != ""
    ; The race must be visible as soon as the dialog closes, even when the
    ; cached Character Book is reused without reopening Manage Characters.
    if IsObject(EditorOCSpeciesHint)
    {
        DllCall("RedrawWindow", "Ptr", EditorOCSpeciesHint.Hwnd, "Ptr", 0,
            "Ptr", 0, "UInt", 0x105)
    }
    return true
}

; Preserve the previous selection if the new hint cannot fit the monitor.
ApplyEditorPortraitHint(control, previous)
{
    global EditorPreviousSpeciesChoice, EditorOriginalPortraitSource, EditorOriginalPortraitFile
    global EditorOriginalSpecies, EditorOriginalMode
    if UpdateOriginalSpeciesHint()
        return
    EditorPreviousSpeciesChoice := previous.Choice
    EditorOriginalPortraitSource := previous.Source
    EditorOriginalPortraitFile := previous.File
    EditorOriginalSpecies := previous.Species
    EditorOriginalMode := previous.Mode
    control.Choose(previous.Choice)
    MsgBox("The character editor needs more room. Choose a smaller Launcher Scale and try again.", "tes3np")
}

ChooseOriginalCharacterPortrait(control, replaceOC := false)
{
    global EditorPreviousSpeciesChoice, EditorOriginalPortraitSource
    global EditorOriginalPortraitFile, EditorOriginalSpecies, EditorOriginalMode
    previous := {Choice: EditorPreviousSpeciesChoice, Source: EditorOriginalPortraitSource,
        File: EditorOriginalPortraitFile, Species: EditorOriginalSpecies, Mode: EditorOriginalMode}

    if !replaceOC && control.Text != "Original Character"
    {
        EditorPreviousSpeciesChoice := control.Value
        EditorOriginalPortraitSource := ""
        EditorOriginalPortraitFile := ""
        EditorOriginalSpecies := ""
        EditorOriginalMode := false
        ApplyEditorPortraitHint(control, previous)
        return
    }

    ; File picker cancellation or rejection leaves the previous selection
    ; and any previously saved picture untouched.
    oldChoice := EditorPreviousSpeciesChoice
    source := FileSelect(1, , "Choose an original character portrait",
        "Images (*.png; *.jpg; *.jpeg; *.bmp)")
    if source = ""
    {
        control.Choose(oldChoice)
        return
    }
    if !IsValidOriginalCharacterImage(source)
    {
        MsgBox("This image could not be used. Choose a readable PNG, JPG, JPEG, "
            "or BMP image under 10 MB. Very large image dimensions are not supported.",
            "Portrait rejected", "Icon!")
        control.Choose(oldChoice)
        return
    }
    species := PromptOriginalCharacterSpecies(EditorOriginalSpecies)
    if species = ""
    {
        control.Choose(oldChoice)
        return
    }
    EditorOriginalPortraitSource := source
    EditorOriginalPortraitFile := ""
    EditorOriginalSpecies := species
    EditorOriginalMode := true
    ; "Original Character" starts the picker, but the final dropdown must
    ; display the chosen race. The independent OC flag determines which
    ; image is saved/displayed, so choosing Dark Elf does not remove the OC.
    for raceIndex, race in CharacterSpeciesOptions()
        if race = species
        {
            selectedIndex := raceIndex + 1
            control.Choose(selectedIndex)
            EditorPreviousSpeciesChoice := selectedIndex
            break
        }
    ApplyEditorPortraitHint(control, previous)
}

IsValidOriginalCharacterImage(source)
{
    ; Accept common image sizes, not only 512x512. Decode with the same
    ; already-initialized GDI+ engine used for the launcher artwork.
    if !RegExMatch(source, "i)\.(png|jpg|jpeg|bmp)$")
        return false
    image := 0
    try
    {
        if FileGetSize(source) > 10485760 || FileGetSize(source) < 1
            return false
        if DllCall("gdiplus\GdipLoadImageFromFile", "WStr", source,
            "Ptr*", &image, "Int") != 0 || !image
            return false
        width := 0, height := 0
        if DllCall("gdiplus\GdipGetImageWidth", "Ptr", image,
            "UInt*", &width, "Int") != 0
            || DllCall("gdiplus\GdipGetImageHeight", "Ptr", image,
            "UInt*", &height, "Int") != 0
            return false
        ; Reject malicious/huge image dimensions before allocating a bitmap.
        return width > 0 && height > 0 && width <= 16384 && height <= 16384
            && width * height <= 67108864
    }
    catch
        return false
    finally
    {
        if image
            DllCall("gdiplus\GdipDisposeImage", "Ptr", image)
    }
}

; Open a native owned dialog after a valid image has been chosen. This race
; is saved normally and shown beneath the Original Character dropdown entry.
PromptOriginalCharacterSpecies(current := "")
{
    global CharacterPage
    outcome := {Species: ""}
    dialog := Gui("+Owner" CharacterPage.Hwnd " -MinimizeBox -MaximizeBox",
        "Original Character race")
    dialog.BackColor := "E2CEA2"
    SetAccessibleTextFont(dialog, "s10 c382314", LauncherThemeFont())
    dialog.Add("Text", "x20 y17 w320 h40",
        "What is your original character's race?")
    options := ["Select race..."]
    for race in CharacterSpeciesOptions()
        options.Push(race)
    selected := dialog.Add("DropDownList", "x20 y65 w320 Choose1", options)
    for i, race in CharacterSpeciesOptions()
        if race = current
            selected.Choose(i + 1)
    confirm := dialog.Add("Button", "x148 y110 w90 h29 Default", "Confirm")
    cancel := dialog.Add("Button", "x250 y110 w90 h29", "Cancel")
    confirm.OnEvent("Click", ConfirmOriginalCharacterSpecies.Bind(dialog, selected, outcome))
    cancel.OnEvent("Click", CloseOriginalCharacterSpeciesDialog.Bind(dialog))
    dialog.OnEvent("Close", CloseOriginalCharacterSpeciesDialog.Bind(dialog))
    dialog.OnEvent("Escape", CloseOriginalCharacterSpeciesDialog.Bind(dialog))
    CharacterPage.Opt("+Disabled")
    try
    {
        dialogScale := GetOwnedMenuScale()
        ScaleOwnedMenuContent(dialog, dialogScale)
        dialog.Show("Hide w" Round(360 * dialogScale) " h" Round(155 * dialogScale))
        PositionOwnedMenuAtParent(dialog, CharacterPage)
        dialog.Show()
        WinWaitClose("ahk_id " dialog.Hwnd)
    }
    finally
    {
        ; Always restore the owner after the child popup has gone away.
        ; Reuse the cached book (no rebuild, reload or resize).
        CharacterPage.Opt("-Disabled")
        DestroyScaledMenu(dialog)
        if DllCall("IsWindow", "Ptr", CharacterPage.Hwnd)
            CharacterPage.Show("Restore")
    }
    return outcome.Species
}

CloseOriginalCharacterSpeciesDialog(dialog, *)
{
    global CharacterPage
    ; An owned modal must re-enable its owner BEFORE being hidden.
    ; Otherwise Windows activates the launcher behind the Character Book,
    ; making Manage Characters seem to minimize on confirmation.
    CharacterPage.Opt("-Disabled")
    dialog.Hide()
}

ConfirmOriginalCharacterSpecies(dialog, selected, outcome, *)
{
    species := NormalizeCharacterSpecies(selected.Text)
    if species = ""
    {
        MsgBox("Choose your original character's actual race.", "Race required", "Icon!")
        return
    }
    outcome.Species := species
    CloseOriginalCharacterSpeciesDialog(dialog)
}

; Copy the accepted image only when Save/Add is confirmed. Original paths are
; not stored in settings; a private, generated filename survives app updates.
InstallOriginalCharacterPortrait(source)
{
    ; Save every new OC portrait as a centered, high-quality 512x512 PNG.
    ; Cropping/resizing is silent; only unreadable files raise an error.
    if !IsValidOriginalCharacterImage(source)
        throw Error("The selected image is not readable or exceeds the image limits.")
    filename := NewLauncherFileId() ".png"
    target := GetCustomPortraitPath(filename)
    DirCreate(AppDataDirectory "\portraits")
    temporary := target ".tmp"

    image := 0, resized := 0, graphics := 0
    try
    {
        if DllCall("gdiplus\GdipLoadImageFromFile", "WStr", source,
            "Ptr*", &image, "Int") != 0 || !image
            throw Error("Could not open the selected image.")

        width := 0, height := 0
        if DllCall("gdiplus\GdipGetImageWidth", "Ptr", image,
            "UInt*", &width, "Int") != 0
            || DllCall("gdiplus\GdipGetImageHeight", "Ptr", image,
            "UInt*", &height, "Int") != 0
            throw Error("Could not read the image dimensions.")
        if width < 1 || height < 1 || width > 16384 || height > 16384
            || width * height > 67108864
            throw Error("The image dimensions are not supported.")

        ; 32bpp ARGB preserves transparent backgrounds, unlike a GDI bitmap.
        if DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 512,
            "Int", 512, "Int", 0, "Int", 0x26200A, "Ptr", 0,
            "Ptr*", &resized, "Int") != 0 || !resized
            throw Error("Could not allocate the portrait image.")
        if DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", resized,
            "Ptr*", &graphics, "Int") != 0 || !graphics
            throw Error("Could not prepare the portrait image.")
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", graphics, "Int", 7)
        DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", graphics, "Int", 4)
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", graphics, "UInt", 0)
        side := Min(width, height)
        left := Floor((width - side) / 2)
        top := Floor((height - side) / 2)
        if DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", graphics,
            "Ptr", image, "Int", 0, "Int", 0, "Int", 512, "Int", 512,
            "Int", left, "Int", top, "Int", side, "Int", side,
            "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Int") != 0
            throw Error("Could not resize the portrait.")

        ; Free the graphics context before encoding; GDI+ owns the bitmap.
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        graphics := 0
        pngEncoder := Buffer(16, 0)
        if DllCall("ole32\CLSIDFromString",
            "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}",
            "Ptr", pngEncoder, "Int") != 0
            throw Error("PNG encoding is unavailable.")
        if DllCall("gdiplus\GdipSaveImageToFile", "Ptr", resized,
            "WStr", temporary, "Ptr", pngEncoder, "Ptr", 0, "Int") != 0
            throw Error("Could not save the resized portrait.")
        FileMove(temporary, target)
        return filename
    }
    finally
    {
        if graphics
            DllCall("gdiplus\GdipDeleteGraphics", "Ptr", graphics)
        if resized
            DllCall("gdiplus\GdipDisposeImage", "Ptr", resized)
        if image
            DllCall("gdiplus\GdipDisposeImage", "Ptr", image)
        if FileExist(temporary)
            try FileDelete(temporary)
    }
}

CloseProfileEditor(*)
{
    BeginInterfaceUpdate(0, "Closing character editor...")
    try HideProfileEditor()
    finally EndInterfaceUpdate()
}

UpdateEditorField(position, control, *)
{
    global EditorUpdating, EditorFields, EditorRows
    if !EditorUpdating && EditorRows[position].Key != ""
        EditorFields[EditorRows[position].Key].Value := control.Value
}

PopulateProfileEditorRows(entries)
{
    global EditorUpdating, EditorRows, EditorFields
    previousCritical := A_IsCritical
    Critical("On")
    changed := []
    EditorUpdating := true
    try
    {
        for position, row in EditorRows
        {
            entry := entries[position]
            for control in [row.Label, row.Input]
            {
                if DllCall("IsWindowVisible", "Ptr", control.Hwnd)
                {
                    changed.Push(control)
                    DllCall("SendMessageW", "Ptr", control.Hwnd, "UInt", 0xB, "Ptr", 0, "Ptr", 0)
                }
            }
            row.Key := entry[1]
            row.Label.Text := entry[2]
            row.Input.Opt(entry[1] = "Password" ? "Password" : "-Password")
            row.Input.Value := EditorFields[entry[1]].Value
        }
    }
    finally
    {
        for control in changed
        {
            DllCall("SendMessageW", "Ptr", control.Hwnd, "UInt", 0xB, "Ptr", 1, "Ptr", 0)
            DllCall("RedrawWindow", "Ptr", control.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x105)
        }
        EditorUpdating := false
        Critical(previousCritical)
    }
}

SaveProfileEditor(index, fields, *)
{
    global Profiles, SelectedProfile, MaxCharacters, EditorSpeciesDropDown, CharacterListPage
    global EditorOriginalSpecies, EditorOriginalPortraitFile, EditorOriginalPortraitSource, EditorOriginalMode
    if !index && Profiles.Length >= MaxCharacters
    {
        MsgBox("You can save up to 10 characters. Remove one before adding another.", "tes3np")
        return
    }
    name := Trim(fields["Name"].Value)
    if name = "" || fields["Password"].Value = "" || InStr(name, "`n") || InStr(name, "`r")
    {
        MsgBox("Enter a player name and password.", "tes3np")
        return
    }
    ; A modal file or race chooser may briefly affect native DDL text.
    ; The accepted OC state is independent of that display-only value.
    isOriginal := EditorOriginalMode
    species := isOriginal ? NormalizeCharacterSpecies(EditorOriginalSpecies)
        : NormalizeCharacterSpecies(EditorSpeciesDropDown.Text)
    if !index && species = ""
    {
        MsgBox("Choose a race for the new character.", "tes3np")
        return
    }
    if isOriginal && species = ""
    {
        MsgBox("Choose the actual race for this original character.", "tes3np")
        return
    }
    for key in ["UsernameDelay", "PasswordDelay", "LoadDelay"]
        if !RegExMatch(fields[key].Value, "^\d{1,3}$") || Integer(fields[key].Value) < 1 || Integer(fields[key].Value) > 300
        {
            MsgBox("Each login delay must be between 1 and 300 seconds.", "tes3np")
            return
        }
    portraitFile := "", newPortrait := ""
    if isOriginal
    {
        if EditorOriginalPortraitSource != ""
        {
            try
            {
                portraitFile := InstallOriginalCharacterPortrait(EditorOriginalPortraitSource)
                newPortrait := portraitFile
            }
            catch Error as err
            {
                reason := SanitizeDiagnosticText(err.Message)
                MsgBox("Portrait could not be saved. " (reason != "" ? reason : "Check the selected picture and folder permissions."), "tes3np", "Icon!")
                return
            }
        }
        else
        {
            portraitFile := NormalizeCustomPortraitFile(EditorOriginalPortraitFile)
            if portraitFile = "" || !FileExist(GetCustomPortraitPath(portraitFile))
            {
                MsgBox("This character's custom portrait is missing. Click Change portrait "
                    "to select a new image.", "tes3np", "Icon!")
                return
            }
        }
    }
    profile := {Name: name, Password: fields["Password"].Value, Species: species, PortraitFile: portraitFile,
        UsernameDelay: Integer(fields["UsernameDelay"].Value), PasswordDelay: Integer(fields["PasswordDelay"].Value), LoadDelay: Integer(fields["LoadDelay"].Value),
        AutoReconnect: fields["AutoReconnect"]}
    previousProfiles := Profiles.Clone()
    previousFavorite := SelectedProfile
    previousPage := CharacterListPage
    saved := false
    try
    {
        BeginInterfaceUpdate(0, "Saving character...", true)
        if index
            Profiles[index] := profile
        else
        {
            Profiles.Push(profile)
            ; The first saved character becomes the favorite automatically.
            ; No additional dialog is needed until the user picks another.
            if Profiles.Length = 1 || SelectedProfile < 1
                SelectedProfile := 1
            ; Clamp to the last measured page after adding a character.
            CharacterListPage := 1000000
        }
        try SaveProfiles()
        catch
        {
            Profiles := previousProfiles
            SelectedProfile := previousFavorite
            CharacterListPage := previousPage
            MsgBox("Could not save the character list. Check launcher data permissions.", "tes3np", "Icon!")
            return
        }
        saved := true
        UpdateCharacterMenuLabel()
        HideProfileEditor()
        RefreshProfiles()
    }
    finally
    {
        if !saved && newPortrait != ""
            try FileDelete(GetCustomPortraitPath(newPortrait))
        EndInterfaceUpdate()
    }
}

RemoveVisibleProfile(position, *)
{
    global Profiles, SelectedProfile, CharacterListPage, CharacterPage
    index := VisibleCharacterProfileIndex(position)
    if index < 1 || index > Profiles.Length
        return
    CharacterPage.Opt("+OwnDialogs")
    if MsgBox("Are you sure you want to remove " Profiles[index].Name " from your character list?", "Remove character", 0x124) != "Yes"
        return
    previousProfiles := Profiles.Clone()
    previousFavorite := SelectedProfile
    previousPage := CharacterListPage
    BeginInterfaceUpdate(0, "Removing character...", true)
    try
    {
        ; Close an open editor so its saved index cannot refer to a different character.
        HideProfileEditor()
        Profiles.RemoveAt(index)
        ; Keep exactly one favorite when the current favorite is removed.
        ; Prefer its next row, or the final row when it was last.
        SelectedProfile := SelectedProfile = index
            ? (Profiles.Length ? Min(index, Profiles.Length) : 0)
            : SelectedProfile > index ? SelectedProfile - 1 : SelectedProfile
        try SaveProfiles()
        catch
        {
            Profiles := previousProfiles
            SelectedProfile := previousFavorite
            CharacterListPage := previousPage
            MsgBox("Could not save the character list. Check launcher data permissions.", "tes3np", "Icon!")
            return
        }
        UpdateCharacterMenuLabel()
        RefreshProfiles()
    }
    finally EndInterfaceUpdate()
}

AddThemedEdit(owner, options, value := "")
{
    return owner.Add("Edit", options " BackgroundE2CEA2 c382314 -E0x200 +Border", value)
}

WipeCharacterData(*)
{
    global Profiles, SelectedProfile, CharacterListPage, CharacterPage
    if !Profiles.Length
        return
    CharacterPage.Opt("+OwnDialogs")
    if MsgBox("Remove ALL saved characters and their passwords from this launcher? This also clears your favorite and stops any active login recovery. Your in-game characters will NOT be deleted. Export Character List first if you want a backup.", "Reset Character List", 0x124) != "Yes"
        return
    previousProfiles := Profiles.Clone()
    previousFavorite := SelectedProfile
    previousPage := CharacterListPage
    BeginInterfaceUpdate(0, "Clearing saved character data...", true)
    try
    {
        StopGameRecovery()
        HideProfileEditor()
        Profiles := []
        SelectedProfile := 0
        CharacterListPage := 1
        try SaveProfiles()
        catch
        {
            Profiles := previousProfiles
            SelectedProfile := previousFavorite
            CharacterListPage := previousPage
            MsgBox("Could not save the character list. Check launcher data permissions.", "tes3np", "Icon!")
            return
        }
        UpdateCharacterMenuLabel()
        RefreshProfiles()
    }
    finally EndInterfaceUpdate()
}
