; First-run TES3MP client detection.
; The stock hash is from an untouched TES3MP 0.8.1 Win64 tes3mp.exe.

CheckModifiedClientFirstRun()
{
    global DataFile
    if IniRead(DataFile, "Patch", "ModifiedClientPrompt", "") != ""
        return

    tesFolder := FindTES3MPFolder()
    executable := tesFolder != "" ? tesFolder "\tes3mp.exe" : ""
    if executable = "" || !FileExist(executable)
        return

    stockHash := "b885c89ac370748a8d15ed6eed8583a953c1593f69e19916db8c904e6da1a550"
    markerlessHash := BundledMarkerlessHash()
    installedHash := SHA256File(executable)
    if installedHash = "" || installedHash = stockHash || (markerlessHash != "" && installedHash = markerlessHash)
        return

    answer := MsgBox("You are using a modified TES3MP client already.`n`nDo you wish to patch it with the Markerless build?", "Modified TES3MP Client Detected", "YesNo Icon?")
    DirCreate(AppDataDirectory)
    IniWrite(answer = "Yes" ? "yes" : "no", DataFile, "Patch", "ModifiedClientPrompt")
    if answer = "Yes"
        OpenPatcher()
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
    ; Use Windows PowerShell's built-in SHA-256 implementation. No extra software is required.
    temporary := A_Temp "\tes3np-client-hash-" A_TickCount "-" DllCall("GetCurrentProcessId") ".txt"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(powershell)
        return ""
    command := '"' powershell '" -NoProfile -NonInteractive -Command "(Get-FileHash -LiteralPath ''"'
        . StrReplace(path, "'", "''") . "'' -Algorithm SHA256).Hash.ToLowerInvariant() | Set-Content -LiteralPath '"'
        . StrReplace(temporary, "'", "''") . "'' -NoNewline -Encoding ASCII""
    try
    {
        RunWait(command, , "Hide")
        if FileExist(temporary)
            return StrLower(Trim(FileRead(temporary, "UTF-8")))
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
