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
    global CharacterPage
    if !IsObject(CharacterPage)
        return
    previous := GetCharacterBookScale()
    if Abs(scale - previous) < 0.001
        return
    ScaleOwnedMenuContent(CharacterPage, scale)
    if CharacterPage.HasOwnProp("BookBackground")
        CharacterPage.BookBackground.Value := A_ScriptDir "\assets\backgrounds\character-book.png"
}

OpenCharacterPage(*)
{
    global CharacterPage, LauncherGui, CharacterHeading, LaunchSettingsHeading, DataTransferButton, WipeCharacterButton, CharacterDescription, AddCharacterButton, CharacterRows, BookDragStrip, CharacterLimitNotice, ButtonFaces, EditorControls, V016CharacterLayoutApplied
    global AccessibilityTextSize
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
            RefreshCachedBookTextPreference(CharacterPage)
            bookScale := GetOwnedMenuScale()
            ApplyCharacterBookScale(bookScale)
            CharacterPage.Show("Hide w" Round(960 * bookScale)
                " h" Round(650 * bookScale))
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
    CharacterPage := Gui("-Caption -Border +Owner" LauncherGui.Hwnd, "tes3np — Characters")
    CharacterPage.BackColor := "FF00FF"
    CharacterPage.BookBackground := CharacterPage.Add("Picture", "x0 y0 w960 h650",
        A_ScriptDir "\assets\backgrounds\character-book.png")
    BookDragStrip := CharacterPage.Add("Text", "x45 y25 w800 h32 BackgroundTrans +0x100")
    ; Use the same native Morrowind-style face as Launcher Settings. Keep
    ; interactive buttons in their existing button font for readability.
    SetAccessibleTextFont(CharacterPage, "s19 Norm c241408", LauncherMorrowindFont)
    CharacterHeading := CharacterPage.Add("Text", "x70 y45 w380 h30 Center BackgroundTrans", "Manage Characters")
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
    SetAccessibleTextFont(CharacterPage, "s12 Norm c241408", LauncherMorrowindFont)
    WipeCharacterButton := AddStyledButton(CharacterPage, 70, 577, 370, 25, "Wipe Character List", WipeCharacterData)
    AddStyledButton(CharacterPage, 515, 575, 90, 30, "Close", CloseCharacterPage)
    DataTransferButton := AddStyledButton(CharacterPage, 775, 575, 110, 30, "Export Data", TransferLauncherData)
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
        ApplyCharacterBookScale(bookScale)
        CharacterPage.Show("Hide w" Round(960 * bookScale)
            " h" Round(650 * bookScale))
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
    global CharacterRows, Profiles, SelectedProfile, CharacterListPage, ButtonFaces, DataTransferButton, WipeCharacterButton, CharacterDescription, AddCharacterButton, MaxCharacters, CharacterLimitNotice, LauncherMorrowindFont
    BeginInterfaceUpdate(0, "Refreshing character list...")
    try
    {
        CharacterListPage := Max(1, Min(CharacterListPage, Max(1, Ceil(Profiles.Length / 10))))
        first := (CharacterListPage - 1) * 10 + 1
        for position, controls in CharacterRows
        {
            index := first + position - 1
            visible := index <= Profiles.Length
            controls.Tick.Visible := visible
            controls.Name.Visible := visible
            controls.Play.Visible := visible
            controls.Edit.Visible := visible
            controls.Remove.Visible := visible
            if visible
            {
                if controls.Name.Text != Profiles[index].Name
                    controls.Name.Text := Profiles[index].Name
                SetBookTick(controls.Tick, SelectedProfile = index)
            }
        }
        descriptionText := "This is a list of all your characters. You can add, edit, or delete your character details at any time. Please note that adding, editing, and deleting characters on this list does not impact them in-game!"
        CharacterDescription.Text := descriptionText
        ; Retain the original paragraph rectangle and all character row positions.
        ; Measure the wrapped text against that rectangle after the book scale
        ; is applied, so Large/Extra Large cannot paint over the first row.
        ; Use the same gap below Add character in both list states.
        actionY := Profiles.Length ? 540 : 164
        MoveStyledButton(AddCharacterButton, 70, actionY, 370, 30)
        ; Shrink the transparent hit area as well as the visible gap so it
        ; cannot cover a character checkbox after a refresh or import.
        CharacterDescription.Move(BookS(70), BookS(80), BookS(390), BookS(81))
        FitCharacterDescriptionFont(CharacterDescription, descriptionText, LauncherMorrowindFont)
        CharacterDescription.Visible := true
        transferX := Profiles.Length ? 775 : 70
        transferY := Profiles.Length ? 575 : actionY + 35
        ; Preserve the original wide Import Data layout and compact Export Data
        ; layout. MoveStyledButton updates both the native control and its painted
        ; face; do not change position or dimensions independently.
        ; Hide the existing painted face while the single transfer control moves.
        ; Otherwise its old location can remain drawn as a second (ghost) button.
        if ButtonFaces.Has(DataTransferButton.Hwnd)
        {
            transferFace := ButtonFaces[DataTransferButton.Hwnd]
            try transferFace.Control.Visible := false
            try transferFace.Label.Visible := false
        }
        MoveStyledButton(DataTransferButton, transferX, transferY, Profiles.Length ? 110 : 370, 30)
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
        DataTransferButton.Text := Profiles.Length ? "Export Data" : "Import Data"
        ; Changing the native control text does not update the separately painted
        ; Morrowind button face. Keep both layers synchronized after Import Data.
        if ButtonFaces.Has(DataTransferButton.Hwnd)
            ButtonFaces[DataTransferButton.Hwnd].Text := DataTransferButton.Text
        AddCharacterButton.Enabled := Profiles.Length < MaxCharacters
    }
    finally EndInterfaceUpdate()
}


; Keep the character-book paragraph in the approved fixed rectangle.
; Font preference supplies the requested ceiling; wrapped text is measured
; with the control's actual GDI font before selecting a size that fits.
FitCharacterDescriptionFont(control, caption, fontName)
{
    desiredSize := AccessibilityFontSize(11)
    control.GetPos(, , &controlWidth, &controlHeight)
    textWidth := Max(1, controlWidth - 4)
    textHeight := Max(1, controlHeight - 2)
    for size in RangeCharacterDescriptionSizes(desiredSize)
    {
        control.SetFont("s" size " Norm c241408", fontName)
        dc := DllCall("user32\\GetDC", "Ptr", control.Hwnd, "Ptr")
        if !dc
            return
        previous := 0
        try
        {
            font := DllCall("user32\\SendMessageW", "Ptr", control.Hwnd,
                "UInt", 0x31, "Ptr", 0, "Ptr", 0, "Ptr")
            if font
                previous := DllCall("gdi32\\SelectObject", "Ptr", dc, "Ptr", font, "Ptr")
            bounds := Buffer(16, 0)
            NumPut("Int", 0, "Int", 0, "Int", textWidth, "Int", 0, bounds)
            ; DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX.
            DllCall("user32\\DrawTextW", "Ptr", dc, "WStr", caption, "Int", -1,
                "Ptr", bounds, "UInt", 0xC10)
            if NumGet(bounds, 12, "Int") <= textHeight
                return
        }
        finally
        {
            if previous
                DllCall("gdi32\\SelectObject", "Ptr", dc, "Ptr", previous, "Ptr")
            DllCall("user32\\ReleaseDC", "Ptr", control.Hwnd, "Ptr", dc)
        }
    }
}

RangeCharacterDescriptionSizes(desiredSize)
{
    sizes := []
    Loop Max(1, desiredSize - 7 + 1)
        sizes.Push(desiredSize - A_Index + 1)
    return sizes
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
    EditProfile((CharacterListPage - 1) * 10 + position)
}

ChooseProfile(position, control, *)
{
    global Profiles, SelectedProfile, CharacterListPage, CharacterPage, DataFile
    index := (CharacterListPage - 1) * 10 + position
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
    BeginInterfaceUpdate(0, "Loading character settings...", true)
    try
    {
        profile := index ? Profiles[index] : NewCharacterProfile()
        LaunchSettingsHeading.Text := index ? "Editing " profile.Name : "Add New Character"
        LaunchSettingsHeading.Visible := true
        HideMacroBookPanel()
        SetAccessibleTextFont(CharacterPage, "s10 c382314", "Segoe UI")
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
        UpdateOriginalSpeciesHint()
    }
    finally EndInterfaceUpdate()
}

; Build once while the book is hidden; later actions only populate these controls.

CreateProfileEditor()
{
    global CharacterPage, EditorControls, EditorRows, EditorSaveButton, EditorSpeciesDropDown, EditorOCSpeciesHint, EditorReconnectTick
    SetAccessibleTextFont(CharacterPage, "s10 c382314", "Segoe UI")
    EditorRows := []
    Loop 5
    {
        position := A_Index
        ; Keep the five editable fields evenly spaced.
        y := 100 + (position - 1) * 50
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
    SetAccessibleTextFont(CharacterPage, "s10 c382314", "Segoe UI")
    speciesLabel := AddBookLabel(CharacterPage, 525, 351, 355, 22, "Race")
    speciesOptions := ["Select race..."]
    for item in CharacterSpeciesOptions()
        speciesOptions.Push(item)
    speciesOptions.Push("Original Character")
    EditorSpeciesDropDown := CharacterPage.Add("DropDownList",
        "x525 y376 w355 h240 Choose1 Hidden BackgroundE2CEA2 c382314", speciesOptions)
    EditorSpeciesDropDown.OnEvent("Change", (*) => ChooseOriginalCharacterPortrait(EditorSpeciesDropDown))
    SetAccessibleTextFont(CharacterPage, "s9 c382314", "Segoe UI")
    ; The old hint overlapped the DDL's collapsed native control (y376..~402),
    ; so its text could remain invisible until the book was reconstructed.
    EditorOCSpeciesHint := CharacterPage.Add("Text",
        "x525 y407 w355 h19 Hidden BackgroundTrans c382314 +0x100", "")
    ; A selected DDL item cannot trigger Change twice: allow editing an OC
    ; by clicking the persistent race line without changing the layout.
    EditorOCSpeciesHint.OnEvent("Click", (*) => ChooseOriginalCharacterPortrait(EditorSpeciesDropDown, true))
    SetAccessibleTextFont(CharacterPage, "s10 c382314", "Segoe UI")
    EditorControls.Push(speciesLabel, EditorSpeciesDropDown, EditorOCSpeciesHint)
    EditorReconnectTick := AddBookTick(CharacterPage, 525, 435, ToggleEditorReconnect)
    reconnectLabel := AddBookLabel(CharacterPage, 551, 432, 329, 24, "Auto reconnect on crash")
    reconnectLabel.Opt("+0x100")
    reconnectLabel.OnEvent("Click", ToggleEditorReconnect)
    EditorControls.Push(EditorReconnectTick, reconnectLabel)
    SetInterfaceLoadingText("Loading Save button...")
    EditorSaveButton := AddStyledButton(CharacterPage, 635, 465, 140, 30, "Save changes", (*) => 0)
    EditorControls.Push(EditorSaveButton)
    dismiss := AddStyledButton(CharacterPage, 685, 507, 30, 24, "X", CloseProfileEditor)
    EditorControls.Push(dismiss)
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
    global EditorOCSpeciesHint, EditorOriginalSpecies, EditorOriginalMode
    isOriginal := EditorOriginalMode
    EditorOCSpeciesHint.Text := isOriginal && EditorOriginalSpecies != ""
        ? "Race: " EditorOriginalSpecies "  |  Change portrait" : ""
    EditorOCSpeciesHint.Visible := isOriginal && EditorOriginalSpecies != ""
    ; The race must be visible as soon as the dialog closes, even when the
    ; cached Character Book is reused without reopening Manage Characters.
    if IsObject(EditorOCSpeciesHint)
    {
        DllCall("RedrawWindow", "Ptr", EditorOCSpeciesHint.Hwnd, "Ptr", 0,
            "Ptr", 0, "UInt", 0x105)
    }
}

ChooseOriginalCharacterPortrait(control, replaceOC := false)
{
    global EditorPreviousSpeciesChoice, EditorOriginalPortraitSource
    global EditorOriginalPortraitFile, EditorOriginalSpecies, EditorOriginalMode

    if !replaceOC && control.Text != "Original Character"
    {
        EditorPreviousSpeciesChoice := control.Value
        EditorOriginalPortraitSource := ""
        EditorOriginalPortraitFile := ""
        EditorOriginalSpecies := ""
        EditorOriginalMode := false
        UpdateOriginalSpeciesHint()
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
    UpdateOriginalSpeciesHint()
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
    SetAccessibleTextFont(dialog, "s10 c382314", "Segoe UI")
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
            CharacterListPage := Ceil(Profiles.Length / 10)
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
    index := (CharacterListPage - 1) * 10 + position
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
    if MsgBox("Remove ALL saved characters and their passwords from this launcher? This also clears your favorite and stops any active login recovery. Your in-game characters will NOT be deleted. Export Data first if you want a backup.", "Wipe Character Data", 0x124) != "Yes"
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
