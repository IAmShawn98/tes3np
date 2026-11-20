[CmdletBinding(DefaultParameterSetName='Single')]
param(
    [Parameter(Mandatory, ParameterSetName='Single')]
    [ValidatePattern('\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?:alpha|beta|live)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z')]
    [string]$Version,
    [Parameter(Mandatory, ParameterSetName='Single')][string]$OutputPath,

    [Parameter(Mandatory, ParameterSetName='History')]
    [ValidatePattern('\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?:alpha|beta|live)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z')]
    [string]$InstalledVersion,
    [Parameter(Mandatory, ParameterSetName='History')]
    [ValidatePattern('\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?:alpha|beta|live)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z')]
    [string]$LatestVersion,
    [Parameter(Mandatory, ParameterSetName='History')][string]$ReleaseOutputPath,
    [Parameter(Mandatory, ParameterSetName='History')][string]$HotfixOutputPath
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
    $body = ([string]$Release.body).Trim()
    $heading = [regex]::Match($body, '(?m)^##[ \t]+v(\S+)')
    if ($heading.Success -and $heading.Groups[1].Value -cne $ExpectedVersion) {
        throw 'Published release notes have a mismatched version heading.'
    }
    $escapedVersion = [regex]::Escape($ExpectedVersion)
    return ($body -replace "(?m)^##[ \t]+v$escapedVersion(?:[ \t]+[^\r\n]*)?[ \t]*\r?\n", '').Trim()
}

if ($PSCmdlet.ParameterSetName -ceq 'Single') {
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
if ($ReleaseOutputPath -ceq $HotfixOutputPath) { throw 'History destinations must differ.' }
Remove-Item -LiteralPath $ReleaseOutputPath, $HotfixOutputPath -ErrorAction SilentlyContinue

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

$featureNotes = @()
$hotfixNotes = @()
foreach ($entry in $entries) {
    $part = "### v$($entry.Info.Version) " + [char]0x2014 + " $($entry.Date)" + [Environment]::NewLine +
        [Environment]::NewLine + $entry.Body
    if ($entry.Info.Hotfix -gt 0) { $hotfixNotes += $part }
    else { $featureNotes += $part }
}
$releaseText = if ($featureNotes.Count) {
    $featureNotes -join ([Environment]::NewLine + [Environment]::NewLine)
} else {
    'No new feature releases since your installed version.'
}
$hotfixText = if ($hotfixNotes.Count) {
    $hotfixNotes -join ([Environment]::NewLine + [Environment]::NewLine)
} else {
    'No new hotfixes since your installed version.'
}
[IO.File]::WriteAllText($ReleaseOutputPath, $releaseText, $utf8)
[IO.File]::WriteAllText($HotfixOutputPath, $hotfixText, $utf8)
