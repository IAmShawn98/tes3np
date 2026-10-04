; Checks the public tes3np release feed. Installation remains an explicit user action.

global UpdateReleaseApi := "https://api.github.com/repos/IAmShawn98/tes3np-releases/releases/tags/latest-alpha"
global UpdateReleasePage := "https://github.com/IAmShawn98/tes3np-releases/releases/tag/latest-alpha"

CheckForUpdates(*)
{
    global AppConfig, UpdateReleaseApi, UpdateReleasePage
    LogLauncherEvent("UPDATE | Checking GitHub for latest public release. Current: v" AppConfig.Version ".")
    try
    {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(5000, 5000, 10000, 10000)
        request.Open("GET", UpdateReleaseApi, false)
        request.SetRequestHeader("User-Agent", "tes3np/" AppConfig.Version)
        request.Send()
        if request.Status != 200
            throw Error("GitHub returned HTTP " request.Status ".")
        body := request.ResponseText
        if !RegExMatch(body, '"name"\s*:\s*"tes3np v([^" ]+)', &match)
            throw Error("The public release did not contain a recognizable tes3np version.")
        latest := match[1]
        LogLauncherEvent("UPDATE | Release check completed. Current: v" AppConfig.Version " | Latest: v" latest ".")
        if CompareTes3npVersions(latest, AppConfig.Version) <= 0
        {
            LogLauncherEvent("UPDATE | SUCCESS | Launcher is up to date.")
            MsgBox("You're already running the latest public version of tes3np.`n`nInstalled: v" AppConfig.Version, "tes3np — Up to date", "Iconi")
            return
        }
        LogLauncherEvent("UPDATE | Update available: v" latest ".")
        message := "tes3np v" latest " is available.`n`nYou are currently running v" AppConfig.Version ".`n`nOpen the official public release page to download the update?"
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
        MsgBox("tes3np couldn't check GitHub for updates right now.`n`n" err.Message, "tes3np — Update check", "Icon!")
    }
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
