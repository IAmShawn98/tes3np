[CmdletBinding()]
param(
    [switch]$Run,
    [string]$TestAccount = 'TES3NPTest',
    [string]$CandidateZip
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$utf8 = [Text.UTF8Encoding]::new($false)

function Get-VerifiedBridgeDownload([string]$Uri, [string]$Path, [string]$Sha256) {
    Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing -TimeoutSec 180
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ine $Sha256) {
        throw "Download checksum does not match: $([IO.Path]::GetFileName($Path))"
    }
}

function New-LegacyBridgeStarter([string]$Repo, [string]$Scratch, [string]$OutputZip) {
    $legacyRevision = 'a77a1fac99845be4954323220f46535079b390b1'
    $releaseBase = 'https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha'
    $archive = Join-Path $Scratch 'legacy-release.zip'
    $starter = Join-Path $Scratch 'starter'
    $releaseHash = '61fca7ba2390f5e1bd5f633ec06b43756a45a1e632a70d759ea5932c4bd9538e'
    Get-VerifiedBridgeDownload "$releaseBase/tes3np-v0.1.20-alpha-windows.zip" $archive $releaseHash
    Expand-Archive -LiteralPath $archive -DestinationPath $starter
    $shippedWorker = Join-Path $starter 'scripts\tes3np-updater.ps1'
    $base = Join-Path $starter 'runtime\AutoHotkey64.exe'
    $exe = Join-Path $starter 'tes3np.exe'
    foreach ($file in $shippedWorker, $base, $exe) {
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Incomplete legacy release: $file" }
    }

    $sourceZip = Join-Path $Scratch 'legacy-source.zip'
    $source = Join-Path $Scratch 'legacy-source'
    & git -C $Repo cat-file -e "$legacyRevision^{commit}"
    if ($LASTEXITCODE -ne 0) {
        & git -C $Repo fetch --no-tags origin $legacyRevision
        if ($LASTEXITCODE -ne 0) { throw "Could not fetch the legacy source revision $legacyRevision." }
    }
    & git -C $Repo archive --format=zip "--output=$sourceZip" $legacyRevision
    if ($LASTEXITCODE -ne 0) { throw "Could not archive v0.1.20-alpha source at $legacyRevision." }
    Expand-Archive -LiteralPath $sourceZip -DestinationPath $source
    $state = [IO.File]::ReadAllText((Join-Path $source 'src\state.ahk'))
    if ($state -notmatch 'AppConfig\s*:=\s*\{Version:\s*"0\.1\.20-alpha"') {
        throw 'The historical checkout is not v0.1.20-alpha.'
    }
    $archivedWorker = Join-Path $source 'scripts\tes3np-updater.ps1'
    $shippedWorkerText = [IO.File]::ReadAllText($shippedWorker).Replace([string][char]13, '')
    $archivedWorkerText = [IO.File]::ReadAllText($archivedWorker).Replace([string][char]13, '')
    if ($shippedWorkerText -cne $archivedWorkerText) {
        throw 'The source snapshot does not match the updater in the original release.'
    }

    # Redirect the two legacy URLs only in a throwaway build of the old launcher.
    # Keep the shipped updater file and all other release payloads untouched.
    $module = Join-Path $source 'src\app\update-check.ahk'
    $text = [IO.File]::ReadAllText($module)
    foreach ($name in 'tes3np-update.json', 'tes3np-windows.zip') {
        $old = '"' + $releaseBase + '/' + $name + '"'
        if ([regex]::Matches($text, [regex]::Escape($old)).Count -ne 1) {
            throw "Could not identify the legacy URL for $name."
        }
        $text = $text.Replace($old, ('LegacyBridgeOrigin() "/releases/download/latest-alpha/' + $name + '"'))
    }
    $origin = @'

LegacyBridgeOrigin()
{
    port := EnvGet("TES3NP_UPDATE_TEST_PORT")
    if !RegExMatch(port, "^\d{1,5}$") || Integer(port) < 1 || Integer(port) > 65535
        throw Error("Start this disposable launcher through the bridge test runner.")
    return "http://127.0.0.1:" port
}
'@
    [IO.File]::WriteAllText($module, $text + [Environment]::NewLine + $origin + [Environment]::NewLine, $utf8)

    $compilerEndpoint = 'https://api.github.com/repos/AutoHotkey/Ahk2Exe/releases/latest'
    $compilerRelease = Invoke-RestMethod -Uri $compilerEndpoint -Headers @{ 'User-Agent' = 'tes3np-legacy-bridge-test' } -TimeoutSec 60
    $compilerAsset = $compilerRelease.assets | Where-Object { $_.name -match '^Ahk2Exe[0-9A-Za-z.]+\.zip$' } | Select-Object -First 1
    if (!$compilerAsset -or $compilerAsset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$' -or
        $compilerAsset.browser_download_url -notmatch '^https://github\.com/AutoHotkey/Ahk2Exe/releases/download/') {
        throw 'Could not identify a SHA-256 verified official Ahk2Exe release.'
    }
    $compilerHash = $compilerAsset.digest.Substring(7)
    $compilerZip = Join-Path $Scratch 'compiler.zip'
    $compilerRoot = Join-Path $Scratch 'compiler'
    Get-VerifiedBridgeDownload $compilerAsset.browser_download_url $compilerZip $compilerHash
    Expand-Archive -LiteralPath $compilerZip -DestinationPath $compilerRoot
    $compiler = Get-ChildItem -LiteralPath $compilerRoot -Filter 'Ahk2Exe.exe' -File -Recurse | Select-Object -First 1
    if (!$compiler) { throw 'Ahk2Exe.exe was missing from the verified compiler archive.' }

    $entry = Join-Path $source 'tes3np.ahk'
    $icon = Join-Path $source 'assets\icons\tes3np.ico'
    $rebuilt = Join-Path $Scratch 'bridge-test.exe'
    $arguments = '/in "' + $entry + '" /out "' + $rebuilt + '" /base "' + $base +
        '" /icon "' + $icon + '" /compress 0 /silent verbose'
    $compile = Start-Process -FilePath $compiler.FullName -ArgumentList $arguments -WorkingDirectory $source -PassThru
    try {
        if (!$compile.WaitForExit(120000)) {
            $compile.Kill()
            throw 'The disposable v0.1.20-alpha launcher compile timed out.'
        }
        if ($compile.ExitCode -ne 0 -or ![IO.File]::Exists($rebuilt)) {
            throw 'The disposable v0.1.20-alpha launcher failed to compile.'
        }
    }
    finally { $compile.Dispose() }
    Copy-Item -LiteralPath $rebuilt -Destination $exe -Force
    [IO.Compression.ZipFile]::CreateFromDirectory($starter, $OutputZip)
}

function New-LegacyBridgeBundle {
    $repo = Split-Path -Parent $PSScriptRoot
    $scratch = Join-Path $env:TEMP ('tes3np-legacy-bridge-' + [guid]::NewGuid().ToString('N'))
    $bundle = Join-Path $scratch 'bundle'
    [IO.Directory]::CreateDirectory($bundle) | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $candidate = if ($CandidateZip) { $CandidateZip } else { Join-Path $repo 'dist\tes3np-windows.zip' }
        $candidate = (Resolve-Path -LiteralPath $candidate).Path
        & python (Join-Path $PSScriptRoot 'check-windows-package.py') $candidate
        if ($LASTEXITCODE -ne 0) { throw 'Build a valid alpha ZIP before preparing the bridge test.' }

        $package = Join-Path $bundle 'tes3np-windows.zip'
        Copy-Item -LiteralPath $candidate -Destination $package
        $manifest = Join-Path $bundle 'tes3np-update.json'
        Push-Location $repo
        try {
            & (Join-Path $PSScriptRoot 'generate-update-metadata.ps1') -PackagePath $package -ManifestPath $manifest
        }
        finally { Pop-Location }
        $metadata = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        if ($metadata.version -cne '0.1.21-alpha') { throw 'The bridge test expects the v0.1.21-alpha candidate.' }

        $zip = [IO.Compression.ZipFile]::OpenRead($package)
        try {
            $entry = $zip.GetEntry('tes3np.exe')
            if (!$entry) { throw 'No launcher executable at the candidate package root.' }
            $exe = Join-Path $scratch 'candidate.exe'
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $exe)
        }
        finally { $zip.Dispose() }
        $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
        [IO.File]::WriteAllText((Join-Path $bundle 'expected-launcher-sha256.txt'), $hash, $utf8)
        New-LegacyBridgeStarter $repo $scratch (Join-Path $bundle 'starter.zip')
        Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $bundle 'Run-TES3NP-Update-Test.ps1')

        $publicDocuments = [Environment]::GetFolderPath('CommonDocuments')
        $destination = Join-Path $publicDocuments ('TES3NP Update Test ' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Move-Item -LiteralPath $bundle -Destination $destination
        $runner = Join-Path $destination 'Run-TES3NP-Update-Test.ps1'
        Write-Host "Prepared the private v0.1.20-alpha to v$($metadata.version) bridge in $destination"
        Write-Host "On $TestAccount, run the following command:"
        Write-Host ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $runner + '" -Run -TestAccount "' + $TestAccount + '"')
    }
    finally {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Start-UpdateFixtureServer([string]$Bundle, [string]$PortFile) {
    Start-Job -ArgumentList $Bundle, $PortFile -ScriptBlock {
        param($Bundle, $PortFile)
        $ErrorActionPreference = 'Stop'
        $routes = @{
            '/releases/download/latest-alpha/tes3np-update.json' = 'tes3np-update.json'
            '/releases/download/latest-alpha/tes3np-windows.zip' = 'tes3np-windows.zip'
        }
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            [IO.File]::WriteAllText($PortFile + '.tmp', [string]$listener.LocalEndpoint.Port)
            [IO.File]::Move($PortFile + '.tmp', $PortFile)
            while ($true) {
                $client = $listener.AcceptTcpClient()
                try {
                    $client.ReceiveTimeout = 5000
                    $client.SendTimeout = 15000
                    $stream = $client.GetStream()
                    $reader = [IO.StreamReader]::new($stream)
                    $request = $reader.ReadLine()
                    for ($line = 0; $line -lt 64; $line++) {
                        if (!$reader.ReadLine()) { break }
                    }
                    $file = $null
                    if ($request -match '^(GET|HEAD) ([^ ]+) HTTP/1\.[01]$') {
                        $method = $Matches[1]
                        $name = $routes[$Matches[2]]
                        if ($name) { $file = Get-Item -LiteralPath (Join-Path $Bundle $name) }
                    }
                    $status = if ($file) { '200 OK' } else { '404 Not Found' }
                    $length = if ($file) { $file.Length } else { 0 }
                    $type = if ($file -and $file.Extension -eq '.zip') { 'application/zip' } else { 'application/json' }
                    $newline = [string][char]13 + [char]10
                    $header = @("HTTP/1.1 $status", "Content-Length: $length", "Content-Type: $type", 'Connection: close', '', '') -join $newline
                    $bytes = [Text.Encoding]::ASCII.GetBytes($header)
                    $stream.Write($bytes, 0, $bytes.Length)
                    if ($file -and $method -eq 'GET') {
                        $inputFile = $file.OpenRead()
                        try { $inputFile.CopyTo($stream) }
                        finally { $inputFile.Dispose() }
                    }
                }
                catch { Write-Warning $_.Exception.Message }
                finally { $client.Dispose() }
            }
        }
        finally { $listener.Stop() }
    }
}

function Invoke-InteractiveBridgeTest {
    if ([Environment]::UserName -ine $TestAccount) {
        throw "Run the bridge from the $TestAccount Windows account so it uses disposable profile data."
    }
    $sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
    if (Get-Process -Name 'tes3np' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sessionId }) {
        throw 'Close TES3NP before starting the bridge test.'
    }

    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tes3np-update.json') -Raw | ConvertFrom-Json
    $expectedHash = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'expected-launcher-sha256.txt')).Trim()
    $root = Join-Path $env:LOCALAPPDATA ('tes3np-update-test-' + [guid]::NewGuid().ToString('N'))
    $install = Join-Path $root 'install'
    $updateTemp = Join-Path $root 'temp'
    [IO.Directory]::CreateDirectory($updateTemp) | Out-Null
    Expand-Archive -LiteralPath (Join-Path $PSScriptRoot 'starter.zip') -DestinationPath $install
    $launcher = Join-Path $install 'tes3np.exe'
    $portFile = Join-Path $root 'feed-port.txt'
    $server = Start-UpdateFixtureServer $PSScriptRoot $portFile
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        $port = ''
        while ($server.State -in @('NotStarted', 'Running') -and [DateTime]::UtcNow -lt $deadline) {
            if ([IO.File]::Exists($portFile)) {
                $port = ([IO.File]::ReadAllText($portFile)).Trim()
                if ($port -match '^\d{1,5}$') { break }
            }
            Start-Sleep -Milliseconds 100
        }
        if ($port -notmatch '^\d{1,5}$') {
            Receive-Job -Job $server
            throw 'The local legacy feed did not start.'
        }

        $launch = [Diagnostics.ProcessStartInfo]::new()
        $launch.FileName = $launcher
        $launch.WorkingDirectory = $install
        $launch.UseShellExecute = $false
        # The legacy updater uses a shared directory under TEMP. Isolate it
        # only for the launched test process and its descendants.
        $launch.EnvironmentVariables['TEMP'] = $updateTemp
        $launch.EnvironmentVariables['TMP'] = $updateTemp
        $launch.EnvironmentVariables['TES3NP_UPDATE_TEST_PORT'] = $port
        $starter = [Diagnostics.Process]::Start($launch)
        Write-Host "Running the v0.1.20-alpha bridge test from $install"
        Write-Host 'Use the normal update button and accept its download and install prompts. Keep this window open.'

        $stateFile = Join-Path $updateTemp 'tes3np-update\update-state.ini'
        $deadline = [DateTime]::UtcNow.AddMinutes(10)
        while ([DateTime]::UtcNow -lt $deadline) {
            if ([IO.File]::Exists($stateFile)) {
                $state = @(Get-Content -LiteralPath $stateFile -ErrorAction SilentlyContinue)
                if ($state -match '^State=(?:ROLLED_BACK|ROLLBACK_FAILED|FAILED)$') {
                    throw "The legacy updater reported $($state -match '^State='). See $stateFile."
                }
                if ($starter.HasExited -and ($state -contains 'State=SUCCESS') -and ($state -contains "Version=$($manifest.version)")) {
                    if ((Get-FileHash -LiteralPath $launcher -Algorithm SHA256).Hash -ine $expectedHash) {
                        throw 'Startup was confirmed, but the installed launcher hash differs from the candidate.'
                    }
                    Write-Host "PASS: v0.1.20-alpha discovered and installed v$($manifest.version). The candidate restarted, confirmed startup, and matched its expected executable hash." -ForegroundColor Green
                    return
                }
            }
            Start-Sleep -Seconds 1
        }
        throw "Update confirmation was not recorded within 10 minutes. The test installation is at $install."
    }
    finally {
        Stop-Job -Job $server -ErrorAction SilentlyContinue
        Remove-Job -Job $server -Force -ErrorAction SilentlyContinue
    }
}

if ($Run) { Invoke-InteractiveBridgeTest }
else { New-LegacyBridgeBundle }
