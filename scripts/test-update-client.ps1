param(
    [string]$SourcePath = 'src/app/update-check.ahk'
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8

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

$entry = Get-Content -LiteralPath 'tes3np.ahk' -Raw -Encoding UTF8
$builder = Get-Content -LiteralPath 'scripts/build-windows.ps1' -Raw -Encoding UTF8
$startup = '(?m)^updateStateFile := GetPendingUpdateStateFile\(\)\r?\nStartLauncher\(\)\r?\nif updateStateFile != ""\r?\n    ConfirmUpdatedLauncherStartup\(updateStateFile\)$'
if ($entry -notmatch $startup -or
    $entry -notmatch 'IniRead\(stateFile, "Update", "State", ""\) != "AWAITING_CONFIRMATION"' -or
    -not $builder.Contains('PrepareBundledResources()`nStartLauncher()')) {
    throw 'Update acknowledgement must follow resource extraction and successful launcher startup.'
}
$worker = Get-Content -LiteralPath 'scripts/tes3np-updater.ps1' -Raw -Encoding UTF8
if (-not $worker.Contains(@'
-ArgumentList @('--update-confirm', $Version, ('"' + $StateFile + '"')) -WorkingDirectory $InstallDir
'@)) {
    throw 'The updater must quote the state path and launch from the install directory.'
}
Write-Host 'PASS: updater confirmation follows startup and supports state paths with spaces.'

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
# Both dialogs use the same styled, measured viewport and select the requested version.
Require-Source 'if CompareTes3npVersions\(latest, AppConfig\.Version\) <= 0 \{[^}]*ShowUpdateStatusPanel\("current", AppConfig\.Version\)' 'current dialog copy when no newer release is available'
Require-Source 'ReadPublishedVersionNotes\(latestVersion\)' 'newer release notes in update preview'
Require-Source 'ReadVersionReleaseNotes\(installedVersion\)' 'installed release notes in version status'
Require-Source 'return bundled != "" \? bundled : ReadPublishedVersionNotes\(version\)' 'installed notes work offline'
Require-Source 'heading\[1\] = version' 'exact bundled version heading'
Require-Source 'row\.SetFont\(entry\.Kind = "heading"' 'gold category headings'
Require-Source 'ShowCenteredUpdateCard\(panel, backdrop, 800, 600\)' 'larger status modal'
Require-Source 'BuildStyledReleaseNoteRows\(notes, noteRows\[1\], 674\)' 'font-measured changelog wrapping'
Require-Source 'GetTextExtentPoint32W' 'measure actual rendered word widths'
Require-Source 'ReleaseNoteFits\(control, remaining, maxWidth\)' 'pixel-width line fitting'

$buildScript = Get-Content -LiteralPath 'scripts/build-windows.ps1' -Raw -Encoding UTF8
if (-not $buildScript.Contains("Copy-Item (Join-Path `$projectRoot 'RELEASE_NOTES.md')")) {
    throw 'Windows packages must include the player-facing release notes.'
}
$workflow = Get-Content -LiteralPath '.github/workflows/publish-alpha.yml' -Raw -Encoding UTF8
if ($workflow -notmatch "Get-Content -LiteralPath 'RELEASE_NOTES\.md'" -or
    $workflow -match "Get-Content[^\r\n]+['""]CHANGELOG\.md") {
    throw 'The alpha publish workflow must use the player-facing release notes.'
}

$state = Get-Content -LiteralPath 'src/state.ahk' -Raw -Encoding UTF8
$version = [regex]::Match($state, 'AppConfig\s*:=\s*\{Version:\s*"([^"]+)"').Groups[1].Value
$playerNotes = Get-Content -LiteralPath 'RELEASE_NOTES.md' -Raw -Encoding UTF8
$versionPattern = [regex]::Escape($version)
$section = [regex]::Match($playerNotes, "(?ms)^##[ \t]+v$versionPattern(?=[ \t]|\r?$)[^\r\n]*\r?\n(.*?)(?=^##[ \t]|\z)")
if (!$version -or !$section.Success) { throw 'Player-facing notes must match the launcher version.' }
$playerNotes = $section.Groups[1].Value
if ($playerNotes -match '(?i)commit [0-9a-f]{7}|regression contract|source checks|github actions|fixture|pending windows|source-only|build transcript') {
    throw 'Internal engineering details must not appear in player-facing release notes.'
}
$categories = @('New Features', 'Improvements', 'Bug Fixes', 'Removed Features')
$found = @([regex]::Matches($playerNotes, '(?m)^### ([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value })
$ordered = @($categories | Where-Object { $_ -in $found })
if (!$found.Count -or ($found -join '|') -ne ($ordered -join '|')) {
    throw 'Player-facing changelog categories must appear in the approved order.'
}
$entries = @($playerNotes -split "`r?`n" | Where-Object { $_ -match '^- ' })
if (!$entries.Count) { throw 'Player-facing release notes have no entries.' }
foreach ($entry in $entries) {
    if ($entry -notmatch '^- \*\*[^*]+(?::\*\* |\*\* \u2014 ).+[.!?]$') {
        throw "Player-facing changelog entry must use a bold area label and an outcome: $entry"
    }
}
if ($playerNotes -notmatch 'Changes since the last public release, v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\.') {
    throw 'Release notes must identify the public comparison baseline.'
}
Write-Host 'PASS: matching player-facing notes, ordered categories, and release publishing source.'

# Mock the moving feed and exact-tag responses without network access.
& {
    $responses = @{}
    function Invoke-RestMethod($Uri, $Headers, $TimeoutSec) {
        $tag = $Uri.Split('/')[-1]
        if (!$responses.ContainsKey($tag)) { throw "Missing fixture for $tag" }
        return $responses[$tag]
    }

    $helper = Join-Path $PSScriptRoot 'fetch-release-notes.ps1'
    $output = [IO.Path]::GetTempFileName()
    try {
        $responses['latest-alpha'] = @{
            tag_name = 'latest-alpha'
            name = 'tes3np v0.1.22-alpha - Latest Test Build'
            body = "## v0.1.22-alpha`n`n### Improvements`n- **Launcher:** New notes."
        }
        & $helper -Version '0.1.22-alpha' -OutputPath $output
        if ([IO.File]::ReadAllText($output) -ne "### Improvements`n- **Launcher:** New notes.") {
            throw 'The moving release did not return the matching changelog.'
        }

        $responses['v0.1.21-alpha'] = @{
            tag_name = 'v0.1.21-alpha'
            body = '### Historical notes'
        }
        & $helper -Version '0.1.21-alpha' -OutputPath $output
        if ([IO.File]::ReadAllText($output) -ne '### Historical notes') {
            throw 'A mismatched moving release must fall back to the exact tag.'
        }

        $responses['latest-alpha'].body = "## v0.1.23-alpha`n`nWrong version."
        Remove-Item -LiteralPath $output
        & $helper -Version '0.1.22-alpha' -OutputPath $output
        if ($LASTEXITCODE -ne 1 -or (Test-Path -LiteralPath $output)) {
            throw 'A mismatched release body must not be displayed under the requested version.'
        }
    } finally {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
}
Write-Host 'PASS: matching, historical, and mismatched published changelog fixtures.'

if ($source -match '\u25C6') {
    throw 'Changelog renderer must not use ornamental diamond markers.'
}
if ($source -match 'WrapReleaseNoteLines\(content, maximum') {
    throw 'Character-count wrapping can clip release note words.'
}
Write-Host 'PASS: plain release notes headings and measured wrapping.'

Write-Host 'All launcher updater validation checks passed.'
exit 0
