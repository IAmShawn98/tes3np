param(
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')][string]$Version,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$baseUri = 'https://api.github.com/repos/IAmShawn98/tes3np-releases/releases/tags'
$headers = @{ 'User-Agent' = 'tes3np-launcher'; 'Accept' = 'application/vnd.github+json' }
$versionPattern = [regex]::Escape($Version)
$notes = ''

foreach ($tag in @('latest-alpha', "v$Version")) {
    try {
        $release = Invoke-RestMethod -Uri "$baseUri/$tag" -Headers $headers -TimeoutSec 5
    } catch {
        continue
    }

    if ($release.draft -or $release.tag_name -ne $tag) { continue }
    $body = ([string]$release.body).Trim()
    if (!$body) { continue }
    $heading = [regex]::Match($body, '(?m)^##[ \t]+v(\S+)')
    if ($tag -eq 'latest-alpha' -and
        $release.name -notmatch "^tes3np v$versionPattern(?:\s|$)") { continue }
    if ($heading.Success -and $heading.Groups[1].Value -ne $Version) { continue }

    # The card supplies the version heading. Leave Markdown section headings
    # and bullets for its shared renderer.
    $notes = ($body -replace "(?m)^##[ \t]+v$versionPattern(?:[ \t]+[^\r\n]*)?[ \t]*\r?\n", '').Trim()
    if ($notes) { break }
}

if (!$notes) { exit 1 }
[IO.File]::WriteAllText($OutputPath, $notes, [Text.UTF8Encoding]::new($false))
