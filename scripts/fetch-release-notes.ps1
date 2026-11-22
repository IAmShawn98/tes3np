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


# A single published GitHub Release can carry every patch in a family.
# This parser intentionally rejects incomplete or ambiguous public history.
# Format v1 requires strict newest-first consecutive patches, an immutable
# base publication timestamp, and the original base changelog after the block.
function Get-PublishedReleases {
    $items = @()
    $complete = $false
    for ($page = 1; $page -le 5; $page++) {
        $listUri = "https://api.github.com/repos/IAmShawn98/tes3np/releases?per_page=100&page=$page"
        $batch = @((Invoke-RestMethod -Uri $listUri -Headers $headers -TimeoutSec 10))
        if ($batch.Count -gt 100) { throw 'Unexpected GitHub releases response.' }
        $items += $batch
        if ($batch.Count -lt 100) { $complete = $true; break }
    }
    if (!$complete) { throw 'Published release history exceeds the supported page limit.' }
    return $items
}

function Get-UtcPublishedDate([string]$Value) {
    if ($Value -cnotmatch '\A[0-9]{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z\z') {
        throw 'Consolidated history publication date must be an exact UTC timestamp.'
    }
    return [DateTimeOffset]::ParseExact($Value, "yyyy-MM-dd'T'HH:mm:ss'Z'",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
}

function Get-ConsolidatedReleaseHistory($Release, [string]$ExpectedLatestVersion) {
    $start = '<!-- TES3NP CONSOLIDATED PATCH HISTORY v1 START -->'
    $end = '<!-- TES3NP CONSOLIDATED PATCH HISTORY v1 END -->'
    $body = (([string]$Release.body) -replace '\r\n?', [string][char]10).TrimEnd()
    if (!$body.Contains($start) -and !$body.Contains($end)) { return $null }
    if ($Release.draft -or !$Release.published_at -or $Release.tag_name -cne "v$ExpectedLatestVersion" -or
        !$body.StartsWith($start + "`n", [StringComparison]::Ordinal) -or
        ([regex]::Matches($body, [regex]::Escape($start))).Count -ne 1 -or
        ([regex]::Matches($body, [regex]::Escape($end))).Count -ne 1) {
        throw 'Consolidated patch history identity or markers are invalid.'
    }
    $latest = Get-VersionInfo $ExpectedLatestVersion
    if ($latest.Hotfix -lt 1 -or $latest.Hotfix -gt 100) {
        throw 'Consolidated history must end in a supported published patch version.'
    }
    $baseVersion = $latest.Feature.ToString() + '-' + $latest.Channel
    if ($baseVersion -ceq '0.1.21-alpha' -and [int64]$Release.id -ne 451907283) {
        throw 'The published patch does not use the original approved GitHub Release record.'
    }
    $separator = "`n" + $end + "`n`n"
    $endIndex = $body.IndexOf($separator, [StringComparison]::Ordinal)
    if ($endIndex -lt 0) { throw 'Consolidated history end marker or base separator is missing.' }
    $block = $body.Substring($start.Length + 1, $endIndex - $start.Length - 1)
    $baseBody = $body.Substring($endIndex + $separator.Length)
    if ($baseBody -cnotmatch "\A##[ \t]+v$([regex]::Escape($baseVersion))\n" -or
        ([regex]::Matches($baseBody, '(?m)^##[ \t]+v')).Count -ne 1) {
        throw 'The original base release heading is missing or repeated.'
    }
    # The published v0.1.21-alpha base body was independently compared to
    # the original GitHub record (ID 451907283) before the first patch.
    # Refuse silently rewritten historical prose after that record is retagged.
    if ($baseVersion -ceq '0.1.21-alpha') {
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            $baseHash = [BitConverter]::ToString($hasher.ComputeHash(
                [Text.Encoding]::UTF8.GetBytes($baseBody))).Replace('-', '')
        } finally { $hasher.Dispose() }
        if ($baseHash -cne '75A996CB28DCEEC757C93DB53584977D87EA62D6A7A198A84F0E35223866D01D') {
            throw 'Original published v0.1.21-alpha changelog does not match the verified historical body.'
        }
    }
    $baseNotes = Get-ReleaseBody ([pscustomobject]@{ body = $baseBody }) $baseVersion
    if ($baseNotes -cnotmatch '(?m)^### (?:New Features|Improvements|Bug Fixes|Removed Features)') {
        throw 'The original base changelog is missing its categories.'
    }
    $metadata = [regex]::Match($block,
        '\A<!-- TES3NP BASE RELEASE PUBLISHED (?<date>[0-9TZ:\-]+) -->\n\n')
    if (!$metadata.Success) { throw 'Original base publication timestamp is missing.' }
    $baseTime = Get-UtcPublishedDate $metadata.Groups['date'].Value
    if ($baseVersion -ceq '0.1.21-alpha' -and
        $metadata.Groups['date'].Value -cne '2026-11-20T05:22:39Z') {
        throw 'Original v0.1.21-alpha publication timestamp does not match the verified record.'
    }
    $patchBlock = $block.Substring($metadata.Length).Trim("`n")
    $lines = [regex]::Matches($patchBlock, '(?m)^##[ \t]+[^\n]+$')
    if ($lines.Count -ne $latest.Hotfix) {
        throw 'Consolidated history does not contain exactly every patch.'
    }
    $entries = @()
    $previousTime = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $match = [regex]::Match($line.Value,
            '\A## v(?<version>[0-9]+\.[0-9]+\.[0-9]+-(?:alpha|beta|live)\.[1-9][0-9]*) — Published (?<date>[0-9TZ:\-]+)\z')
        $number = $latest.Hotfix - $i
        $expected = $baseVersion + '.' + $number
        if (!$match.Success -or $match.Groups['version'].Value -cne $expected) {
            throw "Consolidated patch $number is missing or out of order."
        }
        $publishedTime = Get-UtcPublishedDate $match.Groups['date'].Value
        if ($publishedTime -le $baseTime -or ($null -ne $previousTime -and $publishedTime -ge $previousTime)) {
            throw 'Consolidated patch publication dates are not increasing chronologically.'
        }
        $previousTime = $publishedTime
        $notesStart = $line.Index + $line.Length
        $notesEnd = if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Index } else { $patchBlock.Length }
        $notes = $patchBlock.Substring($notesStart, $notesEnd - $notesStart).Trim()
        if (!$notes -or $notes -cnotmatch '(?m)^### (?:New Features|Improvements|Bug Fixes|Removed Features)') {
            throw "Consolidated patch $number is missing categorized notes."
        }
        $entries += [pscustomobject]@{
            Info = Get-VersionInfo $expected
            Date = $publishedTime.UtcDateTime.ToString('MMMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture)
            Body = $notes
        }
    }
    $entries += [pscustomobject]@{
        Info = Get-VersionInfo $baseVersion
        Date = $baseTime.UtcDateTime.ToString('MMMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture)
        Body = $baseNotes
    }
    return [pscustomobject]@{ BaseVersion = $baseVersion; Entries = $entries }
}

function Find-CurrentConsolidatedRelease($Releases, [string]$HistoricalVersion) {
    $info = Get-VersionInfo $HistoricalVersion
    $baseTag = 'v' + $info.Feature.ToString() + '-' + $info.Channel
    $candidates = @()
    foreach ($item in $Releases) {
        if ($null -eq $item -or $item.draft -or !$item.published_at) { continue }
        if ([string]$item.tag_name -cnotmatch ('\A' + [regex]::Escape($baseTag) + '\.[1-9][0-9]*\z')) { continue }
        $current = Get-VersionInfo ([string]$item.tag_name).Substring(1)
        if ($current.Hotfix -le 100) { $candidates += $item }
    }
    if (!$candidates.Count) { return $null }
    if ($candidates.Count -ne 1) { throw 'Multiple patch releases exist in a consolidated family.' }
    return $candidates[0]
}

if ($PSCmdlet.ParameterSetName -ceq 'Single') {
    $tag = "v$Version"
    try {
        $release = $null
        try { $release = Invoke-RestMethod -Uri "$baseUri/$tag" -Headers $headers -TimeoutSec 5 }
        catch {
            # Historical tags remain Git refs after the sole Release record is
            # retagged. For those missing Release records, inspect the currently
            # published family record and require its complete history block.
            $candidate = Find-CurrentConsolidatedRelease @(Get-PublishedReleases) $Version
            if ($null -eq $candidate) { exit 1 }
            $release = $candidate
        }
        if ($release.draft) { exit 1 }
        $consolidated = Get-ConsolidatedReleaseHistory $release ([string]$release.tag_name).Substring(1)
        if ($null -ne $consolidated) {
            $match = @($consolidated.Entries | Where-Object { $_.Info.Version -ceq $Version })
            if ($match.Count -ne 1) { exit 1 }
            $notes = $match[0].Body
        } else {
            if ($release.tag_name -cne $tag) { exit 1 }
            $notes = Get-ReleaseBody $release $Version
        }
        if (!$notes) { exit 1 }
        [IO.File]::WriteAllText($OutputPath, $notes, $utf8)
        exit 0
    } catch {
        exit 1
    }
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

$all = @(Get-PublishedReleases)
# Preserve the existing separate-release behavior unless the exact latest
# published release declares a strict consolidated history block.
$consolidated = $null
$latestMatches = @($all | Where-Object {
    $null -ne $_ -and !$_.draft -and $_.published_at -and $_.tag_name -ceq "v$LatestVersion"
})
if ($latestMatches.Count -ne 1) { throw 'The latest feed version is not a unique published GitHub release.' }
$consolidated = Get-ConsolidatedReleaseHistory $latestMatches[0] $LatestVersion
if ($null -eq $consolidated -and $latest.Feature.ToString() -ceq '0.1.21' -and
    $latest.Channel -ceq 'alpha' -and $latest.Hotfix -gt 0) {
    $familyTag = 'v0.1.21-alpha'
    $familyExisting = @($all | Where-Object { $null -ne $_ -and !$_.draft -and $_.published_at -and
        ($_.tag_name -ceq $familyTag -or $_.tag_name -cmatch '^v0\.1\.21-alpha\.[1-9][0-9]*$') })
    if ($familyExisting.Count -eq 1) {
        throw 'Single-record alpha patch is missing its mandatory complete release history.'
    }
}
if ($null -ne $consolidated) {
    $familyReleases = @($all | Where-Object {
        $null -ne $_ -and !$_.draft -and $_.published_at -and
        ($_.tag_name -ceq ('v' + $consolidated.BaseVersion) -or
         $_.tag_name -cmatch ('\A' + [regex]::Escape('v' + $consolidated.BaseVersion) + '\.[1-9][0-9]*\z'))
    })
    if ($familyReleases.Count -ne 1) {
        throw 'The consolidated family must have exactly one published GitHub Release record.'
    }
}

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
    if ($null -ne $consolidated -and ($tag -ceq ('v' + $consolidated.BaseVersion) -or
        $tag -cmatch ('\A' + [regex]::Escape('v' + $consolidated.BaseVersion) + '\.[1-9][0-9]*\z'))) {
        continue # All family versions are expanded from the single record below.
    }
    if ($seenTags.ContainsKey($tag)) { throw 'Duplicate published release version.' }
    $seenTags[$tag] = $true
    $notes = Get-ReleaseBody $release $rawVersion
    if (!$notes) { throw 'Published update is missing its release notes.' }
    $published = [DateTimeOffset]::Parse([string]$release.published_at, [Globalization.CultureInfo]::InvariantCulture)
    $date = $published.UtcDateTime.ToString('MMMM d, yyyy', [Globalization.CultureInfo]::InvariantCulture)
    $entries += [pscustomobject]@{ Info = $info; Date = $date; Body = $notes }
}
if (!$latestPublished) { throw 'The latest feed version is not a published GitHub release.' }
if ($null -ne $consolidated) {
    foreach ($entry in $consolidated.Entries) {
        if ((Compare-VersionInfo $entry.Info $installed) -le 0 -or
            (Compare-VersionInfo $entry.Info $latest) -gt 0) { continue }
        $versionTag = 'v' + $entry.Info.Version
        if ($seenTags.ContainsKey($versionTag)) { throw 'Duplicate consolidated version.' }
        $seenTags[$versionTag] = $true
        $entries += $entry
    }
}
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
