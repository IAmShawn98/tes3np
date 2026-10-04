; Checks the public tes3np release feed. Installation remains an explicit user action.

global UpdateReleaseApi := "https://api.github.com/repos/IAmShawn98/tes3np-releases/releases/tags/latest-alpha"
global UpdateReleasePage := "https://github.com/IAmShawn98/tes3np-releases/releases/tag/latest-alpha"
global UpdateManifestUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-update.json"

CheckForUpdates(*)
{
    global AppConfig, UpdateReleasePage, UpdateManifestUrl
    LogLauncherEvent("UPDATE | Checking trusted update manifest. Current: v" AppConfig.Version ".")
    try
    {
        manifestText := DownloadUpdateText(UpdateManifestUrl)
        manifest := ParseAndValidateUpdateManifest(manifestText)
        latest := manifest.version
        LogLauncherEvent("UPDATE | Manifest validated. Current: v" AppConfig.Version " | Latest: v" latest ".")
        if !manifest.updateEnabled
        {
            LogLauncherEvent("UPDATE | Automatic installation disabled by release metadata.")
            MsgBox("Automatic updating is temporarily unavailable. You can still use tes3np normally or view the official release page.", "tes3np — Update check", "Iconi")
            return
        }
        if CompareTes3npVersions(latest, AppConfig.Version) <= 0
        {
            LogLauncherEvent("UPDATE | SUCCESS | Launcher is up to date.")
            MsgBox("You're already running the latest public version of tes3np.`n`nInstalled: v" AppConfig.Version, "tes3np — Up to date", "Iconi")
            return
        }
        LogLauncherEvent("UPDATE | Update available: v" latest ".")
        message := "tes3np v" latest " is available.`n`nYou are currently running v" AppConfig.Version ".`n`nOpen the official public release page?"
        if MsgBox(message, "tes3np — Update available", "YesNo Iconi") = "Yes"
        {
            LogLauncherEvent("UPDATE | User opened official public release page for v" latest ".")
            Run(UpdateReleasePage)
        }
        else
            LogLauncherEvent("UPDATE | User declined to open the public release page.")
    }
    catch Error as err
    {
        LogLauncherEvent("ERROR | UPDATE | " SanitizeDiagnosticPath(err.Message))
        MsgBox("tes3np couldn't safely validate the update feed right now.`n`nNo update was installed.`n`n" err.Message, "tes3np — Update check", "Icon!")
    }
}

DownloadUpdateText(url)
{
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetTimeouts(5000, 5000, 10000, 10000)
    request.Open("GET", url, false)
    request.SetRequestHeader("User-Agent", "tes3np updater")
    request.Send()
    if request.Status != 200
        throw Error("Update metadata returned HTTP " request.Status ".")
    return request.ResponseText
}

ParseAndValidateUpdateManifest(text)
{
    ; AHK v2 has no built-in JSON parser. This parser intentionally accepts only the
    ; small, generated manifest schema we own and rejects missing/ambiguous fields.
    manifest := {}
    manifest.manifestVersion := RequireManifestInteger(text, "manifestVersion")
    manifest.product := RequireManifestString(text, "product")
    manifest.channel := RequireManifestString(text, "channel")
    manifest.version := RequireManifestString(text, "version")
    manifest.releaseId := RequireManifestString(text, "releaseId")
    manifest.platform := RequireManifestString(text, "platform")
    manifest.architecture := RequireManifestString(text, "architecture")
    manifest.fileName := RequireManifestString(text, "fileName")
    manifest.size := RequireManifestInteger(text, "size")
    manifest.sha256 := RequireManifestString(text, "sha256")
    manifest.updateEnabled := RequireManifestBoolean(text, "updateEnabled")

    if manifest.manifestVersion != 1
        throw Error("Unsupported update manifest version.")
    if manifest.product != "tes3np" || manifest.channel != "alpha"
        throw Error("Update manifest identity/channel mismatch.")
    if manifest.platform != "windows" || manifest.architecture != "x64"
        throw Error("Update package is not for this platform.")
    if !RegExMatch(manifest.version, "^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")
        throw Error("Update manifest contains an invalid version.")
    if manifest.releaseId != "v" manifest.version
        throw Error("Update manifest release identity mismatch.")
    if manifest.fileName != "tes3np-windows.zip"
        throw Error("Update manifest contains an unexpected package name.")
    if manifest.size <= 0
        throw Error("Update manifest contains an invalid package size.")
    if !RegExMatch(manifest.sha256, "i)^[0-9a-f]{64}$")
        throw Error("Update manifest contains an invalid SHA-256 value.")
    return manifest
}

RequireManifestString(text, name)
{
    pattern := '"' name '"\s*:\s*"([^"\\]*)"'
    if !RegExMatch(text, pattern, &match)
        throw Error("Update manifest is missing or has invalid " name ".")
    return match[1]
}

RequireManifestInteger(text, name)
{
    pattern := '"' name '"\s*:\s*(\d+)'
    if !RegExMatch(text, pattern, &match)
        throw Error("Update manifest is missing or has invalid " name ".")
    return Integer(match[1])
}

RequireManifestBoolean(text, name)
{
    pattern := 'i)"' name '"\s*:\s*(true|false)'
    if !RegExMatch(text, pattern, &match)
        throw Error("Update manifest is missing or has invalid " name ".")
    return StrLower(match[1]) = "true"
}

CompareTes3npVersions(left, right)
{
    left := RegExReplace(left, "i)^v")
    right := RegExReplace(right, "i)^v")
    leftBase := StrSplit(StrSplit(left, "-")[1], ".")
    rightBase := StrSplit(StrSplit(right, "-")[1], ".")
    Loop 3
    {
        a := A_Index <= leftBase.Length ? Integer(leftBase[A_Index]) : 0
        b := A_Index <= rightBase.Length ? Integer(rightBase[A_Index]) : 0
        if a != b
            return a > b ? 1 : -1
    }
    leftPre := InStr(left, "-") ? SubStr(left, InStr(left, "-") + 1) : ""
    rightPre := InStr(right, "-") ? SubStr(right, InStr(right, "-") + 1) : ""
    if leftPre = rightPre
        return 0
    if leftPre = ""
        return 1
    if rightPre = ""
        return -1
    return StrCompare(leftPre, rightPre, false)
}
