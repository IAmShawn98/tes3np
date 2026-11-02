; Local macro packages. Import extracts files; only Run executes a chosen script.

BuildMacroBookPanel()
{
    global CharacterPage, LauncherMorrowindFont
    global MacroPage, MacroList, MacroDetails, MacroStatus, MacroEmptyNotice
    global MacroImportButton, MacroBindingsButton, MacroBookControls, MacroBookRows
    global MacroScrollOffset, MacroScrollTrack, MacroScrollThumb, MacroScrollDragging, MacroScrollGrab
    MacroPage := CharacterPage
    MacroBookControls := []
    MacroBookRows := []
    MacroScrollOffset := 0
    MacroScrollDragging := false
    MacroScrollGrab := 0
    CharacterPage.SetFont("s19 Norm c241408", LauncherMorrowindFont)
    heading := CharacterPage.Add("Text", "x525 y45 w355 h32 Center BackgroundTrans", "Installed Macros")
    CharacterPage.SetFont("s11 Norm c241408", LauncherMorrowindFont)
    explanation := CharacterPage.Add("Text", "x525 y87 w355 h65 BackgroundTrans",
        "This is a list of your installed macros and apps. Select one to edit its keys, or use the buttons beside it to run, stop, or remove it.")
    MacroEmptyNotice := CharacterPage.Add("Text", "x551 y181 w329 h30 BackgroundTrans",
        "No macros installed yet.")
    ; Retain the invisible ListView as the tested selection/data model.
    MacroList := CharacterPage.Add("ListView", "x525 y144 w355 h226 Hidden -Multi",
        ["Name", "Status", "Type"])
    MacroList.OnEvent("ItemSelect", RefreshMacroButtons)
    MacroBookControls.Push(heading, explanation, MacroEmptyNotice, MacroList)
    ; Match Your Characters: select tick, name, three inline action buttons.
    ; The same ten 24-pixel-spaced book rows begin at y180.
    Loop 10
    {
        position := A_Index
        y := 180 + (position - 1) * 24
        tick := AddBookTick(CharacterPage, 525, y + 2, SelectMacroBookRow.Bind(position))
        CharacterPage.SetFont("s12 Norm c241408", LauncherMorrowindFont)
        name := AddBookLabel(CharacterPage, 551, y, 149, 23, "")
        name.Opt("+0x100")
        name.OnEvent("Click", SelectMacroBookRow.Bind(position))
        run := AddStyledButton(CharacterPage, 705, y, 50, 22, "Run", RunMacroBookRow.Bind(position))
        stop := AddStyledButton(CharacterPage, 760, y, 50, 22, "Stop", StopMacroBookRow.Bind(position))
        remove := AddStyledButton(CharacterPage, 815, y, 65, 22, "Remove", RemoveMacroBookRow.Bind(position))
        MacroBookRows.Push({Tick: tick, Name: name, Run: run, Stop: stop, Remove: remove})
        MacroBookControls.Push(tick, name, run, stop, remove)
    }
    ; Exactly ten visible rows; the viewport scrolls through any number of
    ; installed macros without discarding or paging the hidden selection model.
    MacroScrollTrack := CharacterPage.Add("Text",
        "x887 y180 w8 h238 Background704C27 +0x100 Hidden")
    MacroScrollThumb := CharacterPage.Add("Text",
        "x888 y180 w6 h40 BackgroundC69951 +0x100 Hidden")
    CharacterPage.SetFont("s10 Norm c241408", LauncherMorrowindFont)
    ; Painted labels at the right book flap sample unrelated background art.
    ; Use the same native transparent Text controls as the left description.
    CharacterPage.SetFont("s10 Norm c241408", LauncherMorrowindFont)
    MacroDetails := CharacterPage.Add("Text",
        "x525 y432 w355 h24 BackgroundTrans c241408 +0x100", "")
    MacroStatus := CharacterPage.Add("Text",
        "x525 y475 w355 h24 BackgroundTrans c241408 +0x100", "Ready.")
    MacroImportButton := AddStyledButton(CharacterPage, 525, 508, 355, 28,
        "Add Macro / App", ImportMacroPackage)
    MacroBindingsButton := AddStyledButton(CharacterPage, 525, 543, 355, 28,
        "Edit Selected Macro Keys", EditSelectedMacroBindings)
    MacroBookControls.Push(MacroScrollTrack, MacroScrollThumb,
        MacroDetails, MacroStatus, MacroImportButton, MacroBindingsButton)
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

RefreshMacroBookRows()
{
    global MacroList, MacroItems, MacroBookRows, MacroScrollOffset, MacroImport
    global MacroEmptyNotice, MacroScrollTrack, MacroScrollThumb
    global MacroDetails, MacroStatus, LaunchSettingsHeading, ButtonFaces, CharacterPage
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
        ; Polling process state must not toggle unchanged GUI visibility:
        ; that causes unnecessary repaints over the parchment book.
        for control in [itemRow.Tick, itemRow.Name, itemRow.Run, itemRow.Stop, itemRow.Remove]
            if control.Visible != visible
                control.Visible := visible
        if !visible
            continue
        item := MacroItems[index]
        ; Keep longer names from bleeding into the Run button.
        name := StrLen(item.Name) > 20 ? SubStr(item.Name, 1, 17) "..." : item.Name
        if itemRow.Name.Text != name
            itemRow.Name.Text := name
        selected := index = selectedIndex
        if ButtonFaces[itemRow.Tick.Hwnd].Checked != selected
            SetBookTick(itemRow.Tick, selected)
        running := item.PID && ProcessExist(item.PID)
        canRun := ValidMacroApplication(item) && !running && !busy
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
        thumbHeight := Max(25, Round(238 * MacroBookRows.Length / count))
        travel := 238 - thumbHeight
        thumbY := 180 + Round(MacroScrollOffset / maximum * travel)
        MacroScrollThumb.Move(888, thumbY, 6, thumbHeight)
    }
    ; Keep the details and status directly beneath the final visible row
    ; instead of leaving a large empty gap with only one installed macro.
    ; The last of ten rows ends at y418, and its details/status still fit
    ; above the permanently anchored Add Macro / App button at y508.
    visibleCount := Min(MacroBookRows.Length, Max(0, count - MacroScrollOffset))
    detailsY := 180 + visibleCount * 24 + 18
    statusY := detailsY + 28
    MacroDetails.GetPos(, &oldDetailsY)
    MacroStatus.GetPos(, &oldStatusY)
    needsRepaint := false
    if oldDetailsY != detailsY
    {
        MacroDetails.Move(525, detailsY, 355, 24)
        needsRepaint := true
    }
    if oldStatusY != statusY
    {
        MacroStatus.Move(525, statusY, 355, 24)
        needsRepaint := true
    }
    ; Native transparent Text controls need the old parchment area redrawn
    ; when moved. This runs on actual row-count changes, not each timer tick.
    if needsRepaint && shown
        DllCall("RedrawWindow", "Ptr", CharacterPage.Hwnd, "Ptr", 0,
            "Ptr", 0, "UInt", 0x385)
    MacroDetails.Visible := shown && selectedIndex > 0 && selectedIndex <= count
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
    scale := A_ScreenDPI / 96
    x := (x - NumGet(origin, 0, "Int")) / scale
    y := (y - NumGet(origin, 4, "Int")) / scale
    if x < 520 || x > 900 || y < 175 || y > 422
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
    localY := (pointerY - NumGet(origin, 4, "Int")) / (A_ScreenDPI / 96)
    MacroScrollThumb.GetPos(, &thumbY, , &thumbHeight)
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
    localY := (pointerY - NumGet(origin, 4, "Int")) / (A_ScreenDPI / 96)
    MacroScrollThumb.GetPos(, , , &thumbHeight)
    travel := Max(1, 238 - thumbHeight)
    maximum := Max(0, MacroItems.Length - MacroBookRows.Length)
    ScrollMacroBook(Round((localY - 180 - MacroScrollGrab) / travel * maximum))
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
    global MacroList, MacroItems, MacroDetails, MacroImport, MacroBindingsButton
    ; A stale timer or early editor callback must never read an integer here.
    if !IsObject(MacroList)
        return
    row := MacroList.GetNext()
    selected := row > 0 && row <= MacroItems.Length
    running := selected && MacroItems[row].PID && ProcessExist(MacroItems[row].PID)
    busy := IsObject(MacroImport)
    MacroBindingsButton.Enabled := selected && ValidMacroApplication(MacroItems[row])
        && !running && !busy && ReadMacroBindings(MacroItems[row]).Length > 0
    description := selected ? (!ValidMacroApplication(MacroItems[row])
        ? "Application missing. Remove it and add it again."
        : (MacroItems[row].Description != "" ? MacroItems[row].Description
        : (MacroItems[row].Kind = "App" ? "Installed application" : "Script: " MacroItems[row].Entry)))
        : ""
    ; Single-line fixed-width book label.
    MacroDetails.Text := SubStr(description, 1, 44)
    RefreshMacroBookRows()
}

ImportMacroPackage(*)
{
    global MacroImport, MacroImportButton, MacroStatus, MacroRoot
    if IsObject(MacroImport)
        return
    archive := FileSelect(1, , "Add macro or application",
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
        MsgBox("Choose an .ahk script, ZIP containing scripts, or installed .exe.", "Add Macro / App")
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
        detail := RegExReplace(err.Message, "i)[A-Z]:\\[^`r`n]+", "[path omitted]")
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
    imported := {Folder: destination, Entry: entry, Name: name, Kind: "Macro"}
    if ReadMacroBindings(imported).Length
        ShowMacroBindings(imported)
    MacroStatus.Text := "Imported " name ". Select it and click Run."
}

AddImportedMacro(folder, name, description, entry, kind := "Macro", target := "")
{
    global MacroItems, MacroList, MacroScrollOffset
    MacroItems.Push({Folder: folder, Entry: entry, Name: name, Description: description,
        Kind: kind, Target: target, PID: 0})
    row := MacroList.Add(, name, "Ready", kind = "App" ? "App" : "Macro")
    MacroList.Modify(row, "Select Focus")
    MacroScrollOffset := Max(0, row - 10)
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
        MsgBox("Could not register that application.", "Add Macro / App")
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
        chooser.Show("w500 h165")
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
    if MsgBox("Run " macro.Name "? This tool executes code on your computer. Only run files you trust.", "Run macro / app", 0x124) != "Yes"
        return
    if ReadMacroBindings(macro).Length && !MacroBindingsReady(macro)
        if !ShowMacroBindings(macro)
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
            {
                interpreter := FileSelect(1, , "Choose AutoHotkey executable for this macro",
                    "AutoHotkey (*.exe)")
                if interpreter = ""
                    return
            }
            entry := macro.Folder "\" macro.Entry
            if !ValidMacroEntry(macro.Folder, macro.Entry)
                throw Error("Script no longer exists")
            SplitPath(entry, , &directory)
            ; Child AHK scripts inherit only their own key-binding configuration.
            previousBindings := EnvGet("TES3NP_BINDINGS")
            try
            {
                EnvSet("TES3NP_BINDINGS", ReadMacroBindings(macro).Length
                    ? MacroBindingsPath(macro) : "")
                Run('"' interpreter '" "' entry '"', directory, , &pid)
            }
            finally EnvSet("TES3NP_BINDINGS", previousBindings)
        }
        macro.PID := pid
        MacroList.Modify(row, , macro.Name, "Running", MacroTypeLabel(macro))
        MacroStatus.Text := "Started " macro.Name "."
        RefreshMacroButtons()
    }
    catch
        MsgBox("Could not run this tool. Check its installation.", "Run macro / app")
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
        MacroScrollOffset := Min(MacroScrollOffset, Max(0, MacroItems.Length - 10))
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
