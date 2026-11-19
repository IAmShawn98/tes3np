; Profile persistence, shared executable settings and Windows password protection.

; Morrowind playable races in alphabetical order. Empty means an existing
; character has not chosen its race and keeps the original icon.
CharacterSpeciesOptions()
{
    return ["Argonian", "Breton", "Dark Elf", "High Elf", "Imperial",
        "Khajiit", "Nord", "Orc", "Redguard", "Wood Elf"]
}

NormalizeCharacterSpecies(value)
{
    value := Trim(value)
    for species in CharacterSpeciesOptions()
        if StrLower(species) = StrLower(value)
            return species
    return ""
}

; Custom portraits are private per-character images outside the install tree.
; Persist only a generated basename (never an arbitrary user-selected path).
NormalizeCustomPortraitFile(value)
{
    value := Trim(value)
    return RegExMatch(value, "i)^[0-9a-f]{32}\.(png|jpg|jpeg|bmp)$") ? StrLower(value) : ""
}

GetCustomPortraitPath(filename)
{
    filename := NormalizeCustomPortraitFile(filename)
    return filename = "" ? "" : AppDataDirectory "\portraits\" filename
}

LoadProfiles()
{
    global Profiles, DataFile, SelectedProfile, MaxCharacters
    Profiles := []
    savedCount := IniRead(DataFile, "Profiles", "Count", "0")
    count := RegExMatch(savedCount, "^\d{1,6}$") ? Min(MaxCharacters, Integer(savedCount)) : 0
    saved := IniRead(DataFile, "Profiles", "Selected", "0")
    savedSlot := RegExMatch(saved, "^\d{1,6}$") ? Integer(saved) : 0
    SelectedProfile := 0
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
        {
            Profiles.Push({Name: name, Password: password,
                Species: NormalizeCharacterSpecies(IniRead(DataFile, section, "Species", "")),
                PortraitFile: NormalizeCustomPortraitFile(IniRead(DataFile, section, "PortraitFile", "")),
                UsernameDelay: ReadProfileDelay(section, "Username", AppConfig.UsernameDelay),
                PasswordDelay: ReadProfileDelay(section, "PasswordDelay", AppConfig.PasswordDelay, "Password"),
                LoadDelay: ReadProfileDelay(section, "Load", AppConfig.LoadDelay),
                AutoReconnect: IniRead(DataFile, section, "AutoReconnect", "0") = "1"})
            if A_Index = savedSlot
                SelectedProfile := Profiles.Length
        }
    }
    ; Migrate older lists without a favorite to their first character.
    ; Write only the selection here: the launcher menu may not exist yet
    ; during startup, so SaveDefaultProfile() must not run at this point.
    if Profiles.Length && !SelectedProfile
    {
        SelectedProfile := 1
        if count = Profiles.Length
            try IniWrite(SelectedProfile, DataFile, "Profiles", "Selected")
    }
}

ReadProfileDelay(section, key, fallback, legacyKey := "")
{
    global DataFile
    legacyKey := legacyKey = "" ? key : legacyKey
    value := IniRead(DataFile, section, key, "")
    if value = ""
        value := IniRead(DataFile, "Timing", legacyKey, fallback)
    if !RegExMatch(value, "^\d+$")
        return fallback
    digits := LTrim(value, "0")
    return StrLen(digits) > 3 ? 300 : Max(1, Min(300, Integer("0" digits)))
}

SaveProfiles()
{
    global Profiles, SelectedProfile, DataFile, MaxCharacters
    DirCreate(AppDataDirectory)
    temporary := DataFile ".save.tmp"
    try
    {
        if FileExist(temporary)
            FileDelete(temporary)
        if FileExist(DataFile)
            FileCopy(DataFile, temporary)
        IniWrite(Profiles.Length, temporary, "Profiles", "Count")
        IniWrite(SelectedProfile, temporary, "Profiles", "Selected")
        for index, profile in Profiles
        {
            section := "Character" index
            SetInterfaceLoadingText("Saving character name " index "...")
            IniWrite(profile.Name, temporary, section, "Name")
            IniWrite(NormalizeCharacterSpecies(profile.Species), temporary, section, "Species")
            IniWrite(NormalizeCustomPortraitFile(profile.PortraitFile), temporary, section, "PortraitFile")
            SetInterfaceLoadingText("Saving protected password " index "...")
            IniWrite(ProtectPassword(profile.Password), temporary, section, "Password")
            IniWrite(profile.AutoReconnect ? "1" : "0", temporary, section, "AutoReconnect")
            for key in ["Executable", "UseExpansionPack"]
                try IniDelete(temporary, section, key)
            SetInterfaceLoadingText("Saving login timings " index "...")
            IniWrite(profile.UsernameDelay, temporary, section, "Username")
            IniWrite(profile.PasswordDelay, temporary, section, "PasswordDelay")
            IniWrite(profile.LoadDelay, temporary, section, "Load")
        }
        Loop MaxCharacters - Profiles.Length
            try IniDelete(temporary, "Character" (Profiles.Length + A_Index))
        FileMove(temporary, DataFile, true)
    }
    finally
    {
        if FileExist(temporary)
            try FileDelete(temporary)
    }
}

SaveDefaultProfile(index)
{
    global SelectedProfile, DataFile
    DirCreate(AppDataDirectory)
    IniWrite(index, DataFile, "Profiles", "Selected")
    SelectedProfile := index
    UpdateCharacterMenuLabel()
}

GetSharedExecutable()
{
    global DataFile
    mode := IniRead(DataFile, "Launch", "ClientMode", "Bundled")
    if mode = "CustomOverrides"
        return GetMergedCustomClientExecutable()
    if mode = "CustomExe"
    {
        source := Trim(IniRead(DataFile, "Launch", "CustomExecutable", ""))
        return source = "" ? "" : GetManagedCustomClientExecutable(source)
    }
    if mode = "CustomRuntime" || mode = "Custom"
        return Trim(IniRead(DataFile, "Launch", "CustomExecutable", ""))
    return A_ScriptDir "\client\tes3mp.exe"
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

NewCharacterProfile()
{
    return {Name: "", Password: "", Species: "", PortraitFile: "", UsernameDelay: AppConfig.UsernameDelay,
        PasswordDelay: AppConfig.PasswordDelay, LoadDelay: AppConfig.LoadDelay, AutoReconnect: false}
}

NewLauncherFileId()
{
    uuid := Buffer(16, 0)
    if DllCall("ole32\CoCreateGuid", "Ptr", uuid, "Int") != 0
        throw Error("Could not allocate a unique file identifier.")
    id := ""
    Loop 16
        id .= Format("{:02x}", NumGet(uuid, A_Index - 1, "UChar"))
    return id
}
