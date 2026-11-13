; Local macro packages. Import extracts files; only Run executes a chosen script.

BuildMacroBookPanel()
{
    global CharacterPage, LauncherMorrowindFont, ButtonFaces
    global MacroPage, MacroList, MacroStatus, MacroEmptyNotice
    global MacroImportButton, MacroBookControls, MacroBookRows
    global MacroScrollOffset, MacroScrollTrack, MacroScrollThumb, MacroScrollDragging, MacroScrollGrab
    MacroPage := CharacterPage
    MacroBookControls := []
    MacroBookRows := []
    MacroScrollOffset := 0
    MacroScrollDragging := false
    MacroScrollGrab := 0
    CharacterPage.SetFont("s19 Norm c241408", LauncherMorrowindFont)
    heading := CharacterPage.Add("Text", "x525 y45 w355 h32 Center BackgroundTrans", "Manage Macros")
    CharacterPage.SetFont("s11 Norm c241408", LauncherMorrowindFont)
    explanation := CharacterPage.Add("Text", "x525 y87 w355 h48 BackgroundTrans",
        "Upload, run, or stop macros here. Click a macro name to rename it.")
    MacroEmptyNotice := CharacterPage.Add("Text", "x525 y150 w355 h28 BackgroundTrans",
        "No macros installed yet.")
    ; The hidden ListView retains every imported item and all existing handlers.
    ; Four rows are the viewport, not a limit on the number of macros.
    MacroList := CharacterPage.Add("ListView", "x525 y144 w355 h226 Hidden -Multi",
        ["Name", "Status", "Type"])
    MacroList.OnEvent("ItemSelect", RefreshMacroButtons)
    MacroBookControls.Push(heading, explanation, MacroEmptyNotice, MacroList)
    Loop 4
    {
        position := A_Index
        ; Leave an 8-pixel gap after each row's bottom button.
        ; Previous 60px pitch overlapped the next row's "Ready" label.
        ; Preserve 8px between macro rows and remove the unused space
        ; above the first status by moving the populated list up 12px.
        y := 140 + (position - 1) * 70
        CharacterPage.SetFont("s9 Norm c241408", LauncherMorrowindFont)
        status := CharacterPage.Add("Text",
            "x551 y" y " w329 h17 BackgroundTrans c241408 +0x100", "")
        CharacterPage.SetFont("s12 Norm c241408", LauncherMorrowindFont)
        tick := AddBookTick(CharacterPage, 525, y + 20, SelectMacroBookRow.Bind(position))
        name := AddBookLabel(CharacterPage, 551, y + 19, 329, 22, "")
        name.Opt("+0x100")
        name.OnEvent("Click", RenameMacroBookRow.Bind(position))
        ButtonFaces[name.Hwnd].IsClickable := true
        run := AddStyledButton(CharacterPage, 551, y + 42, 103, 20,
            "Run", RunMacroBookRow.Bind(position))
        stop := AddStyledButton(CharacterPage, 663, y + 42, 103, 20,
            "Stop", StopMacroBookRow.Bind(position))
        remove := AddStyledButton(CharacterPage, 775, y + 42, 105, 20,
            "Remove", RemoveMacroBookRow.Bind(position))
        MacroBookRows.Push({Tick: tick, Status: status, StatusError: false,
            Name: name, Run: run, Stop: stop, Remove: remove})
        MacroBookControls.Push(tick, status, name, run, stop, remove)
    }
    ; The scrollbar uses the existing character-book styling.
    MacroScrollTrack := CharacterPage.Add("Text",
        "x887 y140 w8 h272 Background704C27 +0x100 Hidden")
    MacroScrollThumb := CharacterPage.Add("Text",
        "x888 y140 w6 h40 BackgroundC69951 +0x100 Hidden")
    ; The macro itself owns all hotkeys; keep Upload full-width and tight
    ; against the last visible macro row without extra action slots.
    MacroImportButton := AddStyledButton(CharacterPage, 525, 188, 355, 29,
        "Upload Macro", ImportMacroPackage)
    ; Existing import callbacks still write MacroStatus.Text. Preserve
    ; failure/progress feedback, not the redundant Ready/script-details footer.
    CharacterPage.SetFont("s9 Norm c241408", LauncherMorrowindFont)
    MacroStatus := CharacterPage.Add("Text",
        "x525 y224 w355 h30 Hidden BackgroundTrans c241408", "Ready.")
    MacroBookControls.Push(MacroScrollTrack, MacroScrollThumb,
        MacroImportButton, MacroStatus)
    LoadMacroPackages()
    ShowMacroBookPanel()
}

ShowMacroBookPanel()
{
    global MacroBookControls, MacroList
    ; The editor's hide path may run before the book has built its controls.
    if !IsObject(MacroList)
        return
    for control in MacroBookControls
        if control != MacroList
            control.Visible := true
    ; Retain the legacy ListView only as an invisible selection model.
    MacroList.Visible := false
    RefreshMacroButtons()
}

HideMacroBookPanel()
{
    global MacroBookControls
    ReleaseMacroScroll()
    for control in MacroBookControls
        try control.Visible := false
}

MacroItemDisplayState(item)
{
    if item.Kind = "App" && !ValidMacroApplication(item)
        return {Text: "Application missing", Error: true}
    if item.Kind != "App" && !ValidMacroEntry(item.Folder, item.Entry)
        return {Text: "Script missing", Error: true}
    if item.HasOwnProp("LastError") && item.LastError != ""
        return {Text: item.LastError, Error: true}
    if item.PID && ProcessExist(item.PID)
        return {Text: "Running", Error: false}
    return {Text: "Ready", Error: false}
}

RefreshMacroBookRows()
{
    global MacroList, MacroItems, MacroBookRows, MacroScrollOffset, MacroImport
    global MacroEmptyNotice, MacroScrollTrack, MacroScrollThumb, MacroStatus
    global MacroImportButton, CharacterPage
    global LaunchSettingsHeading, ButtonFaces, LauncherMorrowindFont
    if !IsObject(MacroList) || !MacroBookRows.Length
        return
    count := MacroItems.Length
    maximum := Max(0, count - MacroBookRows.Length)
    MacroScrollOffset := Max(0, Min(MacroScrollOffset, maximum))
    shown := !LaunchSettingsHeading.Visible
    selectedIndex := MacroList.GetNext()
    busy := IsObject(MacroImport)
    MacroList.Visible := false
    for position, itemRow in MacroBookRows
    {
        index := MacroScrollOffset + position
        visible := shown && index <= count
        for control in [itemRow.Tick, itemRow.Status, itemRow.Name,
            itemRow.Run, itemRow.Stop, itemRow.Remove]
            if control.Visible != visible
                control.Visible := visible
        if !visible
            continue
        item := MacroItems[index]
        ; The name occupies its own full row above the action buttons.
        name := StrLen(item.Name) > 37 ? SubStr(item.Name, 1, 34) "..." : item.Name
        if !(itemRow.Name.Text == name)
            itemRow.Name.Text := name
        selected := index = selectedIndex
        if ButtonFaces[itemRow.Tick.Hwnd].Checked != selected
            SetBookTick(itemRow.Tick, selected)
        state := MacroItemDisplayState(item)
        if itemRow.Status.Text != state.Text
            itemRow.Status.Text := state.Text
        if itemRow.StatusError != state.Error
        {
            itemRow.Status.SetFont(state.Error ? "s" Max(7, BookS(9)) " cB22222"
                : "s" Max(7, BookS(9)) " c241408", LauncherMorrowindFont)
            itemRow.StatusError := state.Error
        }
        running := item.PID && ProcessExist(item.PID)
        missing := !ValidMacroApplication(item)
            || (item.Kind != "App" && !ValidMacroEntry(item.Folder, item.Entry))
        canRun := !missing && !running && !busy
        canStop := !!running
        canRemove := !running && !busy
        if itemRow.Run.Enabled != canRun
            itemRow.Run.Enabled := canRun
        if itemRow.Stop.Enabled != canStop
            itemRow.Stop.Enabled := canStop
        if itemRow.Remove.Enabled != canRemove
            itemRow.Remove.Enabled := canRemove
    }
    MacroEmptyNotice.Visible := shown && count = 0
    scrollable := shown && maximum > 0
    if MacroScrollTrack.Visible != scrollable
        MacroScrollTrack.Visible := scrollable
    if MacroScrollThumb.Visible != scrollable
        MacroScrollThumb.Visible := scrollable
    if scrollable
    {
        thumbHeight := Max(25, Round(272 * MacroBookRows.Length / count))
        travel := 272 - thumbHeight
        thumbY := 140 + Round(MacroScrollOffset / maximum * travel)
        MacroScrollThumb.Move(BookS(888), BookS(thumbY), BookS(6), BookS(thumbHeight))
    }
    ; Keep empty-state content close to the introduction, then follow
    ; populated rows without putting Upload inside the scroll viewport.
    ; For 0/1/2/3/4+ entries, y is 188/214/284/354/424.
    ; Match row pitch so Upload stays 12px clear of final action row.
    visibleCount := Min(count, MacroBookRows.Length)
    desiredUploadY := count = 0 ? 188 : 214 + (visibleCount - 1) * 70
    MacroImportButton.GetPos(, &oldUploadY)
    if oldUploadY != BookS(desiredUploadY)
    {
        ; Move the themed hit target and painted face together. Hide while
        ; relocating to avoid leaving stale button artwork on parchment.
        wasVisible := MacroImportButton.Visible
        if wasVisible
            MacroImportButton.Visible := false
        MoveStyledButton(MacroImportButton, 525, desiredUploadY, 355, 29)
        MacroStatus.Move(BookS(525), BookS(desiredUploadY + 36), BookS(355), BookS(30))
        if wasVisible
        {
            MacroImportButton.Visible := true
            DllCall("RedrawWindow", "Ptr", CharacterPage.Hwnd,
                "Ptr", 0, "Ptr", 0, "UInt", 0x385)
        }
    }
    ; Only import failures/progress use the message area below Upload.
    ; Regular Ready/Running/Missing appears above each macro's name.
    feedback := MacroStatus.Text
    showFeedback := busy || RegExMatch(feedback,
        "i)^(Import failed:|The script could not be imported)")
    if MacroStatus.Visible != (shown && showFeedback)
        MacroStatus.Visible := shown && showFeedback
}

SelectMacroBookRow(position, *)
{
    global MacroList, MacroScrollOffset, MacroItems
    index := MacroScrollOffset + position
    if index < 1 || index > MacroItems.Length
        return
    MacroList.Modify(index, "Select Focus")
    RefreshMacroButtons()
}

RenameMacroBookRow(position, *)
{
    global MacroPage, MacroList, MacroScrollOffset, MacroItems
    index := MacroScrollOffset + position
    if index < 1 || index > MacroItems.Length
        return
    item := MacroItems[index]
    MacroPage.Opt("+OwnDialogs")
    prompt := "Enter a display name for this macro."
    name := item.Name
    loop
    {
        result := InputBox(prompt, "Rename macro", "w400 h130", name)
        if result.Result != "OK"
            return
        name := Trim(result.Value)
        if name != "" && StrLen(name) <= 100
            break
        prompt := "Enter a name between 1 and 100 characters."
    }
    if name == item.Name || index > MacroItems.Length || MacroItems[index] != item
        return

    metadata := item.Folder "\.tes3np-package.ini"
    try
    {
        if !FileExist(metadata)
            throw Error("Macro package metadata is missing.")
        ; The INI reader strips the outer quotes, preserving quotes in the name.
        IniWrite(Chr(34) name Chr(34), metadata, "Macro", "Name")
    }
    catch
    {
        MsgBox("Could not save the macro name. Check that the package is writable.",
            "Rename macro", "Icon!")
        return
    }
    item.Name := name
    MacroList.Modify(index, "Select Focus", name)
    RefreshMacroButtons()
}

; Row actions update the existing ListView selection before delegating to
; the tested macro execution, stop and removal callbacks.
RunMacroBookRow(position, *)
{
    SelectMacroBookRow(position)
    RunSelectedMacro()
}

StopMacroBookRow(position, *)
{
    SelectMacroBookRow(position)
    StopSelectedMacro()
}

RemoveMacroBookRow(position, *)
{
    SelectMacroBookRow(position)
    RemoveSelectedMacro()
}

ScrollMacroBook(offset)
{
    global MacroScrollOffset, MacroItems, MacroBookRows
    if !IsObject(MacroBookRows) || !MacroBookRows.Length
        return
    nextOffset := Max(0, Min(Max(0, MacroItems.Length - MacroBookRows.Length), offset))
    if nextOffset = MacroScrollOffset
        return
    MacroScrollOffset := nextOffset
    RefreshMacroButtons()
}

ScrollMacroWheel(wParam)
{
    global CharacterPage, LaunchSettingsHeading, MacroScrollTrack, MacroItems
    global MacroBookRows, MacroScrollOffset
    if !IsObject(CharacterPage) || !IsObject(MacroScrollTrack)
        || !MacroScrollTrack.Visible || LaunchSettingsHeading.Visible
        || MacroItems.Length <= MacroBookRows.Length
        return false
    MouseGetPos(&x, &y, &window)
    if window != CharacterPage.Hwnd
        return false
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", CharacterPage.Hwnd, "Ptr", origin)
    scale := (A_ScreenDPI / 96) * GetCharacterBookScale()
    x := (x - NumGet(origin, 0, "Int")) / scale
    y := (y - NumGet(origin, 4, "Int")) / scale
    if x < 520 || x > 900 || y < 150 || y > 396
        return false
    delta := (wParam >> 16) << 48 >> 48
    if delta
        ScrollMacroBook(MacroScrollOffset + (delta > 0 ? -3 : 3))
    return true
}

PressMacroScroll(hwnd)
{
    global CharacterPage, MacroScrollTrack, MacroScrollThumb
    global MacroScrollDragging, MacroScrollGrab, MacroScrollOffset
    if !IsObject(MacroScrollTrack) || !MacroScrollTrack.Visible
        || (hwnd != MacroScrollTrack.Hwnd && hwnd != MacroScrollThumb.Hwnd)
        return false
    MouseGetPos(, &pointerY)
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", CharacterPage.Hwnd, "Ptr", origin)
    localY := (pointerY - NumGet(origin, 4, "Int")) / ((A_ScreenDPI / 96) * GetCharacterBookScale())
    MacroScrollThumb.GetPos(, &thumbY, , &thumbHeight)
    thumbY /= GetCharacterBookScale()
    thumbHeight /= GetCharacterBookScale()
    MacroScrollGrab := hwnd = MacroScrollThumb.Hwnd
        ? localY - thumbY : thumbHeight / 2
    MacroScrollDragging := true
    DllCall("SetCapture", "Ptr", hwnd)
    DragMacroScroll()
    return true
}

DragMacroScroll()
{
    global CharacterPage, MacroScrollDragging, MacroScrollGrab
    global MacroItems, MacroBookRows, MacroScrollThumb
    if !MacroScrollDragging
        return
    MouseGetPos(, &pointerY)
    origin := Buffer(8, 0)
    DllCall("ClientToScreen", "Ptr", CharacterPage.Hwnd, "Ptr", origin)
    localY := (pointerY - NumGet(origin, 4, "Int")) / ((A_ScreenDPI / 96) * GetCharacterBookScale())
    MacroScrollThumb.GetPos(, , , &thumbHeight)
    thumbHeight /= GetCharacterBookScale()
    travel := Max(1, 272 - thumbHeight)
    maximum := Max(0, MacroItems.Length - MacroBookRows.Length)
    ScrollMacroBook(Round((localY - 140 - MacroScrollGrab) / travel * maximum))
}

ReleaseMacroScroll()
{
    global MacroScrollDragging
    if !MacroScrollDragging
        return false
    MacroScrollDragging := false
    DllCall("ReleaseCapture")
    return true
}

CloseMacroPage(*)
{
    ReleaseMacroScroll()
    SetTimer(RefreshMacroProcesses, 0)
}


LoadMacroPackages()
{
    global MacroRoot, MacroItems, MacroList, MacroScrollOffset
    MacroScrollOffset := 0
    DirCreate(MacroRoot)
    ; Preserve existing tracked process IDs when the book window is rebuilt.
    tracked := Map()
    for item in MacroItems
        if item.PID && ProcessExist(item.PID)
            tracked[item.Folder] := item.PID
    MacroItems := []
    MacroList.Delete()
    Loop Files MacroRoot "\*", "D"
    {
        folder := A_LoopFileFullPath
        metadata := folder "\.tes3np-package.ini"
        if !FileExist(metadata)
            continue
        kind := IniRead(metadata, "Macro", "Kind", "Macro")
        entry := IniRead(metadata, "Macro", "Entry", "")
        target := kind = "App" ? IniRead(metadata, "Macro", "Target", "") : ""
        if kind != "App" && (kind != "Macro" || !ValidMacroEntry(folder, entry))
            continue
        name := IniRead(metadata, "Macro", "Name", "Macro")
        description := IniRead(metadata, "Macro", "Description", "")
        pid := tracked.Has(folder) ? tracked[folder] : 0
        item := {Folder: folder, Entry: entry, Name: name, Description: description,
            Kind: kind, Target: target, PID: pid}
        MacroItems.Push(item)
        MacroList.Add(, name, kind = "App" && !ValidMacroApplication(item) ? "Missing"
            : (pid ? "Running" : "Ready"), MacroTypeLabel(item))
    }
    ; Make the first installed tool immediately available for Run.
    if MacroItems.Length
        MacroList.Modify(1, "Select Focus")
    RefreshMacroButtons()
}

MacroTypeLabel(item)
{
    return item.Kind = "App" ? "App" : "Macro"
}

ValidMacroApplication(item)
{
    if item.Kind != "App"
        return true
    if item.Target = "" || !RegExMatch(item.Target, "i)\.exe$")
        return false
    attributes := FileExist(item.Target)
    return attributes != "" && !InStr(attributes, "D")
}

ValidMacroEntry(folder, entry)
{
    if entry = "" || !RegExMatch(entry, "i)\.ahk$") || RegExMatch(entry, "[:\r\n]") || SubStr(entry, 1, 1) = "\" || SubStr(entry, 1, 1) = "/"
        return false
    for part in StrSplit(StrReplace(entry, "/", "\"), "\")
        if part = ".."
            return false
    attributes := FileExist(folder "\" entry)
    return attributes != "" && !InStr(attributes, "D")
}

RefreshMacroButtons(*)
{
    global MacroList
    ; The selected macro and its row are driven by the existing invisible
    ; ListView, without restoring either crossed-out footer control.
    if !IsObject(MacroList)
        return
    RefreshMacroBookRows()
}

ImportMacroPackage(*)
{
    global MacroImport, MacroImportButton, MacroStatus, MacroRoot
    if IsObject(MacroImport)
        return
    archive := FileSelect(1, , "Upload Macro",
        "AutoHotkey scripts, ZIPs and applications (*.ahk;*.zip;*.exe)")
    if archive = ""
        return
    if RegExMatch(archive, "i)\.ahk$")
    {
        ImportMacroScript(archive)
        return
    }
    if RegExMatch(archive, "i)\.exe$")
    {
        ImportMacroApplication(archive)
        return
    }
    if !RegExMatch(archive, "i)\.zip$")
    {
        MsgBox("Choose an .ahk script, ZIP containing scripts, or installed .exe.", "Upload Macro")
        return
    }
    try
    {
        signature := FileOpen(archive, "r")
        try magic := signature.Length >= 4 ? signature.ReadUInt() : 0
        finally signature.Close()
    }
    catch
    {
        MsgBox("The archive could not be read. Check that it is available on this computer.", "Import Macro")
        return
    }
    if magic != 0x04034B50 && magic != 0x06054B50
    {
        MsgBox("This file is not a ZIP archive. Create a ZIP containing your .ahk script.", "Import Macro")
        return
    }
    staging := MacroRoot "\import-" FormatTime(, "yyyyMMddHHmmss") "-" A_TickCount
    try
    {
        DirCreate(staging)
        helper := A_ScriptDir "\scripts\import-macro.ps1"
        powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
        Run('"' powershell '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' helper '" -Archive "' archive '" -Destination "' staging '"', , "Hide", &pid)
        MacroImport := {PID: pid, Folder: staging, Archive: archive, Started: A_TickCount}
        MacroImportButton.Enabled := false
        MacroStatus.Text := "Extracting and checking macro package..."
        RefreshMacroButtons()
        SetTimer(CheckMacroImport, 200)
    }
    catch
    {
        if DirExist(staging)
            DirDelete(staging, true)
        MsgBox("Could not start ZIP import. Windows PowerShell is required.", "Import Macro")
    }
}

CheckMacroImport()
{
    global MacroImport, MacroImportButton, MacroStatus
    if !IsObject(MacroImport)
        return
    timedOut := false
    if ProcessExist(MacroImport.PID)
    {
        if A_TickCount - MacroImport.Started < 120000
            return
        timedOut := true
        try ProcessClose(MacroImport.PID)
    }
    SetTimer(CheckMacroImport, 0)
    pending := MacroImport
    MacroImport := 0
    try
    {
        if timedOut
            throw Error("ZIP extraction timed out after 120 seconds.")
        if !FileExist(pending.Folder "\.import-success") || FileExist(pending.Folder "\.import-error")
        {
            detail := FileExist(pending.Folder "\.import-error") ? SubStr(FileRead(pending.Folder "\.import-error", "UTF-8"), 1, 200) : "ZIP extraction helper did not complete. Check that scripts/import-macro.ps1 is present and PowerShell can run."
            throw Error(detail)
        }
        FinishMacroImport(pending)
    }
    catch Error as err
    {
        if DirExist(pending.Folder)
            DirDelete(pending.Folder, true)
        detail := SanitizeDiagnosticText(err.Message)
        if detail = ""
            detail := "The macro ZIP could not be imported."
        MacroStatus.Text := "Import failed: " detail
        MsgBox("The ZIP could not be imported.`n`n" detail, "Import Macro")
    }
    finally
    {
        MacroImportButton.Enabled := true
        RefreshMacroButtons()
    }
}

FinishMacroImport(pending)
{
    global MacroStatus, MacroRoot
    scripts := []
    Loop Files pending.Folder "\*.ahk", "R"
        scripts.Push(SubStr(A_LoopFileFullPath, StrLen(pending.Folder) + 2))
    if !scripts.Length
        throw Error("No AutoHotkey script")
    entry := "", manifest := pending.Folder "\macro.ini"
    if FileExist(manifest)
        entry := IniRead(manifest, "Macro", "Entry", "")
    if entry != "" && !ValidMacroEntry(pending.Folder, entry)
        throw Error("Invalid entry script")
    if entry = ""
        entry := scripts.Length = 1 ? scripts[1] : ChooseMacroScript(scripts)
    if entry = ""
    {
        DirDelete(pending.Folder, true)
        MacroStatus.Text := "Import canceled."
        return
    }
    SplitPath(pending.Archive, , , , &defaultName)
    name := IniRead(manifest, "Macro", "Name", defaultName)
    description := IniRead(manifest, "Macro", "Description", "")
    name := SubStr(Trim(name), 1, 100)
    if name = ""
        name := "Macro"
    metadata := pending.Folder "\.tes3np-package.ini"
    IniWrite(name, metadata, "Macro", "Name")
    IniWrite(SubStr(description, 1, 500), metadata, "Macro", "Description")
    IniWrite(entry, metadata, "Macro", "Entry")
    FileDelete(pending.Folder "\.import-success")
    ; Immutable unique install folders allow ZIPs with the same display name.
    destination := MacroRoot "\package-" FormatTime(, "yyyyMMddHHmmss") "-" A_TickCount
    DirMove(pending.Folder, destination)
    AddImportedMacro(destination, name, description, entry)
    MacroStatus.Text := "Imported " name ". Select it and click Run."
}

AddImportedMacro(folder, name, description, entry, kind := "Macro", target := "")
{
    global MacroItems, MacroList, MacroScrollOffset
    MacroItems.Push({Folder: folder, Entry: entry, Name: name, Description: description,
        Kind: kind, Target: target, PID: 0})
    row := MacroList.Add(, name, "Ready", kind = "App" ? "App" : "Macro")
    MacroList.Modify(row, "Select Focus")
    MacroScrollOffset := Max(0, row - 4)
    RefreshMacroButtons()
}

; An installed EXE is linked by path. Copying only its EXE would break apps
; with side-by-side resources and would make launcher removal destructive.
ImportMacroApplication(source)
{
    global MacroRoot, MacroStatus
    if !ValidMacroApplication({Kind: "App", Target: source})
        return
    SplitPath(source, &filename, , , &name)
    name := SubStr(Trim(name), 1, 100)
    if name = ""
        name := filename
    folder := MacroRoot "\app-" FormatTime(, "yyyyMMddHHmmss") "-" A_TickCount
    try
    {
        DirCreate(folder)
        manifest := folder "\.tes3np-package.ini"
        IniWrite(name, manifest, "Macro", "Name")
        IniWrite("App", manifest, "Macro", "Kind")
        IniWrite(filename, manifest, "Macro", "Entry")
        IniWrite(source, manifest, "Macro", "Target")
        IniWrite("Linked local application", manifest, "Macro", "Description")
        AddImportedMacro(folder, name, "Linked local application", filename, "App", source)
        MacroStatus.Text := "Added " name ". Select it and click Run."
    }
    catch
    {
        if DirExist(folder)
            try DirDelete(folder, true)
        MsgBox("Could not register that application.", "Upload Macro")
    }
}

ChooseMacroScript(scripts)
{
    global MacroPage
    result := {Entry: ""}
    chooser := Gui("+Owner" MacroPage.Hwnd " -MinimizeBox -MaximizeBox", "Choose macro script")
    chooser.BackColor := "E2CEA2"
    chooser.SetFont("s10 c382314", "Segoe UI")
    chooser.Add("Text", "x20 y20 w460 h40", "This package has more than one script. Choose the main .ahk file to run.")
    list := chooser.Add("DropDownList", "x20 y70 w460 Choose1", scripts)
    button := chooser.Add("Button", "x260 y115 w100 h30 Default", "Import")
    cancel := chooser.Add("Button", "x380 y115 w100 h30", "Cancel")
    button.OnEvent("Click", AcceptMacroScript.Bind(chooser, list, scripts, result))
    cancel.OnEvent("Click", (*) => chooser.Hide())
    chooser.OnEvent("Close", (*) => chooser.Hide())
    chooser.OnEvent("Escape", (*) => chooser.Hide())
    MacroPage.Opt("+Disabled")
    try
    {
        chooserScale := GetOwnedMenuScale()
        ScaleOwnedMenuContent(chooser, chooserScale)
        chooser.Show("Hide w" Round(500 * chooserScale) " h" Round(165 * chooserScale))
        PositionOwnedMenuAtParent(chooser, MacroPage)
        chooser.Show()
        WinWaitClose("ahk_id " chooser.Hwnd)
    }
    finally
    {
        MacroPage.Opt("-Disabled")
        chooser.Destroy()
    }
    return result.Entry
}

AcceptMacroScript(chooser, list, scripts, result, *)
{
    result.Entry := scripts[list.Value]
    chooser.Hide()
}

RunSelectedMacro(*)
{
    global MacroItems, MacroList, MacroStatus, MacroImport
    row := MacroList.GetNext()
    if !row || row > MacroItems.Length || IsObject(MacroImport)
        return
    macro := MacroItems[row]
    if macro.PID && ProcessExist(macro.PID)
        return
    if !ValidMacroApplication(macro)
        || (macro.Kind != "App" && !ValidMacroEntry(macro.Folder, macro.Entry))
    {
        RefreshMacroButtons()
        return
    }
    if MsgBox("Run " macro.Name "? This tool executes code on your computer. Only run files you trust.", "Run macro / app", 0x124) != "Yes"
        return
    try
    {
        if macro.Kind = "App"
        {
            if !ValidMacroApplication(macro)
                throw Error("App executable is missing")
            SplitPath(macro.Target, , &directory)
            Run('"' macro.Target '"', directory, , &pid)
        }
        else
        {
            interpreter := A_IsCompiled ? A_ScriptDir "\runtime\AutoHotkey64.exe" : A_AhkPath
            if !FileExist(interpreter)
                throw Error("Bundled AutoHotkey macro runtime missing")
            entry := macro.Folder "\" macro.Entry
            if !ValidMacroEntry(macro.Folder, macro.Entry)
                throw Error("Script no longer exists")
            SplitPath(entry, , &directory)
            ; Macro-specific shortcuts and settings belong to the script.
            Run('"' interpreter '" "' entry '"', directory, , &pid)
        }
        macro.PID := pid
        macro.LastError := ""
        MacroList.Modify(row, , macro.Name, "Running", MacroTypeLabel(macro))
        MacroStatus.Text := "Started " macro.Name "."
        RefreshMacroButtons()
    }
    catch Error as err
    {
        ; A missing package runtime is a launcher installation problem, not
        ; a request for an arbitrary interpreter selected by the user.
        missingRuntime := InStr(err.Message, "Bundled AutoHotkey macro runtime missing") > 0
        macro.LastError := missingRuntime ? "Runtime missing" : "Launch failed"
        RefreshMacroButtons()
        MsgBox(missingRuntime
            ? "TES3NP's bundled AutoHotkey runtime is missing.`n`nRebuild or re-extract the complete TES3NP Windows package, keeping the runtime folder beside tes3np.exe."
            : "Could not run this tool. Check its installation.",
            "Run macro / app", "Icon!")
    }
}


StopSelectedMacro(*)
{
    global MacroItems, MacroList, MacroStatus
    row := MacroList.GetNext()
    if !row || row > MacroItems.Length
        return
    macro := MacroItems[row]
    if macro.PID && ProcessExist(macro.PID)
    {
        try ProcessClose(macro.PID)
    }
    RefreshMacroProcesses()
    MacroStatus.Text := "Stopped " macro.Name "."
}

RefreshMacroProcesses()
{
    global MacroItems, MacroList
    if !IsObject(MacroList)
        return
    for row, macro in MacroItems
        if macro.PID && !ProcessExist(macro.PID)
        {
            macro.PID := 0
            MacroList.Modify(row, , macro.Name,
                ValidMacroApplication(macro) ? "Ready" : "Missing", MacroTypeLabel(macro))
        }
    RefreshMacroButtons()
}

RemoveSelectedMacro(*)
{
    global MacroItems, MacroList, MacroStatus
    row := MacroList.GetNext()
    if !row || row > MacroItems.Length
        return
    macro := MacroItems[row]
    if macro.PID && ProcessExist(macro.PID)
        return
    if MsgBox("Remove " macro.Name " from Installed Macros? This does not uninstall linked applications.", "Remove macro / app", 0x124) != "Yes"
        return
    try
    {
        DirDelete(macro.Folder, true)
        MacroItems.RemoveAt(row)
        MacroList.Delete(row)
        global MacroScrollOffset
        if MacroItems.Length
            MacroList.Modify(Min(row, MacroItems.Length), "Select Focus")
        MacroScrollOffset := Min(MacroScrollOffset, Max(0, MacroItems.Length - 4))
        MacroStatus.Text := "Removed from launcher."
        RefreshMacroButtons()
    }
    catch
        MsgBox("Could not remove this macro package. Check that its files are not in use.", "Remove macro")
}

CleanupMacros()
{
    global MacroPage, MacroImport, MacroItems, CharacterPage
    SetTimer(CheckMacroImport, 0)
    SetTimer(RefreshMacroProcesses, 0)
    if IsObject(MacroImport)
    {
        if ProcessExist(MacroImport.PID)
            try ProcessClose(MacroImport.PID)
        if DirExist(MacroImport.Folder)
            try DirDelete(MacroImport.Folder, true)
    }
    ; Macro scripts remain launcher-owned; linked apps should remain running
    ; if the user closes TES3NP instead of being forcibly terminated.
    for macro in MacroItems
        if macro.Kind != "App" && macro.PID && ProcessExist(macro.PID)
            try ProcessClose(macro.PID)
    ; CharacterPage owns the shared UI. Do not destroy it here.
    if IsObject(MacroPage) && MacroPage != CharacterPage
        MacroPage.Destroy()
}

; Single scripts need no archive or manifest. Supporting files belong in a ZIP.
ImportMacroScript(source)
{
    global MacroRoot, MacroStatus
    staging := MacroRoot "\import-" FormatTime(, "yyyyMMddHHmmss") "-" A_TickCount
    try
    {
        DirCreate(staging)
        SplitPath(source, &filename)
        FileCopy(source, staging "\" filename)
        FileAppend("OK", staging "\.import-success")
        FinishMacroImport({Folder: staging, Archive: source})
    }
    catch
    {
        if DirExist(staging)
            try DirDelete(staging, true)
        MacroStatus.Text := "The script could not be imported."
        MsgBox("Could not copy this AutoHotkey script. Check that the file is readable.", "Import Macro")
    }
}
