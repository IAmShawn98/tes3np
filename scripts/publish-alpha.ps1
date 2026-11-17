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
$revision = $env:GITHUB_SHA
if ($env:GITHUB_REPOSITORY -cne $repo -or $env:GITHUB_REF -cne 'refs/heads/main' -or
    (git rev-parse HEAD) -cne $revision -or
    (git ls-remote origin refs/heads/main) -cne "$revision`trefs/heads/main") {
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
if ($release.tagName -cne $Tag -or $release.targetCommitish -cne $revision -or
    !$release.isPrerelease -or $release.assets.Count -ne 2 -or
    $packageName -cnotin $release.assets.name -or $checksumName -cnotin $release.assets.name) {
    throw "Stage $Tag as a prerelease draft for $revision with only the versioned ZIP and checksum."
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

# Generate metadata from the reviewed bytes and checked-out source.
& ./scripts/generate-update-metadata.ps1 -ChannelFeed -PackagePath $packagePath -ManifestPath $manifestPath
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
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
    gh release edit $Tag --repo $repo --draft=false --prerelease --latest=false
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
