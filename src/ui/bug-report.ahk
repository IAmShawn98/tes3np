OpenBugReportDialog(owner, *)
{
    ownerHwnd := owner.Hwnd
    dialog := Gui("+Owner" ownerHwnd " -MinimizeBox -MaximizeBox", "tes3np — Report A Bug")
    dialog.BackColor := "E2CEA2"
    dialog.SetFont("s10 c382314", "Segoe UI")
    dialog.Add("Text", "x20 y16 w420 h23", "What happened?")
    dialog.ReportMessage := dialog.Add("Edit", "x20 y42 w420 h128 Multi WantReturn Limit4000")
    dialog.ReportScreenshots := []
    dialog.ReportList := dialog.Add("ListBox", "x20 y217 w420 h85")
    dialog.ReportAdd := dialog.Add("Button", "x20 y179 w142 h28", "Add Screenshots")
    dialog.ReportRemove := dialog.Add("Button", "x170 y179 w100 h28 Disabled", "Remove")
    dialog.ReportRemove.OnEvent("Click", RemoveBugReportScreenshot.Bind(dialog))
    dialog.ReportAdd.OnEvent("Click", AddBugReportScreenshots.Bind(dialog))
    dialog.ReportList.OnEvent("Change", UpdateBugReportScreenshotButtons.Bind(dialog))
    dialog.Add("Text", "x20 y310 w420 h37",
        "A recent launcher log is attached automatically. Screenshots are optional (up to 5 PNG or JPEG files, 8 MB total).")
    dialog.ReportStatus := dialog.Add("Text", "x20 y354 w420 h43")
    dialog.ReportSend := dialog.Add("Button", "x230 y405 w105 h30", "Send Report")
    dialog.ReportCancel := dialog.Add("Button", "x343 y405 w97 h30", "Cancel")
    dialog.ReportWindow := dialog.Hwnd
    dialog.ReportRequest := 0
    dialog.ReportPoll := 0
    dialog.ReportBusy := false
    dialog.ReportSend.OnEvent("Click", SendBugReport.Bind(dialog))
    dialog.ReportCancel.OnEvent("Click", CloseBugReportDialog.Bind(dialog))
    dialog.OnEvent("Close", CloseBugReportDialog)
    dialog.OnEvent("Escape", CloseBugReportDialog)

    owner.Opt("+Disabled")
    try
    {
        scale := Max(0.8, GetOwnedMenuScale())
        ScaleOwnedMenuContent(dialog, scale)
        dialog.Show("Hide w" Round(460 * scale) " h" Round(453 * scale))
        PositionOwnedMenuAtParent(dialog, owner)
        dialog.Show()
        dialog.ReportMessage.Focus()
        WinWaitClose("ahk_id " dialog.Hwnd)
    }
    finally
    {
        StopBugReportRequest(dialog)
        if DllCall("IsWindow", "Ptr", ownerHwnd)
        {
            owner.Opt("-Disabled")
            WinActivate("ahk_id " ownerHwnd)
        }
        DestroyScaledMenu(dialog)
    }
}

CloseBugReportDialog(dialog, *)
{
    if dialog.ReportBusy
        return true
    dialog.Hide()
}

AddBugReportScreenshots(dialog, *)
{
    dialog.Opt("+OwnDialogs")
    paths := FileSelect("M1", , "Choose screenshots", "Screenshots (*.png; *.jpg; *.jpeg)")
    if !IsObject(paths) || !paths.Length
        return
    selected := dialog.ReportScreenshots.Clone()
    known := Map()
    known.CaseSense := false
    try
    {
        totalBytes := 0
        for path in selected
        {
            known[path] := true
            totalBytes += FileGetSize(path)
        }
        for path in paths
        {
            if known.Has(path)
                continue
            if selected.Length = 5
                throw Error("You can attach up to 5 screenshots.")
            if !RegExMatch(path, "i)\.(png|jpe?g)$") || !IsValidOriginalCharacterImage(path)
                throw Error("Choose a readable PNG or JPEG screenshot.")
            totalBytes += FileGetSize(path)
            if totalBytes > 8 * 1024 * 1024
                throw Error("Screenshots must be 8 MB or less in total.")
            known[path] := true
            selected.Push(path)
        }
    }
    catch Error as err
    {
        dialog.ReportStatus.Text := err is OSError ? "A screenshot could not be read." : err.Message
        return
    }
    dialog.ReportScreenshots := selected
    RefreshBugReportScreenshots(dialog)
}

RemoveBugReportScreenshot(dialog, *)
{
    if dialog.ReportList.Value
    {
        dialog.ReportScreenshots.RemoveAt(dialog.ReportList.Value)
        RefreshBugReportScreenshots(dialog)
    }
}

RefreshBugReportScreenshots(dialog)
{
    names := []
    for path in dialog.ReportScreenshots
    {
        SplitPath(path, &name)
        names.Push(name)
    }
    dialog.ReportList.Delete()
    if names.Length
        dialog.ReportList.Add(names)
    dialog.ReportStatus.Text := ""
    UpdateBugReportScreenshotButtons(dialog)
}

UpdateBugReportScreenshotButtons(dialog, *)
{
    dialog.ReportAdd.Enabled := !dialog.ReportBusy && dialog.ReportScreenshots.Length < 5
    dialog.ReportRemove.Enabled := !dialog.ReportBusy && dialog.ReportList.Value != 0
}

SendBugReport(dialog, *)
{
    global AppConfig
    if dialog.ReportBusy
        return
    message := dialog.ReportMessage.Value
    if Trim(message, " `t`r`n") = ""
    {
        dialog.ReportStatus.Text := "Describe what happened before sending."
        dialog.ReportMessage.Focus()
        return
    }
    if RegExMatch(message, "i)(?:[a-z][a-z0-9+.-]*://|\b(?:www\.|mailto:|(?:discord|steam|file):)|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|org|net|edu|gov|io|gg|dev|app|info|biz|xyz|me|co|uk|ca|au|de|fr|ru|cn)(?=$|[^\w-]))")
    {
        dialog.ReportStatus.Text := "Remove links from the description before sending."
        dialog.ReportMessage.Focus()
        return
    }

    SetBugReportBusy(dialog, true, "Sending report…")
    try
        screenshots := EncodeBugReportScreenshots(dialog.ReportScreenshots)
    catch
    {
        SetBugReportBusy(dialog, false, "A screenshot changed or could not be read. Remove it and add it again.")
        return
    }

    try
    {
        payload := '{"message":' BugReportJsonString(message) ',"version":' BugReportJsonString(AppConfig.Version)
            . ',"log":' BugReportJsonString(ReadBugReportLog()) ',"screenshots":[' screenshots ']}'
        ; WinHTTP string bodies can use a legacy code page. Pass explicit UTF-8 bytes.
        size := StrPut(payload, "UTF-8") - 1
        utf8 := Buffer(size + 1)
        StrPut(payload, utf8, "UTF-8")
        bytes := ComObjArray(0x11, size) ; VT_UI1
        data := 0
        arrayPtr := ComObjValue(bytes)
        if DllCall("oleaut32\SafeArrayAccessData", "Ptr", arrayPtr, "Ptr*", &data, "Int") != 0
            throw Error("Could not prepare report data.")
        try DllCall("ntdll\RtlMoveMemory", "Ptr", data, "Ptr", utf8, "UPtr", size)
        finally DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", arrayPtr, "Int")

        endpoint := "https://script.google.com/macros/s/AKfycbz4OcGNQ9ybOTuomR8BI2x1wQ6mlDN-OJIDOb46f7_MMt3VE6bbp7AOK_Mfmqk0OovwzA/exec"
        dialog.ReportStarted := A_TickCount
        dialog.ReportReadingResponse := false
        request := OpenBugReportRequest("POST", endpoint)
        request.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
        dialog.ReportRequest := request
        request.Send(bytes)
        dialog.ReportPoll := PollBugReport.Bind(dialog)
        SetTimer(dialog.ReportPoll, 100)
    }
    catch
    {
        StopBugReportRequest(dialog)
        SetBugReportBusy(dialog, false, "Couldn’t start sending the report. Your draft is still here.")
    }
}

OpenBugReportRequest(method, url)
{
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetTimeouts(5000, 5000, 15000, 20000)
    request.Open(method, url, true)
    request.Option[6] := false ; Follow only the Apps Script response redirect, without resending the report.
    return request
}

PollBugReport(dialog)
{
    if !DllCall("IsWindow", "Ptr", dialog.ReportWindow)
    {
        StopBugReportRequest(dialog)
        return
    }
    request := dialog.ReportRequest
    status := "Couldn’t confirm delivery. Your draft is still here."
    try
    {
        if A_TickCount - dialog.ReportStarted > 45000
            throw Error("Report request timed out.")
        if !request.WaitForResponse(0)
            return
        if !dialog.ReportReadingResponse && (request.Status = 302 || request.Status = 303)
        {
            location := request.GetResponseHeader("Location")
            if !RegExMatch(location, "^https://script\.googleusercontent\.com/macros/echo\?")
                throw Error("Unexpected report redirect.")
            dialog.ReportReadingResponse := true
            dialog.ReportRequest := OpenBugReportRequest("GET", location)
            dialog.ReportRequest.Send()
            return
        }
        if request.Status = 200
        {
            response := request.ResponseText
            if RegExMatch(response, '^\s*\{\s*"ok"\s*:\s*true\s*,\s*"reportId"\s*:\s*"([a-f0-9]{8})"\s*\}\s*$', &receipt)
            {
                StopBugReportRequest(dialog)
                dialog.ReportMessage.Value := ""
                dialog.ReportScreenshots := []
                RefreshBugReportScreenshots(dialog)
                SetBugReportBusy(dialog, false, "Report sent. Report ID " receipt[1] ".")
                return
            }
            if RegExMatch(response, '^\s*\{\s*"ok"\s*:\s*false\s*,\s*"code"\s*:\s*"([a-z_]+)"\s*\}\s*$', &failure)
            {
                switch failure[1]
                {
                    case "links_not_allowed":
                        status := "Remove links from the description before sending."
                    case "invalid_screenshots":
                        status := "The receiver rejected a screenshot. Choose PNG or JPEG files."
                    case "rate_limited", "try_again":
                        status := "The report inbox is busy. Try again later."
                    default:
                        status := "The report couldn’t be sent. Your draft is still here."
                }
            }
        }
    }
    catch
    {
        ; Keep the player's text and selected screenshots for a manual retry.
    }
    StopBugReportRequest(dialog)
    SetBugReportBusy(dialog, false, status)
}

StopBugReportRequest(dialog)
{
    if IsObject(dialog.ReportPoll)
    {
        SetTimer(dialog.ReportPoll, 0)
        dialog.ReportPoll := 0
    }
    if IsObject(dialog.ReportRequest)
    {
        try dialog.ReportRequest.Abort()
        dialog.ReportRequest := 0
    }
}

SetBugReportBusy(dialog, busy, status)
{
    dialog.ReportBusy := busy
    dialog.ReportMessage.Opt(busy ? "+ReadOnly" : "-ReadOnly")
    dialog.ReportList.Enabled := !busy
    dialog.ReportSend.Enabled := !busy
    dialog.ReportCancel.Enabled := !busy
    dialog.ReportStatus.Text := status
    UpdateBugReportScreenshotButtons(dialog)
}

ReadBugReportLog()
{
    global LauncherLogFile
    try
    {
        file := FileOpen(LauncherLogFile, "r", "UTF-8")
        try
        {
            if file.Length > 96 * 1024
            {
                file.Pos := file.Length - 96 * 1024
                while !file.AtEOF && file.ReadUChar() != 10
                    continue
            }
            return SanitizeDiagnosticText(file.Read())
        }
        finally file.Close()
    }
    catch
        return ""
}

EncodeBugReportScreenshots(paths)
{
    remaining := 8 * 1024 * 1024
    encoded := ""
    for path in paths
    {
        file := FileOpen(path, "r")
        try
        {
            size := file.Length
            if size < 1 || size > remaining
                throw Error("Screenshot size exceeds the limit.")
            bytes := Buffer(size)
            if file.RawRead(bytes, size) != size
                throw Error("Could not read screenshot.")
        }
        finally file.Close()

        ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
        characters := 0
        flags := 0x40000001
        if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", bytes, "UInt", size,
            "UInt", flags, "Ptr", 0, "UInt*", &characters)
            throw Error("Could not encode screenshot.")
        output := Buffer(characters * 2)
        if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", bytes, "UInt", size,
            "UInt", flags, "Ptr", output, "UInt*", &characters)
            throw Error("Could not encode screenshot.")
        encoded .= (encoded = "" ? "" : ",") '"' StrGet(output, "UTF-16") '"'
        remaining -= size
    }
    return encoded
}

BugReportJsonString(value)
{
    value := StrReplace(StrReplace(value, '\', '\\'), '"', '\"')
    position := 1
    while found := RegExMatch(value, "[\x00-\x1F]", &control, position)
    {
        escape := "\u" Format("{:04X}", Ord(control[0]))
        value := SubStr(value, 1, found - 1) escape SubStr(value, found + 1)
        position := found + StrLen(escape)
    }
    return '"' value '"'
}
