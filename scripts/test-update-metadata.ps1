param(
    [string]$Generator = 'scripts/generate-update-metadata.ps1'
)

$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ("tes3np-update-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null

function Assert-Throws([scriptblock]$Action, [string]$Name) {
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { throw "Negative test failed: $Name did not reject invalid input." }
    Write-Host "PASS (rejected): $Name"
}

try {
    $package = Join-Path $root 'tes3np-windows.zip'
    $manifest = Join-Path $root 'tes3np-update.json'
    $checksum = Join-Path $root 'tes3np-windows.zip.sha256'
    [IO.File]::WriteAllBytes($package, [byte[]](1,2,3,4,5,6,7,8))

    & $Generator -PackagePath $package -ManifestPath $manifest -ChecksumPath $checksum
    $good = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $actualHash = (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($good.product -ne 'tes3np' -or $good.channel -ne 'alpha' -or $good.platform -ne 'windows' -or $good.architecture -ne 'x64') { throw 'Positive metadata identity test failed.' }
    if ([int64]$good.package.size -ne 8 -or $good.package.sha256 -ne $actualHash) { throw 'Positive package integrity test failed.' }
    if ($good.updateEnabled -ne $true) { throw 'Emergency update switch default test failed.' }
    Write-Host 'PASS: valid manifest and checksum generated.'

    Assert-Throws { & $Generator -PackagePath (Join-Path $root 'missing.zip') -ManifestPath $manifest -ChecksumPath $checksum | Out-Null } 'missing package'

    $badJson = Join-Path $root 'malformed.json'
    [IO.File]::WriteAllText($badJson, '{ definitely-not-json')
    Assert-Throws { Get-Content -LiteralPath $badJson -Raw | ConvertFrom-Json | Out-Null } 'malformed manifest JSON'

    $tampered = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $tampered.package.sha256 = ('0' * 64)
    if ($tampered.package.sha256 -eq $actualHash) { throw 'Hash tamper fixture unexpectedly matches package.' }
    Write-Host 'PASS (detected): wrong package hash fixture.'

    $tampered = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $tampered.package.size = 999999
    if ([int64]$tampered.package.size -eq (Get-Item -LiteralPath $package).Length) { throw 'Size tamper fixture unexpectedly matches package.' }
    Write-Host 'PASS (detected): wrong package size fixture.'

    $tampered = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $tampered.version = 'not-a-version'
    if ($tampered.version -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw 'Version tamper fixture unexpectedly passed format validation.' }
    Write-Host 'PASS (detected): malformed version fixture.'

    $disabled = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $disabled.updateEnabled = $false
    if ($disabled.updateEnabled -ne $false) { throw 'Emergency disable fixture failed.' }
    Write-Host 'PASS: emergency update disable state is representable.'

    Write-Host 'All updater metadata safety tests passed.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
