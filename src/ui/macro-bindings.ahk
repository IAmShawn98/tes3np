; Declarative key bindings: importing never guesses actions or rewrites scripts.
MacroBindingsPath(macro)
{
    return macro.Folder "\.tes3np-bindings.ini"
}

ReadMacroBindings(macro)
{
    bindings := [], seen := Map()
    manifest := macro.Folder "\macro.ini"
    declarations := IniRead(manifest, "Bindings", , "")
    for line in StrSplit(declarations, "`n", "`r")
    {
        equals := InStr(line, "=")
        if !equals
            continue
        id := Trim(SubStr(line, 1, equals - 1))
        key := Trim(SubStr(line, equals + 1))
        label := IniRead(manifest, "BindingLabels", id, id)
        AddMacroBinding(bindings, seen, id, label, key)
    }
    ; Inline declarations also work for directly imported standalone scripts.
    if !bindings.Length && ValidMacroEntry(macro.Folder, macro.Entry)
        for line in StrSplit(FileRead(macro.Folder "\" macro.Entry, "UTF-8"), "`n", "`r")
            if RegExMatch(line, "^\s*;\s*@tes3np-key\s+([^|]+)\|([^|]+)\|([^|]+)\s*$", &match)
                AddMacroBinding(bindings, seen, Trim(match[1]), Trim(match[2]), Trim(match[3]))
    return bindings
}

AddMacroBinding(bindings, seen, id, label, key)
{
    if bindings.Length >= 12 || !RegExMatch(id, "^[A-Za-z][A-Za-z0-9_]{0,39}$") || seen.Has(id)
        return
    seen[id] := true
    bindings.Push({ID: id, Label: SubStr(label, 1, 100), Default: key})
}

ValidMacroBindingKey(key)
{
    if !RegExMatch(key, "^[A-Za-z0-9]+$")
        return false
    if key = "WheelUp" || key = "WheelDown" || key = "WheelLeft" || key = "WheelRight"
        return true
    return GetKeyVK(key) != 0 || GetKeySC(key) != 0
}

MacroBindingsReady(macro)
{
    path := MacroBindingsPath(macro)
    for binding in ReadMacroBindings(macro)
        if !ValidMacroBindingKey(IniRead(path, "Bindings", binding.ID, ""))
            return false
    return true
}

EditSelectedMacroBindings(*)
{
    global MacroItems, MacroList, MacroImport
    row := MacroList.GetNext()
    if !row || row > MacroItems.Length || IsObject(MacroImport)
        return
    macro := MacroItems[row]
    if macro.PID && ProcessExist(macro.PID)
        return
    ShowMacroBindings(macro)
}

ShowMacroBindings(macro)
{
    global MacroPage
    bindings := ReadMacroBindings(macro)
    if !bindings.Length
        return false
    result := {Saved: false}, fields := []
    dialog := Gui("+Owner" MacroPage.Hwnd " -MinimizeBox -MaximizeBox", macro.Name " — Key Bindings")
    dialog.BackColor := "E2CEA2"
    dialog.SetFont("s10 c382314", "Segoe UI")
    dialog.Add("Text", "x20 y15 w480 h45", "Choose the keys this macro will press. Match your in-game controls. Use a single key such as C, Ctrl, F1, or 2.")
    for index, binding in bindings
    {
        y := 70 + (index - 1) * 38
        dialog.Add("Text", "x20 y" y " w310 h28", binding.Label)
        value := IniRead(MacroBindingsPath(macro), "Bindings", binding.ID, binding.Default)
        fields.Push(dialog.Add("Edit", "x340 y" y " w160 h25", value))
    }
    y := 75 + bindings.Length * 38
    save := dialog.Add("Button", "x280 y" y " w100 h30 Default", "Save")
    cancel := dialog.Add("Button", "x400 y" y " w100 h30", "Cancel")
    save.OnEvent("Click", SaveMacroBindings.Bind(dialog, macro, bindings, fields, result))
    cancel.OnEvent("Click", (*) => dialog.Hide())
    dialog.OnEvent("Close", (*) => dialog.Hide())
    dialog.OnEvent("Escape", (*) => dialog.Hide())
    dialog.Opt("+OwnDialogs")
    MacroPage.Opt("+Disabled")
    try
    {
        dialog.Show("w520 h" (y + 50))
        WinWaitClose("ahk_id " dialog.Hwnd)
    }
    finally
    {
        MacroPage.Opt("-Disabled")
        dialog.Destroy()
    }
    return result.Saved
}

SaveMacroBindings(dialog, macro, bindings, fields, result, *)
{
    global MacroStatus
    values := []
    for index, binding in bindings
    {
        key := Trim(fields[index].Value)
        if !ValidMacroBindingKey(key)
        {
            MsgBox("Choose a valid single key for " binding.Label ".", "Key Bindings", "Icon!")
            fields[index].Focus()
            return
        }
        values.Push(key)
    }
    path := MacroBindingsPath(macro), staging := path ".tmp"
    try
    {
        if FileExist(staging)
            FileDelete(staging)
        for index, binding in bindings
            IniWrite(values[index], staging, "Bindings", binding.ID)
        FileMove(staging, path, true)
        result.Saved := true
        MacroStatus.Text := "Saved bindings for " macro.Name "."
        dialog.Hide()
    }
    catch
    {
        if FileExist(staging)
            try FileDelete(staging)
        MsgBox("Could not save macro bindings. Your previous settings have been kept.", "Key Bindings", "Icon!")
    }
}
