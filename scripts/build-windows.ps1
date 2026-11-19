$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Step([string]$Message) { Write-Host "BUILD CHECKPOINT | $Message" }

# Use .NET hashing so archive verification works even when Get-FileHash is unavailable.
function GetTes3npSha256([string]$FilePath) {
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            return [System.BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $algorithm.Dispose()
    }
}

function Invoke-BuildProcess(
    [string]$Executable, [string]$Arguments, [string]$Label, [int]$TimeoutMs,
    [string]$WorkingDirectory = $projectRoot, [switch]$ShowOutput
) {
    Step "Starting $Label"
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = $Arguments
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    try {
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit($TimeoutMs)) {
            try { $process.Kill() } catch {}
            throw "$Label timed out after $TimeoutMs ms."
        }
        if (!$output.Wait(2000) -or !$errors.Wait(2000)) {
            throw "$Label closed without completing its output."
        }
        $exitCode = $process.ExitCode
        if ($ShowOutput -or $exitCode -ne 0) {
            if ($output.Result) { Write-Host $output.Result }
            if ($errors.Result) { Write-Host $errors.Result }
        }
        Step "$Label exited with code $exitCode"
        return $exitCode
    } finally {
        $process.Dispose()
    }
}

# Public GitHub downloads occasionally return 502/503/504 during an otherwise
# healthy Windows build. Retry with bounded delays, rejecting partial files.
# The whole build continues to fail closed after three attempts.
function GetOfficialRelease([string]$Uri, [hashtable]$Headers, [string]$Label) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            return (Invoke-RestMethod -Uri $Uri -Headers $Headers -TimeoutSec 90 -ErrorAction Stop)
        }
        catch {
            if ($attempt -ge 3) {
                throw "Could not retrieve $Label release metadata after 3 attempts: $($_.Exception.Message)"
            }
            Step "$Label metadata request failed; retrying ($attempt/3)"
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}
function SaveOfficialDownload(
    [string]$Uri, [string]$Destination, [hashtable]$Headers, [string]$Label,
    [string]$MirrorUri = '', [string]$ExpectedSha256 = '',
    [hashtable]$MirrorHeaders = $null
) {
    # A release mirrored on another official host must match the SHA-256 from
    # GitHub's release metadata. No hash, no mirror and no unverified bypass.
    if ($MirrorUri -and $ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "$Label mirror requires an official release SHA-256 digest."
    }
    $endpoints = @($Uri)
    if ($MirrorUri) { $endpoints += $MirrorUri }
    $lastError = 'no response'
    foreach ($endpoint in $endpoints) {
        if (!$endpoint.StartsWith('https://', [StringComparison]::OrdinalIgnoreCase)) {
            throw "$Label download was not HTTPS."
        }
        # Move to the independently hosted archive promptly after persistent
        # GitHub release-asset 504s, but still retry temporary mirror outages.
        $maxAttempts = if ($MirrorUri -and $endpoint -eq $Uri) { 2 } else { 3 }
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                if ([IO.File]::Exists($Destination)) { [IO.File]::Delete($Destination) }
                $requestHeaders = if ($endpoint -eq $MirrorUri -and $null -ne $MirrorHeaders) { $MirrorHeaders } else { $Headers }
                Invoke-WebRequest -Uri $endpoint -OutFile $Destination -Headers $requestHeaders -TimeoutSec 120 -UseBasicParsing -ErrorAction Stop
                if (![IO.File]::Exists($Destination) -or (Get-Item -LiteralPath $Destination).Length -le 0) {
                    throw "The $Label download was empty."
                }
                if ($ExpectedSha256 -and (GetTes3npSha256 $Destination) -ine $ExpectedSha256) {
                    throw "$Label SHA-256 did not match GitHub release metadata."
                }
                return
            }
            catch {
                $lastError = $_.Exception.Message
                if ([IO.File]::Exists($Destination)) {
                    try { [IO.File]::Delete($Destination) } catch {}
                }
                if ($attempt -lt $maxAttempts) {
                    Step "$Label download unavailable; retrying ($attempt/$maxAttempts)"
                    Start-Sleep -Seconds (2 * $attempt)
                }
            }
        }
        if ($endpoint -eq $Uri -and $MirrorUri) {
            Step "GitHub download unavailable; trying verified official $Label mirror"
        }
    }
    throw "Could not download $Label from official sources: $lastError"
}
function CheckOfficialZip([string]$Path, [string]$Label) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        if ($archive.Entries.Count -lt 1) { throw "$Label release ZIP contains no files." }
    }
    finally { $archive.Dispose() }
}

$projectRoot = Split-Path $PSScriptRoot -Parent
# Every build gets a separate scratch tree. A stale Windows file lock from a
# previous run must never block a new build or collide with active tools.
$buildRoot = Join-Path $env:TEMP ('tes3np-build-' + [guid]::NewGuid().ToString('N'))
$tools = Join-Path $buildRoot 'tools'
$dist = Join-Path $projectRoot 'dist'
$package = Join-Path $buildRoot 'tes3np-windows'
$zip = Join-Path $buildRoot 'tes3np-windows.zip'
try {
    # Validate before removing dist or downloading build tools. A broken
    # PowerShell helper must never replace the last good local build.
    Step 'Validating PowerShell helper syntax before packaging'
    & (Join-Path $PSScriptRoot 'check-powershell.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'PowerShell syntax validation failed. Previous build artifacts were not removed.' }
    Step 'Validating source tree and patch manifest before packaging'
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (!$python) { throw 'Python is required to generate embedded resources and validate the source tree.' }
    & python (Join-Path $PSScriptRoot 'project.py') check
    if ($LASTEXITCODE -ne 0) { throw 'Source validation failed. Previous build artifacts were not removed.' }
    Step 'Checking embedded Chat Host architecture before packaging'
    & python (Join-Path $PSScriptRoot 'check-chat-architecture.py')
    if ($LASTEXITCODE -ne 0) { throw 'Chat Host architecture validation failed. Previous build artifacts were not removed.' }
    Step 'Checking privacy of diagnostic output and log-copy paths'
    & python (Join-Path $PSScriptRoot 'check-diagnostic-privacy.py')
    if ($LASTEXITCODE -ne 0) { throw 'Diagnostic privacy validation failed. Previous build artifacts were not removed.' }
    Step 'Testing ZIP and extracted-folder Expansion Pack imports using disposable fixture files'
    & (Join-Path $PSScriptRoot 'test-import-expansion-folder.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Expansion Pack folder/ZIP importer fixture failed. Previous build artifacts were not removed.' }
    Step 'Testing installed-only Expansion Pack toggle in a disposable game directory'
    & (Join-Path $PSScriptRoot 'test-expansion-toggle.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Installed Expansion Pack toggle fixture failed. Previous build artifacts were not removed.' }
    Step 'Checking native Windows Expansion Pack picker COM interfaces (no dialog shown)'
    $powershell51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell51 -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'select-expansion-package.ps1') -SmokeTest
    if ($LASTEXITCODE -ne 0) { throw 'Native Expansion Pack picker COM smoke test failed. Previous build artifacts were not removed.' }
    Step 'Preflight compiling Chat Host before downloading tools'
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (!$dotnet) { throw 'Building embedded chat requires .NET 8 SDK. Install the .NET 8 SDK and rerun the build.' }
    $hostProject = Join-Path $projectRoot 'game-chat\tes3np.GameChat.csproj'
    & dotnet build $hostProject -c Release -r win-x64 --no-self-contained
    if ($LASTEXITCODE -ne 0) { throw 'Chat Host preflight compilation failed. Previous build artifacts were not removed.' }
    Step 'Starting Windows launcher build'
    if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force }
    $null = New-Item $tools -ItemType Directory

    $consoleExe = $env:TES3NP_MARKERLESS_CONSOLE_EXE
    $consoleDlls = $env:TES3NP_MARKERLESS_CONSOLE_DLLS
    $consolePayload = $null
    if ($consoleExe -or $consoleDlls) {
        if (!$consoleExe -or !$consoleDlls) {
            throw 'Set both TES3NP_MARKERLESS_CONSOLE_EXE and TES3NP_MARKERLESS_CONSOLE_DLLS to build the source-built candidate.'
        }
        $markerlessResearch = Join-Path $projectRoot 'research\markerless'
        $consoleCandidate = Get-Content -LiteralPath (Join-Path $markerlessResearch 'console-candidate.json') -Raw | ConvertFrom-Json
        . (Join-Path $PSScriptRoot 'stage-markerless-console.ps1')
        $consoleStage = Join-Path $tools 'markerless-console'
        $consolePayload = Stage-MarkerlessConsole $consoleExe $consoleDlls $consoleStage $consoleCandidate
        Step 'Verified the tested console EXE and staged its 45 matching DLLs'
    }

    $headers = @{ 'User-Agent' = 'tes3np-build'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) {
        $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)"
        $headers['X-GitHub-Api-Version'] = '2022-11-28'
    }
    # Fetch and inspect all upstream artifacts BEFORE clearing the last good
    # dist build. An intermittent GitHub gateway timeout must not destroy it.
    Step 'Querying AutoHotkey/AutoHotkey release metadata'
    $ahkRelease = GetOfficialRelease 'https://api.github.com/repos/AutoHotkey/AutoHotkey/releases/latest' $headers 'AutoHotkey'
    $ahkAsset = $ahkRelease.assets | Where-Object name -match '^AutoHotkey_2\.0\.\d+\.zip$' | Select-Object -First 1
    if (!$ahkAsset) { throw 'Could not find an official AutoHotkey v2.0 release ZIP.' }
    if ($ahkAsset.browser_download_url -notmatch '^https://github\.com/AutoHotkey/AutoHotkey/releases/download/') {
        throw 'Unexpected AutoHotkey release download source.'
    }
    if ($ahkAsset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw 'Official AutoHotkey release SHA-256 digest is unavailable; refusing unverified archive.'
    }
    $expectedAhkHash = $Matches[1]
    $ahkMirror = 'https://docs.autohotkey.com/download/2.0/' + $ahkAsset.name
    Step "Downloading AutoHotkey/AutoHotkey $($ahkRelease.tag_name): $($ahkAsset.name)"
    $ahkZip = Join-Path $tools 'autohotkey.zip'
    # GitHub and AutoHotkey's own download directory publish the same version.
    # Verify every source against the release metadata, including local cache.
    $ahkCacheDir = Join-Path $env:LOCALAPPDATA 'tes3np\build-download-cache'
    $cachedAhkZip = Join-Path $ahkCacheDir $ahkAsset.name
    $cachedAhkValid = $false
    if ([IO.File]::Exists($cachedAhkZip)) {
        try { $cachedAhkValid = (GetTes3npSha256 $cachedAhkZip) -ieq $expectedAhkHash }
        catch { $cachedAhkValid = $false }
    }
    if ($cachedAhkValid) {
        Step 'Using cached official AutoHotkey ZIP (SHA-256 verified)'
        Copy-Item -LiteralPath $cachedAhkZip -Destination $ahkZip -Force
    }
    else {
        SaveOfficialDownload $ahkAsset.browser_download_url $ahkZip $headers 'AutoHotkey' $ahkMirror $expectedAhkHash
    }
    CheckOfficialZip $ahkZip 'AutoHotkey'
    if ((GetTes3npSha256 $ahkZip) -ine $expectedAhkHash) {
        throw 'AutoHotkey ZIP SHA-256 does not match GitHub release metadata.'
    }
    if (!$cachedAhkValid) {
        # A failed cache write must not invalidate a verified downloaded ZIP.
        try {
            [IO.Directory]::CreateDirectory($ahkCacheDir) | Out-Null
            Copy-Item -LiteralPath $ahkZip -Destination $cachedAhkZip -Force
        }
        catch {
            Step 'AutoHotkey cache write unavailable; build can still continue.'
        }
    }
    Step 'Downloaded and checked AutoHotkey release ZIP'

    Step 'Querying AutoHotkey/Ahk2Exe release metadata'
    $compilerRelease = GetOfficialRelease 'https://api.github.com/repos/AutoHotkey/Ahk2Exe/releases/latest' $headers 'Ahk2Exe'
    $compilerAsset = $compilerRelease.assets | Where-Object name -match '^Ahk2Exe[0-9A-Za-z.]+\.zip$' | Select-Object -First 1
    if (!$compilerAsset) { throw 'Could not find the official Ahk2Exe release ZIP.' }
    if ($compilerAsset.browser_download_url -notmatch '^https://github\.com/AutoHotkey/Ahk2Exe/releases/download/') {
        throw 'Unexpected Ahk2Exe release download source.'
    }
    if ($compilerAsset.url -notmatch '^https://api\.github\.com/repos/AutoHotkey/Ahk2Exe/releases/assets/[0-9]+$') {
        throw 'Unexpected Ahk2Exe GitHub API asset URL.'
    }
    if ($compilerAsset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw 'Official Ahk2Exe release SHA-256 digest is unavailable; refusing unverified archive.'
    }
    $expectedCompilerHash = $Matches[1]
    Step "Obtaining verified AutoHotkey/Ahk2Exe $($compilerRelease.tag_name): $($compilerAsset.name)"
    $compilerZip = Join-Path $tools 'compiler.zip'
    $compilerCacheDir = Join-Path $env:LOCALAPPDATA 'tes3np\build-download-cache'
    $cachedCompilerZip = Join-Path $compilerCacheDir $compilerAsset.name
    # A manually downloaded official ZIP is also accepted, but only when its
    # complete SHA-256 matches the actual latest GitHub release metadata.
    $downloadsCompilerZip = Join-Path (Join-Path $env:USERPROFILE 'Downloads') $compilerAsset.name
    $verifiedLocalCompiler = ''
    foreach ($candidate in @($cachedCompilerZip, $downloadsCompilerZip)) {
        if (![IO.File]::Exists($candidate)) { continue }
        try {
            if ((GetTes3npSha256 $candidate) -ieq $expectedCompilerHash) {
                $verifiedLocalCompiler = $candidate
                break
            }
        }
        catch {
            # An unreadable candidate cannot satisfy the verified-file rule.
        }
    }
    if ($verifiedLocalCompiler) {
        Step 'Using verified local official Ahk2Exe ZIP'
        Copy-Item -LiteralPath $verifiedLocalCompiler -Destination $compilerZip -Force
    }
    else {
        # API asset endpoint may bypass transient failures at the browser
        # release URL; GitHub's official metadata binds both to one asset.
        $apiHeaders = @{}
        foreach ($key in $headers.Keys) { $apiHeaders[$key] = $headers[$key] }
        $apiHeaders['Accept'] = 'application/octet-stream'
        SaveOfficialDownload $compilerAsset.browser_download_url $compilerZip $headers 'Ahk2Exe' $compilerAsset.url $expectedCompilerHash $apiHeaders
    }
    CheckOfficialZip $compilerZip 'Ahk2Exe'
    if ((GetTes3npSha256 $compilerZip) -ine $expectedCompilerHash) {
        throw 'Ahk2Exe ZIP SHA-256 does not match GitHub release metadata.'
    }
    if ($verifiedLocalCompiler -ne $cachedCompilerZip) {
        try {
            [IO.Directory]::CreateDirectory($compilerCacheDir) | Out-Null
            Copy-Item -LiteralPath $compilerZip -Destination $cachedCompilerZip -Force
        }
        catch {
            Step 'Ahk2Exe cache write unavailable; build can still continue.'
        }
    }
    Step 'Downloaded or found and checked Ahk2Exe release ZIP'
    try {
        $cacheFolder = Get-Item -LiteralPath $ahkCacheDir -ErrorAction Stop
        if (!($cacheFolder.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $staleBefore = [DateTime]::UtcNow.AddDays(-30)
            Get-ChildItem -LiteralPath $ahkCacheDir -File | Where-Object {
                $_.Name -match '^(AutoHotkey_2\.0\.\d+|Ahk2Exe[0-9A-Za-z.]+)\.zip$' -and
                $_.Name -notin @($ahkAsset.name, $compilerAsset.name) -and
                $_.LastWriteTimeUtc -lt $staleBefore -and
                !($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
            } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        # Cache maintenance must not prevent a build.
    }

    $tes3mpArchive = Join-Path $tools 'tes3mp-0.8.1.zip'
    $officialTES3MP = 'https://github.com/TES3MP/TES3MP/releases/download/tes3mp-0.8.1/tes3mp.Win64.release.0.8.1.zip'
    $officialTes3mpHash = '72d35d574689e698196855c80e27bf79a86a591c2a7d42dddd03de0c597e2bad'
    $reuseTes3mp = $false
    $archiveHash = ''
    Step 'Downloading official TES3MP 0.8.1 Win64 runtime for distribution'
    try {
        SaveOfficialDownload $officialTES3MP $tes3mpArchive $headers 'TES3MP 0.8.1' -ExpectedSha256 $officialTes3mpHash
        CheckOfficialZip $tes3mpArchive 'TES3MP 0.8.1'
    }
    catch {
        if ($consoleExe -or $consoleDlls) { throw }
        # Use an older TES3NP distribution only when the exact markerless
        # executable and original official release provenance are verified.
        # Snapshot before dist is replaced; never alter the candidate.
        $manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'patches\manifest.json') -Raw | ConvertFrom-Json
        $expectedOld = ($manifest.Files | Where-Object Path -eq 'markerless/tes3mp.exe' | Select-Object -First 1).SHA256
        $candidates = @(
            (Join-Path $projectRoot 'dist\tes3np-windows'),
            (Join-Path $env:USERPROFILE 'Documents\tes3np\dist\tes3np-windows'),
            (Join-Path $env:USERPROFILE 'Documents\tes3np\dist\local-build')
        )
        $requiredClient = @('tes3mp.exe', 'tes3mp-client-default.cfg', 'defaults.bin', 'openmw.cfg')
        $requiredLicenses = @('LICENSE', 'DejaVuFontLicense.txt', 'REDISTRIBUTION-NOTICE.txt')
        $verifiedCandidate = $null
        foreach ($candidate in $candidates) {
            $candidateClient = Join-Path $candidate 'client'
            $candidateLicenses = Join-Path $candidate 'licenses\TES3MP'
            $valid = ($expectedOld -match '^[a-fA-F0-9]{64}$')
            foreach ($name in $requiredClient) {
                if (!(Test-Path -LiteralPath (Join-Path $candidateClient $name) -PathType Leaf)) { $valid = $false }
            }
            foreach ($name in $requiredLicenses) {
                if (!(Test-Path -LiteralPath (Join-Path $candidateLicenses $name) -PathType Leaf)) { $valid = $false }
            }
            if (!$valid) { continue }
            if ((GetTes3npSha256 (Join-Path $candidateClient 'tes3mp.exe')) -ine $expectedOld) { continue }
            $notice = Get-Content -LiteralPath (Join-Path $candidateLicenses 'REDISTRIBUTION-NOTICE.txt') -Raw
            if ($notice -notmatch 'TES3MP runtime 0\.8\.1' -or
                $notice -notmatch [regex]::Escape($officialTES3MP) -or
                $notice -notmatch 'Original release archive SHA256: ([a-fA-F0-9]{64})' -or
                $notice -notmatch ('Markerless executable SHA256: ' + [regex]::Escape($expectedOld))) { continue }
            $archiveHash = [regex]::Match($notice, 'Original release archive SHA256: ([a-fA-F0-9]{64})').Groups[1].Value
            if ($archiveHash -ine $officialTes3mpHash) { continue }
            $verifiedCandidate = $candidate
            break
        }
        if (!$verifiedCandidate) {
            throw 'Official TES3MP download failed and no verified prior TES3NP distribution was found. Existing dist was preserved.'
        }
        $oldClientSnapshot = Join-Path $tools 'previous-verified-client'
        $oldLicenseSnapshot = Join-Path $tools 'previous-verified-licenses'
        Copy-Item -LiteralPath (Join-Path $verifiedCandidate 'client') -Destination $oldClientSnapshot -Recurse -Force
        Copy-Item -LiteralPath (Join-Path $verifiedCandidate 'licenses\TES3MP') -Destination $oldLicenseSnapshot -Recurse -Force
        if ((GetTes3npSha256 (Join-Path $oldClientSnapshot 'tes3mp.exe')) -ine $expectedOld) {
            throw 'Verified TES3MP snapshot changed during copy.'
        }
        $reuseTes3mp = $true
        Step "Official download unavailable; using verified TES3MP runtime from $verifiedCandidate"
    }

    $upstreamLicense = 'https://raw.githubusercontent.com/TES3MP/TES3MP/tes3mp-0.8.1/LICENSE'
    $upstreamFontLicense = 'https://raw.githubusercontent.com/TES3MP/TES3MP/tes3mp-0.8.1/files/mygui/DejaVuFontLicense.txt'
    if (!$reuseTes3mp) {
        SaveOfficialDownload $upstreamLicense (Join-Path $tools 'tes3mp-license.txt') $headers 'TES3MP license'
        SaveOfficialDownload $upstreamFontLicense (Join-Path $tools 'tes3mp-font-license.txt') $headers 'TES3MP font license'
    }

    Step 'Official downloads verified; preparing new distribution'
    $null = New-Item $package -ItemType Directory

    Step 'Extracting AutoHotkey runtime'
    # The Windows PowerShell archive module can bind to an unavailable
    # overwrite overload. All build extraction targets are fresh directories.
    [IO.Compression.ZipFile]::ExtractToDirectory($ahkZip, (Join-Path $tools 'autohotkey'))
    Step 'Extracting Ahk2Exe compiler'
    [IO.Compression.ZipFile]::ExtractToDirectory($compilerZip, (Join-Path $tools 'compiler'))
    $base = Get-ChildItem (Join-Path $tools 'autohotkey') -Filter 'AutoHotkey64.exe' -Recurse | Select-Object -First 1 -ExpandProperty FullName
    $compiler = Get-ChildItem (Join-Path $tools 'compiler') -Filter 'Ahk2Exe.exe' -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if (!$base -or !$compiler) { throw 'Required AutoHotkey build tools were not found.' }

    # Execute the same parser and report code as the launcher, with synthetic
    # inputs and NO game files, personal settings, network or clipboard.
    Step 'Testing plugin-mismatch diagnostics with isolated AutoHotkey fixtures'
    $mismatchFixture = Join-Path $projectRoot 'scripts\test-expansion-diagnostics.ahk'
    # AHK can emit #Warn diagnostics while exiting successfully. Keep their
    # output visible and fail the package rather than shipping a truncated
    # diagnostic report or an unresolved fixture-only dependency.
    $fixtureOutput = @(& $base /ErrorStdOut $mismatchFixture 2>&1)
    $fixtureExit = $LASTEXITCODE
    $fixtureOutput | ForEach-Object { Write-Host $_ }
    if ($null -eq $fixtureExit -or $fixtureExit -ne 0) {
        throw 'Plugin-mismatch diagnostic fixture tests failed; packaging stopped.'
    }
    if ($fixtureOutput -match '(?i)Warning:|This line will never execute|appears to never be assigned') {
        throw 'AutoHotkey fixture warnings detected; packaging stopped.'
    }
    Step 'Testing diagnostic privacy with disposable AutoHotkey fixtures'
    $privacyFixture = Join-Path $projectRoot 'scripts\test-diagnostic-privacy.ahk'
    $privacyOutput = @(& $base /ErrorStdOut $privacyFixture 2>&1)
    $privacyExit = $LASTEXITCODE
    $privacyOutput | ForEach-Object { Write-Host $_ }
    if ($null -eq $privacyExit -or $privacyExit -ne 0 -or
        $privacyOutput -match '(?i)Warning:|This line will never execute|appears to never be assigned') {
        throw 'Diagnostic privacy runtime fixture failed; packaging stopped.'
    }


    # Check the COMPLETE launcher source before staging/embed compilation.
    # #Warn issues such as an undeclared AHK built-in can fail Ahk2Exe
    # without a useful error line in its compiler transcript.
    Step 'Preflighting full AutoHotkey launcher source and warning diagnostics'
    $launcherSource = Join-Path $projectRoot 'tes3np.ahk'
    $launcherOutput = @(& $base /ErrorStdOut $launcherSource '--check' 2>&1)
    $launcherExit = $LASTEXITCODE
    $launcherOutput | ForEach-Object { Write-Host $_ }
    if ($null -eq $launcherExit -or $launcherExit -ne 0) {
        throw 'AutoHotkey launcher source preflight failed before packaging.'
    }
    if ($launcherOutput -match '(?i)Warning:|This line will never execute|appears to never be assigned') {
        throw 'AutoHotkey launcher source warnings detected before packaging.'
    }

    $smokeSource = Join-Path $buildRoot 'compiler-smoke.ahk'; $smokeExe = Join-Path $buildRoot 'compiler-smoke.exe'
    Set-Content $smokeSource "#Requires AutoHotkey v2.0`nExitApp(0)`n" -Encoding UTF8
    $smokeArgs = '/in "' + $smokeSource + '" /out "' + $smokeExe + '" /base "' + $base + '" /compress 0 /silent verbose'
    $smokeCode = Invoke-BuildProcess $compiler $smokeArgs 'Ahk2Exe smoke compilation' 45000
    if ($smokeCode -ne 0 -or !(Test-Path $smokeExe)) { throw 'Ahk2Exe smoke compilation failed.' }

    # The compiled launcher cannot run user .ahk files by itself. Package the
    # same official v2 interpreter used to compile it, so Run Macro never
    # depends on a separate system installation or a manual EXE picker.
    Step 'Packaging official AutoHotkey v2 runtime for installed macros'
    $macroRuntimeFolder = Join-Path $package 'runtime'
    $null = New-Item -ItemType Directory -Path $macroRuntimeFolder -Force
    $macroRuntime = Join-Path $macroRuntimeFolder 'AutoHotkey64.exe'
    Copy-Item -LiteralPath $base -Destination $macroRuntime -Force
    if (!(Test-Path -LiteralPath $macroRuntime -PathType Leaf) -or
        (GetTes3npSha256 $macroRuntime) -ine (GetTes3npSha256 $base)) {
        throw 'Packaged AutoHotkey macro runtime does not match the verified build interpreter.'
    }
    # Execute a disposable no-op script through the actual packaged runtime,
    # not merely Ahk2Exe, before accepting the Windows package.
    $runtimeSmoke = Start-Process -FilePath $macroRuntime -ArgumentList ('"' + $smokeSource + '"') -PassThru
    if (!$runtimeSmoke.WaitForExit(15000)) {
        try { $runtimeSmoke.Kill() } catch {}
        throw 'Packaged AutoHotkey macro interpreter smoke test timed out.'
    }
    if ($runtimeSmoke.ExitCode -ne 0) {
        throw "Packaged AutoHotkey macro interpreter smoke test failed: $($runtimeSmoke.ExitCode)"
    }
    $ahkLicenseFolder = Join-Path $package 'licenses\AutoHotkey'
    $null = New-Item -ItemType Directory -Path $ahkLicenseFolder -Force
    $ahkLicense = Get-ChildItem -LiteralPath (Join-Path $tools 'autohotkey') -Recurse -File -Filter 'license.txt' |
        Select-Object -First 1
    if ($ahkLicense) {
        Copy-Item -LiteralPath $ahkLicense.FullName -Destination (Join-Path $ahkLicenseFolder 'license.txt') -Force
    }
    @"
AutoHotkey v2 runtime included for launching user-provided AHK scripts.
Official upstream: https://github.com/AutoHotkey/AutoHotkey
Release: $($ahkRelease.tag_name)
Original archive: $($ahkAsset.name)
Original archive URL: $($ahkAsset.browser_download_url)
The official AutoHotkey repository publishes its license and corresponding source.
Public redistribution/licensing review remains a separate release gate.
"@ | Set-Content -LiteralPath (Join-Path $ahkLicenseFolder 'REDISTRIBUTION-NOTICE.txt') -Encoding UTF8
    Step 'Verified packaged AutoHotkey64.exe hash and script execution'

    # Build an isolated standalone source tree; leave developer source paths untouched.
    $stageRoot = Join-Path $buildRoot 'standalone-source'
    $null = New-Item $stageRoot -ItemType Directory
    foreach ($item in @('tes3np.ahk','src','assets','scripts')) {
        Copy-Item (Join-Path $projectRoot $item) $stageRoot -Recurse
    }
    & python (Join-Path $projectRoot 'scripts/generate-bundled-resources.py') $stageRoot
    if ($LASTEXITCODE -ne 0) { throw 'Resource embedding generation failed.' }
    $resourceIdentityPath = Join-Path $stageRoot 'bundled-resource-id.txt'
    if (!(Test-Path -LiteralPath $resourceIdentityPath -PathType Leaf)) { throw 'Missing bundled resource identity.' }
    $resourceIdentity = (Get-Content -LiteralPath $resourceIdentityPath -Raw -Encoding ASCII).Trim()
    if ($resourceIdentity -notmatch '^v-[a-f0-9]{20}$') { throw 'Invalid bundled resource identity.' }
    $stageEntry = Join-Path $stageRoot 'tes3np.ahk'
    $entryText = [IO.File]::ReadAllText($stageEntry)
    $resourceSetupMarker = '; @bundled-resource-setup@'
    $markerLine = '(?m)^' + [regex]::Escape($resourceSetupMarker) + '(?=\r?$)'
    if ([regex]::Matches($entryText, $markerLine).Count -ne 1) {
        throw "Expected exactly one bundled resource setup marker in tes3np.ahk: $resourceSetupMarker"
    }
    $resourceSetup = @'
#Include src\app\bundled-resources.generated.ahk
PrepareBundledResources()
if A_Args.Length && A_Args[1] = "--check-resources"
    ExitApp(0)
'@
    $entryText = [regex]::Replace($entryText, $markerLine, $resourceSetup)
    # The compiled UI probes use the painter before normal launcher startup.
    $launcherChecksLine = '(?m)^RunLauncherChecks\(A_Args\)(?=\r?$)'
    if ([regex]::Matches($entryText, $launcherChecksLine).Count -ne 1) {
        throw 'Expected exactly one launcher check dispatch in tes3np.ahk.'
    }
    $resourceProbeSetup = @'
if A_Args.Length && (A_Args[1] = "--check-owned-menu-scaling" || A_Args[1] = "--check-expansion-window")
    PrepareBundledResources()
RunLauncherChecks(A_Args)
'@
    $entryText = [regex]::Replace($entryText, $launcherChecksLine, $resourceProbeSetup)
    [IO.File]::WriteAllText($stageEntry, $entryText)
    Get-ChildItem (Join-Path $stageRoot 'src') -Filter '*.ahk' -Recurse | Where-Object { $_.Name -ne 'bundled-resources.generated.ahk' } | ForEach-Object {
        $text = [IO.File]::ReadAllText($_.FullName)
        foreach ($folder in @('assets','patches','scripts')) {
            $text = $text.Replace(('A_ScriptDir "\' + $folder + '\'), ('BundledResourceRoot "\' + $folder + '\'))
            $text = $text.Replace(('A_ScriptDir "\' + $folder + '"'), ('BundledResourceRoot "\' + $folder + '"'))
            # Some AHK sources use doubled backslashes inside quoted paths.
            # Rewrite those too: otherwise the compiled EXE looks for assets beside itself.
            $text = $text.Replace(('A_ScriptDir "\\' + $folder + '\\'), ('BundledResourceRoot "\\' + $folder + '\\'))
            $text = $text.Replace(('A_ScriptDir "\\' + $folder + '"'), ('BundledResourceRoot "\\' + $folder + '"'))
        }
        [IO.File]::WriteAllText($_.FullName, $text)
    }
    # Verify all staged references after conversion, not before it.
    $stagedSources = Get-ChildItem (Join-Path $stageRoot 'src') -Filter '*.ahk' -Recurse | Where-Object { $_.Name -ne 'bundled-resources.generated.ahk' }
    foreach ($stagedFile in $stagedSources) {
        if ([IO.File]::ReadAllText($stagedFile.FullName) -match 'A_ScriptDir\s+"\\+(assets|patches|scripts)(\\|")') { throw "Unconverted resource path in $($stagedFile.FullName)" }
    }
    # Check the exact rewritten entry and includes which Ahk2Exe is about to
    # compile, not only the original source. A warning from an otherwise valid
    # compiled startup must fail preflight instead of surprising the user.
    Step 'Preflighting generated standalone AutoHotkey source and warning diagnostics'
    $stageOutput = @(& $base /ErrorStdOut $stageEntry '--check' 2>&1)
    $stageExit = $LASTEXITCODE
    $stageOutput | ForEach-Object { Write-Host $_ }
    if ($null -eq $stageExit -or $stageExit -ne 0) {
        throw 'Staged AutoHotkey launcher source preflight failed before compilation.'
    }
    if ($stageOutput -match '(?i)Warning:|This line will never execute|appears to never be assigned') {
        throw 'Staged AutoHotkey launcher warnings detected before compilation.'
    }
    $source = $stageEntry; $executable = Join-Path $package 'tes3np.exe'
    $arguments = '/in "' + $source + '" /out "' + $executable + '" /icon "' + (Join-Path $projectRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    $compileCode = Invoke-BuildProcess $compiler $arguments 'Current branch tes3np compilation' 120000
    if ($compileCode -ne 0 -or !(Test-Path $executable)) { throw 'Launcher compilation failed.' }
    Step 'Starting compiled launcher --check (30 second timeout)'
    $check = Start-Process $executable -ArgumentList '--check' -PassThru
    if (!$check.WaitForExit(30000)) { try { $check.Kill() } catch {}; throw 'Compiled launcher validation timed out after 30 seconds.' }
    Step "Compiled launcher --check exited with code $($check.ExitCode)"
    if ($check.ExitCode -ne 0) { throw 'Compiled launcher validation failed.' }
    # The --check smoke test exits before FileInstall runs. Exercise extraction
    # separately to ensure runtime workers/artwork exist and no patch payload is embedded.
    Step 'Validating standalone runtime resource extraction'
    $extract = Start-Process $executable -ArgumentList '--check-resources' -PassThru
    try {
        if (!$extract.WaitForExit(30000)) {
            try { $extract.Kill() } catch {}
            throw 'Embedded resource extraction timed out after 30 seconds.'
        }
        if ($extract.ExitCode -ne 0) { throw "Embedded resource extraction failed with code $($extract.ExitCode)." }
    } finally {
        $extract.Dispose()
    }
    # Verify this executable's unique version; do not overwrite/delete the
    # resource folder that an older, still-running launcher may be using.
    $resourceRoot = Join-Path (Join-Path $env:APPDATA 'tes3np\resources') $resourceIdentity
    $marker = Join-Path $resourceRoot 'resource-version.txt'
    if (!(Test-Path -LiteralPath $marker -PathType Leaf)) { throw "Compiled launcher did not complete resource extraction." }
    $markerText = (Get-Content -LiteralPath $marker -Raw -Encoding UTF8).Trim()
    if (!$markerText.StartsWith($resourceIdentity.Substring(2), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Compiled resource version marker mismatch.'
    }
    foreach ($asset in @('assets\backgrounds\character-book.png', 'assets\icons\tes3np.ico')) {
        if (!(Test-Path -LiteralPath (Join-Path $resourceRoot $asset) -PathType Leaf)) {
            throw "Missing extracted UI asset: $asset"
        }
    }
    # Verify that all import helpers are truly available in the compiled
    # launcher's extracted resource directory, not only in the source checkout.
    # An omitted worker can pass COM/source checks yet fail on a real click.
    foreach ($helperName in @('select-expansion-package.ps1', 'import-expansion-pack.ps1')) {
        $sourceHelper = Join-Path $projectRoot ('scripts\' + $helperName)
        $extractedHelper = Join-Path $resourceRoot ('scripts\' + $helperName)
        if (!(Test-Path -LiteralPath $extractedHelper -PathType Leaf)) {
            throw "Missing extracted Expansion Pack helper: $helperName"
        }
        if ((GetTes3npSha256 $extractedHelper) -ine (GetTes3npSha256 $sourceHelper)) {
            throw "Bundled Expansion Pack helper differs from source: $helperName"
        }
    }
    Step 'Verified both extracted Expansion Pack helpers and source SHA-256 hashes'
    # Check the optional race icons that the launcher actually uses.
    $speciesFolder = Join-Path $projectRoot 'assets\icons\species'
    if (Test-Path -LiteralPath $speciesFolder -PathType Container) {
        foreach ($icon in (Get-ChildItem -LiteralPath $speciesFolder -File -Filter '*.ico')) {
            if ($icon.BaseName -notin @('argonian','breton','dark-elf','high-elf','imperial',
                    'khajiit','nord','orc','redguard','wood-elf')) { continue }
            $path = Join-Path $resourceRoot ('assets\icons\species\' + $icon.Name)
            if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing extracted race portrait: $($icon.Name)"
            }
        }
    }
    # Editable icon PNGs are source-only art masters; the compiled runtime
    # uses the matching ICOs. Verify they were not needlessly FileInstalled.
    if (Test-Path -LiteralPath (Join-Path $resourceRoot 'assets\icons\tes3np.png')) {
        throw 'Unused branding PNG was embedded in the runtime.'
    }
    $runtimeSpecies = Join-Path $resourceRoot 'assets\icons\species'
    if (Test-Path -LiteralPath $runtimeSpecies) {
        if (@(Get-ChildItem -LiteralPath $runtimeSpecies -File -Filter '*.png').Count -gt 0) {
            throw 'Unused race portrait PNG masters were embedded in the runtime.'
        }
    }
    Step 'Verified editable PNG icon masters are excluded from standalone resources'
    # Legacy Expansion Pack contents and the build-only markerless client must
    # not be FileInstalled into tes3np.exe. The verified client ships in client/.
    if (Test-Path -LiteralPath (Join-Path $resourceRoot 'patches')) {
        throw 'Patch payload was embedded into the launcher instead of kept separate.'
    }
    Step 'Verified no Expansion Pack or markerless client was embedded in launcher resources'
    $menuCode = Invoke-BuildProcess $executable '--check-owned-menu-scaling' 'Compiled menu smoke test' 30000 `
        -WorkingDirectory $package -ShowOutput
    if ($menuCode -ne 0) { throw "Compiled menu smoke test failed with code $menuCode." }
    # Package the pinned official non-VR runtime so startup can run offline.
    Step 'Using prechecked official TES3MP 0.8.1 Win64 release archive'
    if (!$reuseTes3mp) {
        $archiveHash = GetTes3npSha256 $tes3mpArchive
        $runtimeExtract = Join-Path $tools 'tes3mp-extracted'
        [IO.Compression.ZipFile]::ExtractToDirectory($tes3mpArchive, $runtimeExtract)
        $runtimeExecutable = Get-ChildItem -LiteralPath $runtimeExtract -Recurse -File -Filter 'tes3mp.exe' | Select-Object -First 1
        if (!$runtimeExecutable) { throw 'Official TES3MP archive has no tes3mp.exe.' }
        $runtimeRoot = $runtimeExecutable.Directory.FullName
    }
    else {
        $runtimeRoot = $oldClientSnapshot
    }
    Step "TES3MP 0.8.1 archive SHA256 (recorded): $archiveHash"
    foreach ($name in @('tes3mp-client-default.cfg','defaults.bin','openmw.cfg')) {
        if (!(Test-Path -LiteralPath (Join-Path $runtimeRoot $name) -PathType Leaf)) {
            throw "Official TES3MP archive is missing $name beside its client."
        }
    }
    $clientFolder = Join-Path $package 'client'
    $null = New-Item -ItemType Directory -Path $clientFolder -Force
    $nonClientEntries = @('tes3mp.exe', 'tes3mp-server.exe', 'tes3mp-server-autorestart.bat',
        'tes3mp-server-default.cfg', 'server', 'bsatool.exe', 'esmtool.exe',
        'openmw-cs.exe', 'openmw-cs.cfg', 'defaults-cs.bin', 'openmw-essimporter.exe',
        'openmw-iniimporter.exe', 'openmw-launcher.exe', 'openmw-wizard.exe', 'tes3mp-browser.exe')
    foreach ($entry in (Get-ChildItem -LiteralPath $runtimeRoot -Force)) {
        if ($entry.Name -in $nonClientEntries -or $entry.Extension -ieq '.pdb') { continue }
        Copy-Item -LiteralPath $entry.FullName -Destination (Join-Path $clientFolder $entry.Name) -Recurse -Force
    }

    $clientExe = Join-Path $clientFolder 'tes3mp.exe'
    if ($consolePayload) {
        foreach ($file in $consolePayload.files) {
            $destination = Join-Path $clientFolder $file.path
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
            Copy-Item -LiteralPath (Join-Path $consoleStage $file.path) -Destination $destination -Force
        }
        $expectedMarkerless = ($consolePayload.files | Where-Object Path -eq 'tes3mp.exe').SHA256
        Test-PackagedMarkerlessConsole $clientExe
        Step 'Packaged source-built console client printed --help with the bundled DLLs'
    }
    else {
        $markerlessSource = Join-Path $projectRoot 'patches\markerless\tes3mp.exe'
        if (!(Test-Path -LiteralPath $markerlessSource)) { throw 'Bundled markerless client missing.' }
        Copy-Item -LiteralPath $markerlessSource -Destination $clientExe -Force
        $markerlessManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'patches\\manifest.json') -Raw | ConvertFrom-Json
        $expectedMarkerless = ($markerlessManifest.Files | Where-Object Path -eq 'markerless/tes3mp.exe' | Select-Object -First 1).SHA256
    }
    if ($expectedMarkerless -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'Expected SHA256 is missing or invalid for the packaged markerless client.'
    }
    $actualMarkerless = GetTes3npSha256 $clientExe
    if ($actualMarkerless -ine $expectedMarkerless) {
        throw "Packaged markerless client SHA256 mismatch. Expected $expectedMarkerless, found $actualMarkerless."
    }
    foreach ($name in @('tes3mp.exe','tes3mp-client-default.cfg','defaults.bin','openmw.cfg')) {
        if (!(Test-Path -LiteralPath (Join-Path $clientFolder $name) -PathType Leaf)) {
            throw "Incomplete packaged TES3MP runtime: $name"
        }
    }

    # Include upstream GPLv3 and bundled font notices for redistribution.
    $licenseFolder = Join-Path $package 'licenses\TES3MP'
    $null = New-Item -ItemType Directory -Path $licenseFolder -Force
    if ($reuseTes3mp) {
        Copy-Item -LiteralPath (Join-Path $oldLicenseSnapshot 'LICENSE') -Destination (Join-Path $licenseFolder 'LICENSE') -Force
        Copy-Item -LiteralPath (Join-Path $oldLicenseSnapshot 'DejaVuFontLicense.txt') -Destination (Join-Path $licenseFolder 'DejaVuFontLicense.txt') -Force
    }
    else {
        Copy-Item -LiteralPath (Join-Path $tools 'tes3mp-license.txt') -Destination (Join-Path $licenseFolder 'LICENSE') -Force
        Copy-Item -LiteralPath (Join-Path $tools 'tes3mp-font-license.txt') -Destination (Join-Path $licenseFolder 'DejaVuFontLicense.txt') -Force
    }
    if ($consolePayload) {
        $sourceFolder = Join-Path $licenseFolder 'markerless-source'
        $null = New-Item -ItemType Directory -Path $sourceFolder -Force
        foreach ($name in @('README.md', 'build-markerless.ps1', 'Restore-Markerless-Console.ps1',
            'tes3mp-0.8.1-markerless-experimental.patch', 'tes3mp-release-console.patch', 'CrabNet-LICENSE.txt')) {
            Copy-Item -LiteralPath (Join-Path $markerlessResearch $name) -Destination $sourceFolder
        }
        $consolePayload | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $sourceFolder 'client-files.json') -Encoding UTF8
        $sourceNotice = 'See markerless-source/README.md for source revisions, patches, and Windows build instructions.'
    }
    else {
        $sourceNotice = 'Corresponding source and build instructions for the legacy executable are still required before redistribution.'
    }
    @"
TES3MP runtime 0.8.1 (GPLv3 with additional permitted terms)
Upstream project and source: https://github.com/TES3MP/TES3MP/tree/tes3mp-0.8.1
Release runtime: $officialTES3MP
Original release archive SHA256: $archiveHash
TES3NP ships a separately modified markerless tes3mp.exe rather than the upstream binary.
Markerless executable SHA256: $expectedMarkerless
$sourceNotice
Bethesda Morrowind game data is not bundled and must be supplied by users.
"@ | Set-Content -LiteralPath (Join-Path $licenseFolder 'REDISTRIBUTION-NOTICE.txt') -Encoding UTF8
    Step 'Verified complete bundled TES3MP runtime and included license notices'
    Step 'Publishing Game Chat'
    # Older packaged updaters validate this installed path before copying files.
    $hostOutput = Join-Path $package 'chat-host'
    & dotnet publish $hostProject -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:DebugType=None -o $hostOutput
    if ($LASTEXITCODE -ne 0 -or !(Test-Path (Join-Path $hostOutput 'tes3np.ChatHost.exe'))) {
        throw 'WebView2 chat host publishing failed.'
    }
    if (!(Test-Path -LiteralPath (Join-Path $hostOutput 'assets\DiscordInt.png') -PathType Leaf)) {
        throw 'Published Discord sign-in emblem is missing.'
    }
    # Keep editable CSS and layout files beside the published chat host.
    Copy-Item (Join-Path $projectRoot 'game-chat\chat.css') (Join-Path $hostOutput 'chat.css') -Force
    Copy-Item (Join-Path $projectRoot 'game-chat\chat.ini') (Join-Path $hostOutput 'chat.ini') -Force
    # Keep the installed version's release notes available offline.
    Copy-Item (Join-Path $projectRoot 'RELEASE_NOTES.md') (Join-Path $package 'RELEASE_NOTES.md') -Force
    Step 'Generating the offline player guide'
    & python (Join-Path $PSScriptRoot 'render_user_guide.py') (Join-Path $projectRoot 'docs\USER-GUIDE.md') (Join-Path $package 'User Guide.html')
    if ($LASTEXITCODE -ne 0) { throw 'Offline player guide generation failed.' }
    Step 'Packaging standalone executable'
    [IO.Compression.ZipFile]::CreateFromDirectory($package, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    Step 'Validating final downloadable Windows ZIP'
    $packageCheck = @($zip)
    if ($consolePayload) { $packageCheck += '--require-console-client' }
    & python (Join-Path $PSScriptRoot 'check-windows-package.py') @packageCheck
    if ($LASTEXITCODE -ne 0) { throw 'Final Windows ZIP integrity validation failed.' }
    Step 'Installing the verified distribution into dist'
    [IO.Directory]::CreateDirectory($dist) | Out-Null
    $publishRoot = Join-Path $dist ('.publish-' + [Guid]::NewGuid().ToString('N'))
    $nextPackage = Join-Path $publishRoot 'tes3np-windows'
    $nextZip = Join-Path $publishRoot 'tes3np-windows.zip'
    $targetPackage = Join-Path $dist 'tes3np-windows'
    $targetZip = Join-Path $dist 'tes3np-windows.zip'
    $previousPackage = Join-Path $publishRoot 'previous'
    [IO.Directory]::CreateDirectory($publishRoot) | Out-Null
    $oldMoved = $false
    $newMoved = $false
    try {
        Copy-Item -LiteralPath $package -Destination $nextPackage -Recurse
        Copy-Item -LiteralPath $zip -Destination $nextZip
        if (Test-Path -LiteralPath $targetPackage) {
            [IO.Directory]::Move($targetPackage, $previousPackage)
            $oldMoved = $true
        }
        [IO.Directory]::Move($nextPackage, $targetPackage)
        $newMoved = $true
        if ([IO.File]::Exists($targetZip)) {
            [IO.File]::Replace($nextZip, $targetZip, [NullString]::Value)
        } else {
            [IO.File]::Move($nextZip, $targetZip)
        }
    } catch {
        if ($newMoved) { [IO.Directory]::Move($targetPackage, $nextPackage) }
        if ($oldMoved) { [IO.Directory]::Move($previousPackage, $targetPackage) }
        throw
    }
    Remove-Item -LiteralPath $publishRoot -Recurse -Force -ErrorAction SilentlyContinue
    Step 'Windows launcher build completed successfully'
}
finally {
    Step 'Cleaning temporary build directory (best effort)'
    # Windows may temporarily lock the downloaded compiler or macro runtime.
    # Use managed filesystem cleanup: unlike native cmd/rmdir, its failures
    # cannot leak a nonzero process status to Build tes3np.bat after a
    # successfully checked ZIP. Never touch dist or an installed launcher.
    $cleaned = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            if (-not [IO.Directory]::Exists($buildRoot)) {
                $cleaned = $true
                break
            }
            [IO.Directory]::Delete($buildRoot, $true)
            $cleaned = $true
            break
        }
        catch {
            # Retry only this build's GUID-named scratch directory; the
            # original packaging exception, if any, remains authoritative.
        }
        if ($attempt -lt 3) { Start-Sleep -Milliseconds 750 }
    }
    if (-not $cleaned) {
        Write-Warning 'Some temporary build tools remain locked. The verified distribution ZIP is unaffected.'
    }
}

# External commands used during the diagnostic/control build can leave LASTEXITCODE
# non-zero even after the complete launcher build succeeds. Explicitly return success
# once every build/validation/package checkpoint above has completed.
exit 0
