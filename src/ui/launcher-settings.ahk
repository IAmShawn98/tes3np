; Launcher-specific display settings.

global LauncherScale := 100

LoadLauncherScale()
{
    global DataFile, LauncherScale
    saved := IniRead(DataFile, "Launcher", "Scale", "100")
    LauncherScale := RegExMatch(saved, "^(?:50|60|70|80|90|100)$") ? Integer(saved) : 100
}

OpenLauncherSettings(*)
{
    global LauncherGui, LauncherScale
    settings := Gui("+Owner" LauncherGui.Hwnd " -MinimizeBox -MaximizeBox", "tes3np — Launcher Settings")
    settings.BackColor := "E2CEA2"
    settings.SetFont("s11 c382314", "Segoe UI")
    settings.Add("Text", "x20 y18 w330 h26", "Launcher Scale")
    settings.SetFont("s9 c382314", "Segoe UI")
    settings.Add("Text", "x20 y48 w330 h38", "Reduce the launcher size on smaller displays. The setting is remembered for future launches.")
    settings.SetFont("s10 c382314", "Segoe UI")
    scaleList := settings.Add("DropDownList", "x20 y96 w330 Choose" ScaleChoiceIndex(LauncherScale), ["50%", "60%", "70%", "80%", "90%", "100%"])
    apply := settings.Add("Button", "x20 y142 w158 h34 Default", "Apply")
    cancel := settings.Add("Button", "x192 y142 w158 h34", "Cancel")
    apply.OnEvent("Click", ApplyLauncherScale.Bind(settings, scaleList))
    cancel.OnEvent("Click", (*) => settings.Destroy())
    settings.OnEvent("Escape", (*) => settings.Destroy())
    settings.Show("w370 h196")
}

ScaleChoiceIndex(scale)
{
    return Max(1, Min(6, ((scale - 50) // 10) + 1))
}

ApplyLauncherScale(settings, scaleList, *)
{
    global LauncherScale, DataFile
    LauncherScale := Integer(StrReplace(scaleList.Text, "%"))
    DirCreate(AppDataDirectory)
    IniWrite(LauncherScale, DataFile, "Launcher", "Scale")
    settings.Destroy()
    ApplyLauncherScaleToWindow()
}

ApplyLauncherScaleToWindow()
{
    global LauncherGui, LauncherScale
    scale := LauncherScale / 100
    width := Round(960 * scale)
    height := Round(716 * scale)
    ; AutoHotkey keeps child controls in logical DPI coordinates. Scaling the top-level
    ; window through SetWindowPos lets Windows scale the composed launcher consistently.
    DllCall("SetWindowPos", "Ptr", LauncherGui.Hwnd, "Ptr", 0, "Int", 0, "Int", 0,
        "Int", width, "Int", height, "UInt", 0x0002 | 0x0004 | 0x0010)
}
