; Multi-event scheduler. Daily Login is the first supported scheduled action.
; Events recur once per day at their configured local clock time.

global ScheduledEvents := []
global ScheduledEventsListView := 0
global ScheduledEventsWindow := 0
global ActiveScheduledEventId := ""
global NextScheduledEventId := 1

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
        type := IniRead(DataFile, section, "Type", "DailyLogin")
        time := IniRead(DataFile, section, "Time", "12:00")
        lastRun := IniRead(DataFile, section, "LastRunDate", "")
        try time := ParseDailyLoginTime(time)
        catch
            continue
        ScheduledEvents.Push({Id: id, Name: name, Type: type, Time: time, LastRunDate: lastRun, Due: false, PreviousRemaining: GetScheduledEventRawRemaining(time)})
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
        ScheduledEvents.Push({Id: 1, Name: "Daily Login", Type: "DailyLogin", Time: oldTime, LastRunDate: oldLastRun, Due: false, PreviousRemaining: GetScheduledEventRawRemaining(oldTime)})
        maxId := 1
        SaveScheduledEvents()
    }
    NextScheduledEventId := maxId + 1
    SetTimer(UpdateDailyLoginCountdown, 1000)
}

ParseDailyLoginTime(value)
{
    value := Trim(value)
    compact := RegExReplace(StrLower(value), "\\s+", "")
    compact := StrReplace(compact, ".", "")
    if compact = ""
        throw Error("Enter a time for the event.")
    if RegExMatch(compact, "^(1[0-2]|0?[1-9])(?::?([0-5]\\d))?(am|pm)$", &match)
    {
        hour := Integer(match[1]), minute := match[2] = "" ? 0 : Integer(match[2])
        if match[3] = "am"
            hour := hour = 12 ? 0 : hour
        else
            hour := hour = 12 ? 12 : hour + 12
        return Format("{:02}:{:02}", hour, minute)
    }
    if RegExMatch(compact, "^(2[0-3]|[01]?\\d)(?::([0-5]\\d))?$", &match)
        return Format("{:02}:{:02}", Integer(match[1]), match[2] = "" ? 0 : Integer(match[2]))
    if RegExMatch(compact, "^(\\d{1,2})([0-5]\\d)$", &match)
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
        IniWrite(event.Type, DataFile, section, "Type")
        IniWrite(event.Time, DataFile, section, "Time")
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
    menu.Add("Text", "x20 y52 w600 h36", "Create timed launcher events. Each event runs once per day at its scheduled time.")
    lv := menu.Add("ListView", "x20 y96 w600 h250 Grid -Multi", ["Event", "Type", "Time", "Countdown"])
    lv.ModifyCol(1, 190), lv.ModifyCol(2, 130), lv.ModifyCol(3, 100), lv.ModifyCol(4, 150)
    add := menu.Add("Button", "x20 y362 w185 h36 Default", "Schedule Event")
    edit := menu.Add("Button", "x218 y362 w185 h36", "Edit Selected")
    del := menu.Add("Button", "x416 y362 w204 h36", "Delete Selected")
    close := menu.Add("Button", "x416 y412 w204 h32", "Close")
    add.OnEvent("Click", (*) => OpenScheduledEventEditor(menu))
    edit.OnEvent("Click", (*) => EditSelectedScheduledEvent())
    del.OnEvent("Click", (*) => DeleteSelectedScheduledEvent())
    close.OnEvent("Click", (*) => CloseScheduledEventsMenu())
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
        ScheduledEventsListView.Add(, event.Name, ScheduledEventTypeLabel(event.Type), FormatScheduledEventTime(event.Time), FormatDailyLoginCountdown(GetScheduledEventSecondsRemaining(event)))
    if selected && selected <= ScheduledEvents.Length
        ScheduledEventsListView.Modify(selected, "Select Focus")
}

ScheduledEventTypeLabel(type)
{
    return type = "DailyLogin" ? "Daily Login" : type
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
    event := editing ? ScheduledEvents[eventIndex] : {Name: "Daily Login", Type: "DailyLogin", Time: "12:00"}
    editor := Gui("+Owner" owner.Hwnd " -MinimizeBox -MaximizeBox", editing ? "tes3np — Edit Event" : "tes3np — Schedule Event")
    editor.BackColor := "E2CEA2"
    editor.SetFont("s10 Bold c382314", "Segoe UI")
    editor.Add("Text", "x20 y20 w330 h22", "Event name")
    editor.SetFont("s10 c382314", "Segoe UI")
    nameEdit := editor.Add("Edit", "x20 y46 w330 h30", event.Name)
    editor.SetFont("s10 Bold c382314", "Segoe UI")
    editor.Add("Text", "x20 y92 w330 h22", "Event type")
    editor.SetFont("s10 c382314", "Segoe UI")
    typeList := editor.Add("DropDownList", "x20 y118 w330 h120 Choose1", ["Daily Login"])

    hour24 := Integer(SubStr(event.Time, 1, 2)), minute := SubStr(event.Time, 4, 2)
    displayHour := Mod(hour24, 12)
    if displayHour = 0
        displayHour := 12
    editor.SetFont("s10 Bold c382314", "Segoe UI")
    editor.Add("Text", "x20 y164 w60 h22", "Hour")
    editor.Add("Text", "x92 y164 w60 h22", "Minute")
    editor.Add("Text", "x164 y164 w90 h22", "Clock")
    editor.SetFont("s10 c382314", "Segoe UI")
    hourEdit := editor.Add("Edit", "x20 y190 w52 h28 Center Number", displayHour)
    minuteEdit := editor.Add("Edit", "x92 y190 w52 h28 Center Number", minute)
    clockMode := editor.Add("DropDownList", "x164 y190 w100 h120 Choose1", ["AM / PM", "24-hour"])
    meridiem := editor.Add("DropDownList", "x274 y190 w76 h120", ["AM", "PM"])
    meridiem.Choose(hour24 >= 12 ? 2 : 1)
    clockMode.OnEvent("Change", UpdateDailyLoginClockMode.Bind(hourEdit, meridiem, clockMode))
    save := editor.Add("Button", "x20 y244 w158 h34 Default", editing ? "Save Changes" : "Schedule Event")
    cancel := editor.Add("Button", "x192 y244 w158 h34", "Cancel")
    save.OnEvent("Click", SaveScheduledEventEditor.Bind(editor, eventIndex, nameEdit, typeList, hourEdit, minuteEdit, clockMode, meridiem))
    cancel.OnEvent("Click", (*) => editor.Destroy())
    editor.OnEvent("Escape", (*) => editor.Destroy())
    editor.Show("w370 h298")
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

SaveScheduledEventEditor(editor, eventIndex, nameEdit, typeList, hourEdit, minuteEdit, clockMode, meridiem, *)
{
    global ScheduledEvents, NextScheduledEventId
    name := Trim(nameEdit.Text)
    if name = ""
    {
        MsgBox("Enter a name for this event.", "tes3np")
        return
    }
    hourText := Trim(hourEdit.Text), minuteText := Trim(minuteEdit.Text)
    if !RegExMatch(hourText, "^\\d{1,2}$") || !RegExMatch(minuteText, "^\\d{1,2}$")
    {
        MsgBox("Choose a valid hour and minute.", "tes3np")
        return
    }
    hour := Integer(hourText), minute := Integer(minuteText)
    if minute > 59
    {
        MsgBox("Minutes must be between 00 and 59.", "tes3np")
        return
    }
    if clockMode.Value = 2
    {
        if hour > 23
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
    type := "DailyLogin"
    if eventIndex > 0 && eventIndex <= ScheduledEvents.Length
    {
        event := ScheduledEvents[eventIndex]
        event.Name := name, event.Type := type, event.Time := time
        event.LastRunDate := "", event.Due := false, event.PreviousRemaining := GetScheduledEventRawRemaining(time)
    }
    else
    {
        ScheduledEvents.Push({Id: NextScheduledEventId, Name: name, Type: type, Time: time, LastRunDate: "", Due: false, PreviousRemaining: GetScheduledEventRawRemaining(time)})
        NextScheduledEventId += 1
    }
    SaveScheduledEvents()
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

GetScheduledEventRawRemaining(time)
{
    now := A_Now
    target := SubStr(now, 1, 8) StrReplace(time, ":") "00"
    return DateDiff(target, now, "Seconds")
}

GetScheduledEventSecondsRemaining(event)
{
    today := FormatTime(, "yyyy-MM-dd")
    remaining := GetScheduledEventRawRemaining(event.Time)
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
        if event.LastRunDate = today
            continue
        remaining := GetScheduledEventRawRemaining(event.Time)
        crossed := event.PreviousRemaining > 0 && remaining <= 0
        event.PreviousRemaining := remaining
        if crossed
            event.Due := true
        if !event.Due
            continue
        if event.Type != "DailyLogin"
            continue

        gamePid := ProcessExist("tes3mp.exe")
        if Client.Enabled || gamePid
        {
            LogLauncherEvent("GAME | Scheduled event '" event.Name "' is due while TES3MP is already running; awaiting user choice.")
            choice := MsgBox("'" event.Name "' is ready, but TES3MP is already running.\n\nRun this event now? This will close the current TES3MP session.\n\nChoose No to cancel this event for today.", "Scheduled Event", "YesNo Icon?")
            if choice != "Yes"
            {
                CompleteScheduledEventForToday(event, "cancelled by user")
                continue
            }
            if Client.Enabled
            {
                currentPid := Client.PID
                StopClient()
                if currentPid && ProcessExist(currentPid)
                    try ProcessClose(currentPid)
            }
            else if gamePid
                try ProcessClose(gamePid)
            Sleep(500)
        }

        ActiveScheduledEventId := event.Id
        LogLauncherEvent("GAME | Scheduled event due | Name: " event.Name " | Type: Daily Login.")
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
    global Client, Profiles
    if Client.Enabled || Profiles.Length < 2
        return false
    executable := GetSharedExecutable()
    queue := []
    for profile in Profiles
    {
        if !ValidateLaunch(profile, executable)
            return false
        queue.Push(profile.Clone())
    }
    profile := queue.RemoveAt(1)
    LogLauncherEvent("GAME | Scheduled daily login starting. Characters: " (queue.Length + 1) ".")
    StartProfileSession(profile, executable, queue, true)
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

CompleteScheduledEventForToday(event, reason := "completed")
{
    event.LastRunDate := FormatTime(, "yyyy-MM-dd")
    event.Due := false
    SaveScheduledEvents()
    LogLauncherEvent("GAME | Scheduled event '" event.Name "' " reason " for today.")
    RefreshScheduledEventsList()
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
        CompleteScheduledEventForToday(event, "completed")
    ActiveScheduledEventId := ""
}

; Compatibility entry point for older UI callers.
OpenDailyLoginScheduleDialog(owner := 0, *)
{
    OpenScheduledEventsMenu(owner)
}
