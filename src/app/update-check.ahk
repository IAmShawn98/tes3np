; Safe update client. Installation remains an explicit user action.

global UpdateReleasePage := "https://github.com/IAmShawn98/tes3np-releases/releases/tag/latest-alpha"
global UpdateManifestUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-update.json"
global UpdatePackageUrl := "https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-windows.zip"
global UpdateBusy := false

CheckForUpdateAvailability(*)
{
    global AppConfig, UpdateManifestUrl
    ; Startup availability checks are intentionally silent. A network or metadata
    ; failure must never interrupt normal launcher use; the button simply stays hidden.
    try {
        manifest := ParseAndValidateUpdateManifest(DownloadUpdateText(UpdateManifestUrl))
        available := manifest.updateEnabled && CompareTes3npVersions(manifest.version, AppConfig.Version) > 0
        SetLauncherUpdateAvailable(available, manifest.version)
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
    window := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Update Confirmation")
    window.BackColor := "C5A45C"
    window.Add("Text", "x2 y2 w636 h254 Background171008")
    window.SetFont("s15 Bold cC5A45C", "Georgia")
    window.Add("Text", "x32 y26 w588 h32 BackgroundTrans", title)
    window.SetFont("s10 cFFFFFF", "Segoe UI")
    window.Add("Text", "x32 y86 w588 h67 BackgroundTrans", message)
    confirm := AddStyledButton(window, 221, 203, 185, 34, confirmLabel, (*) => (response.Accepted := true, window.Destroy()))
    cancel := AddStyledButton(window, 422, 203, 185, 34, "Not Now", (*) => window.Destroy())
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
    preview := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Update Preview")
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
    downloadButton := AddStyledButton(preview, 32, 303, 230, 34, "Continue to Download", (*) => (response.Download := true, preview.Destroy()))
    laterButton := AddStyledButton(preview, 276, 303, 140, 34, "Not Now", (*) => preview.Destroy())
    releaseButton := AddStyledButton(preview, 430, 303, 178, 34, "Release Notes", (*) => Run(UpdateReleasePage))
    preview.OnEvent("Close", (*) => preview.Destroy())
    preview.OnEvent("Escape", (*) => preview.Destroy())
    ShowCenteredUpdateCard(preview, backdrop, 640, 344)
    WinWaitClose("ahk_id " preview.Hwnd)
    backdrop.Destroy()
    return response.Download ? "Yes" : "No"
}

ReadDraftVersionNotes(installedVersion)
{
    ; Only use this for an unreleased development version, never for a
    ; published version whose GitHub release notes are authoritative.
    changelog := A_ScriptDir "\CHANGELOG.md"
    if !FileExist(changelog)
        return 0
    content := StrReplace(FileRead(changelog, "UTF-8"), "`r", "")
    entries := StrSplit(content, "`n")
    collecting := false
    notes := ""
    for entry in entries {
        if SubStr(entry, 1, 3) = "## " {
            if collecting
                break
            if InStr(entry, "v" installedVersion) && InStr(StrLower(entry), "unreleased")
                collecting := true
            continue
        }
        if !collecting
            continue
        line := Trim(entry)
        if SubStr(line, 1, 4) = "### " {
            notes .= SubStr(line, 5) "`n"
        } else if SubStr(line, 1, 2) = "- " {
            notes .= "• " StrReplace(SubStr(line, 3), "**", "") "`n"
        }
    }
    return notes != "" ? {Text: RTrim(notes, "`n"), Source: "Development notes — unreleased, subject to change"} : 0
}

ReadVersionReleaseNotes(installedVersion)
{
    ; Published release notes are loaded by exact version tag. This never
    ; substitutes the latest release's notes for an older installation.
    global BundledResourceRoot
    script := (A_IsCompiled ? BundledResourceRoot : A_ScriptDir) "\scripts\fetch-release-notes.ps1"
    if !FileExist(script)
        return {Text: "The GitHub release notes helper is missing.", Source: "Notes unavailable"}
    output := A_Temp "\tes3np-notes-" A_TickCount ".txt"
    command := 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' script
        . '" -Version "' installedVersion '" -OutputPath "' output '"'
    try {
        exitCode := RunWait(command, A_ScriptDir, "Hide")
        if exitCode != 0 || !FileExist(output)
            throw Error("Release notes could not be retrieved.")
        notesText := FileRead(output, "UTF-8")
        sourceText := FileExist(output ".source") ? FileRead(output ".source", "UTF-8") : "GitHub Releases"
        if InStr(sourceText, "Notes not published") {
            draft := ReadDraftVersionNotes(installedVersion)
            if IsObject(draft)
                return draft
        }
        return {Text: notesText, Source: sourceText}
    } catch Error {
        return {Text: "Could not load release notes for v" installedVersion ". Please check GitHub Releases.", Source: "GitHub unavailable"}
    } finally {
        try FileDelete(output)
        try FileDelete(output ".source")
    }
}

WrapReleaseNoteLines(content, maximum := 56)
{
    wrapped := []
    for entry in StrSplit(StrReplace(content, "`r", ""), "`n") {
        line := Trim(entry)
        if line = "" {
            wrapped.Push("")
            continue
        }
        while StrLen(line) > maximum {
            splitAt := maximum
            while splitAt > 20 && SubStr(line, splitAt, 1) != " "
                splitAt -= 1
            if splitAt <= 20
                splitAt := maximum
            wrapped.Push(RTrim(SubStr(line, 1, splitAt)))
            line := LTrim(SubStr(line, splitAt + 1))
        }
        wrapped.Push(line)
    }
    return wrapped
}

UpdateNotesMouseWheel(dialog, page, refresh, wParam, lParam, msg, hwnd)
{
    ; The Windows wheel coordinates are physical screen pixels. Compare with
    ; the actual dialog window rectangle to avoid mixed-DPI hit-test errors.
    if !DllCall("user32\IsWindow", "Ptr", dialog.Hwnd, "Int")
        return
    mx := (lParam & 0xFFFF) << 48 >> 48
    my := ((lParam >> 16) & 0xFFFF) << 48 >> 48
    bounds := Buffer(16, 0)
    if !DllCall("user32\GetWindowRect", "Ptr", dialog.Hwnd, "Ptr", bounds)
        return
    if mx < NumGet(bounds, 0, "Int") || mx >= NumGet(bounds, 8, "Int")
        || my < NumGet(bounds, 4, "Int") || my >= NumGet(bounds, 12, "Int")
        return
    delta := (wParam >> 16) << 48 >> 48
    page.Offset += delta > 0 ? -3 : 3
    refresh()
    return 0
}

UpdateNotesDragMove(drag, page, refresh)
{
    if !drag.Active
        return
    if !GetKeyState("LButton", "P") {
        drag.Active := false
        SetTimer(drag.Timer, 0)
        return
    }
    MouseGetPos(, &mouseY)
    maxOffset := Max(1, page.Lines.Length - page.Visible + 1)
    travel := Max(1, 107 - drag.ThumbHeight)
    page.Offset := 1 + Round((mouseY - drag.StartY) * (maxOffset - 1) / travel) + drag.StartOffset - 1
    refresh()
}

StartUpdateNotesDrag(thumb, drag, page, refresh, wParam, lParam, msg, hwnd)
{
    if hwnd != thumb.Hwnd || page.Lines.Length <= page.Visible
        return
    drag.Active := true
    MouseGetPos(, &startY)
    drag.StartY := startY
    drag.StartOffset := page.Offset
    drag.Timer := UpdateNotesDragMove.Bind(drag, page, refresh)
    SetTimer(drag.Timer, 16)
}

ShowUpdateStatusPanel(mode, installedVersion, latestVersion := "", channel := "alpha")
{
    global LauncherGui, UpdateReleasePage
    state := {Retry: false}
    backdrop := CreateUpdateBackdrop()
    panel := Gui("-Caption -Border +Owner" backdrop.Hwnd " -DPIScale", "tes3np — Version Status")
    panel.BackColor := "C5A45C"
    panel.Add("Text", "x2 y2 w636 h392 Background171008")
    panel.SetFont("s12 Bold cC5A45C", "Georgia")
    panel.Add("Text", "x28 y18 w586 h38 BackgroundTrans", "You're All Caught Up, Fetcher!")
    panel.SetFont("s10 cEDE1C9", "Segoe UI")
    panel.Add("Text", "x28 y61 w584 h49 BackgroundTrans",
        "You are running the latest and greatest version of the tes3np launcher! If an update is published, you will be notified.")
    panel.SetFont("s10 Bold cC5A45C", "Segoe UI")
    panel.Add("Text", "x28 y117 w584 h24 BackgroundTrans",
        "Build: v" installedVersion " Release Notes -")
    notes := ReadVersionReleaseNotes(installedVersion)
    panel.SetFont("s10 cEDE1C9", "Segoe UI")
    ; Gold-framed notes with the same vertical gold-on-brown scrollbar used
    ; by the launcher parchment. Arrows live at the ends of the track.
    panel.Add("Text", "x28 y151 w584 h185 BackgroundC5A45C")
    panel.Add("Text", "x30 y153 w580 h181 Background171008")
    notesLines := WrapReleaseNoteLines(notes.Text)
    page := {Offset: 1, Lines: notesLines, Visible: 6}
    noteRows := []
    Loop page.Visible
        noteRows.Push(panel.Add("Text", "x38 y" (166 + (A_Index - 1) * 24) " w536 h24 Background171008", ""))
    track := panel.Add("Text", "x585 y181 w16 h125 Background704C27")
    thumb := panel.Add("Text", "x589 y181 w8 h30 BackgroundC69951")
    drag := {Active: false, StartY: 0, StartOffset: 1, ThumbHeight: 30, Timer: 0}
    refresh(*) {
        maxOffset := Max(1, page.Lines.Length - page.Visible + 1)
        page.Offset := Min(maxOffset, Max(1, page.Offset))
        for index, row in noteRows
            row.Text := index + page.Offset - 1 <= page.Lines.Length ? page.Lines[index + page.Offset - 1] : ""
        thumbHeight := Max(22, Round(125 * Min(1, page.Visible / Max(1, page.Lines.Length))))
        drag.ThumbHeight := thumbHeight
        thumb.Move(589, 181 + Round((125 - thumbHeight) * (page.Offset - 1) / Max(1, maxOffset - 1)), 8, thumbHeight)
        track.Visible := page.Lines.Length > page.Visible
        thumb.Visible := page.Lines.Length > page.Visible
    }
    dragStartCallback := StartUpdateNotesDrag.Bind(thumb, drag, page, refresh)
    OnMessage(0x0201, dragStartCallback, 1)
    scrollUp := AddStyledButton(panel, 583, 155, 20, 22, "↑", (*) => (page.Offset -= 1, refresh()))
    scrollDown := AddStyledButton(panel, 583, 310, 20, 22, "↓", (*) => (page.Offset += 1, refresh()))
    refresh()
    ; Register an additional wheel callback only for this dialog's lifetime.
    ; It consumes wheel input solely inside the release-notes viewport.
    wheelCallback := UpdateNotesMouseWheel.Bind(panel, page, refresh)
    OnMessage(0x020A, wheelCallback, 1)
    retry := AddStyledButton(panel, 100, 350, 213, 32, "Check For Updates", (*) => (state.Retry := true, panel.Destroy()))
    close := AddStyledButton(panel, 327, 350, 213, 32, "Close", (*) => panel.Destroy())
    panel.OnEvent("Close", (*) => panel.Destroy())
    panel.OnEvent("Escape", (*) => panel.Destroy())
    ShowCenteredUpdateCard(panel, backdrop, 640, 396)
    hwnd := panel.Hwnd
    WinWaitClose("ahk_id " hwnd)
    OnMessage(0x020A, wheelCallback, 0)
    OnMessage(0x0201, dragStartCallback, 0)
    drag.Active := false
    if IsObject(drag.Timer)
        SetTimer(drag.Timer, 0)
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
