; Display update status, release previews, and download and install confirmations.

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
