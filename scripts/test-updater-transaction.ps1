$ErrorActionPreference='Stop'
$updater = Join-Path $PSScriptRoot 'tes3np-updater.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('tes3np-transaction-test-' + [guid]::NewGuid().ToString('N'))
function New-Fixture {
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
    $install=Join-Path $root 'live'; $stage=Join-Path $root 'stage\tes3np'; $state=Join-Path $root 'state.ini'
    New-Item $install,$stage -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $install 'tes3np.exe') 'OLD'; Set-Content (Join-Path $install 'owned.txt') 'OLD OWNED'; Set-Content (Join-Path $install 'user-note.txt') 'KEEP ME'
    Set-Content (Join-Path $stage 'tes3np.exe') 'NEW'; Set-Content (Join-Path $stage 'owned.txt') 'NEW OWNED'
    return @($install,(Join-Path $root 'stage'),$state)
}
function Invoke-UpdaterExpectedFailure($fixture,[string]$failAt) {
    # Run fault injection in a child pwsh process. The updater intentionally emits
    # Write-Error and exits 1; the parent test must inspect that exit code rather
    # than allowing ErrorActionPreference=Stop to abort the test harness itself.
    & pwsh -NoProfile -NonInteractive -File $updater -InstallDir $fixture[0] -StageDir $fixture[1] -StateFile $fixture[2] -Version '9.9.9-alpha' -TestMode -FailAt $failAt *> $null
    return $LASTEXITCODE
}
try {
    $f=New-Fixture; & $updater -InstallDir $f[0] -StageDir $f[1] -StateFile $f[2] -Version '9.9.9-alpha' -TestMode
    if ($LASTEXITCODE -ne 0) { throw 'Successful transaction fixture failed.' }
    if ((Get-Content (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'NEW') { throw 'New launcher not installed.' }
    if ((Get-Content (Join-Path $f[0] 'user-note.txt') -Raw).Trim() -ne 'KEEP ME') { throw 'Unrelated install file was destroyed.' }
    if ((Get-Content $f[2] -Raw) -notmatch 'State=LAUNCHED') { throw 'Successful state not recorded.' }
    Write-Host 'PASS: successful transaction preserves unrelated files.'

    $f=New-Fixture; $code=Invoke-UpdaterExpectedFailure $f 'after-backup'
    if ($code -eq 0) { throw 'Injected backup failure unexpectedly succeeded.' }
    if ((Get-Content (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'OLD') { throw 'Backup failure did not preserve old launcher.' }
    if ((Get-Content $f[2] -Raw) -notmatch 'State=ROLLED_BACK') { throw 'Rollback state not recorded after backup failure.' }
    Write-Host 'PASS: failure after backup rolls back.'

    $f=New-Fixture; $code=Invoke-UpdaterExpectedFailure $f 'after-install'
    if ($code -eq 0) { throw 'Injected install failure unexpectedly succeeded.' }
    if ((Get-Content (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'OLD') { throw 'Install failure did not restore old launcher.' }
    if ((Get-Content (Join-Path $f[0] 'user-note.txt') -Raw).Trim() -ne 'KEEP ME') { throw 'Rollback damaged unrelated file.' }
    if ((Get-Content $f[2] -Raw) -notmatch 'State=ROLLED_BACK') { throw 'Rollback state not recorded after install failure.' }
    Write-Host 'PASS: failure after installation restores known-good launcher.'
    Write-Host 'All updater transaction tests passed.'
} finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
