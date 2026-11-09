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
                Invoke-WebRequest -Uri $url -Headers $headers -OutFile $dest -UseBasicParsing -TimeoutSec 120
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
$output = @(& $base /ErrorStdOut $launcher '--check' 2>&1)
$code = $LASTEXITCODE
$output | ForEach-Object { Write-Host $_ }
if ($null -eq $code -or $code -ne 0 -or $output -match '(?i)Warning:|appears to never be assigned|This line will never execute') {
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
Write-Host 'PASS: complete AutoHotkey launcher parsed and compiled without warnings.'
