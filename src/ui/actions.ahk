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
