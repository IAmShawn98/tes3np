; Multi-event scheduler. Daily Login is the first supported scheduled action.
; Events recur once per day at their configured local clock time.

global ScheduledEvents := []
global ScheduledEventsListView := 0
global ScheduledEventsWindow := 0
global ActiveScheduledEventId := ""
global NextScheduledEventId := 1
global ScheduledCountdownHotkey := "F8"
global ScheduledCountdownArmedEventId := ""
global ScheduledEventArmedIds := Map()


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
        locked := IniRead(DataFile, section, "Locked", "1") = "1"
        completed := IniRead(DataFile, section, "Completed", "0") = "1"
        mode := IniRead(DataFile, section, "Mode", "IRL")
        durationSeconds := Integer(IniRead(DataFile, section, "DurationSeconds", "0"))
        startedAt := IniRead(DataFile, section, "StartedAt", "")
        try time := ParseDailyLoginTime(time)
        catch
            continue
        ScheduledEvents.Push({Id: id, Name: name, TimeBasis: timeBasis, Time: time, Mode: mode, DurationSeconds: durationSeconds, StartedAt: startedAt, Recurring: recurring, Locked: locked, Completed: completed, LastRunDate: lastRun, Due: false, PreviousRemaining: mode = "Countdown" && startedAt = "" ? 1 : GetScheduledEventRawRemaining(time, timeBasis)})
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
        IniWrite(event.HasOwnProp("Completed") && event.Completed ? "1" : "0", DataFile, section, "Completed")
        IniWrite(event.LastRunDate, DataFile, section, "LastRunDate")
    }
}

OpenScheduledEventsMenu(owner := 0, *)
{
    global LauncherGui, ScheduledEventsWindow, ScheduledEventsListView
    if IsObject(ScheduledEventsWindow)
    {
        try {
            WinActivate("ahk_id " ScheduledEventsWindow.Hwnd)
            return
        }
    }
    ownerHwnd := IsObject(owner) ? owner.Hwnd : LauncherGui.Hwnd
    menu := Gui("+Owner" ownerHwnd " -MinimizeBox -MaximizeBox", "tes3np — Scheduled Events")
    menu.BackColor := "E2CEA2"
    menu.SetFont("s14 Bold c241408", "Segoe UI")
    menu.Add("Text", "x20 y18 w600 h30", "Scheduled Events")
    menu.SetFont("s9 c382314", "Segoe UI")
    menu.Add("Text", "x20 y52 w600 h36", "Want to capture timed in-game events? Easily arm timed events in-game via countdowns and IRL timers.")
    lv := menu.Add("ListView", "x20 y96 w600 h250 Grid -Multi", ["Event", "Mode", "Time / Duration", "Repeat", "Status"])
    lv.ModifyCol(1, 150), lv.ModifyCol(2, 90), lv.ModifyCol(3, 120), lv.ModifyCol(4, 90), lv.ModifyCol(5, 130)
    add := menu.Add("Button", "x20 y362 w185 h36 Default", "Schedule Event")
    edit := menu.Add("Button", "x218 y362 w185 h36", "Edit Selected")
    del := menu.Add("Button", "x416 y362 w204 h36", "Delete Selected")
    arm := menu.Add("Button", "x20 y412 w185 h32", "Start Event")
    hotkey := menu.Add("Button", "x218 y412 w185 h32", "Hotkey: " LTrim(ScheduledCountdownHotkey, "~"))
    close := menu.Add("Button", "x416 y412 w204 h32", "Close")
    add.OnEvent("Click", (*) => OpenScheduledEventEditor(menu))
    edit.OnEvent("Click", (*) => EditSelectedScheduledEvent())
    del.OnEvent("Click", (*) => DeleteSelectedScheduledEvent())
    arm.OnEvent("Click", (*) => ToggleSelectedScheduledEventLock(arm))
    hotkey.OnEvent("Click", (*) => EditScheduledCountdownHotkey(hotkey))
    close.OnEvent("Click", (*) => CloseScheduledEventsMenu())
    lv.OnEvent("Click", (*) => RefreshScheduledEventLockButton(arm))
    lv.OnEvent("DoubleClick", (*) => EditSelectedScheduledEvent())
    menu.OnEvent("Close", (*) => CloseScheduledEventsMenu())
    menu.OnEvent("Escape", (*) => CloseScheduledEventsMenu())
    ScheduledEventsWindow := menu
    ScheduledEventsListView := lv
    RefreshScheduledEventsList()
    menu.Show("w640 h464")
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
        event.Name := name, event.TimeBasis := "IRL", event.Time := time, event.Mode := mode, event.DurationSeconds := durationSeconds, event.StartedAt := "", event.Recurring := recurring, event.Locked := false
        event.LastRunDate := "", event.Completed := false, event.Due := false, event.PreviousRemaining := mode = "Countdown" ? durationSeconds : GetScheduledEventRawRemaining(time, "IRL")
    }
    else
    {
        event := {Id: NextScheduledEventId, Name: name, TimeBasis: "IRL", Time: time, Mode: mode, DurationSeconds: durationSeconds, StartedAt: "", Recurring: recurring, Locked: false, Completed: false, LastRunDate: "", Due: false, PreviousRemaining: mode = "Countdown" ? durationSeconds : GetScheduledEventRawRemaining(time, "IRL")}
        ScheduledEvents.Push(event)
        NextScheduledEventId += 1
    }
    if ScheduledCountdownArmedEventId = event.Id
        ScheduledEventArmedIds.Delete(event.Id)
    ScheduledCountdownArmedEventId := ""
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
        if event.StartedAt = "" || !(event.HasOwnProp("Locked") && event.Locked)
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
            if event.StartedAt = "" || !(event.HasOwnProp("Locked") && event.Locked)
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
    global ScheduledCountdownHotkey, DataFile
    picker := Gui("+Owner" ScheduledEventsWindow.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — Countdown Hotkey")
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
    global ScheduledEventsListView, ScheduledEvents, ScheduledEventArmedIds
    row := IsObject(ScheduledEventsListView) ? ScheduledEventsListView.GetNext() : 0
    if !row || row > ScheduledEvents.Length
    {
        button.Text := "Start Event"
        return
    }
    event := ScheduledEvents[row]
    modeName := event.HasOwnProp("Mode") && event.Mode = "Countdown" ? "Countdown" : "Specific Time (IRL)"
    armed := ScheduledEventArmedIds.Has(event.Id)
    running := event.StartedAt != "" && event.HasOwnProp("Locked") && event.Locked
    button.Text := running || armed ? "Stop " modeName : "Start " modeName
}

ToggleSelectedScheduledEventLock(button, *)
{
    global ScheduledEventsListView, ScheduledEvents, ScheduledCountdownArmedEventId, ScheduledEventArmedIds
    row := IsObject(ScheduledEventsListView) ? ScheduledEventsListView.GetNext() : 0
    if !row
    {
        MsgBox("Select an event first.", "tes3np")
        return
    }
    event := ScheduledEvents[row]
    modeName := event.HasOwnProp("Mode") && event.Mode = "Countdown" ? "Countdown" : "Specific Time (IRL)"
    armed := ScheduledEventArmedIds.Has(event.Id)
    running := event.StartedAt != "" && event.HasOwnProp("Locked") && event.Locked

    if running || armed
    {
        ; Stop completely disarms/resets this event.
        ScheduledEventArmedIds.Delete(event.Id)
        if ScheduledCountdownArmedEventId = event.Id
            ScheduledCountdownArmedEventId := ""
        event.Locked := false
        event.StartedAt := ""
        event.Due := false
        event.PreviousRemaining := event.HasOwnProp("Mode") && event.Mode = "Countdown" ? event.DurationSeconds : 0
    }
    else
    {
        ; Start only arms it. Nothing ticks until the in-game hotkey is pressed.
        event.Locked := false
        event.StartedAt := ""
        event.Due := false
        event.Completed := false
        ScheduledEventArmedIds[event.Id] := true
        ScheduledCountdownArmedEventId := event.Id
    }

    SaveScheduledEvents()
    RefreshScheduledEventsList()
    RefreshScheduledEventLockButton(button)
}
StartArmedScheduledCountdown(*)
{
    global ScheduledCountdownArmedEventId, ScheduledEventArmedIds
    ; The hotkey is deliberately one-shot. Once pressed, the captured start
    ; time is locked and another press cannot move it. The user must explicitly
    ; return to Scheduled Events and arm a countdown again before the hotkey works.
    if ScheduledCountdownArmedEventId = "" || !ScheduledEventArmedIds.Has(ScheduledCountdownArmedEventId)
    {
        TrayTip("No event waiting to start", "Open Scheduled Events and choose Start first.", "Icon!")
        return
    }
    event := FindScheduledEventById(ScheduledCountdownArmedEventId)
    if !IsObject(event) || (event.HasOwnProp("Locked") && event.Locked)
    {
        if ScheduledCountdownArmedEventId != ""
            ScheduledEventArmedIds.Delete(ScheduledCountdownArmedEventId)
        ScheduledCountdownArmedEventId := ""
        TrayTip("No event waiting to start", "Open Scheduled Events and choose Start first.", "Icon!")
        return
    }
    event.StartedAt := A_Now
    event.Locked := true
    event.LastRunDate := ""
    event.Due := false
    if event.HasOwnProp("Mode") && event.Mode = "Countdown"
        event.PreviousRemaining := event.DurationSeconds
    else
        event.PreviousRemaining := GetScheduledEventRawRemaining(event.Time, "IRL")
    ScheduledCountdownArmedEventId := ""
    SaveScheduledEvents()
    RefreshScheduledEventsList()
    TrayTip("Event started", "'" event.Name "' is now set and running.", "Iconi")
}

; Compatibility entry point for older UI callers.
OpenDailyLoginScheduleDialog(owner := 0, *)
{
    OpenScheduledEventsMenu(owner)
}
