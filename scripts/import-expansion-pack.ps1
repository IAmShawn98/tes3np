# Import an NP-supplied ESP or ZIP after TES3MP rejects the installed plugins.
# This operates on the selected Morrowind Data Files and active OpenMW config,
# never on the bundled launcher/client or user credentials.
param(
    [Parameter(Mandatory=$true)][string]$Package,
    [Parameter(Mandatory=$true)][string]$MorrowindFolder,
    [Parameter(Mandatory=$true)][string]$ConfigFile,
    [Parameter(Mandatory=$true)][string]$JobFolder
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Sha256([string]$Path) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
        finally { $stream.Dispose() }
    } finally { $hasher.Dispose() }
}
function Progress([string]$Text, [int]$Percent) {
    $clean = $Text.Replace([Environment]::NewLine, ' ').Replace('=', '-')
    $body = '[Progress]' + [Environment]::NewLine + 'Label=' + $clean + [Environment]::NewLine +
        'Percent=' + $Percent + [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $JobFolder 'progress.ini'), $body, [Text.Encoding]::Unicode)
}
function Result([string]$State, [string]$Message, [string]$Backup = '') {
    $clean = [regex]::Replace($Message, '[\r\n=]+', ' ')
    $body = '[Result]' + [Environment]::NewLine + 'State=' + $State + [Environment]::NewLine +
        'Message=' + $clean + [Environment]::NewLine + 'Backup=' + $Backup + [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $JobFolder 'result.ini'), $body, [Text.Encoding]::Unicode)
}
function AssertPlain([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $attributes = [IO.File]::GetAttributes($cursor)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Linked folders or files cannot be modified by the Expansion Pack importer.'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if (!$parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
}
function AssertGameClosed {
    if (Get-Process -Name 'tes3mp','openmw','openmw-launcher' -ErrorAction SilentlyContinue) {
        throw 'Close all TES3MP/OpenMW clients before importing the Expansion Pack.'
    }
}
function ReplaceVerified([string]$Source, [string]$Target, [string]$Expected) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target)) | Out-Null
    $temp = $Target + '.tes3np-import-' + [guid]::NewGuid().ToString('N')
    $replaceBackup = $Target + '.tes3np-replaced-' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::Copy($Source, $temp, $false)
        if ((Sha256 $temp) -ne $Expected) { throw 'A staged file did not pass SHA-256 verification.' }
        if ([IO.File]::Exists($Target)) {
            [IO.File]::Replace($temp, $Target, $replaceBackup)
            if (Test-Path -LiteralPath $replaceBackup) { [IO.File]::Delete($replaceBackup) }
        } else { [IO.File]::Move($temp, $Target) }
    } finally {
        if (Test-Path -LiteralPath $temp) { [IO.File]::Delete($temp) }
    }
}
function AllowedAsset([string]$Relative) {
    if ($Relative -ieq 'NP Expansion Pack.esp') { return $true }
    # Server-provided expansion artwork, isolated from unrelated game mods.
    return $Relative -match '^(?i)(Icons|Meshes|Textures)[/]tes3mp_np[/][^:]+$'
}
[IO.Directory]::CreateDirectory($JobFolder) | Out-Null
$backups = @()
$changed = @()
$rollbackReady = $false
try {
    Progress 'Checking Expansion Pack download' 5
    AssertGameClosed
    if (![IO.File]::Exists($Package)) { throw 'Select an existing .zip or NP Expansion Pack.esp file.' }
    if ([IO.Path]::GetFileName($ConfigFile) -ine 'openmw.cfg' -or ![IO.File]::Exists($ConfigFile)) {
        throw 'Select your active OpenMW openmw.cfg before importing.'
    }
    AssertPlain $ConfigFile
    $data = Join-Path $MorrowindFolder 'Data Files'
    AssertPlain $data
    foreach ($master in @('Morrowind.esm','Tribunal.esm','Bloodmoon.esm')) {
        if (![IO.File]::Exists((Join-Path $data $master))) { throw ('Required Morrowind GOTY master missing: ' + $master) }
    }
    $staged = Join-Path $JobFolder 'stage'
    [IO.Directory]::CreateDirectory($staged) | Out-Null
    $assets = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $extension = [IO.Path]::GetExtension($Package).ToLowerInvariant()
    if ($extension -eq '.esp') {
        if ([IO.Path]::GetFileName($Package) -ine 'NP Expansion Pack.esp') {
            throw 'The chosen ESP must be named NP Expansion Pack.esp.'
        }
        if ((Get-Item -LiteralPath $Package).Length -gt 134217728) { throw 'The selected ESP is larger than the allowed 128 MB.' }
        $target = Join-Path $staged 'NP Expansion Pack.esp'
        [IO.File]::Copy($Package, $target, $false)
        $assets = @([pscustomobject]@{Relative='NP Expansion Pack.esp'; Source=$target})
    }
    elseif ($extension -eq '.zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($Package)
        try {
            if ($archive.Entries.Count -gt 10000) { throw 'The ZIP contains too many entries.' }
            $total = [long]0
            foreach ($entry in $archive.Entries) {
                $raw = $entry.FullName
                if ($raw.Contains('\') -or $raw.StartsWith('/') -or $raw.Contains(':')
                    -or $raw -match '(^|/)\.\.(/|$)' -or $raw -match '[\x00-\x1F]' ) {
                    throw 'The ZIP contains an unsafe file path.'
                }
                if ($raw.EndsWith('/')) { continue }
                # Block Unix symlinks even if the archive was made outside Windows.
                if ((($entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) {
                    throw 'ZIP symbolic links are not supported.'
                }
                $relative = ''
                if ($raw -match '(?i)(^|/)Data Files/(.+)$') { $relative = $Matches[2] }
                elseif (AllowedAsset $raw) { $relative = $raw }
                if (!$relative) { continue } # Ignore ZIP readmes and licenses outside Data Files.
                if (!(AllowedAsset $relative)) {
                    throw ('Unexpected file in Expansion Pack Data Files: ' + $relative)
                }
                if (!$seen.Add($relative)) { throw ('Duplicate Expansion Pack asset in ZIP: ' + $relative) }
                if ($entry.Length -gt 134217728) { throw 'One archive entry is larger than 128 MB.' }
                $total += $entry.Length
                if ($total -gt 1073741824) { throw 'Unpacked Expansion Pack exceeds the 1 GB limit.' }
                $target = Join-Path $staged ($relative.Replace('/', '\'))
                AssertPlain $target
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
                $read = $entry.Open()
                try {
                    $write = [IO.File]::Create($target)
                    try { $read.CopyTo($write) } finally { $write.Dispose() }
                } finally { $read.Dispose() }
                if ([IO.File]::GetLength($target) -ne $entry.Length) { throw 'ZIP extraction size did not match its declared size.' }
                $assets += [pscustomobject]@{Relative=$relative; Source=$target}
            }
        } finally { $archive.Dispose() }
    } else { throw 'Only .zip and NP Expansion Pack.esp files are supported.' }
    if (!($assets | Where-Object { $_.Relative -ieq 'NP Expansion Pack.esp' })) {
        throw 'The ZIP is missing NP Expansion Pack.esp in its Data Files.'
    }
    Progress 'Preparing verified game file replacements' 35
    $plan = @()
    foreach ($asset in $assets) {
        $target = Join-Path $data ($asset.Relative.Replace('/', '\'))
        AssertPlain $target
        $plan += [pscustomobject]@{Source=$asset.Source; Target=$target; Hash=(Sha256 $asset.Source)}
    }
    $original = [IO.File]::ReadAllText($ConfigFile)
    if ($original -match '(?m)^\s*config\s*=') { throw 'Nested OpenMW configs are not supported. Select your active user openmw.cfg.' }
    $lines = @($original -split '\r?\n' | Where-Object { $_ -notmatch '^\s*content\s*=\s*"?NP Expansion Pack\.esp"?\s*$' })
    $hasData = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*data\s*=\s*(.+?)\s*$') {
            $current = $Matches[1].Trim('"').Replace('/','\')
            try {
                if ([IO.Path]::GetFullPath($current).TrimEnd('\') -ieq [IO.Path]::GetFullPath($data).TrimEnd('\')) {
                    $hasData = $true
                }
            } catch {}
        }
    }
    if (!$hasData) { $lines += ('data="' + $data.Replace('\','/') + '"') }
    $lines += 'content=NP Expansion Pack.esp'
    $updated = ($lines -join [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
    if ($updated -cne $original) {
        $preparedConfig = Join-Path $JobFolder 'prepared-openmw.cfg'
        [IO.File]::WriteAllText($preparedConfig, $updated, ([Text.UTF8Encoding]::new($false)))
        $plan += [pscustomobject]@{Source=$preparedConfig; Target=$ConfigFile; Hash=(Sha256 $preparedConfig)}
    }
    $needed = @($plan | Where-Object { ![IO.File]::Exists($_.Target) -or (Sha256 $_.Target) -ne $_.Hash })
    if (!$needed.Count) {
        Progress 'Expansion files already match the download' 100
        Result 'success' 'Selected Expansion Pack files are already installed. Try connecting again.' $JobFolder
        exit 0
    }
    Progress 'Backing up existing game files' 45
    $i = 0
    foreach ($item in $needed) {
        $existing = [IO.File]::Exists($item.Target)
        $backup = Join-Path $JobFolder ('backup\' + $i)
        $before = ''
        if ($existing) {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
            $before = Sha256 $item.Target
            [IO.File]::Copy($item.Target, $backup, $false)
            if ((Sha256 $backup) -ne $before) { throw 'Backup verification failed.' }
        }
        $backups += [pscustomobject]@{Target=$item.Target; Existed=$existing; Backup=$backup; OriginalHash=$before; InstalledHash=$item.Hash}
        $i++
    }
    $journal = Join-Path $JobFolder 'journal.json'
    $record = [pscustomobject]@{Completed=$false; Package=$Package; Files=$backups}
    [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json -Depth 5))
    $rollbackReady = $true
    for ($i=0; $i -lt $needed.Count; $i++) {
        AssertGameClosed
        $item = $needed[$i]
        Progress ('Installing ' + [IO.Path]::GetFileName($item.Target)) ([int](50 + 45 * $i / $needed.Count))
        $changed += $backups[$i]
        ReplaceVerified $item.Source $item.Target $item.Hash
    }
    foreach ($item in $plan) {
        if (![IO.File]::Exists($item.Target) -or (Sha256 $item.Target) -ne $item.Hash) {
            throw 'Installed Expansion Pack verification failed.'
        }
    }
    $record.Completed = $true
    [IO.File]::WriteAllText($journal, ($record | ConvertTo-Json -Depth 5))
    Progress 'Expansion import complete' 100
    Result 'success' 'Expansion files installed and backed up. Try joining Nerevarine Prophecies again; only the server can confirm compatibility.' $JobFolder
    exit 0
}
catch {
    $reason = $_.Exception.GetBaseException().Message
    $failedRollback = $false
    if ($rollbackReady) {
        for ($i = $changed.Count - 1; $i -ge 0; $i--) {
            $item = $changed[$i]
            try {
                if ($item.Existed) { ReplaceVerified $item.Backup $item.Target $item.OriginalHash }
                elseif ([IO.File]::Exists($item.Target)) { [IO.File]::Delete($item.Target) }
            } catch { $failedRollback = $true }
        }
    }
    if ($rollbackReady) {
        $reason += $(if ($failedRollback) { ' Rollback was incomplete: retain the import job backup.' } else { ' This import was rolled back.' })
    }
    Progress 'Expansion import failed' 100
    Result 'error' $reason
    exit 1
}