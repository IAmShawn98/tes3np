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
function Invoke-Compiler([string]$Compiler,[string]$Arguments,[string]$Label,[int]$TimeoutMs) {
    Step "Starting $Label"
    $process = Start-Process $Compiler -ArgumentList $Arguments -PassThru
    if (!$process.WaitForExit($TimeoutMs)) {
        try { $process.Kill() } catch {}
        Get-Process AutoHotkey*,Ahk2Exe -ErrorAction SilentlyContinue | ForEach-Object { Step ("Lingering process after timeout: {0} PID {1}" -f $_.ProcessName,$_.Id) }
        throw "$Label timed out after $([int]($TimeoutMs/1000)) seconds."
    }
    Step "$Label exited with code $($process.ExitCode)"
    return $process.ExitCode
}
try {
    Step 'Starting Windows launcher build'
    $ahkZip = Get-ReleaseTool 'AutoHotkey/AutoHotkey' '^AutoHotkey_2\.0\..+\.zip$' 'autohotkey.zip'
    $compilerZip = Get-ReleaseTool 'AutoHotkey/Ahk2Exe' '\.zip$' 'compiler.zip'
    $tools = Join-Path $buildRoot 'tools'
    Step 'Extracting AutoHotkey runtime'; Expand-Archive $ahkZip $tools
    Step 'Extracting Ahk2Exe compiler'; Expand-Archive $compilerZip (Join-Path $tools 'Compiler')
    $compiler = Join-Path $tools 'Compiler\Ahk2Exe.exe'; $base = Join-Path $tools 'AutoHotkey64.exe'; $package = Join-Path $buildRoot 'tes3np'
    $null = New-Item $package -ItemType Directory

    $smokeSource = Join-Path $buildRoot 'compiler-smoke.ahk'; $smokeExe = Join-Path $buildRoot 'compiler-smoke.exe'
    Set-Content $smokeSource "#Requires AutoHotkey v2.0`nExitApp(0)`n" -Encoding UTF8
    $smokeArgs = '/in "' + $smokeSource + '" /out "' + $smokeExe + '" /base "' + $base + '" /compress 0 /silent verbose'
    $smokeCode = Invoke-Compiler $compiler $smokeArgs 'Ahk2Exe smoke compilation' 45000
    if ($smokeCode -ne 0 -or !(Test-Path $smokeExe)) { throw 'Ahk2Exe smoke compilation failed.' }

    $mainRoot = Join-Path $buildRoot 'main-source'
    Step 'Fetching known-good main source for control build'
    & git fetch --no-tags --depth=1 origin main:refs/remotes/origin/main
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch main for control build.' }
    Step 'Checking out known-good main source for control build'
    & git -c advice.detachedHead=false worktree add --detach $mainRoot refs/remotes/origin/main
    if ($LASTEXITCODE -ne 0) { throw 'Could not create main control worktree.' }
    $mainSource = Join-Path $mainRoot 'tes3np.ahk'; $mainExe = Join-Path $buildRoot 'main-control.exe'
    $mainArgs = '/in "' + $mainSource + '" /out "' + $mainExe + '" /icon "' + (Join-Path $mainRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    $mainCode = Invoke-Compiler $compiler $mainArgs 'Known-good main launcher control compilation' 120000
    if ($mainCode -ne 0 -or !(Test-Path $mainExe)) { throw 'Known-good main launcher control compilation failed.' }
    Step 'Known-good main launcher compiled successfully with current toolchain'

    # Hybrid A: only update-check.ahk from the updater branch.
    Step 'Preparing main + updater update-check.ahk hybrid control'
    Copy-Item (Join-Path $projectRoot 'src\app\update-check.ahk') (Join-Path $mainRoot 'src\app\update-check.ahk') -Force
    $hybridExe = Join-Path $buildRoot 'hybrid-update-check.exe'
    $hybridArgs = '/in "' + $mainSource + '" /out "' + $hybridExe + '" /icon "' + (Join-Path $mainRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    $hybridCode = Invoke-Compiler $compiler $hybridArgs 'Hybrid main + updater update-check compilation' 60000
    if ($hybridCode -ne 0 -or !(Test-Path $hybridExe)) { throw 'Hybrid update-check compilation failed.' }
    Step 'Hybrid update-check compiled successfully'

    # Hybrid B: now replace only the entrypoint with the updater branch version. Since Hybrid A
    # already contains updater update-check.ahk, this tests the exact interaction of the two changed
    # AHK files while every other source file remains the known-good main revision.
    Step 'Preparing main + updater update-check + updater tes3np.ahk hybrid control'
    Copy-Item (Join-Path $projectRoot 'tes3np.ahk') $mainSource -Force
    $entryExe = Join-Path $buildRoot 'hybrid-entrypoint.exe'
    $entryArgs = '/in "' + $mainSource + '" /out "' + $entryExe + '" /icon "' + (Join-Path $mainRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    $entryCode = Invoke-Compiler $compiler $entryArgs 'Hybrid with updater tes3np.ahk compilation' 60000
    if ($entryCode -ne 0 -or !(Test-Path $entryExe)) { throw 'Hybrid updater entrypoint compilation failed.' }
    Step 'Hybrid updater entrypoint compiled successfully; regression is outside the changed AHK source pair'

    $source = Join-Path $projectRoot 'tes3np.ahk'; $executable = Join-Path $package 'tes3np.exe'
    $arguments = '/in "' + $source + '" /out "' + $executable + '" /icon "' + (Join-Path $projectRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    $compileCode = Invoke-Compiler $compiler $arguments 'Updater-branch tes3np compilation' 120000
    if ($compileCode -ne 0 -or !(Test-Path $executable)) { throw 'Launcher compilation failed.' }
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
    Step 'Compressing final Windows package'; Compress-Archive $package $archive -CompressionLevel Optimal
    Step "Build complete: $archive"
}
finally {
    if ($mainRoot -and (Test-Path $mainRoot)) { & git worktree remove --force $mainRoot 2>$null }
    Step 'Cleaning temporary build directory'; Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}
