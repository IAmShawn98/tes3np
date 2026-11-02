# Offline Windows regression for official Expansion Pack source choices.
# Synthetic Morrowind folder, ZIP, and config live only under TEMP.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Join-Path $env:TEMP ('tes3np-import-fixture-' + [guid]::NewGuid().ToString('N'))
$productionWorker = Join-Path $PSScriptRoot 'import-expansion-pack.ps1'
$worker = Join-Path $root 'isolated-import-worker.ps1'
$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

function AssertFixture([bool]$Passed, [string]$Message) {
    if (!$Passed) { throw "Expansion import fixture failed: $Message" }
}
function WriteFixture([string]$Path, [string]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Value, [Text.Encoding]::ASCII)
}
function CheckWorker([string]$Package, [string]$Name, [bool]$ShouldPass) {
    $job = Join-Path $root ('jobs\' + $Name)
    [IO.Directory]::CreateDirectory($job) | Out-Null
    $output = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -Package $Package -MorrowindFolder $game -ConfigFile $config -JobFolder $job 2>&1)
    $exitCode = $LASTEXITCODE
    $result = Join-Path $job 'result.ini'
    $report = if ([IO.File]::Exists($result)) {
        [IO.File]::ReadAllText($result, [Text.Encoding]::Unicode)
    } else { '[Result file missing]' }
    $workerMessage = (($report -split '\r?\n' | Where-Object { $_ -match '^Message=' }) -join '; ')
    if (!$workerMessage) { $workerMessage = $report }
    # Import worker intentionally writes only progress/result files, not stdout.
    # On failure, surface its actual sanitized result instead of "output=".
    AssertFixture (($exitCode -eq 0) -eq $ShouldPass) "$Name expected success=$ShouldPass, exit=$exitCode, detail=$workerMessage, stdout=$($output -join '; ')"
    AssertFixture ([IO.File]::Exists($result)) "$Name result metadata missing"
    $expected = if ($ShouldPass) { 'State=success' } else { 'State=error' }
    AssertFixture ($report.Contains($expected)) "$Name unexpected worker status: $workerMessage"
    if ($ShouldPass) {
        $journal = Join-Path $job 'journal.json'
        AssertFixture ([IO.File]::Exists($journal)) "$Name backup journal missing"
        $record = [IO.File]::ReadAllText($journal) | ConvertFrom-Json
        AssertFixture ([bool]$record.Completed) "$Name journal incomplete"
    }
}
try {
    AssertFixture ([IO.File]::Exists($productionWorker) -and [IO.File]::Exists($windowsPowerShell)) 'Windows importer and PowerShell runtime must exist'
    [IO.Directory]::CreateDirectory($root) | Out-Null
    # The real worker protects all running TES3MP/OpenMW instances. A build
    # must not fail merely because a player has the game open during packaging.
    # Clone the exact production script ONLY inside TEMP and stub that single
    # process guard, with a strict assertion limiting destinations to this
    # fixture's disposable synthetic game. Never alter the real worker.
    $workerText = [IO.File]::ReadAllText($productionWorker)
    $productionGuard = @'
function AssertGameClosed {
    if (Get-Process -Name 'tes3mp','openmw','openmw-launcher' -ErrorAction SilentlyContinue) {
        throw 'Close all TES3MP/OpenMW clients before importing the Expansion Pack.'
    }
}
'@
    $syntheticGuard = @'
function AssertGameClosed {
    $safeRoot = $env:TES3NP_IMPORT_FIXTURE_ROOT
    if (!$safeRoot) { throw 'Synthetic import root was not provided.' }
    $prefix = [IO.Path]::GetFullPath($safeRoot).TrimEnd('\') + '\'
    $actual = [IO.Path]::GetFullPath($MorrowindFolder)
    if (!$actual.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixture refused a target outside its disposable game folder.'
    }
}
'@
    # Repositories may be checked out with LF or CRLF on Windows.
    $workerText = $workerText.Replace("`r`n", "`n")
    $productionGuard = $productionGuard.Replace("`r`n", "`n")
    $syntheticGuard = $syntheticGuard.Replace("`r`n", "`n")
    AssertFixture ($workerText.Contains($productionGuard)) 'Production client-process protection changed; update the isolated fixture before running'
    AssertFixture ($workerText.IndexOf($productionGuard) -eq $workerText.LastIndexOf($productionGuard)) 'Ambiguous production process guard'
    [IO.File]::WriteAllText($worker, $workerText.Replace($productionGuard, $syntheticGuard), ([Text.UTF8Encoding]::new($false)))
    $env:TES3NP_IMPORT_FIXTURE_ROOT = $root
    $game = Join-Path $root 'synthetic-game'
    $data = Join-Path $game 'Data Files'
    foreach ($master in @('Morrowind.esm','Tribunal.esm','Bloodmoon.esm')) {
        WriteFixture (Join-Path $data $master) ('fake-' + $master)
    }
    $unrelated = Join-Path $data 'UnrelatedMod.esp'
    WriteFixture $unrelated 'do not modify'
    $config = Join-Path $root 'openmw.cfg'
    $originalConfig = (@('content=Morrowind.esm','content=Tribunal.esm','content=Bloodmoon.esm','') -join [Environment]::NewLine)
    WriteFixture $config $originalConfig

    $packageRoot = Join-Path $root 'extracted-package'
    $payload = Join-Path $packageRoot 'NP Update\Data Files'
    $esp = Join-Path $payload 'NP Expansion Pack.esp'
    $icon = Join-Path $payload 'Icons\tes3mp_np\test.tga'
    $mesh = Join-Path $payload 'Meshes\tes3mp_np\test.nif'
    WriteFixture $esp 'new official sample ESP'
    WriteFixture $icon 'sample-icon'
    WriteFixture $mesh 'sample-mesh'
    WriteFixture (Join-Path $packageRoot 'README.txt') 'this is outside Data Files'

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = Join-Path $root 'synthetic-official.zip'
    # Windows PowerShell 5.1 / .NET Framework CreateFromDirectory can store
    # platform-native backslashes in ZIP entry names. A canonical package
    # archive must use forward slashes, which production correctly requires.
    # Construct explicit portable ZIP entries rather than loosening the
    # importer's path-traversal/unsafe-separator checks.
    $zipStream = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $prefix = $packageRoot.TrimEnd('\') + '\'
        foreach ($sourceFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File) {
            $entryName = $sourceFile.FullName.Substring($prefix.Length).Replace('\', '/')
            AssertFixture (!$entryName.Contains('\') -and !$entryName.StartsWith('/')) 'ZIP fixture entry names must be portable'
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipStream, $sourceFile.FullName, $entryName) | Out-Null
        }
    }
    finally { $zipStream.Dispose() }
    $zipCheck = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        AssertFixture ($zipCheck.Entries.Count -ge 4) 'Portable ZIP fixture is missing expected files'
        foreach ($entry in $zipCheck.Entries) {
            AssertFixture (!$entry.FullName.Contains('\')) 'ZIP fixture unexpectedly contains Windows separators'
        }
    }
    finally { $zipCheck.Dispose() }
    CheckWorker $zip 'zip' $true
    foreach ($relative in @('NP Expansion Pack.esp','Icons\tes3mp_np\test.tga','Meshes\tes3mp_np\test.nif')) {
        $installed = Join-Path $data $relative
        $source = Join-Path $payload $relative
        AssertFixture ([IO.File]::ReadAllText($installed) -ceq [IO.File]::ReadAllText($source)) "ZIP did not install $relative"
    }
    AssertFixture ([IO.File]::ReadAllText($config).Contains('content=NP Expansion Pack.esp')) 'ZIP did not enable expansion'
    AssertFixture ([IO.File]::ReadAllText($unrelated) -ceq 'do not modify') 'ZIP touched unrelated mod'

    WriteFixture (Join-Path $data 'NP Expansion Pack.esp') 'previous ESP'
    WriteFixture $config $originalConfig
    CheckWorker $packageRoot 'folder-parent' $true
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'NP Expansion Pack.esp')) -ceq 'new official sample ESP') 'Parent-folder import did not update ESP'
    AssertFixture ([IO.File]::ReadAllText($unrelated) -ceq 'do not modify') 'Parent-folder import touched unrelated mod'

    WriteFixture (Join-Path $data 'NP Expansion Pack.esp') 'previous again'
    CheckWorker $payload 'folder-data-files' $true
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'NP Expansion Pack.esp')) -ceq 'new official sample ESP') 'Data Files selection did not update ESP'

    $badFile = Join-Path $payload 'unapproved.exe'
    WriteFixture $badFile 'malicious fixture'
    WriteFixture (Join-Path $data 'NP Expansion Pack.esp') 'pre-rejection'
    CheckWorker $packageRoot 'reject-unknown-asset' $false
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'NP Expansion Pack.esp')) -ceq 'pre-rejection') 'Rejected package modified the game'
    AssertFixture ([IO.File]::ReadAllText($unrelated) -ceq 'do not modify') 'Rejected package touched unrelated mod'

    Write-Host 'Expansion import ZIP/folder safety fixtures passed.'
    exit 0
}
catch {
    Write-Host ('Expansion import ZIP/folder fixture FAILED: ' + $_.Exception.Message)
    exit 1
}
finally {
    Remove-Item Env:\TES3NP_IMPORT_FIXTURE_ROOT -ErrorAction SilentlyContinue
    if ([IO.Directory]::Exists($root)) { [IO.Directory]::Delete($root, $true) }
}
