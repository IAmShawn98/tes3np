; Portable INI backups deliberately contain readable credentials.
; Local settings continue to use Windows DPAPI; never log backup contents.
TransferLauncherData(*)
{
    global Profiles, CharacterPage
    CharacterPage.Opt("+OwnDialogs")
    if Profiles.Length
        ExportLauncherData()
    else
        ImportLauncherData()
}

ExportLauncherData()
{
    global Profiles, SelectedProfile, DataFile, CharacterPage, ScheduledEvents, ScheduledCountdownHotkey
    if MsgBox("This portable backup includes your characters, settings, and readable passwords so it can work on another computer. Keep it private. Continue?", "Export Data", 0x124) != "Yes"
        return
    path := FileSelect("S16", "tes3np-backup.ini", "Export launcher data", "Launcher backup (*.ini)")
    if path = ""
        return
    if !RegExMatch(path, "i)\.ini$")
        path .= ".ini"
    if StrLower(path) = StrLower(DataFile)
    {
        MsgBox("Choose a backup location outside the live settings file.", "Export Data")
        return
    }
    temporary := path "." DllCall("GetCurrentProcessId", "UInt") ".tmp"
    try
    {
        if FileExist(temporary)
            FileDelete(temporary)
        IniWrite("tes3np", temporary, "Backup", "Application")
        IniWrite("1", temporary, "Backup", "Version")
        IniWrite("HexUTF8", temporary, "Backup", "Passwords")
        IniWrite(Profiles.Length, temporary, "Profiles", "Count")
        IniWrite(SelectedProfile, temporary, "Profiles", "Selected")
        IniWrite(GetSharedExecutable(), temporary, "Launch", "Executable")
        IniWrite(IniRead(DataFile, "Launcher", "HideLaunchAllExplanation", "0"), temporary, "Launcher", "HideLaunchAllExplanation")
        for index, profile in Profiles
        {
            section := "Character" index
            IniWrite(profile.Name, temporary, section, "Name")
            IniWrite(profile.HasOwnProp("Species") ? NormalizeCharacterSpecies(profile.Species) : "", temporary, section, "Species")
            IniWrite(EncodeBackupPassword(profile.Password), temporary, section, "Password")
            IniWrite(profile.UsernameDelay, temporary, section, "Username")
            IniWrite(profile.PasswordDelay, temporary, section, "PasswordDelay")
            IniWrite(profile.LoadDelay, temporary, section, "Load")
            IniWrite(profile.AutoReconnect ? "1" : "0", temporary, section, "AutoReconnect")
        }
        ; Include scheduler configuration in the same portable backup. Copy the
        ; in-memory event state so exporting never stops/restarts its live timer.
        IniWrite(ScheduledEvents.Length, temporary, "ScheduledEvents", "Count")
        IniWrite(ScheduledCountdownHotkey, temporary, "ScheduledEvents", "Hotkey")
        for index, event in ScheduledEvents
        {
            section := "ScheduledEvent" index
            IniWrite(event.Id, temporary, section, "Id")
            IniWrite(event.Name, temporary, section, "Name")
            IniWrite(event.HasOwnProp("TimeBasis") ? event.TimeBasis : "IRL", temporary, section, "TimeBasis")
            IniWrite(event.Time, temporary, section, "Time")
            IniWrite(event.HasOwnProp("Mode") ? event.Mode : "IRL", temporary, section, "Mode")
            IniWrite(event.HasOwnProp("DurationSeconds") ? event.DurationSeconds : 0, temporary, section, "DurationSeconds")
            IniWrite(event.HasOwnProp("StartedAt") ? event.StartedAt : "", temporary, section, "StartedAt")
            IniWrite(event.HasOwnProp("LoginAction") ? event.LoginAction : "LoginCloseAll", temporary, section, "LoginAction")
            IniWrite(event.HasOwnProp("LoginProfiles") ? event.LoginProfiles : "", temporary, section, "LoginProfiles")
            IniWrite(event.Recurring ? "1" : "0", temporary, section, "Recurring")
            IniWrite(event.HasOwnProp("Locked") && event.Locked ? "1" : "0", temporary, section, "Locked")
            IniWrite(event.HasOwnProp("Armed") && event.Armed ? "1" : "0", temporary, section, "Armed")
            IniWrite(event.HasOwnProp("Completed") && event.Completed ? "1" : "0", temporary, section, "Completed")
            IniWrite(event.HasOwnProp("LastRunDate") ? event.LastRunDate : "", temporary, section, "LastRunDate")
        }
        FileMove(temporary, path, true)
        MsgBox("Launcher data exported. This file contains readable passwords; store it privately.", "Export Data")
    }
    catch
        MsgBox("The backup could not be written. Choose a writable location and try again.", "Export Data")
    finally
    {
        if FileExist(temporary)
            try FileDelete(temporary)
    }
}

ImportLauncherData()
{
    global Profiles, SelectedProfile, DataFile, Client, MaxCharacters, ExecutableInput, ScheduledEvents, NextScheduledEventId, ScheduledCountdownHotkey
    if Profiles.Length || Client.Enabled
        return
    path := FileSelect(1, , "Import launcher data", "Launcher backup (*.ini)")
    if path = ""
        return
    temporary := DataFile ".import.tmp"
    try
    {
        if FileGetSize(path) > 1048576
            throw Error("Backup is too large")
        if IniRead(path, "Backup", "Application", "") != "tes3np" || IniRead(path, "Backup", "Version", "") != "1" || IniRead(path, "Backup", "Passwords", "") != "HexUTF8"
            throw Error("Unsupported backup")
        count := ReadBackupInteger(path, "Profiles", "Count", 1, MaxCharacters)
        selected := ReadBackupInteger(path, "Profiles", "Selected", 0, count)
        restored := []
        Loop count
        {
            section := "Character" A_Index
            name := IniRead(path, section, "Name", "")
            password := DecodeBackupPassword(IniRead(path, section, "Password", ""))
            rawSpecies := IniRead(path, section, "Species", "")
            species := NormalizeCharacterSpecies(rawSpecies)
            if rawSpecies != "" && species = ""
                throw Error("Invalid character species")
            if Trim(name) = "" || StrLen(name) > 256 || RegExMatch(name, "[\r\n]") || StrLen(password) > 4096 || RegExMatch(password, "[\r\n]")
                throw Error("Invalid character")
            restored.Push({Name: name, Password: password, Species: species,
                UsernameDelay: ReadBackupInteger(path, section, "Username", 1, 300),
                PasswordDelay: ReadBackupInteger(path, section, "PasswordDelay", 1, 300),
                LoadDelay: ReadBackupInteger(path, section, "Load", 1, 300),
                AutoReconnect: ReadBackupInteger(path, section, "AutoReconnect", 0, 1) = 1})
        }
        executable := IniRead(path, "Launch", "Executable", "")
        SplitPath(executable, &filename)
        pathReset := !FileExist(executable) || StrLower(filename) != "tes3mp.exe"
        if pathReset
            executable := ""
        suppress := ReadBackupInteger(path, "Launcher", "HideLaunchAllExplanation", 0, 1)
        restoredEvents := []
        eventCountText := IniRead(path, "ScheduledEvents", "Count", "0")
        eventCount := RegExMatch(eventCountText, "^\d+$") ? Integer(eventCountText) : 0
        if eventCount > 100
            throw Error("Too many scheduled events")
        maxEventId := 0
        Loop eventCount
        {
            section := "ScheduledEvent" A_Index
            id := ReadBackupInteger(path, section, "Id", 1, 999999)
            name := IniRead(path, section, "Name", "")
            time := IniRead(path, section, "Time", "12:00")
            try time := ParseDailyLoginTime(time)
            catch
                throw Error("Invalid scheduled event time")
            mode := IniRead(path, section, "Mode", "IRL")
            if mode != "IRL" && mode != "Countdown"
                throw Error("Invalid scheduled event mode")
            duration := ReadBackupInteger(path, section, "DurationSeconds", 0, 999999)
            action := IniRead(path, section, "LoginAction", "LoginCloseAll")
            if action != "LoginCloseAll" && action != "LoginUpTo4" && action != "AlertOnly"
                throw Error("Invalid scheduled event action")
            loginProfiles := IniRead(path, section, "LoginProfiles", "")
            startedAt := IniRead(path, section, "StartedAt", "")
            recurring := ReadBackupInteger(path, section, "Recurring", 0, 1) = 1
            locked := ReadBackupInteger(path, section, "Locked", 0, 1) = 1
            armed := ReadBackupInteger(path, section, "Armed", 0, 1) = 1
            completed := ReadBackupInteger(path, section, "Completed", 0, 1) = 1
            lastRun := IniRead(path, section, "LastRunDate", "")
            restoredEvents.Push({Id: id, Name: name, TimeBasis: "IRL", Time: time, Mode: mode, DurationSeconds: duration,
                StartedAt: startedAt, LoginAction: action, LoginProfiles: loginProfiles, Recurring: recurring, Locked: locked,
                Armed: armed, Completed: completed, LastRunDate: lastRun, Due: false,
                PreviousRemaining: mode = "Countdown" && startedAt = "" ? 1 : GetScheduledEventRawRemaining(time, "IRL")})
            maxEventId := Max(maxEventId, id)
        }
        restoredHotkey := IniRead(path, "ScheduledEvents", "Hotkey", "F8")
        ; Validate everything and encrypt every password before replacing live settings.
        DirCreate(AppDataDirectory)
        if FileExist(temporary)
            FileDelete(temporary)
        IniWrite(count, temporary, "Profiles", "Count")
        IniWrite(selected, temporary, "Profiles", "Selected")
        IniWrite(executable, temporary, "Launch", "Executable")
        IniWrite(suppress, temporary, "Launcher", "HideLaunchAllExplanation")
        ; Import replaces the live INI. Preserve this device's onboarding
        ; preference so restoring characters does not re-offer a shortcut.
        shortcutChoice := IniRead(DataFile, "Launcher", "DesktopShortcutChoice", "")
        if shortcutChoice = "Yes" || shortcutChoice = "No"
            IniWrite(shortcutChoice, temporary, "Launcher", "DesktopShortcutChoice")
        for index, profile in restored
        {
            section := "Character" index
            IniWrite(profile.Name, temporary, section, "Name")
            IniWrite(profile.Species, temporary, section, "Species")
            IniWrite(ProtectPassword(profile.Password), temporary, section, "Password")
            IniWrite(profile.UsernameDelay, temporary, section, "Username")
            IniWrite(profile.PasswordDelay, temporary, section, "PasswordDelay")
            IniWrite(profile.LoadDelay, temporary, section, "Load")
            IniWrite(profile.AutoReconnect ? "1" : "0", temporary, section, "AutoReconnect")
        }
        IniWrite(restoredEvents.Length, temporary, "ScheduledEvents", "Count")
        IniWrite(restoredHotkey, temporary, "ScheduledEvents", "Hotkey")
        for index, event in restoredEvents
        {
            section := "ScheduledEvent" index
            IniWrite(event.Id, temporary, section, "Id")
            IniWrite(event.Name, temporary, section, "Name")
            IniWrite(event.TimeBasis, temporary, section, "TimeBasis")
            IniWrite(event.Time, temporary, section, "Time")
            IniWrite(event.Mode, temporary, section, "Mode")
            IniWrite(event.DurationSeconds, temporary, section, "DurationSeconds")
            IniWrite(event.StartedAt, temporary, section, "StartedAt")
            IniWrite(event.LoginAction, temporary, section, "LoginAction")
            IniWrite(event.LoginProfiles, temporary, section, "LoginProfiles")
            IniWrite(event.Recurring ? "1" : "0", temporary, section, "Recurring")
            IniWrite(event.Locked ? "1" : "0", temporary, section, "Locked")
            IniWrite(event.Armed ? "1" : "0", temporary, section, "Armed")
            IniWrite(event.Completed ? "1" : "0", temporary, section, "Completed")
            IniWrite(event.LastRunDate, temporary, section, "LastRunDate")
        }
        FileMove(temporary, DataFile, true)
    }
    catch
    {
        MsgBox("Import failed. Select a valid tes3np Export Data backup. Your current settings were not changed.", "Import Data")
        return
    }
    finally
    {
        if FileExist(temporary)
            try FileDelete(temporary)
    }
    BeginInterfaceUpdate(0, "Restoring launcher data...", true)
    try
    {
        HideProfileEditor()
        Profiles := restored
        SelectedProfile := selected
        ScheduledEvents := restoredEvents
        NextScheduledEventId := maxEventId + 1
        ScheduledCountdownHotkey := restoredHotkey
        ; The standalone character book can omit the legacy executable edit.
        ; OpenCharacterPage initializes that placeholder to integer 0.
        ; The imported executable path was already persisted to DataFile.
        if IsObject(ExecutableInput)
            ExecutableInput.Value := executable
        UpdateCharacterMenuLabel()
        RefreshProfiles()
        ; RefreshProfiles can rebuild/relabel the Characters page before the
        ; imported scheduler state is reflected in its painted button.
        RefreshDailyLoginButton()
    }
    finally EndInterfaceUpdate()
    MsgBox("Launcher data imported." (pathReset ? " Select tes3mp.exe with Browse on this computer." : ""), "Import Data")
}

ReadBackupInteger(path, section, key, minimum, maximum)
{
    value := IniRead(path, section, key, "")
    if !RegExMatch(value, "^\d+$") || StrLen(value) > 6
        throw Error("Invalid backup setting")
    number := Integer(value)
    if number < minimum || number > maximum
        throw Error("Backup setting out of range")
    return number
}

; Encoding preserves spaces, quotes and Unicode. It is not encryption.
EncodeBackupPassword(value)
{
    size := StrPut(value, "UTF-8")
    bytes := Buffer(size, 0)
    StrPut(value, bytes, "UTF-8")
    encoded := ""
    Loop size - 1
        encoded .= Format("{:02X}", NumGet(bytes, A_Index - 1, "UChar"))
    return encoded
}

DecodeBackupPassword(value)
{
    if StrLen(value) > 32768 || !RegExMatch(value, "^(?:[0-9A-Fa-f]{2})*$")
        throw Error("Invalid backup password")
    size := StrLen(value) // 2
    bytes := Buffer(size + 1, 0)
    Loop size
        NumPut("UChar", Integer("0x" SubStr(value, A_Index * 2 - 1, 2)), bytes, A_Index - 1)
    return StrGet(bytes, "UTF-8")
}
