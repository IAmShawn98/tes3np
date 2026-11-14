param(
    [string]$PackagePath = 'dist/tes3np-windows.zip',
    [string]$ManifestPath = 'dist/tes3np-update.json',
    [string]$ChecksumPath,
    [switch]$ChannelFeed,
    [switch]$DisableUpdates
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
    throw "Update package not found: $PackagePath"
}

$statePath = 'src/state.ahk'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "Launcher state file not found: $statePath"
}

$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8
$match = [regex]::Match($state, 'AppConfig\s*:=\s*\{Version:\s*"([^"]+)"')
if (-not $match.Success) {
    throw 'Could not determine launcher version from src/state.ahk.'
}

$version = $match.Groups[1].Value.Trim()
$versionPattern = '\A(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})\.(?:0|[1-9][0-9]{0,8})(?:-(?<channel>alpha|beta)(?:\.[1-9][0-9]{0,8})?|\.[1-9][0-9]{0,8})?\z'
$parsedVersion = [regex]::Match($version, $versionPattern)
if (!$parsedVersion.Success) {
    throw "Launcher version has an unexpected format: $version"
}

$package = Get-Item -LiteralPath $PackagePath
$channel = $parsedVersion.Groups['channel'].Value
if (!$channel) { $channel = 'live' }
if ($ChannelFeed) {
    if ($package.Name -cne "tes3np-v$version-windows.zip") {
        throw "The channel feed requires package tes3np-v$version-windows.zip."
    }
} elseif ($channel -ne 'alpha' -or $package.Name -cne 'tes3np-windows.zip') {
    throw 'Legacy update metadata requires an alpha build and tes3np-windows.zip.'
}
if (!$ChecksumPath) { $ChecksumPath = "$PackagePath.sha256" }
$hash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$revision = if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { 'local' }
# Source snapshots can generate metadata without a Git checkout. A linked
# worktree has a .git file, while a regular checkout has a .git directory.
if ($ChannelFeed -and (Test-Path -LiteralPath '.git') -and
    (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
    $head = git rev-parse --verify --quiet HEAD
    if ($LASTEXITCODE -eq 0) { $revision = $head }
}
$schema = if ($ChannelFeed) { 2 } else { 1 }

$manifest = [ordered]@{
    manifestVersion = $schema
    product = 'tes3np'
    channel = $channel
    version = $version
    releaseId = "v$version"
    platform = 'windows'
    architecture = 'x64'
    package = [ordered]@{
        fileName = $package.Name
        size = [int64]$package.Length
        sha256 = $hash
    }
    sourceRevision = $revision
    updateEnabled = !$DisableUpdates
}

$manifestJson = $manifest | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ManifestPath, $manifestJson + "`n", $utf8NoBom)
[IO.File]::WriteAllText($ChecksumPath, "$hash  $($package.Name)`n", $utf8NoBom)

# Read the generated files back and fail the build if they disagree with the package.
$roundTrip = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($roundTrip.manifestVersion -ne $schema -or $roundTrip.product -ne 'tes3np') {
    throw 'Generated update manifest failed identity validation.'
}
if ($roundTrip.version -cne $version -or $roundTrip.channel -cne $channel -or
    $roundTrip.releaseId -cne "v$version" -or $roundTrip.updateEnabled -ne (!$DisableUpdates)) {
    throw 'Generated update manifest failed version/channel validation.'
}
if ($roundTrip.package.fileName -ne $package.Name -or [int64]$roundTrip.package.size -ne [int64]$package.Length) {
    throw 'Generated update manifest failed package metadata validation.'
}
if ($roundTrip.package.sha256 -ne $hash) {
    throw 'Generated update manifest failed SHA-256 validation.'
}

Write-Host "Generated update metadata for tes3np v$version"
Write-Host "Package: $($package.Name) ($($package.Length) bytes)"
Write-Host "SHA-256: $hash"
