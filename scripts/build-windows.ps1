# Build a portable launcher using official AutoHotkey release tools.
[CmdletBinding()]
param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (!$OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'dist' }
$null = New-Item $OutputDirectory -ItemType Directory -Force
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('tes3np-build-' + [guid]::NewGuid())
$null = New-Item $buildRoot -ItemType Directory
function Get-ReleaseTool([string]$Repository, [string]$Pattern, [string]$Name) {
    $headers = @{ 'User-Agent' = 'tes3np-build'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    $release = Invoke-RestMethod ("https://api.github.com/repos/$Repository/releases/latest") -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
    if (!$asset) { throw "Official release has no matching archive: $Repository $Pattern" }
    $file = Join-Path $buildRoot $Name
    Write-Output "Downloading $Repository $($release.tag_name): $($asset.name)" | Out-Host
    Invoke-WebRequest $asset.browser_download_url -OutFile $file -UseBasicParsing
    if ($asset.digest -match '^sha256:(.+)$') {
        if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $Matches[1]) { throw "Downloaded tool checksum did not match: $Name" }
    }
    Add-Content (Join-Path $buildRoot 'BUILD-TOOLS.txt') ("$Repository $($release.tag_name) $($asset.name) SHA256 " + (Get-FileHash $file -Algorithm SHA256).Hash)
    return $file
}
try {
    $ahkZip = Get-ReleaseTool 'AutoHotkey/AutoHotkey' '^AutoHotkey_2\.0\..+\.zip$' 'autohotkey.zip'
    $compilerZip = Get-ReleaseTool 'AutoHotkey/Ahk2Exe' '\.zip$' 'compiler.zip'
    $tools = Join-Path $buildRoot 'tools'
    Expand-Archive $ahkZip $tools
    Expand-Archive $compilerZip (Join-Path $tools 'Compiler')
    $compiler = Join-Path $tools 'Compiler\Ahk2Exe.exe'
    $base = Join-Path $tools 'AutoHotkey64.exe'
    $package = Join-Path $buildRoot 'tes3np'
    $null = New-Item $package -ItemType Directory
    $executable = Join-Path $package 'tes3np.exe'
    $arguments = '/in "' + (Join-Path $projectRoot 'tes3np.ahk') + '" /out "' + $executable + '" /icon "' + (Join-Path $projectRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    $process = Start-Process $compiler -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0 -or !(Test-Path $executable)) { throw 'Launcher compilation failed.' }
    $check = Start-Process $executable -ArgumentList '--check' -PassThru
    if (!$check.WaitForExit(30000)) { $check.Kill(); throw 'Compiled launcher validation timed out.' }
    if ($check.ExitCode -ne 0) { throw 'Compiled launcher validation failed.' }
    foreach ($folder in @('assets', 'patches')) { Copy-Item (Join-Path $projectRoot $folder) $package -Recurse }
    $scripts = Join-Path $package 'scripts'
    $null = New-Item $scripts -ItemType Directory
    foreach ($worker in @('import-macro.ps1', 'patch-tes3mp.ps1', 'tes3np-updater.ps1')) { Copy-Item (Join-Path $PSScriptRoot $worker) $scripts }
    $runtime = Join-Path $package 'runtime'
    $null = New-Item $runtime -ItemType Directory
    Copy-Item $base $runtime
    $license = Get-ChildItem $tools -File | Where-Object { $_.Name -match '^(license|copying)(\..*)?$' } | Select-Object -First 1
    if (!$license) { throw 'AutoHotkey license is missing from the official archive.' }
    Copy-Item $license.FullName (Join-Path $runtime 'LICENSE.txt')
    Copy-Item (Join-Path $buildRoot 'BUILD-TOOLS.txt') $package
    Copy-Item (Join-Path $projectRoot 'docs\INSTALLATION.md') (Join-Path $package 'INSTALLATION.md')
    Set-Content (Join-Path $package 'START-HERE.txt') @'
TES3NP - Nerevarine Prophecies Launcher

1. Extract this entire folder into your TES3MP 0.8.1 Win64 folder.
2. Double-click tes3np.exe. Keep its accompanying folders together.
3. Choose Patch Tes3mp if shown, check the locations, and click Install / Repair.
4. Choose Start New Adventure or Returning Fetcher to play.

You need Morrowind GOTY and TES3MP installed. AutoHotkey is included;
you do not need to install it separately. See INSTALLATION.md for help.
'@ -Encoding UTF8
    $archive = Join-Path $OutputDirectory 'tes3np-windows.zip'
    if (Test-Path $archive) { Remove-Item $archive }
    Compress-Archive $package $archive -CompressionLevel Optimal
    Write-Output "Built $archive"
}
finally { Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue }
