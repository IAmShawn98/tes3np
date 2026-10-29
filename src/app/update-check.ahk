; Safe update client. Installation remains an explicit user action.

global UpdateReleasePage := "https://github.com/IAmShawn98/tes3np-releases/releases/tag/latest-alpha"
global UpdateManifestUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-update.json"
global UpdatePackageUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-windows.zip"
global UpdateBusy := false

CheckForUpdateAvailability(*)
{
    global AppConfig, UpdateManifestUrl, DataFile
    ; Startup availability checks are intentionally silent. A network or metadata
    ; failure must never interrupt normal launcher use; the button simply stays hidden.
    try {
        manifest := ParseAndValidateUpdateManifest(DownloadUpdateText(UpdateManifestUrl))
        available := manifest.updateEnabled && CompareTes3npVersions(manifest.version, AppConfig.Version) > 0
        SetLauncherUpdateAvailable(available && IniRead(DataFile, "Updates", "NotifyAlpha", "1") = "1", manifest.version)
        LogLauncherEvent("UPDATE | Startup availability check | Current: v" AppConfig.Version " | Latest: v" manifest.version " | Available: " (available ? "yes" : "no") ".")
    } catch Error as err {
        SetLauncherUpdateAvailable(false)
        LogLauncherEvent("UPDATE | Startup availability check unavailable | " SanitizeDiagnosticPath(err.Message))
    }
}

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
            SetLauncherUpdateAvailable(false)
            LogLauncherEvent("UPDATE | Automatic installation disabled by release metadata.")
            ShowUpdateStatusPanel("disabled", AppConfig.Version, latest, manifest.channel)
            return
        }
        if CompareTes3npVersions(latest, AppConfig.Version) <= 0 {
            SetLauncherUpdateAvailable(false)
            LogLauncherEvent("UPDATE | SUCCESS | Launcher is up to date.")
            ShowUpdateStatusPanel(CompareTes3npVersions(latest, AppConfig.Version) = 0 ? "current" : "ahead", AppConfig.Version, latest, manifest.channel)
            return
        }
        SetLauncherUpdateAvailable(true, latest)
        LogLauncherEvent("UPDATE | Update available: v" latest ".")
        ; Viewing the gold preview never downloads, stages, or installs files.
        choice := ShowUpdatePreview(AppConfig.Version, latest, manifest.channel)
        if choice = "Yes" && ShowGoldUpdateConfirmation("Download Update?", "Download and verify v" latest "?`nThe installed launcher will not be changed.", "Download") {
            BeginInterfaceUpdate(LauncherGui, "Downloading update...", true, 5)
            try {
                staged := DownloadAndStageUpdate(manifest)
                SetInterfaceLoadingText("Update ready to install...")
            } finally EndInterfaceUpdate()
            LogLauncherEvent("UPDATE | READY | Verified update staged for v" latest ".")
            if ShowGoldUpdateConfirmation("Install Verified Update?", "v" latest " is verified and ready.`nInstalling will restart tes3np. Rollback is available if startup fails.", "Install Update") {
                StartTransactionalUpdate(manifest.version, staged)
                LogLauncherEvent("UPDATE | Transactional installer started for v" latest ".")
                ExitApp(0)
            }
            LogLauncherEvent("UPDATE | Installation deferred for verified update v" latest ".")
        } else {
            DismissLauncherUpdate(latest)
            LogLauncherEvent("UPDATE | User deferred update v" latest "; clickable version label restored.")
        }
    } catch Error as err {
        LogLauncherEvent("ERROR | UPDATE | " SanitizeDiagnosticPath(err.Message))
        ShowUpdateStatusPanel("error", AppConfig.Version)
    } finally {
        UpdateBusy := false
    }
}

; A gold-bordered dark button matches the loading-card palette without native white controls.
; The inset is opaque near-black; against the gold frame it reads as a
; translucent dark surface without applying transparency to the whole window.
AddGoldUpdateButton(gui, x, y, width, height, caption)
{
    gui.Add("Text", "x" x " y" y " w" width " h" height " BackgroundC5A45C")
    gui.SetFont("s10 Bold cC5A45C", "Segoe UI")
    clickable := gui.Add("Text", "x" (x + 2) " y" (y + 2) " w" (width - 4) " h" (height - 4)
        " +0x100 Center +0x200 Background171008", caption)
    return clickable
}

CreateUpdateBackdrop()
{
    global LauncherGui
    ; Dim only the launcher, not the entire desktop; keep the focused panel above it.
    ; Query physical screen pixels: LauncherGui.GetPos returns DPI-scaled
    ; coordinates, which caused the overlay to cover only part of the launcher.
    bounds := Buffer(16, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", LauncherGui.Hwnd, "Ptr", bounds)
        throw Error("Unable to locate launcher for update backdrop.")
    lx := NumGet(bounds, 0, "Int")
    ly := NumGet(bounds, 4, "Int")
    lw := NumGet(bounds, 8, "Int") - lx
    lh := NumGet(bounds, 12, "Int") - ly
    dim := Gui("-Caption -Border -DPIScale +ToolWindow +Owner" LauncherGui.Hwnd, "tes3np Update Backdrop")
    dim.BackColor := "000000"
    dim.Show("NA x" lx " y" ly " w" lw " h" lh)
    WinSetTransparent(165, "ahk_id " dim.Hwnd)
    return dim
}

ShowCenteredUpdateCard(dialog, backdrop, width, height)
{
    rect := Buffer(16, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", backdrop.Hwnd, "Ptr", rect)
        throw Error("Unable to center update dialog.")
    left := NumGet(rect, 0, "Int")
    top := NumGet(rect, 4, "Int")
    dw := NumGet(rect, 8, "Int") - left
    dh := NumGet(rect, 12, "Int") - top
    dialog.Show("w" width " h" height " x" (left + Round((dw - width) / 2))
        " y" (top + Round((dh - height) / 2)))
}

ShowGoldUpdateConfirmation(title, message, confirmLabel)
{
    global LauncherGui
    response := {Accepted: false}
    backdrop := CreateUpdateBackdrop()
    window := Gui("-Caption -Border +Owner" backdrop.Hwnd " +AlwaysOnTop -DPIScale", "tes3np — Update Confirmation")
    window.BackColor := "C5A45C"
    window.Add("Text", "x2 y2 w636 h254 Background171008")
    window.SetFont("s15 Bold cC5A45C", "Georgia")
    window.Add("Text", "x32 y26 w588 h32 BackgroundTrans", title)
    window.SetFont("s10 cFFFFFF", "Segoe UI")
    window.Add("Text", "x32 y86 w588 h67 BackgroundTrans", message)
    confirm := AddGoldUpdateButton(window, 221, 203, 185, 34, confirmLabel)
    cancel := AddGoldUpdateButton(window, 422, 203, 185, 34, "Not Now")
    confirm.OnEvent("Click", (*) => (response.Accepted := true, window.Destroy()))
    cancel.OnEvent("Click", (*) => window.Destroy())
    window.OnEvent("Escape", (*) => window.Destroy())
    window.OnEvent("Close", (*) => window.Destroy())
    ShowCenteredUpdateCard(window, backdrop, 640, 258)
    hwnd := window.Hwnd
    WinWaitClose("ahk_id " hwnd)
    backdrop.Destroy()
    return response.Accepted
}

ShowUpdatePreview(installedVersion, latestVersion, channel)
{
    global LauncherGui, UpdateReleasePage
    ; This is an informational, owned dialog. No updater work occurs here.
    response := {Download: false}
    backdrop := CreateUpdateBackdrop()
    preview := Gui("-Caption -Border +Owner" backdrop.Hwnd " +AlwaysOnTop -DPIScale", "tes3np — Update Preview")
    preview.BackColor := "C5A45C"
    preview.SetFont("s10 cC5A45C", "Segoe UI")
    preview.Add("Text", "x2 y2 w636 h340 Background171008")
    preview.SetFont("s15 Bold cC5A45C", "Georgia")
    preview.Add("Text", "x32 y26 w588 h32 BackgroundTrans", "Update Preview")
    preview.SetFont("s11 cFFFFFF", "Segoe UI")
    preview.Add("Text", "x32 y86 w588 h24 BackgroundTrans", "Preview Latest v" latestVersion " Update!")
    preview.SetFont("s10 cFFFFFF", "Segoe UI")
    preview.Add("Text", "x32 y137 w588 h22 BackgroundTrans", "Installed: v" installedVersion)
    preview.Add("Text", "x32 y168 w588 h22 BackgroundTrans", "Latest: v" latestVersion)
    preview.Add("Text", "x32 y202 w588 h22 BackgroundTrans", "Channel: " (channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Live Stable"))
    preview.SetFont("s10 cC5A45C", "Segoe UI")
    preview.Add("Text", "x32 y261 w588 h36 BackgroundTrans", "A newer version is available. Review the release details before choosing to download.")
    preview.Add("Text", "x32 y280 w588 h22 BackgroundTrans", "Preview only — nothing has been downloaded or installed.")
    downloadButton := AddGoldUpdateButton(preview, 32, 303, 230, 34, "Continue to Download")
    laterButton := AddGoldUpdateButton(preview, 276, 303, 140, 34, "Not Now")
    releaseButton := AddGoldUpdateButton(preview, 430, 303, 178, 34, "Release Notes")
    downloadButton.OnEvent("Click", (*) => (response.Download := true, preview.Destroy()))
    laterButton.OnEvent("Click", (*) => preview.Destroy())
    releaseButton.OnEvent("Click", (*) => Run(UpdateReleasePage))
    preview.OnEvent("Close", (*) => preview.Destroy())
    preview.OnEvent("Escape", (*) => preview.Destroy())
    ShowCenteredUpdateCard(preview, backdrop, 640, 344)
    WinWaitClose("ahk_id " preview.Hwnd)
    backdrop.Destroy()
    return response.Download ? "Yes" : "No"
}

ShowUpdateStatusPanel(mode, installedVersion, latestVersion := "", channel := "alpha")
{
    global LauncherGui, UpdateReleasePage, DataFile
    state := {Retry: false}
    backdrop := CreateUpdateBackdrop()
    panel := Gui("-Caption -Border +Owner" backdrop.Hwnd " +AlwaysOnTop -DPIScale", "tes3np — Version Status")
    panel.BackColor := "C5A45C"
    panel.Add("Text", "x2 y2 w636 h392 Background171008")
    panel.SetFont("s15 Bold cC5A45C", "Georgia")
    caughtUp := mode = "current" || mode = "ahead"
    heading := caughtUp ? "You're All Caught Up, Fetcher! (v" installedVersion ")"
        : mode = "disabled" ? "Automatic Update Unavailable" : "Unable to Check for Updates"
    panel.Add("Text", "x30 y22 w588 h38 BackgroundTrans", heading)
    panel.SetFont("s10 cEDE1C9", "Segoe UI")
    if caughtUp {
        panel.Add("Text", "x32 y90 w572 h58 BackgroundTrans",
            "You are currently running the latest and greatest version of the tes3np launcher."
            . " If something new comes out, you will be notified.")
    } else {
        message := mode = "disabled"
            ? "Automatic updates are unavailable. You can still view the official releases."
            : "The latest version could not be verified. Your installation was not changed."
        panel.Add("Text", "x32 y90 w572 h58 BackgroundTrans", message)
    }
    panel.SetFont("s12 Bold cC5A45C", "Georgia")
    panel.Add("Text", "x32 y173 w572 h30 BackgroundTrans", "How do you take your releases?")
    panel.SetFont("s10 cEDE1C9", "Segoe UI")
    ; Only alpha has a public feed. Beta and stable preferences will appear once
    ; their respective feeds and release catalogs exist.
    selected := IniRead(DataFile, "Updates", "NotifyAlpha", "1") = "1"
    tick := panel.Add("Text", "x34 y221 w25 h23 +0x100 Center +0x200 Background352919 cC5A45C"
        , selected ? "✓" : "")
    description := panel.Add("Text", "x68 y221 w535 h25 BackgroundTrans",
        "Notify me when the latest alpha build is available to download.")
    toggle(*) {
        selectedNow := IniRead(DataFile, "Updates", "NotifyAlpha", "1") = "1"
        enabled := !selectedNow
        IniWrite(enabled ? "1" : "0", DataFile, "Updates", "NotifyAlpha")
        tick.Text := enabled ? "✓" : ""
        if !enabled
            SetLauncherUpdateAvailable(false)
        else if latestVersion != "" && CompareTes3npVersions(latestVersion, installedVersion) > 0
            SetLauncherUpdateAvailable(true, latestVersion)
    }
    tick.OnEvent("Click", toggle)
    description.OnEvent("Click", toggle)
    panel.SetFont("s9 cC5A45C", "Segoe UI")
    panel.Add("Text", "x32 y265 w572 h32 BackgroundTrans",
        "You can still check for updates anytime by clicking the version text.")
    notes := AddGoldUpdateButton(panel, 32, 348, 195, 34, "View Release Notes")
    retry := AddGoldUpdateButton(panel, 242, 348, 160, 34, "Check Again")
    close := AddGoldUpdateButton(panel, 417, 348, 191, 34, "Close")
    notes.OnEvent("Click", (*) => Run(UpdateReleasePage))
    retry.OnEvent("Click", (*) => (state.Retry := true, panel.Destroy()))
    close.OnEvent("Click", (*) => panel.Destroy())
    panel.OnEvent("Close", (*) => panel.Destroy())
    panel.OnEvent("Escape", (*) => panel.Destroy())
    ShowCenteredUpdateCard(panel, backdrop, 640, 396)
    hwnd := panel.Hwnd
    WinWaitClose("ahk_id " hwnd)
    backdrop.Destroy()
    if state.Retry
        SetTimer(CheckForUpdates, -100)
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

    psArgs := '-NoProfile -ExecutionPolicy Bypass -File "' worker
        . '" -InstallDir "' A_ScriptDir
        . '" -StageDir "' staged
        . '" -StateFile "' stateFile
        . '" -Version "' version
        . '" -ParentPid ' pid

    command := A_ComSpec ' /D /S /C start "" /B powershell.exe ' psArgs
    Run(command, A_ScriptDir, "Hide")

    ; Give the detached updater worker time to start before tes3np exits.
    Sleep(500)
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
    scriptPath := A_Temp "\tes3np-validate-update-" A_TickCount ".ps1"
    script := "$ErrorActionPreference='Stop'`r`n" .
        "Add-Type -AssemblyName System.IO.Compression.FileSystem`r`n" .
        "$package='" PsQuote(package) "'`r`n" .
        "$stage='" PsQuote(stage) "'`r`n" .
        "$z=[IO.Compression.ZipFile]::OpenRead($package)`r`n" .
        "$root=[IO.Path]::GetFullPath($stage+[IO.Path]::DirectorySeparatorChar)`r`n" .
        "try {`r`n" .
        "  foreach($e in $z.Entries){`r`n" .
        "    $p=[IO.Path]::GetFullPath([IO.Path]::Combine($root,$e.FullName))`r`n" .
        "    if(-not $p.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe archive path'}`r`n" .
        "  }`r`n" .
        "} finally { $z.Dispose() }`r`n" .
        "[IO.Compression.ZipFile]::ExtractToDirectory($package,$stage)`r`n" .
        "$exe=Get-ChildItem -LiteralPath $stage -Filter tes3np.exe -Recurse | Select-Object -First 1`r`n" .
        "if(-not $exe){throw 'tes3np.exe missing from staged package'}`r`n"
    try {
        FileAppend(script, scriptPath, "UTF-8")
        shell := ComObject("WScript.Shell")
        command := 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' scriptPath '"'
        exitCode := shell.Run(command, 0, true)
        if exitCode != 0
            throw Error("Update package failed safe staging validation.")
    } finally {
        try FileDelete(scriptPath)
    }
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
    ; The public metadata generator nests the package fields under "package".
    ; Keep support for the older flat manifest layout for prior alpha builds.
    if RegExMatch(text, 's)"package"\s*:\s*\{([^}]*)\}', &packageMatch) {
        packageText := packageMatch[1]
        manifest.fileName := RequireManifestString(packageText, "fileName")
        manifest.size := RequireManifestInteger(packageText, "size")
        manifest.sha256 := RequireManifestString(packageText, "sha256")
    } else {
        manifest.fileName := RequireManifestString(text, "fileName")
        manifest.size := RequireManifestInteger(text, "size")
        manifest.sha256 := RequireManifestString(text, "sha256")
    }
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
