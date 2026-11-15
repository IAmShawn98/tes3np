; Safe update client. Installation remains an explicit user action.

global UpdateBusy := false
global UpdateStartupRequest := 0
global UpdateStartupStarted := 0
global LauncherVersionLabel := 0
global LauncherUpdateButton := 0
global LauncherUpdateDismissedVersion := ""

CreateLauncherVersionLabel()
{
    global AppConfig, LauncherGui, LauncherVersionLabel, LauncherUpdateDismissedVersion

    LauncherUpdateDismissedVersion := ""
    LauncherGui.SetFont("s9 cC5A45C", "Segoe UI")
    LauncherVersionLabel := LauncherGui.Add("Text", "x12 y691 w300 h18 BackgroundTrans", "tes3np · v" AppConfig.Version)
    LauncherVersionLabel.OnEvent("Click", CheckForUpdates)
}

CreateLauncherUpdateButton()
{
    global LauncherGui, LauncherUpdateButton

    ; The update button shares the version label's space.
    LauncherUpdateButton := AddStyledButton(LauncherGui, 12, 682, 300, 30, "Preview Latest Update!", CheckForUpdates)
    LauncherUpdateButton.Visible := false
}

ScaleLauncherVersionLabel(scale)
{
    global LauncherVersionLabel

    if IsObject(LauncherVersionLabel)
        LauncherVersionLabel.SetFont("s" Max(7, Round(9 * scale)), "Segoe UI")
}

SetLauncherUpdateAvailable(isAvailable, latestVersion := "")
{
    global AppConfig, LauncherUpdateButton, LauncherVersionLabel, LauncherUpdateDismissedVersion

    if !IsObject(LauncherUpdateButton) || !IsObject(LauncherVersionLabel)
        return
    if isAvailable && latestVersion != "" {
        kind := GetLauncherUpdateKind(AppConfig.Version, latestVersion)
        LauncherUpdateButton.Text := kind = "hotfix" ? "Hotfix available" : "Preview Latest v" latestVersion " Update!"
        DllCall("user32\InvalidateRect", "Ptr", LauncherUpdateButton.Hwnd, "Ptr", 0, "Int", 1)
    }
    showUpdate := isAvailable && latestVersion != LauncherUpdateDismissedVersion
    LauncherUpdateButton.Visible := showUpdate
    LauncherVersionLabel.Visible := !showUpdate
}

DismissLauncherUpdate(latestVersion)
{
    global LauncherUpdateDismissedVersion
    LauncherUpdateDismissedVersion := latestVersion
    SetLauncherUpdateAvailable(true, latestVersion)
}

CheckForUpdateAvailability(*)
{
    global AppConfig, UpdateStartupRequest, UpdateStartupStarted
    ; The automatic startup check must not block the AHK GUI thread while
    ; waiting for GitHub. Manual checks still use the existing trusted flow.
    if IsObject(UpdateStartupRequest)
        return
    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(5000, 5000, 10000, 10000)
        request.Open("GET", GetUpdateManifestUrl(AppConfig.Version), true)
        request.SetRequestHeader("User-Agent", "tes3np updater")
        UpdateStartupRequest := request
        UpdateStartupStarted := A_TickCount
        request.Send()
        SetTimer(PollStartupUpdateAvailability, 100)
        LogLauncherEvent("UPDATE | Nonblocking startup availability request started.")
    } catch Error as err {
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        SetLauncherUpdateAvailable(false)
        LogLauncherEvent("UPDATE | Startup availability check unavailable (" Type(err) ").")
    }
}

PollStartupUpdateAvailability(*)
{
    global AppConfig, UpdateStartupRequest, UpdateStartupStarted
    request := UpdateStartupRequest
    if !IsObject(request) {
        SetTimer(PollStartupUpdateAvailability, 0)
        return
    }
    elapsed := A_TickCount - UpdateStartupStarted
    ; WinHTTP's individual timeouts are bounded, but abort a stalled whole
    ; request too. Checking completion with 0 seconds never waits on WinHTTP.
    if elapsed > 30000 {
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        try request.Abort()
        SetLauncherUpdateAvailable(false)
        LogLauncherEvent("UPDATE | Startup availability check timed out after " elapsed "ms.")
        return
    }
    try {
        if !request.WaitForResponse(0)
            return
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        if request.Status != 200
            throw Error("Update metadata returned HTTP " request.Status ".")
        manifest := ParseAndValidateUpdateManifest(request.ResponseText, AppConfig.Version)
        available := manifest.UpdateEnabled && GetLauncherUpdateKind(AppConfig.Version, manifest.Version) != ""
        SetLauncherUpdateAvailable(available, manifest.version)
        if available && !HasSeenUpdateAutoPreview(manifest.version)
            SetTimer(AutoPreviewNewUpdate.Bind(manifest.version), -4000)
        LogLauncherEvent("UPDATE | Startup availability check | Current: v" AppConfig.Version " | Latest: v" manifest.version " | Available: " (available ? "yes" : "no") " | Elapsed: " elapsed "ms.")
    } catch Error as err {
        SetTimer(PollStartupUpdateAvailability, 0)
        UpdateStartupRequest := 0
        SetLauncherUpdateAvailable(false)
        LogLauncherEvent("UPDATE | Startup availability check unavailable (" Type(err) ") after " elapsed "ms.")
    }
}

HasSeenUpdateAutoPreview(version)
{
    global DataFile
    return IniRead(DataFile, "Updates", "LastAutoPreviewVersion", "") = version
}

AutoPreviewNewUpdate(version, *)
{
    global LauncherGui, UpdateBusy, LauncherUpdateDismissedVersion
    if UpdateBusy || LauncherUpdateDismissedVersion = version || HasSeenUpdateAutoPreview(version)
        return
    if !IsObject(LauncherGui) || !DllCall("user32\\IsWindowVisible", "Ptr", LauncherGui.Hwnd)
        return
    CheckForUpdates()
}

CheckForUpdates(*)
{
    global AppConfig, UpdateBusy, LauncherGui, DataFile
    if UpdateBusy {
        LogLauncherEvent("UPDATE | Check ignored because another update operation is active.")
        return
    }
    UpdateBusy := true
    staged := ""
    handedOff := false
    LogLauncherEvent("UPDATE | Checking trusted update manifest. Current: v" AppConfig.Version ".")
    try {
        manifest := ParseAndValidateUpdateManifest(DownloadUpdateText(GetUpdateManifestUrl(AppConfig.Version)), AppConfig.Version)
        latest := manifest.version
        kind := GetLauncherUpdateKind(AppConfig.Version, latest)
        LogLauncherEvent("UPDATE | Manifest validated. Current: v" AppConfig.Version " | Latest: v" latest ".")
        if !manifest.updateEnabled {
            SetLauncherUpdateAvailable(false)
            LogLauncherEvent("UPDATE | Automatic installation disabled by release metadata.")
            ShowUpdateStatusPanel("disabled", AppConfig.Version, latest)
            return
        }
        if kind = "" {
            SetLauncherUpdateAvailable(false)
            LogLauncherEvent("UPDATE | SUCCESS | Launcher is up to date.")
            ShowUpdateStatusPanel("current", AppConfig.Version)
            return
        }
        ; The startup check owns the footer notification. Opening a preview
        ; from the version text must not re-show a dismissed banner.
        LogLauncherEvent("UPDATE | Update available: v" latest ".")
        ; The first preview of this published version is remembered across restarts,
        ; regardless of whether it opened automatically or the user opened it.
        ; Store before showing the modal so Cancel/Not Now does not repeat next launch.
        if !HasSeenUpdateAutoPreview(latest)
            IniWrite(latest, DataFile, "Updates", "LastAutoPreviewVersion")
        ; Viewing the gold preview never downloads, stages, or installs files.
        choice := ShowUpdatePreview(AppConfig.Version, latest, manifest.channel, kind)
        if choice = "Yes" && ShowGoldUpdateConfirmation("Download Update?", "Download and verify v" latest "?`nThe installed launcher will not be changed.", "Download") {
            BeginInterfaceUpdate(LauncherGui, "Downloading update...", true, 5)
            try {
                staged := DownloadAndStageUpdate(manifest)
                SetInterfaceLoadingText("Update ready to install...")
            } finally EndInterfaceUpdate()
            LogLauncherEvent("UPDATE | READY | Verified update staged for v" latest ".")
            if ShowGoldUpdateConfirmation("Install Verified Update?", "v" latest " is verified and ready.`nInstalling will restart tes3np. Rollback is available if startup fails.", "Install Update") {
                StartTransactionalUpdate(manifest.version, staged)
                handedOff := true
                LogLauncherEvent("UPDATE | Transactional installer started for v" latest ".")
                ExitApp(0)
            }
            LogLauncherEvent("UPDATE | Installation deferred for verified update v" latest ".")
        } else {
            DismissLauncherUpdate(latest)
            LogLauncherEvent("UPDATE | User deferred update v" latest "; clickable version label restored.")
        }
    } catch Error as err {
        LogLauncherEvent("ERROR | UPDATE | " Type(err))
        ShowUpdateStatusPanel("error", AppConfig.Version)
    } finally {
        if staged != "" && !handedOff
            DeleteLauncherStagingTree(staged)
        UpdateBusy := false
    }
}

ShowGoldUpdateConfirmation(title, message, confirmLabel)
{
    response := {Accepted: false}
    backdrop := CreateGoldPromptBackdrop()
    window := 0
    try {
        window := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Update Confirmation")
        window.BackColor := "C5A45C"
        window.Add("Text", "x2 y2 w636 h254 Background171008")
        window.SetFont("s15 Bold cC5A45C", "Georgia")
        window.Add("Text", "x32 y26 w588 h32 BackgroundTrans", title)
        window.SetFont("s10 cFFFFFF", "Segoe UI")
        window.Add("Text", "x32 y86 w588 h67 BackgroundTrans", message)
        AddStyledButton(window, 221, 203, 185, 34, confirmLabel, (*) => (response.Accepted := true, window.Destroy()))
        AddStyledButton(window, 422, 203, 185, 34, "Not Now", (*) => window.Destroy())
        window.OnEvent("Escape", (*) => window.Destroy())
        window.OnEvent("Close", (*) => window.Destroy())
        hwnd := window.Hwnd
        ShowCenteredGoldPrompt(window, backdrop, 640, 258)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        if IsObject(window)
            try window.Destroy()
        try backdrop.Destroy()
    }
    return response.Accepted
}

ShowUpdatePreview(installedVersion, latestVersion, channel, kind)
{
    notes := ReadPublishedVersionNotes(latestVersion)
    response := {Download: false}
    backdrop := CreateGoldPromptBackdrop()
    preview := 0
    closeNotes := 0
    try {
        preview := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Update Preview")
        preview.BackColor := "C5A45C"
        preview.Add("Text", "x2 y2 w796 h626 Background171008")
        preview.SetFont("s15 Bold cC5A45C", "Georgia")
        releaseType := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Stable"
        title := kind = "hotfix" ? "Hotfix available" : "A New " releaseType " Is Available to Download, S'wit!"
        preview.Add("Text", "x30 y20 w740 h38 BackgroundTrans", title)
        preview.SetFont("s10 cEDE1C9", "Segoe UI")
        preview.Add("Text", "x30 y62 w740 h24 BackgroundTrans", "You can review the changes below before deciding to update.")
        preview.Add("Text", "x30 y94 w195 h24 BackgroundTrans", "Installed: v" installedVersion)
        preview.Add("Text", "x238 y94 w195 h24 BackgroundTrans", "Latest: v" latestVersion)
        preview.Add("Text", "x446 y94 w324 h24 BackgroundTrans", "Channel: " (channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Live Stable"))
        preview.SetFont("s10 Bold cC5A45C", "Segoe UI")
        preview.Add("Text", "x30 y125 w740 h25 BackgroundTrans", "v" latestVersion " Release Notes")
        closeNotes := AddUpdateNotesViewport(preview, notes)
        preview.SetFont("s10 cC5A45C", "Segoe UI")
        preview.Add("Text", "x30 y529 w740 h22 BackgroundTrans", "A newer version is available. Review the release details before choosing to download.")
        preview.Add("Text", "x30 y551 w740 h22 BackgroundTrans", "Preview only — nothing has been downloaded or installed.")
        AddStyledButton(preview, 32, 582, 230, 34, "Continue to Download", (*) => (response.Download := true, preview.Destroy()))
        AddStyledButton(preview, 330, 582, 140, 34, "Not Now", (*) => preview.Destroy())
        AddStyledButton(preview, 590, 582, 178, 34, "Release Notes", (*) => Run(GetTes3npReleasePage(latestVersion)))
        preview.OnEvent("Close", (*) => preview.Destroy())
        preview.OnEvent("Escape", (*) => preview.Destroy())
        hwnd := preview.Hwnd
        ShowCenteredGoldPrompt(preview, backdrop, 800, 630)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        if IsObject(closeNotes)
            try closeNotes()
        if IsObject(preview)
            try preview.Destroy()
        try backdrop.Destroy()
    }
    return response.Download ? "Yes" : "No"
}

ShowUpdateStatusPanel(mode, installedVersion, latestVersion := "")
{
    newer := mode = "disabled" && GetLauncherUpdateKind(installedVersion, latestVersion) != ""
    notesVersion := newer ? latestVersion : installedVersion
    title := "You're All Caught Up, Fetcher!"
    message := "You are running the latest and greatest version of the tes3np launcher! If an update is published, you will be notified."
    if mode = "error" {
        title := "Could Not Check for Updates"
        message := "Showing release notes for your installed version."
    } else if mode = "disabled" {
        title := "Automatic Updates Are Unavailable"
        message := "Check GitHub Releases for download options."
    }
    notes := newer ? ReadPublishedVersionNotes(notesVersion) : ReadVersionReleaseNotes(installedVersion)
    state := {Retry: false}
    backdrop := CreateGoldPromptBackdrop()
    panel := 0
    closeNotes := 0
    try {
        panel := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Version Status")
        panel.BackColor := "C5A45C"
        panel.Add("Text", "x2 y2 w796 h596 Background171008")
        panel.SetFont("s14 Bold cC5A45C", "Georgia")
        panel.Add("Text", "x30 y20 w740 h38 BackgroundTrans", title)
        panel.SetFont("s10 cEDE1C9", "Segoe UI")
        panel.Add("Text", "x30 y65 w740 h55 BackgroundTrans", message)
        panel.SetFont("s10 Bold cC5A45C", "Segoe UI")
        panel.Add("Text", "x30 y125 w740 h25 BackgroundTrans", "Build: v" notesVersion " Release Notes -")
        closeNotes := AddUpdateNotesViewport(panel, notes)
        AddStyledButton(panel, 178, 544, 212, 34, "Check For Updates", (*) => (state.Retry := true, panel.Destroy()))
        AddStyledButton(panel, 410, 544, 212, 34, "Close", (*) => panel.Destroy())
        panel.OnEvent("Close", (*) => panel.Destroy())
        panel.OnEvent("Escape", (*) => panel.Destroy())
        hwnd := panel.Hwnd
        ShowCenteredGoldPrompt(panel, backdrop, 800, 600)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        if IsObject(closeNotes)
            try closeNotes()
        if IsObject(panel)
            try panel.Destroy()
        try backdrop.Destroy()
    }
    if state.Retry
        SetTimer(CheckForUpdates, -100)
}

StartTransactionalUpdate(version, staged)
{
    worker := A_ScriptDir "\scripts\tes3np-updater.ps1"
    stateFile := staged "\update-state.ini"

    if PatchInProgress()
        throw Error("Finish the Expansion Pack import before updating.")
    if !FileExist(worker)
        throw Error("Updater worker is missing from this installation.")
    if !FileExist(stateFile)
        throw Error("Update state file is missing.")

    pid := DllCall("GetCurrentProcessId", "UInt")

    psArgs := '-NoProfile -ExecutionPolicy Bypass -File "' worker
        . '" -InstallDir "' A_ScriptDir
        . '" -StageDir "' staged '\staged'
        . '" -StateFile "' stateFile
        . '" -Version "' version
        . '" -ManagedStage -ParentPid ' pid

    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    Run('"' powershell '" ' psArgs, A_ScriptDir, "Hide")

    ; Give the detached updater worker time to start before tes3np exits.
    Sleep(500)
}

GetPendingUpdateStatePath()
{
    global AppConfig
    if A_Args.Length < 3 || A_Args[1] != "--update-confirm"
        return ""

    version := A_Args[2]
    statePath := A_Args[3]
    updateRoot := GetFullPath(A_Temp "\tes3np-update")
    statePath := GetFullPath(statePath)
    SplitPath(statePath, &name, &folder)
    ; The legacy updater uses the shared directory. New jobs use individual subdirectories.
    SplitPath(folder, &jobId, &jobParent)
    if name != "update-state.ini" || (folder != updateRoot
        && (jobParent != updateRoot || !RegExMatch(jobId, "i)^[0-9a-f]{32}$")))
        throw Error("Update confirmation state path is invalid.")
    if version != AppConfig.Version
        throw Error("Update confirmation version does not match installed launcher.")
    if !FileExist(statePath)
        throw Error("Update confirmation state file is missing.")
    ; Read UTF-8 directly so a byte-order mark cannot hide the [Update] section.
    lines := StrSplit(FileRead(statePath, "UTF-8"), "`n", "`r")
    if lines.Length < 3 || lines[1] != "[Update]"
        || lines[2] != "State=AWAITING_CONFIRMATION" || lines[3] != "Version=" AppConfig.Version
        throw Error("Update confirmation does not match a pending installation.")
    return statePath
}

ConfirmUpdatedLauncherStartup(statePath)
{
    global AppConfig
    ; The worker polls this file directly. Replace it atomically so the worker
    ; cannot read a partially written confirmation.
    tempConfirmationPath := statePath ".confirm.tmp"
    try FileDelete(tempConfirmationPath)
    confirmation := "[Update]`r`nState=CONFIRMED`r`nVersion=" AppConfig.Version
        . "`r`nUpdatedUtc=" FormatTime(A_NowUTC, "yyyy-MM-ddTHH:mm:ssZ") "`r`n"
    FileAppend(confirmation, tempConfirmationPath, "UTF-8")
    FileMove(tempConfirmationPath, statePath, true)

    LogLauncherEvent("UPDATE | CONFIRMED | Updated launcher v" AppConfig.Version " confirmed successful startup.")
}

RecoverInterruptedLauncherUpdate()
{
    if !A_IsCompiled || !FileExist(A_ScriptDir ".tes3np-recovery\pending.txt")
        return
    worker := A_ScriptDir "\scripts\tes3np-updater.ps1"
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    pid := DllCall("GetCurrentProcessId", "UInt")
    Run('"' powershell '" -NoProfile -ExecutionPolicy Bypass -File "' worker
        . '" -InstallDir "' A_ScriptDir '" -Version "' AppConfig.Version
        . '" -RecoverOnly -ParentPid ' pid, A_ScriptDir, "Hide")
    ExitApp(0)
}

GetFullPath(path)
{
    size := DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    if !size
        throw Error("Unable to resolve the full file path.")
    pathBuffer := Buffer(size * 2, 0)
    if !DllCall("Kernel32\GetFullPathNameW", "Str", path, "UInt", size, "Ptr", pathBuffer, "Ptr", 0, "UInt")
        throw Error("Unable to resolve the full file path.")
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
    root := A_Temp "\tes3np-update\" NewLauncherFileId()
    part := root "\tes3np-windows.zip.part"
    stage := root "\staged"
    DirCreate(root)
    try {
        SetInterfaceLoadingText("Downloading update...")
        LogLauncherEvent("UPDATE | Download started | v" manifest.version ".")
        Download(manifest.PackageUrl, part)
        if !FileExist(part)
            throw Error("Downloaded update package is missing.")
        SetInterfaceLoadingText("Checking download size...")
        if FileGetSize(part) != manifest.size
            throw Error("Downloaded update size does not match trusted metadata.")
        SetInterfaceLoadingText("Verifying update...")
        if SHA256File(part) != StrLower(manifest.sha256)
            throw Error("Downloaded update failed SHA-256 verification.")
        LogLauncherEvent("UPDATE | Download verified | SHA-256 and size match trusted metadata.")
        SetInterfaceLoadingText("Preparing update...")
        ValidateUpdateArchive(part, stage)
        FileDelete(part)
        SetInterfaceLoadingText("Saving update state...")
        state := root "\update-state.ini"
        IniWrite("STAGED", state, "Update", "State")
        IniWrite(manifest.version, state, "Update", "Version")
        return root
    } catch {
        DeleteLauncherStagingTree(root)
        throw
    }
}

ValidateUpdateArchive(package, stage)
{
    SplitPath(package, , &root)
    scriptPath := root "\validate-update.ps1"
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
        powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
        command := '"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' scriptPath '"'
        exitCode := shell.Run(command, 0, true)
        if exitCode != 0
            throw Error("Update package failed safe staging validation.")
    } finally {
        try FileDelete(scriptPath)
    }
    LogLauncherEvent("UPDATE | Package staged and structure validated.")
}

PsQuote(value) => StrReplace(value, "'", "''")
