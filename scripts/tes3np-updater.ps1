param(
 [Parameter(Mandatory=$true)][string]$InstallDir,[Parameter(Mandatory=$true)][string]$StageDir,[Parameter(Mandatory=$true)][string]$StateFile,[Parameter(Mandatory=$true)][string]$Version,[int]$ParentPid=0,[switch]$TestMode,[ValidateSet('','after-backup','after-install')][string]$FailAt=''
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
        $safe = [regex]::Replace($safe, '(?i)%(?:LOCALAPPDATA|APPDATA|USERPROFILE)%[\\/][^|\r\n]*', '')
        $safe = [regex]::Replace($safe, '(?i)\b(?:https?|wss?)://[^\s|]+', '')
        $safe = [regex]::Replace($safe, '(?i)\b[A-Z]:[\\/][^|\r\n]*', '')
        $safe = [regex]::Replace($safe, '(?i)\\\\[^|\r\n]*', '')
        $safe = [regex]::Replace($safe, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '')
        $safe = [regex]::Replace($safe, '\b(?:\d{1,3}\.){3}\d{1,3}\b', '')
        $safe = [regex]::Replace($safe, '\b\d{16,21}\b', '')
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
function Get-State{if(-not(Test-Path -LiteralPath $StateFile)){return ''};$line=Get-Content -LiteralPath $StateFile|Where-Object{$_ -like 'State=*'}|Select-Object -First 1;if($line){return $line.Substring(6)};return ''}
function Wait-Parent{if($ParentPid -le 0){Write-UpdaterLog 'No parent PID supplied; continuing.';return};Update-Progress 'Waiting for the launcher to close...' 10;Write-UpdaterLog("Waiting for launcher PID $ParentPid to exit.");try{Wait-Process -Id $ParentPid -Timeout 30 -ErrorAction Stop;Write-UpdaterLog 'Original launcher exited.'}catch{if(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue){throw 'Launcher did not exit in time.'};Write-UpdaterLog 'Original launcher was already closed.'}}
function Assert-SafePaths{$install=[IO.Path]::GetFullPath($InstallDir).TrimEnd('\');$stage=[IO.Path]::GetFullPath($StageDir).TrimEnd('\');Write-UpdaterLog("Validating paths. Install=$install | Stage=$stage");if(-not(Test-Path -LiteralPath $install -PathType Container)){throw 'Install directory does not exist.'};if(-not(Test-Path -LiteralPath $stage -PathType Container)){throw 'Staged update directory does not exist.'};if($install -eq $stage -or $stage.StartsWith($install+'\',[StringComparison]::OrdinalIgnoreCase) -or $install.StartsWith($stage+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Staging and installation directories must not contain one another.'};if(-not((Test-Path -LiteralPath (Join-Path $stage 'tes3np.exe') -PathType Leaf) -or (Test-Path -LiteralPath (Join-Path (Join-Path $stage 'tes3np') 'tes3np.exe') -PathType Leaf))){throw 'Staged launcher is missing at an approved package root.'};Write-UpdaterLog 'Safe path validation passed.'}
function Get-PayloadRoot{
    # Accept only the documented ZIP layouts, never an arbitrary nested EXE.
    $direct=Join-Path $StageDir 'tes3np.exe'
    $nested=Join-Path (Join-Path $StageDir 'tes3np') 'tes3np.exe'
    if(Test-Path -LiteralPath $direct -PathType Leaf){
        if(Test-Path -LiteralPath $nested -PathType Leaf){throw 'Ambiguous staged update: two launcher roots.'}
        return [IO.Path]::GetFullPath($StageDir)
    }
    if(Test-Path -LiteralPath $nested -PathType Leaf){return [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($nested))}
    throw 'Staged update does not have a launcher at the expected package root.'
}
function Assert-CompletePayload([string]$Root){
    # Validate before backing up or writing anything to the live install.
    $required=@(
        'tes3np.exe',
        'client\tes3mp.exe',
        'client\tes3mp-client-default.cfg',
        'client\defaults.bin',
        'client\openmw.cfg',
        'chat-host\tes3np.ChatHost.exe',
        'chat-host\chat.ini',
        'chat-host\chat.css',
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
function Copy-DirectoryContents([string]$Source,[string]$Destination){
    Write-UpdaterLog("Copying files. Source=$Source | Destination=$Destination")
    Get-ChildItem -LiteralPath $Source -Force|ForEach-Object{
        $entry=$_
        if($entry.PSIsContainer -and $entry.Name -ieq 'chat-host'){
            $chatTarget=Join-Path $Destination $entry.Name
            if(-not(Test-Path -LiteralPath $chatTarget)){New-Item -ItemType Directory -Path $chatTarget -Force|Out-Null}
            Get-ChildItem -LiteralPath $entry.FullName -Force|ForEach-Object{
                $target=Join-Path $chatTarget $_.Name
                if($_.Name -in @('chat.ini','chat.css') -and (Test-Path -LiteralPath $target)){
                    Write-UpdaterLog("Preserving existing user-editable chat configuration: $($_.Name)")
                }else{
                    Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
                }
            }
        }else{
            Copy-Item -LiteralPath $entry.FullName -Destination $Destination -Recurse -Force
        }
    }
    Write-UpdaterLog 'File copy completed.'
}
function Stop-LaunchedProcessForRollback($Process){if(-not $Process -or $Process.HasExited){return};Write-UpdaterLog("Stopping updated launcher PID $($Process.Id) before rollback.");try{Stop-Process -Id $Process.Id -Force -ErrorAction Stop;Wait-Process -Id $Process.Id -Timeout 10 -ErrorAction SilentlyContinue}catch{Write-UpdaterLog("Could not stop updated launcher cleanly: $($_.Exception.Message)")};if(Get-Process -Id $Process.Id -ErrorAction SilentlyContinue){throw 'Updated launcher is still running; rollback cannot safely continue.'};Write-UpdaterLog 'Updated launcher stopped; rollback may proceed.'}
function Restore-Rollback([string]$Backup,[string]$Destination,[string]$Payload){
    # Restore backed-up files without deleting unmanaged user files. Remove
    # only new files introduced by this update; do not wipe the install tree.
    if($Payload -and (Test-Path -LiteralPath $Payload -PathType Container)){
        foreach($file in (Get-ChildItem -LiteralPath $Payload -Recurse -File -Force)){
            $relative=$file.FullName.Substring($Payload.TrimEnd('\\').Length).TrimStart('\\')
            $previous=Join-Path $Backup $relative
            if(-not(Test-Path -LiteralPath $previous -PathType Leaf)){
                $installed=Join-Path $Destination $relative
                if(Test-Path -LiteralPath $installed -PathType Leaf){
                    Remove-Item -LiteralPath $installed -Force
                }
            }
        }
    }
    Copy-DirectoryContents $Backup $Destination
    Write-UpdaterLog 'Rollback restored existing files and preserved unrelated files.'
}
$rollback=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($InstallDir))) ('.tes3np-rollback-'+$Version)
$launched=$null
$backupCompleted=$false
$installStarted=$false
$payload=$null
Write-UpdaterLog("START | Transactional updater started for v$Version. ParentPid=$ParentPid")
try{
 Show-ProgressWindow;Update-Progress 'Preparing update...' 5;Assert-SafePaths;$payload=Get-PayloadRoot;Assert-CompletePayload $payload;Wait-Parent;Set-State 'PREPARING';if(Test-Path -LiteralPath $rollback){Write-UpdaterLog 'Removing previous rollback directory.';Remove-Item -LiteralPath $rollback -Recurse -Force};New-Item -ItemType Directory -Path $rollback|Out-Null;Write-UpdaterLog("Rollback directory created: $rollback")
 Update-Progress 'Backing up your current version...' 25;Set-State 'BACKING_UP';Copy-DirectoryContents $InstallDir $rollback;$backupCompleted=$true;Set-State 'BACKED_UP';Write-UpdaterLog 'Current installation backup completed.';if($FailAt -eq 'after-backup'){throw 'Injected failure after backup.'}
 Write-UpdaterLog("Payload root resolved: $payload");Update-Progress 'Installing the update...' 55;Set-State 'INSTALLING';$installStarted=$true;Copy-DirectoryContents $payload $InstallDir;Set-State 'AWAITING_CONFIRMATION';Write-UpdaterLog 'New files installed; awaiting launcher confirmation.';if($FailAt -eq 'after-install'){throw 'Injected failure after install.'}
 if($TestMode){Set-State 'LAUNCHED';Write-UpdaterLog 'Test mode complete.';exit 0}
 $newExe=Join-Path $InstallDir 'tes3np.exe';if(-not(Test-Path -LiteralPath $newExe)){throw 'Updated launcher is missing after installation.'}
 Update-Progress 'Starting the updated launcher...' 80;Write-UpdaterLog("Launching updated executable: $newExe --update-confirm $Version <state-file>")
 $launched=Start-Process -FilePath $newExe -ArgumentList '--update-confirm',$Version,$StateFile -PassThru
 Write-UpdaterLog("Updated launcher process started. PID=$($launched.Id)");Update-Progress 'Finishing up...' 90
 $deadline=[DateTime]::UtcNow.AddSeconds(30);while([DateTime]::UtcNow -lt $deadline){$current=Get-State;if($current -eq 'CONFIRMED'){Write-UpdaterLog 'Updated launcher confirmed successful startup.';Update-Progress 'Update complete!' 100;Set-State 'SUCCESS';Remove-Item -LiteralPath $rollback -Recurse -Force -ErrorAction SilentlyContinue;Write-UpdaterLog 'SUCCESS | Rollback backup removed; update transaction complete.';Start-Sleep -Milliseconds 700;Close-ProgressWindow;exit 0};if($launched.HasExited){Write-UpdaterLog("Updated launcher exited before confirmation. ExitCode=$($launched.ExitCode)");break};[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 250}
 throw 'Updated launcher did not confirm successful startup in time.'
}catch{$message=$_.Exception.Message;Write-UpdaterLog("ERROR | $message");try{Update-Progress 'The update could not finish. Restoring your previous version...' 70;Set-State 'ROLLING_BACK';if((Test-Path -LiteralPath $rollback) -and $backupCompleted){Write-UpdaterLog 'Restoring previous installation from rollback backup.';Stop-LaunchedProcessForRollback $launched;if($installStarted){Restore-Rollback $rollback $InstallDir $payload};Set-State 'ROLLED_BACK';Write-UpdaterLog 'Rollback completed.';Update-Progress 'Previous version restored. Restarting tes3np...' 95;$oldExe=Join-Path $InstallDir 'tes3np.exe';if(-not $TestMode -and (Test-Path -LiteralPath $oldExe)){Write-UpdaterLog 'Relaunching restored launcher.';Start-Process -FilePath $oldExe;Start-Sleep -Milliseconds 700}}else{Set-State 'FAILED';Write-UpdaterLog 'Rollback backup was unavailable.'}}catch{Write-UpdaterLog("ROLLBACK ERROR | $($_.Exception.Message)");Set-State 'ROLLBACK_FAILED'};Close-ProgressWindow;Write-Error $message;exit 1}
finally{Close-ProgressWindow}
