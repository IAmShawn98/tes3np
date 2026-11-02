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

# Retry only temporary Windows sharing/byte-range lock violations (32/33).
# All other failures still fail immediately; repeated locks are reported with
# an operation label, never a machine-specific path or raw file content.
function InvokeLockRetry([scriptblock]$Action, [string]$Operation, [object[]]$Arguments = @()) {
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        # Scripts invoked inside this function have this function's scope,
        # NOT the local scope where the caller created the scriptblock.
        # Explicitly pass every file path on every retry.
        try { return (& $Action @Arguments) }
        catch {
            $cause = $_.Exception.GetBaseException()
            $code = [int]($cause.HResult -band 65535)
            if ($cause -isnot [IO.IOException] -or $code -notin @(32, 33)) { throw }
            if ($attempt -eq 6) {
                throw ("Windows kept a file locked while " + $Operation +
                    " (lock error " + $code + ", six attempts). Close applications or " +
                    "file scanners using the Expansion Pack and try again.")
            }
            Start-Sleep -Milliseconds (@(150, 300, 550, 850, 1300)[$attempt - 1])
        }
    }
}
function Sha256([string]$Path) {
    return (InvokeLockRetry {
        param([string]$filePath)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            $stream = [IO.File]::OpenRead($filePath)
            try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
            finally { $stream.Dispose() }
        } finally { $hasher.Dispose() }
    } ("hashing file during " + $script:ImportActivity) @($Path))
}
function CopyWithRetry([string]$Source, [string]$Target, [string]$Operation) {
    # This helper only targets fresh staging, backup and replacement-temp files.
    # Refuse preexisting targets rather than risking deletion of installed data.
    if ([IO.File]::Exists($Target)) { throw 'Temporary import copy destination already exists.' }
    InvokeLockRetry {
        param([string]$sourcePath, [string]$targetPath)
        try { [IO.File]::Copy($sourcePath, $targetPath, $false) }
        catch {
            # Delete only the disposable destination of a failed copy.
            # Never delete the source or an installed game file.
            if ([IO.File]::Exists($targetPath)) {
                try { [IO.File]::Delete($targetPath) } catch {}
            }
            throw
        }
    } $Operation @($Source, $Target)
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
# Package content has no arbitrary 128 MB/1 GB ceiling. Keep extraction
# bounded by actual free disk space, with a small reserve for metadata.
# Never disable hash checks, archive path validation, or transaction rollback.
function AssertSpace([string]$Destination, [long]$BytesNeeded) {
    if ($BytesNeeded -lt 0) { throw 'Expansion Pack declares an invalid file size.' }
    $rootPath = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Destination))
    try {
        $drive = [IO.DriveInfo]::new($rootPath)
        $free = [long]$drive.AvailableFreeSpace
    } catch {
        throw 'Could not determine available disk space for Expansion Pack installation.'
    }
    $reserve = [long]67108864 # 64 MiB for filesystem metadata/temporary files.
    if ($BytesNeeded -gt $free - $reserve) {
        $requiredGiB = [Math]::Round(([double]$BytesNeeded + $reserve) / 1073741824, 2)
        $freeGiB = [Math]::Round(([double]$free) / 1073741824, 2)
        throw ('Not enough free disk space for Expansion Pack: need approximately ' +
            $requiredGiB + ' GiB on ' + $rootPath + ' (available: ' + $freeGiB + ' GiB).')
    }
}
function ReplaceVerified([string]$Source, [string]$Target, [string]$Expected) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Target)) | Out-Null
    $temp = $Target + '.tes3np-import-' + [guid]::NewGuid().ToString('N')
    try {
        CopyWithRetry $Source $temp ("preparing replacement during " + $script:ImportActivity)
        if ((Sha256 $temp) -ne $Expected) { throw 'A staged file did not pass SHA-256 verification.' }
        if ([IO.File]::Exists($Target)) {
            # The import journal already holds a verified persistent backup.
            # Avoid a redundant .NET File.Replace temporary backup that also
            # has to be deleted while antivirus/indexing may be scanning it.
            InvokeLockRetry {
                param([string]$temporaryPath, [string]$installedPath)
                [IO.File]::Replace($temporaryPath, $installedPath, $null)
            } ("replacing file during " + $script:ImportActivity) @($temp, $Target)
        } else {
            InvokeLockRetry {
                param([string]$temporaryPath, [string]$installedPath)
                [IO.File]::Move($temporaryPath, $installedPath)
            } ("installing new file during " + $script:ImportActivity) @($temp, $Target)
        }
    } finally {
        if ([IO.File]::Exists($temp)) {
            try { [IO.File]::Delete($temp) } catch {}
        }
    }
}
function AllowedAsset([string]$Relative) {
    if ($Relative -ieq 'NP Expansion Pack.esp') { return $true }
    # Server-provided expansion artwork, isolated from unrelated game mods.
    if ($Relative -notmatch '^(Icons|Meshes|Textures)/tes3mp_np/[^:]+$') { return $false }
    $extension = [IO.Path]::GetExtension($Relative).ToLowerInvariant()
    return $extension -in @('.tga','.dds','.nif','.kf','.png','.jpg','.jpeg','.bmp','.wav','.ogg','.mp3','.txt','.xml','.bsa')
}
[IO.Directory]::CreateDirectory($JobFolder) | Out-Null
$backups = @()
$changed = @()
$rollbackReady = $false
$staged = $null
$script:ImportActivity = 'package inspection'
try {
    Progress 'Checking Expansion Pack download' 5
    AssertGameClosed
    if (![IO.File]::Exists($Package) -and ![IO.Directory]::Exists($Package)) {
        throw 'Select an existing Expansion Pack ZIP, ESP or extracted folder.'
    }
    AssertPlain $Package
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
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $extension = [IO.Path]::GetExtension($Package).ToLowerInvariant()
    if ([IO.Directory]::Exists($Package)) {
        # Accept a selected Data Files folder, its parent, or a ZIP wrapper
        # folder that contains Data Files. Use the ZIP allowlist and limits.
        $root = [IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Package))
        $folderPrefix = $root.FullName.TrimEnd('\') + '\'
        $folderIsDataFiles = $root.Name -ieq 'Data Files'
        $total = [long]0
        $entryCount = 0
        foreach ($item in Get-ChildItem -LiteralPath $root.FullName -Recurse -Force -ErrorAction Stop) {
            $entryCount++
            if ($entryCount -gt 10000) { throw 'The extracted Expansion Pack folder contains too many entries.' }
            # Never follow junctions, symbolic links, or reparse-point files.
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Linked files or folders are not supported in an extracted Expansion Pack.'
            }
            if ($item.PSIsContainer) { continue }
            AssertPlain $item.FullName
            if (!$item.FullName.StartsWith($folderPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'An extracted Expansion Pack file is outside the selected folder.'
            }
            $raw = $item.FullName.Substring($folderPrefix.Length).Replace('\','/')
            $relative = ''
            if ($folderIsDataFiles) { $relative = $raw }
            elseif ($raw -match '(?i)(^|/)Data Files/(.+)$') { $relative = $Matches[2] }
            elseif (AllowedAsset $raw) { $relative = $raw }
            if (!$relative) { continue } # Ignore readmes/licenses outside Data Files.
            if (!(AllowedAsset $relative)) {
                throw ('Unexpected file in Expansion Pack Data Files: ' + $relative)
            }
            if (!$seen.Add($relative)) { throw ('Duplicate Expansion Pack asset in folder: ' + $relative) }
            if ($item.Length -lt 0 -or $total -gt ([long]::MaxValue - $item.Length)) {
                throw 'Extracted Expansion Pack has invalid or overflowing file sizes.'
            }
            $total += $item.Length
            AssertSpace $staged ([long]$item.Length)
            $target = Join-Path $staged ($relative.Replace('/', '\'))
            AssertPlain $target
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            $script:ImportActivity = "staging extracted asset $($assets.Count + 1)"
            CopyWithRetry $item.FullName $target ("copying extracted asset " + ($assets.Count + 1))
            if ((Get-Item -LiteralPath $target).Length -ne $item.Length -or (Sha256 $target) -ne (Sha256 $item.FullName)) {
                throw 'A staged Expansion Pack file did not pass verification.'
            }
            $assets += [pscustomobject]@{Relative=$relative; Source=$target}
        }
    }
    elseif ($extension -eq '.esp') {
        if ([IO.Path]::GetFileName($Package) -ine 'NP Expansion Pack.esp') {
            throw 'The chosen ESP must be named NP Expansion Pack.esp.'
        }
        AssertSpace $staged ([long](Get-Item -LiteralPath $Package).Length)
        $target = Join-Path $staged 'NP Expansion Pack.esp'
        $script:ImportActivity = 'staging selected ESP'
        CopyWithRetry $Package $target 'copying selected ESP'
        $assets = @([pscustomobject]@{Relative='NP Expansion Pack.esp'; Source=$target})
    }
    elseif ($extension -eq '.zip') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = InvokeLockRetry {
            param([string]$archivePath)
            [IO.Compression.ZipFile]::OpenRead($archivePath)
        } 'opening downloaded ZIP' @($Package)
        try {
            if ($archive.Entries.Count -gt 10000) { throw 'The ZIP contains too many entries.' }
            $total = [long]0
            foreach ($entry in $archive.Entries) {
                $raw = $entry.FullName
                $unsafePath = $raw.Contains('\') -or $raw.StartsWith('/') -or $raw.Contains(':') -or $raw -match '(^|/)\.\.(/|$)' -or $raw -match '[\x00-\x1F]'
                if ($unsafePath) {
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
                if ($entry.Length -lt 0 -or $total -gt ([long]::MaxValue - $entry.Length)) {
                    throw 'Expansion Pack ZIP has invalid or overflowing file sizes.'
                }
                $total += $entry.Length
                AssertSpace $staged ([long]$entry.Length)
                $script:ImportActivity = "staging ZIP asset $($assets.Count + 1)"
                $target = Join-Path $staged ($relative.Replace('/', '\'))
                AssertPlain $target
                [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
                $read = $entry.Open()
                try {
                    $write = [IO.File]::Create($target)
                    try {
                        $buffer = New-Object byte[] 65536
                        $copied = [long]0
                        while (($count = $read.Read($buffer, 0, $buffer.Length)) -gt 0) {
                            $copied += $count
                            if ($copied -gt $entry.Length) {
                                throw 'Extracted ZIP file exceeded its declared size or safety limit.'
                            }
                            $write.Write($buffer, 0, $count)
                        }
                    } finally { $write.Dispose() }
                } finally { $read.Dispose() }
                if ((Get-Item -LiteralPath $target).Length -ne $entry.Length) { throw 'ZIP extraction size did not match its declared size.' }
                $assets += [pscustomobject]@{Relative=$relative; Source=$target}
            }
        } finally { $archive.Dispose() }
    } else { throw 'Only an extracted folder, .zip, or NP Expansion Pack.esp is supported.' }
    if (!($assets | Where-Object { $_.Relative -ieq 'NP Expansion Pack.esp' })) {
        throw 'The selected package is missing NP Expansion Pack.esp in its Data Files.'
    }
    Progress 'Preparing verified game file replacements' 35
    $plan = @()
    $script:ImportActivity = 'preparing install plan'
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
    $script:ImportActivity = 'checking existing files'
    $needed = @($plan | Where-Object { ![IO.File]::Exists($_.Target) -or (Sha256 $_.Target) -ne $_.Hash })
    if (!$needed.Count) {
        Progress 'Expansion files already match the download' 100
        Result 'success' 'Selected Expansion Pack files are already installed. Try connecting again.' $JobFolder
        exit 0
    }
    Progress 'Backing up existing game files' 45
    $i = 0
    foreach ($item in $needed) {
        $script:ImportActivity = "backing up file $($i + 1) of $($needed.Count)"
        $existing = [IO.File]::Exists($item.Target)
        $backup = Join-Path $JobFolder ('backup\' + $i)
        $before = ''
        if ($existing) {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup)) | Out-Null
            $before = Sha256 $item.Target
            AssertSpace $JobFolder ([long](Get-Item -LiteralPath $item.Target).Length)
            CopyWithRetry $item.Target $backup ("backing up file " + ($i + 1) + " of " + $needed.Count)
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
        $script:ImportActivity = "installing file $($i + 1) of $($needed.Count)"
        Progress ('Installing ' + [IO.Path]::GetFileName($item.Target)) ([int](50 + 45 * $i / $needed.Count))
        AssertSpace $item.Target ([long](Get-Item -LiteralPath $item.Source).Length)
        $changed += $backups[$i]
        ReplaceVerified $item.Source $item.Target $item.Hash
    }
    $script:ImportActivity = 'verifying installed files'
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
            $script:ImportActivity = "rolling back file $($i + 1) of $($changed.Count)"
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
finally {
    # Preserve the job's backup/journal, but do not retain a second full
    # copy of the Expansion Pack in its disposable staging directory.
    if ($staged -and [IO.Directory]::Exists($staged)) {
        try { [IO.Directory]::Delete($staged, $true) }
        catch {
            try {
                [IO.File]::WriteAllText((Join-Path $JobFolder 'stage-cleanup-warning.txt'),
                    'Temporary Expansion Pack staging cleanup was incomplete.',
                    [Text.Encoding]::ASCII)
            } catch {}
        }
    }
}
