[CmdletBinding(DefaultParameterSetName='Single')]
param(
    [Parameter(Mandatory, ParameterSetName='Single')]
    [ValidatePattern('\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?:alpha|beta|live)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z')]
    [string]$Version,
    [Parameter(Mandatory, ParameterSetName='Single')]
    [Parameter(Mandatory, ParameterSetName='Bundled')][string]$OutputPath,

    [Parameter(Mandatory, ParameterSetName='Bundled')]
    [ValidatePattern('\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?:alpha|beta|live)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z')]
    [string]$BundledVersion,
    [Parameter(Mandatory, ParameterSetName='Bundled')][string]$BundledNotesPath,

    [Parameter(Mandatory, ParameterSetName='History')]
    [ValidatePattern('\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?:alpha|beta|live)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z')]
    [string]$InstalledVersion,
    [Parameter(Mandatory, ParameterSetName='History')]
    [ValidatePattern('\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?:alpha|beta|live)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z')]
    [string]$LatestVersion,
    [Parameter(Mandatory, ParameterSetName='History')][string]$SummaryOutputPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$baseUri = 'https://api.github.com/repos/IAmShawn98/tes3np/releases/tags'
$headers = @{ 'User-Agent' = 'tes3np-launcher'; 'Accept' = 'application/vnd.github+json' }
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-VersionInfo([string]$Value) {
    $pattern = '\A(?<feature>(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8}))(?:(?:-(?<channel>alpha|beta|live)(?:\.(?<hotfix>[1-9][0-9]{0,8}))?)|(?:\.(?<legacyHotfix>[1-9][0-9]{0,8})))?\z'
    $m = [regex]::Match($Value, $pattern)
    if (!$m.Success) { throw 'Invalid release version.' }
    $channel = if ($m.Groups['channel'].Success) { $m.Groups['channel'].Value } else { 'live' }
    $hotfix = if ($m.Groups['hotfix'].Success) { [int]$m.Groups['hotfix'].Value }
        elseif ($m.Groups['legacyHotfix'].Success) { [int]$m.Groups['legacyHotfix'].Value }
        else { 0 }
    return [pscustomobject]@{
        Version = $Value
        Feature = [version]$m.Groups['feature'].Value
        Channel = $channel
        Hotfix = $hotfix
    }
}

function Compare-VersionInfo($Left, $Right) {
    if ($Left.Channel -cne $Right.Channel) { throw 'Update notes must stay on the installed channel.' }
    $result = $Left.Feature.CompareTo($Right.Feature)
    if ($result) { return $result }
    return $Left.Hotfix.CompareTo($Right.Hotfix)
}

function Get-ReleaseBody($Release, [string]$ExpectedVersion) {
    $body = (([string]$Release.body) -replace '\r\n?', [string][char]10).Trim()
    # Base GitHub releases may append the machine-managed hotfix index.
    # That index belongs on GitHub, not inside the launcher's base notes tab.
    $indexStart = '<!-- TES3NP HOTFIX HISTORY START -->'
    $indexEnd = '<!-- TES3NP HOTFIX HISTORY END -->'
    if ($body.Contains($indexStart) -or $body.Contains($indexEnd)) {
        $suffix = [regex]::Match($body,
            '(?s)\n\n<!-- TES3NP HOTFIX HISTORY START -->\n### Published Hotfixes\n\n.*?\n<!-- TES3NP HOTFIX HISTORY END -->\s*\z')
        if (!$suffix.Success) { throw 'Published hotfix index is malformed.' }
        $body = $body.Substring(0, $suffix.Index).TrimEnd()
    }
    $heading = [regex]::Match($body, '(?m)^##[ \t]+v(\S+)')
    if ($heading.Success -and $heading.Groups[1].Value -cne $ExpectedVersion) {
        throw 'Published release notes have a mismatched version heading.'
    }
    $escapedVersion = [regex]::Escape($ExpectedVersion)
    return ($body -replace "(?m)^##[ \t]+v$escapedVersion(?:[ \t]+[^\r\n]*)?[ \t]*\r?\n", '').Trim()
}


# Both previews and installed-version notes use the same category formatter.
# Every change retains its published version/date; no source release is rewritten.
function Format-CategoryNotes([object[]]$Entries) {
    $names = @('New Features', 'Improvements', 'Bug Fixes', 'Hotfixes', 'Removed Features', 'Other Changes')
    $groups = [ordered]@{}
    foreach ($name in $names) { $groups[$name] = @() }

    foreach ($entry in $Entries) {
        $sections = @{}
        $current = ''
        foreach ($line in ($entry.Body -split "\r?\n")) {
            if ($line -match '^###\s+(.+?)\s*
    $tag = "v$Version"
    try {
        $release = Invoke-RestMethod -Uri "$baseUri/$tag" -Headers $headers -TimeoutSec 5
    } catch {
        exit 1
    }
    if ($release.draft -or $release.tag_name -cne $tag) { exit 1 }
    $notes = Get-ReleaseBody $release $Version
    if (!$notes) { exit 1 }
    [IO.File]::WriteAllText($OutputPath, $notes, $utf8)
    exit 0
}

# Query only GitHub's publicly published releases, never commits, drafts,
# tags alone or local dev changelogs. The list is bounded; incomplete paging
# fails visibly rather than silently dropping older missed updates.
$installed = Get-VersionInfo $InstalledVersion
$latest = Get-VersionInfo $LatestVersion
if ($installed.Channel -cne $latest.Channel -or
    (Compare-VersionInfo $latest $installed) -le 0) {
    throw 'Invalid update history range.'
}
Remove-Item -LiteralPath $SummaryOutputPath -ErrorAction SilentlyContinue

$all = @()
$complete = $false
for ($page = 1; $page -le 5; $page++) {
    $listUri = "https://api.github.com/repos/IAmShawn98/tes3np/releases?per_page=100&page=$page"
    $batch = @(Invoke-RestMethod -Uri $listUri -Headers $headers -TimeoutSec 10)
    if ($batch.Count -gt 100) { throw 'Unexpected GitHub releases response.' }
    $all += $batch
    if ($batch.Count -lt 100) {
        $complete = $true
        break
    }
}
if (!$complete) { throw 'Published release history exceeds the supported page limit.' }

$entries = @()
$latestPublished = $false
$seenTags = @{}
foreach ($release in $all) {
    if ($null -eq $release -or $release.draft -or !$release.published_at) { continue }
    $tag = [string]$release.tag_name
    if (!$tag.StartsWith('v', [StringComparison]::Ordinal)) { continue }
    $rawVersion = $tag.Substring(1)
    try { $info = Get-VersionInfo $rawVersion }
    catch { continue }
    if ($info.Channel -cne $latest.Channel) { continue }
    if ($tag -ceq "v$LatestVersion") { $latestPublished = $true }
    if ((Compare-VersionInfo $info $installed) -le 0 -or
        (Compare-VersionInfo $info $latest) -gt 0) { continue }
    if ($seenTags.ContainsKey($tag)) { throw 'Duplicate published release version.' }
    $seenTags[$tag] = $true
    $notes = Get-ReleaseBody $release $rawVersion
    if (!$notes) { throw 'Published update is missing its release notes.' }
    $published = [DateTimeOffset]::Parse([string]$release.published_at, [Globalization.CultureInfo]::InvariantCulture)
    $date = $published.UtcDateTime.ToString('MMMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture)
    $entries += [pscustomobject]@{ Info = $info; Date = $date; Body = $notes }
}
if (!$latestPublished) { throw 'The latest feed version is not a published GitHub release.' }
$entries = @($entries | Sort-Object -Property @{
    Expression = { $_.Info.Feature }; Descending = $true
}, @{
    Expression = { $_.Info.Hotfix }; Descending = $true
})

# Reject gaps among numbered hotfixes in the requested update range.
foreach ($entry in $entries) {
    if ($entry.Info.Hotfix -le 0) { continue }
    $baseName = $entry.Info.Version -replace '\.[1-9][0-9]{0,8}$', ''
    $startingHotfix = if ($entry.Info.Feature -eq $installed.Feature) { $installed.Hotfix } else { 0 }
    for ($number = $startingHotfix + 1; $number -le $entry.Info.Hotfix; $number++) {
        $needed = "v$baseName.$number"
        if (!$seenTags.ContainsKey($needed)) { throw "Published update history is missing $needed." }
    }
}
[IO.File]::WriteAllText($SummaryOutputPath, (Format-CategoryNotes $entries), $utf8)
