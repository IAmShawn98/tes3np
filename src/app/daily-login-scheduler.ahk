; Multi-event scheduler. Daily Login is the first supported scheduled action.
; Events recur once per day at their configured local clock time.

global ScheduledEvents := []
global ScheduledEventsListView := 0
global ScheduledEventsWindow := 0
global ActiveScheduledEventId := ""
global NextScheduledEventId := 1
global ScheduledCountdownHotkey := "F8"
global ScheduledCountdownArmedEventId := ""


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
        completed := IniRead(DataFile, section, "Completed", "0") = "1"
        mode := IniRead(DataFile, section, "Mode", "IRL")
        durationSeconds := Integer(IniRead(DataFile, section, "DurationSeconds", "0"))
        startedAt := IniRead(DataFile, section, "StartedAt", "")
        try time := ParseDailyLoginTime(time)
        catch
            continue
        ScheduledEvents.Push({Id: id, Name: name, TimeBasis: timeBasis, Time: time, Mode: mode, DurationSeconds: durationSeconds, StartedAt: startedAt, Recurring: recurring, Completed: completed, LastRunDate: lastRun, Due: false, PreviousRemaining: mode = "Countdown" && startedAt = "" ? 1 : GetScheduledEventRawRemaining(time, timeBasis)})
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
    ; Strip our own pass-through/wildcard prefixes before rebuilding the binding.
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
    currentKey := DisplayScheduledCountdownHotkey(ScheduledCountdownHotkey)
    result := InputBox("Enter any AutoHotkey key name to start an armed countdown while you are in-game. Examples: F1, F8, F12, J, Space, Numpad1", "Countdown Hotkey",, currentKey)
    if result.Result != "OK" || Trim(result.Value) = ""
        return
    newKey := NormalizeScheduledCountdownHotkey(result.Value)
    oldKey := ScheduledCountdownHotkey
    try Hotkey(oldKey, "Off")
    try Hotkey(newKey, StartArmedScheduledCountdown, "On")
    catch
    {
        try Hotkey(oldKey, StartArmedScheduledCountdown, "On")
        MsgBox("That key is not a valid AutoHotkey key name.", "tes3np")
        return
    }
    ScheduledCountdownHotkey := newKey
    cleanKey := DisplayScheduledCountdownHotkey(newKey)
    IniWrite(cleanKey, DataFile, "ScheduledEvents", "CountdownHotkey")
    button.Text := "Hotkey: " cleanKey
}

ArmSelectedScheduledCountdown(*)
{
    global ScheduledEventsListView, ScheduledEvents, ScheduledCountdownArmedEventId, ScheduledCountdownHotkey
    row := IsObject(ScheduledEventsListView) ? ScheduledEventsListView.GetNext() : 0
    if !row
    {
        MsgBox("Select a countdown event to arm.", "tes3np")
        return
    }
    event := ScheduledEvents[row]
    if !event.HasOwnProp("Mode") || event.Mode != "Countdown"
    {
        MsgBox("The selected event is not a countdown.", "tes3np")
        return
    }
    event.StartedAt := ""
    event.Due := false
    event.Completed := false
    ScheduledCountdownArmedEventId := event.Id
    SaveScheduledEvents()
    RefreshScheduledEventsList()
    MsgBox("'" event.Name "' is armed. Press " DisplayScheduledCountdownHotkey(ScheduledCountdownHotkey) " in-game exactly when you want the countdown to start.", "Countdown Armed")
}

StartArmedScheduledCountdown(*)
{
    global ScheduledCountdownArmedEventId, ScheduledEvents
    event := ScheduledCountdownArmedEventId != "" ? FindScheduledEventById(ScheduledCountdownArmedEventId) : 0
    if !IsObject(event)
    {
        ; Fall back to the first waiting countdown so the hotkey still works
        ; after reopening the launcher or if explicit arm state was lost.
        for candidate in ScheduledEvents
        {
            if candidate.HasOwnProp("Mode") && candidate.Mode = "Countdown" && candidate.StartedAt = "" && !(candidate.HasOwnProp("Completed") && candidate.Completed)
            {
                event := candidate
                break
            }
        }
    }
    if !IsObject(event)
    {
        TrayTip("No countdown armed", "Create or arm a countdown first.", "Icon!")
        return
    }
    event.StartedAt := A_Now
    event.LastRunDate := ""
    event.Due := false
    event.PreviousRemaining := event.DurationSeconds
    ScheduledCountdownArmedEventId := ""
    SaveScheduledEvents()
    RefreshScheduledEventsList()
    TrayTip("Countdown started", "'" event.Name "' started.", "Iconi")
}

; Compatibility entry point for older UI callers.
OpenDailyLoginScheduleDialog(owner := 0, *)
{
    OpenScheduledEventsMenu(owner)
}
