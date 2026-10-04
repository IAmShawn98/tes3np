# Build a portable launcher using official AutoHotkey release tools.
[CmdletBinding()]
param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (!$OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'dist' }
$null = New-Item $OutputDirectory -ItemType Directory -Force
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('tes3np-build-' + [guid]::NewGuid())
$null = New-Item $buildRoot -ItemType Directory
function Step([string]$Message) { Write-Host "BUILD CHECKPOINT | $Message" }
function Get-ReleaseTool([string]$Repository, [string]$Pattern, [string]$Name) {
    Step "Querying $Repository release metadata"
    $headers = @{ 'User-Agent' = 'tes3np-build'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    $release = Invoke-RestMethod ("https://api.github.com/repos/$Repository/releases/latest") -Headers $headers -TimeoutSec 30
    $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
    if (!$asset) { throw "Official release has no matching archive: $Repository $Pattern" }
    $file = Join-Path $buildRoot $Name
    Step "Downloading $Repository $($release.tag_name): $($asset.name)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $file -UseBasicParsing -TimeoutSec 120
    Step "Downloaded $Name; verifying checksum"
    if ($asset.digest -match '^sha256:(.+)$') { if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $Matches[1]) { throw "Downloaded tool checksum did not match: $Name" } }
    Add-Content (Join-Path $buildRoot 'BUILD-TOOLS.txt') ("$Repository $($release.tag_name) $($asset.name) SHA256 " + (Get-FileHash $file -Algorithm SHA256).Hash)
    return $file
}
try {
    Step 'Starting Windows launcher build'
    $ahkZip = Get-ReleaseTool 'AutoHotkey/AutoHotkey' '^AutoHotkey_2\.0\..+\.zip$' 'autohotkey.zip'
    $compilerZip = Get-ReleaseTool 'AutoHotkey/Ahk2Exe' '\.zip$' 'compiler.zip'
    $tools = Join-Path $buildRoot 'tools'
    Step 'Extracting AutoHotkey runtime'
    Expand-Archive $ahkZip $tools
    Step 'Extracting Ahk2Exe compiler'
    Expand-Archive $compilerZip (Join-Path $tools 'Compiler')
    $compiler = Join-Path $tools 'Compiler\Ahk2Exe.exe'; $base = Join-Path $tools 'AutoHotkey64.exe'; $package = Join-Path $buildRoot 'tes3np'
    $null = New-Item $package -ItemType Directory
    $executable = Join-Path $package 'tes3np.exe'
    $arguments = '/in "' + (Join-Path $projectRoot 'tes3np.ahk') + '" /out "' + $executable + '" /icon "' + (Join-Path $projectRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    Step 'Starting Ahk2Exe compilation (120 second timeout)'
    $process = Start-Process $compiler -ArgumentList $arguments -PassThru
    if (!$process.WaitForExit(120000)) { try { $process.Kill() } catch {}; throw 'Ahk2Exe compilation timed out after 120 seconds.' }
    Step "Ahk2Exe exited with code $($process.ExitCode)"
    if ($process.ExitCode -ne 0 -or !(Test-Path $executable)) { throw 'Launcher compilation failed.' }
    Step 'Starting compiled launcher --check (30 second timeout)'
    $check = Start-Process $executable -ArgumentList '--check' -PassThru
    if (!$check.WaitForExit(30000)) { try { $check.Kill() } catch {}; throw 'Compiled launcher validation timed out after 30 seconds.' }
    Step "Compiled launcher --check exited with code $($check.ExitCode)"
    if ($check.ExitCode -ne 0) { throw 'Compiled launcher validation failed.' }
    Step 'Copying package payload'
    foreach ($folder in @('assets','patches')) { Copy-Item (Join-Path $projectRoot $folder) $package -Recurse }
    $scripts = Join-Path $package 'scripts'; $null = New-Item $scripts -ItemType Directory
    foreach ($worker in @('import-macro.ps1','patch-tes3mp.ps1','tes3np-updater.ps1')) { Copy-Item (Join-Path $PSScriptRoot $worker) $scripts }
    $runtime = Join-Path $package 'runtime'; $null = New-Item $runtime -ItemType Directory; Copy-Item $base $runtime
    $license = Get-ChildItem $tools -File | Where-Object { $_.Name -match '^(license|copying)(\..*)?$' } | Select-Object -First 1
    if (!$license) { throw 'AutoHotkey license is missing from the official archive.' }
    Copy-Item $license.FullName (Join-Path $runtime 'LICENSE.txt'); Copy-Item (Join-Path $buildRoot 'BUILD-TOOLS.txt') $package; Copy-Item (Join-Path $projectRoot 'docs\INSTALLATION.md') (Join-Path $package 'INSTALLATION.md')
    Set-Content (Join-Path $package 'START-HERE.txt') "TES3NP - Nerevarine Prophecies Launcher`n`nExtract this entire folder into your TES3MP 0.8.1 Win64 folder and run tes3np.exe.`nSee INSTALLATION.md for help." -Encoding UTF8
    $archive = Join-Path $OutputDirectory 'tes3np-windows.zip'; if (Test-Path $archive) { Remove-Item $archive }
    Step 'Compressing final Windows package'
    Compress-Archive $package $archive -CompressionLevel Optimal
    Step "Build complete: $archive"
}
finally { Step 'Cleaning temporary build directory'; Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue }
