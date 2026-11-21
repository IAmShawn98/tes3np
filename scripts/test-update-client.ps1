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
Require-Source 'kind = "hotfix" \? "Hotfix available"' 'hotfix preview heading' $dialogSource
Require-Source 'ReadPublishedUpdateHistory\(installedVersion, latestVersion\)' 'update preview shows only missed published versions' $dialogSource

# Protect both horizontal and vertical spacing, rather than trying to
# paper over one clipped label at a time. The production preview must remain
# readable at normal launcher scale, with no redundant intro or footer copy.
Require-Source 'CreateGoldNativePrompt\(0, "tes3np — Update Preview", 800, 620\)' 'preview uses a compact, bounded window' $dialogSource
Require-Source 'x30 y20 w740 h42 BackgroundTrans", title' 'title has its own line' $dialogSource
Require-Source 'x30 y80 w90 h26 BackgroundTrans", "Installed:"' 'installed label has separate bounds' $dialogSource
Require-Source 'x123 y80 w147 h26 BackgroundTrans", "v" installedVersion' 'installed version is fully visible' $dialogSource
Require-Source 'x272 y80 w70 h26 BackgroundTrans", "Latest:"' 'latest label has separate bounds' $dialogSource
Require-Source 'x346 y80 w167 h26 BackgroundTrans", "v" latestVersion' 'latest version is fully visible' $dialogSource
Require-Source 'x518 y80 w252 h26 BackgroundTrans", "Channel: "' 'channel keeps its own column' $dialogSource
Require-Source 'kind = "hotfix" \? "hotfix" : "release", 118\)' 'tabs follow the metadata row' $dialogSource
Require-Source 'AddUpdateNotesViewport\(preview, notes, scale, tabs.Switch, 0, 28\)' 'note viewport keeps a distinct frame and scroll region' $dialogSource
Require-Source 'AddUpdateNoteTabs\(panel, releaseNotes, hotfixNotes, initialTab := "release", tabY := 123\)' 'existing version status retains its tab position' $dialogSource
Require-Source 'AddUpdateNotesViewport\(panel, notes, scale, switcher := 0, topExtra := 0, bottomExtra := 0\)' 'status panel retains original note geometry' $notesSource
Require-Source 'AddStyledButton\(preview, 32, 568, 185, 34, "Update Now"' 'update action is left-aligned in preview' $dialogSource
Require-Source 'AddStyledButton\(preview, 233, 568, 155, 34, "Not Now"' 'not now appears directly beside update action' $dialogSource
Require-Source 'MsgBox\("Update downloads are disabled for this preview\."' 'offline update button cannot download anything' $dialogSource
Require-Source 'response.Download := true, DestroyScaledMenu\(preview\)' 'production update proceeds to existing confirmation gates' $dialogSource
if ((123 + 147) -ge 272 -or (272 + 70) -ge 346 -or
    (346 + 167) -ge 518 -or (518 + 252) -gt 800 -or
    (272 - (123 + 147)) -gt 8 -or
    (518 - (346 + 167)) -gt 8 -or
    (20 + 42) -ge 80 -or
    (80 + 26) -ge 118 -or
    (118 + 30) -ge 158 -or
    (158 + 367 + 28) -ge 568 -or
    (568 + 34) -ge 620) {
    throw 'Update preview layout has overlapping or out-of-bounds regions.'
}
if ($dialogSource.Contains('"Installed: v" installedVersion') -or
    $dialogSource.Contains('"Latest: v" latestVersion') -or
    $dialogSource.Contains('Review the changes you have missed before deciding to update.') -or
    $dialogSource.Contains('Preview only — nothing has been downloaded or installed.') -or
    $dialogSource.Contains('TEST DATA ONLY') -or
    $dialogSource.Contains('"Close Test Preview"')) {
    throw 'Update preview contains clipped metadata or redundant instructions.'
}
Write-Host 'PASS: compact preview separates title, metadata, tabs, notes and action row.'
if ($dialogSource.Contains('"Continue to Download"') -or
    $dialogSource.Contains('AddStyledButton(preview, 590, 568, 178, 34, "GitHub Release"') -or
    $dialogSource.Contains('AddStyledButton(preview, 330, 568, 140, 34, "Close"')) {
    throw 'Update preview footer must show only Update Now and Not Now.'
}
Write-Host 'PASS: preview footer has two actions, with download still confirmation-gated.'

Require-Source 'ReadVersionReleaseNotes\(originalVersion\)' 'original feature release notes survive hotfixes' $dialogSource
Require-Source 'return bundled != "" \? bundled : ReadPublishedVersionNotes\(version\)' 'installed notes work offline' $notesSource
Require-Source 'heading\[1\] = version' 'exact bundled version heading' $notesSource
Require-Source 'return kind = "heading" \? "s12 Bold cE7BE70"' 'gold category headings' $notesSource
Require-Source 'CreateGoldNativePrompt\(0, "tes3np \u2014 Version Status", 800, 600\)' 'version status uses the gold modal' $dialogSource
Require-Source 'AddUpdateNotesViewport\(panel, releaseNotes, scale, tabs.Switch\)' 'version status passes the scale and tab switcher to release notes' $dialogSource
Require-Source 'ShowGoldNativePrompt\(preview, scale\)\r?\n\s*PaintGoldUpdateDialogButtons\(preview\)' 'update preview paints buttons immediately after show' $dialogSource
Require-Source 'ShowGoldNativePrompt\(panel, scale\)\r?\n\s*PaintGoldUpdateDialogButtons\(panel\)' 'version status paints tabs and footer immediately after show' $dialogSource
Require-Source 'tabs.Switch.Update.Call\(selected = "hotfix" \? tabs.Hotfix : tabs.Release\)\r?\n\s*;[^\r\n]*\r?\n\s*PaintGoldUpdateDialogButtons\(tabs.ReleaseButton.Gui\)' 'release note tab switches repaint their native buttons' $dialogSource
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

        # GitHub links published hotfixes from the base release, but that
        # link index must not duplicate the launcher's Hotfix History tab.
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

# The footer notification must not replace or lengthen the installed version.
Require-Source 'CreateLauncherUpdateBadge\(\)' 'compact update indicator exists'
Require-Source 'nextText := unseen \? "\(1\)" : Chr\(0x25CF\)' 'unread and viewed states share one indicator'
Require-Source 'color := unread \? "D63232" : "E0C27F"' 'viewed state uses visible warm gold on dark artwork'
Require-Source 'size := Max\(6, Round\(\(unread \? 10 : 12\) \* scale\)\)' 'viewed circle is enlarged while respecting saved scale'
Require-Source 'ApplyLauncherBadgeFont\(LauncherScale / 100\)' 'badge state uses saved launcher scale'
Require-Source 'y689 w28 h22 BackgroundTrans' 'badge dot remains left-aligned next to version'
if ($source.Contains('w28 h22 Center BackgroundTrans')) { throw 'Centered single-dot badge leaves an unnecessary horizontal gap.' }
Require-Source 'LauncherUpdateBadge\.Text := nextText' 'badge updates through the shared state change path'
Require-Source 'LauncherVersionLabel\.Visible := true' 'installed version remains visible'
Require-Source 'LauncherUpdateBadge\.OnEvent\("Click", CheckForUpdates\)' 'indicator reopens the optional updater'

# Footer alignment derives from the version control's DPI-aware natural width.
# Redraw just its little badge rectangle, including the background image,
# when replacing or hiding transparent glyphs.
Require-Source 'LauncherVersionLabel := LauncherGui\.Add\("Text", "x12 y691 h18 BackgroundTrans"' 'version label auto sizes to visible text'
Require-Source 'LauncherVersionLabel\.GetPos\(&labelX, , &labelWidth\)' 'indicator follows rendered caption width'
Require-Source 'x := labelX \+ labelWidth \+ 4' 'badge stays close beside caption'
Require-Source 'if wasVisible[\s\S]*LauncherUpdateBadge\.Visible := false[\s\S]*RedrawLauncherUpdateBadge\(\)' 'hidden badge clears old glyph'
Require-Source 'if !wasVisible \|\| LauncherUpdateBadge\.Text != nextText' 'badge updates only for actual state changes'
Require-Source 'MapWindowPoints' 'badge repaint uses physical client coordinates'
Require-Source 'RedrawWindow", "Ptr", LauncherGui\.Hwnd,[\s\S]*"UInt", 0x0185' 'only the badge rectangle repaints its backdrop'
if ($source.Contains('LauncherVersionTextWidth()') -or
    $source.Contains('y691 w300 h18 BackgroundTrans') -or
    $source.Contains('InvalidateRect", "Ptr", LauncherUpdateBadge.Hwnd')) {
    throw 'Badge layout must not measure a physical pixel width as a DPI-scaled GUI coordinate or leave stale glyphs.'
}
Write-Host 'PASS: badge aligns to version and repaints without stale transparent text.'

# The automatic preview is reached only when a newer published version appears.
# Validate the actual Win32 function name; a doubled backslash is not a DLL entry point.
Require-Source 'if !IsObject\(LauncherGui\) \|\| !DllCall\("user32\\IsWindowVisible"' 'automatic update preview uses valid native visibility check'
if ($source.Contains('"user32\\\\IsWindowVisible"')) { throw 'Automatic preview must not use a doubled Win32 function separator.' }
if ($source.Contains('LauncherUpdateButton')) { throw 'Long update buttons must not replace the footer version.' }
# The badge preview must be injected into the actual launcher window only when
# it was explicitly launched with a test flag. Real settings, live update feeds,
# and publishing logic remain untouched.
$badgeHarness = Get-Content -LiteralPath 'scripts/launcher-smoke-tests.ahk' -Raw -Encoding UTF8
$bootstrapSource = Get-Content -LiteralPath 'src/app/bootstrap.ahk' -Raw -Encoding UTF8
$badgeHelper = Get-Content -LiteralPath 'scripts/test-update-badge.ps1' -Raw -Encoding UTF8
if (!$badgeHarness.Contains('case "--test-update-badge":') -or
    !$badgeHarness.Contains('LauncherBadgeTestMode := true') -or
    $badgeHarness.Contains('PreviewUpdateBadgeFixture()') -or
    !$bootstrapSource.Contains('LauncherGui.Title := A_IconTip " [Badge Test]"') -or
    !$bootstrapSource.Contains('LauncherBadgeTestWindowHwnd := LauncherGui.Hwnd') -or
    !$bootstrapSource.Contains('OnMessage(0x8041, HandleLauncherBadgeTestMessage)') -or
    !$bootstrapSource.Contains('if !LauncherBadgeTestMode') -or
    !$source.Contains('HandleLauncherBadgeTestMessage(state, unused, msg, hwnd)') -or
    !$source.Contains('hwnd != LauncherBadgeTestWindowHwnd') -or
    $source.Contains('hwnd != LauncherGui.Hwnd') -or
    !$source.Contains('LauncherBadgeTestState := "unread"') -or
    !$source.Contains('LauncherBadgeTestState := "viewed"') -or
    !$source.Contains('LauncherBadgeTestState := "none"') -or
    !$source.Contains('unseen := LauncherBadgeTestMode ? LauncherBadgeTestState = "unread"') -or
    !$badgeHelper.Contains('SendMessageTimeout(') -or
    !$badgeHelper.Contains('FindWindow(') -or
    !$badgeHelper.Contains('0x8041') -or
    !$badgeHelper.Contains('Badge Test]') -or
    $badgeHelper.Contains('Set-Content ') -or
    $badgeHelper.Contains('Start-Process ') -or
    $badgeHelper.Contains('Invoke-WebRequest ')) {
    throw 'Live badge test must target only the opted-in launcher without changing files or the update feed.'
}
Write-Host 'PASS: PowerShell cosmetic badge injection targets only the real, opted-in launcher.'

# Exercise the real history dialog with synthetic, local-only content.
$historyHelper = Get-Content -LiteralPath 'scripts/test-update-history.ps1' -Raw -Encoding UTF8
if (!$bootstrapSource.Contains('OnMessage(0x8042, HandleLauncherHistoryTestMessage)') -or
    !$source.Contains('HandleLauncherHistoryTestMessage(scenario, unused, msg, hwnd)') -or
    !$source.Contains('SetTimer(ShowLauncherHistoryTestPreview.Bind(scenario), -1)') -or
    !$source.Contains('ShowUpdatePreview(installed, latest, "alpha", kind,') -or
    !$source.Contains('features := "No new feature releases since your installed version."') -or
    !$dialogSource.Contains('ShowUpdatePreview(installedVersion, latestVersion, channel, kind, testHistory := 0)') -or
    !$dialogSource.Contains('history := synthetic ? testHistory : ReadPublishedUpdateHistory(installedVersion, latestVersion)') -or
    !$dialogSource.Contains('if synthetic') -or
    !$dialogSource.Contains('MsgBox("Update downloads are disabled for this preview."') -or
    !$dialogSource.Contains('AddStyledButton(preview, 32, 568, 185, 34, "Update Now"') -or
    !$dialogSource.Contains('AddStyledButton(preview, 233, 568, 155, 34, "Not Now"') -or
    $dialogSource.Contains('TEST DATA ONLY') -or
    !$historyHelper.Contains('SendMessageTimeout(') -or
    !$historyHelper.Contains('FindWindow(') -or
    !$historyHelper.Contains('0x8042') -or
    !$historyHelper.Contains('Badge Test]') -or
    !$historyHelper.Contains("ValidateSet('Missed', 'Hotfix')") -or
    $historyHelper -match '(?i)(Set-Content|Copy-Item|Remove-Item|Invoke-WebRequest|Start-Process)\s') {
    throw 'Synthetic history preview must stay opt-in, preserve the real history reader, and disable all downloads.'
}
Write-Host 'PASS: real update preview supports safe missed-release and hotfix-only test data.'


Require-Source 'AddUpdateNoteTabs\(preview, history\.Release, history\.Hotfix' 'missed changes use separate feature and hotfix tabs' $dialogSource
Require-Source 'switcher\.Update := updateNotes' 'tab switch updates scrollable viewport' $notesSource
Require-Source 'Loop capacity - 1' 'switching from short to long notes fills the viewport' $notesSource



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
