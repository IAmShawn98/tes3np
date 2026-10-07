; Multi-event scheduler. Daily Login is the first supported scheduled action.
; Events recur once per day at their configured local clock time.

global ScheduledEvents := []
global ScheduledEventsListView := 0
global ScheduledEventsWindow := 0
global ActiveScheduledEventId := ""
global NextScheduledEventId := 1
global ScheduledCountdownHotkey := "F8"
global ScheduledCountdownArmedEventId := ""
global ScheduledEventsBookControls := []
global ScheduledEventsBookRows := []
global ScheduledEventsBookMode := false
global ScheduledEventsBookHiddenControls := []
global ScheduledEventsBookCharacterHeadingText := ""


LoadDailyLoginSchedule()
{
    global ScheduledEvents, NextScheduledEventId, DataFile
    ScheduledEvents := []
    count := Integer(IniRead(DataFile, "ScheduledEvents", "Count", "0"))
    maxId := 0
    Loop count
    {
        section := "ScheduledEvent" A_Index
        id := Integer(IniRead(DataFile, section, "Id", A_Index))
        name := IniRead(DataFile, section, "Name", "Daily Login")
        timeBasis := "IRL"
        time := IniRead(DataFile, section, "Time", "12:00")
        lastRun := IniRead(DataFile, section, "LastRunDate", "")
        recurring := IniRead(DataFile, section, "Recurring", "1") = "1"
        locked := IniRead(DataFile, section, "Locked", "0") = "1"
        armed := IniRead(DataFile, section, "Armed", "0") = "1"
        completed := IniRead(DataFile, section, "Completed", "0") = "1"
        mode := IniRead(DataFile, section, "Mode", "IRL")
        durationSeconds := Integer(IniRead(DataFile, section, "DurationSeconds", "0"))
        startedAt := IniRead(DataFile, section, "StartedAt", "")
        try time := ParseDailyLoginTime(time)
        catch
            continue
        ScheduledEvents.Push({Id: id, Name: name, TimeBasis: timeBasis, Time: time, Mode: mode, DurationSeconds: durationSeconds, StartedAt: startedAt, Recurring: recurring, Locked: locked, Armed: armed, Completed: completed, LastRunDate: lastRun, Due: false, PreviousRemaining: mode = "Countdown" && startedAt = "" ? 1 : GetScheduledEventRawRemaining(time, timeBasis)})
        maxId := Max(maxId, id)
    }

    ; Migrate the old single Daily Login schedule once.
    if !ScheduledEvents.Length && IniRead(DataFile, "DailyLogin", "Scheduled", "0") = "1"
    {
        oldTime := IniRead(DataFile, "DailyLogin", "Time", "12:00")
        oldLastRun := IniRead(DataFile, "DailyLogin", "LastRunDate", "")
        try oldTime := ParseDailyLoginTime(oldTime)
        catch
            oldTime := "12:00"
        ScheduledEvents.Push({Id: 1, Name: "Daily Login", TimeBasis: "IRL", Time: oldTime, Recurring: true, Completed: false, LastRunDate: oldLastRun, Due: false, PreviousRemaining: GetScheduledEventRawRemaining(oldTime, "IRL")})
        IniWrite("0", DataFile, "DailyLogin", "Scheduled")
        maxId := 1
        SaveScheduledEvents()
    }
    NextScheduledEventId := maxId + 1
    LoadScheduledCountdownHotkey()
    global ScheduledCountdownArmedEventId
    for event in ScheduledEvents
    {
        if event.HasOwnProp("Armed") && event.Armed && !(event.HasOwnProp("Locked") && event.Locked)
        {
            ScheduledCountdownArmedEventId := event.Id
            break
        }
    }
    ; Preserve the previous launch timestamp before updating it. This provides
    ; a reliable missed-event window even after abnormal exits where cleanup
    ; never had a chance to save LastLauncherExit.
    previousSeen := IniRead(DataFile, "ScheduledEvents", "LastLauncherSeen", "")
    if RegExMatch(previousSeen, "^\d{14}$")
        IniWrite(previousSeen, DataFile, "ScheduledEvents", "LastLauncherExit")
    IniWrite(A_Now, DataFile, "ScheduledEvents", "LastLauncherSeen")
    SetTimer(UpdateDailyLoginCountdown, 1000)
}

ParseDailyLoginTime(value)
{
    value := Trim(value)
    compact := RegExReplace(StrLower(value), "\s+", "")
    compact := StrReplace(compact, ".", "")
    if compact = ""
        throw Error("Enter a time for the event.")
    if RegExMatch(compact, "^(1[0-2]|0?[1-9])(?::?([0-5]\d))?(am|pm)$", &match)
    {
        hour := Integer(match[1]), minute := match[2] = "" ? 0 : Integer(match[2])
        if match[3] = "am"
            hour := hour = 12 ? 0 : hour
        else
            hour := hour = 12 ? 12 : hour + 12
        return Format("{:02}:{:02}", hour, minute)
    }
    if RegExMatch(compact, "^(2[0-3]|[01]?\d)(?::([0-5]\d))?$", &match)
        return Format("{:02}:{:02}", Integer(match[1]), match[2] = "" ? 0 : Integer(match[2]))
    if RegExMatch(compact, "^(\d{1,2})([0-5]\d)$", &match)
    {
        hour := Integer(match[1])
        if hour <= 23
            return Format("{:02}:{:02}", hour, Integer(match[2]))
    }
    throw Error("Enter a valid event time.")
}

SaveScheduledEvents()
{
    global ScheduledEvents, DataFile, AppDataDirectory
    DirCreate(AppDataDirectory)
    oldCount := Integer(IniRead(DataFile, "ScheduledEvents", "Count", "0"))
    Loop oldCount
        try IniDelete(DataFile, "ScheduledEvent" A_Index)
    IniWrite(ScheduledEvents.Length, DataFile, "ScheduledEvents", "Count")
    for index, event in ScheduledEvents
    {
        section := "ScheduledEvent" index
        IniWrite(event.Id, DataFile, section, "Id")
        IniWrite(event.Name, DataFile, section, "Name")
        IniWrite(event.TimeBasis, DataFile, section, "TimeBasis")
        IniWrite(event.Time, DataFile, section, "Time")
        IniWrite(event.HasOwnProp("Mode") ? event.Mode : "IRL", DataFile, section, "Mode")
        IniWrite(event.HasOwnProp("DurationSeconds") ? event.DurationSeconds : 0, DataFile, section, "DurationSeconds")
        IniWrite(event.HasOwnProp("StartedAt") ? event.StartedAt : "", DataFile, section, "StartedAt")
        IniWrite(event.Recurring ? "1" : "0", DataFile, section, "Recurring")
        IniWrite(event.HasOwnProp("Locked") && event.Locked ? "1" : "0", DataFile, section, "Locked")
        IniWrite(event.HasOwnProp("Armed") && event.Armed ? "1" : "0", DataFile, section, "Armed")
        IniWrite(event.HasOwnProp("Completed") && event.Completed ? "1" : "0", DataFile, section, "Completed")
        IniWrite(event.LastRunDate, DataFile, section, "LastRunDate")
    }
}

OpenScheduledEventsMenu(owner := 0, *)
{
    ; Scheduled Events now uses the existing character book instead of a popup.
    OpenScheduledEventsBook()
}

SetBookControlVisible(control, visible)
{
    global ButtonFaces
    try control.Visible := visible
    try if ButtonFaces.Has(control.Hwnd)
    {
        face := ButtonFaces[control.Hwnd]
        if face.HasOwnProp("Control") && IsObject(face.Control)
            face.Control.Visible := visible
        if face.HasOwnProp("Label") && IsObject(face.Label)
            face.Label.Visible := visible
    }
    ; Do not synchronously redraw here. This helper runs once per control and
    ; forcing a full parent repaint for every hide/show caused a repaint loop.
}

OpenScheduledEventsBook(*)
{
    BeginInterfaceUpdate(CharacterPage, "Loading scheduled events...", true)
    try
    {
    global CharacterPage, LaunchSettingsHeading, LaunchSettingsControls, CharacterRows
    global CharacterDescription, AddCharacterButton, WipeCharacterButton, V016DailyLoginControls, LaunchCharacterButton, SessionStatus
    global DataTransferButton, CharacterLimitNotice, ScheduledEventsBookControls, ScheduledEventsBookRows
    global ScheduledEventsBookMode, LauncherMorrowindFont, ButtonFaces, ScheduledCountdownHotkey, CharacterHeading, ScheduledEventsBookHiddenControls

    if !IsObject(CharacterPage)
        return

    HideProfileEditor()
    ScheduledEventsBookMode := true

    ; Hide the normal character-book content while preserving it for Back.
    ; Reuse the existing left heading instead of drawing another heading over it.
    CharacterHeading.Text := "Schedule Event"
    ScheduledEventsBookHiddenControls := []
    HideForSchedule(control) {
        global ScheduledEventsBookHiddenControls
        try if control.Visible {
            ScheduledEventsBookHiddenControls.Push(control)
            SetBookControlVisible(control, false)
        }
    }
    HideForSchedule(CharacterDescription)
    HideForSchedule(LaunchCharacterButton)
    HideForSchedule(SessionStatus)
    HideForSchedule(AddCharacterButton)
    HideForSchedule(WipeCharacterButton)
    HideForSchedule(DataTransferButton)
    HideForSchedule(CharacterLimitNotice)
    for row in CharacterRows {
        HideForSchedule(row.Tick), HideForSchedule(row.Name), HideForSchedule(row.Play)
        HideForSchedule(row.Edit), HideForSchedule(row.Remove)
    }
    if IsObject(V016DailyLoginControls)
        for control in V016DailyLoginControls
            HideForSchedule(control)
    for control in LaunchSettingsControls
        HideForSchedule(control)

    ; Reuse the existing right heading too.
    LaunchSettingsHeading.Text := "Scheduled Events"

    CharacterPage.SetFont("s11 Norm c241408", LauncherMorrowindFont)
    description := CharacterPage.Add("Text", "x70 y90 w370 h105 BackgroundTrans",
        "Need a reminder for boss spawns, timed quests, or daily login points? Schedule countdowns, reminders, and automatic character logins. Start events manually or with an in-game hotkey. The scheduler will alert you while the launcher is open and show any missed events the next time you launch it.")

    add := AddStyledButton(CharacterPage, 70, 180, 370, 30, "Schedule New Event", (*) => OpenScheduledEventBookEditor(0))
    hotkey := AddStyledButton(CharacterPage, 70, 215, 370, 30, "Hotkey: " DisplayScheduledCountdownHotkey(ScheduledCountdownHotkey), (*) => EditScheduledCountdownHotkey(hotkey))
    back := AddStyledButton(CharacterPage, 70, 575, 370, 30, "Back to Characters", CloseScheduledEventsBook)

    ScheduledEventsBookControls := [description, add, hotkey, back]
    ScheduledEventsBookRows := []
    BuildScheduledEventsBookRows()
    FinishButtonDisplay()
    ; Transparent text added after the book is already visible may not paint until
    ; Windows later exposes/resizes the window. Invalidate the completed page once
    ; after all scheduler controls exist so the description/event text paints now.
    PaintScheduledEventsBook()
    }
    finally EndInterfaceUpdate()
}

PaintScheduledEventsBook()
{
    global CharacterPage, ScheduledEventsBookMode
    if !ScheduledEventsBookMode || !IsObject(CharacterPage)
        return
    try DllCall("InvalidateRect", "Ptr", CharacterPage.Hwnd, "Ptr", 0, "Int", true)
    try DllCall("UpdateWindow", "Ptr", CharacterPage.Hwnd)
}

BuildScheduledEventsBookRows()
{
    global CharacterPage, ScheduledEvents, ScheduledEventsBookControls, ScheduledEventsBookRows, LaunchSettingsHeading
    global LauncherMorrowindFont

    LaunchSettingsHeading.Text := "Scheduled Events"

    ; Rebuild only the right-page event rows.
    for row in ScheduledEventsBookRows
        for control in row
        {
            SetBookControlVisible(control, false)
            try control.Destroy()
        }
    ScheduledEventsBookRows := []
    try DllCall("RedrawWindow", "Ptr", CharacterPage.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)

    y := 100
    if !ScheduledEvents.Length
    {
        CharacterPage.SetFont("s11 Norm c241408", LauncherMorrowindFont)
        empty := CharacterPage.Add("Text", "x525 y110 w360 h50 Center BackgroundTrans", "No scheduled events yet.")
        ScheduledEventsBookRows.Push([empty])
        PaintScheduledEventsBook()
        return
    }

    for index, event in ScheduledEvents
    {
        if index > 7
            break
        modeText := event.StartedAt != ""
            ? FormatDailyLoginCountdown(GetScheduledEventSecondsRemaining(event))
            : (event.HasOwnProp("Mode") && event.Mode = "Countdown"
                ? FormatDailyLoginCountdown(event.DurationSeconds)
                : FormatScheduledEventTime(event.Time))
        statusText := event.StartedAt != "" ? "Running" : (event.HasOwnProp("Completed") && event.Completed ? "Completed" : "Ready")
        ; Use a clear title/details hierarchy instead of packing everything into
        ; one small text control.
        ; Event rows need stronger hierarchy/contrast than the surrounding
        ; parchment copy: larger title and larger bold timer/status.
        CharacterPage.SetFont("s15 Bold c120900", LauncherMorrowindFont)
        nameLabel := CharacterPage.Add("Text", "x525 y" y " w355 h28 BackgroundTrans", event.Name)
        CharacterPage.SetFont("s12 Bold c120900", LauncherMorrowindFont)
        detailLabel := CharacterPage.Add("Text", "x525 y" (y + 30) " w355 h24 BackgroundTrans",
            modeText " • " statusText)
        start := AddStyledButton(CharacterPage, 525, y + 58, 135, 26, event.StartedAt != "" ? "Stop Event" : "Start Event", ToggleScheduledEventFromBook.Bind(index))
        edit := AddStyledButton(CharacterPage, 665, y + 58, 105, 26, "Edit", EditScheduledEventFromBook.Bind(index))
        del := AddStyledButton(CharacterPage, 775, y + 58, 105, 26, "Delete", DeleteScheduledEventFromBook.Bind(index))
        ScheduledEventsBookRows.Push([nameLabel, detailLabel, edit, del, start])
        y += 102
    }
    PaintScheduledEventsBook()
}

RefreshScheduledEventsBook()
{
    global ScheduledEventsBookMode
    if ScheduledEventsBookMode
        BuildScheduledEventsBookRows()
}

EditScheduledEventFromBook(index, *)
{
    global CharacterPage
    OpenScheduledEventBookEditor(index)
}

DeleteScheduledEventFromBook(index, *)
{
    global ScheduledEvents
    if index < 1 || index > ScheduledEvents.Length
        return
    event := ScheduledEvents[index]
    if MsgBox("Delete the scheduled event '" event.Name "'?", "tes3np", "YesNo Icon?") != "Yes"
        return
    ScheduledEvents.RemoveAt(index)
    SaveScheduledEvents()
    RefreshDailyLoginButton()
    RefreshScheduledEventsBook()
}

ToggleScheduledEventFromBook(index, *)
{
    global ScheduledEvents, ScheduledCountdownArmedEventId
    if index < 1 || index > ScheduledEvents.Length
        return
    event := ScheduledEvents[index]
    if event.StartedAt != ""
    {
        event.Locked := false
        event.Armed := true
        event.StartedAt := ""
        event.Due := false
        event.PreviousRemaining := event.HasOwnProp("Mode") && event.Mode = "Countdown" ? event.DurationSeconds : 0
        ScheduledCountdownArmedEventId := event.Id
    }
    else
    {
        event.StartedAt := A_Now
        event.Locked := true
        event.Armed := false
        event.LastRunDate := ""
        event.Due := false
        event.Completed := false
        event.PreviousRemaining := event.HasOwnProp("Mode") && event.Mode = "Countdown" ? event.DurationSeconds : GetScheduledEventRawRemaining(event.Time, "IRL")
        if ScheduledCountdownArmedEventId = event.Id
            ScheduledCountdownArmedEventId := ""
    }
    SaveScheduledEvents()
    UpdateScheduledEventBookRow(index)
}

UpdateScheduledEventBookRow(index)
{
    global ScheduledEvents, ScheduledEventsBookRows
    if index < 1 || index > ScheduledEvents.Length || index > ScheduledEventsBookRows.Length
        return
    row := ScheduledEventsBookRows[index]
    if row.Length < 5
        return
    event := ScheduledEvents[index]
    modeText := event.StartedAt != ""
        ? FormatDailyLoginCountdown(GetScheduledEventSecondsRemaining(event))
        : (event.HasOwnProp("Mode") && event.Mode = "Countdown"
            ? FormatDailyLoginCountdown(event.DurationSeconds)
            : FormatScheduledEventTime(event.Time))
    statusText := event.StartedAt != "" ? "Running" : (event.HasOwnProp("Completed") && event.Completed ? "Completed" : "Ready")
    try row[2].Text := modeText " • " statusText
    try
    {
        row[5].Text := event.StartedAt != "" ? "Stop Event" : "Start Event"
        if ButtonFaces.Has(row[5].Hwnd)
        {
            ButtonFaces[row[5].Hwnd].Text := row[5].Text
            PaintButtonNow(row[5].Hwnd)
        }
    }
}

CloseScheduledEventsBook(*)
{
    global CharacterPage, ScheduledEventsBookMode, ScheduledEventsBookControls, ScheduledEventsBookRows, CharacterHeading, LaunchSettingsHeading, ScheduledEventsBookHiddenControls

    BeginInterfaceUpdate(CharacterPage, "Loading characters...", true)
    try
    {
        ScheduledEventsBookMode := false
        ; Hide scheduler controls first, including their custom painted faces.
        ; Destroying a transparent text control while the book is visible does not
        ; reliably erase its pixels from the parchment background.
        for control in ScheduledEventsBookControls
        {
            SetBookControlVisible(control, false)
            try control.Destroy()
        }
        for row in ScheduledEventsBookRows
            for control in row
            {
                SetBookControlVisible(control, false)
                try control.Destroy()
            }
        ScheduledEventsBookControls := []
        ScheduledEventsBookRows := []

        ; Keep this same book window alive. Destroying/recreating it causes the
        ; old hide/show flash. Instead rebuild the normal Characters controls in
        ; place after the loading cover has captured the current frame.
        CharacterHeading.Text := "Your Characters"
        LaunchSettingsHeading.Text := "Launch Settings"
        for control in ScheduledEventsBookHiddenControls
            SetBookControlVisible(control, true)
        ScheduledEventsBookHiddenControls := []
        RefreshProfiles()
        ApplyV016CharacterLayout()
        ; Clear pixels left by the scheduler's transparent text before the
        ; loading cover is released, then paint the restored character page.
        try DllCall("RedrawWindow", "Ptr", CharacterPage.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
        FinishButtonDisplay()
    }
    finally EndInterfaceUpdate()
}

PaintCharactersBook()
{
    global CharacterPage, ScheduledEventsBookMode
    if ScheduledEventsBookMode || !IsObject(CharacterPage)
        return
    try DllCall("InvalidateRect", "Ptr", CharacterPage.Hwnd, "Ptr", 0, "Int", true)
    try DllCall("UpdateWindow", "Ptr", CharacterPage.Hwnd)
}

CloseScheduledEventsMenu()
{
    global ScheduledEventsWindow, ScheduledEventsListView
    if IsObject(ScheduledEventsWindow)
        try ScheduledEventsWindow.Destroy()
    ScheduledEventsWindow := 0
    ScheduledEventsListView := 0
}

RefreshScheduledEventsList()
{
    global ScheduledEvents, ScheduledEventsListView
    if !IsObject(ScheduledEventsListView)
        return
    selected := ScheduledEventsListView.GetNext()
    ScheduledEventsListView.Delete()
    for event in ScheduledEvents
        ScheduledEventsListView.Add(, event.Name, event.HasOwnProp("Mode") && event.Mode = "Countdown" ? "Countdown" : "IRL Time", event.HasOwnProp("Mode") && event.Mode = "Countdown" ? FormatDailyLoginCountdown(event.DurationSeconds) : FormatScheduledEventTime(event.Time), event.Recurring ? "Recurring" : "One Time", event.HasOwnProp("Completed") && event.Completed ? "Completed" : FormatDailyLoginCountdown(GetScheduledEventSecondsRemaining(event)))
    if selected && selected <= ScheduledEvents.Length
        ScheduledEventsListView.Modify(selected, "Select Focus")
}


FormatScheduledEventTime(time)
{
    hour := Integer(SubStr(time, 1, 2)), minute := SubStr(time, 4, 2)
    meridiem := hour >= 12 ? "PM" : "AM"
    displayHour := Mod(hour, 12)
    if displayHour = 0
        displayHour := 12
    return displayHour ":" minute " " meridiem
}

OpenScheduledEventBookEditor(eventIndex := 0)
{
    global CharacterPage, ScheduledEvents, ScheduledEventsBookRows, LauncherMorrowindFont, LaunchSettingsHeading
    BeginInterfaceUpdate(CharacterPage, "Loading event editor...", true)
    try
    {
    editing := eventIndex > 0 && eventIndex <= ScheduledEvents.Length
    LaunchSettingsHeading.Text := editing ? "Edit Scheduled Event" : "Schedule New Event"
    event := editing ? ScheduledEvents[eventIndex] : {Name: "Daily Login", TimeBasis: "IRL", Time: "12:00", Mode: "IRL", DurationSeconds: 3600, Recurring: true, Completed: false}

    ; Replace the right-page event list with the editor.
    for row in ScheduledEventsBookRows
        for control in row
        {
            SetBookControlVisible(control, false)
            try control.Destroy()
        }
    ScheduledEventsBookRows := []
    ; Erase the old event-list pixels before placing editor controls.
    try DllCall("RedrawWindow", "Ptr", CharacterPage.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)

    CharacterPage.SetFont("s11 Bold c241408", LauncherMorrowindFont)
    nameLabel := CharacterPage.Add("Text", "x525 y95 w330 h22 BackgroundTrans", "Event name")
    CharacterPage.SetFont("s10 Norm c241408", "Segoe UI")
    nameEdit := AddThemedEdit(CharacterPage, "x525 y120 w330 h28", event.Name)

    CharacterPage.SetFont("s11 Bold c241408", LauncherMorrowindFont)
    modeLabel := CharacterPage.Add("Text", "x525 y165 w330 h22 BackgroundTrans", "Event mode")
    CharacterPage.SetFont("s10 Norm c241408", "Segoe UI")
    modeList := CharacterPage.Add("DropDownList", "x525 y190 w330 h100", ["Specific Time (IRL)", "Countdown"])
    isCountdown := event.HasOwnProp("Mode") && event.Mode = "Countdown"
    modeList.Choose(isCountdown ? 2 : 1)
    recurringCheck := {Value: event.Recurring ? 1 : 0}
    recurringTick := AddBookTick(CharacterPage, 525, 225, (*) => ToggleScheduledBookRecurring(recurringCheck, recurringTick))
    SetBookTick(recurringTick, recurringCheck.Value)
    CharacterPage.SetFont("s11 Norm c241408", LauncherMorrowindFont)
    recurringLabel := AddBookLabel(CharacterPage, 550, 222, 180, 24, "Recurring")

    hour24 := Integer(SubStr(event.Time, 1, 2)), minute := Integer(SubStr(event.Time, 4, 2))
    displayHour := Mod(hour24, 12)
    if displayHour = 0
        displayHour := 12
    duration := event.HasOwnProp("DurationSeconds") && event.DurationSeconds > 0 ? event.DurationSeconds : 3600
    durationHours := Floor(duration / 3600), durationMinutes := Floor(Mod(duration, 3600) / 60), durationSeconds := Mod(duration, 60)

    CharacterPage.SetFont("s11 Bold c241408", LauncherMorrowindFont)
    hourLabel := CharacterPage.Add("Text", "x525 y270 w60 h22 BackgroundTrans", isCountdown ? "Hours" : "Hour")
    minuteLabel := CharacterPage.Add("Text", "x600 y270 w65 h22 BackgroundTrans", isCountdown ? "Minutes" : "Minute")
    thirdLabel := CharacterPage.Add("Text", "x675 y270 w90 h22 BackgroundTrans", isCountdown ? "Seconds" : "Clock")
    CharacterPage.SetFont("s10 Norm c241408", "Segoe UI")
    hourEdit := AddThemedEdit(CharacterPage, "x525 y295 w60 h28 Center Number", isCountdown ? durationHours : displayHour)
    minuteEdit := AddThemedEdit(CharacterPage, "x600 y295 w60 h28 Center Number", isCountdown ? durationMinutes : minute)
    clockMode := CharacterPage.Add("DropDownList", "x675 y295 w100 h120 Choose1", ["AM / PM", "24-hour"])
    secondEdit := AddThemedEdit(CharacterPage, "x675 y295 w100 h28 Center Number", durationSeconds)
    meridiem := CharacterPage.Add("DropDownList", "x785 y295 w70 h120", ["AM", "PM"])
    meridiem.Choose(hour24 >= 12 ? 2 : 1)

    UpdateScheduledEventModeFields(modeList, hourLabel, minuteLabel, thirdLabel, hourEdit, minuteEdit, clockMode, secondEdit, meridiem, displayHour, minute, durationHours, durationMinutes, durationSeconds)
    modeList.OnEvent("Change", UpdateScheduledEventModeFields.Bind(modeList, hourLabel, minuteLabel, thirdLabel, hourEdit, minuteEdit, clockMode, secondEdit, meridiem, displayHour, minute, durationHours, durationMinutes, durationSeconds))
    clockMode.OnEvent("Change", UpdateDailyLoginClockMode.Bind(hourEdit, meridiem, clockMode))

    save := AddStyledButton(CharacterPage, 525, 350, 155, 30, editing ? "Save Changes" : "Schedule Event",
        SaveScheduledEventBookEditor.Bind(eventIndex, nameEdit, modeList, recurringCheck, hourEdit, minuteEdit, clockMode, secondEdit, meridiem))
    cancel := AddStyledButton(CharacterPage, 700, 350, 155, 30, "Cancel", CancelScheduledEventBookEditor)

    ScheduledEventsBookRows := [[nameLabel, nameEdit, modeLabel, modeList, recurringTick, recurringLabel, hourLabel, minuteLabel, thirdLabel,
        hourEdit, minuteEdit, clockMode, secondEdit, meridiem, save, cancel]]
    FinishButtonDisplay()
    PaintScheduledEventsBook()
    }
    finally EndInterfaceUpdate()
}

ToggleScheduledBookRecurring(state, tick, *)
{
    state.Value := state.Value ? 0 : 1
    SetBookTick(tick, state.Value)
}

SaveScheduledEventBookEditor(eventIndex, nameEdit, modeList, recurringCheck, hourEdit, minuteEdit, clockMode, secondEdit, meridiem, *)
{
    global CharacterPage
    BeginInterfaceUpdate(CharacterPage, "Saving scheduled event...", true)
    try
    {
        ; Reuse the existing validation/save routine with a harmless object that
        ; provides Destroy(), then rebuild the right-page event list.
        editorShim := {Destroy: (*) => 0}
        SaveScheduledEventEditor(editorShim, eventIndex, nameEdit, modeList, recurringCheck, hourEdit, minuteEdit, clockMode, secondEdit, meridiem)
        RefreshScheduledEventsBook()
    }
    finally EndInterfaceUpdate()
}

CancelScheduledEventBookEditor(*)
{
    global CharacterPage
    BeginInterfaceUpdate(CharacterPage, "Loading scheduled events...", true)
    try RefreshScheduledEventsBook()
    finally EndInterfaceUpdate()
}

OpenScheduledEventEditor(owner, eventIndex := 0)
{
    global ScheduledEvents
    editing := eventIndex > 0 && eventIndex <= ScheduledEvents.Length
    event := editing ? ScheduledEvents[eventIndex] : {Name: "Daily Login", TimeBasis: "IRL", Time: "12:00", Mode: "IRL", DurationSeconds: 3600, Recurring: true, Completed: false}
    editor := Gui("+Owner" owner.Hwnd " -MinimizeBox -MaximizeBox", editing ? "tes3np — Edit Event" : "tes3np — Schedule Event")
    editor.BackColor := "E2CEA2"
    editor.SetFont("s10 Bold c382314", "Segoe UI")
    editor.Add("Text", "x20 y20 w330 h22", "Event name")
    editor.SetFont("s10 c382314", "Segoe UI")
    nameEdit := editor.Add("Edit", "x20 y46 w330 h30", event.Name)
    editor.SetFont("s10 Bold c382314", "Segoe UI")
    editor.Add("Text", "x20 y92 w330 h22", "Event mode")
    editor.SetFont("s10 c382314", "Segoe UI")
    modeList := editor.Add("DropDownList", "x20 y118 w330 h100", ["Specific Time (IRL)", "Countdown"])
    isCountdown := event.HasOwnProp("Mode") && event.Mode = "Countdown"
    modeList.Choose(isCountdown ? 2 : 1)
    recurringCheck := editor.Add("CheckBox", "x20 y150 w330 h24", "Recurring")
    recurringCheck.Value := event.Recurring ? 1 : 0

    hour24 := Integer(SubStr(event.Time, 1, 2)), minute := Integer(SubStr(event.Time, 4, 2))
    displayHour := Mod(hour24, 12)
    if displayHour = 0
        displayHour := 12
    duration := event.HasOwnProp("DurationSeconds") && event.DurationSeconds > 0 ? event.DurationSeconds : 3600
    durationHours := Floor(duration / 3600)
    durationMinutes := Floor(Mod(duration, 3600) / 60)
    durationSeconds := Mod(duration, 60)

    editor.SetFont("s10 Bold c382314", "Segoe UI")
    hourLabel := editor.Add("Text", "x20 y184 w60 h22", isCountdown ? "Hours" : "Hour")
    minuteLabel := editor.Add("Text", "x92 y184 w60 h22", isCountdown ? "Minutes" : "Minute")
    thirdLabel := editor.Add("Text", "x164 y184 w90 h22", isCountdown ? "Seconds" : "Clock")
    editor.SetFont("s10 c382314", "Segoe UI")
    hourEdit := editor.Add("Edit", "x20 y210 w52 h28 Center Number", isCountdown ? durationHours : displayHour)
    minuteEdit := editor.Add("Edit", "x92 y210 w52 h28 Center Number", isCountdown ? durationMinutes : minute)
    clockMode := editor.Add("DropDownList", "x164 y210 w100 h120 Choose1", ["AM / PM", "24-hour"])
    secondEdit := editor.Add("Edit", "x164 y210 w100 h28 Center Number", durationSeconds)
    meridiem := editor.Add("DropDownList", "x274 y210 w76 h120", ["AM", "PM"])
    meridiem.Choose(hour24 >= 12 ? 2 : 1)

    UpdateScheduledEventModeFields(modeList, hourLabel, minuteLabel, thirdLabel, hourEdit, minuteEdit, clockMode, secondEdit, meridiem, displayHour, minute, durationHours, durationMinutes, durationSeconds)
    modeList.OnEvent("Change", UpdateScheduledEventModeFields.Bind(modeList, hourLabel, minuteLabel, thirdLabel, hourEdit, minuteEdit, clockMode, secondEdit, meridiem, displayHour, minute, durationHours, durationMinutes, durationSeconds))
    clockMode.OnEvent("Change", UpdateDailyLoginClockMode.Bind(hourEdit, meridiem, clockMode))
    save := editor.Add("Button", "x20 y264 w158 h34 Default", editing ? "Save Changes" : "Schedule Event")
    cancel := editor.Add("Button", "x192 y264 w158 h34", "Cancel")
    save.OnEvent("Click", SaveScheduledEventEditor.Bind(editor, eventIndex, nameEdit, modeList, recurringCheck, hourEdit, minuteEdit, clockMode, secondEdit, meridiem))
    cancel.OnEvent("Click", (*) => editor.Destroy())
    editor.OnEvent("Escape", (*) => editor.Destroy())
    editor.Show("w370 h318")
}

UpdateScheduledEventModeFields(modeList, hourLabel, minuteLabel, thirdLabel, hourEdit, minuteEdit, clockMode, secondEdit, meridiem, irlHour, irlMinute, durationHours, durationMinutes, durationSeconds, *)
{
    isCountdown := modeList.Value = 2
    hourLabel.Text := isCountdown ? "Hours" : "Hour"
    minuteLabel.Text := isCountdown ? "Minutes" : "Minute"
    thirdLabel.Text := isCountdown ? "Seconds" : "Clock"
    clockMode.Visible := !isCountdown
    meridiem.Visible := !isCountdown
    secondEdit.Visible := isCountdown
    if isCountdown
    {
        hourEdit.Text := durationHours
        minuteEdit.Text := durationMinutes
        secondEdit.Text := durationSeconds
    }
    else
    {
        hourEdit.Text := irlHour
        minuteEdit.Text := Format("{:02}", irlMinute)
    }
}

UpdateDailyLoginClockMode(hourEdit, meridiem, clockMode, *)
{
    use24 := clockMode.Value = 2
    meridiem.Enabled := !use24
    hour := Integer(hourEdit.Text = "" ? 0 : hourEdit.Text)
    if use24
    {
        if hour >= 1 && hour <= 12 && meridiem.Text = "PM" && hour != 12
            hour += 12
        else if hour = 12 && meridiem.Text = "AM"
            hour := 0
    }
    else
    {
        if hour = 0
            hour := 12
        else if hour > 12
            hour -= 12
    }
    hourEdit.Text := hour
}

SaveScheduledEventEditor(editor, eventIndex, nameEdit, modeList, recurringCheck, hourEdit, minuteEdit, clockMode, secondEdit, meridiem, *)
{
    global ScheduledEvents, NextScheduledEventId, DataFile, ScheduledCountdownArmedEventId
    name := Trim(nameEdit.Text)
    if name = ""
    {
        MsgBox("Enter a name for this event.", "tes3np")
        return
    }
    mode := modeList.Value = 2 ? "Countdown" : "IRL"
    hourText := Trim(hourEdit.Text), minuteText := Trim(minuteEdit.Text)
    if hourText = "" || minuteText = "" || !IsInteger(hourText) || !IsInteger(minuteText)
    {
        MsgBox(mode = "Countdown" ? "Enter valid hours and minutes." : "Choose a valid hour and minute.", "tes3np")
        return
    }
    hour := Integer(hourText), minute := Integer(minuteText)
    time := "12:00", durationSeconds := 0
    if mode = "Countdown"
    {
        secondText := Trim(secondEdit.Text)
        if secondText = "" || !IsInteger(secondText)
        {
            MsgBox("Enter valid seconds.", "tes3np")
            return
        }
        seconds := Integer(secondText)
        if hour < 0 || minute < 0 || seconds < 0 || minute > 59 || seconds > 59
        {
            MsgBox("Countdown minutes and seconds must be between 0 and 59.", "tes3np")
            return
        }
        durationSeconds := hour * 3600 + minute * 60 + seconds
        if durationSeconds <= 0
        {
            MsgBox("Countdown duration must be greater than zero.", "tes3np")
            return
        }
    }
    else
    {
        if minute < 0 || minute > 59
        {
            MsgBox("Minutes must be between 00 and 59.", "tes3np")
            return
        }
        if clockMode.Value = 2
        {
            if hour < 0 || hour > 23
            {
                MsgBox("24-hour time uses hours 0 through 23.", "tes3np")
                return
            }
            time := Format("{:02}:{:02}", hour, minute)
        }
        else
        {
            if hour < 1 || hour > 12
            {
                MsgBox("AM/PM time uses hours 1 through 12.", "tes3np")
                return
            }
            hour24 := hour
            if meridiem.Text = "AM" && hour = 12
                hour24 := 0
            else if meridiem.Text = "PM" && hour != 12
                hour24 += 12
            time := Format("{:02}:{:02}", hour24, minute)
        }
    }
    recurring := recurringCheck.Value = 1
    if eventIndex > 0 && eventIndex <= ScheduledEvents.Length
    {
        event := ScheduledEvents[eventIndex]
        event.Name := name, event.TimeBasis := "IRL", event.Time := time, event.Mode := mode, event.DurationSeconds := durationSeconds, event.StartedAt := "", event.Recurring := recurring, event.Locked := false, event.Armed := true
        event.LastRunDate := "", event.Completed := false, event.Due := false, event.PreviousRemaining := mode = "Countdown" ? durationSeconds : GetScheduledEventRawRemaining(time, "IRL")
    }
    else
    {
        event := {Id: NextScheduledEventId, Name: name, TimeBasis: "IRL", Time: time, Mode: mode, DurationSeconds: durationSeconds, StartedAt: "", Recurring: recurring, Locked: false, Armed: true, Completed: false, LastRunDate: "", Due: false, PreviousRemaining: mode = "Countdown" ? durationSeconds : GetScheduledEventRawRemaining(time, "IRL")}
        ScheduledEvents.Push(event)
        NextScheduledEventId += 1
    }
    ScheduledCountdownArmedEventId := event.Id
    SaveScheduledEvents()
    savedCount := Integer(IniRead(DataFile, "ScheduledEvents", "Count", "0"))
    if savedCount != ScheduledEvents.Length
    {
        MsgBox("The scheduled event could not be saved to settings.ini.", "tes3np")
        return
    }
    editor.Destroy()
    RefreshScheduledEventsList()
    RefreshDailyLoginButton()
    RefreshScheduledEventsBook()
}

EditSelectedScheduledEvent()
{
    global ScheduledEventsListView, ScheduledEventsWindow
    if !IsObject(ScheduledEventsListView)
        return
    row := ScheduledEventsListView.GetNext()
    if !row
    {
        MsgBox("Select an event to edit.", "tes3np")
        return
    }
    OpenScheduledEventEditor(ScheduledEventsWindow, row)
}

DeleteSelectedScheduledEvent()
{
    global ScheduledEvents, ScheduledEventsListView
    if !IsObject(ScheduledEventsListView)
        return
    row := ScheduledEventsListView.GetNext()
    if !row
    {
        MsgBox("Select an event to delete.", "tes3np")
        return
    }
    event := ScheduledEvents[row]
    if MsgBox("Delete the scheduled event '" event.Name "'?", "tes3np", "YesNo Icon?") != "Yes"
        return
    ScheduledEvents.RemoveAt(row)
    SaveScheduledEvents()
    RefreshScheduledEventsList()
    RefreshDailyLoginButton()
}

RefreshDailyLoginButton()
{
    global V016DailyLoginControls, ScheduledEvents
    if !IsObject(V016DailyLoginControls) || V016DailyLoginControls.Length < 1
        return
    button := V016DailyLoginControls[1]
    button.Text := ScheduledEvents.Length ? "Scheduled Events (" ScheduledEvents.Length ")" : "Schedule Event"
}

UpdateDailyLoginCountdown(*)
{
    CheckDailyLoginSchedule()
    RefreshScheduledEventsList()
    UpdateScheduledEventsBookCountdowns()
}

UpdateScheduledEventsBookCountdowns()
{
    global ScheduledEventsBookMode, ScheduledEventsBookRows, ScheduledEvents
    if !ScheduledEventsBookMode
        return

    ; Update only the detail text in-place. Rebuilding every row once per second
    ; causes the visible page to flash and eats clicks.
    for index, event in ScheduledEvents
    {
        if index > ScheduledEventsBookRows.Length
            break
        row := ScheduledEventsBookRows[index]
        if row.Length < 2
            continue
        detail := row[2]
        try
        {
            modeText := event.StartedAt != ""
                ? FormatDailyLoginCountdown(GetScheduledEventSecondsRemaining(event))
                : (event.HasOwnProp("Mode") && event.Mode = "Countdown"
                    ? FormatDailyLoginCountdown(event.DurationSeconds)
                    : FormatScheduledEventTime(event.Time))
            statusText := event.StartedAt != "" ? "Running" : (event.HasOwnProp("Completed") && event.Completed ? "Completed" : "Ready")
            newText := modeText " • " statusText
            if detail.Text != newText
                detail.Text := newText
        }
    }
}

GetScheduledEventRawRemaining(time, timeBasis := "IRL")
{
    now := A_Now
    target := SubStr(now, 1, 8) StrReplace(time, ":") "00"
    return DateDiff(target, now, "Seconds")
}

GetScheduledEventSecondsRemaining(event)
{
    today := FormatTime(, "yyyy-MM-dd")
    if event.HasOwnProp("Mode") && event.Mode = "Countdown"
    {
        if event.StartedAt = ""
            return event.DurationSeconds
        return Max(0, event.DurationSeconds - DateDiff(A_Now, event.StartedAt, "Seconds"))
    }
    if event.StartedAt = ""
        return 0
    remaining := GetScheduledEventRawRemaining(event.Time, event.TimeBasis)
    if event.Due && event.LastRunDate != today
        return 0
    if remaining <= 0
        target := DateAdd(SubStr(A_Now, 1, 8) StrReplace(event.Time, ":") "00", 1, "Days")
    else
        target := SubStr(A_Now, 1, 8) StrReplace(event.Time, ":") "00"
    return Max(0, DateDiff(target, A_Now, "Seconds"))
}

FormatDailyLoginCountdown(seconds)
{
    hours := Floor(seconds / 3600)
    minutes := Floor(Mod(seconds, 3600) / 60)
    secs := Mod(seconds, 60)
    return Format("{:02}:{:02}:{:02}", hours, minutes, secs)
}

CheckDailyLoginSchedule(*)
{
    global ScheduledEvents, Client, ActiveScheduledEventId
    today := FormatTime(, "yyyy-MM-dd")
    for event in ScheduledEvents
    {
        if event.HasOwnProp("Completed") && event.Completed
            continue
        isCountdown := event.HasOwnProp("Mode") && event.Mode = "Countdown"
        if !isCountdown && event.LastRunDate = today
            continue
        if isCountdown
        {
            if event.StartedAt = ""
                continue
            remaining := event.DurationSeconds - DateDiff(A_Now, event.StartedAt, "Seconds")
        }
        else
        {
            if event.StartedAt = ""
                continue
            remaining := GetScheduledEventRawRemaining(event.Time, event.TimeBasis)
        }
        crossed := event.PreviousRemaining > 0 && remaining <= 0
        event.PreviousRemaining := remaining
        if crossed
            event.Due := true
        if !event.Due
            continue

        gamePid := ProcessExist("tes3mp.exe")
        if Client.Enabled || gamePid
        {
            LogLauncherEvent("GAME | Scheduled event '" event.Name "' became due while TES3MP was already running; alert suppressed.")
            CompleteScheduledEventForToday(event, "skipped because game was already running")
            continue
        }

        LogLauncherEvent("GAME | Scheduled event '" event.Name "' is due; awaiting user choice.")
        choice := MsgBox("'" event.Name "' is ready.\n\nWould you like to log in for this event now?", "Scheduled Event", "YesNo Icon?")
        if choice != "Yes"
        {
            CompleteScheduledEventForToday(event, "cancelled by user")
            continue
        }

        ActiveScheduledEventId := event.Id
        LogLauncherEvent("GAME | Scheduled event due | Name: " event.Name " | Time basis: IRL.")
        if !StartScheduledDailyLogin()
        {
            ActiveScheduledEventId := ""
            LogLauncherEvent("GAME | Scheduled event could not start; will retry.")
            return
        }
        return
    }
}

StartScheduledDailyLogin()
{
    global Client, Profiles, SelectedProfile
    if Client.Enabled || SelectedProfile < 1 || SelectedProfile > Profiles.Length
        return false
    executable := GetSharedExecutable()
    profile := Profiles[SelectedProfile]
    if !ValidateLaunch(profile, executable)
        return false
    LogLauncherEvent("GAME | Scheduled event login starting. Character: " profile.Name ".")
    StartProfileSession(profile, executable, 0, true)
    return true
}

FindScheduledEventById(id)
{
    global ScheduledEvents
    for event in ScheduledEvents
        if event.Id = id
            return event
    return 0
}

CompleteScheduledEventForToday(event, reason := "completed", successful := false)
{
    global ScheduledEvents
    event.LastRunDate := FormatTime(, "yyyy-MM-dd")
    event.Due := false
    if event.HasOwnProp("Mode") && event.Mode = "Countdown" && event.Recurring && event.StartedAt != ""
    {
        ; Keep recurring countdowns anchored to their original cadence. Advancing
        ; from the exact prior boundary avoids adding scheduler/prompt delay every cycle.
        event.StartedAt := DateAdd(event.StartedAt, event.DurationSeconds, "Seconds")
        event.PreviousRemaining := event.DurationSeconds
        event.LastRunDate := ""
    }
    else if successful && !event.Recurring
        event.Completed := true
    SaveScheduledEvents()
    LogLauncherEvent("GAME | Scheduled event '" event.Name "' " reason " for today.")
    RefreshScheduledEventsList()
    RefreshDailyLoginButton()
}

CancelScheduledDailyLoginForToday(reason := "game was closed")
{
    global ActiveScheduledEventId
    if ActiveScheduledEventId = ""
        return
    event := FindScheduledEventById(ActiveScheduledEventId)
    if IsObject(event)
        CompleteScheduledEventForToday(event, "cancelled | Reason: " reason)
    ActiveScheduledEventId := ""
}

MarkScheduledDailyLoginComplete()
{
    global ActiveScheduledEventId
    if ActiveScheduledEventId = ""
        return
    event := FindScheduledEventById(ActiveScheduledEventId)
    if IsObject(event)
        CompleteScheduledEventForToday(event, "completed", true)
    ActiveScheduledEventId := ""
}

SaveScheduledEventShutdownTime()
{
    global DataFile
    IniWrite(A_Now, DataFile, "ScheduledEvents", "LastLauncherExit")
}

ShowMissedScheduledEvents(*)
{
    global ScheduledEvents, DataFile
    lastExit := IniRead(DataFile, "ScheduledEvents", "LastLauncherExit", "")
    if !RegExMatch(lastExit, "^\d{14}$")
    {
        ; First run after this feature was added has no shutdown timestamp yet.
        ; Use the most recent launcher start saved at schedule load so missed
        ; events are not silently ignored.
        lastExit := IniRead(DataFile, "ScheduledEvents", "LastLauncherSeen", "")
        if !RegExMatch(lastExit, "^\d{14}$")
            return
    }

    missed := []
    for event in ScheduledEvents
    {
        if event.HasOwnProp("Completed") && event.Completed
            continue
        cursor := SubStr(lastExit, 1, 8) StrReplace(event.Time, ":", "") "00"
        if cursor <= lastExit
            cursor := DateAdd(cursor, 1, "Days")
        wasMissed := cursor <= A_Now
        if wasMissed
            missed.Push(event.Name)
    }

    if missed.Length
    {
        message := "You missed the following scheduled event" (missed.Length = 1 ? "" : "s") " while the launcher was closed:`n`n"
        for name in missed
            message .= "• " name "`n"
        MsgBox(RTrim(message, "`n"), "Missed Scheduled Events", "Icon!")
    }
}

LoadScheduledCountdownHotkey()
{
    global ScheduledCountdownHotkey, DataFile
    savedKey := IniRead(DataFile, "ScheduledEvents", "CountdownHotkey", "F8")
    ScheduledCountdownHotkey := NormalizeScheduledCountdownHotkey(savedKey)
    try Hotkey(ScheduledCountdownHotkey, StartArmedScheduledCountdown, "On")
    catch
    {
        ScheduledCountdownHotkey := "~*F8"
        Hotkey(ScheduledCountdownHotkey, StartArmedScheduledCountdown, "On")
    }
}

NormalizeScheduledCountdownHotkey(key)
{
    key := Trim(key)
    while SubStr(key, 1, 1) = "~" || SubStr(key, 1, 1) = "*"
        key := SubStr(key, 2)
    return "~*" key
}

DisplayScheduledCountdownHotkey(key)
{
    while SubStr(key, 1, 1) = "~" || SubStr(key, 1, 1) = "*"
        key := SubStr(key, 2)
    return key
}

EditScheduledCountdownHotkey(button, *)
{
    global ScheduledCountdownHotkey, DataFile, ScheduledEventsWindow, CharacterPage
    owner := IsObject(ScheduledEventsWindow) ? ScheduledEventsWindow : CharacterPage
    picker := Gui("+Owner" owner.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — Countdown Hotkey")
    picker.BackColor := "E2CEA2"
    picker.SetFont("s10 Bold c382314", "Segoe UI")
    picker.Add("Text", "x20 y18 w330 h22", "Press the key you want to use")
    picker.SetFont("s9 c382314", "Segoe UI")
    picker.Add("Text", "x20 y46 w330 h36", "Click the box below, then press any key, including F1–F24.")
    keyControl := picker.Add("Hotkey", "x20 y88 w330 h30")
    currentKey := DisplayScheduledCountdownHotkey(ScheduledCountdownHotkey)
    try keyControl.Value := currentKey
    save := picker.Add("Button", "x20 y134 w158 h34 Default", "Save Hotkey")
    cancel := picker.Add("Button", "x192 y134 w158 h34", "Cancel")
    save.OnEvent("Click", SaveScheduledCountdownHotkey.Bind(picker, keyControl, button))
    cancel.OnEvent("Click", (*) => picker.Destroy())
    picker.OnEvent("Escape", (*) => picker.Destroy())
    picker.Show("w370 h188")
}

SaveScheduledCountdownHotkey(picker, keyControl, button, *)
{
    global ScheduledCountdownHotkey, DataFile
    cleanKey := Trim(keyControl.Value)
    if cleanKey = ""
    {
        MsgBox("Press a key first.", "tes3np")
        return
    }
    newKey := NormalizeScheduledCountdownHotkey(cleanKey)
    oldKey := ScheduledCountdownHotkey
    try Hotkey(oldKey, "Off")
    try Hotkey(newKey, StartArmedScheduledCountdown, "On")
    catch
    {
        try Hotkey(oldKey, StartArmedScheduledCountdown, "On")
        MsgBox("That key could not be registered.", "tes3np")
        return
    }
    ScheduledCountdownHotkey := newKey
    IniWrite(DisplayScheduledCountdownHotkey(newKey), DataFile, "ScheduledEvents", "CountdownHotkey")
    button.Text := "Hotkey: " DisplayScheduledCountdownHotkey(newKey)
    picker.Destroy()
}

RefreshScheduledEventLockButton(button)
{
    global ScheduledEventsListView, ScheduledEvents
    row := IsObject(ScheduledEventsListView) ? ScheduledEventsListView.GetNext() : 0
    if !row || row > ScheduledEvents.Length
    {
        button.Text := "Start Event"
        return
    }
    event := ScheduledEvents[row]
    modeName := event.HasOwnProp("Mode") && event.Mode = "Countdown" ? "Countdown" : "Specific Time (IRL)"
    button.Text := event.StartedAt != "" ? "Stop " modeName : "Start " modeName
}

ToggleSelectedScheduledEventLock(button, *)
{
    global ScheduledEventsListView, ScheduledEvents, ScheduledCountdownArmedEventId
    row := IsObject(ScheduledEventsListView) ? ScheduledEventsListView.GetNext() : 0
    if !row
    {
        MsgBox("Select an event first.", "tes3np")
        return
    }

    event := ScheduledEvents[row]
    running := event.StartedAt != ""

    if running
    {
        ; Stop manually: reset and unlock so the hotkey may start it again.
        event.Locked := false
        event.Armed := true
        event.StartedAt := ""
        event.Due := false
        event.PreviousRemaining := event.HasOwnProp("Mode") && event.Mode = "Countdown" ? event.DurationSeconds : 0
        ScheduledCountdownArmedEventId := event.Id
    }
    else
    {
        ; Start manually: begin now and lock out hotkey changes.
        event.StartedAt := A_Now
        event.Locked := true
        event.Armed := false
        event.LastRunDate := ""
        event.Due := false
        event.Completed := false
        event.PreviousRemaining := event.HasOwnProp("Mode") && event.Mode = "Countdown" ? event.DurationSeconds : GetScheduledEventRawRemaining(event.Time, "IRL")
        if ScheduledCountdownArmedEventId = event.Id
            ScheduledCountdownArmedEventId := ""
    }

    SaveScheduledEvents()
    RefreshScheduledEventsList()
    RefreshScheduledEventLockButton(button)
}
StartArmedScheduledCountdown(*)
{
    global ScheduledEvents

    ; The hotkey may start one event whose button is currently in the Start state.
    ; Resolve it from the persisted event state instead of relying on a cached ID.
    event := 0
    for candidate in ScheduledEvents
    {
        if candidate.StartedAt = "" && !(candidate.HasOwnProp("Locked") && candidate.Locked)
        {
            event := candidate
            break
        }
    }
    if !IsObject(event)
        return

    event.StartedAt := A_Now
    event.Armed := false
    event.Locked := true
    event.LastRunDate := ""
    event.Due := false
    event.Completed := false
    if event.HasOwnProp("Mode") && event.Mode = "Countdown"
        event.PreviousRemaining := event.DurationSeconds
    else
        event.PreviousRemaining := GetScheduledEventRawRemaining(event.Time, "IRL")

    SaveScheduledEvents()
    RefreshScheduledEventsList()
    RefreshScheduledEventsBook()
    TrayTip("Event started", "'" event.Name "' is now running and locked.", "Iconi")
}

; Compatibility entry point for older UI callers.
OpenDailyLoginScheduleDialog(owner := 0, *)
{
    OpenScheduledEventsMenu(owner)
}
