param(
    [Parameter(Mandatory=$true)][string]$InstallDir,
    [string]$StageDir,
    [string]$StateFile,
    [Parameter(Mandatory=$true)][string]$Version,
    [int]$ParentPid = 0,
    [switch]$ManagedStage,
    [switch]$RecoverOnly,
    [switch]$TestMode,
    [ValidateSet('', 'after-backup', 'after-install')][string]$FailAt = ''
)
$ErrorActionPreference='Stop'
$LogFile=Join-Path $env:APPDATA 'tes3np\launcher.log'
$ProgressForm=$null;$ProgressStatus=$null;$ProgressBar=$null
function Write-UpdaterLog([string]$Message) {
    try {
        # A standalone worker must remove sensitive fields before writing the
        # shared launcher log. Preserve useful update and rollback milestones.
        $safe = [regex]::Replace($Message, '(?i)\[(?:credential|user|identity|secret|url|path|network path|email|IP|identifier|Discord ID) omitted\]', '')
        $safe = [regex]::Replace($safe, '(?i)\b(?:Account|User|Windows\s+User(?:name)?|Password|Token|Secret|Authorization|Cookie|Api[-_]?Key)\s*[:=][^|\r\n]*', '')
        $safe = [regex]::Replace($safe, '(?i)%(?:LOCALAPPDATA|APPDATA|USERPROFILE)%(?:[\\/][^|\r\n]*)?', '')
        $safe = [regex]::Replace($safe, '(?i)\b(?:https?|wss?)://[^\s|]+', '')
        $safe = [regex]::Replace($safe, '(?i)\b[A-Z]:[\\/][^|\r\n]*', '')
        $safe = [regex]::Replace($safe, '(?i)\\\\[^|\r\n]*', '')
        $safe = [regex]::Replace($safe, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '')
        $safe = [regex]::Replace($safe, '\b(?:\d{1,3}\.){3}\d{1,3}\b', '')
        $safe = [regex]::Replace($safe, '\b\d{16,21}\b', '')
        $windowsUser = [Environment]::UserName
        if($windowsUser -and $windowsUser.Length -ge 3) {
            $safe = [regex]::Replace($safe, '(?i)(?<![\p{L}\p{N}_])' + [regex]::Escape($windowsUser) + '(?![\p{L}\p{N}_])', '')
        }
        $safe = [regex]::Replace($safe, '[\r\n]+', ' ')
        $parts = [Collections.Generic.List[string]]::new()
        foreach ($piece in ($safe -split '\|')) {
            $item = [regex]::Replace($piece, '(?i)\b(?:Executable(?:\s+path)?|Source\s+path|Destination|Install|Stage|Path|Folder|File|URL|Mail|Email)\s*[:=]\s*$', '')
            $item = $item.Trim([char[]]@(' ', [char]9, ':', '='))
            if(-not [string]::IsNullOrWhiteSpace($item)) { [void]$parts.Add($item) }
        }
        $safe = [string]::Join(' | ', $parts)
        if(-not $safe) { return }
        $dir = Split-Path -Parent $LogFile
        if($dir -and -not(Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value (
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' | UPDATE WORKER | ' + $safe
        ) -Encoding UTF8
    } catch {
        # Never interrupt update/rollback when diagnostics are unavailable.
    }
}
function Show-ProgressWindow{if($TestMode){return};Add-Type -AssemblyName System.Windows.Forms;Add-Type -AssemblyName System.Drawing;$script:ProgressForm=New-Object Windows.Forms.Form;$ProgressForm.Text='tes3np — Updating';$ProgressForm.StartPosition='CenterScreen';$ProgressForm.FormBorderStyle='FixedDialog';$ProgressForm.MaximizeBox=$false;$ProgressForm.MinimizeBox=$false;$ProgressForm.ControlBox=$false;$ProgressForm.TopMost=$true;$ProgressForm.ClientSize=New-Object Drawing.Size(430,170);$title=New-Object Windows.Forms.Label;$title.Text='Updating tes3np...';$title.Font=New-Object Drawing.Font('Segoe UI',14,[Drawing.FontStyle]::Bold);$title.AutoSize=$true;$title.Location=New-Object Drawing.Point(24,20);$ProgressForm.Controls.Add($title);$message=New-Object Windows.Forms.Label;$message.Text="Installing v$Version. The launcher will restart automatically when finished.`r`nPlease don't reopen tes3np manually.";$message.Font=New-Object Drawing.Font('Segoe UI',9);$message.AutoSize=$true;$message.Location=New-Object Drawing.Point(26,55);$ProgressForm.Controls.Add($message);$script:ProgressStatus=New-Object Windows.Forms.Label;$ProgressStatus.Text='Preparing update...';$ProgressStatus.Font=New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold);$ProgressStatus.AutoSize=$true;$ProgressStatus.Location=New-Object Drawing.Point(26,104);$ProgressForm.Controls.Add($ProgressStatus);$script:ProgressBar=New-Object Windows.Forms.ProgressBar;$ProgressBar.Location=New-Object Drawing.Point(28,130);$ProgressBar.Size=New-Object Drawing.Size(374,18);$ProgressBar.Minimum=0;$ProgressBar.Maximum=100;$ProgressBar.Value=5;$ProgressForm.Controls.Add($ProgressBar);$ProgressForm.Show();[Windows.Forms.Application]::DoEvents()}
function Update-Progress([string]$Text,[int]$Percent){if($TestMode -or -not $ProgressForm){return};$ProgressStatus.Text=$Text;$ProgressBar.Value=[Math]::Max(0,[Math]::Min(100,$Percent));[Windows.Forms.Application]::DoEvents()}
function Close-ProgressWindow{if($ProgressForm){try{$ProgressForm.Close();$ProgressForm.Dispose()}catch{};$script:ProgressForm=$null}}
function Set-State([string]$State){$dir=Split-Path -Parent $StateFile;if($dir -and -not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};@('[Update]',"State=$State","Version=$Version","UpdatedUtc=$([DateTime]::UtcNow.ToString('o'))")|Set-Content -LiteralPath $StateFile -Encoding UTF8;Write-UpdaterLog("STATE | $State")}
function Test-LauncherConfirmation {
    try {
        $lines = Get-Content -LiteralPath $StateFile -Encoding UTF8 -ErrorAction Stop
        return ($lines -contains 'State=CONFIRMED') -and ($lines -contains "Version=$Version")
    } catch {
        # The launcher or a scanner may briefly hold the state file open.
        # The startup deadline still bounds retries if it stays unavailable.
        return $false
    }
}
function Wait-Parent{if($ParentPid -le 0){Write-UpdaterLog 'No parent PID supplied; continuing.';return};Update-Progress 'Waiting for the launcher to close...' 10;Write-UpdaterLog("Waiting for launcher PID $ParentPid to exit.");try{Wait-Process -Id $ParentPid -Timeout 30 -ErrorAction Stop;Write-UpdaterLog 'Original launcher exited.'}catch{if(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue){throw 'Launcher did not exit in time.'};Write-UpdaterLog 'Original launcher was already closed.'}}
function Assert-SafePaths {
    $separator = [IO.Path]::DirectorySeparatorChar
    $install = [IO.Path]::GetFullPath($InstallDir).TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) { throw 'Install directory does not exist.' }
    if ((Get-Item -LiteralPath $InstallDir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The installation directory is a linked folder.'
    }
    if ($RecoverOnly) { return }

    $stage = [IO.Path]::GetFullPath($StageDir).TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar)
    Write-UpdaterLog("Validating paths. Install=$install | Stage=$stage")
    if (-not (Test-Path -LiteralPath $StageDir -PathType Container)) { throw 'Staged update directory does not exist.' }
    if (!$StateFile) { throw 'Update state file was not supplied.' }
    if ($install -eq $stage -or
        $stage.StartsWith($install + $separator, [StringComparison]::OrdinalIgnoreCase) -or
        $install.StartsWith($stage + $separator, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Staging and installation directories must not contain one another.'
    }
    Write-UpdaterLog 'Safe path validation passed.'
}
function Get-PayloadRoot{
    # Accept only the documented ZIP layouts, never an arbitrary nested EXE.
    $direct=Join-Path $StageDir 'tes3np.exe'
    $nested=Join-Path (Join-Path $StageDir 'tes3np') 'tes3np.exe'
    if(Test-Path -LiteralPath $direct -PathType Leaf){
        if(Test-Path -LiteralPath $nested -PathType Leaf){throw 'Ambiguous staged update: two launcher roots.'}
        return [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($direct))
    }
    if(Test-Path -LiteralPath $nested -PathType Leaf){return [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($nested))}
    throw 'Staged update does not have a launcher at the expected package root.'
}
function Assert-CompletePayload([string]$Root){
    # Validate before backing up or writing anything to the live install.
    $required=@(
        'tes3np.exe',
        'runtime\AutoHotkey64.exe',
        'RELEASE_NOTES.md',
        'client\tes3mp.exe',
        'client\tes3mp-client-default.cfg',
        'client\defaults.bin',
        'client\openmw.cfg',
        'chat-host\tes3np.ChatHost.exe',
        'chat-host\chat.ini',
        'chat-host\chat.css',
        'chat-host\assets\DiscordInt.png',
        'licenses\TES3MP\LICENSE',
        'licenses\TES3MP\REDISTRIBUTION-NOTICE.txt'
    )
    foreach($relative in $required){
        $file=Join-Path $Root $relative
        if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Incomplete staged update; missing $relative"}
        if((Get-Item -LiteralPath $file).Length -le 0){throw "Incomplete staged update; empty $relative"}
    }
    foreach($folder in @($StageDir,$Root)){
        $folderEntry=Get-Item -LiteralPath $folder -Force
        if(($folderEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw "Staged update directory is a reparse point: $folder"
        }
    }
    # Inspect each directory before descending: do not follow junctions or
    # symbolic links, even when they point outside the staging directory.
    $pending=New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Root)
    while($pending.Count -gt 0){
        $current=$pending.Pop()
        foreach($entry in (Get-ChildItem -LiteralPath $current -Force)){
            if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw "Staged update contains a reparse point: $($entry.FullName)"
            }
            if($entry.PSIsContainer){$pending.Push($entry.FullName)}
        }
    }
    Write-UpdaterLog 'Required staged update payload files verified before installation.'
}
function Copy-DirectoryContents([string]$Source, [string]$Destination, [string]$PreserveChatSettingsIn = '') {
    Write-UpdaterLog("Copying files. Source=$Source | Destination=$Destination")
    $entries = Get-ChildItem -LiteralPath $Source -Force | Sort-Object { $_.Name -ieq 'tes3np.exe' }
    foreach ($entry in $entries) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Updater cannot copy a linked file or folder.'
        }
        $target = Join-Path $Destination $entry.Name
        $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Updater cannot replace a linked file or folder.'
        }
        if ($entry.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $target -PathType Container)) {
                [IO.Directory]::CreateDirectory($target) | Out-Null
            }
            Copy-DirectoryContents $entry.FullName $target $PreserveChatSettingsIn
        } elseif ($Source -ieq $PreserveChatSettingsIn -and $entry.Name -in @('chat.ini', 'chat.css') -and
                  (Test-Path -LiteralPath $target -PathType Leaf)) {
            Write-UpdaterLog("Preserving existing user-editable chat configuration: $($entry.Name)")
        } else {
            if (Test-Path -LiteralPath $target -PathType Container) {
                throw "Cannot install file over an existing directory: $($entry.Name)"
            }
            if ($entry.Name -ieq 'tes3np.exe' -and (Test-Path -LiteralPath $target -PathType Leaf)) {
                # Leave a launchable EXE on disk if the worker stops during the copy.
                $replacement = Join-Path $transaction 'launcher-replacement.exe'
                Copy-Item -LiteralPath $entry.FullName -Destination $replacement -Force
                [IO.File]::Replace($replacement, $target, [NullString]::Value)
            } else {
                Copy-Item -LiteralPath $entry.FullName -Destination $target -Force
            }
        }
    }
}
function Stop-LaunchedProcessForRollback($Process) {
    if (!$Process -or $Process.HasExited) { return }
    Write-UpdaterLog("Stopping updated launcher PID $($Process.Id) before rollback.")
    try { $Process.Kill() } catch {
        if (!$Process.HasExited) { throw }
    }
    if (!$Process.WaitForExit(10000)) {
        throw 'Updated launcher is still running; rollback cannot safely continue.'
    }
    Write-UpdaterLog 'Updated launcher stopped; rollback may proceed.'
}
function Restore-Rollback([string]$Backup, [string]$Destination, [string]$Journal) {
    foreach ($path in @($Backup, $Journal)) {
        $entry = Get-Item -LiteralPath $path -Force
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Update recovery contains a linked path.'
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Backup 'tes3np.exe') -PathType Leaf)) {
        throw 'The previous launcher backup is missing.'
    }
    $newFiles = @(Get-Content -LiteralPath $Journal -Encoding UTF8)
    foreach ($relative in $newFiles) {
        if (!$relative -or [IO.Path]::IsPathRooted($relative) -or
            $relative.Contains(':') -or $relative -match '(^|[\\/])\.\.([\\/]|$)') {
            throw 'Invalid path in the update rollback journal.'
        }
    }
    foreach ($relative in $newFiles) {
        $installed = Join-Path $Destination $relative
        if (Test-Path -LiteralPath $installed -PathType Leaf) {
            Remove-Item -LiteralPath $installed -Force
        }
    }
    Copy-DirectoryContents $Backup $Destination
    Write-UpdaterLog 'Rollback restored existing files and preserved unrelated files.'
}

$transaction = $null
$journal = $null
$ownerMarker = $null
$rollback = $null
$installLock = $null
$ownsInstall = $false
$mayWriteState = $false
$ownsRecoveryDirectory = $false
$managedRoot = $null
$launched = $null
$backupCompleted = $false
$installStarted = $false
$payload = $null
Write-UpdaterLog("START | Transactional updater started for v$Version. ParentPid=$ParentPid")
try {
    Show-ProgressWindow
    Update-Progress 'Preparing update...' 5
    Assert-SafePaths
    $installPath = [IO.Path]::GetFullPath($InstallDir).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $installParent = [IO.Path]::GetDirectoryName($installPath)
    if (-not $installParent) { throw 'Install the launcher in its own directory before updating.' }
    $digest = [Security.Cryptography.SHA256]::Create()
    try {
        $installKey = [BitConverter]::ToString($digest.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($installPath.ToUpperInvariant()))).Replace('-', '')
    } finally { $digest.Dispose() }
    $installLock = New-Object Threading.Mutex($false, "tes3np-update-$installKey")
    try {
        $ownsInstall = $installLock.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        $ownsInstall = $true
    }
    if (!$ownsInstall) { throw 'Another update is active for this installation.' }

    if ($ManagedStage) {
        $root = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($StateFile))
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) 'tes3np-update'
        if ((Split-Path -Leaf $root) -notmatch '^[0-9a-f]{32}$' -or
            [IO.Path]::GetDirectoryName($root) -ine $tempRoot -or
            [IO.Path]::GetFileName($StateFile) -ine 'update-state.ini' -or
            [IO.Path]::GetFullPath($StageDir) -ine (Join-Path $root 'staged') -or
            ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Invalid managed update staging directory.'
        }
        $managedRoot = $root
    }
    $mayWriteState = !$RecoverOnly
    $transaction = $installPath + '.tes3np-recovery'
    $rollback = Join-Path $transaction 'backup'
    $journal = Join-Path $transaction 'pending.txt'
    $ownerMarker = Join-Path $transaction 'owner.txt'
    $existingTransaction = Get-Item -LiteralPath $transaction -Force -ErrorAction SilentlyContinue
    if ($existingTransaction) {
        $marker = Get-Item -LiteralPath $ownerMarker -Force -ErrorAction SilentlyContinue
        if (!$existingTransaction.PSIsContainer -or
            ($existingTransaction.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            !$marker -or $marker.PSIsContainer -or
            ($marker.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            [IO.File]::ReadAllText($ownerMarker) -cne $installKey) {
            throw 'Existing recovery path does not belong to this installation.'
        }
    }

    Wait-Parent
    $ownsRecoveryDirectory = $true
    if (Test-Path -LiteralPath $journal -PathType Leaf) {
        Restore-Rollback $rollback $InstallDir $journal
        Remove-Item -LiteralPath $journal -Force
    }
    if (Test-Path -LiteralPath $rollback -PathType Container) {
        Remove-Item -LiteralPath $rollback -Recurse -Force
    }
    if (Test-Path -LiteralPath ($journal + '.tmp') -PathType Leaf) {
        Remove-Item -LiteralPath ($journal + '.tmp') -Force
    }

    if ($RecoverOnly) {
        if (!$TestMode) {
            $restoredLauncher = Join-Path $InstallDir 'tes3np.exe'
            Start-Process -FilePath $restoredLauncher -WorkingDirectory $InstallDir
        }
        exit 0
    }
    $payload = Get-PayloadRoot
    Assert-CompletePayload $payload
    Set-State 'PREPARING'
    [IO.Directory]::CreateDirectory($transaction) | Out-Null
    [IO.File]::WriteAllText($ownerMarker, $installKey)
    [IO.Directory]::CreateDirectory($rollback) | Out-Null
    Write-UpdaterLog("Rollback directory created: $rollback")

    Update-Progress 'Backing up your current version...' 25
    Set-State 'BACKING_UP'
    Copy-DirectoryContents $InstallDir $rollback
    $backupCompleted = $true
    Set-State 'BACKED_UP'
    Write-UpdaterLog 'Current installation backup completed.'
    if ($FailAt -eq 'after-backup') { throw 'Injected failure after backup.' }

    Update-Progress 'Installing the update...' 55
    Set-State 'INSTALLING'
    $newFiles = foreach ($file in (Get-ChildItem -LiteralPath $payload -Recurse -File -Force)) {
        $relative = $file.FullName.Substring($payload.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath (Join-Path $rollback $relative))) { $relative }
    }
    [IO.File]::WriteAllLines($journal + '.tmp', [string[]]@($newFiles | Where-Object { $_ }))
    [IO.File]::Move($journal + '.tmp', $journal)
    $installStarted = $true
    Copy-DirectoryContents $payload $InstallDir (Join-Path $payload 'chat-host')
    Set-State 'AWAITING_CONFIRMATION'
    Write-UpdaterLog 'New files installed; awaiting launcher confirmation.'
    if ($FailAt -eq 'after-install') { throw 'Injected failure after install.' }

    if ($TestMode) {
        Remove-Item -LiteralPath $journal -Force
        Set-State 'LAUNCHED'
        Write-UpdaterLog 'Test mode complete.'
        exit 0
    }

    $newExe = Join-Path $InstallDir 'tes3np.exe'
    if (-not (Test-Path -LiteralPath $newExe -PathType Leaf)) {
        throw 'Updated launcher is missing after installation.'
    }
    Update-Progress 'Starting the updated launcher...' 80
    $launched = Start-Process -FilePath $newExe -ArgumentList @('--update-confirm', $Version, ('"' + $StateFile + '"')) -WorkingDirectory $InstallDir -PassThru
    Write-UpdaterLog("Updated launcher process started. PID=$($launched.Id)")
    Update-Progress 'Finishing up...' 90

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-LauncherConfirmation) {
            Remove-Item -LiteralPath $journal -Force
            try { Set-State 'SUCCESS' } catch { Write-UpdaterLog 'Could not record successful update state.' }
            Write-UpdaterLog 'SUCCESS | Updated launcher confirmed startup.'
            try { Update-Progress 'Update complete!' 100 } catch {}
            Start-Sleep -Milliseconds 700
            exit 0
        }
        if ($launched.HasExited) {
            Write-UpdaterLog("Updated launcher exited before startup completed. ExitCode=$($launched.ExitCode)")
            break
        }
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 250
    }
    throw 'Updated launcher did not confirm successful startup in time.'
} catch {
    Write-UpdaterLog("ERROR | $($_.Exception.Message)")
    if (!$mayWriteState) {
        if ($RecoverOnly -and !$TestMode -and $ownsInstall) {
            [Windows.Forms.MessageBox]::Show(
                'TES3NP could not restore the previous version. Review launcher.log for details.',
                'tes3np Recovery') | Out-Null
        }
        throw
    }
    try {
        Update-Progress 'The update could not finish. Restoring your previous version...' 70
        try { Set-State 'ROLLING_BACK' } catch { Write-UpdaterLog 'Could not record rollback start.' }
        if ($backupCompleted -and (Test-Path -LiteralPath $rollback)) {
            Stop-LaunchedProcessForRollback $launched
            if ($installStarted) {
                Restore-Rollback $rollback $InstallDir $journal
                Remove-Item -LiteralPath $journal -Force
            }
            try { Set-State 'ROLLED_BACK' } catch { Write-UpdaterLog 'Could not record completed rollback state.' }
            Write-UpdaterLog 'Rollback completed.'
            Update-Progress 'Previous version restored. Restarting tes3np...' 95
            $oldExe = Join-Path $InstallDir 'tes3np.exe'
            if (-not $TestMode -and (Test-Path -LiteralPath $oldExe -PathType Leaf)) {
                Start-Process -FilePath $oldExe -WorkingDirectory $InstallDir
                Start-Sleep -Milliseconds 700
            }
        } else {
            Set-State 'FAILED'
            Write-UpdaterLog 'Rollback backup was unavailable.'
        }
    } catch {
        Write-UpdaterLog("ROLLBACK ERROR | $($_.Exception.Message)")
        Set-State 'ROLLBACK_FAILED'
    }
    Write-Error 'TES3NP update failed. Review launcher.log for the cleaned error details.'
    exit 1
} finally {
    Close-ProgressWindow
    if ($ownsInstall) {
        if ($ownsRecoveryDirectory -and (Test-Path -LiteralPath $transaction -PathType Container) -and
            !(Test-Path -LiteralPath $journal)) {
            Remove-Item -LiteralPath $transaction -Recurse -Force -ErrorAction SilentlyContinue
        }
        $installLock.ReleaseMutex()
    }
    if ($installLock) { $installLock.Dispose() }
    if ($launched) { $launched.Dispose() }
    if ($managedRoot) {
        Remove-Item -LiteralPath (Join-Path $managedRoot 'staged') -Recurse -Force -ErrorAction SilentlyContinue
    }
}
