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
