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
    global Profiles, SelectedProfile, DataFile, CharacterPage
    ; The v1 portable INI has no binary attachment container. Custom pictures
    ; remain local; imported characters retain their real race and stock icon.
    if MsgBox("This portable backup includes your characters, settings, and readable passwords. Original Character portrait images are stored locally and are NOT included in the INI backup. Keep it private. Continue?", "Export Data", 0x124) != "Yes"
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
        IniWrite(IniRead(DataFile, "Launcher", "HideFavoriteSwitchExplanation", "0"), temporary, "Launcher", "HideFavoriteSwitchExplanation")
        for index, profile in Profiles
        {
            section := "Character" index
            IniWrite(profile.Name, temporary, section, "Name")
            IniWrite(profile.HasOwnProp("Species") ? NormalizeCharacterSpecies(profile.Species) : "", temporary, section, "Species")
            IniWrite(EncodeBackupPassword(profile.Password), temporary, section, "Password")
            IniWrite(profile.UsernameDelay, temporary, section, "Username")
            IniWrite(profile.PasswordDelay, temporary, section, "PasswordDelay")
            IniWrite(profile.LoadDelay, temporary, section, "Load")
            ; Older v1 backup readers require this field. Automatic restart is retired.
            IniWrite("0", temporary, section, "AutoReconnect")
        }
        FileMove(temporary, path, true)
        MsgBox("Launcher data exported. This file contains readable passwords; store it privately. Custom portrait images must be copied separately if needed.", "Export Data")
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
    global Profiles, SelectedProfile, DataFile, Client, MaxCharacters
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
        ; Legacy backups could contain no favorite. Every nonempty list
        ; now has one, including immediately after the import completes.
        if selected = 0
            selected := 1
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
                LoadDelay: ReadBackupInteger(path, section, "Load", 1, 300)})
        }
        executable := IniRead(path, "Launch", "Executable", "")
        SplitPath(executable, &filename)
        pathReset := !FileExist(executable) || StrLower(filename) != "tes3mp.exe"
        if pathReset
            executable := ""
        ; Old v1 backups omit this optional notice flag. Do not reset a notice
        ; already acknowledged on this computer when importing such a backup.
        favoriteNotice := IniRead(path, "Launcher", "HideFavoriteSwitchExplanation", "0")
        if favoriteNotice != "0" && favoriteNotice != "1"
            throw Error("Invalid favorite-switch notice setting")
        if IniRead(DataFile, "Launcher", "HideFavoriteSwitchExplanation", "0") = "1"
            favoriteNotice := "1"
        ; Validate everything and encrypt every password before replacing live settings.
        DirCreate(AppDataDirectory)
        if FileExist(temporary)
            FileDelete(temporary)
        IniWrite(count, temporary, "Profiles", "Count")
        IniWrite(selected, temporary, "Profiles", "Selected")
        IniWrite(executable, temporary, "Launch", "Executable")
        IniWrite(favoriteNotice, temporary, "Launcher", "HideFavoriteSwitchExplanation")
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
        UpdateCharacterMenuLabel()
        RefreshProfiles()
    }
    finally EndInterfaceUpdate()
    MsgBox("Launcher data imported." (pathReset ? " An old executable path was unavailable. Use Launcher Settings > Game Client Settings if you need a custom client." : ""), "Import Data")
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
