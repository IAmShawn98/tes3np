#Requires AutoHotkey v2.0
#SingleInstance Off
; Standalone Windows fixture checks. No TES3MP files, network, clipboard or
; player data are touched. Run using the downloaded AutoHotkey64.exe runtime.
#Include ..\src\game\expansion-mismatch.ahk

global AppConfig := {Version: "TEST"}
; Production sets these in src/state.ahk and src/data/settings.ahk.
; The isolated parser fixture intentionally does not load the live launcher.
; Its test-only placeholders silence #Warn; no tests call GUI/game code.
global Client := {PID: 0, Enabled: false, Queue: 0}
global LauncherGui := 0
global EmbeddedChatPid := 0
global DataFile := ""

; This fixture includes only the production diagnostic module, NOT the whole
; live launcher. Provide inert dependency stubs so #Warn can resolve the same
; external function references it resolves in tes3np.ahk. The tests call
; only pure parser/render functions; any attempted runtime operation fails.
MismatchFixtureDisallow(operation)
{
    throw Error("Fixture attempted launcher-only operation: " operation)
}

PatchConfigurationPath()
{
    return MismatchFixtureDisallow("configuration path")
}

LogLauncherEvent(message)
{
    return MismatchFixtureDisallow("launcher log")
}

ShowLauncherWindow(activate := true)
{
    return MismatchFixtureDisallow("launcher GUI")
}

AddStyledButton(gui, x, y, width, height, text, callback)
{
    return MismatchFixtureDisallow("styled button")
}

SendLauncherChatCommand(command, targetHwnd := 0)
{
    return MismatchFixtureDisallow("ChatHost command")
}

CancelScheduledDailyLoginForToday()
{
    return MismatchFixtureDisallow("scheduled login")
}

StopClient()
{
    return MismatchFixtureDisallow("game client")
}

SetClientStatus(status)
{
    return MismatchFixtureDisallow("game status")
}

UploadExpansionFromFile()
{
    return MismatchFixtureDisallow("ZIP importer")
}

MismatchFixtureAssert(condition, reason)
{
    if !condition
        throw Error("Mismatch fixture failed: " reason)
}

try
{
    clean := "content=Morrowind.esm`ncontent=Tribunal.esm`n"
        . "content=Bloodmoon.esm`ncontent=PRIVATE_CHARACTER_MOD.esp`n"
        . "content=NP Expansion Pack.esp`n"
        . "data=C:\Users\SENSITIVE_NAME\Games"
    info := TES3MPAnalyzeMismatchConfig(clean)
    MismatchFixtureAssert(info.Total = 5, "enabled content count")
    MismatchFixtureAssert(info.ExpansionCount = 1, "expansion entry")
    MismatchFixtureAssert(info.ExpansionIndex = 5, "expansion position")
    MismatchFixtureAssert(info.OtherCount = 1, "non-expansion count")
    MismatchFixtureAssert(info.OtherAfterExpansion = 0, "expansion last")
    MismatchFixtureAssert(info.OtherDuplicates = 0, "no duplicates")
    MismatchFixtureAssert(info.Morrowind && info.Tribunal && info.Bloodmoon, "masters")

    rejection := "Your plugins or their load order don't match the server's"
    generic := TES3MPAnalyzeMismatchLogText("password=SENSITIVE_TOKEN`n" rejection)
    MismatchFixtureAssert(generic.Rejected, "server rejection")
    MismatchFixtureAssert(!generic.Order, "generic rejection is not a separate order error")
    MismatchFixtureAssert(!generic.MissingOther && !generic.MissingExpansion,
        "generic rejection does not imply missing plugins")
    MismatchFixtureAssert(TES3MPMismatchAssessment(info, generic, "Not checked")
        = "Cause not determined from available checks", "no unsupported conclusion")

    report := TES3MPRenderMismatchDiagnostics(info, generic,
        "Not checked", "TEST", "2026-11-01 00:00:00")
    for privateValue in ["PRIVATE_CHARACTER_MOD", "SENSITIVE_NAME",
        "SENSITIVE_TOKEN", "C:\Users", "password=", "data="]
        MismatchFixtureAssert(!InStr(report, privateValue), "private value in report")
    MismatchFixtureAssert(InStr(report, "Cause not determined"), "honest uncertainty")
    ; Regression: the original multiline Return silently stopped after the
    ; Expansion Pack fields and warned that the rest was unreachable.
    MismatchFixtureAssert(InStr(report, "Repeated additional content entries: 0"),
        "middle of report was not truncated")
    MismatchFixtureAssert(InStr(report, "Other missing plugin specifically indicated: No"),
        "client log evidence fields must be present")
    MismatchFixtureAssert(InStr(report, "Load-order wording near rejection: No"),
        "last report field must be present")
    MismatchFixtureAssert(!InStr(report, "SAFE PLUGIN"), "no redundant title")
    MismatchFixtureAssert(!InStr(report, "Privacy:"), "no privacy disclaimer")

    otherLog := TES3MPAnalyzeMismatchLogText(
        "Missing plugin SECRET_PERSONAL_MOD.esp`n" rejection)
    MismatchFixtureAssert(otherLog.Rejected && otherLog.MissingOther,
        "missing non-expansion plugin")
    MismatchFixtureAssert(!otherLog.MissingExpansion, "not NP-specific")
    MismatchFixtureAssert(TES3MPMismatchAssessment(info, otherLog, "Not checked")
        = "Other plugin or base-game dependency needs attention",
        "other-plugin assessment")
    otherReport := TES3MPRenderMismatchDiagnostics(info, otherLog,
        "Not checked", "TEST", "2026-11-01 00:00:00")
    MismatchFixtureAssert(!InStr(otherReport, "SECRET_PERSONAL_MOD"), "private missing name")
    MismatchFixtureAssert(InStr(otherReport, "Other missing plugin specifically indicated: Yes"),
        "other-plugin evidence in copied report")

    expansionLog := TES3MPAnalyzeMismatchLogText(
        "Missing plugin NP Expansion Pack.esp`n" rejection)
    MismatchFixtureAssert(expansionLog.MissingExpansion && !expansionLog.MissingOther,
        "expansion-specific missing plugin")
    MismatchFixtureAssert(TES3MPMismatchAssessment(info, expansionLog, "Not checked")
        = "Expansion Pack configuration needs attention", "expansion assessment")

    baseLog := TES3MPAnalyzeMismatchLogText("Missing master Tribunal.esm`n" rejection)
    MismatchFixtureAssert(baseLog.MissingBaseMaster && !baseLog.MissingOther,
        "base game master distinguished")

    orderedLog := TES3MPAnalyzeMismatchLogText(
        "Incorrect plugin load order on client`n" rejection)
    MismatchFixtureAssert(orderedLog.Order, "separate load-order indicator")
    MismatchFixtureAssert(!generic.Order, "generic load-order false positive blocked")

    duplicate := TES3MPAnalyzeMismatchConfig(
        "content=Morrowind.esm`ncontent=Tribunal.esm`ncontent=Bloodmoon.esm`n"
        . "content=SOME_MOD.esp`ncontent=SOME_MOD.esp`ncontent=NP Expansion Pack.esp")
    MismatchFixtureAssert(duplicate.OtherDuplicates = 1, "duplicate other plugin")
    MismatchFixtureAssert(TES3MPMismatchAssessment(duplicate, generic, "Not checked")
        = "Other plugin or base-game dependency needs attention", "duplicate assessment")

    missingExpansion := TES3MPAnalyzeMismatchConfig(
        "content=Morrowind.esm`ncontent=Tribunal.esm`ncontent=Bloodmoon.esm")
    MismatchFixtureAssert(TES3MPMismatchAssessment(missingExpansion, generic, "Not checked")
        = "Expansion Pack configuration needs attention", "missing expansion assessment")

    noConfig := TES3MPNewMismatchConfigResult("Not found")
    noLog := TES3MPNewMismatchLogResult("Not found")
    unavailable := TES3MPRenderMismatchDiagnostics(noConfig, noLog,
        "Not checked", "TEST", "2026-11-01 00:00:00")
    MismatchFixtureAssert(InStr(unavailable, "OpenMW config check: Not found"),
        "missing config stated explicitly")
    MismatchFixtureAssert(InStr(unavailable, "Missing Expansion Pack specifically named: Unknown"),
        "missing log is not reported as clean")
    MismatchFixtureAssert(!InStr(unavailable, "SOME_MOD"), "no unknown raw mod names")

    minimal := TES3MPBuildMinimumMismatchDiagnostics()
    MismatchFixtureAssert(InStr(minimal, "Unable to complete"),
        "exception fallback is explicit")
    MismatchFixtureAssert(!InStr(minimal, "SAFE") && !InStr(minimal, "Privacy:"),
        "fallback heading concise")
    FileAppend("Plugin mismatch diagnostic fixtures passed.`n", "*", "UTF-8")
    ExitApp(0)
}
catch Error as err
{
    FileAppend("Plugin mismatch diagnostic fixture FAILED: "
        err.Message " (line " err.Line ")`n", "*", "UTF-8")
    ExitApp(1)
}
