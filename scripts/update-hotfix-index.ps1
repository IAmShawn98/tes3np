param(
    [Parameter(Mandatory)]
    [ValidatePattern('\Av(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})-alpha\.[1-9][0-9]{0,8}\z')]
    [string]$LatestHotfixTag
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$repo = 'IAmShawn98/tes3np'
$nl = [string][char]10
$startMarker = '<!-- TES3NP HOTFIX HISTORY START -->'
$endMarker = '<!-- TES3NP HOTFIX HISTORY END -->'

$lastDot = $LatestHotfixTag.LastIndexOf('.')
$baseTag = $LatestHotfixTag.Substring(0, $lastDot)
$latestNumber = [int]$LatestHotfixTag.Substring($lastDot + 1)
if ($latestNumber -gt 100) { throw 'Too many hotfix entries to verify safely.' }

function Get-PublishedRelease([string]$Tag) {
    $release = gh release view $Tag --repo $repo --json tagName,isDraft,publishedAt,body |
        ConvertFrom-Json
    if ($release.tagName -cne $Tag -or $release.isDraft -or !$release.publishedAt) {
        throw "Release $Tag is not a published GitHub release."
    }
    return $release
}

$base = Get-PublishedRelease $baseTag
$body = (([string]$base.body) -replace '\r\n?', $nl).TrimEnd()
$hasStart = $body.Contains($startMarker)
$hasEnd = $body.Contains($endMarker)
if ($hasStart -ne $hasEnd) { throw 'The existing hotfix history block is incomplete.' }

$original = $body
if ($hasStart) {
    # Only the append-only history block at the end may be rewritten.
    $suffix = [regex]::Match($body,
        '(?s)\n\n<!-- TES3NP HOTFIX HISTORY START -->\n### Published Hotfixes\n\n.*?\n<!-- TES3NP HOTFIX HISTORY END -->\s*\z')
    if (!$suffix.Success) { throw 'Unexpected change to the original release history layout.' }
    $original = $body.Substring(0, $suffix.Index).TrimEnd()
}
if (!$original.StartsWith("## $baseTag$nl", [StringComparison]::Ordinal) -or
    $original.Contains($startMarker) -or $original.Contains($endMarker)) {
    throw 'Original release content is missing or contains unexpected history markers.'
}

$entries = @()
for ($number = $latestNumber; $number -ge 1; $number--) {
    $tag = "$baseTag.$number"
    $release = Get-PublishedRelease $tag
    $published = [DateTimeOffset]::Parse([string]$release.publishedAt,
        [Globalization.CultureInfo]::InvariantCulture)
    $date = $published.UtcDateTime.ToString('MMMM d, yyyy',
        [Globalization.CultureInfo]::InvariantCulture)
    $link = "https://github.com/$repo/releases/tag/$tag"
    $entries += "- [$tag]($link) " + [char]0x2014 + " Published $date"
}

$index = $startMarker + $nl + '### Published Hotfixes' + $nl + $nl +
    ($entries -join $nl) + $nl + $endMarker
$updatedBody = $original + $nl + $nl + $index + $nl

if ($body -ceq $updatedBody.TrimEnd()) {
    Write-Host "Published Hotfixes already up to date on $baseTag."
    exit 0
}

$tempFile = [IO.Path]::Combine([IO.Path]::GetTempPath(),
    "tes3np-hotfix-index-$([guid]::NewGuid().ToString('N')).md")
try {
    [IO.File]::WriteAllText($tempFile, $updatedBody, [Text.UTF8Encoding]::new($false))
    gh release edit $baseTag --repo $repo --notes-file $tempFile
    $verified = Get-PublishedRelease $baseTag
    $resultBody = (([string]$verified.body) -replace '\r\n?', $nl).TrimEnd()
    if ($resultBody -cne $updatedBody.TrimEnd()) {
        throw 'The published hotfix history was not saved exactly as requested.'
    }
    Write-Host "Updated Published Hotfixes on $baseTag without editing its original changelog."
}
finally {
    Remove-Item -LiteralPath $tempFile -ErrorAction SilentlyContinue
}
