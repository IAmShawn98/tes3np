$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Step([string]$Message) { Write-Host "BUILD CHECKPOINT | $Message" }

# The SHA256 cmdlet is not present in every host configuration (including
# a reported PowerShell 7.6.9 build session). .NET hashing is available in
# both Windows PowerShell 5.1 and PowerShell 7, and verifies the same bytes.
# Keep all manifest comparisons fail-closed rather than skipping verification.
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

function Invoke-Compiler([string]$Compiler, [string]$Arguments, [string]$Label, [int]$TimeoutMs) {
    Step "Starting $Label"
    $stdout = Join-Path $env:TEMP 'tes3np-compiler-stdout.log'
    $stderr = Join-Path $env:TEMP 'tes3np-compiler-stderr.log'
    Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue

    # PowerShell 5.1 Start-Process -PassThru without -Wait can expose an
    # empty ExitCode even after calling WaitForExit() on its returned wrapper.
    # -Wait ensures PowerShell receives and populates the final process status.
    $process = Start-Process -FilePath $Compiler -ArgumentList $Arguments -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $compilerExitCode = $process.ExitCode
    Step "$Label exited with code $compilerExitCode"
    if ($null -eq $compilerExitCode -or $compilerExitCode -ne 0) {
        Step 'COMPILER DIAGNOSTICS (full logs retained in Windows TEMP)'
        if (Test-Path $stdout) { Get-Content $stdout | ForEach-Object { Write-Host $_ } }
        if (Test-Path $stderr) { Get-Content $stderr | ForEach-Object { Write-Host $_ } }
        if ($null -eq $compilerExitCode) { throw "$Label finished without a readable exit code." }
    }
    return [int]$compilerExitCode
}

$projectRoot = Split-Path $PSScriptRoot -Parent
# Every build gets a separate scratch tree. A stale Windows file lock from a
# previous run must never block a new build or collide with active tools.
$buildRoot = Join-Path $env:TEMP ('tes3np-build-' + [guid]::NewGuid().ToString('N'))
$tools = Join-Path $buildRoot 'tools'
$package = Join-Path $projectRoot 'dist\tes3np-windows'
$zip = Join-Path $projectRoot 'dist\tes3np-windows.zip'
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
    Step 'Testing ZIP and extracted-folder Expansion Pack imports using disposable fixture files'
    & (Join-Path $PSScriptRoot 'test-import-expansion-folder.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Expansion Pack folder/ZIP importer fixture failed. Previous build artifacts were not removed.' }
    Step 'Preflight compiling Chat Host before downloading tools'
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (!$dotnet) { throw 'Building embedded chat requires .NET 8 SDK. Install the .NET 8 SDK and rerun the build.' }
    $hostProject = Join-Path $projectRoot 'chat-host\tes3np.ChatHost.csproj'
    & dotnet build $hostProject -c Release -r win-x64 --no-self-contained
    if ($LASTEXITCODE -ne 0) { throw 'Chat Host preflight compilation failed. Previous build artifacts were not removed.' }
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

    $smokeSource = Join-Path $buildRoot 'compiler-smoke.ahk'; $smokeExe = Join-Path $buildRoot 'compiler-smoke.exe'
    Set-Content $smokeSource "#Requires AutoHotkey v2.0`nExitApp(0)`n" -Encoding UTF8
    $smokeArgs = '/in "' + $smokeSource + '" /out "' + $smokeExe + '" /base "' + $base + '" /compress 0 /silent verbose'
    $smokeCode = Invoke-Compiler $compiler $smokeArgs 'Ahk2Exe smoke compilation' 45000
    if ($smokeCode -ne 0 -or !(Test-Path $smokeExe)) { throw 'Ahk2Exe smoke compilation failed.' }

    # Build an isolated standalone source tree; leave developer source paths untouched.
    $stageRoot = Join-Path $buildRoot 'standalone-source'
    $null = New-Item $stageRoot -ItemType Directory
    foreach ($item in @('tes3np.ahk','src','assets','patches','scripts')) {
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
    $entryText = $entryText.Replace("`nStartLauncher()`n", "`nPrepareBundledResources()`nStartLauncher()`n")
    $entryText = $entryText.Replace("`nHandleUpdaterStartupMode()`n", "`nif A_Args.Length && A_Args[1] = `"--check-resources`"`n{`n    PrepareBundledResources()`n    ExitApp(0)`n}`nHandleUpdaterStartupMode()`n")
    $entryText = $entryText.Replace('#Include src\app\bootstrap.ahk', '#Include src\app\bootstrap.ahk' + "`n" + '#Include src\app\bundled-resources.generated.ahk')
    if (-not $entryText.Contains('#Include src\app\bundled-resources.generated.ahk')) { throw 'Generated resources include is missing.' }
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
    if (-not $entryText.Contains('PrepareBundledResources()' + "`n" + 'StartLauncher()')) { throw 'Could not insert resource initialization before launcher startup.' }
    $source = $stageEntry; $executable = Join-Path $package 'tes3np.exe'
    $arguments = '/in "' + $source + '" /out "' + $executable + '" /icon "' + (Join-Path $projectRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    $compileCode = Invoke-Compiler $compiler $arguments 'Current branch tes3np compilation' 120000
    if ($compileCode -ne 0 -or !(Test-Path $executable)) { throw 'Launcher compilation failed.' }
    Step 'Starting compiled launcher --check (30 second timeout)'
    $check = Start-Process $executable -ArgumentList '--check' -PassThru
    if (!$check.WaitForExit(30000)) { try { $check.Kill() } catch {}; throw 'Compiled launcher validation timed out after 30 seconds.' }
    Step "Compiled launcher --check exited with code $($check.ExitCode)"
    if ($check.ExitCode -ne 0) { throw 'Compiled launcher validation failed.' }
    # The --check smoke test exits before FileInstall runs. Exercise extraction
    # separately and verify every file against the manifest before packaging.
    Step 'Validating standalone embedded patch extraction'
    $extract = Start-Process $executable -ArgumentList '--check-resources' -PassThru -Wait
    if ($extract.ExitCode -ne 0) { throw "Embedded resource extraction failed with code $($extract.ExitCode)." }
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
    # Include every species icon installed in this checkout in the extraction
    # smoke test, without requiring people to have optional custom artwork.
    $speciesFolder = Join-Path $projectRoot 'assets\icons\species'
    if (Test-Path -LiteralPath $speciesFolder -PathType Container) {
        foreach ($icon in (Get-ChildItem -LiteralPath $speciesFolder -File -Filter '*.ico')) {
            $path = Join-Path $resourceRoot ('assets\icons\species\' + $icon.Name)
            if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Missing extracted species portrait: $($icon.Name)"
            }
        }
    }
    $manifestPath = Join-Path $resourceRoot 'patches\manifest.json'
    if (!(Test-Path -LiteralPath $manifestPath)) { throw "Missing extracted patch manifest: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($item in $manifest.Files) {
        $payloadPath = Join-Path (Join-Path $resourceRoot 'patches') $item.Path.Replace('/', '\')
        if (!(Test-Path -LiteralPath $payloadPath -PathType Leaf)) { throw "Missing extracted patch file: $($item.Path)" }
        $hash = GetTes3npSha256 $payloadPath
        if ($hash -ine $item.SHA256) { throw "Damaged extracted patch file: $($item.Path)" }
    }
    Step "Verified $($manifest.Files.Count) extracted patch payload files"
    # Download TES3MP only at BUILD time, never on user startup.
    # Pin to the official non-VR 0.8.1 release; do not scrape unknown mirrors.
    Step 'Downloading official TES3MP 0.8.1 Win64 runtime for distribution'
    $tes3mpArchive = Join-Path $tools 'tes3mp-0.8.1.zip'
    $officialTES3MP = 'https://github.com/TES3MP/TES3MP/releases/download/tes3mp-0.8.1/tes3mp.Win64.release.0.8.1.zip'
    Invoke-WebRequest -Uri $officialTES3MP -OutFile $tes3mpArchive -Headers $headers
    $archiveHash = GetTes3npSha256 $tes3mpArchive
    Step "TES3MP 0.8.1 archive SHA256: $archiveHash"
    $runtimeExtract = Join-Path $tools 'tes3mp-extracted'
    Expand-Archive -LiteralPath $tes3mpArchive -DestinationPath $runtimeExtract
    $runtimeExecutable = Get-ChildItem -LiteralPath $runtimeExtract -Recurse -File -Filter 'tes3mp.exe' | Select-Object -First 1
    if (!$runtimeExecutable) { throw 'Official TES3MP archive has no tes3mp.exe.' }
    $runtimeRoot = $runtimeExecutable.Directory.FullName
    foreach ($name in @('tes3mp-client-default.cfg','defaults.bin','openmw.cfg')) {
        if (!(Test-Path -LiteralPath (Join-Path $runtimeRoot $name) -PathType Leaf)) {
            throw "Official TES3MP archive is missing $name beside its client."
        }
    }
    $clientFolder = Join-Path $package 'client'
    $null = New-Item -ItemType Directory -Path $clientFolder -Force
    foreach ($entry in (Get-ChildItem -LiteralPath $runtimeRoot -Force)) {
        if ($entry.Name -ieq 'tes3mp.exe') { continue }
        Copy-Item -LiteralPath $entry.FullName -Destination (Join-Path $clientFolder $entry.Name) -Recurse -Force
    }

    # Replace ONLY the packaged copy of the official executable. The original
    # release archive and any user-installed TES3MP remain untouched.
    $markerlessSource = Join-Path $projectRoot 'patches\markerless\tes3mp.exe'
    if (!(Test-Path -LiteralPath $markerlessSource)) { throw 'Bundled markerless client missing.' }
    Copy-Item -LiteralPath $markerlessSource -Destination (Join-Path $clientFolder 'tes3mp.exe') -Force
    $markerlessManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'patches\manifest.json') -Raw | ConvertFrom-Json
    $expectedMarkerless = ($markerlessManifest.Files | Where-Object Path -eq 'markerless/tes3mp.exe' | Select-Object -First 1).SHA256
    if (!$expectedMarkerless -or (GetTes3npSha256 (Join-Path $clientFolder 'tes3mp.exe')) -ine $expectedMarkerless) {
        throw 'Packaged markerless client SHA256 mismatch.'
    }
    foreach ($name in @('tes3mp.exe','tes3mp-client-default.cfg','defaults.bin','openmw.cfg')) {
        if (!(Test-Path -LiteralPath (Join-Path $clientFolder $name) -PathType Leaf)) {
            throw "Incomplete packaged TES3MP runtime: $name"
        }
    }

    # Include upstream GPLv3 and bundled font notices for redistribution.
    $licenseFolder = Join-Path $package 'licenses\TES3MP'
    $null = New-Item -ItemType Directory -Path $licenseFolder -Force
    $upstreamLicense = 'https://raw.githubusercontent.com/TES3MP/TES3MP/tes3mp-0.8.1/LICENSE'
    $upstreamFontLicense = 'https://raw.githubusercontent.com/TES3MP/TES3MP/tes3mp-0.8.1/files/mygui/DejaVuFontLicense.txt'
    Invoke-WebRequest -Uri $upstreamLicense -OutFile (Join-Path $licenseFolder 'LICENSE') -Headers $headers
    Invoke-WebRequest -Uri $upstreamFontLicense -OutFile (Join-Path $licenseFolder 'DejaVuFontLicense.txt') -Headers $headers
    @"
TES3MP runtime 0.8.1 (GPLv3 with additional permitted terms)
Upstream project and source: https://github.com/TES3MP/TES3MP/tree/tes3mp-0.8.1
Release runtime: $officialTES3MP
Original release archive SHA256: $archiveHash
TES3NP ships a separately modified markerless tes3mp.exe rather than the upstream binary.
Markerless executable SHA256: $expectedMarkerless
Corresponding source and build instructions for the modified executable must
be made available by the distributor to comply with GPLv3. Do not publish
a release until that source and applicable third-party notices are supplied.
Bethesda Morrowind game data is not bundled and must be supplied by users.
"@ | Set-Content -LiteralPath (Join-Path $licenseFolder 'REDISTRIBUTION-NOTICE.txt') -Encoding UTF8
    Step 'Verified complete bundled TES3MP runtime and included license notices'
    Step 'Publishing embedded WebView2 chat host'
    $hostOutput = Join-Path $package 'chat-host'
    & dotnet publish $hostProject -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:DebugType=None -o $hostOutput
    if ($LASTEXITCODE -ne 0 -or !(Test-Path (Join-Path $hostOutput 'tes3np.ChatHost.exe'))) {
        throw 'WebView2 chat host publishing failed.'
    }
    # Keep editable CSS and layout files beside the published chat host.
    Copy-Item (Join-Path $projectRoot 'chat-host\chat.css') (Join-Path $hostOutput 'chat.css') -Force
    Copy-Item (Join-Path $projectRoot 'chat-host\chat.ini') (Join-Path $hostOutput 'chat.ini') -Force
    # Include draft notes for an unreleased development build only; published
    # versions always display their exact GitHub release notes.
    if ($env:GITHUB_REF_NAME -ne 'main') {
        Copy-Item (Join-Path $projectRoot 'CHANGELOG.md') (Join-Path $package 'CHANGELOG.md') -Force
    }
    Step 'Packaging standalone executable'
    Compress-Archive (Join-Path $package '*') $zip
    Step 'Validating final downloadable Windows ZIP'
    & python (Join-Path $PSScriptRoot 'check-windows-package.py') $zip
    if ($LASTEXITCODE -ne 0) { throw 'Final Windows ZIP integrity validation failed.' }
    Step 'Windows launcher build completed successfully'
}
finally {
    Step 'Cleaning temporary build directory'
    # Antivirus/indexers or a just-exited compiler can temporarily lock extracted
    # tools. Scratch cleanup is best effort once the ZIP has been validated:
    # never turn a successful build into a failure due to a locked temp file.
    # Failures in the actual build/verification try block still propagate.
    if (Test-Path -LiteralPath $buildRoot) {
        $cleanupDone = $false
        $cleanupError = 'Directory is still present.'
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $buildRoot)) {
                    $cleanupDone = $true
                    break
                }
            } catch {
                $cleanupError = $_.Exception.Message
            }
            if ($attempt -lt 3) { Start-Sleep -Milliseconds 500 }
        }
        if (-not $cleanupDone) {
            Write-Warning "Temporary files could not be fully cleaned: $buildRoot ($cleanupError). The validated package remains intact."
        }
    }
}

# External commands used during the diagnostic/control build can leave LASTEXITCODE
# non-zero even after the complete launcher build succeeds. Explicitly return success
# once every build/validation/package checkpoint above has completed.
exit 0
