param(
    [string]$SourcePath = 'src/app/update-check.ahk'
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
$metadata = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $SourcePath) 'update-metadata.ahk') -Raw -Encoding UTF8
$installSource = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $SourcePath) 'update-install.ahk') -Raw -Encoding UTF8
$dialogSource = Get-Content -LiteralPath 'src/ui/update-dialogs.ahk' -Raw -Encoding UTF8
$notesSource = Get-Content -LiteralPath 'src/ui/update-notes.ahk' -Raw -Encoding UTF8

function Require-Source([string]$Pattern, [string]$Name, [string]$Code = $source) {
    if ($Code -notmatch $Pattern) { throw "Updater client safety check missing: $Name" }
    Write-Host "PASS: $Name"
}

Require-Source 'update-feed/" channel "\.json"' 'channel-specific manifest endpoint' $metadata
Require-Source '"manifestVersion", "number"\) != 2' 'manifest schema rejection' $metadata
Require-Source '!\(ReadUpdateManifestValue\(fields, "product", "string"\) == "tes3np"\)' 'product identity validation' $metadata
Require-Source '!\(channel == ParseTes3npVersion\(installedVersion\)\.Channel\)' 'installed channel validation' $metadata
Require-Source '!\(ReadUpdateManifestValue\(fields, "platform", "string"\) == "windows"\)' 'platform validation' $metadata
Require-Source '!\(ReadUpdateManifestValue\(fields, "architecture", "string"\) == "x64"\)' 'architecture validation' $metadata
Require-Source '!\(releaseId == "v" version\)' 'release identity validation' $metadata
Require-Source '!\(fileName == "tes3np-" releaseId "-windows\.zip"\)' 'package filename validation' $metadata
Require-Source '\[0-9a-f\]\{64\}' 'SHA-256 format validation' $metadata
Require-Source 'Download\(manifest\.PackageUrl, part\)' 'download uses validated package address' $installSource
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
Require-Source '#Include src\\app\\update-install\.ahk' 'update installation module is included by the launcher' $entry
$startup = '(?m)^updateStatePath := GetPendingUpdateStatePath\(\)\r?\n(?:\r?\n|;[^\r\n]*\r?\n)*; @bundled-resource-setup@\r?\n\r?\nif updateStatePath = ""\r?\n    RecoverInterruptedLauncherUpdate\(\)\r?\nStartLauncher\(\)\r?\nif updateStatePath != ""\r?\n    ConfirmUpdatedLauncherStartup\(updateStatePath\)$'
if ($entry -notmatch $startup -or
    $installSource -notmatch 'FileRead\(statePath, "UTF-8"\)' -or
    $installSource -notmatch 'lines\[2\] != "State=AWAITING_CONFIRMATION" \|\| lines\[3\] != "Version=" AppConfig\.Version' -or
    -not $builder.Contains('$resourceSetupMarker = ''; @bundled-resource-setup@''') -or
    $builder -notmatch 'PrepareBundledResources\(\)\r?\nif A_Args\.Length && A_Args\[1\] = "--check-resources"') {
    throw 'Update acknowledgement must follow resource extraction and successful launcher startup.'
}
$worker = Get-Content -LiteralPath 'scripts/tes3np-updater.ps1' -Raw -Encoding UTF8
if (-not $worker.Contains(@'
-ArgumentList @('--update-confirm', $Version, ('"' + $StateFile + '"')) -WorkingDirectory $InstallDir
'@)) {
    throw 'The updater must quote the state path and launch from the install directory.'
}
Write-Host 'PASS: updater confirmation follows startup and supports state paths with spaces.'

# The release generator writes fileName/size/sha256 under "package".
Require-Source 'ReadUpdateManifestValue\(fields, "package", "object"\)' 'nested release package metadata support' $metadata
$generator = Get-Content -LiteralPath 'scripts/generate-update-metadata.ps1' -Raw
foreach ($field in @('fileName', 'size', 'sha256')) {
    if ($generator -notmatch [regex]::Escape($field)) { throw "Release generator missing $field" }
}
if ($generator -notmatch 'package\s*=\s*\[ordered\]@\{') {
    throw 'Release metadata generator no longer uses the expected nested package object.'
}
Write-Host 'PASS: release generator and launcher package metadata contract.'

# Both dialogs use the same styled, measured viewport and select the requested version.
Require-Source 'if kind = "" \{[^}]*ShowUpdateStatusPanel\("current", AppConfig\.Version\)' 'current dialog copy when no newer release is available'
Require-Source 'kind = "hotfix" \? "Hotfix available"' 'hotfix preview heading' $dialogSource
Require-Source 'ReadPublishedVersionNotes\(latestVersion\)' 'newer release notes in update preview' $dialogSource
Require-Source 'ReadVersionReleaseNotes\(installedVersion\)' 'installed release notes in version status' $dialogSource
Require-Source 'return bundled != "" \? bundled : ReadPublishedVersionNotes\(version\)' 'installed notes work offline' $notesSource
Require-Source 'heading\[1\] = version' 'exact bundled version heading' $notesSource
Require-Source 'row\.SetFont\(entry\.Kind = "heading"' 'gold category headings' $notesSource
Require-Source 'ShowCenteredGoldPrompt\(panel, backdrop, 800, 600\)' 'larger status modal' $dialogSource
Require-Source '#Include src\\ui\\update-dialogs\.ahk' 'update dialogs are included by the launcher' $entry
Require-Source 'BuildStyledReleaseNoteRows\(notes, noteRows\[1\], 674\)' 'font-measured changelog wrapping' $notesSource
Require-Source 'GetTextExtentPoint32W' 'measure actual rendered word widths' $notesSource
Require-Source 'ReleaseNoteFits\(control, remaining, maxWidth\)' 'pixel-width line fitting' $notesSource
Require-Source '#Include src\\ui\\update-notes\.ahk' 'release notes module is included by the launcher' $entry
Require-Source 'UpdateNotesMouseWheel\.Bind\(viewport, page, refresh\)' 'wheel handler is bound to the release notes viewport' $notesSource
Require-Source 'GetWindowRect", "Ptr", viewport\.Hwnd, "Ptr", bounds' 'wheel hit test uses the viewport HWND' $notesSource

$buildScript = Get-Content -LiteralPath 'scripts/build-windows.ps1' -Raw -Encoding UTF8
if (-not $buildScript.Contains("Copy-Item (Join-Path `$projectRoot 'RELEASE_NOTES.md')")) {
    throw 'Windows packages must include the player-facing release notes.'
}
$workflow = Get-Content -LiteralPath '.github/workflows/publish-alpha.yml' -Raw -Encoding UTF8
$publisher = Get-Content -LiteralPath 'scripts/publish-alpha.ps1' -Raw -Encoding UTF8
if ($workflow -notmatch 'run: ./scripts/publish-alpha\.ps1' -or
    $publisher -notmatch "Get-Content -LiteralPath 'RELEASE_NOTES\.md'" -or
    $publisher -match "Get-Content[^\r\n]+['""]CHANGELOG\.md") {
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
if ($playerNotes -notmatch 'Changes since the last public release, v\d+\.\d+\.\d+(?:-(?:alpha|beta|live)(?:\.\d+)?|\.\d+)?\.') {
    throw 'Release notes must identify the public comparison baseline.'
}
Write-Host 'PASS: matching player-facing notes, ordered categories, and release publishing source.'

# Mock exact-tag responses without network access.
& {
    $responses = @{}
    function Invoke-RestMethod($Uri, $Headers, $TimeoutSec) {
        $base = 'https://api.github.com/repos/IAmShawn98/tes3np/releases/tags/'
        if (!$Uri.StartsWith($base, [StringComparison]::Ordinal)) { throw 'Unexpected release notes repository.' }
        $tag = $Uri.Substring($base.Length)
        if (!$responses.ContainsKey($tag)) { throw "Missing fixture for $tag" }
        return $responses[$tag]
    }

    $helper = Join-Path $PSScriptRoot 'fetch-release-notes.ps1'
    $output = [IO.Path]::GetTempFileName()
    try {
        $responses['v0.1.22-alpha.10'] = @{
            tag_name = 'v0.1.22-alpha.10'
            body = "## v0.1.22-alpha.10`n`n### Improvements`n- **Launcher:** New notes."
        }
        & $helper -Version '0.1.22-alpha.10' -OutputPath $output
        if ([IO.File]::ReadAllText($output) -ne "### Improvements`n- **Launcher:** New notes.") {
            throw 'The exact hotfix tag did not return the matching changelog.'
        }

        $responses['v1.0.0-live.1'] = @{
            tag_name = 'v1.0.0-live.1'
            body = "## v1.0.0-live.1`n`n### Bug Fixes`n- **Launcher:** Fixed startup."
        }
        & $helper -Version '1.0.0-live.1' -OutputPath $output
        if ([IO.File]::ReadAllText($output) -ne "### Bug Fixes`n- **Launcher:** Fixed startup.") {
            throw 'The live hotfix did not return its release notes.'
        }

        $responses['v0.1.21.4'] = @{
            tag_name = 'v0.1.21.4'
            body = '### Historical notes'
        }
        & $helper -Version '0.1.21.4' -OutputPath $output
        if ([IO.File]::ReadAllText($output) -ne '### Historical notes') {
            throw 'The older unsuffixed live tag did not return its release notes.'
        }

        $responses['v0.1.22-alpha.10'].body = "## v0.1.23-alpha`n`nWrong version."
        Remove-Item -LiteralPath $output
        & $helper -Version '0.1.22-alpha.10' -OutputPath $output
        if ($LASTEXITCODE -ne 1 -or (Test-Path -LiteralPath $output)) {
            throw 'A mismatched release body must not be displayed under the requested version.'
        }
    } finally {
        Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue
    }
}
Write-Host 'PASS: matching, historical, and mismatched published changelog fixtures.'

if ($notesSource -match '\u25C6') {
    throw 'Changelog renderer must not use ornamental diamond markers.'
}
if ($notesSource -match 'WrapReleaseNoteLines\(content, maximum') {
    throw 'Character-count wrapping can clip release note words.'
}
Write-Host 'PASS: plain release notes headings and measured wrapping.'

Write-Host 'All launcher updater validation checks passed.'
exit 0
