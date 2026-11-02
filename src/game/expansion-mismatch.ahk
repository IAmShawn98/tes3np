; Detect TES3MP's actual plugin/load-order rejection from NEW log output only.
; Keep one launcher-owned dialog for any number of downloads. The transient
; signed ZIP URL is delivered from ChatHost via bounded WM_COPYDATA, stored
; only in memory, and never requires WebView2 to handle native retries.
global ExpansionMismatchDialog := 0
global ExpansionMismatchSlot := 0
global ExpansionMismatchZipUrl := ""
global ExpansionMismatchFileButton := 0
global ExpansionMismatchDownloadSlot := 0
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
    global LauncherGui, ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchZipUrl, ExpansionMismatchFileButton, ExpansionMismatchDownloadSlot
    ; No close/reopen cycle while a browser is downloading. Duplicate
    ; server mismatches cannot stack additional native WebView2 children.
    if IsObject(ExpansionMismatchDialog)
        return
    ExpansionMismatchZipUrl := ""
    ShowLauncherWindow(true)
    dialog := Gui("+Owner" LauncherGui.Hwnd " -MaximizeBox -MinimizeBox", "tes3np")
    dialog.BackColor := "1B140B"
    dialog.SetFont("s16 Bold cC5A45C", "Georgia")
    dialog.Add("Text", "x25 y19 w610 h43 BackgroundTrans", "Your Plugins Don't Match the Servers")
    dialog.SetFont("s10 Norm cEDE1C9", "Segoe UI")
    dialog.Add("Text", "x25 y74 w610 h74 BackgroundTrans",
        "The likely cause is due to an update for the Nerevarine Prophecies content Expansion Pack. "
        . "Please ensure you have the latest and greatest enabled, then retry logging in again.")
    dialog.Add("Text", "x25 y159 w610 h88 BackgroundTrans",
        "Download the latest Expansion Pack from Discord by clicking the button below, "
        . "waiting for it to complete, then clicking the OK button to locate and install "
        . "the new expansion pack.")
    dialog.Add("Text", "x25 y256 w610 h66 BackgroundTrans",
        "If the latest expansion pack doesn't resolve your issue, please click "
        . "'Copy Diagnostic Info' and send it to bug reports on Discord for further examination.")
    dialog.SetFont("s10 Bold cC5A45C", "Segoe UI")
    dialog.Add("Text", "x25 y324 w610 h24 BackgroundTrans", "Latest Expansion Pack - Discord")
    ; Native child HWND placeholder for the existing ChatHost's WebView2.
    ; No extra Discord popup and no second browser profile are created.
    downloadSlot := dialog.Add("Text", "x25 y349 w610 h113 +0x100 Background202023",
        "Connecting to the Nerevarine Prophecies Discord channel...")
    ExpansionMismatchDownloadSlot := downloadSlot
    ; This status is created before the download actions so both callbacks
    ; always reference a fully initialized control.
    nativeStatus := dialog.Add("Text", "x25 y518 w610 h19 cD8C38C BackgroundTrans", "")
    ; The native download button overlays the original Discord placeholder.
    ; Once a ZIP is found we must hide the placeholder itself, not only the
    ; foreign WebView child, or its native HWND can intercept mouse clicks.
    ExpansionMismatchFileButton := AddStyledButton(dialog, 37, 368, 586, 61,
        "Download Expansion Pack ZIP",
        (*) => TES3MPExpansionRequestDownload(downloadSlot.Hwnd, nativeStatus, "main-button"))
    ExpansionMismatchFileButton.Visible := false
    AddStyledButton(dialog, 25, 475, 210, 33, "Download ZIP / Retry",
        (*) => TES3MPExpansionRequestDownload(downloadSlot.Hwnd, nativeStatus, "retry-button"))
    AddStyledButton(dialog, 245, 475, 210, 33, "Copy Diagnostic Info",
        (*) => TES3MPCopyMismatchDiagnostics(nativeStatus))
    dialog.SetFont("s9 Norm cD8C38C", "Segoe UI")
    dialog.Add("Link", "x25 y543 w610 h20",
        '<a href="https://discord.com/channels/509601787901116437/1555049936800718928">Open the download channel in Discord if the embed is unavailable</a>')
    AddStyledButton(dialog, 340, 574, 140, 38, "OK",
        (*) => CloseTES3MPExpansionMismatchDialog(dialog, downloadSlot.Hwnd, true))
    AddStyledButton(dialog, 490, 574, 140, 38, "Cancel",
        (*) => CloseTES3MPExpansionMismatchDialog(dialog, downloadSlot.Hwnd))
    dialog.OnEvent("Close", (*) => CloseTES3MPExpansionMismatchDialog(dialog, downloadSlot.Hwnd))
    dialog.OnEvent("Escape", (*) => CloseTES3MPExpansionMismatchDialog(dialog, downloadSlot.Hwnd))
    dialog.Show("w660 h627")
    ExpansionMismatchDialog := dialog
    ExpansionMismatchSlot := downloadSlot.Hwnd
    ; WM_APP command 6: attach one child browser to this exact HWND.
    SendLauncherChatCommand(6, downloadSlot.Hwnd)
}

CloseTES3MPExpansionMismatchDialog(dialog, slotHwnd, import := false)
{
    global ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchZipUrl, ExpansionMismatchFileButton, ExpansionMismatchDownloadSlot
    if IsObject(ExpansionMismatchDialog) && ExpansionMismatchDialog != dialog
        return
    ExpansionMismatchDialog := 0
    ExpansionMismatchSlot := 0
    ExpansionMismatchZipUrl := ""
    ExpansionMismatchFileButton := 0
    ExpansionMismatchDownloadSlot := 0
    ; Normal OK/Cancel closes just this dialog. We never recycle the
    ; embedded Discord controller during an ordinary ZIP download.
    SendLauncherChatCommand(7, slotHwnd)
    try dialog.Destroy()
    if import
        UploadExpansionFromFile()
}

TES3MPExpansionZipAvailable(wParam, lParam, msg, hwnd)
{
    global LauncherGui, EmbeddedChatPid, ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchZipUrl, ExpansionMismatchFileButton
    ; WM_COPYDATA is synchronous; copy the data before returning.
    ; Only accept our current ChatHost's authenticated HTTPS attachment.
    if !IsObject(ExpansionMismatchDialog) || !lParam || hwnd != LauncherGui.Hwnd
        return 0
    ; Verify the sender before dereferencing an external window message.
    try
    {
        oldHidden := A_DetectHiddenWindows
        DetectHiddenWindows(true)
        try
        {
            validSender := wParam && EmbeddedChatPid
                && (WinGetPID("ahk_id " wParam) = EmbeddedChatPid)
                && (StrLower(WinGetProcessName("ahk_id " wParam)) = "tes3np.chathost.exe")
        }
        finally
            DetectHiddenWindows(oldHidden)
        if !validSender
            return 0
    }
    catch
        return 0
    if NumGet(lParam, 0, "Ptr") != 0x8335
        return 0
    cbData := NumGet(lParam, A_PtrSize, "UInt")
    if cbData < 36 || cbData > 8192 || Mod(cbData, 2)
        return 0
    textPtr := NumGet(lParam, A_PtrSize = 8 ? 16 : 8, "Ptr")
    if !textPtr
        return 0
    payload := StrGet(textPtr, cbData // 2 - 1, "UTF-16")
    separator := InStr(payload, "|")
    if !separator
        return 0
    slotText := SubStr(payload, 1, separator-1)
    if !RegExMatch(slotText, "^\d+$") || (slotText + 0) != ExpansionMismatchSlot
        return 0
    url := SubStr(payload, separator+1)
    if !RegExMatch(url, "i)^https://(?:cdn\.discordapp\.com|media\.discordapp\.net)/attachments/[^?#]+\.zip(?:[?#]|$)")
        return 0
    ExpansionMismatchZipUrl := url
    if IsObject(ExpansionMismatchFileButton)
    {
        ; The filename comes from the validated official attachment path.
        ; Query-string tokens stay in memory, never in button text or logs.
        if RegExMatch(url, "i)/([^/?#]+\.zip)(?:[?#]|$)", &filenameMatch)
        {
            name := StrReplace(filenameMatch[1], "%20", " ")
            ExpansionMismatchFileButton.Text := "Download " SubStr(name, 1, 68)
        }
    }
    ; Do not manipulate a cross-process child window during synchronous
    ; WM_COPYDATA. Defer hiding the placeholder and raising the download
    ; control until the original message handler has returned.
    slot := ExpansionMismatchSlot
    SetTimer((*) => TES3MPExpansionActivateDownloadButton(slot), -30)
    LogLauncherEvent("EXPANSION | Latest ZIP ready; activating native download button.")
    return 1
}

TES3MPExpansionActivateDownloadButton(slotHwnd)
{
    global ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchDownloadSlot, ExpansionMismatchFileButton
    if (!IsObject(ExpansionMismatchDialog) || slotHwnd != ExpansionMismatchSlot
        || !IsObject(ExpansionMismatchFileButton) || !IsObject(ExpansionMismatchDownloadSlot))
        return
    ; Keep the slot HWND alive for link refresh and normal dialog cleanup.
    ; Only hide it so it cannot sit above the clickable AHK-owned button.
    SendLauncherChatCommand(9, slotHwnd)
    try ExpansionMismatchDownloadSlot.Visible := false
    try
    {
        ExpansionMismatchFileButton.Visible := true
        ; HWND_TOP + SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE.
        DllCall("SetWindowPos", "Ptr", ExpansionMismatchFileButton.Hwnd,
            "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        DllCall("RedrawWindow", "Ptr", ExpansionMismatchFileButton.Hwnd,
            "Ptr", 0, "Ptr", 0, "UInt", 0x0121)
        LogLauncherEvent("EXPANSION | Main ZIP download button brought above browser placeholder.")
    }
    catch Error as err
        LogLauncherEvent("EXPANSION | Could not activate main ZIP button (" Type(err) ").")
}

TES3MPExpansionRequestDownload(slotHwnd, statusControl, origin := "download")
{
    global ExpansionMismatchDialog, ExpansionMismatchSlot, ExpansionMismatchZipUrl
    if !IsObject(ExpansionMismatchDialog) || slotHwnd != ExpansionMismatchSlot
        return
    url := ExpansionMismatchZipUrl
    if url = ""
    {
        LogLauncherEvent("EXPANSION | Download requested before Discord ZIP discovery.")
        return
    }
    ; Re-validate every click. A cancelled browser transfer never disables
    ; this button or creates/disposes any browser controller.
    if !RegExMatch(url, "i)^https://(?:cdn\.discordapp\.com|media\.discordapp\.net)/attachments/[^?#]+\.zip(?:[?#]|$)")
        || RegExMatch(url, '[\s"<>]') || StrLen(url) > 4000
        return
    try
    {
        LogLauncherEvent("EXPANSION | ZIP click received from " origin ".")
        statusControl.Text := ""
        ; Launch the Windows URL handler in a disposable helper process.
        ; Opening a URL directly uses ShellExecute on AHK's GUI thread and can block
        ; the entire launcher when the browser is busy with a large download.
        ; Run returns when rundll32 starts; it never waits for the download.
        LogLauncherEvent("EXPANSION | Launching external ZIP URL helper.")
        Run('rundll32.exe url.dll,FileProtocolHandler "' url '"', , "Hide")
        LogLauncherEvent("EXPANSION | ZIP download handed off asynchronously.")
    }
    catch Error as err
        LogLauncherEvent("EXPANSION | Native browser handoff failed (" Type(err) ").")
}

; Privacy-first diagnostic report: ONLY fixed labels, counts and YES/NO values.
; Never put raw client logs, mod names, paths, addresses, tokens, usernames,
; character names, config lines or Discord messages on the clipboard.
TES3MPCopyMismatchDiagnostics(statusControl)
{
    try
    {
        A_Clipboard := TES3MPBuildSafeMismatchDiagnostics()
        if !ClipWait(1)
        {
            statusControl.Text := "Could not copy diagnostic info."
            return
        }
        statusControl.Text := "Diagnostic info copied. Paste it into Discord bug reports."
        LogLauncherEvent("EXPANSION | Privacy-safe structured mismatch report copied.")
    }
    catch Error as err
    {
        statusControl.Text := "Could not copy diagnostic info."
        LogLauncherEvent("EXPANSION | Diagnostic report failed (" Type(err) ").")
    }
}

TES3MPBuildSafeMismatchDiagnostics()
{
    global AppConfig, DataFile
    configFound := "No"
    configChecked := false
    contentCount := 0
    expansionCount := 0
    expansionIndex := 0
    morrowindMaster := false
    tribunalMaster := false
    bloodmoonMaster := false
    config := PatchConfigurationPath()
    if FileExist(config)
    {
        configFound := "Yes"
        try
        {
            ; Do not read or copy an unbounded configuration file.
            if FileGetSize(config) <= 1048576
            {
                for line in StrSplit(FileRead(config, "UTF-8"), "`n", "`r")
                {
                    if !RegExMatch(Trim(line), "i)^content\s*=\s*(.*)$", &entry)
                        continue
                    contentCount += 1
                    ; Names are used ONLY for comparisons with the four
                    ; known game/plugin filenames; none enter the report.
                    plugin := StrLower(Trim(StrReplace(Trim(entry[1]), '"', "")))
                    if plugin = "np expansion pack.esp"
                    {
                        expansionCount += 1
                        expansionIndex := contentCount
                    }
                    else if plugin = "morrowind.esm"
                        morrowindMaster := true
                    else if plugin = "tribunal.esm"
                        tribunalMaster := true
                    else if plugin = "bloodmoon.esm"
                        bloodmoonMaster := true
                }
                configChecked := true
            }
        }
    }
    enabled := configChecked ? (expansionCount ? "Yes" : "No") : "Unknown"
    position := configChecked && expansionCount = 1
        ? expansionIndex " of " contentCount : "Unknown"
    last := configChecked && expansionCount = 1
        ? (expansionIndex = contentCount ? "Yes" : "No") : "Unknown"
    duplicate := configChecked ? (expansionCount > 1 ? "Yes" : "No") : "Unknown"

    ; File existence is checked without exposing the configured install path.
    ; No directory crawl, file hashing or package contents are copied.
    installed := "Not checked"
    try
    {
        root := IniRead(DataFile, "Patch", "MorrowindFolder", "")
        if root != "" && DirExist(root "\Data Files")
            installed := FileExist(root "\Data Files\NP Expansion Pack.esp") ? "Yes" : "No"
    }

    markers := TES3MPReadSafeMismatchLogMarkers()
    return "TES3NP - SAFE PLUGIN MISMATCH DIAGNOSTICS`r`n"
        . "Generated (UTC): " FormatTime(A_NowUTC, "yyyy-MM-dd HH:mm:ss") "`r`n"
        . "Launcher version: " AppConfig.Version "`r`n"
        . "Reported issue: Server rejected plugin/load-order configuration`r`n"
        . "`r`n[Configuration]`r`n"
        . "Active OpenMW configuration found: " configFound "`r`n"
        . "Configuration safely inspected: " (configChecked ? "Yes" : "No") "`r`n"
        . "Enabled content entries: " (configChecked ? contentCount : "Unknown") "`r`n"
        . "Expansion Pack enabled: " enabled "`r`n"
        . "Expansion Pack content position: " position "`r`n"
        . "Expansion Pack last in load order: " last "`r`n"
        . "Duplicate Expansion Pack entries: " duplicate "`r`n"
        . "Expansion Pack ESP installed at configured game location: " installed "`r`n"
        . "Morrowind master enabled: " TES3MPSafeDiagnosticYN(morrowindMaster, configChecked) "`r`n"
        . "Tribunal master enabled: " TES3MPSafeDiagnosticYN(tribunalMaster, configChecked) "`r`n"
        . "Bloodmoon master enabled: " TES3MPSafeDiagnosticYN(bloodmoonMaster, configChecked) "`r`n"
        . "`r`n[Latest client log: fixed error indicators only]`r`n"
        . "Recent client log inspected: " TES3MPSafeDiagnosticYN(markers.Available, true) "`r`n"
        . "Server plugin/load-order rejection present: " TES3MPSafeDiagnosticYN(markers.Rejected, markers.Available) "`r`n"
        . "Missing plugin/master indicator present: " TES3MPSafeDiagnosticYN(markers.Missing, markers.Available) "`r`n"
        . "Load-order indicator present: " TES3MPSafeDiagnosticYN(markers.Order, markers.Available) "`r`n"
        . "`r`nPrivacy: Only fixed labels, version, counts and status flags are included.`r`n"
        . "No raw log lines, mod names, paths, account details or tokens are copied."
}

TES3MPSafeDiagnosticYN(value, known)
{
    return !known ? "Unknown" : (value ? "Yes" : "No")
}

TES3MPReadSafeMismatchLogMarkers()
{
    result := {Available: false, Rejected: false, Missing: false, Order: false}
    newestPath := ""
    newestTime := ""
    ; Use the same bounded known log folders as the existing mismatch watcher.
    ; Only the latest matching log is read, and never returned verbatim.
    watch := CaptureTES3MPLogBaseline()
    for folder in watch.Paths
    {
        if !DirExist(folder)
            continue
        Loop Files, folder "\tes3mp-client*.log", "F"
        {
            if A_LoopFileTimeModified > newestTime
            {
                newestTime := A_LoopFileTimeModified
                newestPath := A_LoopFileFullPath
            }
        }
    }
    if newestPath = ""
        return result
    try
    {
        file := FileOpen(newestPath, "r", "UTF-8")
        if !IsObject(file)
            return result
        try
        {
            file.Pos := Max(0, file.Length - 65536)
            raw := StrLower(file.Read())
        }
        finally file.Close()
        result.Available := true
        result.Rejected := InStr(raw, "your plugins or their load order don't match the server's") > 0
        result.Missing := InStr(raw, "missing plugin") > 0
            || InStr(raw, "missing master") > 0
            || InStr(raw, "missing dependency") > 0
        result.Order := InStr(raw, "load order") > 0
        ; raw is deliberately never placed in the clipboard or any log.
    }
    return result
}
