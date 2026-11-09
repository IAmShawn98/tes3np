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
function CheckWorker([string]$Package, [string]$Name, [bool]$ShouldPass, [string]$ExpectedError = '', [bool]$LockProgress = $false) {
    $job = Join-Path $root ('jobs\' + $Name)
    [IO.Directory]::CreateDirectory($job) | Out-Null
    $output = @()
    if ($LockProgress) {
        # Simulate the launcher reading progress.ini with no delete sharing.
        # A direct WriteAllText would collide with it. The worker must publish
        # via a temporary file and retry the atomic replacement.
        $progressPath = Join-Path $job 'progress.ini'
        [IO.File]::WriteAllText($progressPath, "[Progress]`r`nLabel=Earlier value`r`nPercent=4`r`n", [Text.Encoding]::Unicode)
        $held = [IO.File]::Open($progressPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $observedAttempt = $false
        $proc = $null
        try {
            $childArgs = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
                '-File', ('"' + $worker + '"'),
                '-Package', ('"' + $Package + '"'),
                '-MorrowindFolder', ('"' + $game + '"'),
                '-ConfigFile', ('"' + $config + '"'),
                '-JobFolder', ('"' + $job + '"'))
            $proc = Start-Process -FilePath $windowsPowerShell -ArgumentList $childArgs -PassThru -WindowStyle Hidden
            # Confirm the worker prepared its atomic status temp while locked.
            for ($watch = 0; $watch -lt 200; $watch++) {
                if (@(Get-ChildItem -LiteralPath $job -Filter '.progress.ini-*.tmp' -ErrorAction Stop).Count -gt 0) {
                    $observedAttempt = $true
                    break
                }
                if ($proc.HasExited) { break }
                Start-Sleep -Milliseconds 50
            }
            if ($observedAttempt) { Start-Sleep -Milliseconds 200 }
        }
        finally { $held.Dispose() }
        if ($proc) {
            $proc.WaitForExit()
            $exitCode = $proc.ExitCode
            $proc.Dispose()
        } else { $exitCode = -1 }
        AssertFixture ($observedAttempt) "$Name did not exercise the locked progress.ini publisher"
    }
    else {
        $output = @(& $windowsPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -Package $Package -MorrowindFolder $game -ConfigFile $config -JobFolder $job 2>&1)
        $exitCode = $LASTEXITCODE
    }
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
    # UI-facing import results must never expose the disposable user's path.
    # Real rollback locations stay in the private journal, not result.ini.
    AssertFixture (!$report.Contains($root)) "$Name leaked a local path in result.ini"
    AssertFixture (!$report.Contains('[path omitted]')) "$Name inserted a privacy placeholder"
    if ($ShouldPass) {
        AssertFixture ($report.Contains('Backup=available')) "$Name did not retain the non-sensitive backup status"
    }
    $expected = if ($ShouldPass) { 'State=success' } else { 'State=error' }
    AssertFixture ($report.Contains($expected)) "$Name unexpected worker status: $workerMessage"
    if (!$ShouldPass) {
        AssertFixture ($workerMessage.Contains('[step: ')) "$Name failed without a sanitized diagnostic stage"
    }
    AssertFixture (![IO.Directory]::Exists((Join-Path $job 'stage'))) "$Name left a full duplicate of the pack in staging"
    if (!$ShouldPass -and $ExpectedError) {
        AssertFixture ($workerMessage.Contains($ExpectedError)) "$Name rejected for an unexpected reason: $workerMessage"
        AssertFixture (!$workerMessage.Contains('Rollback was incomplete')) "$Name incorrectly reports an incomplete rollback"
    }
    if ($ShouldPass) {
        $journal = Join-Path $job 'journal.json'
        AssertFixture ([IO.File]::Exists($journal)) "$Name backup journal missing"
        $record = [IO.File]::ReadAllText($journal) | ConvertFrom-Json
        AssertFixture ([bool]$record.Completed) "$Name journal incomplete"
        foreach ($item in @($record.Files)) {
            if ($item.Existed) {
                AssertFixture ([IO.File]::Exists([string]$item.Backup)) "$Name lost a rollback backup"
            }
        }
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
    # Expansion Pack v0.2 may exceed 1 GiB or contain large individual assets.
    # These policy assertions don't create multi-gigabyte fixture files.
    AssertFixture (!$workerText.Contains('Unpacked Expansion Pack exceeds the 1 GB limit.')) 'Old 1 GiB ZIP cap reintroduced'
    AssertFixture (!$workerText.Contains('Extracted Expansion Pack exceeds the 1 GB limit.')) 'Old 1 GiB folder cap reintroduced'
    AssertFixture (!$workerText.Contains('if ($entry.Length -gt 134217728)')) 'Old 128 MiB ZIP entry cap reintroduced'
    AssertFixture (!$workerText.Contains('if ($item.Length -gt 134217728)')) 'Old 128 MiB folder asset cap reintroduced'
    AssertFixture ($workerText.Contains('AssertSpace $staged ([long]$entry.Length)')) 'ZIP free-space protection missing'
    AssertFixture ($workerText.Contains('AssertSpace $staged ([long]$item.Length)')) 'Folder free-space protection missing'
    AssertFixture ($workerText.Contains('AssertSpace $item.Target')) 'Installation destination free-space protection missing'
    AssertFixture ($workerText.Contains('function InvokeFileOperation([string]$Kind, [string]$Source, [string]$Destination, [string]$Operation)')) 'Lock retry needs explicit typed file paths'
    AssertFixture (!$workerText.Contains('InvokeLockRetry')) 'Legacy caller scriptblock retries must not return'
    AssertFixture ($workerText.Contains("'hash' {")) 'Hash branch missing from typed retry'
    AssertFixture ($workerText.Contains("'copy' {")) 'Copy branch missing from typed retry'
    AssertFixture ($workerText.Contains("'replace' {")) 'Atomic replacement branch missing from typed retry'
    AssertFixture ($workerText.Contains("'move' {")) 'New-file move branch missing from typed retry'
    AssertFixture ($workerText.Contains("'zipopen' {")) 'ZIP open branch missing from typed retry'
    AssertFixture ($workerText.Contains("InvokeFileOperation 'hash' `$Path")) 'Hash retry lost the source path'
    AssertFixture ($workerText.Contains("InvokeFileOperation 'copy' `$Source `$Target `$Operation")) 'Copy retry lost explicit paths'
    AssertFixture ($workerText.Contains("InvokeFileOperation 'replace' `$temp `$Target")) 'Replace retry lost explicit paths'
    AssertFixture ($workerText.Contains("InvokeFileOperation 'move' `$temp `$Target")) 'Move retry lost explicit paths'
    AssertFixture ($workerText.Contains("InvokeFileOperation 'zipopen' `$Package")) 'ZIP open retry lost the archive path'
    AssertFixture ($workerText.Contains('($cause -isnot [IO.IOException] -or $code -notin @(32,33))')) 'Retry must remain limited to Windows lock errors'
    AssertFixture ($workerText.Contains('[IO.File]::Replace($Source, $Destination, [NullString]::Value)')) 'PowerShell 5.1 File.Replace requires a real CLR null, not a coerced empty backup filename'
    AssertFixture ($workerText.Contains("WriteJobIni 'progress.ini' `$body")) 'Progress must use atomic publisher'
    AssertFixture ($workerText.Contains("WriteJobIni 'result.ini' `$body")) 'Result must use atomic publisher'
    AssertFixture ($workerText.Contains("InvokeFileOperation 'replace' `$temp `$target")) 'Atomic status replacement must retry locks'
    AssertFixture (!$workerText.Contains('[IO.File]::Replace($Source, $Destination, $null)')) 'Do not pass $null into .NET string argument for replacement backup'
    AssertFixture ($workerText.Contains("ReplaceVerified `$item.Source `$item.Target `$item.Hash`n        `$changed += `$backups[`$i]")) 'Rollback must track successfully committed replacements, not failed lock attempts'
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
    $sound = Join-Path $payload 'Sound\tes3mp_np\mnts\contact.wav'
    WriteFixture $esp 'new official sample ESP'
    WriteFixture $icon 'sample-icon'
    WriteFixture $mesh 'sample-mesh'
    # The official updated ZIP previously failed on this sound effect.
    WriteFixture $sound 'sample-contact-audio'
    WriteFixture (Join-Path $packageRoot 'README.txt') 'this is outside Data Files'

    # Windows PowerShell 5.1 does not necessarily load ZipArchiveMode
    # from System.IO.Compression when only FileSystem is referenced.
    # Both are required: ZipArchiveMode is in System.IO.Compression,
    # while ZipFile / ZipFileExtensions live in FileSystem on .NET Framework.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    AssertFixture ([IO.Compression.ZipArchiveMode]::Create -ne $null) 'ZipArchiveMode could not be loaded'
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
    # Directly exercise the exact Windows PowerShell 5.1/.NET interop bug:
    # $null can bind as an empty backup filename in File.Replace. An existing
    # destination must be replaced while passing a real CLR null string.
    $replaceOld = Join-Path $root 'clr-null-old.cfg'
    $replaceNew = Join-Path $root 'clr-null-new.cfg'
    WriteFixture $replaceOld 'old-clr-null'
    WriteFixture $replaceNew 'new-clr-null'
    [IO.File]::Replace($replaceNew, $replaceOld, [NullString]::Value)
    AssertFixture ([IO.File]::ReadAllText($replaceOld) -ceq 'new-clr-null') 'CLR null File.Replace cannot update an existing config'
    AssertFixture (![IO.File]::Exists($replaceNew)) 'File.Replace left a staging file after replacing configuration'
    CheckWorker $zip 'zip' $true
    # Ensure a real game-file replacement is needed on the second import.
    WriteFixture (Join-Path $data 'NP Expansion Pack.esp') 'previous before progress lock'
    # Retest while the launcher-like progress reader holds the INI open.
    CheckWorker $zip 'zip-progress-reader-lock' $true '' $true
    foreach ($relative in @('NP Expansion Pack.esp','Icons\tes3mp_np\test.tga','Meshes\tes3mp_np\test.nif','Sound\tes3mp_np\mnts\contact.wav')) {
        $installed = Join-Path $data $relative
        $source = Join-Path $payload $relative
        AssertFixture ([IO.File]::ReadAllText($installed) -ceq [IO.File]::ReadAllText($source)) "ZIP did not install $relative"
    }
    AssertFixture ([IO.File]::ReadAllText($config).Contains('content=NP Expansion Pack.esp')) 'ZIP did not enable expansion'
    AssertFixture ([IO.File]::ReadAllText($unrelated) -ceq 'do not modify') 'ZIP touched unrelated mod'

    # The real failure mode is ERROR_LOCK_VIOLATION (byte-range lock).
    # Hold one byte in an already installed asset from THIS test process,
    # verify finite retries end safely, then release and successfully import.
    $lockedAsset = Join-Path $data 'NP Expansion Pack.esp'
    WriteFixture $lockedAsset 'old locked ESP content'
    $held = [IO.File]::Open($lockedAsset, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
    $held.Lock(0, 1)
    try {
        CheckWorker $zip 'reject-persistent-win32-lock' $false 'six attempts'
    }
    finally {
        $held.Unlock(0, 1)
        $held.Dispose()
    }
    AssertFixture ([IO.File]::ReadAllText($lockedAsset) -ceq 'old locked ESP content') 'File lock caused a partial game update'
    CheckWorker $zip 'recover-after-lock' $true
    AssertFixture ([IO.File]::ReadAllText($lockedAsset) -ceq 'new official sample ESP') 'Reimport after releasing lock failed'

    # Deliberately malformed ZIP: the importer must continue rejecting
    # Windows-style backslashes in archive entry names, not normalize them.
    $badZip = Join-Path $root 'reject-unsafe-backslashes.zip'
    $badArchive = [IO.Compression.ZipFile]::Open($badZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $badEntry = $badArchive.CreateEntry('NP Update\Data Files\NP Expansion Pack.esp')
        AssertFixture ($badEntry.FullName.Contains('\')) 'Malformed ZIP fixture entry must contain backslashes'
    }
    finally { $badArchive.Dispose() }
    CheckWorker $badZip 'reject-backslash-entry' $false 'unsafe file path'
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'NP Expansion Pack.esp')) -ceq 'new official sample ESP') 'Rejected malformed ZIP changed the installed expansion'

    WriteFixture (Join-Path $data 'NP Expansion Pack.esp') 'previous ESP'
    WriteFixture $config $originalConfig
    CheckWorker $packageRoot 'folder-parent' $true
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'NP Expansion Pack.esp')) -ceq 'new official sample ESP') 'Parent-folder import did not update ESP'
    AssertFixture ([IO.File]::ReadAllText($unrelated) -ceq 'do not modify') 'Parent-folder import touched unrelated mod'

    WriteFixture (Join-Path $data 'NP Expansion Pack.esp') 'previous again'
    CheckWorker $payload 'folder-data-files' $true
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'NP Expansion Pack.esp')) -ceq 'new official sample ESP') 'Data Files selection did not update ESP'
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'Sound\tes3mp_np\mnts\contact.wav')) -ceq 'sample-contact-audio') 'Folder import did not retain sound'

    # Non-NP sound directories are not accepted.
    $foreignSound = Join-Path $payload 'Sound\other_mod\contact.wav'
    WriteFixture $foreignSound 'not-part-of-NP'
    WriteFixture (Join-Path $data 'NP Expansion Pack.esp') 'pre-sound-rejection'
    CheckWorker $packageRoot 'reject-foreign-sound' $false 'Unexpected file in Expansion Pack Data Files'
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'NP Expansion Pack.esp')) -ceq 'pre-sound-rejection') 'Foreign sound changed installed ESP'
    Remove-Item -LiteralPath $foreignSound -Force

    # Never allow executables into Sound even within the NP namespace.
    $invalidAudio = Join-Path $payload 'Sound\tes3mp_np\mnts\unapproved.exe'
    WriteFixture $invalidAudio 'not-audio'
    CheckWorker $packageRoot 'reject-non-audio-sound' $false 'Unexpected file in Expansion Pack Data Files'
    AssertFixture ([IO.File]::ReadAllText((Join-Path $data 'NP Expansion Pack.esp')) -ceq 'pre-sound-rejection') 'Invalid sound changed installed ESP'
    Remove-Item -LiteralPath $invalidAudio -Force

    $badFile = Join-Path $payload 'unapproved.exe'
    WriteFixture $badFile 'malicious fixture'
    WriteFixture (Join-Path $data 'NP Expansion Pack.esp') 'pre-rejection'
    CheckWorker $packageRoot 'reject-unknown-asset' $false 'Unexpected file in Expansion Pack Data Files'
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
