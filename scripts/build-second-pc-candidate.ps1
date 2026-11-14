& {
    $ErrorActionPreference = 'Stop'
    $candidate = Split-Path -Parent $PSScriptRoot
    $build = Join-Path $env:LOCALAPPDATA 'TES3MP-Markerless-Build\6588eb15'
    $pwsh7 = (Get-Command pwsh.exe -CommandType Application | Select-Object -First 1).Source
    $savedExe = $env:TES3NP_MARKERLESS_CONSOLE_EXE
    $savedDlls = $env:TES3NP_MARKERLESS_CONSOLE_DLLS

    Push-Location -LiteralPath $candidate
    try {
        $env:TES3NP_MARKERLESS_CONSOLE_EXE = Join-Path $build 'output\markerless-console-1d225cad\tes3mp.exe'
        $env:TES3NP_MARKERLESS_CONSOLE_DLLS = Join-Path $build 'verified-dependencies-781d661c'
        & $pwsh7 -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1
        if ($LASTEXITCODE -ne 0) { throw 'Candidate build failed.' }
        python .\scripts\check-windows-package.py .\dist\tes3np-windows.zip --require-console-client
        if ($LASTEXITCODE -ne 0) { throw 'Candidate ZIP verification failed.' }
        & $pwsh7 -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-local-regression.ps1 -SkipBuild -NoLaunch
        if ($LASTEXITCODE -ne 0) { throw 'Updater regression checks failed.' }

        $bundle = New-Item -ItemType Directory -Path (Join-Path $candidate 'second-pc') -Force
        Copy-Item -LiteralPath .\dist\tes3np-windows.zip, .\scripts\tes3np-updater.ps1, .\scripts\test-second-pc-migration.ps1 -Destination $bundle.FullName -Force
        $zip = Join-Path $bundle.FullName 'tes3np-windows.zip'
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        Set-Content -LiteralPath ($zip + '.sha256') -Value $hash -Encoding ASCII
        "Copy this folder to the second PC: $($bundle.FullName)"
        "Candidate ZIP SHA-256: $hash"
    }
    finally {
        $env:TES3NP_MARKERLESS_CONSOLE_EXE = $savedExe
        $env:TES3NP_MARKERLESS_CONSOLE_DLLS = $savedDlls
        Pop-Location
    }
}
