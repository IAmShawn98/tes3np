; TES3MP client detection. This is only run from explicit patch/verify actions.
; The stock hash is from an untouched TES3MP 0.8.1 Win64 tes3mp.exe.

CheckModifiedClientForPatch(tesFolder, action := "Apply")
{
    global DataFile
    executable := tesFolder != "" ? tesFolder "\tes3mp.exe" : ""
    if executable = "" || !FileExist(executable)
        return true

    stockHash := "b885c89ac370748a8d15ed6eed8583a953c1593f69e19916db8c904e6da1a550"
    markerlessHash := BundledMarkerlessHash()
    installedHash := SHA256File(executable)
    if installedHash = "" || installedHash = stockHash || (markerlessHash != "" && installedHash = markerlessHash)
    {
        ; A normal client should not inherit an earlier custom-client skip choice.
        try IniDelete(DataFile, "Patch", "CustomClientChoice")
        return true
    }

    if action = "Verify"
    {
        message := "It looks like you're using a modified version of TES3MP that isn't part of the official tes3np patches.`n`n"
            . "If you choose Install / Repair, you'll be asked whether to replace this executable with the Markerless build or keep your existing custom version."
        MsgBox(message, "Custom TES3MP Client Detected", "Iconi")
        return true
    }

    message := "It looks like you're using a custom patch of TES3MP.`n`n"
        . "Would you like the patcher to overwrite your custom tes3mp.exe with the Markerless build, or would you like us to skip it instead?`n`n"
        . "Yes — overwrite the custom tes3mp.exe with Markerless.`n"
        . "No — keep the custom tes3mp.exe and skip Markerless."
    answer := MsgBox(message, "Custom TES3MP Patch Detected", "YesNo Icon?")
    choice := answer = "Yes" ? "overwrite" : "skip"
    DirCreate(AppDataDirectory)
    ; This value controls only the patch/verify operation being started. Detection runs again
    ; the next time the user explicitly starts Install / Repair or Verify.
    IniWrite(choice, DataFile, "Patch", "CustomClientChoice")
    try IniDelete(DataFile, "Patch", "ModifiedClientPrompt")
    return true
}

ShouldSkipMarkerless()
{
    global DataFile
    return IniRead(DataFile, "Patch", "CustomClientChoice", "") = "skip"
}

BundledMarkerlessHash()
{
    manifest := A_ScriptDir "\patches\manifest.json"
    if !FileExist(manifest)
        return ""
    text := FileRead(manifest, "UTF-8")
    if RegExMatch(text, 'is)"Path"\s*:\s*"markerless/tes3mp\.exe"\s*,\s*"SHA256"\s*:\s*"([0-9a-fA-F]{64})"', &match)
        return StrLower(match[1])
    return ""
}

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
            LogLauncherEvent("Bundled TES3MP runtime missing: " path)
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
    ; Stable cache key includes the source path, file size and modified time,
    ; and bundled runtime version. Changed binaries get a fresh directory.
    token := source "|" FileGetSize(source) "|" FileGetTime(source, "M")
        . "|" FileGetSize(bundled "\defaults.bin") "|" FileGetTime(bundled "\defaults.bin", "M")
        . "|" FileGetSize(bundled "\tes3mp.exe") "|" FileGetTime(bundled "\tes3mp.exe", "M")
    key := 2166136261
    Loop Parse token
        key := Mod((key ^ Ord(A_LoopField)) * 16777619, 4294967296)
    folder := AppDataDirectory "\client-cache\" Format("{:08X}", key)
    output := folder "\tes3mp.exe"
    if FileExist(folder "\.ready") && FileExist(output)
        return output
    ; A new cache folder is assembled completely before its ready marker is
    ; written. Interrupted preparation will be retried on the next launch.
    try
    {
        if DirExist(folder)
            DirDelete(folder, true)
        DirCreate(AppDataDirectory "\client-cache")
        DirCopy(bundled, folder, true)
        FileCopy(source, output, true)
        FileAppend(source "`n", folder "\.ready", "UTF-8")
        LogLauncherEvent("GAME | Custom executable prepared with bundled runtime.")
        return output
    }
    catch Error as err
    {
        LogLauncherEvent("GAME | Custom executable staging failed: " err.Message)
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

GetCustomOverrideFolder()
{
    global AppDataDirectory
    return AppDataDirectory "\custom-client\overrides"
}

GetMergedCustomClientExecutable()
{
    global AppDataDirectory
    bundled := A_ScriptDir "\client"
    overrides := GetCustomOverrideFolder()
    if !DirExist(overrides) || !FileExist(overrides "\tes3mp.exe")
        return ""
    signature := ""
    for root in [bundled, overrides]
    {
        signature .= root "|"
        Loop Files root "\*", "FR"
            signature .= StrLower(SubStr(A_LoopFileFullPath, StrLen(root) + 2)) "|" A_LoopFileSize "|" A_LoopFileTimeModified ";"
    }
    key := 2166136261
    Loop Parse signature
        key := Mod((key ^ Ord(A_LoopField)) * 16777619, 4294967296)
    folder := AppDataDirectory "\client-cache\merged-" Format("{:08X}", key)
    output := folder "\tes3mp.exe"
    if FileExist(folder "\.ready") && FileExist(output)
        return output
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
        LogLauncherEvent("GAME | Merged runtime failed: " err.Message)
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
                LogLauncherEvent("GAME | Custom dependency staged | " relative)
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
        LogLauncherEvent("GAME | Custom override installation failed: " err.Message)
        MsgBox("Unable to save custom files: " err.Message, "Game Client", "Icon!")
        return false
    }
}
