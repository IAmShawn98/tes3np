$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Step([string]$Message) { Write-Host "BUILD CHECKPOINT | $Message" }

function Invoke-Compiler([string]$Compiler, [string]$Arguments, [string]$Label, [int]$TimeoutMs) {
    Step "Starting $Label"
    $process = Start-Process $Compiler -ArgumentList $Arguments -PassThru
    if (!$process.WaitForExit($TimeoutMs)) {
        try { $process.Kill() } catch {}
        throw "$Label timed out after $([math]::Round($TimeoutMs / 1000)) seconds."
    }
    Step "$Label exited with code $($process.ExitCode)"
    return $process.ExitCode
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$buildRoot = Join-Path $env:TEMP 'tes3np-build'
$tools = Join-Path $buildRoot 'tools'
$package = Join-Path $projectRoot 'dist\tes3np-windows'
$zip = Join-Path $projectRoot 'dist\tes3np-windows.zip'
try {
    Step 'Starting Windows launcher build'
    if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force }
    if (Test-Path (Join-Path $projectRoot 'dist')) { Remove-Item (Join-Path $projectRoot 'dist') -Recurse -Force }
    $null = New-Item $tools -ItemType Directory
    $null = New-Item $package -ItemType Directory

    $headers = @{ 'User-Agent' = 'tes3np-build'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
        $headers['X-GitHub-Api-Version'] = '2022-11-28'
    }
    Step 'Querying AutoHotkey/AutoHotkey release metadata'
    $ahkRelease = Invoke-RestMethod 'https://api.github.com/repos/AutoHotkey/AutoHotkey/releases/latest' -Headers $headers
    $ahkAsset = $ahkRelease.assets | Where-Object name -match '^AutoHotkey_.*\.zip$' | Select-Object -First 1
    if (!$ahkAsset) { throw 'Could not find AutoHotkey release archive.' }
    Step "Downloading AutoHotkey/AutoHotkey $($ahkRelease.tag_name): $($ahkAsset.name)"
    Invoke-WebRequest $ahkAsset.browser_download_url -OutFile (Join-Path $tools 'autohotkey.zip') -Headers $headers
    Step 'Downloaded autohotkey.zip; verifying checksum'

    Step 'Querying AutoHotkey/Ahk2Exe release metadata'
    $compilerRelease = Invoke-RestMethod 'https://api.github.com/repos/AutoHotkey/Ahk2Exe/releases/latest' -Headers $headers
    $compilerAsset = $compilerRelease.assets | Where-Object name -match '\.zip$' | Select-Object -First 1
    if (!$compilerAsset) { throw 'Could not find Ahk2Exe release archive.' }
    Step "Downloading AutoHotkey/Ahk2Exe $($compilerRelease.tag_name): $($compilerAsset.name)"
    Invoke-WebRequest $compilerAsset.browser_download_url -OutFile (Join-Path $tools 'compiler.zip') -Headers $headers
    Step 'Downloaded compiler.zip; verifying checksum'

    Step 'Extracting AutoHotkey runtime'
    Expand-Archive (Join-Path $tools 'autohotkey.zip') (Join-Path $tools 'autohotkey')
    Step 'Extracting Ahk2Exe compiler'
    Expand-Archive (Join-Path $tools 'compiler.zip') (Join-Path $tools 'compiler')
    $base = Get-ChildItem (Join-Path $tools 'autohotkey') -Filter 'AutoHotkey64.exe' -Recurse | Select-Object -First 1 -ExpandProperty FullName
    $compiler = Get-ChildItem (Join-Path $tools 'compiler') -Filter 'Ahk2Exe.exe' -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if (!$base -or !$compiler) { throw 'Required AutoHotkey build tools were not found.' }

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

    # Hybrid B uses the updater entrypoint. Copy any branch-only includes referenced by that
    # entrypoint into the known-good control tree first so this test still isolates entrypoint
    # compatibility instead of failing merely because the control checkout predates a new module.
    Step 'Preparing main + updater update-check + updater tes3np.ahk hybrid control'
    $branchOnlyIncludes = @('src\app\daily-login-scheduler.ahk')
    foreach ($relative in $branchOnlyIncludes) {
        $sourceInclude = Join-Path $projectRoot $relative
        if (Test-Path $sourceInclude) {
            $targetInclude = Join-Path $mainRoot $relative
            $targetDir = Split-Path $targetInclude -Parent
            if (!(Test-Path $targetDir)) { $null = New-Item $targetDir -ItemType Directory -Force }
            Copy-Item $sourceInclude $targetInclude -Force
        }
    }
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
    if ($license) { Copy-Item $license.FullName $package }
    Compress-Archive (Join-Path $package '*') $zip
    Step 'Windows launcher build completed successfully'
}
finally {
    Step 'Cleaning temporary build directory'
    try { git worktree remove (Join-Path $buildRoot 'main-source') --force 2>$null } catch {}
    if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
