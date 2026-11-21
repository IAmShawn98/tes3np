; Display update status, release previews, and download and install confirmations.

ShowGoldUpdateConfirmation(title, message, confirmLabel)
{
    response := {Accepted: false}
    window := CreateGoldNativePrompt(0, "tes3np — Update Confirmation", 640, 258)
    try {
        window.SetFont("s15 Bold cC5A45C", "Georgia")
        extra := AddGoldPromptCopy(window, 32, 26, 588, 32, title)
        window.SetFont("s10 cFFFFFF", "Segoe UI")
        extra += AddGoldPromptCopy(window, 32, 86 + extra, 588, 67, message)
        AddStyledButton(window, 221, 203 + extra, 185, 34, confirmLabel, (*) => (response.Accepted := true, DestroyScaledMenu(window)))
        AddStyledButton(window, 422, 203 + extra, 185, 34, "Not Now", (*) => DestroyScaledMenu(window))
        GrowGoldNativePrompt(window, extra)
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

ShowUpdatePreview(installedVersion, latestVersion, channel, kind, testHistory := 0)
{
    ; Production always reads actual published history. The optional data
    ; injection is used only by the explicit offline UI test command.
    ; Hotfix-to-hotfix updates open on the dated hotfix history tab.
    synthetic := IsObject(testHistory)
    history := synthetic ? testHistory : ReadPublishedUpdateHistory(installedVersion, latestVersion)
    notes := kind = "hotfix" ? history.Hotfix : history.Release
    response := {Download: false}
    preview := CreateGoldNativePrompt(0, "tes3np — Update Preview", 800, 630)
    closeNotes := 0
    try {
        preview.SetFont("s15 Bold cC5A45C", "Georgia")
        releaseType := channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Stable"
        title := kind = "hotfix" ? "Hotfix available" : "A New " releaseType " Is Available to Download, S'wit!"
        preview.Add("Text", "x30 y20 w740 h38 BackgroundTrans", title)
        preview.SetFont("s10 cEDE1C9", "Segoe UI")
        copy := synthetic ? "TEST DATA ONLY — Simulated changes, not actual published releases."
            : "Review published changes you have missed before deciding to update."
        preview.Add("Text", "x30 y62 w740 h24 BackgroundTrans", copy)
        ; The metadata fits in three columns. A single wrapped Text control
        ; with "Installed: v..." clips the version onto a hidden second line
        ; when its caption exceeds w195/h24 (especially at larger DPI).
        ; Keep each version in its own no-space label within the same row.
        preview.Add("Text", "x30 y94 w77 h24 BackgroundTrans", "Installed:")
        preview.Add("Text", "x109 y94 w125 h24 BackgroundTrans", "v" installedVersion)
        preview.Add("Text", "x238 y94 w61 h24 BackgroundTrans", "Latest:")
        preview.Add("Text", "x301 y94 w138 h24 BackgroundTrans", "v" latestVersion)
        preview.Add("Text", "x446 y94 w324 h24 BackgroundTrans", "Channel: " (channel = "alpha" ? "Alpha" : channel = "beta" ? "Beta" : "Live Stable"))
        tabs := AddUpdateNoteTabs(preview, history.Release, history.Hotfix, kind = "hotfix" ? "hotfix" : "release")
        preview.SetFont("s10 cC5A45C", "Segoe UI")
        preview.Add("Text", "x30 y529 w740 h22 BackgroundTrans",
            synthetic ? "Offline test only — no package can be downloaded or installed."
                : "Download the latest version directly; intermediate installs are not required.")
        preview.Add("Text", "x30 y551 w740 h22 BackgroundTrans", "Preview only — nothing has been downloaded or installed.")
        if synthetic
        {
            ; No download or GitHub action exists in the synthetic UI test.
            AddStyledButton(preview, 32, 582, 230, 34, "Close Test Preview", (*) => DestroyScaledMenu(preview))
            AddStyledButton(preview, 330, 582, 140, 34, "Not Now", (*) => DestroyScaledMenu(preview))
        }
        else
        {
            AddStyledButton(preview, 32, 582, 230, 34, "Continue to Download", (*) => (response.Download := true, DestroyScaledMenu(preview)))
            AddStyledButton(preview, 330, 582, 140, 34, "Not Now", (*) => DestroyScaledMenu(preview))
            AddStyledButton(preview, 590, 582, 178, 34, "GitHub Release", (*) => Run(GetTes3npReleasePage(latestVersion)))
        }
        preview.OnEvent("Close", (*) => DestroyScaledMenu(preview))
        preview.OnEvent("Escape", (*) => DestroyScaledMenu(preview))
        scale := GetUpdatePromptFitScale(preview)
        ScaleOwnedMenuContent(preview, scale)
        closeNotes := AddUpdateNotesViewport(preview, notes, scale, tabs.Switch)
        hwnd := preview.Hwnd
        ShowGoldNativePrompt(preview, scale)
        PaintGoldUpdateDialogButtons(preview)
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
    originalVersion := GetTes3npOriginalVersion(notesVersion)
    releaseNotes := ReadVersionReleaseNotes(originalVersion)
    hotfixNotes := "No hotfixes have been released for this version."
    if ParseTes3npVersion(notesVersion).Hotfix > 0 {
        if mode = "error"
            hotfixNotes := "Published hotfix history is unavailable while offline."
        else
            hotfixNotes := ReadPublishedUpdateHistory(originalVersion, notesVersion).Hotfix
    }
    state := {Retry: false}
    panel := CreateGoldNativePrompt(0, "tes3np — Version Status", 800, 600)
    closeNotes := 0
    try {
        panel.SetFont("s14 Bold cC5A45C", "Georgia")
        panel.Add("Text", "x30 y20 w740 h38 BackgroundTrans", title)
        panel.SetFont("s10 cEDE1C9", "Segoe UI")
        panel.Add("Text", "x30 y65 w740 h55 BackgroundTrans", message)
        tabs := AddUpdateNoteTabs(panel, releaseNotes, hotfixNotes)
        panel.SetFont("s9 cC5A45C", "Segoe UI")
        panel.Add("Text", "x482 y129 w288 h22 BackgroundTrans", "Build: v" notesVersion)
        AddStyledButton(panel, 178, 544, 212, 34, "Check For Updates", (*) => (state.Retry := true, DestroyScaledMenu(panel)))
        AddStyledButton(panel, 410, 544, 212, 34, "Close", (*) => DestroyScaledMenu(panel))
        panel.OnEvent("Close", (*) => DestroyScaledMenu(panel))
        panel.OnEvent("Escape", (*) => DestroyScaledMenu(panel))
        scale := GetUpdatePromptFitScale(panel)
        ScaleOwnedMenuContent(panel, scale)
        closeNotes := AddUpdateNotesViewport(panel, releaseNotes, scale, tabs.Switch)
        hwnd := panel.Hwnd
        ShowGoldNativePrompt(panel, scale)
        PaintGoldUpdateDialogButtons(panel)
        WinWaitClose("ahk_id " hwnd)
    } finally {
        if IsObject(closeNotes)
            try closeNotes()
        CloseGoldNativePrompt(panel)
    }
    if state.Retry
        SetTimer(CheckForUpdates, -100)
}

; Keep both tab buttons inside the same gold panel. The existing measured,
; scrollable notes viewport is reused instead of opening stacked dialogs.
AddUpdateNoteTabs(panel, releaseNotes, hotfixNotes, initialTab := "release")
{
    tabs := {Release: releaseNotes, Hotfix: hotfixNotes, Selected: initialTab, Switch: {}}
    tabs.ReleaseButton := AddStyledButton(panel, 30, 123, 199, 30, "Release Notes", (*) => SelectUpdateNoteTab(tabs, "release"))
    tabs.HotfixButton := AddStyledButton(panel, 242, 123, 199, 30, "Hotfix History", (*) => SelectUpdateNoteTab(tabs, "hotfix"))
    SetUpdateNoteTabLabels(tabs)
    return tabs
}

SelectUpdateNoteTab(tabs, selected)
{
    if tabs.Selected = selected
        return
    tabs.Selected := selected
    SetUpdateNoteTabLabels(tabs)
    if tabs.Switch.HasOwnProp("Update")
        tabs.Switch.Update.Call(selected = "hotfix" ? tabs.Hotfix : tabs.Release)
    ; Tab text and the newly rendered notes must be visible without hover.
    PaintGoldUpdateDialogButtons(tabs.ReleaseButton.Gui)
}

SetUpdateNoteTabLabels(tabs)
{
    tabs.ReleaseButton.Text := tabs.Selected = "release" ? "• Release Notes" : "Release Notes"
    tabs.HotfixButton.Text := tabs.Selected = "hotfix" ? "• Hotfix History" : "Hotfix History"
    for control in [tabs.ReleaseButton, tabs.HotfixButton]
        DllCall("user32\InvalidateRect", "Ptr", control.Hwnd, "Ptr", 0, "Int", 1)
}

; Release dialogs create dynamically painted ClassButton controls while hidden.
; A direct paint after showing them covers the Windows first-exposure race where
; the controls look blank until hovered or the window is minimized/restored.
; Restrict the pass to controls owned by this dialog; no launcher/UI rebuild.
PaintGoldUpdateDialogButtons(panel)
{
    global ButtonFaces
    if !IsObject(panel) || !DllCall("user32\IsWindowVisible", "Ptr", panel.Hwnd, "Int")
        return
    ; ShowGoldNativePrompt already paints the background and ordinary text.
    ; Do not invalidate the entire visible parent here: that repaints the
    ; backdrop over its newly exposed children and causes an opening flash.
    ; Only paint our buffered button faces to repair the missed first WM_PAINT.
    for handle, face in ButtonFaces
        if face.Window = panel.Hwnd && !face.HasOwnProp("IsLabel")
            && DllCall("user32\IsWindowVisible", "Ptr", handle, "Int")
            PaintButtonNow(handle)
}

GetUpdatePromptFitScale(panel)
{
    ; The backdrop uses screen pixels and matches the launcher. Keep the
    ; original dialog layout whenever it fits, with a margin at each edge.
    panel.NativePromptBackdrop.GetClientPos(, , &width, &height)
    return Max(0.5, Min(1.0, (width - 32) / panel.NativePromptWidth,
        (height - 32) / panel.NativePromptHeight))
}
