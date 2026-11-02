; Local macro packages. Import extracts files; only Run executes a chosen script.

BuildMacroBookPanel()
{
    global CharacterPage, LauncherMorrowindFont, ButtonFaces
    global MacroPage, MacroList, MacroDetails, MacroStatus, MacroEmptyNotice
    global MacroImportButton, MacroRunButton, MacroStopButton, MacroRemoveButton
    global MacroBindingsButton, MacroBookControls, MacroBookRows
    global MacroPreviousButton, MacroNextButton, MacroPageLabel
    MacroPage := CharacterPage
    MacroBookControls := []
    MacroBookRows := []
    CharacterPage.SetFont("s19 Norm c241408", LauncherMorrowindFont)
    heading := CharacterPage.Add("Text", "x525 y45 w355 h32 Center BackgroundTrans", "Installed Macros")
    CharacterPage.SetFont("s11 Norm c241408", LauncherMorrowindFont)
    explanation := CharacterPage.Add("Text", "x525 y87 w355 h45 BackgroundTrans",
        "Add an AutoHotkey macro (.ahk or ZIP) or link an application (.exe). Select a tool to run it.")
    nameHeading := AddBookLabel(CharacterPage, 525, 143, 206, 22, "Macro / Application")
    stateHeading := AddBookLabel(CharacterPage, 740, 143, 80, 22, "Status")
    typeHeading := AddBookLabel(CharacterPage, 824, 143, 55, 22, "Type")
    MacroEmptyNotice := CharacterPage.Add("Text", "x525 y175 w355 h30 BackgroundTrans",
        "you havent installed any macros.")
    ; The legacy ListView remains an invisible selection/data model so all
    ; tested import, run, stop, remove and binding handlers stay unchanged.
    ; Only the visible list is replaced with the launcher-painted book rows.
    MacroList := CharacterPage.Add("ListView", "x525 y144 w355 h226 Hidden -Multi",
        ["Name", "Status", "Type"])
    MacroList.OnEvent("ItemSelect", RefreshMacroButtons)
    MacroBookControls.Push(heading, explanation, nameHeading, stateHeading, typeHeading,
        MacroEmptyNotice, MacroList)
    Loop 5
    {
        position := A_Index
        y := 167 + (position - 1) * 34
        select := AddStyledButton(CharacterPage, 525, y, 207, 29, "",
            SelectMacroBookRow.Bind(position))
        ButtonFaces[select.Hwnd].MacroSelected := false
        CharacterPage.SetFont("s10 Norm c241408", LauncherMorrowindFont)
        status := AddBookLabel(CharacterPage, 741, y + 2, 78, 25, "")
        kind := AddBookLabel(CharacterPage, 824, y + 2, 56, 25, "")
        MacroBookRows.Push({Select: select, Status: status, Kind: kind})
        MacroBookControls.Push(select, status, kind)
    }
    MacroPreviousButton := AddStyledButton(CharacterPage, 525, 343, 88, 26,
        "Previous", PreviousMacroBookPage)
    CharacterPage.SetFont("s10 Norm c241408", LauncherMorrowindFont)
    MacroPageLabel := AddBookLabel(CharacterPage, 623, 343, 150, 26, "")
    MacroNextButton := AddStyledButton(CharacterPage, 792, 343, 88, 26,
        "Next", NextMacroBookPage)
    CharacterPage.SetFont("s10 Norm c241408", LauncherMorrowindFont)
    MacroDetails := AddBookLabel(CharacterPage, 525, 377, 355, 26, "")
    MacroImportButton := AddStyledButton(CharacterPage, 525, 410, 164, 30,
        "Add Macro / App", ImportMacroPackage)
    MacroRunButton := AddStyledButton(CharacterPage, 696, 410, 88, 30,
        "Run", RunSelectedMacro)
    MacroStopButton := AddStyledButton(CharacterPage, 791, 410, 89, 30,
        "Stop", StopSelectedMacro)
    MacroRemoveButton := AddStyledButton(CharacterPage, 525, 446, 164, 30,
        "Remove", RemoveSelectedMacro)
    MacroBindingsButton := AddStyledButton(CharacterPage, 696, 446, 184, 30,
        "Edit Keys", EditSelectedMacroBindings)
    CharacterPage.SetFont("s10 Norm c241408", LauncherMorrowindFont)
    MacroStatus := AddBookLabel(CharacterPage, 525, 488, 355, 27, "Ready.")
    MacroBookControls.Push(MacroPreviousButton, MacroPageLabel, MacroNextButton,
        MacroDetails, MacroImportButton, MacroRunButton, MacroStopButton,
        MacroRemoveButton, MacroBindingsButton, MacroStatus)
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
    for control in MacroBookControls
        try control.Visible := false
}

RefreshMacroBookRows()
{
    global MacroList, MacroItems, MacroBookRows, MacroListPage
    global MacroEmptyNotice, MacroPreviousButton, MacroNextButton, MacroPageLabel
    global MacroDetails, MacroImportButton, MacroRunButton, MacroStopButton
    global MacroRemoveButton, MacroBindingsButton, MacroStatus
    global LaunchSettingsHeading, ButtonFaces
    if !IsObject(MacroList) || !MacroBookRows.Length
        return
    count := MacroItems.Length
    pages := Max(1, Ceil(count / 5))
    MacroListPage := Max(1, Min(MacroListPage, pages))
    shown := !LaunchSettingsHeading.Visible
    selectedIndex := MacroList.GetNext()
    ; The data/selection ListView must never paint over the book artwork.
    MacroList.Visible := false
    for position, itemRow in MacroBookRows
    {
        index := (MacroListPage - 1) * 5 + position
        visible := shown && index <= count
        itemRow.Select.Visible := visible
        itemRow.Status.Visible := visible
        itemRow.Kind.Visible := visible
        if !visible
            continue
        item := MacroItems[index]
        name := SubStr(item.Name, 1, 27)
        if itemRow.Select.Text != name
            itemRow.Select.Text := name
        status := !ValidMacroApplication(item) ? "Missing"
            : (item.PID && ProcessExist(item.PID) ? "Running" : "Ready")
        if itemRow.Status.Text != status
            itemRow.Status.Text := status
        if itemRow.Kind.Text != MacroTypeLabel(item)
            itemRow.Kind.Text := MacroTypeLabel(item)
        selected := index = selectedIndex
        if ButtonFaces[itemRow.Select.Hwnd].MacroSelected != selected
        {
            ButtonFaces[itemRow.Select.Hwnd].MacroSelected := selected
            DllCall("InvalidateRect", "Ptr", itemRow.Select.Hwnd, "Ptr", 0, "Int", 0)
        }
    }
    MacroEmptyNotice.Visible := shown && count = 0
    paging := shown && pages > 1
    MacroPreviousButton.Visible := paging
    MacroNextButton.Visible := paging
    MacroPageLabel.Visible := paging
    MacroPreviousButton.Enabled := MacroListPage > 1
    MacroNextButton.Enabled := MacroListPage < pages
    if paging
        MacroPageLabel.Text := "Page " MacroListPage " of " pages
    displayed := Min(5, Max(0, count - (MacroListPage - 1) * 5))
    bottom := count ? 167 + displayed * 34 : 205
    if pages > 1
    {
        MoveStyledButton(MacroPreviousButton, 525, bottom + 5, 88, 26)
        MoveStyledButton(MacroPageLabel, 623, bottom + 5, 150, 26)
        MoveStyledButton(MacroNextButton, 792, bottom + 5, 88, 26)
        bottom += 33
    }
    detailY := bottom + 4
    MoveStyledButton(MacroDetails, 525, detailY, 355, 26)
    MacroDetails.Visible := shown && count > 0
    actionY := count ? detailY + 30 : 217
    MoveStyledButton(MacroImportButton, 525, actionY, 164, 30)
    MoveStyledButton(MacroRunButton, 696, actionY, 88, 30)
    MoveStyledButton(MacroStopButton, 791, actionY, 89, 30)
    MoveStyledButton(MacroRemoveButton, 525, actionY + 36, 164, 30)
    MoveStyledButton(MacroBindingsButton, 696, actionY + 36, 184, 30)
    MoveStyledButton(MacroStatus, 525, actionY + 76, 355, 27)
}

SelectMacroBookRow(position, *)
{
    global MacroList, MacroListPage, MacroItems
    index := (MacroListPage - 1) * 5 + position
    if index < 1 || index > MacroItems.Length
        return
    MacroList.Modify(index, "Select Focus")
    RefreshMacroButtons()
}

PreviousMacroBookPage(*)
{
    global MacroListPage
    MacroListPage := Max(1, MacroListPage - 1)
    RefreshMacroButtons()
}

NextMacroBookPage(*)
{
    global MacroListPage, MacroItems
    MacroListPage := Min(Max(1, Ceil(MacroItems.Length / 5)), MacroListPage + 1)
    RefreshMacroButtons()
}

CloseMacroPage(*)
{
    SetTimer(RefreshMacroProcesses, 0)
}


LoadMacroPackages()
{
    global MacroRoot, MacroItems, MacroList
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
    global MacroList, MacroItems, MacroRunButton, MacroStopButton, MacroRemoveButton, MacroDetails, MacroImport, MacroBindingsButton
    ; A stale timer or early editor callback must never read an integer here.
    if !IsObject(MacroList)
        return
    row := MacroList.GetNext()
    selected := row > 0 && row <= MacroItems.Length
    running := selected && MacroItems[row].PID && ProcessExist(MacroItems[row].PID)
    busy := IsObject(MacroImport)
    MacroRunButton.Enabled := selected && ValidMacroApplication(MacroItems[row])
        && !running && !busy
    MacroBindingsButton.Enabled := selected && ValidMacroApplication(MacroItems[row])
        && !running && !busy && ReadMacroBindings(MacroItems[row]).Length > 0
    MacroStopButton.Enabled := running
    MacroRemoveButton.Enabled := selected && !running && !busy
    description := selected ? (!ValidMacroApplication(MacroItems[row])
        ? "Application missing. Remove it and add it again."
        : (MacroItems[row].Description != "" ? MacroItems[row].Description
        : (MacroItems[row].Kind = "App" ? "Installed application" : "Script: " MacroItems[row].Entry)))
        : ""
    MacroDetails.Text := SubStr(description, 1, 58)
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
    global MacroItems, MacroList, MacroListPage
    MacroItems.Push({Folder: folder, Entry: entry, Name: name, Description: description,
        Kind: kind, Target: target, PID: 0})
    row := MacroList.Add(, name, "Ready", kind = "App" ? "App" : "Macro")
    MacroList.Modify(row, "Select Focus")
    MacroListPage := Ceil(row / 5)
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
        global MacroListPage
        if MacroItems.Length
            MacroList.Modify(Min(row, MacroItems.Length), "Select Focus")
        MacroListPage := MacroItems.Length ? Ceil(Min(row, MacroItems.Length) / 5) : 1
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
