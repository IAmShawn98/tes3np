# Disposable Windows regression for the user-installed NP Expansion Pack toggle.
# Never touches the real game, player config, old packs or rollback journals.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Join-Path $env:TEMP ('tes3np-toggle-fixture-' + [guid]::NewGuid().ToString('N'))
$game = Join-Path $root 'Morrowind'
$data = Join-Path $game 'Data Files'
$config = Join-Path $root 'openmw.cfg'
$backups = Join-Path $root 'backups'
$worker = Join-Path $PSScriptRoot 'toggle-expansion-pack.ps1'
$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
function AssertToggle([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw ('Expansion toggle fixture: ' + $Message) }
}
function RunToggle([string]$Action, [string]$Name, [bool]$ExpectedSuccess) {
    $result = Join-Path $root ($Name + '.txt')
    $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File', ('"' + $worker + '"'),
        '-Action', $Action,
        '-MorrowindFolder', ('"' + $game + '"'),
        '-ConfigFile', ('"' + $config + '"'),
        '-BackupFolder', ('"' + $backups + '"'),
        '-ResultFile', ('"' + $result + '"'))
    $process = Start-Process -FilePath $windowsPowerShell -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
    $success = ($process.ExitCode -eq 0)
    $details = if (Test-Path -LiteralPath $result) { [IO.File]::ReadAllText($result) } else { 'result missing' }
    AssertToggle ($success -eq $ExpectedSuccess) ("$Name expected success=$ExpectedSuccess; code=$($process.ExitCode); result=$details")
    AssertToggle (Test-Path -LiteralPath $result -PathType Leaf) "$Name result file missing"
}
try {
    [IO.Directory]::CreateDirectory($data) | Out-Null
    foreach ($master in @('Morrowind.esm','Tribunal.esm','Bloodmoon.esm')) {
        [IO.File]::WriteAllText((Join-Path $data $master), 'synthetic fixture', [Text.Encoding]::ASCII)
    }
    $original = 'data="' + $data.Replace('\','/') + '"' + "`r`n" + 'content=Morrowind.esm' + "`r`n" + 'content=OtherMod.esp' + "`r`n"
    [IO.File]::WriteAllText($config, $original, [Text.Encoding]::UTF8)
    # No user-supplied ESP: enabling must fail, change nothing, and never fall
    # back to bundled v0.1 art.
    RunToggle 'Enable' 'missing-pack' $false
    AssertToggle ([IO.File]::ReadAllText($config) -eq $original) 'missing pack changed configuration'
    $esp = Join-Path $data 'NP Expansion Pack.esp'
    [IO.File]::WriteAllText($esp, '', [Text.Encoding]::ASCII)
    RunToggle 'Enable' 'empty-pack' $false
    AssertToggle ([IO.File]::ReadAllText($config) -eq $original) 'empty pack changed configuration'
    # A player may install the ESP in a separate data= directory.
    $alternate = Join-Path $root 'custom-expansion-data'
    [IO.Directory]::CreateDirectory($alternate) | Out-Null
    $alternateEsp = Join-Path $alternate 'NP Expansion Pack.esp'
    [IO.File]::WriteAllText($alternateEsp, 'synthetic separately installed pack', [Text.Encoding]::ASCII)
    $alternateConfig = $original + 'data="' + $alternate.Replace('\','/') + '"' + "`r`n"
    [IO.File]::WriteAllText($config, $alternateConfig, [Text.Encoding]::UTF8)
    RunToggle 'Enable' 'alternate-data-folder' $true
    $afterAlternateEnable = [IO.File]::ReadAllText($config)
    AssertToggle ($afterAlternateEnable.Contains('content=NP Expansion Pack.esp')) 'separately installed pack was not enabled'
    AssertToggle ($afterAlternateEnable.Contains('content=OtherMod.esp')) 'alternate enable lost unrelated mod'
    RunToggle 'Disable' 'alternate-disabled' $true
    AssertToggle ([IO.File]::ReadAllText($alternateEsp) -eq 'synthetic separately installed pack') 'alternate pack changed on toggle'
    AssertToggle (-not ([IO.File]::ReadAllText($config).Contains('content=NP Expansion Pack.esp'))) 'alternate disable left content enabled'
    [IO.File]::WriteAllText($config, $original, [Text.Encoding]::UTF8)
    # Original game-folder case must work independently as well.
    [IO.File]::WriteAllText($esp, 'synthetic installed Expansion Pack', [Text.Encoding]::ASCII)
    $beforeEsp = [IO.File]::ReadAllText($esp)
    RunToggle 'Enable' 'installed-pack' $true
    $enabled = [IO.File]::ReadAllText($config)
    AssertToggle ($enabled.Contains('content=NP Expansion Pack.esp')) 'installed pack not enabled'
    AssertToggle ($enabled.Contains('content=OtherMod.esp')) 'unrelated mod entry lost'
    AssertToggle ([IO.File]::ReadAllText($esp) -eq $beforeEsp) 'installed ESP was changed by toggle'
    RunToggle 'Disable' 'disable-pack' $true
    $disabled = [IO.File]::ReadAllText($config)
    AssertToggle (!$disabled.Contains('content=NP Expansion Pack.esp')) 'disable left the pack enabled'
    AssertToggle ($disabled.Contains('content=OtherMod.esp')) 'disable removed unrelated mod'
    AssertToggle ([IO.File]::ReadAllText($esp) -eq $beforeEsp) 'disable deleted or changed installed ESP'
    AssertToggle (@(Get-ChildItem -LiteralPath $backups -Filter '*.cfg').Count -ge 2) 'config backups not retained'
    Write-Host 'PASS: missing/empty rejects; installed enable/disable preserves existing assets, other mods and config backups.'
}
finally {
    if (Test-Path -LiteralPath $root -PathType Container) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
