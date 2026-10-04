param(
 [Parameter(Mandatory=$true)][string]$InstallDir,[Parameter(Mandatory=$true)][string]$StageDir,[Parameter(Mandatory=$true)][string]$StateFile,[Parameter(Mandatory=$true)][string]$Version,[int]$ParentPid=0,[switch]$TestMode,[ValidateSet('','after-backup','after-install')][string]$FailAt=''
)
$ErrorActionPreference='Stop'
function Set-State([string]$State){$dir=Split-Path -Parent $StateFile;if($dir -and -not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};@('[Update]',"State=$State","Version=$Version","UpdatedUtc=$([DateTime]::UtcNow.ToString('o'))")|Set-Content -LiteralPath $StateFile -Encoding UTF8}
function Get-State{if(-not(Test-Path -LiteralPath $StateFile)){return ''};$line=Get-Content -LiteralPath $StateFile|Where-Object{$_ -like 'State=*'}|Select-Object -First 1;if($line){return $line.Substring(6)};return ''}
function Wait-Parent{if($ParentPid -le 0){return};try{Wait-Process -Id $ParentPid -Timeout 30 -ErrorAction Stop}catch{if(Get-Process -Id $ParentPid -ErrorAction SilentlyContinue){throw 'Launcher did not exit in time.'}}}
function Assert-SafePaths{$install=[IO.Path]::GetFullPath($InstallDir).TrimEnd('\');$stage=[IO.Path]::GetFullPath($StageDir).TrimEnd('\');if(-not(Test-Path -LiteralPath $install -PathType Container)){throw 'Install directory does not exist.'};if(-not(Test-Path -LiteralPath $stage -PathType Container)){throw 'Staged update directory does not exist.'};if($install -eq $stage -or $stage.StartsWith($install+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Staging directory must be outside the live installation.'};if(-not(Get-ChildItem -LiteralPath $stage -Filter tes3np.exe -Recurse -File|Select-Object -First 1)){throw 'Staged launcher is missing.'}}
function Get-PayloadRoot{(Get-ChildItem -LiteralPath $StageDir -Filter tes3np.exe -Recurse -File|Select-Object -First 1).Directory.FullName}
function Copy-DirectoryContents([string]$Source,[string]$Destination){Get-ChildItem -LiteralPath $Source -Force|ForEach-Object{Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force}}
$rollback=Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($InstallDir))) ('.tes3np-rollback-'+$Version)
try{
 Assert-SafePaths;Wait-Parent;Set-State 'PREPARING';if(Test-Path -LiteralPath $rollback){Remove-Item -LiteralPath $rollback -Recurse -Force};New-Item -ItemType Directory -Path $rollback|Out-Null
 Set-State 'BACKING_UP';Copy-DirectoryContents $InstallDir $rollback;Set-State 'BACKED_UP';if($FailAt -eq 'after-backup'){throw 'Injected failure after backup.'}
 $payload=Get-PayloadRoot;Set-State 'INSTALLING';Copy-DirectoryContents $payload $InstallDir;Set-State 'AWAITING_CONFIRMATION';if($FailAt -eq 'after-install'){throw 'Injected failure after install.'}
 if($TestMode){Set-State 'LAUNCHED';exit 0}
 $newExe=Join-Path $InstallDir 'tes3np.exe';if(-not(Test-Path -LiteralPath $newExe)){throw 'Updated launcher is missing after installation.'}
 Start-Process -FilePath $newExe -ArgumentList '--update-confirm',$Version,$StateFile
 $deadline=[DateTime]::UtcNow.AddSeconds(30);while([DateTime]::UtcNow -lt $deadline){if((Get-State) -eq 'CONFIRMED'){Set-State 'SUCCESS';Remove-Item -LiteralPath $rollback -Recurse -Force -ErrorAction SilentlyContinue;exit 0};Start-Sleep -Milliseconds 250}
 throw 'Updated launcher did not confirm successful startup in time.'
}catch{$message=$_.Exception.Message;try{Set-State 'ROLLING_BACK';if(Test-Path -LiteralPath $rollback){Copy-DirectoryContents $rollback $InstallDir;Set-State 'ROLLED_BACK';$oldExe=Join-Path $InstallDir 'tes3np.exe';if(-not $TestMode -and (Test-Path -LiteralPath $oldExe)){Start-Process -FilePath $oldExe}}else{Set-State 'FAILED'}}catch{Set-State 'ROLLBACK_FAILED'};Write-Error $message;exit 1}
