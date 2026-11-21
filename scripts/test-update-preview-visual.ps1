# Disposable, opt-in Windows visual inspection of the production Update Preview.
# This uses the original AutoHotkey UI modules and an isolated fake history
# helper. No public update, installed launcher, game data, AppData, or feed is
# changed. Update Now only closes the preview in this standalone test driver.
[CmdletBinding()]
param(
    [ValidateSet(50, 100)]
    [int]$Scale = 100,
    [switch]$CheckOnly,
    [string]$AutoHotkeyPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root 'tes3np.ahk'
if (!(Test-Path -LiteralPath $entry -PathType Leaf)) {
    throw 'Run this test from a complete TES3NP development checkout.'
}

if (!$AutoHotkeyPath) {
    $candidates = @(
        (Join-Path $root 'dist\local-build\runtime\AutoHotkey64.exe'),
        (Join-Path $root 'dist\tes3np-windows\runtime\AutoHotkey64.exe')
    )
    $AutoHotkeyPath = @($candidates | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1)[0]
}
if (!$AutoHotkeyPath -or !(Test-Path -LiteralPath $AutoHotkeyPath -PathType Leaf)) {
    throw 'The packaged AutoHotkey64.exe is missing. Run the existing Windows build first.'
}

$source = Get-Content -LiteralPath $entry -Raw -Encoding UTF8
$matches = [regex]::Matches($source, '(?m)^#Include[ \t]+(?<file>(?:src|scripts)\\[^\r\n]+)[ \t]*$')
if ($matches.Count -lt 25) {
    throw 'The launcher module entrypoint changed; visual test includes cannot be verified.'
}
$includes = foreach ($match in $matches) {
    $relative = $match.Groups['file'].Value.Trim()
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (!(Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Required launcher source is missing: $relative"
    }
    "#Include $full"
}

# All executable test files and artwork copies live under a new disposable TEMP
# directory. The actual production #Include files are read-only references.
$temporary = Join-Path $env:TEMP ('tes3np-update-preview-visual-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
try {
    $requiredArt = @(
        'controls\button.png',
        'controls\scroll-panel.png',
        'backgrounds\character-book.png',
        'backgrounds\launcher.png',
        'headings\quest.png',
        'headings\together.png',
        'icons\discord.png'
    )
    foreach ($asset in $requiredArt) {
        $from = Join-Path $root ('assets\' + $asset)
        if (!(Test-Path -LiteralPath $from -PathType Leaf)) {
            throw "The visual test needs the original launcher artwork: $asset"
        }
        $to = Join-Path $temporary ('assets\' + $asset)
        New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
        Copy-Item -LiteralPath $from -Destination $to -Force
    }

    $helperDir = Join-Path $temporary 'scripts'
    New-Item -ItemType Directory -Path $helperDir -Force | Out-Null
    $helperPath = Join-Path $helperDir 'fetch-release-notes.ps1'
    $fakeHistory = @'
param(
    [string]$InstalledVersion,
    [string]$LatestVersion,
    [string]$ReleaseOutputPath,
    [string]$HotfixOutputPath
)
$ErrorActionPreference = 'Stop'
if ($InstalledVersion -cne '0.1.21-alpha' -or $LatestVersion -cne '0.1.21-alpha.3') {
    throw 'Unexpected visual-test version.'
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ReleaseOutputPath, '', $utf8)
$history = @"
### v0.1.21-alpha.1 — sample earlier hotfix

### New Features
- **Update notifications:** See a red (1) when an update is available. It disappears after you view the update.

### Improvements
- **Launcher updates:** Review changes before choosing **Update Now** or **Not Now**. Downloads and installation still require confirmation.
- **Expansion Pack:** Recognize an existing official pack without reinstalling it when verification records are missing.

### Bug Fixes
- **Expansion Pack:** Fixed an issue that could prevent disabling the pack when verification failed.

### v0.1.21-alpha.2 — sample earlier hotfix

### Improvements
- **Visual test only:** Example notes for an earlier missed hotfix. This is not a published release.

### Bug Fixes
- **Visual test only:** Example earlier change, included so the expandable history can be tested.

### v0.1.21-alpha.3 — sample latest hotfix

### New Features
- **Visual test only:** Example latest hotfix change, not a published update.

### Improvements
- **Visual test only:** Check the gold borders, red circular 1, and scroll layout.
- **Visual test only:** Check that earlier missed versions are initially compact.

### Bug Fixes
- **Visual test only:** No actual files will be downloaded, installed, or replaced.
"@
[IO.File]::WriteAllText($HotfixOutputPath, $history, $utf8)
'@
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($helperPath, $fakeHistory, $utf8)

    $runnerPath = Join-Path $temporary 'tes3np-preview-test.ahk'
    $prefix = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
'@
    $driver = @'
; This isolated entrypoint reuses production UI modules without calling
; StartLauncher, CheckForUpdates, or any installation or user-data function.
Thread("Interrupt", 0)
CoordMode("Mouse", "Screen")
visualScale := A_Args.Length ? Integer(A_Args[1]) : 100
if visualScale != 50 && visualScale != 100
    ExitApp(61)
if A_Args.Length >= 2 && A_Args[2] = "--check-only"
    ExitApp(0)
LauncherScale := visualScale
ownerScale := visualScale / 100
ownerWidth := Round(800 * ownerScale + 32)
ownerHeight := Round(620 * ownerScale + 32)
primary := MonitorGetPrimary()
MonitorGetWorkArea(primary, &ml, &mt, &mr, &mb)
ownerWidth := Min(ownerWidth, mr - ml - 24)
ownerHeight := Min(ownerHeight, mb - mt - 24)
LauncherGui := Gui("-Caption -Border -DPIScale", "TES3NP visual update preview")
LauncherGui.BackColor := "171008"
LauncherGui.Add("Picture", "x0 y0 w" ownerWidth " h" ownerHeight,
    A_ScriptDir "\assets\backgrounds\launcher.png")
LauncherGui.Show("w" ownerWidth " h" ownerHeight
    " x" (ml + (mr - ml - ownerWidth) // 2)
    " y" (mt + (mb - mt - ownerHeight) // 2))
OnMessage(0x0201, PressButton, 1)
OnMessage(0x0202, ReleaseButton, 1)
OnMessage(0x0100, HandleThemedButtonKey, 1)
OnMessage(0x0007, HandleThemedButtonFocus, 1)
OnMessage(0x0008, HandleThemedButtonFocus, 1)
OnMessage(0x0215, HandleCaptureLost, 1)
SetTimer(UpdateButtonHover, 30)
try {
    ; This executes the real, unchanged ShowUpdatePreview rendering code.
    ; Only the published-history helper is redirected by A_ScriptDir to the
    ; disposable fixture script, never GitHub's live release feed.
    result := ShowUpdatePreview("0.1.21-alpha", "0.1.21-alpha.3",
        "alpha", "hotfix")
    SetTimer(UpdateButtonHover, 0)
    MsgBox("VISUAL TEST ONLY — " (result = "Yes" ? "Update Now" : "Not Now / Close")
        " was selected." Chr(10) "Nothing was downloaded or installed."
        Chr(10) "No public update was published.", "TES3NP visual test", "Iconi")
} finally {
    SetTimer(UpdateButtonHover, 0)
    try LauncherGui.Destroy()
    try DisposeButtonPainter()
}
ExitApp(0)

; These two helpers are called by real UI mouse handling but do not belong to
; this isolated viewer. Its preview has no macro or Character Book scrollbar.
'@
    $scriptText = $prefix + [Environment]::NewLine +
        ($includes -join [Environment]::NewLine) +
        [Environment]::NewLine + $driver
    [IO.File]::WriteAllText($runnerPath, $scriptText, $utf8)

    Write-Host "TES3NP | Opening isolated Update Preview visual test ($Scale%)." -ForegroundColor Cyan
    Write-Host 'Preview includes two SAMPLE missed hotfixes; the production updater and feed are not used.' -ForegroundColor Cyan
    $argsForAhk = @($runnerPath, "$Scale")
    if ($CheckOnly) {
        $argsForAhk += '--check-only'
    }
    & $AutoHotkeyPath @argsForAhk
    if ($LASTEXITCODE -ne 0) {
        throw "The AutoHotkey visual test failed (exit $LASTEXITCODE)."
    }
    if ($CheckOnly) {
        Write-Host 'PASS | Visual-test script parsed without opening a GUI.' -ForegroundColor Green
    } else {
        Write-Host 'PASS | Visual test closed. No updater installation or user profile change was requested.' -ForegroundColor Green
    }
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
