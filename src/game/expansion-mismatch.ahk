; Detect TES3MP's actual plugin/load-order rejection from NEW log output only.
; The launcher owns this dialog. A Discord ZIP handoff replaces it only after
; ChatHost confirms that the previous embedded WebView2 child was disposed.
global ExpansionMismatchDialog := 0
global ExpansionMismatchSlot := 0
global ExpansionMismatchRefreshPending := false
; TES3MP owns its error window; terminate only the failed PID before prompting.
CaptureTES3MPLogBaseline()
{
    watch := {Paths: [], Files: Map(), Carry: ""}
    config := PatchConfigurationPath()
    SplitPath(config, , &configFolder)
    AddTES3MPLogFolder(watch, configFolder)
    AddTES3MPLogFolder(watch, A_MyDocuments "\My Games\OpenMW")
    onedrive := EnvGet("OneDrive")
    if onedrive != ""
        AddTES3MPLogFolder(watch, onedrive "\Documents\My Games\OpenMW")
    for folder in watch.Paths
    {
        Loop Files, folder "\tes3mp-client*.log", "F"
        {
            path := A_LoopFileFullPath
            try watch.Files[StrLower(path)] := {Size: FileGetSize(path), Modified: FileGetTime(path, "M")}
        }
    }
    return watch
}

AddTES3MPLogFolder(watch, folder)
{
    if folder = "" || !DirExist(folder)
        return
    for existing in watch.Paths
        if StrLower(existing) = StrLower(folder)
            return
    watch.Paths.Push(folder)
}

CheckTES3MPPluginMismatch()
{
    global Client
    if !Client.Enabled || !Client.HasOwnProp("LogWatch") || !IsObject(Client.LogWatch)
        return false
    watch := Client.LogWatch
    for folder in watch.Paths
    {
        Loop Files, folder "\tes3mp-client*.log", "F"
        {
            path := A_LoopFileFullPath
            key := StrLower(path)
            try
            {
                size := FileGetSize(path)
                modified := FileGetTime(path, "M")
                previous := watch.Files.Has(key) ? watch.Files[key] : {Size: 0, Modified: ""}
                if size = previous.Size && modified = previous.Modified
                    continue
                ; Logs can truncate/reopen between launches. An unchanged
                ; length with a newer timestamp is a rewritten file.
                offset := size > previous.Size ? previous.Size : 0
                watch.Files[key] := {Size: size, Modified: modified}
                if size <= 0
                    continue
                file := FileOpen(path, "r", "UTF-8")
                if !IsObject(file)
                    continue
                try
                {
                    file.Pos := Max(0, size - 262144, offset)
                    chunk := file.Read()
                }
                finally file.Close()
                if chunk = ""
                    continue
                text := watch.Carry chunk
                if InStr(text, "Your plugins or their load order don't match the server's", false)
                {
                    HandleTES3MPPluginMismatch()
                    return true
                }
                watch.Carry := StrLen(text) > 384 ? SubStr(text, -384) : text
            }
            catch Error as err
                LogLauncherEvent("GAME | Plugin-mismatch log inspection unavailable: " Type(err) ".")
        }
    }
    return false
}

HandleTES3MPPluginMismatch()
{
    global Client
    pid := Client.PID
    scheduled := Client.HasOwnProp("ScheduledDailyLogin") && Client.ScheduledDailyLogin
    LogLauncherEvent("GAME | PLUGIN MISMATCH | New TES3MP client log reports a server load-order rejection. Stopping failed launch.")
    ; Close only this attempted client (never every running TES3MP game).
    if pid && ProcessExist(pid)
        try ProcessClose(pid)
    if IsObject(Client.Queue)
        Client.Queue := 0
    if scheduled
        CancelScheduledDailyLoginForToday()
    StopClient()
    SetClientStatus("Game blocked: plugins or load order do not match the server.")
    ShowTES3MPExpansionMismatchDialog()
}

ShowTES3MPExpansionMismatchDialog()
{
    global LauncherGui, ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchRefreshPending
    ; A repeated plugin mismatch must not stack duplicate dialogs.
    if IsObject(ExpansionMismatchDialog)
        return
    ExpansionMismatchRefreshPending := false
    ShowLauncherWindow(true)
    dialog := Gui("+Owner" LauncherGui.Hwnd " -MaximizeBox -MinimizeBox", "tes3np")
    dialog.BackColor := "1B140B"
    dialog.SetFont("s17 Bold cC5A45C", "Georgia")
    dialog.Add("Text", "x25 y22 w630 h35 BackgroundTrans", "Plugins Don't Match the Server")
    dialog.SetFont("s11 Norm cEDE1C9", "Segoe UI")
    dialog.Add("Text", "x25 y77 w610 h122 BackgroundTrans",
        "Your installed plugins or load order don't match the server's requirements. "
        . "This may be caused by an outdated Expansion Pack or differences in your game files or load order."
        . Chr(10) Chr(10)
        . "Download the latest Expansion Pack below. When the download finishes, "
        . "click OK to select and install the ZIP file.")
    dialog.SetFont("s10 Bold cC5A45C", "Segoe UI")
    dialog.Add("Text", "x25 y204 w610 h25 BackgroundTrans", "Latest Expansion Pack - Discord")
    ; Native child HWND placeholder for the existing ChatHost's WebView2.
    ; No extra Discord popup and no second browser profile are created.
    downloadSlot := dialog.Add("Text", "x25 y231 w610 h118 +0x100 Background202023",
        "Connecting to the Nerevarine Prophecies Discord channel...")
    ; Always-active launcher-owned retry button. If Discord's child WebView
    ; stops responding during a browser download, this native button still
    ; sends a fresh request using the latest validated link in ChatHost.
    AddStyledButton(dialog, 25, 359, 215, 31, "Download ZIP / Retry",
        (*) => SendLauncherChatCommand(8, downloadSlot.Hwnd))
    dialog.SetFont("s9 Norm cD8C38C", "Segoe UI")
    dialog.Add("Link", "x25 y397 w610 h20",
        '<a href="https://discord.com/channels/509601787901116437/1555049936800718928">Open the download channel in Discord if the embed is unavailable</a>')
    AddStyledButton(dialog, 340, 425, 140, 38, "OK",
        (*) => CloseTES3MPExpansionMismatchDialog(dialog, downloadSlot.Hwnd, true))
    AddStyledButton(dialog, 490, 425, 140, 38, "Cancel",
        (*) => CloseTES3MPExpansionMismatchDialog(dialog, downloadSlot.Hwnd))
    dialog.OnEvent("Close", (*) => CloseTES3MPExpansionMismatchDialog(dialog, downloadSlot.Hwnd))
    dialog.OnEvent("Escape", (*) => CloseTES3MPExpansionMismatchDialog(dialog, downloadSlot.Hwnd))
    dialog.Show("w660 h482")
    ExpansionMismatchDialog := dialog
    ExpansionMismatchSlot := downloadSlot.Hwnd
    ; WM_APP command 6: attach one child browser to this exact HWND.
    SendLauncherChatCommand(6, downloadSlot.Hwnd)
}

CloseTES3MPExpansionMismatchDialog(dialog, slotHwnd, import := false)
{
    global ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchRefreshPending
    if IsObject(ExpansionMismatchDialog) && ExpansionMismatchDialog != dialog
        return
    ExpansionMismatchDialog := 0
    ExpansionMismatchSlot := 0
    ExpansionMismatchRefreshPending := false
    ; Existing manual OK/Cancel behavior stays unchanged. ChatHost disposes
    ; its own child on command 7; its later acknowledgment is ignored here.
    SendLauncherChatCommand(7, slotHwnd)
    try dialog.Destroy()
    if import
        UploadExpansionFromFile()
}

TES3MPExpansionDownloadHandedOff(slotHwnd, *)
{
    global ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchRefreshPending
    ; WM_APP + 0x335 is sent only after Windows accepts a ZIP handoff.
    ; Match the exact current dialog's placeholder, not a previous session.
    if (!IsObject(ExpansionMismatchDialog) || slotHwnd != ExpansionMismatchSlot || ExpansionMismatchRefreshPending)
        return
    ExpansionMismatchRefreshPending := true
    LogLauncherEvent("EXPANSION | ZIP sent to browser; refreshing mismatch prompt.")
    ; Hide the now-stale Discord child before asking ChatHost to dispose it.
    ; No window is destroyed until ChatHost acknowledges command 7.
    try ExpansionMismatchDialog.Hide()
    SendLauncherChatCommand(7, slotHwnd)
    ; If the helper never acknowledges, restore the old dialog and keep its
    ; native OK/Cancel + external channel fallback accessible.
    SetTimer((*) => TES3MPExpansionRefreshTimedOut(slotHwnd), -2500)
}

TES3MPExpansionBrowserClosed(slotHwnd, *)
{
    global ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchRefreshPending
    ; WM_APP + 0x336 means ChatHost disposed this exact embedded browser.
    if (!ExpansionMismatchRefreshPending || !IsObject(ExpansionMismatchDialog) || slotHwnd != ExpansionMismatchSlot)
        return
    dialog := ExpansionMismatchDialog
    ExpansionMismatchDialog := 0
    ExpansionMismatchSlot := 0
    ExpansionMismatchRefreshPending := false
    try dialog.Destroy()
    ; Defer new GUI creation until after this window-message handler exits.
    SetTimer(ShowTES3MPExpansionMismatchDialog, -100)
}

TES3MPExpansionRefreshTimedOut(slotHwnd)
{
    global ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchRefreshPending
    ; A timer from an earlier refresh cannot interrupt a newly reopened popup.
    if (!ExpansionMismatchRefreshPending || slotHwnd != ExpansionMismatchSlot)
        return
    ExpansionMismatchRefreshPending := false
    if IsObject(ExpansionMismatchDialog)
        try ExpansionMismatchDialog.Show()
    LogLauncherEvent("EXPANSION | Discord child close timed out; prompt restored without auto-reopen.")
}
