& {
    $ErrorActionPreference = 'Stop'
    $bundle = $PSScriptRoot
    $zip = Join-Path $bundle 'tes3np-windows.zip'
    $worker = Join-Path $bundle 'tes3np-updater.ps1'
    $expected = (Get-Content -LiteralPath ($zip + '.sha256') -Raw).Trim()
    if ($expected -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $zip).Hash -ne $expected) {
        throw 'Candidate ZIP checksum mismatch.'
    }
    if ((Get-FileHash -LiteralPath $worker).Hash -ne '32157b1f44567e35db2313285d470f67299e0de4b6334948b5d6ea7500ae5f4d') {
        throw 'Unexpected updater script checksum.'
    }
    if (Get-Process -Name 'tes3np','tes3np.ChatHost' -ErrorAction SilentlyContinue) {
        throw 'Close the other TES3NP sessions before starting the test.'
    }

    $root = Join-Path $env:LOCALAPPDATA ('TES3NP-Upgrade-Test-' + [guid]::NewGuid().ToString('N'))
    $job = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'tes3np-update') ([guid]::NewGuid().ToString('N'))
    $legacyZip = Join-Path $root 'public-v0.1.20-alpha.zip'
    $legacy = Join-Path $root 'legacy'
    $stage = Join-Path $job 'staged'
    $null = New-Item -ItemType Directory -Path $root, $job
    $oldUrl = 'https://github.com/IAmShawn98/tes3np-releases/releases/download/latest-alpha/tes3np-v0.1.20-alpha-windows.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $oldUrl -OutFile $legacyZip
    if ((Get-FileHash -LiteralPath $legacyZip).Hash -ne '61fca7ba2390f5e1bd5f633ec06b43756a45a1e632a70d759ea5932c4bd9538e') {
        throw 'Public v0.1.20-alpha ZIP checksum mismatch.'
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($legacyZip, $legacy)
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $stage)
    if (!(Test-Path -LiteralPath (Join-Path $legacy 'tes3np.exe') -PathType Leaf)) {
        $legacy = Join-Path $legacy 'tes3np'
    }
    $oldExe = Join-Path $legacy 'tes3np.exe'
    $oldHash = (Get-FileHash -LiteralPath $oldExe).Hash
    Start-Process -FilePath $oldExe -WorkingDirectory $legacy
    $null = Read-Host 'Confirm v0.1.20-alpha, add a dummy character, change a preference, close TES3NP, then press Enter'
    while (Get-Process -Name 'tes3np','tes3np.ChatHost' -ErrorAction SilentlyContinue) {
        $null = Read-Host 'TES3NP or Chat Host is still open. Close it, then press Enter'
    }

    $legacyMarker = Join-Path $legacy 'migration-test.txt'
    Set-Content -LiteralPath $legacyMarker -Value 'TES3NP migration test' -Encoding ASCII
    $rollback = Join-Path $root 'rollback-copy'
    Copy-Item -LiteralPath $legacy -Destination $rollback -Recurse
    $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $rollbackState = Join-Path $job 'rollback-state.ini'
    'Injecting a deliberate failure after installation on the rollback copy...'
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File $worker -InstallDir $rollback -StageDir $stage -StateFile $rollbackState -Version '0.1.21-alpha' -TestMode -FailAt after-install
    $rollbackExit = $LASTEXITCODE
    if ($rollbackExit -eq 0 -or (Get-Content -LiteralPath $rollbackState) -notcontains 'State=ROLLED_BACK' -or
        (Get-FileHash -LiteralPath (Join-Path $rollback 'tes3np.exe')).Hash -ne $oldHash -or
        (Get-Content -LiteralPath (Join-Path $rollback 'migration-test.txt') -Raw).Trim() -ne 'TES3NP migration test') {
        throw 'Rollback test failed.'
    }
    'PASS: injected failure restored the original v0.1.20-alpha executable.'

    $state = Join-Path $job 'update-state.ini'
    & $ps51 -NoProfile -ExecutionPolicy Bypass -File $worker -InstallDir $legacy -StageDir $stage -StateFile $state -Version '0.1.21-alpha'
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $state) -notcontains 'State=SUCCESS') {
        throw 'Upgrade did not report SUCCESS.'
    }
    if ((Get-FileHash -LiteralPath $oldExe).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage 'tes3np.exe')).Hash -or
        (Get-Content -LiteralPath $legacyMarker -Raw).Trim() -ne 'TES3NP migration test') {
        throw 'The upgraded executable or unrelated test file failed verification.'
    }
    'PASS: v0.1.21-alpha installed and confirmed its automatic restart.'
    'Check that the dummy character and the changed preference are still visible.'
    "Test folder: $root"
}
