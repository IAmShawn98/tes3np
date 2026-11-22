# Read-only, isolated PowerShell 5.1 contract tests for one existing prerelease
# record. No network calls, no AppData, no source or public resource writes.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$helper = Join-Path $PSScriptRoot 'fetch-release-notes.ps1'
$notesPath = Join-Path $root 'RELEASE_NOTES.md'
if (!(Test-Path -LiteralPath $helper) -or !(Test-Path -LiteralPath $notesPath)) {
    throw 'Run from the existing TES3NP source checkout with RELEASE_NOTES.md.'
}
$local = [IO.File]::ReadAllText($notesPath).Replace("`r`n", "`n")
$patch = [regex]::Match($local, '(?ms)^## v0\.1\.21-alpha\.1[^\n]*\n(?<body>.*?)(?=^## v0\.1\.21-alpha(?:\s|$))')
$base = [regex]::Match($local, '(?ms)^## v0\.1\.21-alpha(?!\.)[^\n]*\n(?<body>.*)\z')
if (!$patch.Success -or !$base.Success) { throw 'Approved patch or original base release notes are missing.' }
$patch1 = $patch.Groups['body'].Value.Trim()
$baseSource = '## v0.1.21-alpha' + "`n`n" + $base.Groups['body'].Value.Trim()
$start = '<!-- TES3NP CONSOLIDATED PATCH HISTORY v1 START -->'
$end = '<!-- TES3NP CONSOLIDATED PATCH HISTORY v1 END -->'
$baseDate = '2026-11-20T05:22:39Z' # Original published record date
$patch1Date = '2026-11-22T10:00:00Z' # FICTIONAL TEST DATE
$patch2Date = '2026-11-24T14:00:00Z' # FICTIONAL TEST DATE
$patch2 = '### Bug Fixes' + "`n`n" + '- **Fixture:** Second patch.'
$checks = 0

function Make-Body([int]$Count) {
    $parts = @()
    if ($Count -ge 2) {
        $parts += '## v0.1.21-alpha.2 — Published ' + $patch2Date + "`n`n" + $patch2
    }
    $parts += '## v0.1.21-alpha.1 — Published ' + $patch1Date + "`n`n" + $patch1
    return $start + "`n" + '<!-- TES3NP BASE RELEASE PUBLISHED ' + $baseDate + ' -->' +
        "`n`n" + ($parts -join "`n`n") + "`n" + $end + "`n`n" + $baseSource
}
$global:Tes3npConsolidatedFixtureReleases = @()
function Set-Release([int]$Count) {
    $global:Tes3npConsolidatedFixtureReleases = @([pscustomobject]@{
        id = 451907283
        tag_name = ('v0.1.21-alpha.' + $Count)
        published_at = $patch1Date
        draft = $false
        body = Make-Body $Count
    })
}
# Shadow HTTP calls in the dynamically scoped script-under-test, exactly as
# the existing updater fixture does. All requests are kept fully offline.
function Invoke-RestMethod($Uri, $Headers, $TimeoutSec) {
    if ($Uri -ceq 'https://api.github.com/repos/IAmShawn98/tes3np/releases?per_page=100&page=1') {
        # Emit one PSCustomObject per release, as the real API response is
        # consumed by Get-PublishedReleases. Never wrap the array in a comma.
        foreach ($release in $global:Tes3npConsolidatedFixtureReleases) {
            Write-Output $release
        }
        return
    }
    throw 'Fixture deliberately has no separate historical GitHub Release pages.'
}
$work = Join-Path $env:TEMP ('tes3np-consolidated-fixture-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$feature = Join-Path $work 'releases.txt'
$hotfix = Join-Path $work 'patches.txt'
$single = Join-Path $work 'single.txt'
function Check([string]$Label, [scriptblock]$Action) {
    & $Action
    $script:checks += 1
    Write-Host ('PASS | ' + $Label)
}
function Run-History([string]$Installed, [string]$Latest) {
    Remove-Item -LiteralPath $feature,$hotfix -ErrorAction SilentlyContinue
    & $helper -InstalledVersion $Installed -LatestVersion $Latest -ReleaseOutputPath $feature -HotfixOutputPath $hotfix
    if (!(Test-Path -LiteralPath $feature) -or !(Test-Path -LiteralPath $hotfix)) {
        throw 'Valid fixture did not emit both output files.'
    }
}
function Reject-History([string]$Installed, [string]$Latest) {
    Remove-Item -LiteralPath $feature,$hotfix -ErrorAction SilentlyContinue
    $failed = $false
    try { & $helper -InstalledVersion $Installed -LatestVersion $Latest -ReleaseOutputPath $feature -HotfixOutputPath $hotfix }
    catch { $failed = $true }
    if ((Test-Path -LiteralPath $feature) -or (Test-Path -LiteralPath $hotfix)) {
        throw 'Invalid fixture emitted published history.'
    }
    if (!$failed -and $LASTEXITCODE -eq 0) { throw 'Invalid history was not rejected.' }
}
try {
    Set-Release 1
    Check 'Mock GitHub API returns one flat published release object' {
        $probe = @(Invoke-RestMethod -Uri 'https://api.github.com/repos/IAmShawn98/tes3np/releases?per_page=100&page=1' -Headers @{} -TimeoutSec 10)
        if ($probe.Count -ne 1 -or $null -eq $probe[0] -or
            $probe[0] -isnot [pscustomobject] -or
            $probe[0].tag_name -cne 'v0.1.21-alpha.1' -or
            [int64]$probe[0].id -ne 451907283) {
            throw 'Mock did not return the flat, published release shape expected by the fetcher.'
        }
    }
    Check 'Base to patch 1 includes only approved patch' {
        Run-History '0.1.21-alpha' '0.1.21-alpha.1'
        $updates = [IO.File]::ReadAllText($hotfix)
        if (!$updates.Contains('### v0.1.21-alpha.1')) { throw 'Patch 1 missing.' }
        if (!$updates.Contains('**Update Notifications:**') -or !$updates.Contains('**Expansion Pack:**') -or
            $updates.Contains('Second patch.')) { throw 'Approved patch contents were not preserved.' }
        if ([IO.File]::ReadAllText($feature) -notmatch 'No new feature releases') { throw 'Base release was reoffered.' }
    }
    Check 'Historical base changelog reads from single current record' {
        Remove-Item -LiteralPath $single -ErrorAction SilentlyContinue
        & $helper -Version '0.1.21-alpha' -OutputPath $single
        if (!(Test-Path $single) -or !([IO.File]::ReadAllText($single)).Contains('**Game Chat:**')) {
            throw 'Historical base changelog was lost.'
        }
    }
    Check 'Published patch 1 reads from current record' {
        Remove-Item -LiteralPath $single -ErrorAction SilentlyContinue
        & $helper -Version '0.1.21-alpha.1' -OutputPath $single
        if (!(Test-Path $single) -or !([IO.File]::ReadAllText($single)).Contains('**Missed Updates:**')) {
            throw 'Published patch 1 notes were lost.'
        }
    }
    Set-Release 2
    Check 'Patch 1 to patch 2 excludes installed history' {
        Run-History '0.1.21-alpha.1' '0.1.21-alpha.2'
        $updates = [IO.File]::ReadAllText($hotfix)
        if (!$updates.Contains('Second patch.') -or $updates.Contains('**Missed Updates:**')) {
            throw 'Latest patch filtering failed.'
        }
    }
    Check 'Base to patch 2 returns newest first' {
        Run-History '0.1.21-alpha' '0.1.21-alpha.2'
        $updates = [IO.File]::ReadAllText($hotfix)
        if ($updates.IndexOf('v0.1.21-alpha.2') -ge $updates.IndexOf('v0.1.21-alpha.1')) {
            throw 'Patch version order is wrong.'
        }
    }
    Check 'Older installed release can receive base and both patches' {
        Run-History '0.1.20-alpha' '0.1.21-alpha.2'
        if (!([IO.File]::ReadAllText($feature)).Contains('**Game Chat:**')) { throw 'Base notes missing.' }
        if (!([IO.File]::ReadAllText($hotfix)).Contains('Second patch.')) { throw 'Patch notes missing.' }
    }
    $valid = $global:Tes3npConsolidatedFixtureReleases[0].body
    $invalid = @{
        'missing end marker' = $valid.Replace($end, '<!-- REMOVED -->')
        'duplicate marker' = $start + "`n" + $valid
        'missing patch 1' = [regex]::Replace($valid, '(?ms)^## v0\.1\.21-alpha\.1 — Published .*?(?=^' + [regex]::Escape($end) + ')', '')
        'wrong patch order' = $valid.Replace('## v0.1.21-alpha.2 — Published', '## v0.1.21-alpha.9 — Published')
        'duplicate patch heading' = $valid.Replace('## v0.1.21-alpha.1 — Published', '## v0.1.21-alpha.2 — Published')
        'invalid UTC date' = $valid.Replace($patch2Date, '2026-11-99T14:00:00Z')
        'missing base date' = $valid.Replace('<!-- TES3NP BASE RELEASE PUBLISHED', '<!-- MISSING BASE DATE')
        'changed but valid base UTC date' = $valid.Replace($baseDate, '2026-11-19T05:22:39Z')
        'missing original base' = $valid.Replace($baseSource, '## v0.1.21-alpha')
        'wrong base version' = $valid.Replace('## v0.1.21-alpha' + "`n", '## v0.1.22-alpha' + "`n")
        'chronology reversed' = $valid.Replace($patch1Date, '2026-11-25T10:00:00Z')
    }
    foreach ($key in ($invalid.Keys | Sort-Object)) {
        $global:Tes3npConsolidatedFixtureReleases[0].body = $invalid[$key]
        Check ('Rejected ' + $key) { Reject-History '0.1.21-alpha' '0.1.21-alpha.2' }
    }
    $global:Tes3npConsolidatedFixtureReleases[0].body = $valid
    $global:Tes3npConsolidatedFixtureReleases[0].draft = $true
    Check 'Draft current record is rejected' { Reject-History '0.1.21-alpha' '0.1.21-alpha.2' }
    $global:Tes3npConsolidatedFixtureReleases[0].draft = $false
    $global:Tes3npConsolidatedFixtureReleases[0].tag_name = 'v0.1.21-alpha.3'
    Check 'Wrong latest release tag is rejected' { Reject-History '0.1.21-alpha' '0.1.21-alpha.2' }
    $global:Tes3npConsolidatedFixtureReleases[0].tag_name = 'v0.1.21-alpha.2'
    $global:Tes3npConsolidatedFixtureReleases[0].body = '## v0.1.21-alpha.2' + "`n`n" + '### Bug Fixes' + "`n" + '- Missing history.'
    Check 'Sole patch record without mandatory history is rejected' { Reject-History '0.1.21-alpha' '0.1.21-alpha.2' }
    $global:Tes3npConsolidatedFixtureReleases[0].body = $valid
    $global:Tes3npConsolidatedFixtureReleases[0].id = 451907282
    Check 'Different GitHub Release record ID is rejected' { Reject-History '0.1.21-alpha' '0.1.21-alpha.2' }
    $global:Tes3npConsolidatedFixtureReleases[0].id = 451907283
    $global:Tes3npConsolidatedFixtureReleases += [pscustomobject]@{ id = 999; tag_name = 'v0.1.21-alpha'; published_at = $baseDate; draft = $false; body = $baseSource }
    Check 'Second published release in consolidated family is rejected' { Reject-History '0.1.21-alpha' '0.1.21-alpha.2' }
    Write-Host ("SUCCESS: $checks consolidated read-side fixture groups passed (isolated; no publication).")
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name 'Tes3npConsolidatedFixtureReleases' -Scope Global -ErrorAction SilentlyContinue
}
