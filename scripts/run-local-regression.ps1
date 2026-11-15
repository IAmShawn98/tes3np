# Offline TES3NP regression runner. Run on the Windows development checkout.
# Never touches the installed Morrowind game, credentials or user AppData
# except for the ordinary launcher build/startup performed by request.
param(
    [switch]$SkipBuild,
    [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (!(Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw 'Windows PowerShell 5.1 was not found.'
}

function Run-OfflineTest([string]$Name, [string]$Interpreter, [string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ("Missing local test script: " + $Name)
    }
    Write-Host ("REGRESSION | " + $Name) -ForegroundColor Cyan
    & $Interpreter -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Path
    if ($LASTEXITCODE -ne 0) {
        throw ("Regression failed: " + $Name + " (exit " + $LASTEXITCODE + ").")
    }
    Write-Host ("PASS | " + $Name) -ForegroundColor Green
}

Push-Location $root
try {
    if (!$SkipBuild) {
        Write-Host 'REGRESSION | Running existing Build tes3np.bat (includes offline source, Chat Host, importer and package checks)' -ForegroundColor Cyan
        & (Join-Path $root 'Build tes3np.bat')
        if ($LASTEXITCODE -ne 0) {
            throw 'The Windows build failed. Existing build artifacts are preserved by its preflight.'
        }
        Write-Host 'PASS | Complete Windows build' -ForegroundColor Green
    }

    # All three fixtures use only synthetic update data / the TEMP folder.
    # None performs an actual launcher update or changes a Morrowind install.
    Run-OfflineTest 'Updater source and version-contract checks' $windowsPowerShell (Join-Path $PSScriptRoot 'test-update-client.ps1')
    Run-OfflineTest 'Updater metadata and tamper fixtures' $windowsPowerShell (Join-Path $PSScriptRoot 'test-update-metadata.ps1')

    # Use the current PowerShell 7 installation when possible. Windows can
    # expose multiple pwsh.exe aliases, so discovery must return one path.
    $pwsh = if ($PSVersionTable.PSVersion.Major -ge 7) {
        Join-Path $PSHOME 'pwsh.exe'
    } else {
        Get-Command 'pwsh.exe' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty Source
    }
    if (!$pwsh) {
        throw 'PowerShell 7 (pwsh.exe) is required for the isolated updater transaction fixture. Build succeeded, but the full offline regression pass is incomplete.'
    }
    Run-OfflineTest 'Isolated updater transaction and rollback fixtures' $pwsh (Join-Path $PSScriptRoot 'test-updater-transaction.ps1')

    if ($SkipBuild) {
        Write-Host 'PASS | Offline updater fixtures complete. Build skipped.' -ForegroundColor Green
    } else {
        Write-Host 'PASS | Windows build and offline updater fixtures complete.' -ForegroundColor Green
    }
    if (!$NoLaunch) {
        $launcher = Join-Path $root 'tes3np.exe'
        if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) {
            throw 'The built launcher executable is missing.'
        }
        Start-Process -FilePath $launcher -WorkingDirectory $root
        Write-Host 'LAUNCHED | tes3np.exe. Manually check characters, macros, client settings, Expansion Pack toggle/import, Game Chat and Happy Hour.' -ForegroundColor Cyan
    }
}
finally {
    Pop-Location
}
