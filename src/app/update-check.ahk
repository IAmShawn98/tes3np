; Safe update client. Installation remains an explicit user action.

global UpdateReleasePage := "https://github.com/IAmShawn98/tes3np-releases/releases/tag/latest-alpha"
global UpdateManifestUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-update.json"
global UpdatePackageUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-windows.zip"
global UpdateBusy := false

CheckForUpdates(*)
{
    global AppConfig, UpdateReleasePage, UpdateManifestUrl, UpdateBusy, LauncherGui
    if UpdateBusy {
        LogLauncherEvent("UPDATE | Check ignored because another update operation is active.")
        return
    }
    UpdateBusy := true
    LogLauncherEvent("UPDATE | Checking trusted update manifest. Current: v" AppConfig.Version ".")
    try {
        manifest := ParseAndValidateUpdateManifest(DownloadUpdateText(UpdateManifestUrl))
        latest := manifest.version
        LogLauncherEvent("UPDATE | Manifest validated. Current: v" AppConfig.Version " | Latest: v" latest ".")
        if !manifest.updateEnabled {
            LogLauncherEvent("UPDATE | Automatic installation disabled by release metadata.")
            MsgBox("Automatic updating is temporarily unavailable. You can still use tes3np normally or view the official release page.", "tes3np — Update check", "Iconi")
            return
        }
        if CompareTes3npVersions(latest, AppConfig.Version) <= 0 {
            LogLauncherEvent("UPDATE | SUCCESS | Launcher is up to date.")
            MsgBox("You're already running the latest public version of tes3np.`n`nInstalled: v" AppConfig.Version, "tes3np — Up to date", "Iconi")
            return
        }
        LogLauncherEvent("UPDATE | Update available: v" latest ".")
        choice := MsgBox("tes3np v" latest " is available.`n`nInstalled: v" AppConfig.Version "`n`nDownload and verify the update now?", "tes3np — Update available", "YesNo Iconi")
        if choice = "Yes" {
            BeginInterfaceUpdate(LauncherGui, "Downloading update...", true, 5)
            try {
                staged := DownloadAndStageUpdate(manifest)
                SetInterfaceLoadingText("Update ready to install...")
            } finally EndInterfaceUpdate()
            LogLauncherEvent("UPDATE | READY | Verified update staged for v" latest ".")
            if MsgBox("tes3np v" latest " was downloaded and verified successfully.`n`nInstall it now? The launcher will close and automatically roll back if the updated launcher cannot confirm a successful start.", "tes3np — Update verified", "YesNo Iconi") = "Yes" {
                StartTransactionalUpdate(manifest.version, staged)
                LogLauncherEvent("UPDATE | Transactional installer started for v" latest ".")
                ExitApp(0)
            }
            LogLauncherEvent("UPDATE | Installation deferred for verified update v" latest ".")
        } else {
            LogLauncherEvent("UPDATE | User deferred update v" latest ".")
            if MsgBox("Open the official release page instead?", "tes3np — Update available", "YesNo Iconi") = "Yes"
                Run(UpdateReleasePage)
        }
    } catch Error as err {
        LogLauncherEvent("ERROR | UPDATE | " SanitizeDiagnosticPath(err.Message))
        MsgBox("tes3np couldn't safely prepare or start the update.`n`nNo update was installed. The current launcher remains unchanged unless the transactional installer had already started; in that case it will automatically roll back if the new launcher cannot confirm a successful start.`n`n" err.Message, "tes3np — Update", "Icon!")
    } finally {
        UpdateBusy := false
    }
}

StartTransactionalUpdate(version, staged)
{
    worker := A_ScriptDir "\scripts\tes3np-updater.ps1"
    stateFile := A_Temp "\tes3np-update\update-state.ini"
    expectedStage := A_Temp "\tes3np-update\staged"
    if !FileExist(worker)
        throw Error("Updater worker is missing from this installation.")
    if !FileExist(stateFile)
        throw Error("Update state file is missing.")
    if StrLower(GetFullPath(staged)) != StrLower(GetFullPath(expectedStage))
        throw Error("Staged update path is invalid.")
    pid := DllCall("GetCurrentProcessId", "UInt")
    args := ' -NoProfile -NonInteractive -File "' worker '" -InstallDir "' A_ScriptDir '" -StageDir "' staged '" -StateFile "' stateFile '" -Version "' version '" -ParentPid ' pid
    Run('powershell.exe' args, A_ScriptDir, "Hide")
}

ConfirmInstalledUpdate(version, stateFile)
{
    expectedState := A_Temp "\tes3np-update\update-state.ini"
    if StrLower(GetFullPath(stateFile)) != StrLower(GetFullPath(expectedState))
        throw Error("Update confirmation state path is invalid.")
    if !RegExMatch(version, "^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")
        throw Error("Update confirmation version is invalid.")
    if !FileExist(stateFile)
        throw Error("Update confirmation state file is missing.")
    stagedVersion := IniRead(stateFile, "Update", "Version", "")
    if stagedVersion != version
        throw Error("Update confirmation version does not match staged update.")
    IniWrite("CONFIRMED", stateFile, "Update", "State")
}

GetFullPath(path)
{
    size := DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    if !size
        throw Error("Unable to resolve update confirmation path.")
    pathBuffer := Buffer(size * 2, 0)
    if !DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", size, "Ptr", pathBuffer, "Ptr", 0, "UInt")
        throw Error("Unable to resolve update confirmation path.")
    return StrGet(pathBuffer)
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

DownloadAndStageUpdate(manifest)
{
    global UpdatePackageUrl
    root := A_Temp "\tes3np-update"
    part := root "\tes3np-windows.zip.part"
    package := root "\tes3np-windows.zip"
    stage := root "\staged"
    try DirDelete(root, true)
    DirCreate(root)
    SetInterfaceLoadingText("Downloading update...")
    LogLauncherEvent("UPDATE | Download started | v" manifest.version ".")
    Download(UpdatePackageUrl, part)
    if !FileExist(part)
        throw Error("Downloaded update package is missing.")
    SetInterfaceLoadingText("Checking download size...")
    actualSize := FileGetSize(part)
    if actualSize != manifest.size
        throw Error("Downloaded update size does not match trusted metadata.")
    SetInterfaceLoadingText("Verifying update...")
    actualHash := GetFileSha256(part)
    if StrLower(actualHash) != StrLower(manifest.sha256)
        throw Error("Downloaded update failed SHA-256 verification.")
    FileMove(part, package, true)
    LogLauncherEvent("UPDATE | Download verified | SHA-256 and size match trusted metadata.")
    SetInterfaceLoadingText("Preparing update...")
    ValidateUpdateArchive(package, stage)
    SetInterfaceLoadingText("Saving update state...")
    state := root "\update-state.ini"
    IniWrite("STAGED", state, "Update", "State")
    IniWrite(manifest.version, state, "Update", "Version")
    IniWrite(manifest.sha256, state, "Update", "Sha256")
    return stage
}

GetFileSha256(path)
{
    shell := ComObject("WScript.Shell")
    tempOut := A_Temp "\tes3np-hash-" A_TickCount ".txt"
    cmd := A_ComSpec ' /D /C certutil -hashfile "' path '" SHA256 > "' tempOut '"'
    exitCode := shell.Run(cmd, 0, true)
    if exitCode != 0 || !FileExist(tempOut)
        throw Error("Unable to calculate update SHA-256.")
    text := FileRead(tempOut)
    try FileDelete(tempOut)
    if !RegExMatch(text, "i)([0-9a-f]{64})", &m)
        throw Error("Unable to read update SHA-256 result.")
    return StrLower(m[1])
}

ValidateUpdateArchive(package, stage)
{
    script := "$ErrorActionPreference='Stop';" .
        "$z=[IO.Compression.ZipFile]::OpenRead('" PsQuote(package) "');" .
        "$root=[IO.Path]::GetFullPath('" PsQuote(stage) "'+[IO.Path]::DirectorySeparatorChar);" .
        "foreach($e in $z.Entries){$p=[IO.Path]::GetFullPath([IO.Path]::Combine($root,$e.FullName));if(-not $p.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe archive path'}};" .
        "$z.Dispose();[IO.Compression.ZipFile]::ExtractToDirectory('" PsQuote(package) "','" PsQuote(stage) "');" .
        "$exe=Get-ChildItem -LiteralPath '" PsQuote(stage) "' -Filter tes3np.exe -Recurse | Select-Object -First 1;if(-not $exe){throw 'tes3np.exe missing from staged package'}"
    shell := ComObject("WScript.Shell")
    command := 'powershell.exe -NoProfile -NonInteractive -Command "' StrReplace(script, '"', '\"') '"'
    exitCode := shell.Run(command, 0, true)
    if exitCode != 0
        throw Error("Update package failed safe staging validation.")
    LogLauncherEvent("UPDATE | Package staged and structure validated.")
}

PsQuote(value) => StrReplace(value, "'", "''")

ParseAndValidateUpdateManifest(text)
{
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

RequireManifestString(text, name) {
    if !RegExMatch(text, '"' name '"\s*:\s*"([^"\\]*)"', &m)
        throw Error("Update manifest is missing or has invalid " name ".")
    return m[1]
}
RequireManifestInteger(text, name) {
    if !RegExMatch(text, '"' name '"\s*:\s*(\d+)', &m)
        throw Error("Update manifest is missing or has invalid " name ".")
    return Integer(m[1])
}
RequireManifestBoolean(text, name) {
    if !RegExMatch(text, 'i)"' name '"\s*:\s*(true|false)', &m)
        throw Error("Update manifest is missing or has invalid " name ".")
    return StrLower(m[1]) = "true"
}

CompareTes3npVersions(left, right)
{
    left := RegExReplace(left, "i)^v"), right := RegExReplace(right, "i)^v")
    leftBase := StrSplit(StrSplit(left, "-")[1], "."), rightBase := StrSplit(StrSplit(right, "-")[1], ".")
    Loop 3 {
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
