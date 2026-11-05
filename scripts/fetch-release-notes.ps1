param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')][string]$Version,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$uri = 'https://api.github.com/repos/IAmShawn98/tes3np-releases/releases/tags/v' + $Version
$notes = [ordered]@{ source = 'GitHub Releases'; text = ''; url = '' }
try {
    $release = Invoke-RestMethod -Uri $uri -Headers @{
        'User-Agent'='tes3np-launcher'
        'Accept'='application/vnd.github+json'
    } -TimeoutSec 12
    $notes.url = [string]$release.html_url
    $body = [string]$release.body
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($body -split '\r?\n')) {
        $line = $line.Trim()
        if (!$line) { continue }
        if ($line -match '^#{1,6}\s+(.+)$') { $lines.Add('### ' + $Matches[1]); continue }
        if ($line -match '^[-*+]\s+(.+)$') { $lines.Add([char]0x2022 + ' ' + $Matches[1]); continue }
        if ($line -match '^\d+\.\s+(.+)$') { $lines.Add([char]0x2022 + ' ' + $Matches[1]); continue }
        if ($line -match '^(-{3,}|\*{3,})$') { continue }
        $lines.Add($line)
    }
    # Keep section markers; the native AHK view wraps and styles the text.
    $notes.text = (($lines -join "`n") -replace '[`*_]', '').Trim()
    if (!$notes.text) { $notes.text = 'This release does not have published notes.' }
} catch {
    $notes.source = 'Notes not published or GitHub unavailable'
    $notes.text = 'No published release notes were found for v' + $Version + '. Check the versioned GitHub release when it is published.'
}
$parent = Split-Path -Parent $OutputPath
if ($parent -and !(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText($OutputPath, $notes.text, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($OutputPath + '.source', $notes.source, (New-Object Text.UTF8Encoding($false)))
