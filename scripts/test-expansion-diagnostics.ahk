#Requires AutoHotkey v2.0
#SingleInstance Off
; Standalone Windows fixture checks. No TES3MP files, network, clipboard or
; player data are touched. Run using the downloaded AutoHotkey64.exe runtime.
#Include ..\src\game\expansion-mismatch.ahk

global AppConfig := {Version: "TEST"}
; Production sets these in src/state.ahk and src/data/settings.ahk.
; The isolated parser fixture intentionally does not load the live launcher.
; Its test-only placeholders silence #Warn; no tests call GUI/game code.
global Client := {PID: 0, Enabled: false}
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

StopClient()
{
    return MismatchFixtureDisallow("game client")
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
    ; Regression: the displayed mismatch was produced by a successful live
    ; log read. Reopening the same log after StopClient can fail; use the
    ; already-sanitized evidence and never require a second read.
    captured := TES3MPAnalyzeMismatchLogText(
        "Missing plugin SECRET_PERSONAL_MOD.esp`n" rejection)
    chosen := TES3MPSelectMismatchLogEvidence(captured)
    MismatchFixtureAssert(chosen.Rejected && chosen.MissingOther,
        "live rejection evidence remains available after client stops")
    MismatchFixtureAssert(chosen.Source = "Captured during failed login",
        "live rejection provenance is explicit")
    MismatchFixtureAssert(!chosen.MissingExpansion, "live evidence is correctly classified")
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
    MismatchFixtureAssert(InStr(report, "Client evidence source: Latest client log"),
        "fallback log provenance appears in report")
    capturedReport := TES3MPRenderMismatchDiagnostics(info, chosen,
        "Not checked", "TEST", "2026-11-01 00:00:00")
    MismatchFixtureAssert(InStr(capturedReport,
        "Client evidence source: Captured during failed login"),
        "live evidence provenance appears in report")
    MismatchFixtureAssert(!InStr(capturedReport, "SECRET_PERSONAL_MOD"),
        "live log evidence never leaks arbitrary plugin names")
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

    ; TES3MP comparison details are written after the generic rejection.
    ; Capture fixed discrepancy categories, never the arbitrary filenames.
    comparison := TES3MPAnalyzeMismatchLogText(rejection "`n"
        . "0: checksum 0x67C998DD doesn't match 0x7B6AF5B9`n"
        . "1: SECRET_CHARACTER.esp doesn't match Tribunal.esm, checksum 0xABCDEF12 doesn't match 0xF481F334")
    MismatchFixtureAssert(comparison.ComparisonSlots = 2, "differing slots counted")
    MismatchFixtureAssert(comparison.FirstSlot = 0, "first zero-based differing slot")
    MismatchFixtureAssert(comparison.ChecksumCount = 2, "checksum slots")
    MismatchFixtureAssert(comparison.NameMismatchCount = 1, "plugin-name mismatch")
    MismatchFixtureAssert(!comparison.Order, "checksum details do not imply order text")
    MismatchFixtureAssert(TES3MPMismatchAssessment(info, comparison, "Yes")
        = "TES3MP reported multiple plugin comparison discrepancies",
        "comparison-specific assessment")
    TES3MPAccumulateMismatchDetailText(comparison,
        "4: PRIVATE_MOD.esp is past the number of plugins used by the server`n"
        . "5: Another.esp is past the number of plugins used by the server")
    MismatchFixtureAssert(comparison.ComparisonSlots = 4, "follow-on slots captured")
    MismatchFixtureAssert(comparison.ExtraClientCount = 2, "extra client slots classified")
    TES3MPAccumulateMismatchDetailText(comparison,
        "4: PRIVATE_MOD.esp is past the number of plugins used by the server")
    MismatchFixtureAssert(comparison.ExtraClientCount = 2,
        "repeated comparison slot does not inflate totals")
    reportComparison := TES3MPRenderMismatchDiagnostics(info, comparison,
        "Yes", "TEST", "2026-11-01 00:00:00")
    for privateValue in ["SECRET_CHARACTER", "PRIVATE_MOD", "Another.esp",
        "0x67C998DD", "0xF481F334"]
        MismatchFixtureAssert(!InStr(reportComparison, privateValue),
            "private comparison detail leaked")
    MismatchFixtureAssert(InStr(reportComparison, "Checksum mismatch slots: 2"),
        "checksum comparison reported")
    MismatchFixtureAssert(InStr(reportComparison, "First differing slot (zero-based): 0"),
        "slot index reported")
    MismatchFixtureAssert(InStr(reportComparison, "Extra client plugin slots: 2"),
        "extra client slots reported")
    MismatchFixtureAssert(InStr(reportComparison, "Detailed comparison captured: Yes"),
        "comparison availability explicit")
    MismatchFixtureAssert(InStr(reportComparison, "0 [checksum]"),
        "first slot category included")
    MismatchFixtureAssert(InStr(reportComparison, "1 [checksum+name]"),
        "combined slot categories included")
    MismatchFixtureAssert(InStr(reportComparison, "4 [extra-client]"),
        "follow-on per-slot information included")
    MismatchFixtureAssert(InStr(report, "Slot details (zero-based): None captured"),
        "missing comparison details explicitly reported")

    serverExtra := TES3MPAnalyzeMismatchLogText(rejection
        . "`n4: Server.esp is past the number of plugins used by the client")
    MismatchFixtureAssert(serverExtra.ExtraServerCount = 1 && serverExtra.ExtraClientCount = 0,
        "extra server slots distinguished")
    MismatchFixtureAssert(TES3MPMismatchAssessment(info, serverExtra, "Yes")
        = "Server has plugin slots beyond the client list",
        "extra server assessment")
    MismatchFixtureAssert(InStr(report, "Detailed comparison captured: No"),
        "generic rejection does not pretend comparison was captured")
    MismatchFixtureAssert(InStr(report, "Expansion ESP SHA-256: Unknown"),
        "missing fingerprint must not be guessed")

    ; Exercise Windows CNG using synthetic data only, never live game files.
    fixtureEsp := A_Temp "\tes3np-expansion-sha256-" A_TickCount ".esp"
    try
    {
        FileAppend("abc", fixtureEsp, "UTF-8-RAW")
        fingerprint := TES3MPReadExpansionFingerprint(fixtureEsp)
        MismatchFixtureAssert(fingerprint.Status = "Hashed" && fingerprint.Size = 3,
            "local synthetic ESP bytes hashed")
        MismatchFixtureAssert(fingerprint.Sha256 =
            "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
            "known SHA-256 test vector")
        fingerprintReport := TES3MPRenderMismatchDiagnostics(info, generic,
            "Yes", "TEST", "2026-11-01 00:00:00", fingerprint)
        MismatchFixtureAssert(InStr(fingerprintReport, fingerprint.Sha256),
            "content fingerprint included in report")
        MismatchFixtureAssert(!InStr(fingerprintReport, fixtureEsp),
            "local fixture path excluded from report")
    }
    finally
    {
        if FileExist(fixtureEsp)
            FileDelete(fixtureEsp)
    }

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
