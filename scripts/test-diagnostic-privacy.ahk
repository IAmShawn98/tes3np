#Requires AutoHotkey v2.0
#SingleInstance Off
; Disposable privacy tests. Never read real launcher data or Discord history.
global AppDataDirectory := A_Temp "\tes3np-privacy-fixture-" A_TickCount
global DataFile := AppDataDirectory "\settings.ini"
global Profiles := [{Name: "TestWizard", Password: "test-only-secret-123"}]
global BundledResourceRoot := "", MacroRoot := AppDataDirectory "\macros"
global MacroImport := 0, PatchJob := 0, LauncherDataResetting := false
global Client := {Enabled: false}, ExpansionAutoDownloadActive := false
global ExpansionAutoInstallLocked := false, MorrowindPromptGui := 0
global ExpansionRecoveryRunning := false, ExpansionRecoveryPending := false
#Include ..\src\app\diagnostics.ahk
#Include ..\src\data\cleanup.ahk

PrivacyFixtureAssert(ok, reason)
{
    if !ok
        throw Error("Privacy fixture failed: " reason)
}



previousWindowsUser := EnvGet("USERNAME")
try
{
    EnvSet("USERNAME", "ExamplePerson")
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
    PrivacyFixtureAssert(safe = "GAME | Character: TestWizard",
        "private fields are removed without stray labels or separators")
    legacy := SanitizeDiagnosticText("2026-11-04 | GAME | Path: [path omitted] | URL: [url omitted] | Character: TestWizard")
    PrivacyFixtureAssert(legacy = "2026-11-04 | GAME | Character: TestWizard",
        "prior placeholder-style log entries are compacted")
    PrivacyFixtureAssert(!InStr(safe, "[") && !InStr(safe, "omitted"),
        "clean diagnostics contain no redaction notices")
    windowsName := SanitizeDiagnosticText("GAME | Windows session ExamplePerson | Character: TestWizard")
    PrivacyFixtureAssert(!InStr(windowsName, "ExamplePerson"),
        "standalone Windows account name excluded from diagnostics")
    PrivacyFixtureAssert(InStr(windowsName, "Character: TestWizard"),
        "public character name retained independently of Windows account name")
    sameName := SanitizeDiagnosticText("GAME | Character: ExamplePerson")
    PrivacyFixtureAssert(sameName = "GAME | Character: ExamplePerson",
        "character name retained even when identical to the Windows account")

    FileAppend(input "`n2026-11-04 | GAME | Path: [path omitted] | Character: TestWizard", AppDataDirectory "\launcher.log", "UTF-8")
    ; The first append must not join a previous log lacking its final newline.
    LogLauncherEvent("Fixture append after incomplete historical log.")
    PrivacyFixtureAssert(InStr(FileRead(LauncherLogFile, "UTF-8"), "Character: TestWizard`n"),
        "new events must start on a separate line even before migration")
    ; Reproduce historical v3-to-v4 migration damage from the uploaded log.
    FileAppend("2026-11-04 22:58:35 | Launcher startup beginning.2026-11-04 22:58:39 | UI | Launcher transition 2547ms.`n",
        AppDataDirectory "\launcher.log", "UTF-8")
    FileAppend(input "`n", AppDataDirectory "\chat-host.log", "UTF-8")
    DirCreate(AppDataDirectory "\Logs")
    privateArchive := "Yagrum: genuine Happy Hour announcement [discord:123456789012345678]"
    FileAppend(privateArchive, AppDataDirectory "\Logs\game-chat.log", "UTF-8")
    IniWrite("3", DataFile, "Diagnostics", "PrivacyScrubVersion")
    SanitizeExistingDiagnosticLogs()
    PrivacyFixtureAssert(!InStr(FileRead(LauncherLogFile, "UTF-8"), "ExamplePerson"),
        "legacy launcher log cleaned")
    PrivacyFixtureAssert(!InStr(FileRead(LauncherLogFile, "UTF-8"), "[path omitted]"),
        "previous redaction markers removed from historical logs")
    repaired := FileRead(LauncherLogFile, "UTF-8")
    PrivacyFixtureAssert(InStr(repaired, "Launcher startup beginning.`n2026-11-04 22:58:39"),
        "joined legacy diagnostic timestamps are separated")
    PrivacyFixtureAssert(SubStr(repaired, -1) = "`n",
        "migrated diagnostics end with a newline for future writes")
    PrivacyFixtureAssert(!InStr(FileRead(AppDataDirectory "\chat-host.log", "UTF-8"),
        "test-only-secret-123"), "legacy Chat Host log cleaned")
    PrivacyFixtureAssert(FileRead(AppDataDirectory "\Logs\game-chat.log", "UTF-8")
        = privateArchive, "private chat archive not modified")
    PrivacyFixtureAssert(IniRead(DataFile, "Diagnostics", "PrivacyScrubVersion", "") = "4",
        "one-time migration checkpoint written")

    FileAppend("CHAT HOST | Picker opened. | Token: fixture-only-token`n", AppDataDirectory "\chat-host.log", "UTF-8")
    FileAppend("EXPANSION | Installer ran.`n", AppDataDirectory "\patch-all.log", "UTF-8")
    FileAppend("RENDER | Frame painted.`n", AppDataDirectory "\render-errors.log", "UTF-8")
    FileAppend("unlisted log must stay private", AppDataDirectory "\unlisted.log", "UTF-8")
    report := ReadBugReportLog()
    PrivacyFixtureAssert(InStr(report, "===== launcher.log =====") = 1
        && InStr(report, "===== chat-host.log =====`nGAME")
        && InStr(report, "CHAT HOST | Picker opened.")
        && InStr(report, "===== patch-all.log =====`nEXPANSION | Installer ran.")
        && InStr(report, "===== render-errors.log =====`nRENDER | Frame painted."),
        "bug report combines the available diagnostic logs under source headings")
    PrivacyFixtureAssert(!InStr(report, "patch-errors.log") && !InStr(report, "fixture-only-token")
        && !InStr(report, "unlisted log must stay private") && !InStr(report, "genuine Happy Hour announcement"),
        "bug report skips missing logs and keeps secrets and other files out")

    largeLog := AppDataDirectory "\large-fixture.log"
    stream := FileOpen(largeLog, "w", "UTF-8")
    try
    {
        line := "Old diagnostic event " Chr(0x00E9) "`n"
        batch := ""
        Loop 256
            batch .= line
        while stream.Pos <= 2 * 1024 * 1024
            stream.Write(batch)
        stream.Write("Latest diagnostic event " Chr(0x00E9) "`n")
    }
    finally stream.Close()
    PrivacyFixtureAssert(TrimDiagnosticLog(largeLog), "oversized diagnostic log trimmed")
    PrivacyFixtureAssert(FileGetSize(largeLog) <= 1024 * 1024 + 3,
        "diagnostic log retains at most one MiB plus BOM")
    tail := FileRead(largeLog, "UTF-8")
    PrivacyFixtureAssert(InStr(tail, line) = 1
        && InStr(tail, "Latest diagnostic event " Chr(0x00E9) "`n"),
        "log trimming keeps complete UTF-8 events")
    PrivacyFixtureAssert(!FileExist(largeLog ".trim.tmp"), "diagnostic staging file removed")

    pipeLog := AppDataDirectory "\dense-report-fixture.log"
    Loop 24
        FileAppend("PART|FIELD|OK`n", pipeLog, "UTF-8")
    FileAppend("LATEST|EVENT`n", pipeLog, "UTF-8")
    tail := ReadBugReportDiagnosticTail(pipeLog, 160)
    PrivacyFixtureAssert(StrPut(tail, "UTF-8") - 1 <= 160
        && InStr(tail, "PART | FIELD | OK") = 1 && InStr(tail, "LATEST | EVENT"),
        "UTF-8 bound still holds after the sanitizer expands separators")

    originalDataRoot := AppDataDirectory
    reportRoot := AppDataDirectory "\report-size"
    DirCreate(reportRoot)
    for filename in GetDiagnosticLogNames()
        FileCopy(largeLog, reportRoot "\" filename)
    try
    {
        AppDataDirectory := reportRoot
        report := ReadBugReportLog()
        PrivacyFixtureAssert(StrPut(report, "UTF-8") - 1 <= 96 * 1024,
            "combined bug report preserves the transport budget in UTF-8 bytes")
        for filename in GetDiagnosticLogNames()
            PrivacyFixtureAssert(InStr(report, "===== " filename " =====`nOld diagnostic event "),
                "large diagnostics retain complete recent lines for " filename)
        recent := "Latest diagnostic event " Chr(0x00E9)
        StrReplace(report, recent, "", , &recentCount)
        PrivacyFixtureAssert(recentCount = GetDiagnosticLogNames().Length,
            "each bounded diagnostic section includes its latest entry")
    }
    finally AppDataDirectory := originalDataRoot

    cache := AppDataDirectory "\client-cache"
    old := DateAdd(A_Now, -60, "Days")
    for id in ["00000001", "00000002", "00000003", "custom"]
    {
        path := cache "\" id
        DirCreate(path)
        FileAppend("fixture", path "\.ready")
        FileSetTime(old, path "\.ready")
        FileSetTime(old, path, "M", "D")
        PrivacyFixtureAssert(IsOldLauncherFile(path, 30) && IsOldLauncherFile(path "\.ready", 30),
            "fixture ages both directory and marker for " id)
    }
    keep := cache "\00000001"
    recent := cache "\00000002"
    FileSetTime(, recent "\.ready")
    PruneLauncherCache(cache, "^\d{8}$", ".ready", [keep], 30)
    PrivacyFixtureAssert(DirExist(keep), "keeps explicitly protected cache")
    PrivacyFixtureAssert(DirExist(recent), "keeps recently used cache")
    PrivacyFixtureAssert(DirExist(cache "\custom"), "keeps unrelated directory")
    PrivacyFixtureAssert(!DirExist(cache "\00000003"), "removes stale unreferenced cache")

    job := AppDataDirectory "\fixture-import"
    DirCreate(job "\stage")
    FileAppend("recovery fixture", job "\journal.json")
    FileAppend("scratch", job "\stage\scratch")
    CleanupFinishedExpansionImport(job)
    PrivacyFixtureAssert(FileExist(job "\journal.json") && !DirExist(job "\stage"),
        "import recovery journal survives scratch cleanup")
    IniWrite("error", job "\result.ini", "Result", "State")
    IniWrite("complete", job "\result.ini", "Result", "Rollback")
    CleanupFinishedExpansionImport(job)
    PrivacyFixtureAssert(!DirExist(job), "verified rollback releases the obsolete job")
    FileAppend("PASS | TES3NP diagnostic redaction fixtures`n", "*", "UTF-8")
}
catch Error as err
{
    FileAppend("FAIL | TES3NP diagnostic redaction fixtures: " err.Message "`n", "*", "UTF-8")
    ExitApp(1)
}
finally
{
    EnvSet("USERNAME", previousWindowsUser)
    try DirDelete(AppDataDirectory, true)
}
ExitApp(0)
