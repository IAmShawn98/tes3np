; In-app scheduler for the optional daily multi-character login routine.
; Disabled by default and driven by the launcher's own timer, not Windows Task Scheduler.

global DailyLoginScheduleEnabled := false
global DailyLoginScheduleTime := "12:00"
global DailyLoginScheduleDisplay := "12:00"
global DailyLoginLastRunDate := ""

LoadDailyLoginSchedule()
{
    global DataFile, DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginScheduleDisplay, DailyLoginLastRunDate
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
    SetTimer(CheckDailyLoginSchedule, 30000)
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
    global DataFile, AppDataDirectory, DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginScheduleDisplay
    normalized := ParseDailyLoginTime(time)
    DailyLoginScheduleEnabled := enabled
    DailyLoginScheduleTime := normalized
    DailyLoginScheduleDisplay := Trim(time)
    DirCreate(AppDataDirectory)
    IniWrite(enabled ? "1" : "0", DataFile, "DailyLogin", "Scheduled")
    IniWrite(normalized, DataFile, "DailyLogin", "Time")
    IniWrite(DailyLoginScheduleDisplay, DataFile, "DailyLogin", "DisplayTime")
}

OpenDailyLoginScheduleDialog(owner := 0, *)
{
    global LauncherGui, DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginScheduleDisplay
    ownerHwnd := IsObject(owner) ? owner.Hwnd : LauncherGui.Hwnd
    schedule := Gui("+Owner" ownerHwnd " -MinimizeBox -MaximizeBox", "tes3np — Daily Login Schedule")
    schedule.BackColor := "E2CEA2"
    schedule.SetFont("s11 Bold c241408", "Segoe UI")
    schedule.Add("Text", "x20 y18 w330 h26", "Daily Login Points")
    schedule.SetFont("s9 c382314", "Segoe UI")
    schedule.Add("Text", "x20 y50 w330 h50", "Optionally run Launch All & Close once each day while tes3np is open. This setting is off by default.")
    schedule.SetFont("s9 Bold c382314", "Segoe UI")
    enabled := schedule.Add("CheckBox", "x20 y112 w330 h24", "Run automatically every day")
    enabled.Value := DailyLoginScheduleEnabled ? 1 : 0
    schedule.Add("Text", "x20 y154 w110 h22", "Daily time")
    schedule.SetFont("s10 c382314", "Segoe UI")
    timeEdit := schedule.Add("Edit", "x140 y150 w140 h26 Center", DailyLoginScheduleDisplay)
    schedule.SetFont("s8 c5A4027", "Segoe UI")
    schedule.Add("Text", "x20 y184 w330 h48", "Enter the time however you prefer, such as 9 PM, 9:30 PM, 21:30, or 2130. The launcher must be running at that time.")
    save := schedule.Add("Button", "x20 y234 w158 h34 Default", "Save")
    cancel := schedule.Add("Button", "x192 y234 w158 h34", "Cancel")
    save.OnEvent("Click", SaveDailyLoginScheduleDialog.Bind(schedule, enabled, timeEdit))
    cancel.OnEvent("Click", (*) => schedule.Destroy())
    schedule.OnEvent("Escape", (*) => schedule.Destroy())
    schedule.Show("w370 h288")
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

CheckDailyLoginSchedule(*)
{
    global DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginLastRunDate
    global DataFile, AppDataDirectory, Client
    if !DailyLoginScheduleEnabled || Client.Enabled
        return
    nowTime := FormatTime(, "HH:mm")
    today := FormatTime(, "yyyy-MM-dd")
    if nowTime != DailyLoginScheduleTime || DailyLoginLastRunDate = today
        return
    if !StartScheduledDailyLogin()
        return
    DailyLoginLastRunDate := today
    DirCreate(AppDataDirectory)
    IniWrite(today, DataFile, "DailyLogin", "LastRunDate")
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
