#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\src\app\update-metadata.ahk

AssertUpdateMetadata(condition, description)
{
    if !condition
        throw Error(description)
}

try {
    for candidate in [
        ["0.1.21-alpha", "0.1.21-alpha.1", "hotfix"],
        ["0.1.21-alpha.9", "0.1.21-alpha.10", "hotfix"],
        ["0.1.21-beta.9", "0.1.21-beta.10", "hotfix"],
        ["1.0.0-live", "1.0.0-live.1", "hotfix"],
        ["1.0.0-live.9", "1.0.0-live.10", "hotfix"],
        ["1.0.0.1", "1.0.0-live.2", "hotfix"],
        ["0.1.21.9", "0.1.21.10", "hotfix"],
        ["0.1.21-alpha.20", "0.1.22-alpha", "update"],
        ["0.1.21-beta.20", "0.1.22-beta.1", "update"],
        ["1.0.0-live.20", "1.0.1-live", "update"],
        ["0.1.21.20", "0.1.22", "update"],
        ["0.1.22", "0.1.21.21", ""],
        ["0.1.21-alpha.10", "0.1.21-alpha.9", ""],
        ["0.1.21", "0.1.21", ""],
        ["0.1.21-alpha", "0.1.21-beta", ""],
        ["0.1.21-beta", "1.0.0-live", ""]
    ] {
        AssertUpdateMetadata(GetLauncherUpdateKind(candidate[1], candidate[2]) == candidate[3],
            "Unexpected update kind for " candidate[1] " -> " candidate[2])
    }

    feed := "https://raw.githubusercontent.com/IAmShawn98/tes3np/update-feed/"
    AssertUpdateMetadata(GetUpdateManifestUrl("0.1.21-alpha") == feed "alpha.json", "Wrong alpha feed")
    AssertUpdateMetadata(GetUpdateManifestUrl("0.1.21-beta.10") == feed "beta.json", "Wrong beta feed")
    AssertUpdateMetadata(GetUpdateManifestUrl("0.1.21.10") == feed "live.json", "Wrong live feed")
    AssertUpdateMetadata(GetUpdateManifestUrl("1.0.0-live.1") == feed "live.json", "Wrong suffixed live feed")
    AssertUpdateMetadata(GetTes3npReleasePage("1.0.0-live.1") ==
        "https://github.com/IAmShawn98/tes3np/releases/tag/v1.0.0-live.1", "Wrong live hotfix release page")

    ; The PowerShell generator supplies a real v2 manifest with a fake ZIP.
    text := FileRead(A_Args[1], "UTF-8")
    installed := A_Args[2]
    channel := ParseTes3npVersion(installed).Channel
    wrongChannel := channel = "alpha" ? "beta" : "alpha"
    wrongVersion := "0.1.21-" wrongChannel
    expectedFile := "tes3np-v" installed "-windows.zip"
    parsed := ParseAndValidateUpdateManifest(text, installed)
    expectedUrl := "https://github.com/IAmShawn98/tes3np/releases/download/v" installed "/" expectedFile
    AssertUpdateMetadata(parsed.Version == installed && parsed.PackageUrl == expectedUrl && parsed.Size = 8
        && parsed.UpdateEnabled, "Generated manifest did not round-trip")
    disabled := StrReplace(text, "true", "false")
    AssertUpdateMetadata(!ParseAndValidateUpdateManifest(disabled, installed).UpdateEnabled, "Updates stayed enabled")

    for bad in [
        [text, wrongVersion, "Incorrect launcher channel"],
        [StrReplace(text, '"' channel '"', '"' wrongChannel '"'), wrongVersion, "Version channel does not match metadata"],
        [StrReplace(text, expectedFile, "tes3np-windows.zip"), installed, "Unversioned package"],
        [StrReplace(text, expectedFile, "../" expectedFile), installed, "Path components in package name"],
        [StrReplace(text, '"releaseId"', '"wrongReleaseId"'), installed, "Missing release identity"],
        [StrReplace(text, '"channel"', '"channel": "alpha", "channel"'), installed, "Duplicate JSON key"],
        [RegExReplace(text, '"manifestVersion":\s*2', '"manifestVersion": 1'), installed, "Legacy schema"],
        [RegExReplace(text, '"size":\s*8', '"size": 8.5'), installed, "Nonintegral size"],
        [RegExReplace(text, '"size":\s*8', '"size": 0'), installed, "Zero size"],
        [RegExReplace(text, '"sha256":\s*"[0-9a-f]{64}"', '"sha256": "invalid"'), installed, "Invalid SHA-256"],
        [StrReplace(text, "true", '"true"'), installed, "String used as boolean"],
        [text "trailing data", installed, "Trailing data"]
    ] {
        rejected := false
        try ParseAndValidateUpdateManifest(bad[1], bad[2])
        catch
            rejected := true
        AssertUpdateMetadata(rejected, "Accepted invalid manifest: " bad[3])
    }
    FileAppend("PASS: AutoHotkey updater version, channel and generated manifest fixtures`n", "*")
}
catch Error as err {
    FileAppend("FAIL: " err.Message "`n", "**")
    ExitApp(1)
}
ExitApp(0)
