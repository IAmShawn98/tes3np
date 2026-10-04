; TES3MP client detection.
; The stock hash is from an untouched TES3MP 0.8.1 Win64 tes3mp.exe.

CheckModifiedClientFirstRun()
{
    global DataFile

    tesFolder := FindTES3MPFolder()
    executable := tesFolder != "" ? tesFolder "\tes3mp.exe" : ""
    if executable = "" || !FileExist(executable)
        return

    stockHash := "b885c89ac370748a8d15ed6eed8583a953c1593f69e19916db8c904e6da1a550"
    markerlessHash := BundledMarkerlessHash()
    installedHash := SHA256File(executable)
    if installedHash = "" || installedHash = stockHash || (markerlessHash != "" && installedHash = markerlessHash)
        return

    message := "It looks like you're using a custom patch of TES3MP.`n`n"
        . "Would you like the patcher to overwrite your custom tes3mp.exe with the Markerless build, or would you like us to skip it instead?`n`n"
        . "Yes — overwrite the custom tes3mp.exe with Markerless.`n"
        . "No — keep the custom tes3mp.exe and skip Markerless."
    answer := MsgBox(message, "Custom TES3MP Patch Detected", "YesNo Icon?")
    choice := answer = "Yes" ? "overwrite" : "skip"
    DirCreate(AppDataDirectory)
    ; Store the answer for this launch so the patcher knows what to do. Startup no longer
    ; treats this value as a reason to suppress the prompt on future launches.
    IniWrite(choice, DataFile, "Patch", "CustomClientChoice")
    try IniDelete(DataFile, "Patch", "ModifiedClientPrompt")
    if answer = "Yes"
        OpenPatcher()
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
