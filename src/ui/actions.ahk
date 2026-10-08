; Front-page actions. Game-session behavior lives in game/session.ahk.
OpenCharacters(*)
{
    OpenCharacterPage()
}

OpenWiki(*)
{
    try Run(AppConfig.Wiki)
    catch Error as err
        MsgBox("Could not open your web browser.", "tes3np")
}

QuitLauncher(*)
{
    ExitApp()
}

; Styled companion window. Discord channel messages require an authorized
; server-side feed; never collect or store a personal Discord user token.
global InGameChatGui := false

OpenInGameChatWindow(*)
{
    global InGameChatGui, LauncherGui, LauncherMorrowindFont
    if IsObject(InGameChatGui)
    {
        try
        {
            InGameChatGui.Show()
            WinActivate("ahk_id " InGameChatGui.Hwnd)
            return
        }
        catch
            InGameChatGui := false
    }
    chat := Gui("+Resize +MinSize390x380", "tes3np — In-Game Chat")
    chat.BackColor := "E2CEA2"
    chat.SetFont("s17 Norm c382314", LauncherMorrowindFont)
    chat.Add("Text", "x18 y15 w410 h32", "Nerevarine Prophecies")
    chat.SetFont("s11 Norm c382314", LauncherMorrowindFont)
    chat.Add("Text", "x18 y51 w410 h25", "In-Game Chat")
    chat.Add("Text", "x18 y88 w410 h265 +Border BackgroundFFFFFF", "")
    chat.Add("Text", "x34 y112 w380 h75 BackgroundTrans", "Live messages are not connected yet.")
    chat.Add("Text", "x34 y191 w380 h105 BackgroundTrans", "Discord requires an authorized message feed. This preview does not read your Discord account or use a user token.")
    open := chat.Add("Button", "x18 y369 w190 h34", "Open Channel in Discord")
    open.OnEvent("Click", OpenInGameDiscordChannel)
    close := chat.Add("Button", "x310 y369 w118 h34", "Close")
    close.OnEvent("Click", (*) => chat.Destroy())
    chat.OnEvent("Close", (*) => (InGameChatGui := false))
    chat.OnEvent("Escape", (*) => chat.Destroy())
    chat.OnEvent("Size", ResizeInGameChatWindow)
    InGameChatGui := chat
    chat.Show("w448 h422")
}

ResizeInGameChatWindow(guiObj, minMax, width, height)
{
    if minMax = -1
        return
    for control in guiObj
    {
        try
        {
            if control.Type = "Text"
            {
                control.GetPos(&x, &y, &w, &h)
                if y = 88
                    control.Move(, , width - 38, height - 157)
                else if y = 112 || y = 191
                    control.Move(, , width - 68)
            }
            else if control.Type = "Button"
            {
                control.GetPos(&x, &y, &w, &h)
                control.Move(x > 250 ? width - 138 : 18, height - 53)
            }
        }
    }
}

OpenInGameDiscordChannel(*)
{
    try Run("https://discord.com/channels/509601787901116437/1384271857842130994")
    catch
        MsgBox("Could not open the Discord channel.", "tes3np", "Icon!")
}
