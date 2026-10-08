; Character book, profile editor and launch explanation dialog.

OpenCharacterPage(*)
{
    global CharacterPage, LauncherGui, CharacterHeading, LaunchSettingsHeading, LaunchSettingsControls, DataTransferButton, WipeCharacterButton, CharacterDescription, CharacterDescriptionMagic, LaunchCharacterButton, SessionStatus, AddCharacterButton, CharacterRows, ExecutableInput, BookDragStrip, CharacterLimitNotice, ButtonFaces, EditorControls, V016DailyLoginControls, V016CharacterLayoutApplied
    if IsObject(CharacterPage)
    {
        PrepareWindowDisplay(CharacterPage)
        CharacterPage.Show()
        RevealWindowDisplay(CharacterPage, true)
        return
    }
    SetInterfaceLoadingText("Loading saved characters...")
    LoadProfiles()
    SetInterfaceLoadingText("Building character menu...")
    ; A rebuilt book must start with fresh control collections. The previous
    ; GUI's controls are destroyed with the window, but AHK arrays still retain
    ; those object references unless explicitly cleared.
    CharacterRows := []
    LaunchSettingsControls := []
    EditorControls := []
    V016DailyLoginControls := []
    ; The previous CharacterPage was destroyed when leaving the scheduler, so
    ; the v0.1.16 layout hook must run again for this fresh GUI. Otherwise its
    ; one-time guard skips recreating the Schedule Event button.
    V016CharacterLayoutApplied := false
    CharacterPage := Gui("-Caption -Border +Owner" LauncherGui.Hwnd, "tes3np — Characters")
    CharacterPage.BackColor := "FF00FF"
    CharacterPage.Add("Picture", "x0 y0 w960 h650", A_ScriptDir "\assets\backgrounds\character-book.png")
    BookDragStrip := CharacterPage.Add("Text", "x45 y25 w800 h32 BackgroundTrans +0x100")
    ; Use the same native Morrowind-style face as Launcher Settings. Keep
    ; interactive buttons in their existing button font for readability.
    CharacterPage.SetFont("s19 Norm c241408", LauncherMorrowindFont)
    CharacterHeading := CharacterPage.Add("Text", "x70 y45 w380 h30 Center BackgroundTrans", "Your Characters")
    LaunchSettingsHeading := CharacterPage.Add("Text", "x525 y45 w360 h30 Center BackgroundTrans", "Launch Settings")
    CharacterPage.SetFont("s12 Norm c241408", LauncherMorrowindFont)
    AddCharacterButton := AddStyledButton(CharacterPage, 70, 475, 370, 30, "Add character", (*) => EditProfile(0))
    CharacterPage.SetFont("s12 Norm c241408", LauncherMorrowindFont)
    CharacterDescription := CharacterPage.Add("Text", "x70 y80 w390 h165 BackgroundTrans", "")
    CharacterDescriptionMagic := false
    Loop 10
    {
        CharacterPage.SetFont("s12 Norm c241408", LauncherMorrowindFont)
        index := A_Index
        ; Leave breathing room below the character description so its final line cannot overlap the list.
        y := 240 + (index - 1) * 24
        SetInterfaceLoadingText("Loading character checkbox " index "...")
        tick := AddBookTick(CharacterPage, 70, y + 2, ChooseProfile.Bind(index))
        SetInterfaceLoadingText("Loading character name " index "...")
        name := AddBookLabel(CharacterPage, 95, y, 140, 23, "")
        SetInterfaceLoadingText("Loading Play button " index "...")
        play := AddStyledButton(CharacterPage, 240, y, 55, 22, "Play", PlayVisibleProfile.Bind(index))
        SetInterfaceLoadingText("Loading Edit button " index "...")
        edit := AddStyledButton(CharacterPage, 300, y, 60, 22, "Edit", EditVisibleProfile.Bind(index))
        SetInterfaceLoadingText("Loading Remove button " index "...")
        remove := AddStyledButton(CharacterPage, 370, y, 70, 22, "Remove", RemoveVisibleProfile.Bind(index))
        CharacterRows.Push({Tick: tick, Name: name, Play: play, Edit: edit, Remove: remove})
    }
    CharacterPage.SetFont("s12 Norm c241408", LauncherMorrowindFont)
    CharacterLimitNotice := AddBookLabel(CharacterPage, 70, 435, 370, 25, "* You have reached the server character limit.")
    ButtonFaces[CharacterLimitNotice.Hwnd].TextColor := 0x0000FF
    CharacterLimitNotice.Visible := false
    CharacterPage.SetFont("s12 Norm c241408", LauncherMorrowindFont)
    executableLabel := CharacterPage.Add("Text", "x525 y110 w360 h22 BackgroundTrans", "TES3MP executable")
    CharacterPage.SetFont("s12 Norm c241408", LauncherMorrowindFont)
    SetInterfaceLoadingText("Loading executable field...")
    ExecutableInput := AddThemedEdit(CharacterPage, "x525 y137 w270", GetSharedExecutable())
    ExecutableInput.OnEvent("Change", SaveSharedExecutable)
    SetInterfaceLoadingText("Loading Browse button...")
    ExecutableInput.GetPos(, &executableY, , &executableHeight)
    browse := AddStyledButton(CharacterPage, 805, executableY, 80, executableHeight, "Browse", BrowseSharedExecutable)
    LaunchSettingsControls := [executableLabel, ExecutableInput, browse]
    SessionStatus := CharacterPage.Add("Text", "x70 y555 w370 h50 Hidden", "")
    SetInterfaceLoadingText("Loading Launch button...")
    LaunchCharacterButton := AddStyledButton(CharacterPage, 70, 510, 370, 30, "Launch character", LaunchProfile)
    WipeCharacterButton := AddStyledButton(CharacterPage, 70, 577, 370, 25, "Wipe Character List", WipeCharacterData)
    AddStyledButton(CharacterPage, 515, 575, 90, 30, "Close", CloseCharacterPage)
    DataTransferButton := AddStyledButton(CharacterPage, 775, 575, 110, 30, "Export Data", TransferLauncherData)
    CharacterPage.OnEvent("Close", CloseCharacterPage)
    CharacterPage.OnEvent("Escape", CloseCharacterPage)
    SetInterfaceLoadingText("Loading character editor... ")
    CreateProfileEditor()
    HideProfileEditor()
    ; Build the one-time Character Book refinements explicitly now that all base
    ; controls exist. This replaces the old 250 ms polling timer without losing
    ; the Scheduled Events button on a freshly created book.
    ApplyV016CharacterLayout()
    RefreshProfiles()
    PrepareWindowDisplay(CharacterPage)
    CharacterPage.Show("w960 h650")
    RevealWindowDisplay(CharacterPage, true)
}

RefreshProfiles()
{
    global CharacterRows, Profiles, SelectedProfile, CharacterListPage, ButtonFaces, DataTransferButton, WipeCharacterButton, CharacterDescription, CharacterDescriptionMagic, LaunchCharacterButton, AddCharacterButton, MaxCharacters, CharacterLimitNotice, V016DailyLoginControls
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
        descriptionText := Profiles.Length
            ? "This is a list containing all of your registered Nerevarine Prophecies characters. From here you can add or delete up to 10 characters. Click on the checkbox before a characters name to favorite it. When you favorite a character, that sets you up for quick launching the game, and logging yourself in for schedualed events automatically. You can change your favorite character anytime."
            : "This will be a list of all your Nerevarine Prophecies characters. From here, you will be able to launch your characters automatically with optional crash recovery and much more."
        CharacterDescription.Text := descriptionText
        ; Keep functional description text on the bundled Mystic Cards TTF. The
        ; vanilla bitmap renderer is intentionally not used for long paragraphs.
        if IsObject(CharacterDescriptionMagic)
            CharacterDescriptionMagic.Visible := false
        CharacterDescriptionMagic := false
        CharacterDescription.Text := descriptionText
        CharacterDescription.Visible := true
        ; Keep the character action stack in one canonical layout. The v0.1.16
        ; refinement creates Daily Login after this window is built, so refreshes
        ; (including Import Data) must preserve that layout instead of restoring
        ; the older button positions.
        ; Match the canonical v0.1.16 character-book action layout after every
        ; refresh/import. Import previously restored an older Y-position set,
        ; making the three left-page buttons jump upward until the page reopened.
        actionY := Profiles.Length ? 505 : 185
        MoveStyledButton(AddCharacterButton, 70, actionY, 370, 30)
        CharacterDescription.Move(70, 80, 390, Profiles.Length ? 165 : 90)
        ; Individual characters already have Play buttons in their rows. Keep the
        ; legacy full-width Launch Character button hidden; showing it here after
        ; an import overlaps Daily Login and the action stack.
        LaunchCharacterButton.Visible := false
        transferX := Profiles.Length ? 775 : 70
        transferY := Profiles.Length ? 575 : 225
        ; Preserve the original wide Import Data layout and compact Export Data
        ; layout. MoveStyledButton updates both the native control and its painted
        ; face; do not change position or dimensions independently.
        MoveStyledButton(DataTransferButton, transferX, transferY, Profiles.Length ? 110 : 370, 30)
        WipeCharacterButton.Visible := Profiles.Length > 0
        if Profiles.Length > 0
        {
            ; Daily Login sits directly below Add Character.
            if IsObject(V016DailyLoginControls) && V016DailyLoginControls.Length
            {
                dailyButton := V016DailyLoginControls[1]
                MoveStyledButton(dailyButton, 70, 540, 370, 30)
            }
            MoveStyledButton(WipeCharacterButton, 70, 575, 370, 30)
        }
        CharacterLimitNotice.Visible := Profiles.Length >= MaxCharacters
        DataTransferButton.Text := Profiles.Length ? "Export Data" : "Import Data"
        ; Changing the native control text does not update the separately painted
        ; Morrowind button face. Keep both layers synchronized after Import Data.
        if ButtonFaces.Has(DataTransferButton.Hwnd)
            ButtonFaces[DataTransferButton.Hwnd].Text := DataTransferButton.Text
        if IsObject(V016DailyLoginControls)
            for control in V016DailyLoginControls
                control.Visible := Profiles.Length > 0
        AddCharacterButton.Enabled := Profiles.Length < MaxCharacters
        LaunchCharacterButton.Text := SelectedProfile ? "Launch " Profiles[SelectedProfile].Name : "Launch character"
        LaunchCharacterButton.Enabled := SelectedProfile > 0
    }
    finally EndInterfaceUpdate()
}

MoveStyledButton(control, x, y, width, height)
{
    global ButtonFaces
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
    global SelectedProfile, CharacterListPage
    index := (CharacterListPage - 1) * 10 + position
    SelectedProfile := SelectedProfile = index ? 0 : index
    SaveDefaultProfile()
    RefreshProfiles()
}

HideProfileEditor()
{
    global EditorControls, EditorScrolling, LaunchSettingsHeading, LaunchSettingsControls
    EditorScrolling := false
    ; EditorControls/LaunchSettingsControls can still reference controls from a
    ; CharacterPage that was deliberately destroyed during a book-page rebuild.
    ; Ignore those stale handles; OpenCharacterPage will populate fresh controls.
    for control in EditorControls
        try control.Visible := false
    try LaunchSettingsHeading.Text := "Launch Settings"
    for control in LaunchSettingsControls
        try control.Visible := true
}

CloseCharacterPage(*)
{
    global CharacterPage, ScheduledEventsBookMode
    ; If Close is pressed while the shared Character Book is showing the
    ; scheduler, restore the actual Characters page before hiding the book.
    ; Otherwise the next Manage Characters open simply re-shows the scheduler
    ; controls because the same CharacterPage is being reused.
    if ScheduledEventsBookMode
        CloseScheduledEventsBook()
    HideProfileEditor()
    CharacterPage.Hide()
    ShowLauncherWindow()
}

EditProfile(index, *)
{
    global Profiles, CharacterPage, MaxCharacters, EditorControls, EditorReconnectTick, LaunchSettingsHeading, LaunchSettingsControls
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
        for control in LaunchSettingsControls
            control.Visible := false
        editor := CharacterPage
        editor.SetFont("s10 c382314", "Segoe UI")
        global EditorFields, EditorRows, EditorEntries, EditorOffset, EditorTrack, EditorThumb, EditorUpdating
        EditorEntries := [["Name", "Username", profile.Name], ["Password", "Password", profile.Password],
            ["UsernameDelay", "Username screen delay (sec)", profile.UsernameDelay],
            ["PasswordDelay", "Password screen delay (sec)", profile.PasswordDelay],
            ["LoadDelay", "Character loading delay (sec)", profile.LoadDelay]]
        EditorFields := Map()
        for entry in EditorEntries
            EditorFields[entry[1]] := {Value: entry[3]}
        EditorUpdating := true
        for row in EditorRows
            row.Key := ""
        EditorOffset := 0
        SetBookTick(EditorReconnectTick, profile.AutoReconnect)
        ScrollEditorRows(0)
        global EditorSaveButton, ButtonFaces
        EditorSaveButton.Text := index ? "Save changes" : "Add character"
        ButtonFaces[EditorSaveButton.Hwnd].LoadingText := "Saving character..."
        ButtonFaces[EditorSaveButton.Hwnd].Action := SaveProfileEditor.Bind(index, EditorFields, editor)
        for control in EditorControls
            control.Visible := true
        EditorTrack.Visible := false
        EditorThumb.Visible := false
    }
    finally EndInterfaceUpdate()
}

; Build once while the book is hidden; later actions only populate these controls.

CreateProfileEditor()
{
    global CharacterPage, EditorControls, EditorRows, EditorTrack, EditorThumb, EditorSaveButton, EditorReconnectTick
    CharacterPage.SetFont("s10 c382314", "Segoe UI")
    EditorRows := []
    Loop 5
    {
        position := A_Index
        y := 110 + (position - 1) * 54
        SetInterfaceLoadingText("Loading setting label " position "...")
        label := AddBookLabel(CharacterPage, 525, y, 355, 22, "")
        SetInterfaceLoadingText("Loading setting field " position "...")
        input := AddThemedEdit(CharacterPage, "x525 y" (y + 23) " w355 h25 Hidden")
        input.OnEvent("Change", UpdateEditorField.Bind(position))
        EditorRows.Push({Label: label, Input: input, Key: ""})
        EditorControls.Push(label)
        EditorControls.Push(input)
    }
    SetInterfaceLoadingText("Loading settings scrollbar...")
    EditorTrack := CharacterPage.Add("Text", "x890 y210 w7 h213 Hidden Background704C27 +0x100")
    EditorThumb := CharacterPage.Add("Text", "x890 y210 w7 h110 Hidden BackgroundC69951 +0x100")
    SetInterfaceLoadingText("Loading auto reconnect setting...")
    EditorReconnectTick := AddBookTick(CharacterPage, 525, 400, ToggleEditorReconnect)
    reconnectLabel := AddBookLabel(CharacterPage, 550, 397, 330, 24, "Auto reconnect on close or crash")
    EditorControls.Push(EditorReconnectTick, reconnectLabel)
    SetInterfaceLoadingText("Loading Save button...")
    EditorSaveButton := AddStyledButton(CharacterPage, 635, 465, 140, 30, "Save changes", (*) => 0)
    EditorControls.Push(EditorTrack)
    EditorControls.Push(EditorThumb)
    EditorControls.Push(EditorSaveButton)
    dismiss := AddStyledButton(CharacterPage, 685, 507, 30, 24, "X", CloseProfileEditor)
    EditorControls.Push(dismiss)
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

ToggleEditorReconnect(*)
{
    global EditorReconnectTick, ButtonFaces
    SetBookTick(EditorReconnectTick, !ButtonFaces[EditorReconnectTick.Hwnd].Checked)
}

ScrollEditorRows(offset)
{
    global EditorOffset, EditorUpdating, EditorRows, EditorEntries, EditorFields, EditorThumb
    ; These five rows already exist: scrolling only swaps their displayed values.
    ; Redraw the changed fields locally instead of rebuilding or covering the book.
    previousCritical := A_IsCritical
    Critical("On")
    changed := []
    EditorUpdating := true
    try
    {
        EditorOffset := 0
        first := 1
        for position, row in EditorRows
        {
            entry := EditorEntries[first + position - 1]
            if row.Key = entry[1]
                continue
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
        EditorThumb.Move(890, 210 + Round(EditorOffset / 54 * 103))
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

ScrollEditorWheel(wParam)
{
    global CharacterPage, EditorTrack, EditorOffset
    if !IsObject(CharacterPage) || !IsSet(EditorTrack) || !EditorTrack.Visible
        return false
    MouseGetPos(&x, &y, &window)
    if window != CharacterPage.Hwnd
        return false
    point := Buffer(8, 0)
    NumPut("Int", x, "Int", y, point)
    DllCall("ScreenToClient", "Ptr", CharacterPage.Hwnd, "Ptr", point)
    scale := A_ScreenDPI / 96
    x := NumGet(point, 0, "Int") / scale
    y := NumGet(point, 4, "Int") / scale
    if x < 520 || x > 905 || y < 200 || y > 445
        return false
    delta := (wParam >> 16) << 48 >> 48
    ScrollEditorRows(EditorOffset + (delta > 0 ? -54 : 54))
    return true
}

PressEditorScroll(hwnd)
{
    global EditorTrack, EditorThumb, EditorScrolling, EditorGrab, EditorOffset, CharacterPage
    if !IsSet(EditorTrack) || !EditorTrack.Visible || (hwnd != EditorTrack.Hwnd && hwnd != EditorThumb.Hwnd)
        return false
    MouseGetPos(, &y)
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", CharacterPage.Hwnd, "Ptr", origin)
    localY := (y - NumGet(origin, 4, "Int")) / (A_ScreenDPI / 96)
    EditorGrab := hwnd = EditorThumb.Hwnd ? localY - (210 + Round(EditorOffset / 54 * 103)) : 55
    EditorScrolling := true
    DllCall("SetCapture", "Ptr", hwnd)
    DragEditorScroll()
    return true
}

DragEditorScroll()
{
    global EditorScrolling, EditorGrab, CharacterPage
    if !IsSet(EditorScrolling) || !EditorScrolling
        return
    MouseGetPos(, &y)
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", CharacterPage.Hwnd, "Ptr", origin)
    localY := (y - NumGet(origin, 4, "Int")) / (A_ScreenDPI / 96)
    ScrollEditorRows(Round((localY - 210 - EditorGrab) / 103 * 54))
}

ReleaseEditorScroll()
{
    global EditorScrolling
    if !IsSet(EditorScrolling) || !EditorScrolling
        return false
    EditorScrolling := false
    DllCall("ReleaseCapture")
    return true
}

BrowseSharedExecutable(*)
{
    global ExecutableInput
    path := FileSelect(1, , "Select tes3mp.exe", "Applications (*.exe)")
    if path != ""
    {
        ExecutableInput.Value := path
        SaveSharedExecutable()
    }
}

SaveProfileEditor(index, fields, editor, *)
{
    global Profiles, SelectedProfile, MaxCharacters, EditorReconnectTick, ButtonFaces
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
    for key in ["UsernameDelay", "PasswordDelay", "LoadDelay"]
        if !RegExMatch(fields[key].Value, "^\d+$") || Integer(fields[key].Value) < 1 || Integer(fields[key].Value) > 300
        {
            MsgBox("Each login delay must be between 1 and 300 seconds.", "tes3np")
            return
        }
    profile := {Name: name, Password: fields["Password"].Value,
        UsernameDelay: Integer(fields["UsernameDelay"].Value), PasswordDelay: Integer(fields["PasswordDelay"].Value), LoadDelay: Integer(fields["LoadDelay"].Value),
        AutoReconnect: ButtonFaces[EditorReconnectTick.Hwnd].Checked}
    BeginInterfaceUpdate(0, "Saving character...", true)
    try
    {
        if index
            Profiles[index] := profile
        else
        {
            Profiles.Push(profile)
            global CharacterListPage
            CharacterListPage := Ceil(Profiles.Length / 10)
        }
        SaveProfiles()
        HideProfileEditor()
        RefreshProfiles()
    }
    finally EndInterfaceUpdate()
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
    BeginInterfaceUpdate(0, "Removing character...", true)
    try
    {
        ; Close an open editor so its saved index cannot refer to a different character.
        HideProfileEditor()
        Profiles.RemoveAt(index)
        SelectedProfile := SelectedProfile = index ? 0 : SelectedProfile > index ? SelectedProfile - 1 : SelectedProfile
        SaveProfiles()
        RefreshProfiles()
    }
    finally EndInterfaceUpdate()
}

ShowLaunchAllExplanation()
{
    global CharacterPage, DataFile
    result := {Accepted: false}
    dialog := Gui("+Owner" CharacterPage.Hwnd " -MinimizeBox -MaximizeBox", "Launch All & Close")
    dialog.BackColor := "E2CEA2"
    dialog.SetFont("s10 c382314", "Segoe UI")
    dialog.Add("Text", "x20 y20 w420 h125", "This option launches each character one by one, waits 10 seconds after loading, then closes that game client. It’s useful for collecting daily login points on characters you don’t usually play every day. The launcher stays open when the list is finished.")
    remember := dialog.Add("Checkbox", "x20 y150 w420 h25", "Don't show me this again")
    launch := dialog.Add("Button", "x225 y190 w100 h30 Default", "Launch all")
    cancel := dialog.Add("Button", "x340 y190 w100 h30", "Cancel")
    launch.OnEvent("Click", AcceptLaunchAllExplanation.Bind(dialog, remember, result))
    cancel.OnEvent("Click", (*) => dialog.Hide())
    dialog.OnEvent("Close", (*) => dialog.Hide())
    dialog.OnEvent("Escape", (*) => dialog.Hide())
    CharacterPage.Opt("+Disabled")
    try
    {
        dialog.Show("w460 h240")
        WinWaitClose("ahk_id " dialog.Hwnd)
    }
    finally
    {
        CharacterPage.Opt("-Disabled")
        dialog.Destroy()
    }
    return result.Accepted
}

AcceptLaunchAllExplanation(dialog, remember, result, *)
{
    global DataFile
    if remember.Value
    {
        DirCreate(AppDataDirectory)
        IniWrite("1", DataFile, "Launcher", "HideLaunchAllExplanation")
    }
    result.Accepted := true
    dialog.Hide()
}

AddThemedEdit(owner, options, value := "")
{
    return owner.Add("Edit", options " BackgroundE2CEA2 c382314 -E0x200 +Border", value)
}

WipeCharacterData(*)
{
    global Profiles, SelectedProfile, CharacterListPage, CharacterPage, Client
    if !Profiles.Length
        return
    CharacterPage.Opt("+OwnDialogs")
    if MsgBox("Remove ALL saved characters and their passwords from this launcher? This also clears your favorite and stops any active recovery or launch-all sequence. Your in-game characters will NOT be deleted. Export Data first if you want a backup.", "Wipe Character Data", 0x124) != "Yes"
        return
    BeginInterfaceUpdate(0, "Clearing saved character data...", true)
    try
    {
        StopClient()
        Client.Profile := 0
        if Client.HasOwnProp("Queue")
            Client.Queue := 0
        HideProfileEditor()
        Profiles := []
        SelectedProfile := 0
        CharacterListPage := 1
        SaveProfiles()
        RefreshProfiles()
    }
    finally EndInterfaceUpdate()
}
