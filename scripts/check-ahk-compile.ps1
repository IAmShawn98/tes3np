# CI-only: compile the actual AHK launcher without downloading TES3MP
# or packaging a distribution. Catches Ahk2Exe errors that static checks miss.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:RUNNER_TEMP 'tes3np-ahk-compiler-check'
New-Item -Path $work -ItemType Directory -Force | Out-Null
$headers = @{ 'User-Agent' = 'tes3np-source-validation'; 'Accept' = 'application/vnd.github+json' }
if ($env:GITHUB_TOKEN) { $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN }

function Download-VerifiedTool([string]$Repository, [string]$NamePattern, [string]$Label) {
    $release = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $Repository + '/releases/latest') -Headers $headers -TimeoutSec 60
    $asset = $release.assets | Where-Object { $_.name -match $NamePattern } | Select-Object -First 1
    if (!$asset -or $asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw "No SHA-256 verified official $Label ZIP was published."
    }
    $expected = $Matches[1]
    $dest = Join-Path $work ($Label + '.zip')
    $sources = @($asset.browser_download_url)
    if ($Label -eq 'autohotkey') {
        $sources += 'https://docs.autohotkey.com/download/2.0/' + $asset.name
    }
    foreach ($url in $sources) {
        for ($attempt=1; $attempt -le 2; $attempt++) {
            try {
                if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Force }
                # Public release downloads/mirrors never receive the Actions token.
                Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = 'tes3np-source-validation' } -OutFile $dest -UseBasicParsing -TimeoutSec 120
                if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ine $expected) {
                    throw "Official $Label ZIP SHA-256 mismatch."
                }
                $extract = Join-Path $work $Label
                Expand-Archive -LiteralPath $dest -DestinationPath $extract -Force
                Write-Host "Verified official $Label release archive."
                return $extract
            }
            catch {
                if ($attempt -eq 2) { Write-Host "$Label source failed; trying fallback if available." }
                else { Start-Sleep -Seconds 2 }
            }
        }
    }
    throw "Could not download a SHA-256 verified official $Label compiler tool."
}

$ahkRoot = Download-VerifiedTool 'AutoHotkey/AutoHotkey' '^AutoHotkey_2\.0\.\d+\.zip$' 'autohotkey'
$compilerRoot = Download-VerifiedTool 'AutoHotkey/Ahk2Exe' '^Ahk2Exe[0-9A-Za-z.]+\.zip$' 'ahk2exe'
$base = Get-ChildItem -LiteralPath $ahkRoot -Recurse -Filter 'AutoHotkey64.exe' -File | Select-Object -First 1 -ExpandProperty FullName
$compiler = Get-ChildItem -LiteralPath $compilerRoot -Recurse -Filter 'Ahk2Exe.exe' -File | Select-Object -First 1 -ExpandProperty FullName
if (!$base -or !$compiler) { throw 'Verified AutoHotkey tools were not extracted.' }

$launcher = Join-Path $projectRoot 'tes3np.ahk'
Write-Host 'Parsing complete AutoHotkey launcher (no game or UI startup).'
$parseStdout = Join-Path $work 'parse-stdout.txt'
$parseStderr = Join-Path $work 'parse-stderr.txt'
$parseArguments = '/ErrorStdOut "' + $launcher + '" --check'
$parse = Start-Process -FilePath $base -WorkingDirectory $projectRoot -ArgumentList $parseArguments -PassThru -Wait -RedirectStandardOutput $parseStdout -RedirectStandardError $parseStderr
$output = @()
if (Test-Path $parseStdout) { $output += @(Get-Content $parseStdout) }
if (Test-Path $parseStderr) { $output += @(Get-Content $parseStderr) }
$output | ForEach-Object { Write-Host $_ }
Write-Host "AutoHotkey parser process exit: $($parse.ExitCode)"
if ($parse.ExitCode -ne 0 -or $output -match '(?i)Warning:|appears to never be assigned|This line will never execute') {
    throw 'AutoHotkey source parse/warning check failed.'
}

Write-Host 'Compiling the real launcher through verified Ahk2Exe.'
$exe = Join-Path $work 'tes3np-ci-smoke.exe'
$stdout = Join-Path $work 'compiler-stdout.txt'
$stderr = Join-Path $work 'compiler-stderr.txt'
$args = '/in "' + $launcher + '" /out "' + $exe + '" /base "' + $base + '" /compress 0 /silent verbose'
$process = Start-Process -FilePath $compiler -WorkingDirectory $projectRoot -ArgumentList $args -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if (Test-Path $stdout) { Get-Content $stdout | ForEach-Object { Write-Host $_ } }
if (Test-Path $stderr) { Get-Content $stderr | ForEach-Object { Write-Host $_ } }
if ($process.ExitCode -ne 0 -or !(Test-Path -LiteralPath $exe)) {
    throw "Ahk2Exe launcher compile failed with exit code $($process.ExitCode)."
}
Write-Host 'Probing compiled native Expansion Pack UI function bindings without launching UI.'
$probe = Start-Process -FilePath $exe -ArgumentList '--check-expansion-ui' -WorkingDirectory $projectRoot -PassThru -Wait
if ($probe.ExitCode -ne 0) {
    throw "Compiled launcher Expansion Pack UI function probe failed with exit code $($probe.ExitCode)."
}
Write-Host 'Running real native download card smoke test on a disposable window.'
$nativeOut = Join-Path $work 'native-window-stdout.txt'
$nativeErr = Join-Path $work 'native-window-stderr.txt'
$nativeArgs = '/ErrorStdOut "' + $launcher + '" --check-expansion-window'
$nativeProcess = Start-Process -FilePath $base -WorkingDirectory $projectRoot -ArgumentList $nativeArgs -PassThru -RedirectStandardOutput $nativeOut -RedirectStandardError $nativeErr
if (!$nativeProcess.WaitForExit(45000)) {
    try { Stop-Process -Id $nativeProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw 'Native Expansion GUI initialization smoke test timed out.'
}
if (Test-Path $nativeOut) { Get-Content $nativeOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $nativeErr) { Get-Content $nativeErr | ForEach-Object { Write-Host $_ } }
if ($nativeProcess.ExitCode -ne 0) {
    throw "Native Expansion downloader window setup failed with code $($nativeProcess.ExitCode)."
}
Write-Host 'PASS: actual native downloader window and custom Cancel initialized.'
Write-Host 'Testing actual Windows compositor staging for first-paint-ready launcher pages.'
$pageOut = Join-Path $work 'page-compositor-stdout.txt'
$pageErr = Join-Path $work 'page-compositor-stderr.txt'
$pageArgs = '/ErrorStdOut "' + $launcher + '" --check-page-compositor'
$pageTest = Start-Process -FilePath $base -WorkingDirectory $projectRoot -ArgumentList $pageArgs -PassThru -RedirectStandardOutput $pageOut -RedirectStandardError $pageErr
if (!$pageTest.WaitForExit(30000)) {
    try { Stop-Process -Id $pageTest.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw 'Page compositor staging smoke test timed out.'
}
if (Test-Path $pageOut) { Get-Content $pageOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $pageErr) { Get-Content $pageErr | ForEach-Object { Write-Host $_ } }
if ($pageTest.ExitCode -ne 0) {
    throw "Page compositor staging smoke test failed with code $($pageTest.ExitCode)."
}
Write-Host 'PASS: staged native page withheld from DWM until complete paint.'
Write-Host 'Checking fast native Character Book close with an already-painted launcher.'
$bookOut = Join-Path $work 'character-return-stdout.txt'
$bookErr = Join-Path $work 'character-return-stderr.txt'
$bookArgs = '/ErrorStdOut "' + $launcher + '" --check-cached-character-return'
$bookProcess = Start-Process -FilePath $base -WorkingDirectory $projectRoot -ArgumentList $bookArgs -PassThru -RedirectStandardOutput $bookOut -RedirectStandardError $bookErr
if (!$bookProcess.WaitForExit(30000)) {
    try { Stop-Process -Id $bookProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw 'Cached Character Book close smoke test timed out.'
}
if (Test-Path $bookOut) { Get-Content $bookOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $bookErr) { Get-Content $bookErr | ForEach-Object { Write-Host $_ } }
if ($bookProcess.ExitCode -ne 0) {
    throw "Cached Character Book close smoke test failed with code $($bookProcess.ExitCode)."
}
Write-Host 'PASS: cached Character Book closes without a global control redraw.'
Write-Host 'Testing menu scale and owner-relative placement after moving parent on Windows.'
$menuOut = Join-Path $work 'menu-scale-stdout.txt'
$menuErr = Join-Path $work 'menu-scale-stderr.txt'
$menuArgs = '/ErrorStdOut "' + $launcher + '" --check-owned-menu-scaling'
$menuTest = Start-Process -FilePath $base -WorkingDirectory $projectRoot -ArgumentList $menuArgs -PassThru -RedirectStandardOutput $menuOut -RedirectStandardError $menuErr
if (!$menuTest.WaitForExit(30000)) {
    try { Stop-Process -Id $menuTest.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw 'Owned menu placement/scale test timed out.'
}
if (Test-Path $menuOut) { Get-Content $menuOut | ForEach-Object { Write-Host $_ } }
if (Test-Path $menuErr) { Get-Content $menuErr | ForEach-Object { Write-Host $_ } }
if ($menuTest.ExitCode -ne 0) {
    throw "Owned menu placement/scale test failed with code $($menuTest.ExitCode)."
}
Write-Host 'PASS: owner-moved menu stays centered and control sizes match launcher percent.'
Write-Host 'PASS: complete launcher parsed and compiled; Expansion Pack UI functions resolved.'
