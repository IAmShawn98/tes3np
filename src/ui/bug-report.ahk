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
        RefreshBugReportScreenshots(settings)
    }
    finally EndInterfaceUpdate()
    settings.ReportMessage.Focus()
}

BuildBugReportPage(settings)
{
    global LauncherMorrowindFont
    SetAccessibleTextFont(settings, "s" V016Font(17) " Norm c241408", LauncherMorrowindFont)
    heading := settings.Add("Text", "x" V016S(32) " y" V016S(126) " w" V016S(448)
        " h" V016S(32) " Center BackgroundTrans", "Report A Bug")
    SetAccessibleTextFont(settings, "s" V016Font(12) " Norm c382314", LauncherMorrowindFont)
    prompt := settings.Add("Text", "x" V016S(32) " y" V016S(165) " w" V016S(448)
        " h" V016S(22) " BackgroundTrans", "What happened?")
    SetAccessibleTextFont(settings, "s" V016Font(10) " Norm c382314", LauncherThemeFont())
    settings.ReportMessage := AddThemedEdit(settings, "x" V016S(32) " y" V016S(190)
        " w" V016S(448) " h" V016S(76) " Multi WantReturn Limit4000")

    settings.ReportAdd := AddStyledButton(settings, V016S(32), V016S(273), V016S(214), V016S(30),
        "Add Screenshots (0)", AddBugReportScreenshots.Bind(settings))
    SetAccessibleTextFont(settings, "s" V016Font(10) " Norm c382314", LauncherThemeFont())
    box := settings.Add("Text", "x" V016S(32) " y" V016S(309) " w" V016S(448)
        " h" V016S(112) " +Border BackgroundE2CEA2")
    settings.ReportEmpty := settings.Add("Text", "x" V016S(41) " y" V016S(320) " w" V016S(430)
        " h" V016S(36) " BackgroundE2CEA2", "Up to 5 PNG or JPEG screenshots (8 MB total).")
    settings.ReportRows := []
    Loop 5
    {
        rowY := 312 + (A_Index - 1) * 21
        SetAccessibleTextFont(settings, "s" V016Font(10) " Norm c382314", LauncherThemeFont())
        name := settings.Add("Text", "x" V016S(41) " y" V016S(rowY) " w" V016S(392)
            " h" V016S(21) " +0x4280 BackgroundE2CEA2")
        remove := AddStyledButton(settings, V016S(441), V016S(rowY), V016S(32), V016S(20),
            "×", RemoveBugReportScreenshot.Bind(settings, A_Index))
        settings.ReportRows.Push({Name: name, Remove: remove})
    }
    SetAccessibleTextFont(settings, "s" V016Font(10) " Norm c382314", LauncherThemeFont())
    note := settings.Add("Text", "x" V016S(32) " y" V016S(426) " w" V016S(448)
        " h" V016S(19) " BackgroundTrans", "Recent diagnostic logs are attached automatically.")
    settings.ReportStatus := settings.Add("Text", "x" V016S(32) " y" V016S(448)
        " w" V016S(448) " h" V016S(32) " BackgroundTrans")
    settings.ReportSend := AddStyledButton(settings, V016S(32), V016S(483), V016S(214), V016S(30),
        "Send Report", SendBugReport.Bind(settings))
    settings.ReportCancel := AddStyledButton(settings, V016S(266), V016S(483), V016S(214), V016S(30),
        "Cancel", CloseBugReportPage.Bind(settings))

    settings.ReportControls := [heading, prompt, settings.ReportMessage, settings.ReportAdd,
        box, settings.ReportEmpty, note, settings.ReportStatus,
        settings.ReportSend, settings.ReportCancel]
    for row in settings.ReportRows
        settings.ReportControls.Push(row.Name, row.Remove)
    settings.ReportScreenshots := []
    settings.ReportWindow := settings.Hwnd
    settings.ReportRequest := 0
    settings.ReportPoll := 0
    settings.ReportBusy := false
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
        settings.ReportStatus.Text := ""
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
    if settings.ReportBusy
        return
    settings.Opt("+OwnDialogs")
    try paths := FileSelect("M1", , "Choose screenshots", "Screenshots (*.png; *.jpg; *.jpeg)")
    catch
    {
        settings.ReportStatus.Text := "The screenshot picker couldn’t open."
        return
    }
    if !IsObject(paths) || !paths.Length
        return
    settings.ReportStatus.Text := AddBugReportAttachments(settings.ReportScreenshots, paths)
    RefreshBugReportScreenshots(settings)
}

AddBugReportAttachments(attachments, paths)
{
    remaining := 8 * 1024 * 1024
    known := Map()
    known.CaseSense := "Off"
    for attachment in attachments
    {
        known[attachment.Path] := true
        remaining -= attachment.Bytes.Size
    }
    skipped := ""
    skippedCount := 0
    for path in paths
    {
        SplitPath(path, &name)
        try
        {
            if known.Has(path)
                throw Error("That screenshot is already attached.")
            if attachments.Length >= 5
                throw Error("You can attach up to 5 screenshots.")
            bytes := ReadBugReportScreenshot(path, remaining)
            attachments.Push({Path: path, Name: name, Bytes: bytes})
            known[path] := true
            remaining -= bytes.Size
        }
        catch Error as err
        {
            skippedCount += 1
            if skipped = ""
            {
                displayName := StrLen(name) > 32 ? SubStr(name, 1, 29) "…" : name
                skipped := displayName " — " (err is OSError ? "Couldn’t read this file." : err.Message)
            }
        }
    }
    return skippedCount ? skippedCount " skipped. " skipped : ""
}

RemoveBugReportScreenshot(settings, index, *)
{
    if settings.ReportBusy || index > settings.ReportScreenshots.Length
        return
    settings.ReportScreenshots.RemoveAt(index)
    settings.ReportStatus.Text := ""
    RefreshBugReportScreenshots(settings)
    if index > settings.ReportScreenshots.Length
        settings.ReportAdd.Focus()
}

RefreshBugReportScreenshots(settings)
{
    count := settings.ReportScreenshots.Length
    SetPaintedLabelText(settings.ReportAdd, "Add Screenshots (" count ")")
    settings.ReportEmpty.Visible := count = 0
    for index, row in settings.ReportRows
    {
        attached := index <= count
        row.Name.Text := attached ? settings.ReportScreenshots[index].Name : ""
        SetBookControlVisible(row.Name, attached)
        SetBookControlVisible(row.Remove, attached)
    }
    UpdateBugReportScreenshotButtons(settings)
}

UpdateBugReportScreenshotButtons(settings)
{
    settings.ReportAdd.Enabled := !settings.ReportBusy && settings.ReportScreenshots.Length < 5
    for row in settings.ReportRows
        row.Remove.Enabled := !settings.ReportBusy
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

    SetBugReportBusy(settings, true, "Sending report...")
    try
        screenshots := EncodeBugReportScreenshots(settings.ReportScreenshots)
    catch
    {
        SetBugReportBusy(settings, false, "Couldn’t prepare the screenshots. Your draft is still here.")
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
                count := settings.ReportScreenshots.Length
                settings.ReportScreenshots := []
                RefreshBugReportScreenshots(settings)
                status := count ? "Report sent with " count (count = 1 ? " screenshot." : " screenshots.") : "Report sent."
                SetBugReportBusy(settings, false, status " ID " receipt[1] ".")
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
    settings.ReportSend.Enabled := !busy
    settings.ReportCancel.Enabled := !busy
    settings.ReportStatus.Text := status
    UpdateBugReportScreenshotButtons(settings)
}

ReadBugReportScreenshot(path, remaining)
{
    if !RegExMatch(path, "i)\.(png|jpe?g)$")
        throw Error("Choose PNG or JPEG screenshots.")
    file := FileOpen(path, "r")
    try
    {
        size := file.Length
        if size > remaining
            throw Error("Screenshots must be 8 MB or less in total.")
        if size < 4
            throw Error("A screenshot is empty or incomplete.")
        bytes := Buffer(size)
        file.Pos := 0
        if file.RawRead(bytes, size) != size
            throw Error("A screenshot could not be read.")
    }
    finally file.Close()
    ; Check the same signatures and end markers as the report receiver.
    isPng := size >= 33 && NumGet(bytes, 0, "UInt") = 0x474E5089
        && NumGet(bytes, 4, "UInt") = 0x0A1A0A0D && NumGet(bytes, size - 8, "UInt") = 0x444E4549
    isJpeg := NumGet(bytes, 0, "UShort") = 0xD8FF && NumGet(bytes, 2, "UChar") = 0xFF
        && NumGet(bytes, size - 2, "UShort") = 0xD9FF
    if !isPng && !isJpeg
        throw Error("A screenshot is incomplete or isn’t a PNG or JPEG.")
    return bytes
}

EncodeBugReportScreenshots(attachments)
{
    encoded := ""
    for index, attachment in attachments
    {
        bytes := attachment.Bytes
        size := bytes.Size
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
        encoded .= (index = 1 ? "" : ",") '"' StrGet(output, "UTF-16") '"'
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
