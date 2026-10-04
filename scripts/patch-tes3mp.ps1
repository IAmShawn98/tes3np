# Windows PowerShell 5.1. Never execute patch payloads during installation.
param(
    [ValidateSet('Apply','Verify','Restore')][string]$Action = 'Apply',
    [Parameter(Mandatory=$true)][string]$TesFolder,
    [Parameter(Mandatory=$true)][string]$MorrowindFolder,
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$PayloadFolder,
    [Parameter(Mandatory=$true)][string]$JobFolder,
    [string]$RestoreFolder = '',
    [string]$PreviousBackup = ''
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$stage = 'Checking installation'
$field = 'TES3MP folder'
$fileLabel = 'tes3mp.exe'
$journal = @()
$changed = @()
$rollbackReady = $false
$logs = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'tes3np'
$settingsFile = Join-Path $logs 'settings.ini'
$skipMarkerless = $false
if ([IO.File]::Exists($settingsFile)) {
    $skipMarkerless = [IO.File]::ReadAllLines($settingsFile) | Where-Object { $_.Trim() -ieq 'CustomClientChoice=skip' } | Select-Object -First 1
    $skipMarkerless = [bool]$skipMarkerless
}

function Replace-ExistingFile([string]$Source, [string]$Destination) {
    $replacementBackup = $Destination + '.tes3np-replace-' + [guid]::NewGuid().ToString('N')
    [IO.File]::Replace($Source, $Destination, $replacementBackup)
    try { [IO.File]::Delete($replacementBackup) } catch { }
}
function Write-AtomicText([string]$Path, [string]$Text, [Text.Encoding]$Encoding = $utf8) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, $Text, $Encoding)
    if ([IO.File]::Exists($Path)) { Replace-ExistingFile $temporary $Path }
    else { [IO.File]::Move($temporary, $Path) }
}
function Progress([string]$Label, [int]$Percent) {
    $script:stage = $Label
    Write-AtomicText (Join-Path $JobFolder 'progress.ini') ("[Progress]`r`nLabel=$Label`r`nPercent=$Percent`r`n") ([Text.Encoding]::Unicode)
}
function Log-Event([string]$Message, [bool]$ErrorEvent = $false) {
    [IO.Directory]::CreateDirectory($logs) | Out-Null
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message + "`r`n"
    [IO.File]::AppendAllText((Join-Path $logs 'patch-all.log'), $line, $utf8)
    if ($ErrorEvent) { [IO.File]::AppendAllText((Join-Path $logs 'patch-errors.log'), $line, $utf8) }
}
function Result([string]$State, [string]$Message, [string]$Backup = '') {
    Write-AtomicText (Join-Path $JobFolder 'result.ini') ("[Result]`r`nState=$State`r`nMessage=$Message`r`nBackup=$Backup`r`n") ([Text.Encoding]::Unicode)
}
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Canonical([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -eq [IO.Path]::GetPathRoot($full)) { return $full }
    return $full.TrimEnd([char]92,[char]47)
}
function Ensure-PlainPath([string]$Path) {
    $node = Canonical $Path
    $root = [IO.Path]::GetPathRoot($node)
    while ($node) {
        if (Test-Path -LiteralPath $node) {
            $item = Get-Item -LiteralPath $node -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked folders/files are not supported. Choose a physical installation path.' }
        }
        if ($node.TrimEnd([char]92,[char]47) -ieq $root.TrimEnd([char]92,[char]47)) { break }
        $parent = [IO.Path]::GetDirectoryName($node)
        if ($parent -eq $node) { break }
        $node = $parent
    }
}
function Assert-GameClosed {
    if (Get-Process -Name 'tes3mp','openmw','openmw-launcher','tes3mp-browser' -ErrorAction SilentlyContinue) { throw 'Close TES3MP, its terminal, and the OpenMW launcher before continuing.' }
}
function Make-Config([string]$Original) {
    $lines = @($Original -split '\r?\n')
    if ($lines | Where-Object { $_ -match '^\s*config\s*=' }) { throw 'This configuration redirects to other configuration folders. Select the active user openmw.cfg instead.' }
    $kept = @($lines | Where-Object { $_ -notmatch '^\s*content\s*=\s*"?NP Expansion Pack\.esp"?\s*$' })
    $data = Join-Path $MorrowindFolder 'Data Files'
    $hasData = $false
    foreach ($line in $kept) {
        if ($line -match '^\s*data\s*=\s*(.+?)\s*$') {
            $value = $matches[1].Trim([char]34)
            try { if ((Canonical $value) -ieq (Canonical $data)) { $hasData = $true } } catch { }
        }
    }
    $contents = @($kept | Where-Object { $_ -match '^\s*content\s*=' })
    if ($contents.Count -eq 0) { $kept += 'content=Morrowind.esm','content=Tribunal.esm','content=Bloodmoon.esm' }
    else {
        foreach ($master in @('Morrowind.esm','Tribunal.esm','Bloodmoon.esm')) {
            $pattern = '^\s*content\s*=\s*"?' + [regex]::Escape($master) + '"?\s*$'
            if (-not ($kept | Where-Object { $_ -match $pattern })) { throw 'Existing load order is missing an official master. Configure Morrowind, Tribunal and Bloodmoon first.' }
        }
    }
    if (-not $hasData) { $kept += ('data="' + $data.Replace('\','/') + '"') }
    $kept += 'content=NP Expansion Pack.esp'
    $oldContent = @($lines | Where-Object { $_ -match '^\s*content\s*=' })
    $ep = @($oldContent | Where-Object { $_ -match '^\s*content\s*=\s*"?NP Expansion Pack\.esp"?\s*$' })
    $good = $hasData -and $ep.Count -eq 1 -and $oldContent[-1] -match '^\s*content\s*=\s*"?NP Expansion Pack\.esp"?\s*$'
    return [pscustomobject]@{Text=(($kept -join "`r`n") + "`r`n");AlreadyGood=$good}
}
function Copy-Verified([string]$Source, [string]$Target, [string]$Expected) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target)) | Out-Null
    $temporary = $Target + '.tes3np-patch-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::Copy($Source, $temporary, $false)
        if ((Hash $temporary) -ne $Expected) { throw 'Copied file failed verification.' }
        if ([IO.File]::Exists($Target)) { Replace-ExistingFile $temporary $Target }
        else { [IO.File]::Move($temporary, $Target) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

try {
    [IO.Directory]::CreateDirectory($JobFolder) | Out-Null
    Progress 'Checking installation' 0
    Log-Event ("$Action started. Markerless skip: $skipMarkerless")
    $TesFolder = Canonical $TesFolder
    $MorrowindFolder = Canonical $MorrowindFolder
    $ConfigFile = [IO.Path]::GetFullPath($ConfigFile)
    $executable = Join-Path $TesFolder 'tes3mp.exe'
    if ($Action -ne 'Verify') { Assert-GameClosed }
    if (-not [IO.File]::Exists($executable)) { throw 'Select a TES3MP folder containing tes3mp.exe.' }
    Ensure-PlainPath $executable
    $field = 'OpenMW configuration'
    $fileLabel = 'openmw.cfg'
    Ensure-PlainPath $ConfigFile
    if ([IO.Path]::GetFileName($ConfigFile) -ine 'openmw.cfg') { throw 'Select an openmw.cfg configuration file.' }

    if ($Action -eq 'Restore') {
        $field = 'Restore backup'; $fileLabel = 'journal.json'; Progress 'Checking backup' 5
        $backupJournal = Join-Path $RestoreFolder 'journal.json'
        if (-not [IO.File]::Exists($backupJournal)) { throw 'The patch backup was not found.' }
        $saved = Get-Content -LiteralPath $backupJournal -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.Completed -ne $true -or $saved.Restored -eq $true -or (Canonical $saved.TesFolder) -ine $TesFolder -or (Canonical $saved.MorrowindFolder) -ine $MorrowindFolder -or (Canonical $saved.ConfigFile) -ine $ConfigFile) { throw 'This backup does not match the selected installation or has already been restored.' }
        foreach ($item in $saved.Files) {
            $fileLabel = [IO.Path]::GetFileName($item.Target); Ensure-PlainPath $item.Target
            if (-not [IO.File]::Exists($item.Target) -or (Hash $item.Target) -ne $item.InstalledHash) { throw 'Files have changed since this patch. Restore was stopped to preserve your changes.' }
            if ($item.Existed -and (-not [IO.File]::Exists($item.Backup) -or (Hash $item.Backup) -ne $item.OriginalHash)) { throw 'A backup file is missing or damaged.' }
        }
        $i = 0
        foreach ($item in $saved.Files) {
            $backup = Join-Path $JobFolder ('rollback\' + $i); [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
            [IO.File]::Copy($item.Target,$backup,$false)
            $journal += [pscustomobject]@{Target=$item.Target;Existed=$true;Backup=$backup;OriginalHash=$item.InstalledHash;InstalledHash=$item.OriginalHash}; $i++
        }
        $rollbackReady = $true; $i = 0
        foreach ($item in $saved.Files) {
            $fileLabel = [IO.Path]::GetFileName($item.Target); Assert-GameClosed
            Progress ('Restoring ' + [IO.Path]::GetFileName($item.Target)) ([int](10 + 85 * $i / [Math]::Max(1,$saved.Files.Count)))
            $changed += $journal[$i]
            if ($item.Existed) { Copy-Verified $item.Backup $item.Target $item.OriginalHash } else { [IO.File]::Delete($item.Target) }
            Log-Event ('Restored managed file ' + ($i + 1) + '.'); $i++
        }
        $saved.Restored = $true; Write-AtomicText $backupJournal ($saved | ConvertTo-Json -Depth 6)
        Progress 'Restore complete' 100; Result 'success' 'Previous files restored. Patch again before using NP launch features.' $saved.PreviousBackup; Log-Event 'Restore completed.'; exit 0
    }

    $field = 'Morrowind folder'; Progress 'Checking Morrowind game files' 5
    foreach ($master in @('Morrowind.esm','Tribunal.esm','Bloodmoon.esm')) {
        $fileLabel = 'Data Files/' + $master
        if (-not [IO.File]::Exists((Join-Path $MorrowindFolder ('Data Files\' + $master)))) { throw ('Required official master is missing: ' + $master + '. Choose the Morrowind GOTY installation folder.') }
    }
    Ensure-PlainPath (Join-Path $MorrowindFolder 'Data Files')
    $field = 'TES3MP folder'; $fileLabel = 'openmw.cfg'
    if (-not [IO.File]::Exists((Join-Path $TesFolder 'openmw.cfg'))) { throw 'This TES3MP installation is missing its bundled openmw.cfg. Extract a complete TES3MP client first.' }
    $fileLabel = 'tes3mp.exe'; $binary = [IO.File]::ReadAllBytes($executable); $offset = [BitConverter]::ToInt32($binary,60)
    if ($offset -lt 64 -or ($offset + 6) -gt $binary.Length -or [BitConverter]::ToUInt16($binary,$offset+4) -ne 0x8664 -or [Text.Encoding]::ASCII.GetString($binary) -notmatch 'Your client is on version 0\.8\.1') { throw 'These bundled patches require TES3MP 0.8.1 for 64-bit Windows.' }
    Progress 'Verifying bundled patch files' 10
    $field = 'Bundled patches'; $fileLabel = 'patches/manifest.json'
    $manifest = Get-Content -LiteralPath (Join-Path $PayloadFolder 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(); $i = 0
    foreach ($file in $manifest.Files) {
        $fileLabel = 'patches/' + $file.Path; $relative = $file.Path.Replace('/', '\')
        if ($relative -match '(^|\\)\.\.($|\\)|:' -or [IO.Path]::IsPathRooted($relative)) { throw 'Invalid bundled patch path.' }
        $source = Join-Path $PayloadFolder $relative; Ensure-PlainPath $source
        if (-not [IO.File]::Exists($source) -or (Hash $source) -ne $file.SHA256) { throw 'A bundled patch file is missing or damaged. Extract a fresh launcher ZIP.' }
        if ($relative -eq 'markerless\tes3mp.exe') {
            $target = $executable
            if ($skipMarkerless) { $i++; Progress 'Keeping custom tes3mp.exe' ([int](10 + 20 * $i / $manifest.Files.Count)); continue }
        }
        elseif ($relative.StartsWith('expansion-pack\Data Files\')) { $target = Join-Path $MorrowindFolder $relative.Substring('expansion-pack\'.Length) }
        elseif ($relative -eq 'expansion-pack\LICENSE.txt') { $target = Join-Path $TesFolder 'tes3np-NP-EP-LICENSE.txt' }
        else { throw 'Unknown bundled patch file.' }
        Ensure-PlainPath $target
        if ($Action -ne 'Verify' -or $relative -ne 'expansion-pack\LICENSE.txt') { $plan += [pscustomobject]@{Source=$source;Target=$target;Hash=$file.SHA256} }
        $i++; Progress ('Checking ' + [IO.Path]::GetFileName($source)) ([int](10 + 20 * $i / $manifest.Files.Count))
    }
    $field = 'OpenMW configuration'; $fileLabel = 'openmw.cfg'
    $originalConfig = if ([IO.File]::Exists($ConfigFile)) { [IO.File]::ReadAllText($ConfigFile) } else { '' }
    $configuration = Make-Config $originalConfig; $stagedConfig = Join-Path $JobFolder 'prepared-openmw.cfg'
    if ($configuration.AlreadyGood) { [IO.File]::Copy($ConfigFile,$stagedConfig,$true) } else { [IO.File]::WriteAllText($stagedConfig,$configuration.Text,$utf8) }
    $plan += [pscustomobject]@{Source=$stagedConfig;Target=$ConfigFile;Hash=(Hash $stagedConfig)}
    $needed = @($plan | Where-Object { -not [IO.File]::Exists($_.Target) -or (Hash $_.Target) -ne $_.Hash })
    if ($Action -eq 'Verify') {
        if ($needed.Count) {
            $fileLabel = [IO.Path]::GetFileName($needed[0].Target); $field = 'Installed files / configuration'
            Log-Event ('Setup needed: verification found ' + $needed.Count + ' missing or different managed file(s). First mismatch: ' + $fileLabel + '.')
            Progress 'Setup needed' 100
            Result 'needs_setup' 'This copy of TES3MP needs the Nerevarine Prophecies patches. Click Install / Repair to install or update the required files. Your game has not been changed by this check.' $PreviousBackup; exit 0
        }
        Progress 'Verification complete' 100
        $verifiedMessage = if ($skipMarkerless) { 'Custom TES3MP client preserved; EP files and plugin load order verified.' } else { 'Markerless client, EP files and plugin load order verified.' }
        Result 'success' $verifiedMessage $PreviousBackup; Log-Event 'Verification completed.'; exit 0
    }
    if (-not $needed.Count) {
        Progress 'Already installed and verified' 100
        $alreadyMessage = if ($skipMarkerless) { 'Already installed. Custom tes3mp.exe preserved; EP files and configuration verified.' } else { 'Already installed. All patch files and EP configuration verified.' }
        Result 'success' $alreadyMessage $PreviousBackup; Log-Event 'No file changes needed; verification completed.'; exit 0
    }
    Progress 'Backing up files before changes' 35; $i = 0
    foreach ($item in $needed) {
        $field = 'Backup storage'; $fileLabel = [IO.Path]::GetFileName($item.Target); $exists = [IO.File]::Exists($item.Target); $backup = Join-Path $JobFolder ('backup\' + $i); $originalHash = ''
        if ($exists) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null; [IO.File]::Copy($item.Target,$backup,$false); $originalHash = Hash $item.Target; if ((Hash $backup) -ne $originalHash) { throw 'A backup file failed verification.' } }
        Progress ('Backing up ' + [IO.Path]::GetFileName($item.Target)) ([int](30 + 10 * $i / $needed.Count))
        $journal += [pscustomobject]@{Target=$item.Target;Existed=$exists;Backup=$backup;OriginalHash=$originalHash;InstalledHash=$item.Hash}; $i++
    }
    $record = [pscustomobject]@{Completed=$false;Restored=$false;TesFolder=$TesFolder;MorrowindFolder=$MorrowindFolder;ConfigFile=$ConfigFile;PreviousBackup=$PreviousBackup;Files=$journal}
    Write-AtomicText (Join-Path $JobFolder 'journal.json') ($record | ConvertTo-Json -Depth 6); $rollbackReady = $true; $i = 0
    foreach ($item in $needed) {
        $field = 'Installation destination'; $fileLabel = [IO.Path]::GetFileName($item.Target); Assert-GameClosed
        Progress ('Patching ' + [IO.Path]::GetFileName($item.Target)) ([int](40 + 50 * $i / $needed.Count)); $changed += $journal[$i]
        Copy-Verified $item.Source $item.Target $item.Hash; Log-Event ('Installed managed file ' + ($i + 1) + '.'); $i++
    }
    Progress 'Verifying installed files and load order' 95
    foreach ($item in $plan) { $fileLabel = [IO.Path]::GetFileName($item.Target); if ((Hash $item.Target) -ne $item.Hash) { throw 'Installed file verification failed.' } }
    $record.Completed = $true; Write-AtomicText (Join-Path $JobFolder 'journal.json') ($record | ConvertTo-Json -Depth 6); Progress 'Setup complete' 100
    $successMessage = if ($skipMarkerless) { 'Custom tes3mp.exe preserved. NP Expansion Pack installed and verified. Direct connect is ready through tes3np.' } else { 'Markerless client and NP Expansion Pack installed and verified. Direct connect is ready through tes3np.' }
    Result 'success' $successMessage $JobFolder; Log-Event 'Setup completed.'; exit 0
} catch {
    $baseError = $_.Exception.GetBaseException(); $reason = $baseError.Message; $errorType = $baseError.GetType().FullName; $hresult = $baseError.HResult.ToString('X8'); $win32 = $baseError.HResult -band 0xFFFF
    if ($hresult.StartsWith('8007')) {
        switch ($win32) {
            5 { $reason = 'Access denied. Check write permissions for this location.' }
            32 { $reason = 'The file is being used by another process. Close the game, its terminal and OpenMW Launcher.' }
            33 { $reason = 'The file is locked by another process.' }
            112 { $reason = 'The destination disk is full. Free disk space and retry.' }
            39 { $reason = 'There is not enough disk space for the file operation.' }
            2 { $reason = 'The required file was not found.' }
            3 { $reason = 'The required folder/path was not found.' }
        }
    }
    $reason = [regex]::Replace($reason, '"[A-Za-z]:\\[^"\r\n]*"', '[path omitted]'); $reason = [regex]::Replace($reason, '[A-Za-z]:\\[^\r\n]+', '[path omitted]'); $reason = [regex]::Replace($reason, '\\\\[^\r\n]+', '[network path omitted]'); $reason = ($reason -replace '[\r\n]+',' ').Trim()
    $failureLine = $_.InvocationInfo.ScriptLineNumber; $failureFunction = ($_.ScriptStackTrace -split "`r?`n")[0] -replace ", .*: line", ": line"
    $message = "Source line: $failureLine | Function: $failureFunction | Step: $stage | Field: $field | File: $fileLabel | Reason: $reason | Error type: $errorType | HRESULT: 0x$hresult"
    if ($hresult.StartsWith('8007')) { $message += " | Win32: $win32" }
    $rollbackFailed = $false
    if ($rollbackReady) {
        foreach ($item in @($changed | Select-Object -Last 10000)) {
            try { if ($item.Existed) { Copy-Verified $item.Backup $item.Target $item.OriginalHash } elseif ([IO.File]::Exists($item.Target)) { [IO.File]::Delete($item.Target) } } catch { $rollbackFailed = $true }
        }
        if ($rollbackFailed) { $message += ' Automatic rollback could not restore every file; keep the patch backup for recovery.' } else { $message += ' Changes from this attempt were rolled back.' }
    }
    Log-Event ($message) $true; Result 'error' $message; exit 1
}