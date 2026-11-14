OpenBugReportPage(settings, *)
{
    global V016SettingsDataControls, V016SettingsDataActive
    if !V016SettingsDataActive || IsBugReportPageVisible(settings)
        return
    BeginInterfaceUpdate(settings, "Opening Report A Bug...", false)
    try
    {
        if !settings.HasOwnProp("ReportControls")
            BuildBugReportPage(settings)
        for control in V016SettingsDataControls
            SetBookControlVisible(control, false)
        for control in settings.ReportControls
            SetBookControlVisible(control, true)
    }
    finally EndInterfaceUpdate()
    settings.ReportMessage.Focus()
}

BuildBugReportPage(settings)
{
    global LauncherMorrowindFont
    settings.SetFont("s" V016Font(17) " Norm c241408", LauncherMorrowindFont)
    heading := settings.Add("Text", "x" V016S(32) " y" V016S(126) " w" V016S(448)
        " h" V016S(32) " Center BackgroundTrans", "Report A Bug")
    settings.SetFont("s" V016Font(12) " Norm c382314", LauncherMorrowindFont)
    prompt := settings.Add("Text", "x" V016S(32) " y" V016S(165) " w" V016S(448)
        " h" V016S(22) " BackgroundTrans", "What happened?")
    settings.SetFont("s" V016Font(10) " Norm c382314", "Segoe UI")
    settings.ReportMessage := AddThemedEdit(settings, "x" V016S(32) " y" V016S(190)
        " w" V016S(448) " h" V016S(100) " Multi WantReturn Limit4000")

    settings.ReportAdd := AddStyledButton(settings, V016S(32), V016S(299), V016S(214), V016S(30),
        "Add Screenshots", AddBugReportScreenshots.Bind(settings))
    settings.ReportRemove := AddStyledButton(settings, V016S(266), V016S(299), V016S(214), V016S(30),
        "Remove", RemoveBugReportScreenshot.Bind(settings))
    settings.SetFont("s" V016Font(10) " Norm c382314", "Segoe UI")
    settings.ReportList := settings.Add("ListBox", "x" V016S(32) " y" V016S(337)
        " w" V016S(448) " h" V016S(54) " +0x100 -E0x200 +Border BackgroundE2CEA2")
    settings.ReportList.OnEvent("Change", UpdateBugReportScreenshotButtons.Bind(settings))
    note := settings.Add("Text", "x" V016S(32) " y" V016S(398) " w" V016S(448)
        " h" V016S(40) " BackgroundTrans",
        "A recent launcher log is attached automatically.`nUp to 5 PNG or JPEG screenshots (8 MB total).")
    settings.ReportStatus := settings.Add("Text", "x" V016S(32) " y" V016S(440)
        " w" V016S(448) " h" V016S(40) " BackgroundTrans")
    settings.ReportSend := AddStyledButton(settings, V016S(32), V016S(483), V016S(214), V016S(30),
        "Send Report", SendBugReport.Bind(settings))
    settings.ReportCancel := AddStyledButton(settings, V016S(266), V016S(483), V016S(214), V016S(30),
        "Cancel", CloseBugReportPage.Bind(settings))

    settings.ReportControls := [heading, prompt, settings.ReportMessage, settings.ReportAdd,
        settings.ReportRemove, settings.ReportList, note, settings.ReportStatus,
        settings.ReportSend, settings.ReportCancel]
    settings.ReportScreenshots := []
    settings.ReportWindow := settings.Hwnd
    settings.ReportRequest := 0
    settings.ReportPoll := 0
    settings.ReportBusy := false
    UpdateBugReportScreenshotButtons(settings)
}

IsBugReportPageVisible(settings)
{
    return settings.HasOwnProp("ReportControls") && settings.ReportMessage.Visible
}

CloseBugReportPage(settings, *)
{
    global V016SettingsDataControls
    if !IsBugReportPageVisible(settings) || settings.ReportBusy
        return
    BeginInterfaceUpdate(settings, "Returning to Launcher Data...", false)
    try
    {
        settings.ReportMessage.Value := ""
        settings.ReportScreenshots := []
        RefreshBugReportScreenshots(settings)
        for control in settings.ReportControls
            SetBookControlVisible(control, false)
        for control in V016SettingsDataControls
            SetBookControlVisible(control, true)
    }
    finally EndInterfaceUpdate()
    settings.ReportPageButton.Focus()
}

AddBugReportScreenshots(settings, *)
{
    settings.Opt("+OwnDialogs")
    paths := FileSelect("M1", , "Choose screenshots", "Screenshots (*.png; *.jpg; *.jpeg)")
    if !IsObject(paths) || !paths.Length
        return
    selected := settings.ReportScreenshots.Clone()
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
        settings.ReportStatus.Text := err is OSError ? "A screenshot could not be read." : err.Message
        return
    }
    settings.ReportScreenshots := selected
    RefreshBugReportScreenshots(settings)
}

RemoveBugReportScreenshot(settings, *)
{
    if settings.ReportList.Value
    {
        settings.ReportScreenshots.RemoveAt(settings.ReportList.Value)
        RefreshBugReportScreenshots(settings)
    }
}

RefreshBugReportScreenshots(settings)
{
    names := []
    for path in settings.ReportScreenshots
    {
        SplitPath(path, &name)
        names.Push(name)
    }
    settings.ReportList.Delete()
    if names.Length
        settings.ReportList.Add(names)
    settings.ReportStatus.Text := ""
    UpdateBugReportScreenshotButtons(settings)
}

UpdateBugReportScreenshotButtons(settings, *)
{
    settings.ReportAdd.Enabled := !settings.ReportBusy && settings.ReportScreenshots.Length < 5
    settings.ReportRemove.Enabled := !settings.ReportBusy && settings.ReportList.Value != 0
}

SendBugReport(settings, *)
{
    global AppConfig
    if settings.ReportBusy
        return
    message := settings.ReportMessage.Value
    if Trim(message, " `t`r`n") = ""
    {
        settings.ReportStatus.Text := "Describe what happened before sending."
        settings.ReportMessage.Focus()
        return
    }
    if RegExMatch(message, "i)(?:[a-z][a-z0-9+.-]*://|\b(?:www\.|mailto:|(?:discord|steam|file):)|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|org|net|edu|gov|io|gg|dev|app|info|biz|xyz|me|co|uk|ca|au|de|fr|ru|cn)(?=$|[^\w-]))")
    {
        settings.ReportStatus.Text := "Remove links from the description before sending."
        settings.ReportMessage.Focus()
        return
    }

    SetBugReportBusy(settings, true, "Sending report…")
    try
        screenshots := EncodeBugReportScreenshots(settings.ReportScreenshots)
    catch
    {
        SetBugReportBusy(settings, false, "A screenshot changed or could not be read. Remove it and add it again.")
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
        settings.ReportStarted := A_TickCount
        settings.ReportReadingResponse := false
        request := OpenBugReportRequest("POST", endpoint)
        request.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
        settings.ReportRequest := request
        request.Send(bytes)
        settings.ReportPoll := PollBugReport.Bind(settings)
        SetTimer(settings.ReportPoll, 100)
    }
    catch
    {
        StopBugReportRequest(settings)
        SetBugReportBusy(settings, false, "Couldn’t start sending the report. Your draft is still here.")
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

PollBugReport(settings)
{
    if !DllCall("IsWindow", "Ptr", settings.ReportWindow)
    {
        StopBugReportRequest(settings)
        return
    }
    request := settings.ReportRequest
    status := "Couldn’t confirm delivery. Your draft is still here."
    try
    {
        if A_TickCount - settings.ReportStarted > 45000
            throw Error("Report request timed out.")
        if !request.WaitForResponse(0)
            return
        if !settings.ReportReadingResponse && (request.Status = 302 || request.Status = 303)
        {
            location := request.GetResponseHeader("Location")
            if !RegExMatch(location, "^https://script\.googleusercontent\.com/macros/echo\?")
                throw Error("Unexpected report redirect.")
            settings.ReportReadingResponse := true
            settings.ReportRequest := OpenBugReportRequest("GET", location)
            settings.ReportRequest.Send()
            return
        }
        if request.Status = 200
        {
            response := request.ResponseText
            if RegExMatch(response, '^\s*\{\s*"ok"\s*:\s*true\s*,\s*"reportId"\s*:\s*"([a-f0-9]{8})"\s*\}\s*$', &receipt)
            {
                StopBugReportRequest(settings)
                settings.ReportMessage.Value := ""
                settings.ReportScreenshots := []
                RefreshBugReportScreenshots(settings)
                SetBugReportBusy(settings, false, "Report sent. Report ID " receipt[1] ".")
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
    StopBugReportRequest(settings)
    SetBugReportBusy(settings, false, status)
}

StopBugReportRequest(settings)
{
    if IsObject(settings.ReportPoll)
    {
        SetTimer(settings.ReportPoll, 0)
        settings.ReportPoll := 0
    }
    if IsObject(settings.ReportRequest)
    {
        try settings.ReportRequest.Abort()
        settings.ReportRequest := 0
    }
}

SetBugReportBusy(settings, busy, status)
{
    settings.ReportBusy := busy
    settings.ReportMessage.Opt(busy ? "+ReadOnly" : "-ReadOnly")
    settings.ReportList.Enabled := !busy
    settings.ReportSend.Enabled := !busy
    settings.ReportCancel.Enabled := !busy
    settings.ReportStatus.Text := status
    UpdateBugReportScreenshotButtons(settings)
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
