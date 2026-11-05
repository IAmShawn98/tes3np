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
# The UI now uses an owned error-status panel instead of the removed
# "No update was installed" string. Assert the actual fail-closed behavior:
# errors report status, and neither download nor installation proceeds without
# the user's separate confirmation.
Require-Source 'LogLauncherEvent\("ERROR \| UPDATE \| "' 'update failure is logged'
Require-Source 'ShowUpdateStatusPanel\("error", AppConfig\.Version\)' 'update failure opens status panel'
Require-Source 'if choice = "Yes" && ShowGoldUpdateConfirmation\("Download Update\?"' 'download requires user confirmation'
Require-Source 'if ShowGoldUpdateConfirmation\("Install Verified Update\?"' 'installation requires second confirmation'

$downloadGate = $source.IndexOf('if choice = "Yes" && ShowGoldUpdateConfirmation("Download Update?"')
$stage = $source.IndexOf('staged := DownloadAndStageUpdate(manifest)', $downloadGate)
$installGate = $source.IndexOf('if ShowGoldUpdateConfirmation("Install Verified Update?"', $stage)
$launch = $source.IndexOf('StartTransactionalUpdate(manifest.version, staged)', $installGate)
if ($downloadGate -lt 0 -or $stage -le $downloadGate -or
    $installGate -le $stage -or $launch -le $installGate -or
    [regex]::Matches($source, 'StartTransactionalUpdate\(manifest\.version, staged\)').Count -ne 1) {
    throw 'Updater client safety check missing: confirmed stage -> confirmed transactional installation order'
}
Write-Host 'PASS: verified update is staged and installed only after separate confirmations.'

# The public release generator writes fileName/size/sha256 under "package".
# Guard the contract against regressions that silently hide update availability.
Require-Source 'packageMatch' 'nested release package metadata support'
Require-Source 'RequireManifestString\(packageText, "fileName"\)' 'nested package file name'
Require-Source 'RequireManifestInteger\(packageText, "size"\)' 'nested package size'
Require-Source 'RequireManifestString\(packageText, "sha256"\)' 'nested package checksum'
$generator = Get-Content -LiteralPath 'scripts/generate-update-metadata.ps1' -Raw
foreach ($field in @('fileName', 'size', 'sha256')) {
    if ($generator -notmatch [regex]::Escape($field)) { throw "Release generator missing $field" }
}
if ($generator -notmatch 'package\s*=\s*\[ordered\]@\{') {
    throw 'Release metadata generator no longer uses the expected nested package object.'
}
Write-Host 'PASS: release generator and launcher package metadata contract.'

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
# Guard the section-aware release notes and expanded modal dimensions.
Require-Source 'BuildStyledReleaseNoteRows\(notes\.Text\)' 'section-aware release notes'
Require-Source 'row\.SetFont\(entry\.Kind = "heading"' 'gold category headings'
Require-Source 'ShowCenteredUpdateCard\(panel, backdrop, 800, 600\)' 'larger status modal'
$notesHelper = Get-Content -LiteralPath 'scripts/fetch-release-notes.ps1' -Raw
$expectedHeading = '$lines.Add(''### '' + $Matches[1])'
if (-not $notesHelper.Contains($expectedHeading)) {
    throw 'Published release notes must preserve heading markers.'
}
Write-Host 'PASS: changelog categories remain visible for draft and published versions.'
Write-Host 'All launcher updater validation checks passed.'
