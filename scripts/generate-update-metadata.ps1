param(
    [string]$PackagePath = 'dist/tes3np-windows.zip',
    [string]$ManifestPath = 'dist/tes3np-update.json',
    [string]$ChecksumPath = 'dist/tes3np-windows.zip.sha256'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
    throw "Update package not found: $PackagePath"
}

$statePath = 'src/state.ahk'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "Launcher state file not found: $statePath"
}

$state = [IO.File]::ReadAllText($statePath)
$match = [regex]::Match($state, 'AppConfig\s*:=\s*\{Version:\s*"([^"]+)"')
if (-not $match.Success) {
    throw 'Could not determine launcher version from src/state.ahk.'
}

$version = $match.Groups[1].Value.Trim()
if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "Launcher version has an unexpected format: $version"
}

$package = Get-Item -LiteralPath $PackagePath
$hash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$revision = if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { 'local' }

$manifest = [ordered]@{
    manifestVersion = 1
    product = 'tes3np'
    channel = 'alpha'
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
    updateEnabled = $true
}

$manifestJson = $manifest | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ManifestPath, $manifestJson + "`n", $utf8NoBom)
[IO.File]::WriteAllText($ChecksumPath, "$hash  $($package.Name)`n", $utf8NoBom)

# Read the generated files back and fail the build if they disagree with the package.
$roundTrip = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($roundTrip.manifestVersion -ne 1 -or $roundTrip.product -ne 'tes3np') {
    throw 'Generated update manifest failed identity validation.'
}
if ($roundTrip.version -ne $version -or $roundTrip.channel -ne 'alpha') {
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
