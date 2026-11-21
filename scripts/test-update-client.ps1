param(
    [string]$SourcePath = 'src/app/update-check.ahk'
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
$metadata = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $SourcePath) 'update-metadata.ahk') -Raw -Encoding UTF8
$installSource = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $SourcePath) 'update-install.ahk') -Raw -Encoding UTF8
$dialogSource = Get-Content -LiteralPath 'src/ui/update-dialogs.ahk' -Raw -Encoding UTF8
$notesSource = Get-Content -LiteralPath 'src/ui/update-notes.ahk' -Raw -Encoding UTF8
$fetcherSource = Get-Content -LiteralPath 'scripts/fetch-release-notes.ps1' -Raw -Encoding UTF8

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

Require-Source 'message := "If an update is published, you will be notified\."' 'up-to-date status uses concise notification wording' $dialogSource
Require-Source 'panel\.Add\("Text", "x30 y65 w740 h30 BackgroundTrans", message\)' 'status description uses single-line height' $dialogSource
if ($dialogSource.Contains('You are running the latest and greatest version of the tes3np launcher!')) {
    throw 'Obsolete up-to-date status wording must not return.'
}
Require-Source 'kind = "hotfix" \? "Hotfix available"' 'hotfix preview heading' $dialogSource
Require-Source 'ReadPublishedCategorizedUpdateNotes\(installedVersion, latestVersion\)' 'update preview categorizes missed published versions' $dialogSource

# The preview must derive each version field's width from actual rendered text,
# rather than the length of the shorter feature-only test version. The optional
# second metadata row reflows the notes, actions and gold frame as one unit.
Require-Source 'CreateGoldNativePrompt\(0, "tes3np \u2014 Update Preview", 800, 620\)' 'preview base height is retained' $dialogSource
Require-Source 'AddUpdatePreviewMetadata\(preview, installedVersion, latestVersion, channel\)' 'feature and hotfix use the same metadata layout' $dialogSource

Require-Source 'panel\.Add\("Text", "x30 y80 BackgroundTrans \+0x80", "Installed: v" installedVersion\)' 'installed caption autosizes before height assignment' $dialogSource
Require-Source 'panel\.Add\("Text", "x30 y80 BackgroundTrans \+0x80", "Latest: v" latestVersion\)' 'latest caption autosizes before height assignment' $dialogSource
Require-Source 'panel\.Add\("Text", "x30 y80 BackgroundTrans \+0x80", "Channel: " channelName\)' 'channel caption autosizes before height assignment' $dialogSource
Require-Source 'installed\.Move\(, , installedWidth, 26\)' 'installed caption height applied only after measuring natural width' $dialogSource
Require-Source 'latest\.Move\(, , latestWidth, 26\)' 'latest caption height applied only after measuring natural width' $dialogSource
Require-Source 'channelText\.Move\(, , channelWidth, 26\)' 'channel caption height applied only after measuring natural width' $dialogSource
if ($dialogSource.Contains('x30 y80 h26 BackgroundTrans +0x80')) {
    throw 'Fixed Text height at creation prevents content-width auto-sizing and fails compiled metadata smoke checks.'
}
Require-Source 'installed.GetPos\(, , &installedWidth\)' 'installed caption uses measured natural width' $dialogSource
Require-Source 'latest.GetPos\(, , &latestWidth\)' 'latest caption uses measured natural width' $dialogSource
Require-Source 'channelText.GetPos\(, , &channelWidth\)' 'channel caption uses measured natural width' $dialogSource
Require-Source 'gap := 18' 'metadata groups have an intentional consistent gap' $dialogSource
Require-Source 'if channelX \+ channelWidth <= 770' 'three fields use the same row when they fit' $dialogSource
Require-Source 'if latestX \+ latestWidth <= 770' 'channel drops to a second row when necessary' $dialogSource
Require-Source 'channelText.Move\(30, 144\)' 'longer versions can use three rows without overlap' $dialogSource
Require-Source 'GrowGoldNativePrompt\(preview, rowExtra\)' 'metadata wrapping extends the gold frame' $dialogSource
Require-Source 'preview.Add\("Text", "x30 y" \(118 \+ rowExtra\) " w740 h30 BackgroundTrans", "Changes in This Update"\)' 'preview has one changes heading' $dialogSource
Require-Source 'notes := ReadPublishedCategorizedUpdateNotes\(installedVersion, latestVersion\)' 'all update types use categorized missed changes' $dialogSource
Require-Source 'actionY := 568 \+ rowExtra' 'action buttons follow any wrapped header' $dialogSource
Require-Source 'AddStyledButton\(preview, 32, actionY, 185, 34, "Update Now"' 'update action is left-aligned in preview' $dialogSource
Require-Source 'AddStyledButton\(preview, 233, actionY, 155, 34, "Not Now"' 'not now appears directly beside update action' $dialogSource
Require-Source 'AddUpdateNotesViewport\(preview, notes, scale, 0, rowExtra, 28 \+ rowExtra\)' 'single categorized notes viewport follows dynamic header' $dialogSource
Require-Source 'ReadInstalledCumulativeNotes\(notesVersion\)' 'status merges the installed base release and hotfixes' $dialogSource
Require-Source 'AddUpdateNotesViewport\(panel, releaseNotes, scale\)' 'version status retains original note geometry' $dialogSource
Require-Source 'response.Download := true, DestroyScaledMenu\(preview\)' 'production update still enters existing confirmation flow' $dialogSource

$previewStart = $dialogSource.IndexOf('ShowUpdatePreview(installedVersion')
$metadataStart = $dialogSource.IndexOf('AddUpdatePreviewMetadata(panel, installedVersion')
$statusStart = $dialogSource.IndexOf('ShowUpdateStatusPanel(mode, installedVersion')
if ($previewStart -lt 0 -or $metadataStart -le $previewStart -or $statusStart -le $metadataStart) {
    throw 'Preview and measured metadata helper must remain separate from the Version Status dialog.'
}
$previewPath = $dialogSource.Substring($previewStart, $metadataStart - $previewStart)
if (!$previewPath.Contains('notes := ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion)') -or
    !$previewPath.Contains('"Changes in This Update"') -or
    $previewPath.Contains('AddUpdateNoteTabs(') -or
    $previewPath.Contains('history.Hotfix') -or
    $previewPath.Contains('history.Release')) {
    throw 'Update preview must show one categorized summary of only missed published changes.'
}
$smokeSource = Get-Content -LiteralPath 'scripts/launcher-smoke-tests.ahk' -Raw -Encoding UTF8
if (!$smokeSource.Contains('CheckUpdatePreviewMetadataLayout()') -or
    !$smokeSource.Contains('Update preview metadata overlaps at this version length.') -or
    !$smokeSource.Contains('1.0.0-live.100')) {
    throw 'Windows smoke tests must verify dynamic metadata widths and clipping.'
}
if ($dialogSource.Contains('x123 y80 w147 h26') -or
    $dialogSource.Contains('Review the changes you have missed before deciding to update.') -or
    $dialogSource -match 'Preview only \u2014 nothing has been downloaded or installed\.' -or
    $dialogSource.Contains('TEST DATA ONLY') -or
    $dialogSource.Contains('Update downloads are disabled for this preview.') -or
    $dialogSource.Contains('"Close Test Preview"')) {
    throw 'Update preview reintroduced fixed-width version labels or redundant copy.'
}
if ((20 + 42) -ge 80 -or (80 + 26) -ge 118 -or
    (118 + 30) -ge 158 -or (158 + 367 + 28) -ge 568 -or
    (568 + 34) -ge 620) {
    throw 'Preview base geometry overlaps; wrapped rows must preserve these same gaps.'
}
Write-Host 'PASS: preview metadata adapts to version widths and every update shows categorized changes.'
if ($dialogSource.Contains('"Continue to Download"') -or
    $dialogSource.Contains('AddStyledButton(preview, 590, 568, 178, 34, "GitHub Release"')) {
    throw 'Update preview footer must show only Update Now and Not Now.'
}
Write-Host 'PASS: preview footer has two actions, with download still confirmation-gated.'

Require-Source 'ReadInstalledCumulativeNotes\(notesVersion\)' 'installed notes merge original and hotfix changes' $dialogSource
Require-Source 'Loop info.Hotfix \+ 1' 'installed cumulative notes include every installed hotfix only' $notesSource
Require-Source 'return BuildInstalledVersionNotes\(records\)' 'installed history groups hotfixes above the base release' $notesSource
Require-Source 'details := BuildCategorizedUpdateNotes\(\[record\], false\)' 'installed version groups retain category headings without duplicate version captions' $notesSource
Require-Source 'BuildCategorizedUpdateNotes\(records, includeVersionHeadings := true\)' 'published preview preserves categorized version headings' $notesSource
Require-Source 'ReadBundledVersionNotes\(entryVersion\)' 'installed notes use offline bundled source' $notesSource
Require-Source 'if number = 0\s*notes := ReadPublishedVersionNotes\(base\)' 'original release has an online fallback' $notesSource
Require-Source 'return bundled != "" \? bundled : ReadPublishedVersionNotes\(version\)' 'existing original notes remain available offline' $notesSource
Require-Source 'heading\[1\] = version' 'exact bundled version heading' $notesSource
Require-Source 'return kind = "heading" \? "s12 Bold cE7BE70"' 'gold category headings remain' $notesSource
Require-Source 'CreateGoldNativePrompt\(0, "tes3np \u2014 Version Status", 800, 600\)' 'version status uses the gold modal' $dialogSource
Require-Source 'AddUpdateNotesViewport\(panel, releaseNotes, scale\)' 'version status keeps measured scrolling without tabs' $dialogSource
Require-Source 'ShowGoldNativePrompt\(preview, scale\)\r?\n\s*PaintGoldUpdateDialogButtons\(preview\)' 'update preview paints buttons immediately after show' $dialogSource
Require-Source 'ShowGoldNativePrompt\(panel, scale\)\r?\n\s*PaintGoldUpdateDialogButtons\(panel\)' 'version status paints its footer immediately after show' $dialogSource
if ($dialogSource.Contains('AddUpdateNoteTabs(') -or
    $dialogSource.Contains('Hotfix History') -or
    $dialogSource.Contains('tabs.Switch')) {
    throw 'Obsolete separate release/hotfix tabs must not return.'
}
# A redundant full-window redraw after Show was making the dialog visibly
# flicker. Only its missing owner-painted button faces should be repainted.
if ($dialogSource.Contains('RedrawWindow", "Ptr", panel.Hwnd')) {
    throw 'Release Notes should not redraw the entire visible dialog after opening.'
}
Write-Host 'PASS: release dialog avoids redundant full-window repaint.'
Require-Source 'face.Window = panel.Hwnd' 'release repaint is scoped to the active panel' $dialogSource
Require-Source 'PaintButtonNow\(handle\)' 'themed button faces are explicitly painted' $dialogSource
Require-Source '#Include src\\ui\\update-dialogs\.ahk' 'update dialogs are included by the launcher' $entry
Require-Source 'BuildStyledReleaseNoteRows\(notes, sample, width - Max\(2, px\(10\)\)\)' 'font-measured changelog wrapping uses the scaled width' $notesSource
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
if (!$publisher.Contains('$requiredTag = if ($number -eq 0)') -or
    !$publisher.Contains('gh release view $requiredTag') -or
    !$publisher.Contains('Published changelog $requiredTag was changed')) {
    throw 'Publishing a hotfix must verify the original and all earlier published changelogs.'
}
$indexHelper = Get-Content -LiteralPath 'scripts/update-hotfix-index.ps1' -Raw -Encoding UTF8
if (!$publisher.Contains('& ./scripts/update-hotfix-index.ps1 -LatestHotfixTag $Tag') -or
    !$publisher.Contains('TES3NP HOTFIX HISTORY START') -or
    !$indexHelper.Contains('gh release edit $baseTag --repo $repo --notes-file $tempFile') -or
    !$indexHelper.Contains('Published Hotfixes') -or
    !$fetcherSource.Contains('Published hotfix index is malformed.')) {
    throw 'Hotfix publication must append a verified history section without altering the original notes.'
}
$indexCall = $publisher.IndexOf('update-hotfix-index.ps1')
$feedPublish = $publisher.IndexOf('Copy-Item -LiteralPath $manifestPath -Destination $feedFile')
if ($indexCall -lt 0 -or $feedPublish -le $indexCall) {
    throw 'The base release hotfix index must be updated before advancing the public feed.'
}
& (Join-Path $PSScriptRoot 'test-hotfix-index.ps1')
Write-Host 'PASS: original GitHub changelog is retained and published hotfix links are verified.'


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
$categories = @('New Features', 'Improvements', 'Bug Fixes', 'Hotfixes', 'Removed Features')
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

        # GitHub links published hotfixes from the base release, but that
        # link index must not be duplicated in the launcher's categorized preview.
        $baseNotes = '### New Features' + [char]10 + '- **Launcher:** Original features.'
        $indexedBody = '## v0.1.21-alpha' + [char]10 + [char]10 + $baseNotes +
            [char]10 + [char]10 + '<!-- TES3NP HOTFIX HISTORY START -->' +
            [char]10 + '### Published Hotfixes' + [char]10 + [char]10 +
            '- [v0.1.21-alpha.1](https://github.com/IAmShawn98/tes3np/releases/tag/v0.1.21-alpha.1)' +
            [char]10 + '<!-- TES3NP HOTFIX HISTORY END -->'
        $responses['v0.1.21-alpha'] = @{
            tag_name = 'v0.1.21-alpha'
            body = $indexedBody
        }
        & $helper -Version '0.1.21-alpha' -OutputPath $output
        if ([IO.File]::ReadAllText($output) -cne $baseNotes) {
            throw 'The launcher displayed GitHub hotfix index inside original release notes.'
        }

        $responses['v0.1.22-alpha.10'].body = "## v0.1.23-alpha`n`nWrong version."
        Remove-Item -LiteralPath $output
        # The fetcher fails closed by throwing on invalid release headings.
        # Catch the expected error instead of aborting the entire test runner.
        $rejected = $false
        try {
            & $helper -Version '0.1.22-alpha.10' -OutputPath $output
            if ($LASTEXITCODE -ne 0) { $rejected = $true }
        } catch {
            $rejected = $true
        }
        if (!$rejected -or (Test-Path -LiteralPath $output)) {
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

# The installed version stays visible. An unseen newer update gets a red (1),
# which disappears after its preview is viewed and stays hidden on restart.
Require-Source 'CreateLauncherUpdateBadge\(\)' 'compact unread update indicator exists'
Require-Source 'LauncherUpdateBadge := LauncherGui\.Add\("Text", "x" x " y689 w28 h22 BackgroundTrans", "\(1\)"\)' 'red (1) is the only badge glyph'
Require-Source 'LauncherUpdateBadge\.SetFont\("s" size " Bold cD63232", "Segoe UI"\)' 'unread badge stays red at saved scale'
Require-Source 'size := Max\(6, Round\(10 \* scale\)\)' 'unread badge respects saved scale'
Require-Source 'ApplyLauncherBadgeFont\(LauncherScale / 100\)' 'badge uses saved launcher scale'
Require-Source 'LauncherVersionLabel\.Visible := true' 'installed version remains visible'
Require-Source 'LauncherUpdateBadge\.OnEvent\("Click", CheckForUpdates\)' 'red (1) opens the optional updater'

# Place the badge beside the natural-width version label and redraw the
# backing image only under its rectangle when hiding or showing it.
Require-Source 'LauncherVersionLabel := LauncherGui\.Add\("Text", "x12 y691 BackgroundTrans", "tes3np' 'version caption is measured without fixed dimensions'
Require-Source 'LauncherVersionLabel\.GetPos\(, , &naturalWidth\)' 'version caption natural width is captured'
Require-Source 'LauncherVersionLabel\.Move\(, , Ceil\(naturalWidth \* 1\.125\) \+ 4, 18\)' 'version label height applied after width measurement with 50 percent headroom'
Require-Source 'LauncherVersionLabel\.GetPos\(&labelX, , &labelWidth\)' 'badge follows rendered version width'
Require-Source 'x := labelX \+ labelWidth \+ 4' 'badge stays close beside caption'
Require-Source 'if wasVisible[\s\S]*LauncherUpdateBadge\.Visible := false[\s\S]*RedrawLauncherUpdateBadge\(\)' 'viewing the update hides the badge and clears old pixels'
Require-Source 'if !wasVisible\s*\{\s*ApplyLauncherBadgeFont\(LauncherScale / 100\)\s*LauncherUpdateBadge\.Visible := true\s*RedrawLauncherUpdateBadge\(\)' 'new update shows badge only when previously hidden'
Require-Source 'MapWindowPoints' 'badge repaint uses physical client coordinates'
Require-Source 'RedrawWindow", "Ptr", LauncherGui\.Hwnd,[\s\S]*"UInt", 0x0185' 'only badge rectangle repaints its backdrop'
if ($source.Contains('LauncherVersionTextWidth()') -or
    $source.Contains('y691 w300 h18 BackgroundTrans') -or
    $source.Contains('InvalidateRect", "Ptr", LauncherUpdateBadge.Hwnd') -or
    $source.Contains('Chr(0x25CF)') -or $source.Contains('E0C27F') -or
    $source.Contains('LauncherUpdateDismissedVersion') -or
    $source.Contains('DismissLauncherUpdate(')) {
    throw 'Only an unread red (1) may be shown; viewed state must be hidden and the footer must repaint cleanly.'
}
Write-Host 'PASS: red (1) disappears after preview, stays hidden for viewed versions and repaints cleanly.'

# The automatic preview is reached only when a newer published version appears.
# Validate the actual Win32 function name; a doubled backslash is not a DLL entry point.
Require-Source 'if !IsObject\(LauncherGui\) \|\| !DllCall\("user32\\IsWindowVisible"' 'automatic update preview uses valid native visibility check'
if ($source.Contains('"user32\\\\IsWindowVisible"')) { throw 'Automatic preview must not use a doubled Win32 function separator.' }
if ($source.Contains('LauncherUpdateButton')) { throw 'Long update buttons must not replace the footer version.' }
# Check the production code path after temporary injection tooling is removed.
# These assertions remain useful build regressions, not a runtime test mode.
$bootstrapSource = Get-Content -LiteralPath 'src/app/bootstrap.ahk' -Raw -Encoding UTF8
$badgeHarness = Get-Content -LiteralPath 'scripts/launcher-smoke-tests.ahk' -Raw -Encoding UTF8
Require-Source '&& !HasSeenUpdateAutoPreview\(latestVersion\)' 'only unseen published versions show the red indicator'
Require-Source 'IniWrite\(latest, DataFile, "Updates", "LastAutoPreviewVersion"\)' 'viewing an update persists its seen state across restarts'
Require-Source 'if UpdateBusy \|\| HasSeenUpdateAutoPreview\(version\)' 'previously viewed updates do not automatically reopen'
Require-Source 'ShowUpdatePreview\(installedVersion, latestVersion, channel, kind\)' 'release preview has only production parameters' $dialogSource
Require-Source 'history := ReadPublishedUpdateHistory\(installedVersion, latestVersion\)' 'category formatter reads only published history' $notesSource
Require-Source 'AddStyledButton\(preview, 32, actionY, 185, 34, "Update Now"' 'real Update Now remains available' $dialogSource
Require-Source 'response.Download := true, DestroyScaledMenu\(preview\)' 'Update Now enters the existing confirmation-gated updater' $dialogSource
Require-Source 'AddStyledButton\(preview, 233, actionY, 155, 34, "Not Now"' 'Not Now leaves the updater unchanged' $dialogSource
Require-Source 'SetTimer\(CheckForUpdateAvailability, -250\)' 'normal update polling starts' $bootstrapSource
Require-Source 'SetTimer\(OfferDesktopShortcutOnFirstLaunch, -1800\)' 'normal first-run prompt restored' $bootstrapSource
if ($source -match 'LauncherBadgeTest|LauncherHistoryTest|HandleLauncherHistoryTest|ShowLauncherHistoryTestPreview' -or
    $bootstrapSource -match 'LauncherBadgeTest|LauncherHistoryTest|0x8041|0x8042' -or
    $badgeHarness.Contains('--test-update-badge') -or
    $dialogSource -match 'testHistory|synthetic|TEST DATA ONLY|Update downloads are disabled for this preview') {
    throw 'Temporary manual notification/history injection code remains in production.'
}
Write-Host 'PASS: temporary manual updater preview instrumentation removed; normal updater checks preserved.'

Require-Source 'return BuildCategorizedUpdateNotes\(records\)' 'missed published changes retain category-first formatting' $notesSource
Require-Source 'BuildInstalledVersionNotes\(\[base, patch\]\)' 'compiled data smoke exercises grouped installed hotfix notes' $badgeHarness
Require-Source 'switcher\.Update := updateNotes' 'scrollable viewport still supports safe content refresh' $notesSource
Require-Source 'Loop capacity - 1' 'short and long categorized notes fill the viewport' $notesSource
Require-Source 'if !CheckCategorizedUpdateNotes\(\)\s*ExitApp\(234\)' 'compiled --check runs real category formatting smoke tests' $badgeHarness
Require-Source 'AddPublishedNoteRecords\("### v0\.1\.21-alpha\.1' 'smoke test parses a dated published hotfix' $badgeHarness



# Synthetic publication timeline. Drafts and already installed changes are
# excluded; skipped release notes are grouped by feature and dated hotfix.
& {
    $nl = [Environment]::NewLine
    $releases = @(
        @{ tag_name='v0.1.22-alpha.3'; draft=$true; published_at='2026-11-28T00:00:00Z'; body='DRAFT MUST NOT LEAK' },
        @{ tag_name='v0.1.22-alpha.2'; draft=$false; published_at='2026-11-27T02:00:00Z'; body=(@('## v0.1.22-alpha.2','','### Bug Fixes','- **Launcher:** Fixed newer bug.') -join $nl) },
        @{ tag_name='v0.1.22-alpha.1'; draft=$false; published_at='2026-11-25T02:00:00Z'; body=(@('## v0.1.22-alpha.1','','### Bug Fixes','- **Launcher:** Fixed older bug.') -join $nl) },
        @{ tag_name='v0.1.22-alpha'; draft=$false; published_at='2026-11-23T02:00:00Z'; body=(@('## v0.1.22-alpha','','### New Features','- **Launcher:** Added newer feature.') -join $nl) },
        @{ tag_name='v0.1.21-alpha.1'; draft=$false; published_at='2026-11-21T02:00:00Z'; body=(@('## v0.1.21-alpha.1','','### Bug Fixes','- **Launcher:** Fixed intermediate bug.') -join $nl) },
        @{ tag_name='v0.1.21-alpha'; draft=$false; published_at='2026-11-20T02:00:00Z'; body=(@('## v0.1.21-alpha','','### Improvements','- **Launcher:** Improved intermediate version.') -join $nl) },
        @{ tag_name='v0.1.20-alpha.1'; draft=$false; published_at='2026-11-19T02:00:00Z'; body=(@('## v0.1.20-alpha.1','','### Bug Fixes','- **Launcher:** Fixed an early bug.') -join $nl) },
        @{ tag_name='v0.1.20-alpha'; draft=$false; published_at='2026-11-17T02:00:00Z'; body=(@('## v0.1.20-alpha','','### Improvements','- **Launcher:** Original installed notes.') -join $nl) }
    )
    function Invoke-RestMethod($Uri, $Headers, $TimeoutSec) {
        if ($Uri -cne 'https://api.github.com/repos/IAmShawn98/tes3np/releases?per_page=100&page=1') {
            throw 'Unexpected release history URL.'
        }
        return $releases
    }
    $helper = Join-Path $PSScriptRoot 'fetch-release-notes.ps1'
    $featureFile = [IO.Path]::GetTempFileName()
    $hotfixFile = [IO.Path]::GetTempFileName()
    try {
        & $helper -InstalledVersion '0.1.20-alpha' -LatestVersion '0.1.22-alpha.2' -ReleaseOutputPath $featureFile -HotfixOutputPath $hotfixFile
        if ($LASTEXITCODE -ne 0) { throw 'Published release history fixture failed.' }
        $features = [IO.File]::ReadAllText($featureFile)
        $hotfixes = [IO.File]::ReadAllText($hotfixFile)
        if ($features -notmatch 'v0\.1\.22-alpha' -or $features -notmatch 'v0\.1\.21-alpha' -or
            $features -match 'v0\.1\.20-alpha' -or $features -match 'DRAFT' -or
            $hotfixes -notmatch 'v0\.1\.22-alpha\.2 . November 27, 2026' -or
            $hotfixes -notmatch 'v0\.1\.20-alpha\.1' -or $hotfixes -match 'DRAFT') {
            throw 'Skipped history does not match the published, uninstalled changes.'
        }
        & $helper -InstalledVersion '0.1.22-alpha.1' -LatestVersion '0.1.22-alpha.2' -ReleaseOutputPath $featureFile -HotfixOutputPath $hotfixFile
        if ($LASTEXITCODE -ne 0) { throw 'Hotfix-only history fixture failed.' }
        $features = [IO.File]::ReadAllText($featureFile)
        $hotfixes = [IO.File]::ReadAllText($hotfixFile)
        if ($features -notmatch 'No new feature releases' -or
            $hotfixes -notmatch 'v0\.1\.22-alpha\.2' -or
            $hotfixes -match 'v0\.1\.22-alpha\.1' -or
            $hotfixes -match 'Original installed notes') {
            throw 'Hotfix preview included an old changelog or already installed fix.'
        }
        $releases = @($releases | Where-Object { $_.tag_name -cne 'v0.1.22-alpha.2' })
        Remove-Item -LiteralPath $featureFile,$hotfixFile -ErrorAction SilentlyContinue
        # The helper throws when the requested latest release is not published.
        # Either a terminating error or a nonzero exit code is a safe refusal.
        $rejected = $false
        try {
            & $helper -InstalledVersion '0.1.22-alpha.1' -LatestVersion '0.1.22-alpha.2' -ReleaseOutputPath $featureFile -HotfixOutputPath $hotfixFile
            if ($LASTEXITCODE -ne 0) { $rejected = $true }
        } catch {
            $rejected = $true
        }
        if (!$rejected -or (Test-Path -LiteralPath $featureFile) -or (Test-Path -LiteralPath $hotfixFile)) {
            throw 'Unpublished latest version must not produce history.'
        }
    } finally {
        Remove-Item -LiteralPath $featureFile,$hotfixFile -ErrorAction SilentlyContinue
    }
}
Write-Host 'PASS: publication-only, missed-version, hotfix-only and missing-target note fixtures.'

Write-Host 'All launcher updater validation checks passed.'
exit 0
