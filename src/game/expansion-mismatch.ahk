; Detect TES3MP's actual plugin/load-order rejection from NEW log output only.
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
                if InStr(text, "Your plugins or their load order don't match the server's")
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
    global LauncherGui
    ShowLauncherWindow(true)
    dialog := Gui("+Owner" LauncherGui.Hwnd " -MaximizeBox -MinimizeBox", "tes3np - Expansion Pack")
    dialog.BackColor := "1B140B"
    dialog.SetFont("s17 Bold cC5A45C", "Georgia")
    dialog.Add("Text", "x25 y22 w630 h35 BackgroundTrans", "Expansion Pack May Need Updating")
    dialog.SetFont("s11 Norm cEDE1C9", "Segoe UI")
    dialog.Add("Text", "x25 y75 w630 h105 BackgroundTrans",
        "TES3MP could not join because your installed plugins or load order do not match the server. "
        . "This can happen when Nerevarine Prophecies releases a new Expansion Pack, "
        . "or when game files, other mods, or the load order differ from what the server requires.")
    dialog.Add("Text", "x25 y188 w630 h58 BackgroundTrans",
        "Please check the Nerevarine Prophecies Discord server for a possible Expansion Pack update. "
        . "If there is an update, download it first and click Upload Expansion below.")
    AddStyledButton(dialog, 263, 262, 205, 38, "Upload Expansion", (*) => (dialog.Destroy(), UploadExpansionFromFile()))
    AddStyledButton(dialog, 486, 262, 145, 38, "Cancel", (*) => dialog.Destroy())
    dialog.OnEvent("Close", (*) => dialog.Destroy())
    dialog.OnEvent("Escape", (*) => dialog.Destroy())
    dialog.Show("w660 h318")
}
