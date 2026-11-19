param([ValidateSet('Enable','Disable')][string]$Action,[string]$MorrowindFolder,[string]$ConfigFile,[string]$BackupFolder,[string]$ResultFile='')
$ErrorActionPreference='Stop'
# This result file is shown by the launcher when the toggle fails.
function CleanToggleError([string]$Message) {
 $safe=[regex]::Replace($Message,'(?i)\b(?:Password|Token|Secret|Authorization|Cookie|Api[-_]?Key|Account|User)\s*[:=][^|\r\n]*','')
 $safe=[regex]::Replace($safe,'(?i)\b(?:https?|wss?)://[^\s|]+','')
 $safe=[regex]::Replace($safe,'(?i)["''](?:[A-Z]:[\\/]|\\\\)[^"'']*["'']','')
 $safe=[regex]::Replace($safe,'(?i)\b[A-Z]:[\\/][^|;\r\n]+','')
 $safe=[regex]::Replace($safe,'(?i)\\\\[^|;\r\n]+','')
 $safe=[regex]::Replace($safe,'(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b','')
 $safe=[regex]::Replace($safe,'\b(?:\d{1,3}\.){3}\d{1,3}\b','')
 $safe=[regex]::Replace($safe,'\b\d{16,21}\b','')
 $user=[Environment]::UserName
 if($user -and $user.Length -ge 3) {
  $safe=[regex]::Replace($safe,'(?i)(?<![\p{L}\p{N}_])'+[regex]::Escape($user)+'(?![\p{L}\p{N}_])','')
 }
 $safe=[regex]::Replace($safe,'[\r\n]+',' ')
 $safe=[regex]::Replace($safe,'\s{2,}',' ').Trim()
 if(!$safe){return 'Expansion Pack toggle could not be completed.'}
 return $safe
}
try{
 # Include preflight in the guarded section so errors always reach the launcher.
 if(Get-Process -Name 'tes3mp','openmw','openmw-launcher' -ErrorAction SilentlyContinue){throw 'Close all game clients before changing the Expansion Pack.'}
 if([IO.Path]::GetFileName($ConfigFile) -ine 'openmw.cfg' -or !(Test-Path -LiteralPath $ConfigFile -PathType Leaf)){throw 'The active user openmw.cfg is missing.'}
 $old=[IO.File]::ReadAllText($ConfigFile)
 if($old -match '(?m)^\s*config\s*='){throw 'Nested OpenMW configurations are not supported by this toggle.'}
 $pattern='^\s*content\s*=\s*"?NP Expansion Pack\.esp"?\s*$'
 $lines=@($old -split '\r?\n' | Where-Object {$_ -notmatch $pattern})
 if($Action -eq 'Enable'){
  $data=Join-Path $MorrowindFolder 'Data Files'
  foreach($master in @('Morrowind.esm','Tribunal.esm','Bloodmoon.esm')){if(!(Test-Path (Join-Path $data $master))){throw ('Missing game master: '+$master)}}
  # Pack contents may be in the base game or a separately configured OpenMW
  # data directory. This action edits load order only; it never copies assets.
  $candidateFolders=@($data)
  foreach ($line in $lines) {
   if ($line -match '^\s*data\s*=\s*(.+?)\s*$') {
    $configured = $matches[1].Trim().Trim('"')
    if ($configured -and [IO.Path]::IsPathRooted($configured)) {
     $candidateFolders += $configured
    }
   }
  }
  $foundInstalled = $false
  foreach ($folder in $candidateFolders) {
   try {
    $esp = Join-Path $folder 'NP Expansion Pack.esp'
    if ((Test-Path -LiteralPath $esp -PathType Leaf) -and
        (Get-Item -LiteralPath $esp).Length -gt 0) {
     $foundInstalled = $true
     break
    }
   } catch {}
  }
  if (!$foundInstalled) {
   throw 'NP Expansion Pack is not installed in the configured OpenMW data folders. Download it from official Discord and import it first.'
  }
  $existsData=$false
  foreach($line in $lines){
   if($line -match '^\s*data\s*=\s*(.+?)\s*$'){
    $v=$matches[1].Trim('"').Replace('/','\')
    try{if([IO.Path]::GetFullPath($v).TrimEnd('\') -ieq [IO.Path]::GetFullPath($data).TrimEnd('\')){$existsData=$true}}catch{}
   }
  }
  if(!$existsData){$lines+=('data="'+$data.Replace('\','/')+'"')}
  $lines+='content=NP Expansion Pack.esp'
 }
 [IO.Directory]::CreateDirectory($BackupFolder)|Out-Null
 $backup=Join-Path $BackupFolder ('openmw-'+[datetime]::UtcNow.ToString('yyyyMMddHHmmssfff')+'.cfg')
 [IO.File]::Copy($ConfigFile,$backup,$false)
 $new=($lines -join [Environment]::NewLine).TrimEnd()+[Environment]::NewLine
 $temp=$ConfigFile+'.tes3np-'+[Guid]::NewGuid().ToString('N')+'.tmp'
 try{
  [IO.File]::WriteAllText($temp,$new,[Text.UTF8Encoding]::new($false))
  # File.Replace requires a valid backup path on Windows; null triggers
  # "The path is not of a legal form." Use our already-created, unique
  # backup file as the replacement backup, retaining rollback protection.
  if ([IO.File]::ReadAllText($ConfigFile) -cne $old) {
   throw 'The OpenMW configuration changed while TES3NP was preparing the toggle. Try again.'
  }
  [IO.File]::Replace($temp,$ConfigFile,$backup)
 }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
 if($ResultFile){[IO.File]::WriteAllText($ResultFile,('Expansion Pack '+$Action+' complete.'),[Text.Encoding]::UTF8)}
 exit 0
}catch{
 if($ResultFile){[IO.File]::WriteAllText($ResultFile,(CleanToggleError $_.Exception.Message),[Text.Encoding]::UTF8)}
 exit 1
}
