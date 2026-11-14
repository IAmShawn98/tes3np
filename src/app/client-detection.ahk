; Managed TES3MP client selection, dependency verification and custom override cache.
; The retired markerless overwrite/skip prompt was never called by the current patcher.

SHA256File(path)
{
    ; Windows certutil avoids nested PowerShell quoting and requires no extra software.
    temporary := A_Temp "\tes3np-client-hash-" A_TickCount "-" DllCall("GetCurrentProcessId") ".txt"
    command := A_ComSpec ' /D /C certutil -hashfile "' path '" SHA256 > "' temporary '"'
    try
    {
        RunWait(command, , "Hide")
        if FileExist(temporary)
        {
            output := FileRead(temporary, "UTF-8")
            if RegExMatch(output, "i)\b([0-9a-f]{64})\b", &match)
                return StrLower(match[1])
        }
    }
    catch
    {
    }
    finally
    {
        try FileDelete(temporary)
    }
    return ""
}

; Use the locally installed TES3MP runtime with TES3NP's bundled client.
; The original vanilla executable is never overwritten.
PrepareMarkerlessClientRuntime()
{
    ; The release contains the complete TES3MP 0.8.1 client runtime.
    ; No lookup, downloads or writes to an external TES3MP installation.
    clientFolder := A_ScriptDir "\client"
    required := ["tes3mp.exe", "tes3mp-client-default.cfg", "defaults.bin", "openmw.cfg"]
    for name in required
    {
        path := clientFolder "\" name
        if !FileExist(path)
        {
            LogLauncherEvent("Bundled TES3MP runtime file missing.")
            MsgBox("This TES3NP installation is incomplete. Missing:" Chr(10) path Chr(10) Chr(10)
                . "Extract the complete TES3NP release ZIP and run the tes3np.exe inside it.",
                "Missing bundled TES3MP runtime", "Icon!")
            return false
        }
    }
    return true
}

; Stage a bare custom executable alongside a COPY of bundled dependencies.
; Never overwrite TES3NP's bundled client or the user's original binary.
GetManagedCustomClientExecutable(source)
{
    global AppDataDirectory
    SplitPath(source, &filename)
    if StrLower(filename) != "tes3mp.exe" || !FileExist(source)
        return source
    bundled := A_ScriptDir "\client"
    if !FileExist(bundled "\defaults.bin")
        return source
    ; Custom replacements can have the same length and timestamp.
    sourceHash := SHA256File(source)
    if sourceHash = ""
    {
        LogLauncherEvent("GAME | Custom executable checksum unavailable.")
        MsgBox("Could not read the selected TES3MP executable. Check its location and permissions.", "Custom client error", "Icon!")
        return ""
    }
    token := source "|" sourceHash
        . "|" FileGetSize(bundled "\defaults.bin") "|" FileGetTime(bundled "\defaults.bin", "M")
        . "|" FileGetSize(bundled "\tes3mp.exe") "|" FileGetTime(bundled "\tes3mp.exe", "M")
    key := 2166136261
    Loop Parse token
        key := Mod((key ^ Ord(A_LoopField)) * 16777619, 4294967296)
    folder := AppDataDirectory "\client-cache\" Format("{:08X}", key)
    output := folder "\tes3mp.exe"
    if FileExist(folder "\.ready") && FileExist(output)
    {
        try FileSetTime(, folder "\.ready")
        return output
    }
    ; A new cache folder is assembled completely before its ready marker is
    ; written. Interrupted preparation will be retried on the next launch.
    try
    {
        if DirExist(folder)
            DirDelete(folder, true)
        DirCreate(AppDataDirectory "\client-cache")
        DirCopy(bundled, folder, true)
        FileCopy(source, output, true)
        if SHA256File(output) != sourceHash
            throw Error("The custom executable changed during staging. Try again.")
        FileAppend(source "`n", folder "\.ready", "UTF-8")
        LogLauncherEvent("GAME | Custom executable prepared with bundled runtime.")
        return output
    }
    catch Error as err
    {
        LogLauncherEvent("GAME | Custom executable staging failed (" Type(err) ").")
        MsgBox("Could not prepare custom TES3MP executable:`n" err.Message
            . "`n`nYour original file and bundled client were not changed.", "Custom client error", "Icon!")
        return ""
    }
}

; Validate the selected runtime rather than assuming the bundled client.
ValidateSelectedClientRuntime(executable)
{
    if !FileExist(executable)
    {
        MsgBox("Selected TES3MP executable was not found:`n" executable, "Missing TES3MP", "Icon!")
        return false
    }
    SplitPath(executable, , &folder)
    for name in ["tes3mp-client-default.cfg", "defaults.bin", "openmw.cfg"]
    {
        if !FileExist(folder "\" name)
        {
            MsgBox("Selected TES3MP runtime is incomplete.`nMissing: " folder "\" name
                . "`n`nSelect a complete TES3MP installation through Launcher Settings.", "TES3MP files missing", "Icon!")
            return false
        }
    }
    return true
}

; Restore an existing custom client if Windows closed during an override swap.
RecoverCustomClientOverrides()
{
    global AppDataDirectory
    managed := AppDataDirectory "\custom-client"
    active := managed "\overrides"
    previous := managed "\previous"
    if DirExist(active) || !DirExist(previous)
        return
    try
    {
        DirMove(previous, active)
        LogLauncherEvent("GAME | Recovered saved overrides from interrupted custom-client installation.")
    }
    catch Error as err
        LogLauncherEvent("GAME | Interrupted custom-client recovery failed (" Type(err) ").")
}

GetCustomOverrideFolder()
{
    global AppDataDirectory
    return AppDataDirectory "\custom-client\overrides"
}

GetMergedCustomClientExecutable()
{
    global AppDataDirectory
    bundled := A_ScriptDir "\client"
    RecoverCustomClientOverrides()
    overrides := GetCustomOverrideFolder()
    if !DirExist(overrides) || !FileExist(overrides "\tes3mp.exe")
        return ""
    signature := ""
    for root in [bundled, overrides]
    {
        signature .= root "|"
        ; Use file content checksums rather than timestamps: archives and
        ; copied mods can retain their original sizes and modified times.
        files := []
        Loop Files root "\*", "FR"
            files.Push(A_LoopFileFullPath)
        for file in files
        {
            relative := StrLower(SubStr(file, StrLen(root) + 2))
            ; Bundled files are shipped as a build artifact. Avoid launching
            ; certutil for every bundled asset on each GetSharedExecutable call.
            if root = bundled
                signature .= relative "|" FileGetSize(file) "|" FileGetTime(file, "M") ";"
            else
            {
                checksum := SHA256File(file)
                if checksum = ""
                {
                    LogLauncherEvent("GAME | SHA256 unavailable for custom override; using file metadata to preserve launch ability.")
                    checksum := FileGetSize(file) "|" FileGetTime(file, "M")
                }
                signature .= relative "|" checksum ";"
            }
        }
    }
    key := 2166136261
    Loop Parse signature
        key := Mod((key ^ Ord(A_LoopField)) * 16777619, 4294967296)
    folder := AppDataDirectory "\client-cache\merged-" Format("{:08X}", key)
    output := folder "\tes3mp.exe"
    if FileExist(folder "\.ready") && FileExist(output)
    {
        try FileSetTime(, folder "\.ready")
        return output
    }
    try
    {
        DirCreate(AppDataDirectory "\client-cache")
        if DirExist(folder)
            DirDelete(folder, true)
        DirCopy(bundled, folder, true)
        Loop Files overrides "\*", "FR"
        {
            relative := SubStr(A_LoopFileFullPath, StrLen(overrides) + 2)
            target := folder "\" relative
            SplitPath(target, , &parent)
            DirCreate(parent)
            FileCopy(A_LoopFileFullPath, target, true)
        }
        if !ValidateSelectedClientRuntime(output)
            throw Error("Incomplete merged runtime.")
        FileAppend(signature, folder "\.ready", "UTF-8")
        LogLauncherEvent("GAME | Merged custom override runtime prepared.")
        return output
    }
    catch Error as err
    {
        LogLauncherEvent("GAME | Merged runtime failed (" Type(err) ").")
        MsgBox("Could not prepare custom client: " err.Message, "Game Client", "Icon!")
        return ""
    }
}

InstallCustomClientOverrides(source, dependencies := "")
{
    global AppDataDirectory
    SplitPath(source, &filename)
    if StrLower(filename) != "tes3mp.exe" || !FileExist(source)
        return false
    managed := AppDataDirectory "\custom-client"
    incoming := managed "\incoming"
    overrides := managed "\overrides"
    backup := managed "\previous"
    try
    {
        if dependencies != "" && (!DirExist(dependencies) || InStr(StrLower(dependencies), StrLower(managed)))
            throw Error("Invalid dependencies folder.")
        DirCreate(managed)
        if DirExist(incoming)
            DirDelete(incoming, true)
        DirCreate(incoming)
        if dependencies != ""
        {
            ; Both resources\mygui and mygui folder selections must yield
            ; resources\mygui\*.layout in the assembled client runtime.
            dependencies := RTrim(dependencies, "\/")
            SplitPath(dependencies, &selectedName)
            prefix := StrLower(selectedName) = "mygui" ? "resources\mygui\" :
                StrLower(selectedName) = "resources" ? "resources\" : ""
            copied := 0
            Loop Files dependencies "\*", "FR"
            {
                relative := prefix SubStr(A_LoopFileFullPath, StrLen(dependencies) + 2)
                destination := incoming "\" relative
                SplitPath(destination, , &destinationFolder)
                DirCreate(destinationFolder)
                FileCopy(A_LoopFileFullPath, destination, true)
                copied += 1
                LogLauncherEvent("GAME | Custom dependency staged.")
            }
            if copied = 0
                throw Error("Selected dependencies folder contains no files.")
            LogLauncherEvent("GAME | Dependencies selected | Files: " copied " | Prefix: " prefix ".")
        }
        ; Explicitly selected EXE always wins even when the dependencies
        ; folder also happens to contain its own tes3mp.exe.
        FileCopy(source, incoming "\tes3mp.exe", true)
        if DirExist(backup)
            DirDelete(backup, true)
        if DirExist(overrides)
            DirMove(overrides, backup)
        try DirMove(incoming, overrides)
        catch Error as err
        {
            if DirExist(backup) && !DirExist(overrides)
                DirMove(backup, overrides)
            throw err
        }
        LogLauncherEvent("GAME | Custom executable and dependencies stored as overrides.")
        return true
    }
    catch Error as err
    {
        LogLauncherEvent("GAME | Custom override installation failed (" Type(err) ").")
        MsgBox("Unable to save custom files: " err.Message, "Game Client", "Icon!")
        return false
    }
}
