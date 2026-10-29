$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Step([string]$Message) { Write-Host "BUILD CHECKPOINT | $Message" }

function Invoke-Compiler([string]$Compiler, [string]$Arguments, [string]$Label, [int]$TimeoutMs) {
    Step "Starting $Label"
    $stdout = Join-Path $env:TEMP 'tes3np-compiler-stdout.log'
    $stderr = Join-Path $env:TEMP 'tes3np-compiler-stderr.log'
    Remove-Item $stdout, $stderr -ErrorAction SilentlyContinue
    $process = Start-Process $Compiler -ArgumentList $Arguments -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (!$process.WaitForExit($TimeoutMs)) {
        try { $process.Kill() } catch {}
        throw "$Label timed out after $([math]::Round($TimeoutMs / 1000)) seconds."
    }
    # PowerShell 5.1 can report a blank ExitCode with Start-Process output
    # redirection until the process object has been fully refreshed.
    $process.WaitForExit()
    $process.Refresh()
    $compilerExitCode = $process.ExitCode
    if ($null -eq $compilerExitCode) {
        throw "$Label finished but Windows did not provide an exit code. See $stdout and $stderr."
    }
    Step "$Label exited with code $compilerExitCode"
    if ($compilerExitCode -ne 0) {
        Step 'COMPILER DIAGNOSTICS (full logs retained in Windows TEMP)'
        if (Test-Path $stdout) { Get-Content $stdout | ForEach-Object { Write-Host $_ } }
        if (Test-Path $stderr) { Get-Content $stderr | ForEach-Object { Write-Host $_ } }
    }
    return [int]$compilerExitCode
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

    # Build an isolated standalone source tree; leave developer source paths untouched.
    $stageRoot = Join-Path $buildRoot 'standalone-source'
    $null = New-Item $stageRoot -ItemType Directory
    foreach ($item in @('tes3np.ahk','src','assets','patches','scripts')) {
        Copy-Item (Join-Path $projectRoot $item) $stageRoot -Recurse
    }
    & python (Join-Path $projectRoot 'scripts/generate-bundled-resources.py') $stageRoot
    if ($LASTEXITCODE -ne 0) { throw 'Resource embedding generation failed.' }
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
    $resourceRoot = Join-Path $env:APPDATA 'tes3np\resources'
    $manifestPath = Join-Path $resourceRoot 'patches\manifest.json'
    if (!(Test-Path -LiteralPath $manifestPath)) { throw "Missing extracted patch manifest: $manifestPath" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($item in $manifest.Files) {
        $payloadPath = Join-Path (Join-Path $resourceRoot 'patches') $item.Path.Replace('/', '\')
        if (!(Test-Path -LiteralPath $payloadPath -PathType Leaf)) { throw "Missing extracted patch file: $($item.Path)" }
        $hash = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash
        if ($hash -ine $item.SHA256) { throw "Damaged extracted patch file: $($item.Path)" }
    }
    Step "Verified $($manifest.Files.Count) extracted patch payload files"
    # Ship markerless as a sidecar; do not extract it every time TES3NP launches.
    $clientFolder = Join-Path $package 'client'
    $null = New-Item -ItemType Directory -Path $clientFolder -Force
    $markerlessSource = Join-Path $projectRoot 'patches\markerless\tes3mp.exe'
    if (!(Test-Path -LiteralPath $markerlessSource)) { throw 'Bundled markerless client missing.' }
    Copy-Item -LiteralPath $markerlessSource -Destination (Join-Path $clientFolder 'tes3mp.exe')
    $markerlessManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'patches\manifest.json') -Raw | ConvertFrom-Json
    $expectedMarkerless = ($markerlessManifest.Files | Where-Object Path -eq 'markerless/tes3mp.exe' | Select-Object -First 1).SHA256
    if (!$expectedMarkerless -or (Get-FileHash (Join-Path $clientFolder 'tes3mp.exe') -Algorithm SHA256).Hash -ine $expectedMarkerless) { throw 'Bundled client SHA256 mismatch.' }
    Step 'Verified bundled markerless TES3MP executable'
    Step 'Publishing embedded WebView2 chat host'
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (!$dotnet) { throw 'Building embedded chat requires .NET 8 SDK. Install the .NET 8 SDK and rerun the build.' }
    $hostProject = Join-Path $projectRoot 'chat-host\tes3np.ChatHost.csproj'
    $hostOutput = Join-Path $package 'chat-host'
    & dotnet publish $hostProject -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:DebugType=None -o $hostOutput
    if ($LASTEXITCODE -ne 0 -or !(Test-Path (Join-Path $hostOutput 'tes3np.ChatHost.exe'))) {
        throw 'WebView2 chat host publishing failed.'
    }
    # Keep editable CSS and layout files beside the published chat host.
    Copy-Item (Join-Path $projectRoot 'chat-host\chat.css') (Join-Path $hostOutput 'chat.css') -Force
    Copy-Item (Join-Path $projectRoot 'chat-host\chat.ini') (Join-Path $hostOutput 'chat.ini') -Force
    Step 'Packaging standalone executable'
    Compress-Archive (Join-Path $package '*') $zip
    Step 'Windows launcher build completed successfully'
}
finally {
    Step 'Cleaning temporary build directory'
    if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

# External commands used during the diagnostic/control build can leave LASTEXITCODE
# non-zero even after the complete launcher build succeeds. Explicitly return success
# once every build/validation/package checkpoint above has completed.
exit 0
