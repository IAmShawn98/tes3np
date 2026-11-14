param(
    [Parameter(Mandatory)][ValidatePattern('\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?:alpha|beta)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z')][string]$Version,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$baseUri = 'https://api.github.com/repos/IAmShawn98/tes3np/releases/tags'
$headers = @{ 'User-Agent' = 'tes3np-launcher'; 'Accept' = 'application/vnd.github+json' }
$versionPattern = [regex]::Escape($Version)
$tag = "v$Version"
try {
    $release = Invoke-RestMethod -Uri "$baseUri/$tag" -Headers $headers -TimeoutSec 5
} catch {
    exit 1
}
if ($release.draft -or $release.tag_name -cne $tag) { exit 1 }
$body = ([string]$release.body).Trim()
$heading = [regex]::Match($body, '(?m)^##[ \t]+v(\S+)')
if ($heading.Success -and $heading.Groups[1].Value -cne $Version) { exit 1 }

# The card supplies the version heading. Preserve Markdown categories and bullets.
$notes = ($body -replace "(?m)^##[ \t]+v$versionPattern(?:[ \t]+[^\r\n]*)?[ \t]*\r?\n", '').Trim()
if (!$notes) { exit 1 }
[IO.File]::WriteAllText($OutputPath, $notes, [Text.UTF8Encoding]::new($false))
