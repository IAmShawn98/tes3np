; Display update status, release previews, and download and install confirmations.

ShowGoldUpdateConfirmation(title, message, confirmLabel)
{
    response := {Accepted: false}
    window := CreateGoldNativePrompt(0, "tes3np — Update Confirmation", 640, 258)
    try {
        window.SetFont("s15 Bold cC5A45C", "Georgia")
        window.Add("Text", "x32 y26 w588 h32 BackgroundTrans", title)
        window.SetFont("s10 cFFFFFF", "Segoe UI")
        window.Add("Text", "x32 y86 w588 h67 BackgroundTrans", message)
        AddStyledButton(window, 221, 203, 185, 34, confirmLabel, (*) => (response.Accepted := true, DestroyScaledMenu(window)))
        AddStyledButton(window, 422, 203, 185, 34, "Not Now", (*) => DestroyScaledMenu(window))
        window.OnEvent("Escape", (*) => DestroyScaledMenu(window))
        window.OnEvent("Close", (*) => DestroyScaledMenu(window))
        hwnd := window.Hwnd
        ShowGoldNativePrompt(window, GetUpdatePromptFitScale(window))
        WinWaitClose("ahk_id " hwnd)
    } finally {
        CloseGoldNativePrompt(window)
    }
    return response.Accepted
}

ShowUpdatePreview(installedVersion, latestVersion, channel, kind)
{
    notes := ReadPublishedVersionNotes(latestVersion)
    response := {Download: false}
    preview := CreateGoldNativePrompt(0, "tes3np — Update Preview", 800, 630)
    closeNotes := 0
    try {
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
        preview.SetFont("s10 cC5A45C", "Segoe UI")
        preview.Add("Text", "x30 y529 w740 h22 BackgroundTrans", "A newer version is available. Review the release details before choosing to download.")
        preview.Add("Text", "x30 y551 w740 h22 BackgroundTrans", "Preview only — nothing has been downloaded or installed.")
        AddStyledButton(preview, 32, 582, 230, 34, "Continue to Download", (*) => (response.Download := true, DestroyScaledMenu(preview)))
        AddStyledButton(preview, 330, 582, 140, 34, "Not Now", (*) => DestroyScaledMenu(preview))
        AddStyledButton(preview, 590, 582, 178, 34, "Release Notes", (*) => Run(GetTes3npReleasePage(latestVersion)))
        preview.OnEvent("Close", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Escape", (*) => DestroyScaledMenu(preview))
        scale := GetUpdatePromptFitScale(preview)
        ScaleOwnedMenuContent(preview, scale)
        closeNotes := AddUpdateNotesViewport(preview, notes, scale)
        hwnd := preview.Hwnd
        ShowGoldNativePrompt(preview, scale)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        if IsObject(closeNotes)
            try closeNotes()
        CloseGoldNativePrompt(preview)
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
    panel := CreateGoldNativePrompt(0, "tes3np — Version Status", 800, 600)
    closeNotes := 0
    try {
        panel.SetFont("s14 Bold cC5A45C", "Georgia")
        panel.Add("Text", "x30 y20 w740 h38 BackgroundTrans", title)
        panel.SetFont("s10 cEDE1C9", "Segoe UI")
        panel.Add("Text", "x30 y65 w740 h55 BackgroundTrans", message)
        panel.SetFont("s10 Bold cC5A45C", "Segoe UI")
        panel.Add("Text", "x30 y125 w740 h25 BackgroundTrans", "Build: v" notesVersion " Release Notes -")
        AddStyledButton(panel, 178, 544, 212, 34, "Check For Updates", (*) => (state.Retry := true, DestroyScaledMenu(panel)))
        AddStyledButton(panel, 410, 544, 212, 34, "Close", (*) => DestroyScaledMenu(panel))
        panel.OnEvent("Close", (*) => DestroyScaledMenu(panel))
        panel.OnEvent("Escape", (*) => DestroyScaledMenu(panel))
        scale := GetUpdatePromptFitScale(panel)
        ScaleOwnedMenuContent(panel, scale)
        closeNotes := AddUpdateNotesViewport(panel, notes, scale)
        hwnd := panel.Hwnd
        ShowGoldNativePrompt(panel, scale)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        if IsObject(closeNotes)
            try closeNotes()
        CloseGoldNativePrompt(panel)
    }
    if state.Retry
        SetTimer(CheckForUpdates, -100)
}

GetUpdatePromptFitScale(panel)
{
    ; The backdrop uses screen pixels and matches the launcher. Keep the
    ; original dialog layout whenever it fits, with a margin at each edge.
    panel.NativePromptBackdrop.GetClientPos(, , &width, &height)
    return Max(0.5, Min(1.0, (width - 32) / panel.NativePromptWidth,
        (height - 32) / panel.NativePromptHeight))
}
