; In-app scheduler for the optional daily multi-character login routine.
; Disabled by default and driven by the launcher's own timer, not Windows Task Scheduler.

global DailyLoginScheduleEnabled := false
global DailyLoginScheduleTime := "12:00"
global DailyLoginScheduleDisplay := "12:00"
global DailyLoginLastRunDate := ""
global DailyLoginLastCheckMinute := ""
global DailyLoginCountdownTarget := ""
global DailyLoginScheduleDue := false

LoadDailyLoginSchedule()
{
    global DataFile, DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginScheduleDisplay, DailyLoginLastRunDate, DailyLoginScheduleDue
    DailyLoginScheduleEnabled := IniRead(DataFile, "DailyLogin", "Scheduled", "0") = "1"
    DailyLoginScheduleTime := IniRead(DataFile, "DailyLogin", "Time", "12:00")
    DailyLoginScheduleDisplay := IniRead(DataFile, "DailyLogin", "DisplayTime", DailyLoginScheduleTime)
    DailyLoginLastRunDate := IniRead(DataFile, "DailyLogin", "LastRunDate", "")
    try DailyLoginScheduleTime := ParseDailyLoginTime(DailyLoginScheduleDisplay)
    catch
    {
        DailyLoginScheduleTime := "12:00"
        DailyLoginScheduleDisplay := "12:00"
    }
    DailyLoginScheduleDue := false
    SetTimer(CheckDailyLoginSchedule, 1000)
    SetTimer(UpdateDailyLoginCountdown, 1000)
}

ParseDailyLoginTime(value)
{
    value := Trim(value)
    compact := RegExReplace(StrLower(value), "\s+", "")
    compact := StrReplace(compact, ".", "")
    if compact = ""
        throw Error("Enter a time for Daily Login.")

    ; 12-hour input: 9 PM, 9pm, 9:30 p.m., 09:30AM.
    if RegExMatch(compact, "^(1[0-2]|0?[1-9])(?::?([0-5]\d))?(am|pm)$", &match)
    {
        hour := Integer(match[1])
        minute := match[2] = "" ? 0 : Integer(match[2])
        if match[3] = "am"
            hour := hour = 12 ? 0 : hour
        else
            hour := hour = 12 ? 12 : hour + 12
        return Format("{:02}:{:02}", hour, minute)
    }

    ; 24-hour input: 21:00, 9:30, 21, 9.
    if RegExMatch(compact, "^(2[0-3]|[01]?\d)(?::([0-5]\d))?$", &match)
        return Format("{:02}:{:02}", Integer(match[1]), match[2] = "" ? 0 : Integer(match[2]))

    ; Clock-style shorthand: 930, 0930, 2130.
    if RegExMatch(compact, "^(\d{1,2})([0-5]\d)$", &match)
    {
        hour := Integer(match[1])
        if hour <= 23
            return Format("{:02}:{:02}", hour, Integer(match[2]))
    }
    throw Error("Enter a time such as 9 PM, 9:30 PM, 21:30, 9:30, or 2130.")
}

SaveDailyLoginSchedule(enabled, time)
{
    global DataFile, AppDataDirectory, DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginScheduleDisplay, DailyLoginScheduleDue
    normalized := ParseDailyLoginTime(time)
    DailyLoginScheduleEnabled := enabled
    DailyLoginScheduleTime := normalized
    DailyLoginScheduleDisplay := Trim(time)
    DailyLoginScheduleDue := false
    DirCreate(AppDataDirectory)
    IniWrite(enabled ? "1" : "0", DataFile, "DailyLogin", "Scheduled")
    IniWrite(normalized, DataFile, "DailyLogin", "Time")
    IniWrite(DailyLoginScheduleDisplay, DataFile, "DailyLogin", "DisplayTime")
    RefreshDailyLoginButton()
}

OpenDailyLoginScheduleDialog(owner := 0, *)
{
    global LauncherGui, DailyLoginScheduleEnabled, DailyLoginScheduleTime
    ownerHwnd := IsObject(owner) ? owner.Hwnd : LauncherGui.Hwnd
    schedule := Gui("+Owner" ownerHwnd " -MinimizeBox -MaximizeBox", "tes3np — Daily Login Schedule")
    schedule.BackColor := "E2CEA2"
    schedule.SetFont("s11 Bold c241408", "Segoe UI")
    schedule.Add("Text", "x20 y18 w330 h26", "Daily Login Points")
    schedule.SetFont("s9 c382314", "Segoe UI")
    schedule.Add("Text", "x20 y50 w330 h50", "Choose when tes3np should automatically log every saved character in and out for daily login points.")
    schedule.SetFont("s9 Bold c382314", "Segoe UI")
    enabled := schedule.Add("CheckBox", "x20 y108 w330 h24", "Enable daily login schedule")
    enabled.Value := DailyLoginScheduleEnabled ? 1 : 0

    schedule.Add("Text", "x20 y148 w52 h22", "Hour")
    schedule.Add("Text", "x92 y148 w52 h22", "Minute")
    schedule.Add("Text", "x164 y148 w90 h22", "Clock")
    schedule.SetFont("s10 c382314", "Segoe UI")

    currentHour := Integer(SubStr(DailyLoginScheduleTime, 1, 2))
    currentMinute := SubStr(DailyLoginScheduleTime, 4, 2)
    use24 := currentHour > 12
    displayHour := use24 ? currentHour : (currentHour = 0 ? 12 : currentHour > 12 ? currentHour - 12 : currentHour)
    hourEdit := schedule.Add("Edit", "x20 y172 w52 h28 Center Number", displayHour)
    minuteEdit := schedule.Add("Edit", "x92 y172 w52 h28 Center Number", currentMinute)
    clockMode := schedule.Add("DropDownList", "x164 y172 w100 h120 Choose1", ["AM / PM", "24-hour"])
    meridiem := schedule.Add("DropDownList", "x274 y172 w76 h120", ["AM", "PM"])
    if use24
    {
        clockMode.Choose(2)
        hourEdit.Text := currentHour
        meridiem.Enabled := false
    }
    else
        meridiem.Choose(currentHour >= 12 ? 2 : 1)

    clockMode.OnEvent("Change", UpdateDailyLoginClockMode.Bind(hourEdit, meridiem, clockMode))
    schedule.SetFont("s8 c5A4027", "Segoe UI")
    schedule.Add("Text", "x20 y210 w330 h34", "Choose AM/PM or switch to a 24-hour clock to match your regional preference.")
    save := schedule.Add("Button", "x20 y250 w158 h34 Default", "Save")
    cancel := schedule.Add("Button", "x192 y250 w158 h34", "Cancel")
    save.OnEvent("Click", SaveDailyLoginClockDialog.Bind(schedule, enabled, hourEdit, minuteEdit, clockMode, meridiem))
    cancel.OnEvent("Click", (*) => schedule.Destroy())
    schedule.OnEvent("Escape", (*) => schedule.Destroy())
    schedule.Show("w370 h304")
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

SaveDailyLoginClockDialog(schedule, enabled, hourEdit, minuteEdit, clockMode, meridiem, *)
{
    hourText := Trim(hourEdit.Text)
    minuteText := Trim(minuteEdit.Text)
    if !RegExMatch(hourText, "^\d{1,2}$") || !RegExMatch(minuteText, "^\d{1,2}$")
    {
        MsgBox("Choose a valid hour and minute.", "tes3np")
        return
    }
    hour := Integer(hourText), minute := Integer(minuteText)
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
        value := Format("{:02}:{:02}", hour, minute)
    }
    else
    {
        if hour < 1 || hour > 12
        {
            MsgBox("AM/PM time uses hours 1 through 12.", "tes3np")
            return
        }
        value := hour ":" Format("{:02}", minute) " " meridiem.Text
    }
    try SaveDailyLoginSchedule(enabled.Value = 1, value)
    catch Error as err
    {
        MsgBox(err.Message, "tes3np")
        return
    }
    schedule.Destroy()
}

SaveDailyLoginScheduleDialog(schedule, enabled, timeEdit, *)
{
    try SaveDailyLoginSchedule(enabled.Value = 1, Trim(timeEdit.Text))
    catch Error as err
    {
        MsgBox(err.Message, "tes3np")
        return
    }
    schedule.Destroy()
}

RefreshDailyLoginButton()
{
    global V016DailyLoginControls, DailyLoginScheduleEnabled, DailyLoginScheduleTime
    if !IsObject(V016DailyLoginControls) || V016DailyLoginControls.Length < 1
        return
    button := V016DailyLoginControls[1]
    if !DailyLoginScheduleEnabled
    {
        button.Text := "Daily Login: Off"
        return
    }
    button.Text := "Daily Login — " FormatDailyLoginCountdown(GetDailyLoginSecondsRemaining())
}

GetDailyLoginSecondsRemaining()
{
    global DailyLoginScheduleTime, DailyLoginLastRunDate, DailyLoginScheduleDue
    now := A_Now
    today := FormatTime(, "yyyy-MM-dd")
    target := SubStr(now, 1, 8) StrReplace(DailyLoginScheduleTime, ":") "00"
    remaining := DateDiff(target, now, "Seconds")
    ; Do not visually roll over to tomorrow until today's scheduled action has
    ; actually started successfully.
    if (remaining <= 0 || DailyLoginScheduleDue) && DailyLoginLastRunDate != today
        return 0
    if remaining <= 0
        target := DateAdd(target, 1, "Days")
    return Max(0, DateDiff(target, now, "Seconds"))
}

FormatDailyLoginCountdown(seconds)
{
    hours := Floor(seconds / 3600)
    minutes := Floor(Mod(seconds, 3600) / 60)
    secs := Mod(seconds, 60)
    return Format("{:02}:{:02}:{:02}", hours, minutes, secs)
}

UpdateDailyLoginCountdown(*)
{
    global DailyLoginScheduleEnabled
    if DailyLoginScheduleEnabled
        RefreshDailyLoginButton()
}

CheckDailyLoginSchedule(*)
{
    global DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginLastRunDate, DailyLoginScheduleDue
    global DataFile, AppDataDirectory, Client
    if !DailyLoginScheduleEnabled
        return

    today := FormatTime(, "yyyy-MM-dd")
    if DailyLoginLastRunDate = today
        return

    ; Latch the schedule once its target has been reached. This prevents the UI
    ; countdown from rolling into tomorrow before the actual login sequence has
    ; successfully begun.
    if GetDailyLoginSecondsRemainingRaw() <= 0
        DailyLoginScheduleDue := true
    if !DailyLoginScheduleDue || Client.Enabled
        return

    LogLauncherEvent("GAME | Daily Login countdown reached zero; starting scheduled login.")
    if !StartScheduledDailyLogin()
    {
        LogLauncherEvent("GAME | Daily Login is due but could not start; will retry.")
        return
    }

    DailyLoginLastRunDate := today
    DailyLoginScheduleDue := false
    DirCreate(AppDataDirectory)
    IniWrite(today, DataFile, "DailyLogin", "LastRunDate")
}

GetDailyLoginSecondsRemainingRaw()
{
    global DailyLoginScheduleTime
    now := A_Now
    target := SubStr(now, 1, 8) StrReplace(DailyLoginScheduleTime, ":") "00"
    return DateDiff(target, now, "Seconds")
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
        {
            LogLauncherEvent("GAME | Scheduled daily login skipped because a character or executable needs attention.")
            return false
        }
        queue.Push(profile.Clone())
    }
    profile := queue.RemoveAt(1)
    LogLauncherEvent("GAME | Scheduled daily login starting. Characters: " (queue.Length + 1) ".")
    StartProfileSession(profile, executable, queue)
    return true
}
