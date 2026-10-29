param([ValidateSet('Enable','Disable')][string]$Action,[string]$MorrowindFolder,[string]$ConfigFile,[string]$PayloadFolder,[string]$BackupFolder,[string]$ResultFile='')
$ErrorActionPreference='Stop'
$planned=@()
$copied=@()
try{
 # Include preflight in the guarded section so errors always reach the launcher.
 if(Get-Process -Name 'tes3mp','openmw','openmw-launcher' -ErrorAction SilentlyContinue){throw 'Close all game clients before changing the Expansion Pack.'}
 if([IO.Path]::GetFileName($ConfigFile) -ine 'openmw.cfg' -or !(Test-Path -LiteralPath $ConfigFile -PathType Leaf)){throw 'The active user openmw.cfg is missing.'}
 $old=[IO.File]::ReadAllText($ConfigFile)
 if($old -match '(?m)^\s*config\s*='){throw 'Nested OpenMW configurations are not supported by this toggle.'}
 $pattern='^\s*content\s*=\s*"?NP Expansion Pack\.esp"?\s*
 if($Action -eq 'Enable'){
  $data=Join-Path $MorrowindFolder 'Data Files'
  foreach($master in @('Morrowind.esm','Tribunal.esm','Bloodmoon.esm')){if(!(Test-Path (Join-Path $data $master))){throw ('Missing game master: '+$master)}}
  $manifest=Get-Content -LiteralPath (Join-Path $PayloadFolder 'manifest.json') -Raw | ConvertFrom-Json
  $entries=@($manifest.Files | Where-Object {$_.Path -like 'expansion-pack/Data Files/*'})
  if(!$entries.Count){throw 'No bundled Expansion Pack assets found.'}
  foreach($entry in $entries){
   $rel=$entry.Path.Substring('expansion-pack/Data Files/'.Length)
   if($rel -match '(^|[/\\])\.\.([/\\]|$)' -or [IO.Path]::IsPathRooted($rel)){throw 'Unsafe asset path.'}
   $src=Join-Path $PayloadFolder ($entry.Path.Replace('/','\'))
   $dst=Join-Path $data ($rel.Replace('/','\'))
   if(!(Test-Path -LiteralPath $src -PathType Leaf) -or (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -ine $entry.SHA256){throw ('Damaged bundled asset: '+$rel)}
   if(Test-Path -LiteralPath $dst -PathType Leaf){
    if((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -ine $entry.SHA256){throw ('Existing modified asset requires manual review: '+$rel)}
   } else {$planned+=@{Source=$src;Target=$dst}}
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
 foreach($item in $planned){
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Target))|Out-Null
  [IO.File]::Copy($item.Source,$item.Target,$false)
  $copied+=$item.Target
 }
 $new=($lines -join [Environment]::NewLine).TrimEnd()+[Environment]::NewLine
 $temp=$ConfigFile+'.tes3np-pending'
 try{
  [IO.File]::WriteAllText($temp,$new,[Text.UTF8Encoding]::new($false))
  # File.Replace requires a valid backup path on Windows; null triggers
  # "The path is not of a legal form." Use our already-created, unique
  # backup file as the replacement backup, retaining rollback protection.
  [IO.File]::Replace($temp,$ConfigFile,$backup)
 }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
 if($ResultFile){[IO.File]::WriteAllText($ResultFile,('Expansion Pack '+$Action+' complete.'),[Text.Encoding]::UTF8)}
 exit 0
}catch{
 foreach($f in $copied){if(Test-Path -LiteralPath $f){Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}}
 if($ResultFile){[IO.File]::WriteAllText($ResultFile,$_.Exception.Message,[Text.Encoding]::UTF8)}
 exit 1
}

 $lines=@($old -split '\r?\n' | Where-Object {$_ -notmatch $pattern})
 if($Action -eq 'Enable'){
  $data=Join-Path $MorrowindFolder 'Data Files'
  foreach($master in @('Morrowind.esm','Tribunal.esm','Bloodmoon.esm')){if(!(Test-Path (Join-Path $data $master))){throw ('Missing game master: '+$master)}}
  $manifest=Get-Content -LiteralPath (Join-Path $PayloadFolder 'manifest.json') -Raw | ConvertFrom-Json
  $entries=@($manifest.Files | Where-Object {$_.Path -like 'expansion-pack/Data Files/*'})
  if(!$entries.Count){throw 'No bundled Expansion Pack assets found.'}
  foreach($entry in $entries){
   $rel=$entry.Path.Substring('expansion-pack/Data Files/'.Length)
   if($rel -match '(^|[/\\])\.\.([/\\]|$)' -or [IO.Path]::IsPathRooted($rel)){throw 'Unsafe asset path.'}
   $src=Join-Path $PayloadFolder ($entry.Path.Replace('/','\'))
   $dst=Join-Path $data ($rel.Replace('/','\'))
   if(!(Test-Path -LiteralPath $src -PathType Leaf) -or (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash -ine $entry.SHA256){throw ('Damaged bundled asset: '+$rel)}
   if(Test-Path -LiteralPath $dst -PathType Leaf){
    if((Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -ine $entry.SHA256){throw ('Existing modified asset requires manual review: '+$rel)}
   } else {$planned+=@{Source=$src;Target=$dst}}
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
 foreach($item in $planned){
  [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Target))|Out-Null
  [IO.File]::Copy($item.Source,$item.Target,$false)
  $copied+=$item.Target
 }
 $new=($lines -join [Environment]::NewLine).TrimEnd()+[Environment]::NewLine
 $temp=$ConfigFile+'.tes3np-pending'
 try{
  [IO.File]::WriteAllText($temp,$new,[Text.UTF8Encoding]::new($false))
  # File.Replace requires a valid backup path on Windows; null triggers
  # "The path is not of a legal form." Use our already-created, unique
  # backup file as the replacement backup, retaining rollback protection.
  [IO.File]::Replace($temp,$ConfigFile,$backup)
 }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
 if($ResultFile){[IO.File]::WriteAllText($ResultFile,('Expansion Pack '+$Action+' complete.'),[Text.Encoding]::UTF8)}
 exit 0
}catch{
 foreach($f in $copied){if(Test-Path -LiteralPath $f){Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}}
 if($ResultFile){[IO.File]::WriteAllText($ResultFile,$_.Exception.Message,[Text.Encoding]::UTF8)}
 exit 1
}
