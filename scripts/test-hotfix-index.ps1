# Offline GitHub release-index fixture. No network access or release writes.
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'update-hotfix-index.ps1'
$baseTag = 'v0.1.22-alpha'
$baseNotes = '## v0.1.22-alpha' + [char]10 + [char]10 +
    '### New Features' + [char]10 + '- **Launcher:** Original notes stay intact.'
$global:TES3NPHfxFixture = @{
    Releases = @{}
    EditCalls = 0
}
$fixtures = $global:TES3NPHfxFixture

function gh {
    $fixture = $global:TES3NPHfxFixture
    if ($args.Count -ge 4 -and $args[0] -ceq 'release' -and
        $args[1] -ceq 'view') {
        $tag = [string]$args[2]
        if (!$fixture.Releases.ContainsKey($tag)) { throw "Missing fake release $tag." }
        return ($fixture.Releases[$tag] | ConvertTo-Json -Compress -Depth 4)
    }
    if ($args.Count -ge 6 -and $args[0] -ceq 'release' -and
        $args[1] -ceq 'edit') {
        $tag = [string]$args[2]
        $noteIndex = [array]::IndexOf([object[]]$args, '--notes-file')
        if (!$fixture.Releases.ContainsKey($tag) -or $noteIndex -lt 0 -or
            $noteIndex + 1 -ge $args.Count) {
            throw 'Unexpected fake GitHub release edit.'
        }
        $file = [string]$args[$noteIndex + 1]
        $fixture.Releases[$tag].body = [IO.File]::ReadAllText($file)
        $fixture.EditCalls++
        return
    }
    throw "Unexpected GitHub CLI request."
}

function New-FakeRelease([string]$Tag, [string]$Date, [string]$Body) {
    return @{
        tagName = $Tag
        isDraft = $false
        publishedAt = $Date
        body = $Body
    }
}

try {
    $fixtures.Releases[$baseTag] = New-FakeRelease $baseTag '2026-11-23T12:00:00Z' $baseNotes
    $fixtures.Releases["$baseTag.1"] = New-FakeRelease "$baseTag.1" '2026-11-25T02:00:00Z' 'First hotfix only.'
    $fixtures.Releases["$baseTag.2"] = New-FakeRelease "$baseTag.2" '2026-11-27T04:00:00Z' 'Second hotfix only.'

    & $helper -LatestHotfixTag "$baseTag.1" | Out-Null
    $once = [string]$fixtures.Releases[$baseTag].body
    if (!$once.StartsWith($baseNotes, [StringComparison]::Ordinal) -or
        !$once.Contains("[$baseTag.1](https://github.com/IAmShawn98/tes3np/releases/tag/$baseTag.1)") -or
        !$once.Contains('November 25, 2026') -or $fixtures.EditCalls -ne 1) {
        throw 'First hotfix did not append only the published link and date.'
    }

    & $helper -LatestHotfixTag "$baseTag.1" | Out-Null
    if ($fixtures.EditCalls -ne 1 -or [string]$fixtures.Releases[$baseTag].body -cne $once) {
        throw 'Repeating a hotfix publication unexpectedly rewrote the original release.'
    }

    & $helper -LatestHotfixTag "$baseTag.2" | Out-Null
    $twice = [string]$fixtures.Releases[$baseTag].body
    if (!$twice.StartsWith($baseNotes, [StringComparison]::Ordinal) -or
        $twice.IndexOf("[$baseTag.2]") -ge $twice.IndexOf("[$baseTag.1]") -or
        !$twice.Contains('November 27, 2026') -or
        [regex]::Matches($twice, '<!-- TES3NP HOTFIX HISTORY START -->').Count -ne 1 -or
        $fixtures.EditCalls -ne 2) {
        throw 'Second hotfix did not update the existing history block newest first.'
    }

    # A malformed user-edited history is rejected rather than overwritten.
    $original = $fixtures.Releases[$baseTag].body
    $fixtures.Releases[$baseTag].body = $original.Replace(
        '<!-- TES3NP HOTFIX HISTORY END -->', '<!-- BROKEN HOTFIX HISTORY END -->')
    $rejected = $false
    try { & $helper -LatestHotfixTag "$baseTag.2" | Out-Null }
    catch { $rejected = $true }
    if (!$rejected -or $fixtures.EditCalls -ne 2) {
        throw 'A malformed original release history must fail without writing.'
    }

    # An unpublished newer hotfix cannot be added to the base release.
    $fixtures.Releases[$baseTag].body = $original
    $fixtures.Releases["$baseTag.3"] = New-FakeRelease "$baseTag.3" '2026-11-29T04:00:00Z' 'Not published.'
    $fixtures.Releases["$baseTag.3"].isDraft = $true
    $rejected = $false
    try { & $helper -LatestHotfixTag "$baseTag.3" | Out-Null }
    catch { $rejected = $true }
    if (!$rejected -or $fixtures.EditCalls -ne 2) {
        throw 'Draft hotfix must fail without modifying the public release.'
    }

    Write-Host 'PASS: GitHub release index is publication-only, date-accurate, append-only and idempotent.'
}
finally {
    Remove-Variable -Name TES3NPHfxFixture -Scope Global -ErrorAction SilentlyContinue
}
