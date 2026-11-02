; Detect TES3MP's actual plugin/load-order rejection from NEW log output only.
; Keep one launcher-owned dialog for any number of downloads. The transient
; signed ZIP URL is delivered from ChatHost via bounded WM_COPYDATA, stored
; only in memory, and never requires WebView2 to handle native retries.
global ExpansionMismatchDialog := 0
global ExpansionMismatchSlot := 0
global ExpansionMismatchZipUrl := ""
global ExpansionMismatchFileButton := 0
global ExpansionMismatchDownloadSlot := 0
; Keep only fixed error classifications from the current failed login;
; never retain the original client log text, paths, or player content.
global TES3MPLastMismatchEvidence := 0
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
    global Client, TES3MPLastMismatchEvidence
    if !Client.Enabled || !Client.HasOwnProp("LogWatch") || !IsObject(Client.LogWatch)
        return false
    watch := Client.LogWatch
    pending := Client.HasOwnProp("MismatchPending") && Client.MismatchPending
    for folder in watch.Paths
    {
        Loop Files, folder "\tes3mp-client*.log", "F"
        {
            path := A_LoopFileFullPath
            key := StrLower(path)
            ; Once a rejection is found, read only its own log. Never mix
            ; details from another game client or an unrelated old log.
            if pending && key != Client.MismatchLogKey
                continue
            try
            {
                size := FileGetSize(path)
                modified := FileGetTime(path, "M")
                previous := watch.Files.Has(key) ? watch.Files[key] : {Size: 0, Modified: ""}
                if size = previous.Size && modified = previous.Modified
                    continue
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
                if pending
                {
                    ; The comparison can be logged after the first rejection
                    ; sentence. Retain categories and integer slots only.
                    TES3MPAccumulateMismatchDetailText(TES3MPLastMismatchEvidence, chunk)
                    continue
                }
                currentText := watch.Carry chunk
                if InStr(currentText, "Your plugins or their load order don't match the server's", false)
                {
                    TES3MPLastMismatchEvidence := TES3MPAnalyzeMismatchLogText(currentText)
                    Client.MismatchPending := true
                    Client.MismatchLogKey := key
                    ; Two ordinary watchdog ticks allow following detail
                    ; lines to flush. No new timer or background process.
                    Client.MismatchCaptureUntil := A_TickCount + 1500
                    LogLauncherEvent("GAME | PLUGIN MISMATCH | Rejection captured; collecting bounded comparison categories.")
                    return true
                }
                watch.Carry := StrLen(currentText) > 384 ? SubStr(currentText, -384) : currentText
            }
            catch Error as err
                LogLauncherEvent("GAME | Plugin-mismatch log inspection unavailable: " Type(err) ".")
        }
    }
    if pending
    {
        if A_TickCount >= Client.MismatchCaptureUntil
            HandleTES3MPPluginMismatch()
        ; Do not advance login stages once rejection was detected.
        return true
    }
    return false
}


HandleTES3MPPluginMismatch()
{
    global Client
    pid := Client.PID
    LogLauncherEvent("GAME | PLUGIN MISMATCH | New TES3MP client log reports a server load-order rejection. Stopping failed launch.")
    ; Close only this attempted client (never every running TES3MP game).
    if pid && ProcessExist(pid)
        try ProcessClose(pid)
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

; Privacy-first reporting: parse only fixed categories and counts. Do not
; copy raw config entries, client logs, mod names, paths, chat or auth tokens.
TES3MPCopyMismatchDiagnostics(statusControl)
{
    limited := false
    try
        report := TES3MPBuildMismatchDiagnostics()
    catch Error as err
    {
        limited := true
        LogLauncherEvent("EXPANSION | Diagnostic collection error ("
            Type(err) ", line " err.Line ").")
        report := TES3MPBuildMinimumMismatchDiagnostics()
    }
    TES3MPTryCopyMismatchReport(report, statusControl, limited)
}

TES3MPBuildMinimumMismatchDiagnostics()
{
    global AppConfig
    return "TES3NP - Plugin Mismatch Diagnostics`r`n"
        . "Launcher version: " AppConfig.Version "`r`n"
        . "Reported issue: Server rejected the client plugin/load order`r`n"
        . "Configuration check: Unable to complete`r`n"
        . "Client log check: Unable to complete`r`n"
        . "Cause: Not determined (diagnostic collection failed)"
}

TES3MPTryCopyMismatchReport(report, statusControl, limited := false, attempt := 1)
{
    global ExpansionMismatchDialog
    if !IsObject(ExpansionMismatchDialog)
        return
    try
        A_Clipboard := report
    catch Error as err
    {
        if attempt < 3
        {
            SetTimer((*) => TES3MPTryCopyMismatchReport(
                report, statusControl, limited, attempt + 1), -200)
            return
        }
        try statusControl.Text := "Could not access clipboard. Click Copy Diagnostic Info again."
        LogLauncherEvent("EXPANSION | Clipboard unavailable ("
            Type(err) ", line " err.Line ").")
        return
    }
    try statusControl.Text := "Diagnostic Info Copied!"
    LogLauncherEvent("EXPANSION | Mismatch diagnostics copied ("
        (limited ? "collection failed" : "collected") ").")
}

TES3MPNewMismatchConfigResult(status := "Not found")
{
    return {Status: status, Total: 0, ExpansionCount: 0, ExpansionIndex: 0,
        OtherCount: 0, OtherDuplicates: 0, OtherAfterExpansion: 0,
        Morrowind: false, Tribunal: false, Bloodmoon: false}
}

; Pure parser: accepts fixture text for deterministic tests. Never returns
; arbitrary plugin names; they are used only for in-memory comparisons.
TES3MPAnalyzeMismatchConfig(configText)
{
    info := TES3MPNewMismatchConfigResult("Read")
    seenOther := Map()
    for line in StrSplit(configText, "`n", "`r")
    {
        if !RegExMatch(Trim(line), "i)^content\s*=\s*(.*?)\s*$", &entry)
            continue
        plugin := StrLower(Trim(entry[1], ' "'))
        if plugin = ""
            continue
        info.Total += 1
        if plugin = "np expansion pack.esp"
        {
            info.ExpansionCount += 1
            info.ExpansionIndex := info.Total
        }
        else if plugin = "morrowind.esm"
            info.Morrowind := true
        else if plugin = "tribunal.esm"
            info.Tribunal := true
        else if plugin = "bloodmoon.esm"
            info.Bloodmoon := true
        else
        {
            info.OtherCount += 1
            if seenOther.Has(plugin)
                info.OtherDuplicates += 1
            else
                seenOther[plugin] := true
        }
    }
    if info.ExpansionCount = 1
        info.OtherAfterExpansion := info.Total - info.ExpansionIndex
    return info
}

TES3MPReadMismatchConfigInfo()
{
    config := PatchConfigurationPath()
    if !FileExist(config)
        return TES3MPNewMismatchConfigResult("Not found")
    try
    {
        if FileGetSize(config) > 1048576
            return TES3MPNewMismatchConfigResult("Too large to inspect")
        return TES3MPAnalyzeMismatchConfig(FileRead(config, "UTF-8"))
    }
    catch Error as err
    {
        LogLauncherEvent("EXPANSION | Diagnostic config read unavailable ("
            Type(err) ", line " err.Line ").")
        return TES3MPNewMismatchConfigResult("Read error")
    }
}

TES3MPNewMismatchLogResult(status := "Not found")
{
    return {Status: status, Source: "Latest client log", Rejected: false,
        MissingExpansion: false, MissingOther: false, MissingBaseMaster: false,
        MissingUnspecified: false, Order: false,
        ComparisonSlots: 0, FirstSlot: -1, ChecksumCount: 0,
        NameMismatchCount: 0, ExtraClientCount: 0, ExtraServerCount: 0,
        SlotFlags: Map()}
}

; Look at ONLY the last server-rejection context (nearby lines). Arbitrary
; names are neither returned nor written to logs/clipboard.
TES3MPAnalyzeMismatchLogText(raw)
{
    result := TES3MPNewMismatchLogResult("Read")
    lines := StrSplit(StrLower(raw), "`n", "`r")
    lastRejection := 0
    for index, line in lines
        if InStr(line, "your plugins or their load order don't match the server's")
            lastRejection := index
    if !lastRejection
        return result
    result.Rejected := true
    first := Max(1, lastRejection - 18)
    last := Min(lines.Length, lastRejection + 512)
    Loop last - first + 1
    {
        currentIndex := first + A_Index - 1
        if currentIndex = lastRejection
            continue
        TES3MPAccumulateMismatchLine(result, lines[currentIndex])
    }
    return result
}

TES3MPAccumulateMismatchDetailText(result, raw)
{
    for line in StrSplit(StrLower(raw), "`n", "`r")
        TES3MPAccumulateMismatchLine(result, line)
    return result
}

TES3MPAccumulateMismatchLine(result, line)
{
    ; The generic rejection mentions load order but does not independently
    ; prove a load-order problem.
    if InStr(line, "your plugins or their load order don't match the server's")
        return
    missing := InStr(line, "missing plugin") || InStr(line, "missing master")
        || InStr(line, "missing dependency") || InStr(line, "could not find plugin")
        || InStr(line, "failed to load plugin")
    if missing
    {
        if InStr(line, "np expansion pack.esp")
            result.MissingExpansion := true
        else if InStr(line, "morrowind.esm") || InStr(line, "tribunal.esm")
            || InStr(line, "bloodmoon.esm")
            result.MissingBaseMaster := true
        else if RegExMatch(line, "i)\.(esp|esm|omwaddon)\b")
            result.MissingOther := true
        else
            result.MissingUnspecified := true
    }
    if InStr(line, "load order") || InStr(line, "plugin order")
        result.Order := true

    ; TES3MP comparison examples:
    ; 0: checksum 0x... doesn't match 0x...
    ; 1: Some.esp doesn't match Other.esm, checksum ...
    ; 3: Some.esp is past the number of plugins used by the server
    ; Only fixed categories and zero-based slot numbers are retained.
    if !RegExMatch(Trim(line), "i)(?:^|:\s+)(\d{1,4}):\s*(.+)$", &match)
        return
    slot := Integer(match[1])
    detail := match[2]
    bits := 0
    if InStr(detail, "checksum") && InStr(detail, "doesn't match")
        bits |= 1
    if RegExMatch(detail, "i)\.(?:esm|esp|omwaddon)\b.*doesn't match.*\.(?:esm|esp|omwaddon)\b")
        bits |= 2
    if InStr(detail, "past the number of plugins used by the server")
        bits |= 4
    if InStr(detail, "past the number of plugins used by the client")
        bits |= 8
    if !bits
        return
    oldBits := result.SlotFlags.Has(slot) ? result.SlotFlags[slot] : 0
    newBits := bits & ~oldBits
    if !newBits
        return
    result.SlotFlags[slot] := oldBits | newBits
    if !oldBits
    {
        result.ComparisonSlots += 1
        result.FirstSlot := result.FirstSlot < 0 ? slot : Min(result.FirstSlot, slot)
    }
    if newBits & 1
        result.ChecksumCount += 1
    if newBits & 2
        result.NameMismatchCount += 1
    if newBits & 4
        result.ExtraClientCount += 1
    if newBits & 8
        result.ExtraServerCount += 1
}


TES3MPSelectMismatchLogEvidence(captured)
{
    ; The watcher already found a real server rejection in NEW log output.
    ; Prefer its bounded classifications rather than reopening a possibly
    ; locked log after the failed client is terminated.
    if IsObject(captured) && captured.Rejected && captured.Status = "Read"
    {
        captured.Source := "Captured during failed login"
        return captured
    }
    return TES3MPReadSafeMismatchLogMarkers()
}

TES3MPReadSafeMismatchLogMarkers()
{
    result := TES3MPNewMismatchLogResult()
    newestPath := ""
    newestTime := ""
    ; Reuse the existing known folders, with no drive-wide search.
    watch := {Paths: []}
    SplitPath(PatchConfigurationPath(), , &configFolder)
    AddTES3MPLogFolder(watch, configFolder)
    AddTES3MPLogFolder(watch, A_MyDocuments "\My Games\OpenMW")
    onedrive := EnvGet("OneDrive")
    if onedrive != ""
        AddTES3MPLogFolder(watch, onedrive "\Documents\My Games\OpenMW")
    for folder in watch.Paths
    {
        if !DirExist(folder)
            continue
        try
        {
            Loop Files, folder "\tes3mp-client*.log", "F"
            {
                if A_LoopFileTimeModified > newestTime
                {
                    newestTime := A_LoopFileTimeModified
                    newestPath := A_LoopFileFullPath
                }
            }
        }
        catch Error as err
        {
            LogLauncherEvent("EXPANSION | Diagnostic log enumeration failed ("
                Type(err) ", line " err.Line ").")
            result.Status := "Read error"
        }
    }
    if newestPath = ""
        return result
    try
    {
        file := FileOpen(newestPath, "r", "UTF-8")
        if !IsObject(file)
            return TES3MPNewMismatchLogResult("Read error")
        try
        {
            file.Pos := Max(0, file.Length - 65536)
            recent := file.Read()
        }
        finally file.Close()
        return TES3MPAnalyzeMismatchLogText(recent)
    }
    catch Error as err
    {
        LogLauncherEvent("EXPANSION | Diagnostic log read failed ("
            Type(err) ", line " err.Line ").")
        return TES3MPNewMismatchLogResult("Read error")
    }
}

TES3MPMismatchYesNo(flag, available := true)
{
    return !available ? "Unknown" : (flag ? "Yes" : "No")
}

; This is an evidence summary, not a claim about the current server manifest
; or the version inside a player's downloaded ZIP.
TES3MPMismatchAssessment(info, markers, installed)
{
    configOK := info.Status = "Read"
    expansionEvidence := (configOK && (info.ExpansionCount != 1
        || info.ExpansionIndex != info.Total)) || markers.MissingExpansion
        || installed = "No"
    otherEvidence := (configOK && (info.OtherDuplicates > 0
        || !info.Morrowind || !info.Tribunal || !info.Bloodmoon))
        || markers.MissingOther || markers.MissingBaseMaster
    if expansionEvidence && otherEvidence
        return "Both Expansion Pack and other plugin issues indicated"
    if expansionEvidence
        return "Expansion Pack configuration needs attention"
    if otherEvidence
        return "Other plugin or base-game dependency needs attention"
    if markers.Status = "Read" && markers.Rejected && markers.ComparisonSlots > 0
    {
        categories := (markers.ChecksumCount > 0) + (markers.NameMismatchCount > 0)
            + (markers.ExtraClientCount > 0) + (markers.ExtraServerCount > 0)
        if categories > 1
            return "TES3MP reported multiple plugin comparison discrepancies"
        if markers.ChecksumCount > 0
            return "TES3MP reported plugin checksum differences"
        if markers.NameMismatchCount > 0
            return "TES3MP reported different plugins at matching load-order slots"
        if markers.ExtraClientCount > 0
            return "Client has plugin slots beyond the server list"
        if markers.ExtraServerCount > 0
            return "Server has plugin slots beyond the client list"
    }
    return "Cause not determined from available checks"
}

TES3MPMismatchSlotSummary(markers)
{
    if markers.ComparisonSlots = 0
        return "None captured"
    details := ""
    shown := 0
    ; Only numeric plugin indices and constant category words reach the
    ; clipboard. Bound the summary even for very large server mod lists.
    for slot, flags in markers.SlotFlags
    {
        if shown >= 12
            break
        categories := ""
        if flags & 1
            categories .= "checksum"
        if flags & 2
            categories .= (categories = "" ? "" : "+") "name"
        if flags & 4
            categories .= (categories = "" ? "" : "+") "extra-client"
        if flags & 8
            categories .= (categories = "" ? "" : "+") "extra-server"
        details .= (details = "" ? "" : "; ") slot " [" categories "]"
        shown += 1
    }
    if markers.ComparisonSlots > shown
        details .= "; +" (markers.ComparisonSlots - shown) " more"
    return details
}

; The report is generated solely from an allowlist of fixed strings, numeric
; counts and known tri-state flags. No untrusted text enters the clipboard.
TES3MPRenderMismatchDiagnostics(info, markers, installed, version, stamp, fingerprint := 0)
{
    configOK := info.Status = "Read"
    logOK := markers.Status = "Read" && markers.Rejected
    if !IsObject(fingerprint)
        fingerprint := TES3MPNewExpansionFingerprintResult("Not checked")
    hashText := RegExMatch(fingerprint.Sha256, "^[0-9A-F]{64}$")
        ? fingerprint.Sha256 : "Unknown"
    expansion := TES3MPMismatchYesNo(info.ExpansionCount > 0, configOK)
    expansionLast := TES3MPMismatchYesNo(info.ExpansionCount = 1 && info.ExpansionIndex = info.Total, configOK && info.ExpansionCount = 1)
    totalText := configOK ? info.Total : "Unknown"
    expansionCountText := configOK ? info.ExpansionCount : "Unknown"
    otherCountText := configOK ? info.OtherCount : "Unknown"
    duplicatesText := configOK ? info.OtherDuplicates : "Unknown"
    afterText := (configOK && info.ExpansionCount = 1) ? info.OtherAfterExpansion : "Unknown"

    ; Each field is appended explicitly. Do not split a return expression
    ; before a parenthesized value: AHK treats that as unreachable code and
    ; silently truncates the report beginning with OtherCount.
    report := "TES3NP - Plugin Mismatch Diagnostics`r`n"
    report .= "Generated (UTC): " stamp "`r`n"
    report .= "Launcher version: " version "`r`n"
    report .= "Reported issue: Server rejected the client plugin/load order`r`n"
    report .= "`r`n[Assessment]`r`n"
    report .= "Evidence: " TES3MPMismatchAssessment(info, markers, installed) "`r`n"
    report .= "Expansion Pack version verified: No (not checked)`r`n"
    report .= "`r`n[Configured content]`r`n"
    report .= "OpenMW config check: " info.Status "`r`n"
    report .= "Enabled content entries: " totalText "`r`n"
    report .= "Expansion Pack enabled: " expansion "`r`n"
    report .= "Expansion Pack entries: " expansionCountText "`r`n"
    report .= "Expansion Pack last: " expansionLast "`r`n"
    report .= "Additional content entries (not the 3 base masters or Expansion Pack): " otherCountText "`r`n"
    report .= "Repeated additional content entries: " duplicatesText "`r`n"
    report .= "Content entries following Expansion Pack: " afterText "`r`n"
    report .= "Morrowind master: " TES3MPMismatchYesNo(info.Morrowind, configOK) "`r`n"
    report .= "Tribunal master: " TES3MPMismatchYesNo(info.Tribunal, configOK) "`r`n"
    report .= "Bloodmoon master: " TES3MPMismatchYesNo(info.Bloodmoon, configOK) "`r`n"
    report .= "Expansion ESP in configured game folder: " installed "`r`n"
    report .= "Expansion ESP fingerprint check: " fingerprint.Status "`r`n"
    report .= "Expansion ESP size (bytes): " fingerprint.Size "`r`n"
    report .= "Expansion ESP SHA-256: " hashText "`r`n"
    report .= "`r`n[Client rejection evidence]`r`n"
    report .= "Client log check: " markers.Status "`r`n"
    report .= "Client evidence source: " markers.Source "`r`n"
    report .= "Recent server rejection in inspected log: " TES3MPMismatchYesNo(markers.Rejected, markers.Status = "Read") "`r`n"
    report .= "Missing Expansion Pack specifically named: " TES3MPMismatchYesNo(markers.MissingExpansion, logOK) "`r`n"
    report .= "Other missing plugin specifically indicated: " TES3MPMismatchYesNo(markers.MissingOther, logOK) "`r`n"
    report .= "Missing base-game master indicated: " TES3MPMismatchYesNo(markers.MissingBaseMaster, logOK) "`r`n"
    report .= "Missing dependency not identified: " TES3MPMismatchYesNo(markers.MissingUnspecified, logOK) "`r`n"
    report .= "Load-order wording near rejection: " TES3MPMismatchYesNo(markers.Order, logOK) "`r`n"
    report .= "Detailed comparison captured: " TES3MPMismatchYesNo(markers.ComparisonSlots > 0, logOK) "`r`n"
    report .= "Affected comparison slots: " (logOK ? markers.ComparisonSlots : "Unknown") "`r`n"
    report .= "First differing slot (zero-based): " (logOK && markers.FirstSlot >= 0 ? markers.FirstSlot : "Unknown") "`r`n"
    report .= "Checksum mismatch slots: " (logOK ? markers.ChecksumCount : "Unknown") "`r`n"
    report .= "Plugin-name mismatch slots: " (logOK ? markers.NameMismatchCount : "Unknown") "`r`n"
    report .= "Extra client plugin slots: " (logOK ? markers.ExtraClientCount : "Unknown") "`r`n"
    report .= "Extra server plugin slots: " (logOK ? markers.ExtraServerCount : "Unknown") "`r`n"
    report .= "Slot details (zero-based): " (logOK ? TES3MPMismatchSlotSummary(markers) : "Unknown")
    return report
}
TES3MPNewExpansionFingerprintResult(status := "Not checked")
{
    return {Status: status, Size: "Unknown", Sha256: "Unknown"}
}

; CNG hashes the actual ESP contents in bounded 1 MiB blocks. The digest
; identifies bytes, not compatibility with any unverified server manifest.
TES3MPFileSHA256(path)
{
    algorithm := 0
    hash := 0
    file := 0
    try
    {
        if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &algorithm,
            "WStr", "SHA256", "Ptr", 0, "UInt", 0, "Int") != 0
            throw Error("SHA256 provider unavailable")
        lengthBuffer := Buffer(4, 0)
        returned := Buffer(4, 0)
        if DllCall("bcrypt\BCryptGetProperty", "Ptr", algorithm, "WStr", "ObjectLength",
            "Ptr", lengthBuffer.Ptr, "UInt", lengthBuffer.Size,
            "Ptr", returned.Ptr, "UInt", 0, "Int") != 0
            throw Error("SHA256 object length unavailable")
        hashObjectLength := NumGet(lengthBuffer, 0, "UInt")
        if hashObjectLength < 1 || hashObjectLength > 65536
            throw Error("Invalid SHA256 object length")
        hashObject := Buffer(hashObjectLength, 0)
        if DllCall("bcrypt\BCryptCreateHash", "Ptr", algorithm, "Ptr*", &hash,
            "Ptr", hashObject.Ptr, "UInt", hashObject.Size,
            "Ptr", 0, "UInt", 0, "UInt", 0, "Int") != 0
            throw Error("SHA256 hash initialization failed")
        file := FileOpen(path, "r")
        if !IsObject(file)
            throw Error("Expansion ESP could not be opened")
        block := Buffer(1048576, 0)
        while (read := file.RawRead(block, block.Size)) > 0
        {
            if DllCall("bcrypt\BCryptHashData", "Ptr", hash,
                "Ptr", block.Ptr, "UInt", read, "UInt", 0, "Int") != 0
                throw Error("SHA256 update failed")
        }
        digest := Buffer(32, 0)
        if DllCall("bcrypt\BCryptFinishHash", "Ptr", hash,
            "Ptr", digest.Ptr, "UInt", digest.Size, "UInt", 0, "Int") != 0
            throw Error("SHA256 finalize failed")
        result := ""
        Loop digest.Size
            result .= Format("{:02X}", NumGet(digest, A_Index - 1, "UChar"))
        return result
    }
    finally
    {
        if IsObject(file)
            file.Close()
        if hash
            DllCall("bcrypt\BCryptDestroyHash", "Ptr", hash, "Int")
        if algorithm
            DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", algorithm,
                "UInt", 0, "Int")
    }
}

TES3MPReadExpansionFingerprint(path)
{
    info := TES3MPNewExpansionFingerprintResult("Not found")
    if !FileExist(path)
        return info
    try
    {
        info.Size := FileGetSize(path)
        info.Sha256 := TES3MPFileSHA256(path)
        info.Status := "Hashed"
    }
    catch Error as err
    {
        info.Status := "Read error"
        LogLauncherEvent("EXPANSION | Fingerprint calculation unavailable ("
            Type(err) ", line " err.Line ").")
    }
    return info
}

TES3MPBuildMismatchDiagnostics()
{
    global AppConfig, DataFile, TES3MPLastMismatchEvidence
    info := TES3MPReadMismatchConfigInfo()
    markers := TES3MPSelectMismatchLogEvidence(TES3MPLastMismatchEvidence)
    installed := "Not checked"
    fingerprint := TES3MPNewExpansionFingerprintResult()
    try
    {
        root := IniRead(DataFile, "Patch", "MorrowindFolder", "")
        if root != "" && DirExist(root "\Data Files")
        {
            esp := root "\Data Files\NP Expansion Pack.esp"
            fingerprint := TES3MPReadExpansionFingerprint(esp)
            installed := FileExist(esp) ? "Yes" : "No"
        }
    }
    catch Error as err
        LogLauncherEvent("EXPANSION | Diagnostic expansion-file check failed ("
            Type(err) ", line " err.Line ").")
    return TES3MPRenderMismatchDiagnostics(info, markers, installed,
        AppConfig.Version, FormatTime(A_NowUTC, "yyyy-MM-dd HH:mm:ss"), fingerprint)
}
