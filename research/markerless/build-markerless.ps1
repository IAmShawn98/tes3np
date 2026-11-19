param([string]$WorkRoot = 'C:\tes3mp-markerless-build')

$ErrorActionPreference = 'Stop'
$sourceRevision = '68954091c54d0596037c4fb54d2812313b7582a1'
$networkRevision = '19e66190e83f53bcdcbcd6513238ed2e54878a21'
$generator = 'Visual Studio 17 2022'

function Invoke-BuildTool([string]$Tool, [string[]]$Arguments) {
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Tool exited with code $LASTEXITCODE." }
}

function Get-PinnedSource([string]$Url, [string]$Revision, [string]$Path) {
    New-Item -ItemType Directory -Path $Path | Out-Null
    Invoke-BuildTool git @('-C', $Path, 'init', '--quiet')
    Invoke-BuildTool git @('-C', $Path, 'fetch', '--depth', '1', $Url, $Revision)
    Invoke-BuildTool git @('-C', $Path, 'checkout', '--quiet', '--detach', 'FETCH_HEAD')
}

function Save-Client([string]$Variant, [string]$BuildDir, [string]$OutputDir) {
    $binary = @(Get-ChildItem -LiteralPath $BuildDir -Filter tes3mp.exe -File -Recurse)
    if ($binary.Count -ne 1) { throw "Expected one tes3mp.exe in $BuildDir, found $($binary.Count)." }
    $destination = Join-Path $OutputDir $Variant
    New-Item -ItemType Directory -Path $destination | Out-Null
    $executable = Join-Path $destination 'tes3mp.exe'
    Copy-Item -LiteralPath $binary[0].FullName -Destination $executable
    return (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
}

$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
if ($WorkRoot -match '\s') { throw 'The upstream dependency script requires a build path without spaces.' }
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
$work = Join-Path $WorkRoot ([Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
Write-Host "Build directory: $work"

$git = (Get-Command git.exe).Source
$bash = Join-Path (Split-Path (Split-Path $git)) 'bin\bash.exe'
if (!(Test-Path -LiteralPath $bash)) { throw 'Git for Windows Bash is required.' }
foreach ($tool in @('cmake.exe', 'python.exe', '7z.exe')) { Get-Command $tool -ErrorAction Stop | Out-Null }

$source = Join-Path $work 'tes3mp'
$network = Join-Path $work 'crabnet'
$networkInstall = Join-Path $work 'crabnet-install'
$networkBuild = Join-Path $work 'crabnet-build'
$output = Join-Path $work 'output'
$patch = Join-Path $PSScriptRoot 'tes3mp-0.8.1-markerless-experimental.patch'

Get-PinnedSource 'https://github.com/TES3MP/TES3MP.git' $sourceRevision $source
Get-PinnedSource 'https://github.com/TES3MP/CrabNet.git' $networkRevision $network
Invoke-BuildTool git @('-C', $source, 'apply', '--check', $patch)

Write-Host 'Building the CrabNet static library'
Invoke-BuildTool cmake @('-S', $network, '-B', $networkBuild, '-G', $generator, '-A', 'x64', '-DCRABNET_ENABLE_DLL=OFF')
Invoke-BuildTool cmake @('--build', $networkBuild, '--config', 'Release', '--target', 'RakNetLibStatic', '--parallel', '2')
Invoke-BuildTool cmake @('--install', $networkBuild, '--config', 'Release', '--prefix', $networkInstall)
$env:RAKNET_ROOT = $networkInstall.Replace('\', '/')

# Reuse upstream's dependency archive versions and compiler library layout.
# Preinstall the matching Qt kit using aqt's maintained install command.
$build = Join-Path $source 'MSVC2019_64'
$qt = Join-Path $build 'deps\Qt'
Invoke-BuildTool python @('-m', 'venv', (Join-Path $work 'aqt'))
$python = Join-Path $work 'aqt\Scripts\python.exe'
Invoke-BuildTool $python @('-m', 'pip', 'install', 'aqtinstall==3.1.21')
Invoke-BuildTool $python @('-m', 'aqt', 'install-qt', 'windows', 'desktop', '5.15.0', 'win64_msvc2019_64', '-O', $qt)
if (!(Test-Path -LiteralPath (Join-Path $qt '5.15.0\msvc2019_64\bin\qmake.exe'))) {
    throw 'Qt 5.15.0 installation did not produce the expected MSVC x64 kit.'
}

# Adapt the upstream helper in this disposable checkout for VS 2022.
# The stock and markerless executables both use this same configuration.
$helper = Join-Path $source 'CI\before_script.msvc.sh'
$helperText = [IO.File]::ReadAllText($helper).Replace("`r`n", "`n")
$oldGenerator = 'GENERATOR="Visual Studio 16 2019"'
$oldConfigure = 'run_cmd cmake .. $CMAKE_OPTS || RET=$?'
if (!$helperText.Contains($oldGenerator) -or !$helperText.Contains($oldConfigure)) {
    throw 'Upstream Windows helper did not match the pinned build recipe.'
}
$helperText = $helperText.Replace('curl --retry 10', 'curl --fail --retry 3').Replace('curl --silent --retry 10', 'curl --fail --silent --show-error --retry 3')
$helperText = $helperText.Replace($oldGenerator, "GENERATOR=`"$generator`"")
$helperText = $helperText.Replace($oldConfigure, @'
run_cmd cmake .. $CMAKE_OPTS -DBUILD_OPENMW_MP=OFF -DBUILD_BROWSER=OFF -DBUILD_LAUNCHER=OFF -DBUILD_WIZARD=OFF -DBUILD_OPENCS=OFF -DBUILD_MWINIIMPORTER=OFF -DBUILD_ESSIMPORTER=OFF -DBUILD_BSATOOL=OFF -DBUILD_ESMTOOL=OFF -DBUILD_NIFTEST=OFF "-DRakNet_LIBRARY_DEBUG=$RAKNET_ROOT/lib/RakNetLibStatic.lib" || RET=$?
'@.Trim())
[IO.File]::WriteAllText($helper, $helperText, [Text.UTF8Encoding]::new($false))
$env:STEP = 'openmw'

Write-Host 'Configuring the stock TES3MP client'
Push-Location $source
try {
    Invoke-BuildTool $bash @('CI/before_script.msvc.sh', '-c', 'Release', '-p', 'Win64', '-v', '2019', '-k', '-V')
} finally {
    Pop-Location
}
# MSVC 2022 no longer provides std::chrono through the old transitive headers.
$miscExtensions = Join-Path $source 'apps\openmw\mwscript\miscextensions.cpp'
$miscText = [IO.File]::ReadAllText($miscExtensions)
$include = '#include <cstdlib>'
if (!$miscText.Contains($include)) { throw 'Could not locate the pinned misc extensions include.' }
[IO.File]::WriteAllText($miscExtensions, $miscText.Replace($include, "#include <chrono>`r`n$include"), [Text.UTF8Encoding]::new($false))

Write-Host 'Building the stock TES3MP client'
Invoke-BuildTool cmake @('--build', $build, '--config', 'Release', '--target', 'tes3mp', '--parallel', '2')
New-Item -ItemType Directory -Path $output | Out-Null
$stockHash = Save-Client 'stock' $build $output

Write-Host 'Applying the markerless patch and rebuilding the TES3MP client'
Invoke-BuildTool git @('-C', $source, 'apply', $patch)
Invoke-BuildTool git @('-C', $source, 'diff', '--check')
Invoke-BuildTool cmake @('--build', $build, '--config', 'Release', '--target', 'tes3mp', '--parallel', '2')
$markerlessHash = Save-Client 'markerless' $build $output
if ($stockHash -eq $markerlessHash) { throw 'The two client executables have identical hashes.' }

@(
    "TES3MP source: $sourceRevision"
    "CrabNet source: $networkRevision"
    "$stockHash  stock/tes3mp.exe"
    "$markerlessHash  markerless/tes3mp.exe"
) | Set-Content -LiteralPath (Join-Path $output 'build-info.txt') -Encoding ASCII
Copy-Item -LiteralPath $patch, $PSCommandPath -Destination $output
if ($env:GITHUB_OUTPUT) { "directory=$output" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append }
Write-Host "Built both clients in $output"
