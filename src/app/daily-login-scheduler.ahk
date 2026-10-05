; In-app scheduler for the optional daily multi-character login routine.
; Disabled by default and driven by the launcher's own timer, not Windows Task Scheduler.

global DailyLoginScheduleEnabled := false
global DailyLoginScheduleTime := "12:00"
global DailyLoginLastRunDate := ""

LoadDailyLoginSchedule()
{
    global DataFile, DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginLastRunDate
    DailyLoginScheduleEnabled := IniRead(DataFile, "DailyLogin", "Scheduled", "0") = "1"
    DailyLoginScheduleTime := IniRead(DataFile, "DailyLogin", "Time", "12:00")
    DailyLoginLastRunDate := IniRead(DataFile, "DailyLogin", "LastRunDate", "")
    if !RegExMatch(DailyLoginScheduleTime, "^(?:[01]\d|2[0-3]):[0-5]\d$")
        DailyLoginScheduleTime := "12:00"
    SetTimer(CheckDailyLoginSchedule, 30000)
}

SaveDailyLoginSchedule(enabled, time)
{
    global DataFile, AppDataDirectory, DailyLoginScheduleEnabled, DailyLoginScheduleTime
    if !RegExMatch(time, "^(?:[01]\d|2[0-3]):[0-5]\d$")
        throw Error("Choose a valid time in 24-hour HH:MM format.")
    DailyLoginScheduleEnabled := enabled
    DailyLoginScheduleTime := time
    DirCreate(AppDataDirectory)
    IniWrite(enabled ? "1" : "0", DataFile, "DailyLogin", "Scheduled")
    IniWrite(time, DataFile, "DailyLogin", "Time")
}

OpenDailyLoginScheduleSettings(owner := 0, *)
{
    global LauncherGui, DailyLoginScheduleEnabled, DailyLoginScheduleTime
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
    timeEdit := schedule.Add("Edit", "x140 y150 w100 h26 Center", DailyLoginScheduleTime)
    schedule.SetFont("s8 c5A4027", "Segoe UI")
    schedule.Add("Text", "x20 y184 w330 h38", "Use 24-hour time (HH:MM), such as 09:30 or 21:00. The launcher must be running at that time.")
    save := schedule.Add("Button", "x20 y234 w158 h34 Default", "Save")
    cancel := schedule.Add("Button", "x192 y234 w158 h34", "Cancel")
    enabled.OnEvent("Click", PromptDailyLoginTime.Bind(enabled, timeEdit))
    save.OnEvent("Click", SaveDailyLoginScheduleDialog.Bind(schedule, enabled, timeEdit))
    cancel.OnEvent("Click", (*) => schedule.Destroy())
    schedule.OnEvent("Escape", (*) => schedule.Destroy())
    schedule.Show("w370 h288")
}

PromptDailyLoginTime(enabled, timeEdit, *)
{
    if !enabled.Value
        return
    result := InputBox("What time should tes3np run the daily character logins?`n`nUse 24-hour HH:MM format.", "tes3np — Daily Login Time", "w360 h150", timeEdit.Text)
    if result.Result != "OK"
    {
        enabled.Value := 0
        return
    }
    if !RegExMatch(result.Value, "^(?:[01]\d|2[0-3]):[0-5]\d$")
    {
        MsgBox("Enter a valid time such as 09:30 or 21:00.", "tes3np")
        enabled.Value := 0
        return
    }
    timeEdit.Text := result.Value
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
