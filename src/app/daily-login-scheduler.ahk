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

CheckDailyLoginSchedule(*)
{
    global DailyLoginScheduleEnabled, DailyLoginScheduleTime, DailyLoginLastRunDate
    global DataFile, AppDataDirectory, LaunchAllQueue, LaunchAllActive
    if !DailyLoginScheduleEnabled || LaunchAllActive
        return
    nowTime := FormatTime(, "HH:mm")
    today := FormatTime(, "yyyy-MM-dd")
    if nowTime != DailyLoginScheduleTime || DailyLoginLastRunDate = today
        return
    ; Do not interrupt a game/session the launcher is already managing.
    if IsSet(LaunchAllQueue) && LaunchAllQueue.Length
        return
    if !StartScheduledDailyLogin()
        return
    DailyLoginLastRunDate := today
    DirCreate(AppDataDirectory)
    IniWrite(today, DataFile, "DailyLogin", "LastRunDate")
}

StartScheduledDailyLogin()
{
    ; Session code supplies this reusable entry point. It intentionally skips the
    ; manual confirmation prompt while preserving the same validated queue.
    try return StartLaunchAllCharacters(true)
    catch
        return false
}
