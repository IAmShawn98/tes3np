param(
    [string]$SourcePath = 'src/app/update-check.ahk'
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
$metadata = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $SourcePath) 'update-metadata.ahk') -Raw -Encoding UTF8
$installSource = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $SourcePath) 'update-install.ahk') -Raw -Encoding UTF8
$dialogSource = Get-Content -LiteralPath 'src/ui/update-dialogs.ahk' -Raw -Encoding UTF8
$notesSource = Get-Content -LiteralPath 'src/ui/update-notes.ahk' -Raw -Encoding UTF8
$badgeHarness = Get-Content -LiteralPath 'scripts/launcher-smoke-tests.ahk' -Raw -Encoding UTF8
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
Require-Source 'ReadPublishedCategorizedUpdateNotes\(installedVersion, latestVersion, true\)' 'update preview categorizes missed published versions' $dialogSource

# The preview must derive each version field's width from actual rendered text,
# rather than the length of the shorter feature-only test version. The optional
# second metadata row reflows the notes, actions and gold frame as one unit.
Require-Source 'preview := CreateGoldNativePrompt\(0, "tes3np \u2014 Update Preview",\s*600, 556 \+ notesSpace \+ missedSpace\)' 'preview allocates real extra history height only when releases were missed' $dialogSource
Require-Source 'missedSpace := hasMissed \? 64 : 0' 'history has measured room without shrinking the upper changelog' $dialogSource
Require-Source 'notesSpace := 100' 'upper changelog is taller without overlapping earlier updates' $dialogSource
Require-Source 'scale := Min\(GetOwnedMenuScale\(\), GetUpdatePromptFitScale\(preview\)\)' 'production popup uses actual launcher scale rather than an 81.5% miniature' $dialogSource
Require-Source 'AddUpdatePreviewMetadata\(preview, installedVersion, latestVersion, channel, true\)' 'both update types use the compact measured metadata card' $dialogSource
Require-Source 'AddUpdatePreviewMetadata\(panel, installedVersion, latestVersion, channel, compact := false\)' 'legacy metadata geometry remains testable' $dialogSource
Require-Source 'if compact\s+return AddCompactUpdatePreviewMetadata\(panel, installedVersion, latestVersion, channel\)' 'compact preview uses its own reference-styled renderer' $dialogSource
Require-Source 'sideLeft := 48' 'metadata retains 28px left frame padding' $dialogSource
Require-Source 'sideRight := 552' 'metadata retains 28px right frame padding' $dialogSource
Require-Source 'startX := Round\(\(600 - fullWidth\) / 2\)' 'three compact fields remain centered as one group' $dialogSource
Require-Source 'for fontSize in \[9, 8, 7, 6\]' 'compact metadata measures fonts before reflowing' $dialogSource
Require-Source 'probe.SetFont\("s" fontSize " Bold cE7BE70", "Segoe UI"\)' 'reference label measurement uses gold bold typography' $dialogSource
Require-Source 'probe.SetFont\("s" fontSize " Norm cFFF0DC", "Segoe UI"\)' 'reference value measurement uses pale ivory typography' $dialogSource
Require-Source 'panel.SetFont\("s" compactFontSize " Bold cE7BE70", "Segoe UI"\)' 'only Installed, Latest and Channel prefixes are gold' $dialogSource
Require-Source 'panel.SetFont\("s" compactFontSize " Norm cFFF0DC", "Segoe UI"\)' 'version and channel values remain ivory' $dialogSource
Require-Source '\{Label: "Installed:", Value: "v" installedVersion\}' 'Installed label stays separate from its value' $dialogSource
Require-Source '\{Label: "Latest:", Value: "v" latestVersion\}' 'Latest label stays separate from its value' $dialogSource
Require-Source '\{Label: "Channel:", Value: channelName\}' 'Channel label stays separate from its value' $dialogSource
Require-Source 'gap := 24' 'compact metadata has reference-sized divider gaps' $dialogSource
Require-Source 'measuredWidth <= availableWidth' 'metadata chooses the font size based on actual available ribbon width' $dialogSource
Require-Source 'PositionCompactMetadataPair\(pairs\[3\], channelX, 61\)' 'standard metadata uses one centered line' $dialogSource
Require-Source 'PositionCompactMetadataPair\(pairs\[3\], Round\(\(600 - pairs\[3\]\.Width\) / 2\), 93\)' 'long channel metadata can wrap cleanly onto a second row' $dialogSource
Require-Source 'pair.Value.Move\(x \+ pair.LabelWidth \+ 3, y, pair.ValueWidth, 26\)' 'label/value pairs preserve a measured 3px internal gap' $dialogSource
Require-Source 'installed.GetPos\(, , &installedWidth\)' 'legacy installed field still measures its natural width' $dialogSource
Require-Source 'latest.GetPos\(, , &latestWidth\)' 'legacy latest field still measures its natural width' $dialogSource
Require-Source 'channelText.GetPos\(, , &channelWidth\)' 'legacy channel field still measures its natural width' $dialogSource
Require-Source 'installed.Move\(, , installedWidth, 26\)' 'legacy installed field sets its height after measuring' $dialogSource
Require-Source 'latest.Move\(, , latestWidth, 26\)' 'legacy latest field sets its height after measuring' $dialogSource
Require-Source 'channelText.Move\(, , channelWidth, 26\)' 'legacy channel field sets its height after measuring' $dialogSource
Require-Source 'if channelX \+ channelWidth <= rightEdge' 'legacy metadata remains dynamically measured' $dialogSource
Require-Source 'channelText.Move\(baseX, labelY \+ 32\)' 'legacy metadata can reflow onto a second row' $dialogSource
Require-Source 'channelText.Move\(baseX, labelY \+ 64\)' 'legacy metadata can reflow onto a third row' $dialogSource
Require-Source 'metadataBorder.Move\(, , , 40 \+ rowExtra\)' 'gold metadata border retains vertical padding with wrapped versions' $dialogSource
Require-Source 'GrowGoldNativePrompt\(preview, rowExtra\)' 'compact dialog grows if longer versions require rows' $dialogSource
Require-Source '"Changes in This Update"' 'preview retains its established player-facing heading' $dialogSource
Require-Source 'preview.Add\("Text", "x20 y" \(131 \+ rowExtra\) " w560 h" \(365 \+ notesSpace \+ missedSpace\) " BackgroundC5A45C"\)' 'gold frame grows with measured history content without clipping' $dialogSource
Require-Source 'preview.Add\("Text", "x40 y" \(312 \+ rowExtra \+ notesSpace\) " w520 h2 BackgroundC5A45C"\)' 'pinned earlier updates divider follows the full-height notes' $dialogSource
Require-Source '"Updates You Missed"' 'pinned history uses the approved player-facing heading' $dialogSource
Require-Source 'missedVersions := notes.HasOwnProp\("MissedVersions"\) \? notes.MissedVersions : \[\]' 'published preview reads every missed release' $dialogSource
Require-Source 'hasMissed := missedVersions.Length > 0' 'history stays absent when no versions are missed' $dialogSource
Require-Source 'AddUpdateNotesViewport\(preview, notes.Latest, scale,' 'latest changelog keeps its own scrollable viewport' $dialogSource
Require-Source '0, rowExtra, notesSpace, true, true, hasMissed\)' 'latest notes stop above the pinned missed history' $dialogSource
Require-Source 'AddMissedUpdateLinks\(preview, missedVersions, scale,\s*rowExtra, notesSpace, missedHeading, 0, previewState\)' 'pinned missed releases use the measured heading to bound their viewport' $dialogSource
Require-Source 'missedHeading := preview.Add\("Text", "x40 y" \(324 \+ rowExtra \+ notesSpace\)' 'the real missing-updates heading is retained for clipping tests' $dialogSource
Require-Source '" w520 h28 BackgroundTrans", "Updates You Missed"\)' 'the full Georgia heading has room for native glyph descenders' $dialogSource
Require-Source 'link.OnEvent\("Click", OpenMissedUpdateVersion.Bind\(page, slot\)\)' 'each missed version hyperlink resolves from its current scroll row' $dialogSource
Require-Source 'badge.OnEvent\("Click", OpenMissedUpdateVersion.Bind\(page, slot\)\)' 'red (1) markers also open their associated GitHub changelog' $dialogSource
Require-Source 'badges.Push\(badge\)' 'every visible missed version has its own red number one' $dialogSource
Require-Source 'MeasureMissedUpdateTextWidth\(row, caption\)' 'small red markers sit after actual measured version text' $dialogSource
Require-Source 'badge.Visible := !IsMissedUpdateRead\(page, item\)' 'only visible version rows show a red one' $dialogSource
Require-Source 'scrolling := page.MaxOffset > 1' 'missed-update scrollbar appears only when rows overflow' $dialogSource
Require-Source 'for slot in \[1, 2, 3, 4\]' 'four missed updates appear together at normal scale' $dialogSource
Require-Source 'observer.RowHeight := rowHeight' 'native smoke reports measured row height when four entries cannot fit' $dialogSource
Require-Source 'observer.BottomLimit := bottomLimit' 'native smoke reports history list lower bound on layout regressions' $dialogSource
Require-Source 'up := AddStyledButton\(panel, arrowX, arrowTop, px\(20\), px\(22\),' 'missed-version scroll uses the parent gold up arrow' $dialogSource
Require-Source 'down := AddStyledButton\(panel, arrowX, arrowBottom, px\(20\), px\(22\),' 'missed-version scroll uses the parent gold down arrow' $dialogSource
Require-Source 'badge := panel.Add\("Picture", "Hidden x0 y0 w" px\(20\) " h" px\(20\)' 'missed release badges match the 20px latest hotfix badge' $dialogSource
Require-Source 'prefix.Text := prefixText' 'gold demo prefix remains separate from white version text' $dialogSource
Require-Source 'Underline cFFF0DC' 'published release links appear ivory/white and underlined' $dialogSource
Require-Source 'preview.Add\("Text", "x40 y" \(354 \+ rowExtra \+ notesSpace\)' 'thin gold divider separates Updates You Missed from the list' $dialogSource
Require-Source 'page.Total - page.VisibleRows \+ 1' 'scrolling includes Clear as a final item' $dialogSource
Require-Source 'clearButton := AddStyledButton\(panel, px\(34\), markReadY, px\(118\), px\(26\),' 'Mark Read stays visible in a fixed footer below the list' $dialogSource
Require-Source '"Mark Read", ClearMissedUpdateBadges.Bind\(page\)' 'bulk action is explicitly labeled Mark Read' $dialogSource
Require-Source 'markReadY := px\(528 \+ topExtra \+ bottomExtra\)' 'fixed Mark Read button stays in the lower-left corner' $dialogSource
Require-Source 'ClearMissedUpdateBadges\(page, \*\)' 'Mark Read still marks all missed versions read without removing history' $dialogSource
Require-Source 'scrollExpected := count > observer.Page.VisibleRows' 'native smoke excludes fixed Mark Read from scroll count' $badgeHarness
Require-Source 'observer.Clear.Visible \|\| scrolledClearY != originalClearY' 'native smoke rejects Mark Read moving or disappearing during scrolling' $badgeHarness
Require-Source 'Total: versions.Length, MaxOffset: 1' 'scroll offsets include only release entries, never the Mark Read button' $dialogSource
Require-Source 'ClearMissedUpdateBadges\(page, \*\)' 'Clear marks all listed versions read without deleting entries' $dialogSource
Require-Source 'MarkMissedUpdateItemRead\(page, item\)' 'clicking one release marks only that version read' $dialogSource
Require-Source 'SetLauncherDemoUnreadCount\(count\)' 'demo feedback changes footer count without persistent writes' $dialogSource
Require-Source 'MarkPublishedVersionRead\(latestVersion, true\)' 'opening real popup clears only the offered update' $dialogSource
Require-Source 'IsPublishedVersionRead\(version\)' 'real per-version read state can be checked independently' $source
Require-Source 'IniRead\(path, "ReadPublishedVersions", version, ""\)' 'read receipts are loaded from durable per-version INI keys' $source
Require-Source 'fixturePath != "" \? fixturePath : DataFile' 'INI regression can use disposable paths without modifying user settings' $source
Require-Source 'MarkPublishedVersionRead\("0\.1\.21-alpha\.4", true, fixture\)' 'native test marks only offered version read in temporary INI' $badgeHarness
Require-Source 'IsPublishedVersionRead\("0\.1\.21-alpha\.3", fixture\)' 'native test ensures older versions stay unread' $badgeHarness
Require-Source 'if offered\s*IniWrite\(version, path, "Updates", "LastAutoPreviewVersion"\)' 'automatic preview dedup remains limited to offered version' $source
Require-Source 'rowTop := px\(356 \+ topExtra \+ bottomExtra\)' 'version links begin beneath the complete heading' $dialogSource
Require-Source 'heading.GetPos\(, &headingY, , &headingHeight\)' 'viewport positions against actual scaled heading bounds' $dialogSource
Require-Source 'rowTop := Max\(rowTop, headingY \+ headingHeight \+ Max\(2, px\(4\)\)\)' 'list background cannot cover the end of the heading' $dialogSource
Require-Source '" h" \(bottomLimit - rowTop\) " Background171008"' 'opaque history background stops before the gold card border' $dialogSource
Require-Source 'rowHeight := px\(29\)' 'missed-update links initially reserve 29px to avoid font clipping' $dialogSource
Require-Source 'rowHeight := Max\(rowHeight, ReleaseNoteLineHeight\(link\) \+ px\(8\)\)' 'native font metrics enlarge rows when Windows requires more glyph room' $dialogSource
Require-Source 'rowStep := px\(24\)' 'missed-update rows retain compact and consistent spacing' $dialogSource
Require-Source 'rowStep := Max\(rowStep, rowHeight \+ Max\(1, px\(2\)\)\)' 'missed-update link controls never overlap and erase neighboring glyphs' $dialogSource
Require-Source 'bottomLimit := px\(522 \+ topExtra \+ bottomExtra\)' 'missed-version viewport ends above reserved Mark Read footer' $dialogSource
Require-Source 'page.VisibleRows := Max\(1, Min\(4,' 'oversized font uses fewer rows with scroll rather than truncation' $dialogSource
Require-Source 'page.MaxOffset := Max\(1, page.Total - page.VisibleRows \+ 1\)' 'hidden missed versions remain reachable via scroll' $dialogSource
Require-Source 'Run\(expected\)' 'published changelogs open their exact GitHub release in a browser' $dialogSource
Require-Source '"https://github.com/IAmShawn98/tes3np/releases/tag/v" version' 'hyperlink destination is locked to release tags in the official repository' $dialogSource
Require-Source 'MissedVersions: missedVersions' 'list includes the newest missed version and every older missed version' $notesSource
Require-Source 'Url: "https://github.com/IAmShawn98/tes3np/releases/tag/v" record.Version' 'links derive from verified published history' $notesSource
Require-Source 'A_ScriptDir "\\assets\\controls\\update-badge\.png"' 'update preview uses a true transparent circular badge bitmap' $dialogSource
if (!(Test-Path -LiteralPath 'assets/controls/update-unread-circle.png' -PathType Leaf)) { throw 'Unnumbered circular footer artwork is missing.' }
if (!(Get-Content -LiteralPath 'scripts/generate-bundled-resources.py' -Raw).Contains('"assets/controls/update-unread-circle.png"')) { throw 'Standalone build must embed blank circular unread artwork.' }
if (!(Test-Path -LiteralPath 'assets/controls/update-badge.png' -PathType Leaf)) {
    throw 'Transparent circular update badge artwork is missing.'
}
if (!(Get-Content -LiteralPath 'scripts/generate-bundled-resources.py' -Raw).Contains('"assets/controls/update-badge.png"')) {
    throw 'Standalone launcher build must include its circular notification artwork.'
}
Require-Source 'actionY := 511 \+ rowExtra \+ notesSpace \+ missedSpace' 'production action buttons move beneath expanded history' $dialogSource
Require-Source 'AddStyledButton\(preview, 109, actionY, 181, 34, "Update Now"' 'update button is centered under the card' $dialogSource
Require-Source 'AddStyledButton\(preview, 313, actionY, 181, 34, "Not Now"' 'Not Now is centered beside Update Now' $dialogSource
Require-Source 'response.Download := true, DestroyScaledMenu\(preview\)' 'production updater still enters its confirmation flow' $dialogSource
Require-Source 'AddUpdateNotesViewport\(panel, releaseNotes, scale\)' 'installed Version Status stays unchanged' $dialogSource
Require-Source 'BuildPublishedPreviewSections\(records\)' 'preview data comes only from the published version parser' $notesSource
Require-Source 'EarlierLabels: earlierLabels' 'published missed versions are retained in the pinned summary' $notesSource
Require-Source 'compactLayout := false, fixedEarlier := false\)' 'preview-only compact notes layout leaves installed status unaffected' $notesSource
Require-Source 'viewX := compactLayout \? 23 : 28' 'compact scroll hit area does not cover the outer gold frame' $notesSource
Require-Source 'viewY := compactLayout \? 168 \+ topExtra : 158 \+ topExtra' 'scroll hit area clears latest-hotfix heading' $notesSource

$previewStart = $dialogSource.IndexOf('ShowUpdatePreview(installedVersion')
$metadataStart = $dialogSource.IndexOf('AddUpdatePreviewMetadata(panel, installedVersion')
$statusStart = $dialogSource.IndexOf('ShowUpdateStatusPanel(mode, installedVersion')
if ($previewStart -lt 0 -or $metadataStart -le $previewStart -or $statusStart -le $metadataStart) {
    throw 'Preview, metadata and installed Version Status must remain separate production functions.'
}
$previewPath = $dialogSource.Substring($previewStart, $metadataStart - $previewStart)
if (!$previewPath.Contains('ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion, true)') -or
    !$previewPath.Contains('notes.HasOwnProp("MissedVersions")') -or
    $previewPath.Contains('AddUpdateNoteTabs(') -or
    $previewPath.Contains('history.Hotfix') -or
    $previewPath.Contains('history.Release')) {
    throw 'Preview must use real missed published changes in one compact gold modal.'
}
$smokeSource = Get-Content -LiteralPath 'scripts/launcher-smoke-tests.ahk' -Raw -Encoding UTF8
if (!$smokeSource.Contains('CheckUpdatePreviewMetadataLayout()') -or
    !$smokeSource.Contains('Update preview metadata overlaps at this version length.') -or
    !$smokeSource.Contains('1.0.0-live.100')) {
    throw 'Windows regression must verify measured version labels, wrapping, and clipping.'
}
if ($dialogSource.Contains('x123 y80 w147 h26') -or
    $dialogSource.Contains('Review the changes you have missed before deciding to update.') -or
    $dialogSource.Contains('TEST DATA ONLY') -or
    $dialogSource.Contains('"Close Test Preview"')) {
    throw 'Temporary copy or fixed-size version captions must not enter the production dialog.'
}
if ((14 + 31) -ge 53 -or (61 + 26) -ge 96 -or
    (96 + 30) -ge 131 -or (131 + 365 + 100) -ge (511 + 100) -or
    (511 + 100 + 34) -ge (556 + 100)) {
    throw 'Compact preview frame overlaps title, metadata, notes, or footer controls.'
}
Write-Host 'PASS: compact preview, pinned missed-version links and fixed scroll bounds match reference layout.'
if ($dialogSource.Contains('"Continue to Download"') -or
    $dialogSource.Contains('AddStyledButton(preview, 590, 568, 178, 34, "GitHub Release"')) {
    throw 'Preview footer must retain only the two established update choices.'
}
Write-Host 'PASS: Update Now and Not Now remain confirmation-gated and centered.'
$bootstrapSource = Get-Content -LiteralPath 'src/app/bootstrap.ahk' -Raw -Encoding UTF8
Require-Source 'if A_Args.Length \|\| !RegExMatch\(AppConfig.Version' 'pre-publication review runs only on ordinary startup with a hotfix draft' $bootstrapSource
Require-Source 'FileExist\(checkoutRoot "\\.git"\)' 'unreleased review only works in a development checkout' $bootstrapSource
Require-Source 'ReadBundledVersionNotes\(AppConfig.Version\) != ""' 'startup preview requires locally existing unreleased notes' $bootstrapSource
Require-Source 'ReadBundledVersionNotes\(version\)' 'review uses actual drafted RELEASE_NOTES rather than fake hotfixes' $bootstrapSource
Require-Source 'draftSections := BuildPublishedPreviewSections\(\[record\]\)' 'development preview uses the genuine single draft record' $bootstrapSource
Require-Source 'Loop 24' 'development preview includes twenty-four scrolling stress entries' $bootstrapSource
Require-Source 'demoVersion := Mod\(A_Index, 2\) \? "0.1.21-alpha" : "0.1.20-alpha"' 'demo repeats two actually published release tags rather than inventing nonexistent pages' $bootstrapSource
Require-Source 'Url: GetTes3npReleasePage\(demoVersion\)' 'all demo entries open the correct GitHub page for the displayed version' $bootstrapSource
Require-Source 'draftSections.MissedVersions := demoRows' 'mock history exists only inside the gated development review' $bootstrapSource
Require-Source 'ShowDevelopmentUnreadBadgeSample\(25\)' 'demo starts with 24 older entries plus one currently offered unread version' $bootstrapSource
Require-Source 'draftSections.DemoMode := true' 'demo reads current version without altering persisted player update state' $bootstrapSource
Require-Source 'ShowUpdatePreview\(GetTes3npOriginalVersion\(version\), version,' 'review invokes the real production update dialog' $bootstrapSource
Require-Source 'BuildPublishedPreviewSections\(\[record\]\)' 'review uses the real production notes parser' $bootstrapSource
if (Test-Path 'scripts/test-update-preview-visual.ps1') {
    throw 'Retired standalone fake-history visual test still exists.'
}
Write-Host 'PASS: real production dialog auto-opens only at a source-checkout startup; fake visual fixture removed.'

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
if (!$previewPath.Contains('ReadPublishedCategorizedUpdateNotes(installedVersion, latestVersion, true)') -or
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
if ((20 + 42) -ge 74 -or (80 + 26) -ge 118 -or
    (118 + 30) -ge 161 -or (161 + 30) -ge (158 + 44) -or
    (158 + 367 + 28) -ge 568 -or (568 + 34) -ge 620) {
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
Require-Source 'case "Bug Fixes", "Fixed", "Hotfixes":' 'legacy Hotfixes sections render under Bug Fixes' $notesSource
Require-Source 'return "Bug Fixes"' 'hotfix fixes use the normal Bug Fixes category' $notesSource
Require-Source 'InStr\(stacked, "### Hotfixes"\)' 'compiled smoke forbids a redundant Hotfixes category' $badgeHarness
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
Require-Source 'BuildStyledReleaseNoteRows\(notes, sample, width - Max\(2, px\(10\)\), premium, compactLayout, scale\)' 'font-measured changelog wrapping uses the scaled width' $notesSource
Require-Source 'UpdateNoteFontFace\(kind, premium := false\)' 'preview-only serif headings preserve status styling' $notesSource
Require-Source 'UpdateNoteFont\(kind, premium := false, compact := false, scale := 1.0\)' 'compact and status font paths remain separate' $notesSource
Require-Source 'if compactLayout' 'compact preview hides arrows when no scrolling is required' $notesSource
Require-Source 'row.SetFont\("s" Max\(4, Round\(10 \* scale\)\)' 'missed release links use measured compact text' $dialogSource
Require-Source 'scale := Min\(GetOwnedMenuScale\(\), GetUpdatePromptFitScale\(preview\)\)' 'full production update popup retains owner scale instead of miniature rendering' $dialogSource
Require-Source 'bottomY := px\(compactLayout \? \(fixedEarlier \? 309 : 480\)' 'latest notes end before the taller missed-version list' $notesSource
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

# The installed version stays visible. The footer displays the exact count
# of new published releases since the last preview, then clears on viewing.
Require-Source 'CreateLauncherUpdateBadge\(\)' 'compact unread update indicator exists'
Require-Source 'LauncherUpdateBadge := LauncherGui.Add\("Picture",' 'footer notification uses transparent circular artwork instead of rectangular text background' $source
Require-Source 'update-unread-circle\.png' 'footer uses a blank alpha circle, not a bitmap with an embedded numeral' $source
Require-Source 'LauncherUpdateBadge.Value := "\*w" bitmapPixels " \*h" bitmapPixels' 'badge image is explicitly resized before its final control bounds' $source
Require-Source 'LauncherUpdateNumber.OnEvent\("Click", CheckForUpdates\)' 'number overlay remains clickable like its circular backdrop' $source
Require-Source 'LauncherUpdateNumber.SetFont\("s" size " Bold cFFFFFF", "Segoe UI"\)' 'number overlay stays white at saved launcher scale' $source
Require-Source 'ShapeCircularUpdateBadge\(LauncherUpdateBadge\)' 'badge shape is updated at launcher scaling'
Require-Source 'CreateEllipticRgn' 'native circle is drawn rather than parentheses'
Require-Source 'size := Max\(4, Round\(8 \* scale / GetLauncherBadgeDpiScale\(\)\)\)' 'badge numeral accounts for physical DPI and launcher scale'
Require-Source 'SetLauncherUnreadBadgeNumber\(LauncherUpdateNumber.Text\)' 'resize of circular artwork recenters numeral at saved scale' $source
Require-Source 'LauncherVersionLabel\.Visible := true' 'installed version remains visible'
Require-Source 'LauncherUpdateBadge\.OnEvent\("Click", CheckForUpdates\)' 'red (1) opens the optional updater'

# Place the badge beside the natural-width version label and redraw the
# backing image only under its rectangle when hiding or showing it.
Require-Source 'LauncherVersionLabel := LauncherGui\.Add\("Text", "x12 y691 BackgroundTrans", "tes3np' 'version caption is measured without fixed dimensions'
Require-Source 'LauncherVersionLabel\.GetPos\(, , &naturalWidth\)' 'version caption natural width is captured'
Require-Source 'LauncherVersionLabel\.Move\(, , Ceil\(naturalWidth \* 1\.125\) \+ 4, 18\)' 'version label height applied after width measurement with 50 percent headroom'
Require-Source 'label.GetPos\(&labelX, , &labelWidth\)' 'measured badge positioning reads actual version label bounds' $source
Require-Source 'x := GetLauncherUnreadBadgeX\(LauncherVersionLabel, 1\)' 'initial badge anchors to rendered caption instead of padded label width' $source
Require-Source 'SetLauncherUnreadBadgeNumber\(unreadCount\)' 'launcher footer displays the unread number, not a fixed one'
Require-Source 'LauncherUnreadBadgeDiameter\(count, scale\)' 'multi-digit counts enlarge the diameter of a true circle'
Require-Source 'textPixels := MeasureMissedUpdateTextWidth\(label, label.Text\)' 'badge uses native GDI text width, not text-control padding' $source
Require-Source 'x := GetLauncherUnreadBadgeX\(LauncherVersionLabel, scale\)' 'badge realigns after launcher-scale changes' $source
Require-Source 'if LauncherUpdateNumber.Text = value && oldWidth = diameter[\s\S]*oldHeight = diameter && oldX = x' 'badge repositions even if count and size stay unchanged' $source
Require-Source 'CheckUnreadBadgeTextAdjacency\(\)' 'native test checks gap after rendered text at 50 and 100 percent' $badgeHarness
Require-Source 'screenGap := Round\(\(badgeX - labelX\) \* dpi - textPixels\)' 'native smoke measures actual text-to-badge separation' $badgeHarness
Require-Source 'GetDpiForWindow' 'badge size is calibrated from actual Windows DPI' $source
Require-Source 'ReleaseNoteFits\(LauncherUpdateNumber, LauncherUpdateNumber.Text,' 'numeric badge checks actual rendered digit width' $source
Require-Source 'ReleaseNoteLineHeight\(LauncherUpdateNumber\) <= availableHeight' 'numeric badge shrinks font before vertical clipping' $source
Require-Source 'innerWidth := Max\(1, Round\(diameter \* 0\.72\)\)' 'number inset uses the largest safe width inside the circle' $source
Require-Source 'x" x " y689 w22 h22 \+0x40 BackgroundTrans' 'Picture control scales the circular bitmap to fit its resized bounds' $source
Require-Source 'if width > 30' 'native GUI smoke rejects oversized circles while permitting 27 pixels' $badgeHarness
Require-Source 'badge := panel.Add\("Picture"' 'smoke tests the real Picture renderer, not a surrogate Text control' $badgeHarness
Require-Source 'assetRoot := A_IsCompiled \? BundledResourceRoot : A_ScriptDir' 'compiled GUI smoke reads the extracted resource root' $badgeHarness
Require-Source 'badgeAsset := assetRoot "\\assets\\controls\\update-unread-circle\.png"' 'badge smoke loads its PNG from the runtime asset folder' $badgeHarness
Require-Source 'if !FileExist\(badgeAsset\)' 'native smoke diagnoses missing bundled badge art before creating a Picture' $badgeHarness
Require-Source 'badgeAsset\)' 'native smoke uses the verified PNG path when adding its Picture control' $badgeHarness
Require-Source 'physical := Max\(16, Round\(\(21 \+ 6 \* \(digits - 1\)\) \* scale\)\)' 'two-digit footer circle targets 27 physical pixels, slightly larger than previous 23' $source
Require-Source 'LauncherUpdateBadge.Move\(x, centeredY, diameter, diameter\)' 'numeric badge remains square in geometry and round in rendering' $source
Require-Source 'region := DllCall\("gdi32\\CreateEllipticRgn"' 'unread notification always uses a clipped circle'
Require-Source 'StartLauncherUnreadReleaseCount\(AppConfig.Version, manifest.version\)' 'startup counts actual published releases asynchronously'
Require-Source 'Run\(command, A_ScriptDir, "Hide", &pid\)' 'published release count uses a hidden worker rather than blocking the GUI'
Require-Source 'CountUnseenPublishedUpdateRecords\(records, job.Installed\)' 'published history counts per-version receipts rather than a cumulative cutoff' $source
Require-Source 'GetLauncherUpdateKind\(installed, version\) = ""' 'unread tally excludes installed release and deduplicates records' $source
Require-Source 'if LauncherObservedUpdateVersion = job.Latest' 'stale background results do not override a different offered version' $source
Require-Source 'CheckUnreadPublishedReleaseCounts\(\)' 'compiled smoke verifies unread count increases and clears correctly' $badgeHarness
Require-Source 'if wasVisible[\s\S]*LauncherUpdateBadge\.Visible := false[\s\S]*RedrawLauncherUpdateBadge\(\)' 'viewing the update hides the badge and clears old pixels'
Require-Source 'if !wasVisible\s*\{\s*LauncherUpdateBadge.Visible := true\s*LauncherUpdateNumber.Visible := true\s*RedrawLauncherUpdateBadge\(\)' 'both circular art and numeral become visible together' $source
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
Write-Host 'PASS: numeric unread badge follows published missed versions, clears on preview, and repaints cleanly.'

# The automatic preview is reached only when a newer published version appears.
# Validate the actual Win32 function name; a doubled backslash is not a DLL entry point.
Require-Source 'if !IsObject\(LauncherGui\) \|\| !DllCall\("user32\\IsWindowVisible"' 'automatic update preview uses valid native visibility check'
if ($source.Contains('"user32\\\\IsWindowVisible"')) { throw 'Automatic preview must not use a doubled Win32 function separator.' }
if ($source.Contains('LauncherUpdateButton')) { throw 'Long update buttons must not replace the footer version.' }
# Check the production code path after temporary injection tooling is removed.
# These assertions remain useful build regressions, not a runtime test mode.
$bootstrapSource = Get-Content -LiteralPath 'src/app/bootstrap.ahk' -Raw -Encoding UTF8
Require-Source 'available := isAvailable && latestVersion != "" && unreadCount > 0' 'older unread releases keep the footer count after offered version is read' $source
Require-Source 'IniWrite\("1", path, "ReadPublishedVersions", version\)' 'read receipts persist separately for each published version' $source
Require-Source 'if UpdateBusy \|\| HasSeenUpdateAutoPreview\(version\)' 'previously viewed updates do not automatically reopen'
Require-Source 'ShowUpdatePreview\(installedVersion, latestVersion, channel, kind, reviewNotes := 0\)' 'real production modal optionally accepts checkout-only draft notes' $dialogSource
Require-Source 'history := ReadPublishedUpdateHistory\(installedVersion, latestVersion\)' 'category formatter reads only published history' $notesSource
Require-Source 'AddStyledButton\(preview, 109, actionY, 181, 34, "Update Now"' 'real Update Now remains available' $dialogSource
Require-Source 'response.Download := true, DestroyScaledMenu\(preview\)' 'Update Now enters the existing confirmation-gated updater' $dialogSource
Require-Source 'AddStyledButton\(preview, 313, actionY, 181, 34, "Not Now"' 'Not Now leaves the updater unchanged' $dialogSource
Require-Source 'SetTimer\(CheckForUpdateAvailability, -250\)' 'normal update polling starts' $bootstrapSource
Require-Source 'SetTimer\(OfferDesktopShortcutOnFirstLaunch, -1800\)' 'normal first-run prompt restored' $bootstrapSource
if ($source -match 'LauncherBadgeTest|LauncherHistoryTest|HandleLauncherHistoryTest|ShowLauncherHistoryTestPreview' -or
    $bootstrapSource -match 'LauncherBadgeTest|LauncherHistoryTest|0x8041|0x8042' -or
    $badgeHarness.Contains('--test-update-badge') -or
    $dialogSource -match 'testHistory|synthetic|TEST DATA ONLY|Update downloads are disabled for this preview') {
    throw 'Temporary manual notification/history injection code remains in production.'
}
Write-Host 'PASS: temporary manual updater preview instrumentation removed; normal updater checks preserved.'

Require-Source 'return BuildCategorizedUpdateNotes\(records\)' 'default missed published changes retain categorized formatting' $notesSource
Require-Source 'BuildPublishedPreviewSections\(records\)' 'latest-first update preview splits genuine published records' $notesSource
Require-Source 'CheckMissedUpdateLinkViewport\(\)' 'native smoke tests missed update links and scrolling' $badgeHarness
Require-Source 'Opaque missed-updates viewport covers the heading text\.' 'native layout smoke reproduces and rejects clipped Updates You Missed heading' $badgeHarness
Require-Source 'Label: items\[1\].Label " \(unreleased draft\)"' 'native smoke reproduces the clipped local draft line' $badgeHarness
Require-Source 'Missed-update Text controls overlap and may erase glyphs\.' 'native smoke checks row overlap' $badgeHarness
Require-Source 'for count in \[1, 3, 7, 24\]' 'regression covers one through twenty-four missed version rows' $badgeHarness
Require-Source 'observer.Badges.Length != 4' 'native smoke verifies all four visible rows get a full-size red one' $badgeHarness
Require-Source 'observer.Page.Offset := observer.Page.MaxOffset' 'native smoke verifies the last missed version remains reachable' $badgeHarness
Require-Source 'previewSections := BuildPublishedPreviewSections\(\[newestMissed, previousMissed, patch\]\)' 'compiled smoke covers compact and expanded missed updates' $badgeHarness
Require-Source 'CheckExpandablePublishedPreviewViewport\(\)' 'native smoke exercises expanding and collapsing the missed-update viewport' $badgeHarness
Require-Source 'switcher.Update.Call\(sections.Expanded\)' 'native smoke calls the correct AHK bound callback' $badgeHarness
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
