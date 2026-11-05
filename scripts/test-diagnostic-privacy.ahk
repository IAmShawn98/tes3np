#Requires AutoHotkey v2.0
#SingleInstance Off
; Disposable privacy tests. Never read real launcher data or Discord history.
global AppDataDirectory := A_Temp "\tes3np-privacy-fixture-" A_TickCount
global DataFile := AppDataDirectory "\settings.ini"
global Profiles := [{Name: "TestWizard", Password: "test-only-secret-123"}]
#Include ..\src\app\diagnostics.ahk

PrivacyFixtureAssert(ok, reason)
{
    if !ok
        throw Error("Privacy fixture failed: " reason)
}



try
{
    DirCreate(AppDataDirectory)
    input := "GAME | Character: TestWizard | Executable: C:\Users\ExamplePerson\tes3mp.exe"
        . " | Password: test-only-secret-123 | Mail: sample@example.org"
        . " | URL: https://example.org/private?token=abc"
    safe := SanitizeDiagnosticText(input)
    PrivacyFixtureAssert(InStr(safe, "TestWizard"), "public character name preserved")
    PrivacyFixtureAssert(!InStr(safe, "ExamplePerson"), "Windows path hidden")
    PrivacyFixtureAssert(!InStr(safe, "test-only-secret-123"), "password value hidden")
    PrivacyFixtureAssert(!InStr(safe, "sample@example.org"), "email hidden")
    PrivacyFixtureAssert(!InStr(safe, "https://example.org"), "URL hidden")
    PrivacyFixtureAssert(InStr(safe, "[path omitted]"), "path redaction marker present")

    FileAppend(input "`n", AppDataDirectory "\launcher.log", "UTF-8")
    FileAppend(input "`n", AppDataDirectory "\chat-host.log", "UTF-8")
    DirCreate(AppDataDirectory "\Logs")
    privateArchive := "Yagrum: genuine Happy Hour announcement [discord:123456789012345678]"
    FileAppend(privateArchive, AppDataDirectory "\Logs\game-chat.log", "UTF-8")
    SanitizeExistingDiagnosticLogs()
    PrivacyFixtureAssert(!InStr(FileRead(LauncherLogFile, "UTF-8"), "ExamplePerson"),
        "legacy launcher log cleaned")
    PrivacyFixtureAssert(!InStr(FileRead(AppDataDirectory "\chat-host.log", "UTF-8"),
        "test-only-secret-123"), "legacy Chat Host log cleaned")
    PrivacyFixtureAssert(FileRead(AppDataDirectory "\Logs\game-chat.log", "UTF-8")
        = privateArchive, "private chat archive not modified")
    PrivacyFixtureAssert(IniRead(DataFile, "Diagnostics", "PrivacyScrubVersion", "") = "1",
        "one-time migration checkpoint written")
    FileAppend("PASS | TES3NP diagnostic redaction fixtures`n", "*", "UTF-8")
}
catch Error as err
{
    FileAppend("FAIL | TES3NP diagnostic redaction fixtures: " err.Message "`n", "*", "UTF-8")
    ExitApp(1)
}
finally
{
    try DirDelete(AppDataDirectory, true)
}
ExitApp(0)
