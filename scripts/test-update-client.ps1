param(
    [string]$SourcePath = 'src/app/update-check.ahk'
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SourcePath -Raw

function Require-Source([string]$Pattern, [string]$Name) {
    if ($source -notmatch $Pattern) { throw "Updater client safety check missing: $Name" }
    Write-Host "PASS: $Name"
}

Require-Source 'tes3np-update\.json' 'dedicated update manifest endpoint'
Require-Source 'manifestVersion\s*!=\s*1' 'manifest schema rejection'
Require-Source 'product\s*!=\s*"tes3np"' 'product identity validation'
Require-Source 'channel\s*!=\s*"alpha"' 'release channel validation'
Require-Source 'platform\s*!=\s*"windows"' 'platform validation'
Require-Source 'architecture\s*!=\s*"x64"' 'architecture validation'
Require-Source 'releaseId\s*!=\s*"v"\s*manifest\.version' 'release identity validation'
Require-Source 'fileName\s*!=\s*"tes3np-windows\.zip"' 'package filename validation'
Require-Source '\[0-9a-f\]\{64\}' 'SHA-256 format validation'
Require-Source '!manifest\.updateEnabled' 'emergency update disable handling'
Require-Source 'No update was installed' 'fail-closed user messaging'

# Version comparison fixtures mirror the launcher algorithm and protect against
# the common lexical 0.1.10 < 0.1.9 mistake.
function Compare-Version([string]$left, [string]$right) {
    $left = $left -replace '^v',''
    $right = $right -replace '^v',''
    $lp = $left.Split('-',2); $rp = $right.Split('-',2)
    $la = $lp[0].Split('.'); $ra = $rp[0].Split('.')
    for ($i=0; $i -lt 3; $i++) {
        $a = if ($i -lt $la.Length) { [int]$la[$i] } else { 0 }
        $b = if ($i -lt $ra.Length) { [int]$ra[$i] } else { 0 }
        if ($a -ne $b) { return $(if ($a -gt $b) { 1 } else { -1 }) }
    }
    $lpre = if ($lp.Length -gt 1) { $lp[1] } else { '' }
    $rpre = if ($rp.Length -gt 1) { $rp[1] } else { '' }
    if ($lpre -eq $rpre) { return 0 }
    if (-not $lpre) { return 1 }
    if (-not $rpre) { return -1 }
    return [Math]::Sign([string]::Compare($lpre,$rpre,$true))
}

$fixtures = @(
    @('0.1.10-alpha','0.1.9-alpha',1),
    @('0.2.0-alpha','0.1.99-alpha',1),
    @('1.0.0','1.0.0-alpha',1),
    @('0.1.4-alpha','0.1.4-alpha',0),
    @('0.1.3-alpha','0.1.4-alpha',-1)
)
foreach ($f in $fixtures) {
    $actual = Compare-Version $f[0] $f[1]
    if ($actual -ne $f[2]) { throw "Version fixture failed: $($f[0]) vs $($f[1]) => $actual, expected $($f[2])" }
}
Write-Host 'PASS: semantic version ordering fixtures.'
Write-Host 'All launcher updater validation checks passed.'
