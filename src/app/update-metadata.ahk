ParseTes3npVersion(version)
{
    component := "(0|[1-9][0-9]{0,8})"
    hotfix := "([1-9][0-9]{0,8})"
    pattern := "\A" component "\." component "\." component "(?:-(alpha|beta|live)(?:\." hotfix ")?|\." hotfix ")?\z"
    if !RegExMatch(version, pattern, &parts)
        throw Error("Invalid TES3NP version.")
    return {Channel: parts[4] = "" ? "live" : parts[4],
        Feature: [Integer(parts[1]), Integer(parts[2]), Integer(parts[3])],
        Hotfix: Integer(parts[5] != "" ? parts[5] : parts[6] != "" ? parts[6] : "0")}
}

GetLauncherUpdateKind(installed, candidate)
{
    current := ParseTes3npVersion(installed)
    offered := ParseTes3npVersion(candidate)
    if current.Channel != offered.Channel
        return ""
    for index, component in current.Feature {
        if offered.Feature[index] != component
            return offered.Feature[index] > component ? "update" : ""
    }
    return offered.Hotfix > current.Hotfix ? "hotfix" : ""
}

GetUpdateManifestUrl(version)
{
    channel := ParseTes3npVersion(version).Channel
    return "https://raw.githubusercontent.com/IAmShawn98/tes3np/update-feed/" channel ".json"
}

GetTes3npReleasePage(version)
{
    ParseTes3npVersion(version)
    return "https://github.com/IAmShawn98/tes3np/releases/tag/v" version
}

ParseAndValidateUpdateManifest(text, installedVersion)
{
    fields := ReadUpdateManifestObject(text)
    if ReadUpdateManifestValue(fields, "manifestVersion", "number") != 2
        throw Error("Unsupported update manifest version.")
    version := ReadUpdateManifestValue(fields, "version", "string")
    channel := ReadUpdateManifestValue(fields, "channel", "string")
    if !(ReadUpdateManifestValue(fields, "product", "string") == "tes3np")
        || !(channel == ParseTes3npVersion(installedVersion).Channel)
        || !(channel == ParseTes3npVersion(version).Channel)
        throw Error("Update manifest identity/channel mismatch.")
    if !(ReadUpdateManifestValue(fields, "platform", "string") == "windows")
        || !(ReadUpdateManifestValue(fields, "architecture", "string") == "x64")
        throw Error("Update package is not for this platform.")
    releaseId := ReadUpdateManifestValue(fields, "releaseId", "string")
    if !(releaseId == "v" version)
        throw Error("Update manifest release identity mismatch.")

    package := ReadUpdateManifestObject(ReadUpdateManifestValue(fields, "package", "object"))
    fileName := ReadUpdateManifestValue(package, "fileName", "string")
    if !(fileName == "tes3np-" releaseId "-windows.zip")
        throw Error("Update manifest contains an unexpected package name.")
    size := ReadUpdateManifestValue(package, "size", "number")
    if size <= 0
        throw Error("Update manifest contains an invalid package size.")
    sha256 := ReadUpdateManifestValue(package, "sha256", "string")
    if !RegExMatch(sha256, "i)\A[0-9a-f]{64}\z")
        throw Error("Update manifest contains an invalid SHA-256 value.")
    enabled := ReadUpdateManifestValue(fields, "updateEnabled", "boolean")
    url := "https://github.com/IAmShawn98/tes3np/releases/download/" releaseId "/" fileName
    return {Version: version, Channel: channel, Size: size, Sha256: sha256, UpdateEnabled: enabled, PackageUrl: url}
}

; The feed schema uses unescaped text, integers, booleans and one nested
; package object. Reject duplicate keys, trailing data and malformed values.
ReadUpdateManifestObject(text)
{
    if !RegExMatch(text, "s)\A\s*\{(.*)\}\s*\z", &objectMatch)
        throw Error("Invalid update manifest object.")
    body := objectMatch[1]
    fields := Map()
    fields.CaseSense := "On"
    offset := 1
    pattern := '\G[ \t\r\n]*"([A-Za-z][A-Za-z0-9]*)"[ \t\r\n]*:[ \t\r\n]*(\{[^{}]*\}|"[^"\\\x00-\x1f]*"|(?:0|[1-9][0-9]{0,17})|true|false)[ \t\r\n]*(,|\z)'
    loop {
        if !RegExMatch(body, pattern, &field, offset) || fields.Has(field[1])
            throw Error("Invalid or duplicate update manifest field.")
        fields[field[1]] := field[2]
        if field[3] = ""
            return fields
        offset += field.Len[0]
    }
}

ReadUpdateManifestValue(fields, name, type)
{
    if fields.Has(name) {
        value := fields[name]
        switch type {
            case "string":
                if SubStr(value, 1, 1) = '"'
                    return SubStr(value, 2, -1)
            case "number":
                if RegExMatch(value, "\A[0-9]+\z")
                    return Integer(value)
            case "boolean":
                if value == "true" || value == "false"
                    return value == "true"
            case "object":
                if SubStr(value, 1, 1) = "{"
                    return value
        }
    }
    throw Error("Update manifest is missing or has invalid " name ".")
}
