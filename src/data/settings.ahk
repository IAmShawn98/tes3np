; Profile persistence, shared executable settings and Windows password protection.

LoadProfiles()
{
    global Profiles, DataFile, SelectedProfile, MaxCharacters
    Profiles := []
    savedCount := IniRead(DataFile, "Profiles", "Count", "0")
    count := RegExMatch(savedCount, "^\d{1,6}$") ? Min(MaxCharacters, Integer(savedCount)) : 0
    Loop count
    {
        section := "Character" A_Index
        SetInterfaceLoadingText("Reading character " A_Index "...")
        name := IniRead(DataFile, section, "Name", "")
        encrypted := IniRead(DataFile, section, "Password", "")
        password := ""
        if encrypted != ""
        {
            try password := ProtectPassword(encrypted, false)
            catch
                password := ""
        }
        if name != ""
            Profiles.Push({Name: name, Password: password,
                UsernameDelay: ReadProfileDelay(section, "Username", AppConfig.UsernameDelay),
                PasswordDelay: ReadProfileDelay(section, "PasswordDelay", AppConfig.PasswordDelay, "Password"),
                LoadDelay: ReadProfileDelay(section, "Load", AppConfig.LoadDelay),
                AutoReconnect: IniRead(DataFile, section, "AutoReconnect", "1") = "1"})
    }
    saved := IniRead(DataFile, "Profiles", "Selected", "0")
    SelectedProfile := RegExMatch(saved, "^\d+$") && Integer(saved) <= Profiles.Length ? Integer(saved) : 0

}

ReadProfileDelay(section, key, fallback, legacyKey := "")
{
    global DataFile
    legacyKey := legacyKey = "" ? key : legacyKey
    value := IniRead(DataFile, section, key, "")
    if value = ""
        value := IniRead(DataFile, "Timing", legacyKey, fallback)
    return RegExMatch(value, "^\d+$") ? Max(1, Min(300, Integer(value))) : fallback
}

SaveProfiles()
{
    global Profiles, DataFile
    DirCreate(AppDataDirectory)
    GetSharedExecutable()
    IniWrite(Profiles.Length, DataFile, "Profiles", "Count")
    for index, profile in Profiles
    {
        section := "Character" index
        SetInterfaceLoadingText("Saving character name " index "...")
        IniWrite(profile.Name, DataFile, section, "Name")
        SetInterfaceLoadingText("Saving protected password " index "...")
        IniWrite(ProtectPassword(profile.Password), DataFile, section, "Password")
        ; Executable is shared; remove obsolete per-character copies.
        try IniDelete(DataFile, section, "Executable")
        SetInterfaceLoadingText("Saving login timings " index "...")
        IniWrite(profile.UsernameDelay, DataFile, section, "Username")
        IniWrite(profile.PasswordDelay, DataFile, section, "PasswordDelay")
        IniWrite(profile.LoadDelay, DataFile, section, "Load")
        IniWrite(profile.AutoReconnect ? "1" : "0", DataFile, section, "AutoReconnect")
    }
    index := Profiles.Length + 1
    while IniRead(DataFile, "Character" index, "Name", "") != ""
    {
        IniDelete(DataFile, "Character" index)
        index += 1
    }
    SaveDefaultProfile()
}

SaveDefaultProfile()
{
    global SelectedProfile, DataFile
    DirCreate(AppDataDirectory)
    IniWrite(SelectedProfile, DataFile, "Profiles", "Selected")
    UpdateCharacterMenuLabel()
}

GetSharedExecutable()
{
    ; Bundled markerless client is the only supported automatic launch target.
    return A_ScriptDir "\client\tes3mp.exe"
}

SaveSharedExecutable(*)
{
    global ExecutableInput, DataFile
    DirCreate(AppDataDirectory)
    IniWrite(Trim(ExecutableInput.Value), DataFile, "Launch", "Executable")
}

ProtectPassword(value, encrypt := true)
{
    ; Windows DPAPI ties saved secrets to the current Windows account.
    if encrypt
    {
        size := StrPut(value, "UTF-8")
        bytes := Buffer(size)
        StrPut(value, bytes, "UTF-8")
    }
    else
    {
        if !RegExMatch(value, "^(?:[0-9A-Fa-f]{2})+$")
            throw Error("Invalid encrypted password")
        size := StrLen(value) // 2
        bytes := Buffer(size)
        Loop size
            NumPut("UChar", Integer("0x" SubStr(value, A_Index * 2 - 1, 2)), bytes, A_Index - 1)
    }
    input := Buffer(A_PtrSize * 2, 0)
    output := Buffer(A_PtrSize * 2, 0)
    NumPut("UInt", size, input)
    NumPut("Ptr", bytes.Ptr, input, A_PtrSize)
    functionName := encrypt ? "CryptProtectData" : "CryptUnprotectData"
    if !DllCall("Crypt32\" functionName, "Ptr", input, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 1, "Ptr", output)
        throw Error("Password encryption failed")
    data := NumGet(output, A_PtrSize, "Ptr")
    try
    {
        if !encrypt
            return StrGet(data, "UTF-8")
        result := ""
        Loop NumGet(output, 0, "UInt")
            result .= Format("{:02X}", NumGet(data, A_Index - 1, "UChar"))
        return result
    }
    finally DllCall("LocalFree", "Ptr", data)
}

HasSavedCharacters()
{
    global DataFile, MaxCharacters
    count := IniRead(DataFile, "Profiles", "Count", "0")
    if !RegExMatch(count, "^\d{1,6}$")
        return false
    Loop Min(Integer(count), MaxCharacters)
    {
        if Trim(IniRead(DataFile, "Character" A_Index, "Name", "")) != ""
            return true
    }
    return false
}

NewCharacterProfile()
{
    return {Name: "", Password: "", UsernameDelay: AppConfig.UsernameDelay,
        PasswordDelay: AppConfig.PasswordDelay, LoadDelay: AppConfig.LoadDelay,
        AutoReconnect: true}
}
