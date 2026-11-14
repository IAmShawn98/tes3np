$ErrorActionPreference='Stop'
$updater = Join-Path $PSScriptRoot 'tes3np-updater.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('tes3np-transaction-test-' + [guid]::NewGuid().ToString('N'))
function New-Fixture {
    if (Test-Path $root) { Remove-Item $root -Recurse -Force }
    $install=Join-Path $root 'live'; $stage=Join-Path $root 'stage\tes3np'; $state=Join-Path $root 'state.ini'
    New-Item $install,$stage -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $install 'tes3np.exe') 'OLD'; Set-Content (Join-Path $install 'owned.txt') 'OLD OWNED'; Set-Content (Join-Path $install 'user-note.txt') 'KEEP ME'
    Set-Content (Join-Path $stage 'tes3np.exe') 'NEW'; Set-Content (Join-Path $stage 'owned.txt') 'NEW OWNED'; Set-Content (Join-Path $stage 'new-only.txt') 'REMOVE ON ROLLBACK'
    foreach($relative in @('runtime\AutoHotkey64.exe','RELEASE_NOTES.md','client\tes3mp.exe','client\tes3mp-client-default.cfg','client\defaults.bin','client\openmw.cfg','chat-host\tes3np.ChatHost.exe','chat-host\chat.ini','chat-host\chat.css','licenses\TES3MP\LICENSE','licenses\TES3MP\REDISTRIBUTION-NOTICE.txt')){
        $target=Join-Path $stage $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Set-Content -LiteralPath $target -Value 'TEST PAYLOAD'
    }
    $existingChat=Join-Path $install 'chat-host'
    foreach ($rootFolder in @($stage, $install)) {
        $assets = Join-Path $rootFolder 'chat-host/assets'
        New-Item -ItemType Directory -Path $assets -Force | Out-Null
        Set-Content (Join-Path $assets 'DiscordInt.png') $(if ($rootFolder -eq $stage) { 'NEW LOGO' } else { 'OLD LOGO' })
    }
    New-Item -ItemType Directory -Path $existingChat -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $existingChat 'chat.ini') -Value 'CUSTOM USER CHAT SIZE'
    Set-Content -LiteralPath (Join-Path $existingChat 'chat.css') -Value 'CUSTOM USER CHAT STYLE'
    return @($install,(Join-Path $root 'stage'),$state)
}
function Invoke-UpdaterExpectedFailure($fixture,[string]$failAt) {
    & pwsh -NoProfile -NonInteractive -File $updater -InstallDir $fixture[0] -StageDir $fixture[1] -StateFile $fixture[2] -Version '9.9.9-alpha' -TestMode -FailAt $failAt *> $null
    $code=$LASTEXITCODE
    # A nonzero child status is the expected test result, not the harness result.
    $global:LASTEXITCODE = 0
    return $code
}
try {
    $f=New-Fixture; & $updater -InstallDir ($f[0] + [IO.Path]::DirectorySeparatorChar) -StageDir $f[1] -StateFile $f[2] -Version '9.9.9-alpha' -TestMode
    if ($LASTEXITCODE -ne 0) { throw 'Successful transaction fixture failed.' }
    if ((Get-Content (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'NEW') { throw 'New launcher not installed.' }
    if ((Get-Content (Join-Path $f[0] 'user-note.txt') -Raw).Trim() -ne 'KEEP ME') { throw 'Unrelated install file was destroyed.' }
    if ((Get-Content (Join-Path $f[0] 'chat-host\chat.ini') -Raw).Trim() -ne 'CUSTOM USER CHAT SIZE') { throw 'Update overwrote saved chat layout.' }
    if ((Get-Content (Join-Path $f[0] 'chat-host\chat.css') -Raw).Trim() -ne 'CUSTOM USER CHAT STYLE') { throw 'Update overwrote saved chat theme.' }
    if ((Get-Content (Join-Path $f[0] 'chat-host/assets/DiscordInt.png') -Raw).Trim() -ne 'NEW LOGO' -or
        (Test-Path (Join-Path $f[0] 'chat-host/assets/assets'))) {
        throw 'Update nested an existing Chat Host directory instead of replacing its assets.'
    }
    if ((Get-Content $f[2] -Raw) -notmatch 'State=LAUNCHED') { throw 'Successful state not recorded.' }
    if (Test-Path -LiteralPath ($f[0] + '.tes3np-recovery')) {
        throw 'The rollback backup was created inside the install directory.'
    }
    Write-Host 'PASS: successful transaction preserves unrelated files.'

    # Simulate an existing v0.1.20-alpha directory upgrading to the new
    # self-contained v0.1.21 layout. Never modify a real player profile.
    $f=New-Fixture
    $legacy=Join-Path $f[0] 'tes3np'
    New-Item -ItemType Directory -Path $legacy -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $legacy 'old-version-note.txt') -Value 'PRESERVE LEGACY FILE'
    $ini=Join-Path $f[0] 'launcher-data.ini'
    Set-Content -LiteralPath $ini -Value '[Characters] ORIGINAL TEST PROFILES'
    & $updater -InstallDir $f[0] -StageDir $f[1] -StateFile $f[2] -Version '0.1.21-alpha' -TestMode
    if ($LASTEXITCODE -ne 0) { throw 'Legacy upgrade layout fixture failed.' }
    if ((Get-Content -LiteralPath (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'NEW') { throw 'Legacy upgrade did not install new launcher.' }
    if ((Get-Content -LiteralPath $ini -Raw).Trim() -ne '[Characters] ORIGINAL TEST PROFILES') { throw 'Legacy upgrade overwrote user data.' }
    if ((Get-Content -LiteralPath (Join-Path $legacy 'old-version-note.txt') -Raw).Trim() -ne 'PRESERVE LEGACY FILE') { throw 'Legacy upgrade destroyed an unrelated directory.' }
    Write-Host 'PASS: legacy alpha layout upgrades without deleting unrelated files or test character data.'

    $f=New-Fixture
    Remove-Item -LiteralPath (Join-Path $root 'stage\tes3np\client\defaults.bin') -Force
    $code=Invoke-UpdaterExpectedFailure $f ''
    if ($code -eq 0) { throw 'Incomplete staged payload was incorrectly accepted.' }
    if ((Get-Content (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'OLD') { throw 'Rejected payload modified live launcher.' }
    if ((Get-Content (Join-Path $f[0] 'user-note.txt') -Raw).Trim() -ne 'KEEP ME') { throw 'Rejected payload damaged unrelated file.' }
    if (Test-Path (Join-Path $f[0] 'new-only.txt')) { throw 'Rejected payload installed a new file.' }
    Write-Host 'PASS: incomplete staged payload rejected without modifying installed files.'

    # A nested install/staging pair must be rejected before backup or copy.
    $f=New-Fixture
    $nestedInstall=Join-Path $f[1] 'tes3np'
    $code=Invoke-UpdaterExpectedFailure @($nestedInstall,$f[1],$f[2]) ''
    if($code -eq 0){throw 'Updater accepted an install folder inside its staging folder.'}
    if((Get-Content (Join-Path $nestedInstall 'tes3np.exe') -Raw).Trim() -ne 'NEW'){
        throw 'Overlapping paths altered staged/live content.'
    }
    Write-Host 'PASS: overlapping staging and installation paths are rejected.'

    # Ensure the updater cannot accept a payload root buried in arbitrary subfolders.
    $f=New-Fixture
    $buried=Join-Path $f[1] 'unexpected'
    New-Item -ItemType Directory -Path $buried -Force | Out-Null
    Move-Item -LiteralPath (Join-Path $f[1] 'tes3np') -Destination (Join-Path $buried 'tes3np')
    $code=Invoke-UpdaterExpectedFailure $f ''
    if($code -eq 0){throw 'Updater accepted an unexpected nested payload root.'}
    if((Get-Content (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'OLD'){
        throw 'Unexpected payload root changed existing launcher.'
    }
    Write-Host 'PASS: unexpected payload nesting rejected before touching installation.'

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
    if (Test-Path (Join-Path $f[0] 'new-only.txt')) { throw 'New file from failed update was not removed.' }
    if ((Get-Content (Join-Path $f[0] 'owned.txt') -Raw).Trim() -ne 'OLD OWNED') { throw 'Updated owned file was not rolled back.' }
    if ((Get-Content (Join-Path $f[0] 'chat-host/assets/DiscordInt.png') -Raw).Trim() -ne 'OLD LOGO' -or
        (Test-Path (Join-Path $f[0] 'chat-host/assets/assets'))) {
        throw 'Rollback did not restore the original Chat Host asset path and contents.'
    }
    Write-Host 'PASS: failure after installation restores known-good launcher.'
    $f = New-Fixture
    $conflict = Join-Path $f[0] 'owned.txt'
    Remove-Item -LiteralPath $conflict
    New-Item -ItemType Directory -Path $conflict | Out-Null
    Set-Content -LiteralPath (Join-Path $conflict 'user.txt') 'KEEP THIS DIRECTORY'
    $code = Invoke-UpdaterExpectedFailure $f ''
    if ($code -eq 0 -or (Get-Content $f[2] -Raw) -notmatch 'State=ROLLED_BACK') {
        throw 'A staged file was accepted at an existing directory path.'
    }
    if (Test-Path -LiteralPath (Join-Path $conflict 'owned.txt')) {
        throw 'A staged file was copied into the existing directory.'
    }
    if ((Get-Content -LiteralPath (Join-Path $conflict 'user.txt') -Raw).Trim() -ne 'KEEP THIS DIRECTORY') {
        throw 'Rollback changed user data in the existing directory.'
    }
    if ((Get-Content -LiteralPath (Join-Path $f[0] 'chat-host/assets/DiscordInt.png') -Raw).Trim() -ne 'OLD LOGO') {
        throw 'A partial update was not restored after a file/directory conflict.'
    }
    Write-Host 'PASS: a file/directory conflict rolls back files already copied.'
    $f = New-Fixture
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $key = [BitConverter]::ToString($sha256.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($f[0].ToUpperInvariant()))).Replace('-', '')
    } finally { $sha256.Dispose() }

    Set-Content -LiteralPath $f[2] 'OTHER WORKER OWNS STATE'
    $held = New-Object Threading.Mutex($false, "tes3np-update-$key")
    if (!$held.WaitOne(0)) { throw 'Could not reserve fixture installation lock.' }
    try {
        $code = Invoke-UpdaterExpectedFailure $f ''
        if ($code -eq 0 -or (Get-Content -LiteralPath $f[2] -Raw).Trim() -ne 'OTHER WORKER OWNS STATE') {
            throw 'A competing updater ran or overwrote the active worker state.'
        }
        if ((Get-Content -LiteralPath (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'OLD') {
            throw 'The competing updater modified the installed executable.'
        }
    } finally {
        $held.ReleaseMutex()
        $held.Dispose()
    }
    Write-Host 'PASS: overlapping updater workers leave the active transaction alone.'

    $transaction = $f[0] + '.tes3np-recovery'
    New-Item -ItemType Directory -Path $transaction | Out-Null
    Set-Content -LiteralPath (Join-Path $transaction 'user.txt') 'PRESERVE UNOWNED DIRECTORY'
    $code = Invoke-UpdaterExpectedFailure $f ''
    if ($code -eq 0 -or !(Test-Path -LiteralPath (Join-Path $transaction 'user.txt'))) {
        throw 'Updater claimed or removed an unrelated recovery directory.'
    }
    Remove-Item -LiteralPath $transaction -Recurse
    Write-Host 'PASS: an unrelated directory at the recovery path is preserved.'

    New-Item -ItemType Directory -Path $transaction | Out-Null
    [IO.File]::WriteAllText((Join-Path $transaction 'owner.txt'), $key)
    Copy-Item -LiteralPath $f[0] -Destination (Join-Path $transaction 'backup') -Recurse
    Set-Content -LiteralPath (Join-Path $transaction 'pending.txt') 'new-only.txt'
    Set-Content -LiteralPath (Join-Path $f[0] 'tes3np.exe') 'INTERRUPTED UPDATE'
    Set-Content -LiteralPath (Join-Path $f[0] 'new-only.txt') 'INTERRUPTED FILE'
    Remove-Item -LiteralPath $f[1] -Recurse
    & $updater -InstallDir $f[0] -Version '9.9.9-alpha' -RecoverOnly -TestMode
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $f[0] 'tes3np.exe') -Raw).Trim() -ne 'OLD' -or
        (Test-Path -LiteralPath (Join-Path $f[0] 'new-only.txt')) -or
        (Test-Path -LiteralPath $transaction)) {
        throw 'Startup recovery failed to restore the interrupted transaction without its staging folder.'
    }
    Write-Host 'PASS: startup recovery restores an interrupted installation without its staging folder.'
    Write-Host 'All updater transaction tests passed.'
    exit 0
} finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
