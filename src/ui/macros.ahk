; Local macro packages. Import extracts files; only Run executes a chosen script.

OpenMacros(*)
{
    OpenCharacterPage()
}

BuildMacroBookPanel()
{
    global CharacterPage, LauncherMorrowindFont
    global MacroPage, MacroList, MacroDetails, MacroStatus, MacroEmptyNotice
    global MacroImportButton, MacroRunButton, MacroStopButton, MacroRemoveButton
    global MacroBindingsButton, MacroBookControls
    MacroPage := CharacterPage
    MacroBookControls := []
    CharacterPage.SetFont("s18 Norm c241408", LauncherMorrowindFont)
    heading := CharacterPage.Add("Text", "x525 y45 w355 h33 Center BackgroundTrans", "Installed Macros")
    CharacterPage.SetFont("s9 Norm c382314", "Segoe UI")
    explanation := CharacterPage.Add("Text", "x525 y88 w355 h43 BackgroundTrans",
        "Add a macro (.ahk or ZIP), or link an installed application (.exe). Run it here whenever you need it.")
    MacroEmptyNotice := CharacterPage.Add("Text", "x525 y155 w355 h34 BackgroundTrans",
        "you havent installed any macros.")
    MacroList := CharacterPage.Add("ListView", "x525 y144 w355 h226 -Multi BackgroundF0E3C5",
        ["Name", "Status", "Type"])
    MacroList.ModifyCol(1, 185), MacroList.ModifyCol(2, 90), MacroList.ModifyCol(3, 70)
    MacroList.OnEvent("ItemSelect", RefreshMacroButtons)
    MacroList.OnEvent("DoubleClick", RunSelectedMacro)
    MacroDetails := CharacterPage.Add("Text", "x525 y380 w355 h40 BackgroundTrans", "")
    MacroImportButton := CharacterPage.Add("Button", "x525 y430 w118 h29", "Add Macro / App")
    MacroRunButton := CharacterPage.Add("Button", "x649 y430 w47 h29 Disabled", "Run")
    MacroStopButton := CharacterPage.Add("Button", "x702 y430 w47 h29 Disabled", "Stop")
    MacroRemoveButton := CharacterPage.Add("Button", "x755 y430 w62 h29 Disabled", "Remove")
    MacroBindingsButton := CharacterPage.Add("Button", "x823 y430 w62 h29 Disabled", "Keys")
    MacroStatus := CharacterPage.Add("Text", "x525 y477 w355 h48 BackgroundTrans", "Ready.")
    MacroImportButton.OnEvent("Click", ImportMacroPackage)
    MacroRunButton.OnEvent("Click", RunSelectedMacro)
    MacroStopButton.OnEvent("Click", StopSelectedMacro)
    MacroRemoveButton.OnEvent("Click", RemoveSelectedMacro)
    MacroBindingsButton.OnEvent("Click", EditSelectedMacroBindings)
    MacroBookControls.Push(heading, explanation, MacroEmptyNotice, MacroList,
        MacroDetails, MacroImportButton, MacroRunButton, MacroStopButton,
        MacroRemoveButton, MacroBindingsButton, MacroStatus)
    LoadMacroPackages()
    ShowMacroBookPanel()
}

ShowMacroBookPanel()
{
    global MacroBookControls, MacroList, MacroEmptyNotice, MacroItems
    if !IsObject(MacroList)
        return
    for control in MacroBookControls
        control.Visible := true
    MacroList.Visible := MacroItems.Length > 0
    MacroEmptyNotice.Visible := MacroItems.Length = 0
    RefreshMacroProcesses()
}

HideMacroBookPanel()
{
    global MacroBookControls
    for control in MacroBookControls
        try control.Visible := false
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
        entry := IniRead(metadata, "Macro", "Entry", "")
        if !ValidMacroEntry(folder, entry)
            continue
        name := IniRead(metadata, "Macro", "Name", "Macro")
        description := IniRead(metadata, "Macro", "Description", "")
        pid := tracked.Has(folder) ? tracked[folder] : 0
        MacroItems.Push({Folder: folder, Entry: entry, Name: name, Description: description, PID: pid})
        MacroList.Add(, name, pid ? "Running" : "Ready", "Macro")
    }
    RefreshMacroButtons()
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
    row := MacroList.GetNext()
    selected := row > 0 && row <= MacroItems.Length
    running := selected && MacroItems[row].PID && ProcessExist(MacroItems[row].PID)
    busy := IsObject(MacroImport)
    MacroRunButton.Enabled := selected && !running && !busy
    MacroBindingsButton.Enabled := selected && !running && !busy && ReadMacroBindings(MacroItems[row]).Length > 0
    MacroStopButton.Enabled := running
    MacroRemoveButton.Enabled := selected && !running && !busy
    MacroDetails.Text := selected ? (MacroItems[row].Description != "" ? MacroItems[row].Description : "Script: " MacroItems[row].Entry) : (MacroItems.Length ? "Select a macro to run, stop, or remove it." : "")
    global MacroEmptyNotice, LaunchSettingsHeading
    MacroList.Visible := MacroItems.Length > 0 && !LaunchSettingsHeading.Visible
    MacroEmptyNotice.Visible := MacroItems.Length = 0 && !LaunchSettingsHeading.Visible
}

ImportMacroPackage(*)
{
    global MacroImport, MacroImportButton, MacroStatus, MacroRoot
    if IsObject(MacroImport)
        return
    archive := FileSelect(1, , "Import macro", "AutoHotkey scripts or ZIPs (*.ahk;*.zip)")
    if archive = ""
        return
    if RegExMatch(archive, "i)\.ahk$")
    {
        ImportMacroScript(archive)
        return
    }
    if !RegExMatch(archive, "i)\.zip$")
    {
        MsgBox("Choose an .ahk script or a ZIP containing scripts. Other archive formats are not supported yet.", "Import Macro")
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
    imported := {Folder: destination, Entry: entry, Name: name}
    if ReadMacroBindings(imported).Length
        ShowMacroBindings(imported)
    MacroStatus.Text := "Imported " name ". Select it and click Run."
}

AddImportedMacro(folder, name, description, entry)
{
    global MacroItems, MacroList
    MacroItems.Push({Folder: folder, Entry: entry, Name: name, Description: description, PID: 0})
    row := MacroList.Add(, name, "Ready", "Macro")
    MacroList.Modify(row, "Select Focus Vis")
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
    if MsgBox("Run " macro.Name "? Imported macros execute code on your computer. Only run a package you trust.", "Run macro", 0x124) != "Yes"
        return
    if ReadMacroBindings(macro).Length && !MacroBindingsReady(macro)
        if !ShowMacroBindings(macro)
            return
    interpreter := A_IsCompiled ? A_ScriptDir "\runtime\AutoHotkey64.exe" : A_AhkPath
    if !FileExist(interpreter)
    {
        interpreter := FileSelect(1, , "Choose AutoHotkey executable for this macro", "AutoHotkey (*.exe)")
        if interpreter = ""
            return
    }
    try
    {
        entry := macro.Folder "\" macro.Entry
        if !ValidMacroEntry(macro.Folder, macro.Entry)
            throw Error("Script no longer exists")
        SplitPath(entry, , &workingDirectory)
        ; Child scripts inherit the configuration path. Restore the launcher environment.
        previousBindings := EnvGet("TES3NP_BINDINGS")
        try
        {
            EnvSet("TES3NP_BINDINGS", ReadMacroBindings(macro).Length ? MacroBindingsPath(macro) : "")
            Run('"' interpreter '" "' entry '"', workingDirectory, , &pid)
        }
        finally EnvSet("TES3NP_BINDINGS", previousBindings)
        macro.PID := pid
        MacroList.Modify(row, , macro.Name, "Running", "Macro")
        MacroStatus.Text := "Started " macro.Name ". Its own hotkeys and controls remain active."
        RefreshMacroButtons()
    }
    catch
        MsgBox("Could not run this macro. Check its script and AutoHotkey version.", "Run macro")
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
    for row, macro in MacroItems
        if macro.PID && !ProcessExist(macro.PID)
        {
            macro.PID := 0
            MacroList.Modify(row, , macro.Name, "Ready", "Macro")
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
    if MsgBox("Remove " macro.Name " from your installed macros? The original ZIP is kept.", "Remove macro", 0x124) != "Yes"
        return
    try
    {
        DirDelete(macro.Folder, true)
        MacroItems.RemoveAt(row)
        MacroList.Delete(row)
        MacroStatus.Text := "Macro removed."
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
    ; Imported macros are owned sessions; stop only their tracked processes.
    for macro in MacroItems
        if macro.PID && ProcessExist(macro.PID)
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
