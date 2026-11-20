param(
    [Parameter(Mandatory)]
    [ValidatePattern('\Av(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})-alpha(\.[1-9][0-9]{0,8})?\z')]
    [string]$Tag,

    [Parameter(Mandatory)]
    [ValidatePattern('\A[0-9a-fA-F]{64}\z')]
    [string]$CandidateSha256
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$ProgressPreference = 'SilentlyContinue'
$repo = 'IAmShawn98/tes3np'
$mainRevision = $env:GITHUB_SHA
if ($env:GITHUB_REPOSITORY -cne $repo -or $env:GITHUB_REF -cne 'refs/heads/main' -or
    (git rev-parse HEAD) -cne $mainRevision -or
    (git ls-remote origin refs/heads/main) -cne "$mainRevision`trefs/heads/main") {
    throw 'Dispatch Publish Alpha from the current main commit in IAmShawn98/tes3np.'
}
if ((gh api "repos/$repo" --jq '.visibility') -cne 'public') {
    throw 'The owner must make tes3np public before publishing its downloads and feed.'
}

$work = Join-Path $env:RUNNER_TEMP "tes3np-$Tag-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $work | Out-Null
$packageName = "tes3np-$Tag-windows.zip"
$checksumName = "$packageName.sha256"
$packagePath = Join-Path $work $packageName
$checksumPath = Join-Path $work $checksumName
$manifestPath = Join-Path $work 'alpha.json'
$feedDirectory = Join-Path $work 'feed'

$release = gh release view $Tag --repo $repo --json tagName,targetCommitish,isDraft,isPrerelease,assets |
    ConvertFrom-Json
$revision = $release.targetCommitish
if ($release.tagName -cne $Tag -or $revision -cnotmatch '\A[0-9a-f]{40}\z' -or
    !$release.isPrerelease -or $release.assets.Count -ne 2 -or
    $packageName -cnotin $release.assets.name -or $checksumName -cnotin $release.assets.name) {
    throw "Stage $Tag as a prerelease draft for the full reviewed commit SHA with only the versioned ZIP and checksum."
}

if ((git merge-base $revision $mainRevision) -cne $revision) {
    throw 'The draft targets a source commit outside main.'
}
# These documentation and publish-tool paths are outside the packaged source.
$reviewPaths = @(
    'README.md',
    'docs/RELEASE-REVIEW.md',
    'docs/RELEASING.md',
    'docs/DEVELOPMENT.md',
    'docs/PATCHING.md',
    'scripts/check-release-gates.py',
    'scripts/publish-alpha.ps1',
    # Older candidates may contain documentation that has since been retired.
    'CHANGELOG.md',
    'docs/ALPHA-COMPATIBILITY-CHECKLIST.md',
    'docs/ARCHITECTURE.md',
    'docs/ASSETS.md',
    'docs/MODIFIED-TES3MP-SOURCE-PROVENANCE.md',
    'docs/ASSET-DISTRIBUTION-APPROVAL.md',
    'docs/CLEAN-WINDOWS-TEST-RESULTS.md'
)
$changed = git diff --name-only --no-renames $revision $mainRevision
if ($changed | Where-Object { $_ -cnotin $reviewPaths }) {
    throw 'Source changed after the candidate build. Build and validate a candidate from the new source.'
}

$remoteTag = @(git ls-remote origin "refs/tags/$Tag" "refs/tags/$Tag^{}")
if ($remoteTag.Count -and ($remoteTag[-1] -split "`t")[0] -cne $revision) {
    throw "$Tag already points to a different source commit."
}
gh release download $Tag --repo $repo --dir $work --pattern $packageName --pattern $checksumName

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ine $CandidateSha256 -or
    (Get-Content -LiteralPath $checksumPath -Raw).TrimEnd() -cne "$hash  $packageName") {
    throw 'The draft ZIP or checksum differs from the reviewed candidate.'
}
python scripts/check-windows-package.py $packagePath --require-console-client

# Generate metadata from the reviewed bytes and the source revision that built them.
$sourceDir = Join-Path $work 'source'
git worktree add --detach $sourceDir $revision
Push-Location -LiteralPath $sourceDir
try {
    & ./scripts/generate-update-metadata.ps1 -ChannelFeed -PackagePath $packagePath -ManifestPath $manifestPath
} finally {
    Pop-Location
}
$manifestText = (Get-Content -LiteralPath $manifestPath -Raw).Replace("`r`n", "`n")
[IO.File]::WriteAllText($manifestPath, $manifestText)
$manifest = $manifestText | ConvertFrom-Json
if ($manifest.releaseId -cne $Tag -or $manifest.channel -cne 'alpha' -or $manifest.sourceRevision -cne $revision) {
    throw 'The generated alpha manifest does not match the release tag and commit.'
}

# Start the first feed on an orphan branch. On later runs keep other channels.
$feedRef = 'refs/heads/update-feed'
if (git ls-remote origin $feedRef) {
    git fetch --no-tags origin $feedRef
    git worktree add --detach $feedDirectory FETCH_HEAD
} else {
    git worktree add --detach $feedDirectory HEAD
    git -C $feedDirectory switch --orphan update-feed
}
$feedFile = Join-Path $feedDirectory 'alpha.json'
if (Test-Path -LiteralPath $feedFile) {
    $previous = Get-Content -LiteralPath $feedFile -Raw | ConvertFrom-Json
    if ($previous.manifestVersion -ne 2 -or $previous.channel -cne 'alpha' -or
        $previous.version -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+-alpha(\.[0-9]+)?\z') {
        throw 'Existing alpha feed metadata could not be validated.'
    }
    if ([version]($previous.version -replace '-alpha') -gt [version]($manifest.version -replace '-alpha')) {
        throw 'The alpha feed already points to a newer release.'
    }
    if ($previous.version -ceq $manifest.version -and
        ($previous.package.sha256 -cne $hash -or $previous.sourceRevision -cne $revision)) {
        throw 'The alpha feed already uses this version for a different candidate.'
    }
}

if ($release.isDraft) {
    $playerNotes = Get-Content -LiteralPath 'RELEASE_NOTES.md' -Raw -Encoding UTF8
    $tagPattern = [regex]::Escape($Tag)
    $section = [regex]::Match($playerNotes, "(?ms)^##[ \t]+$tagPattern(?=[ \t]|\r?$)[^\r\n]*\r?\n(.*?)(?=^##[ \t]|\z)")
    $notes = $section.Groups[1].Value.Trim()
    if (!$notes) { throw "No RELEASE_NOTES.md content found for $Tag." }
    # Published base and earlier hotfix notes are immutable. Each hotfix
    # adds its own section without replacing any prior public changelog.
    $hotfix = [regex]::Match($Tag, '\.([1-9][0-9]{0,8})$')
    if ($hotfix.Success) {
        $baseTag = $Tag.Substring(0, $Tag.Length - $hotfix.Length)
        $previousCount = [int]$hotfix.Groups[1].Value
        if ($previousCount -gt 100) { throw 'Too many hotfix entries to verify safely.' }
        for ($number = 0; $number -lt $previousCount; $number++) {
            $requiredTag = if ($number -eq 0) { $baseTag } else { "$baseTag.$number" }
            $requiredPattern = [regex]::Escape($requiredTag)
            $historical = [regex]::Match($playerNotes,
                "(?ms)^##[ \t]+$requiredPattern(?=[ \t]|\r?$)[^\r\n]*\r?\n(.*?)(?=^##[ \t]|\z)")
            if (!$historical.Success -or !$historical.Groups[1].Value.Trim()) {
                throw "Hotfix $Tag must retain the complete $requiredTag changelog."
            }
            $published = gh release view $requiredTag --repo $repo --json tagName,isDraft,body | ConvertFrom-Json
            if ($published.tagName -cne $requiredTag -or $published.isDraft) {
                throw "Previous release $requiredTag is not published."
            }
            $publishedBody = ([string]$published.body) -replace '\r\n', [string][char]10
            $indexStart = '<!-- TES3NP HOTFIX HISTORY START -->'
            $indexEnd = '<!-- TES3NP HOTFIX HISTORY END -->'
            if ($number -eq 0 -and ($publishedBody.Contains($indexStart) -or
                $publishedBody.Contains($indexEnd))) {
                $protectedSuffix = [regex]::Match($publishedBody,
                    '(?s)\n\n<!-- TES3NP HOTFIX HISTORY START -->\n### Published Hotfixes\n\n.*?\n<!-- TES3NP HOTFIX HISTORY END -->\s*\z')
                if (!$protectedSuffix.Success) {
                    throw "Published $requiredTag has an unexpected hotfix history format."
                }
                $publishedBody = $publishedBody.Substring(0, $protectedSuffix.Index)
            }
            $publishedBody = ($publishedBody -replace "(?m)^##[ \t]+$requiredPattern(?:[ \t]+[^\r\n]*)?[ \t]*\n", '').Trim()
            $localBody = ($historical.Groups[1].Value -replace '\r\n', [string][char]10).Trim()
            if ($publishedBody -cne $localBody) {
                throw "Published changelog $requiredTag was changed. Preserve the exact historical notes."
            }
        }
    }
    $notesFile = Join-Path $work 'release-notes.md'
    [IO.File]::WriteAllText($notesFile, "## $Tag`n`n$notes`n")
    gh release edit $Tag --repo $repo --draft=false --prerelease --latest=false --notes-file $notesFile
}
$publishedTag = @(git ls-remote origin "refs/tags/$Tag" "refs/tags/$Tag^{}")
if (!$publishedTag.Count -or ($publishedTag[-1] -split "`t")[0] -cne $revision) {
    throw 'Published tag does not point to the reviewed commit.'
}

# Verify the files at the same unsigned URLs players use before updating the feed.
$base = "https://github.com/$repo/releases/download/$Tag"
$publicZip = Join-Path $work 'public.zip'
$publicChecksum = Join-Path $work 'public.sha256'
Invoke-WebRequest "$base/$packageName" -OutFile $publicZip -MaximumRetryCount 3 -RetryIntervalSec 2
Invoke-WebRequest "$base/$checksumName" -OutFile $publicChecksum -MaximumRetryCount 3 -RetryIntervalSec 2
if ((Get-FileHash -LiteralPath $publicZip -Algorithm SHA256).Hash -ine $hash -or
    (Get-Content -LiteralPath $publicChecksum -Raw).TrimEnd() -cne "$hash  $packageName") {
    throw 'The public ZIP or checksum differs from the reviewed candidate. The feed was not updated.'
}

# Each hotfix is published separately. The parent release gets only an
# append-only link index, updated after its ZIP is publicly verified and
# before the public feed points players to the new hotfix.
if ($Tag -match '\.[1-9][0-9]{0,8}$') {
    & ./scripts/update-hotfix-index.ps1 -LatestHotfixTag $Tag
}

Copy-Item -LiteralPath $manifestPath -Destination $feedFile
git -C $feedDirectory add -- alpha.json
if (git -C $feedDirectory status --porcelain -- alpha.json) {
    git -C $feedDirectory -c user.name=github-actions[bot] -c user.email=41898282+github-actions[bot]@users.noreply.github.com commit -m "Publish alpha feed for $Tag"
    git -C $feedDirectory push origin "HEAD:${feedRef}"
}
$feedRevision = git -C $feedDirectory rev-parse HEAD
$publicManifest = Join-Path $work 'public-alpha.json'
Invoke-WebRequest "https://raw.githubusercontent.com/$repo/update-feed/alpha.json?revision=$feedRevision" `
    -OutFile $publicManifest -MaximumRetryCount 3 -RetryIntervalSec 2
if ((Get-FileHash -LiteralPath $publicManifest).Hash -cne (Get-FileHash -LiteralPath $manifestPath).Hash) {
    throw 'Public alpha feed did not return the generated manifest.'
}

Write-Host "Published $Tag and verified its alpha manifest and Windows download."
