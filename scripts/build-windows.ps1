# Build a portable launcher using pinned official AutoHotkey tools.
[CmdletBinding()]
param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (!$OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'dist' }
$null = New-Item $OutputDirectory -ItemType Directory -Force
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('tes3np-build-' + [guid]::NewGuid())
$null = New-Item $buildRoot -ItemType Directory
function Get-VerifiedTool([string]$Url, [string]$Name, [string]$Hash) {
    $file = Join-Path $buildRoot $Name
    Invoke-WebRequest $Url -OutFile $file -UseBasicParsing
    if ((Get-FileHash $file -Algorithm SHA256).Hash -ne $Hash) {
        throw "Downloaded tool checksum did not match: $Name"
    }
    return $file
}
try {
    $ahkZip = Get-VerifiedTool 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.28/AutoHotkey_2.0.28.zip' 'autohotkey.zip' 'B63BE7548792B4AD0DFE424D91CC69376694ED2F758245B7A75A0C77D693B478'
    $compilerZip = Get-VerifiedTool 'https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe1.1.37.02a2/Ahk2Exe.zip' 'compiler.zip' 'C29B8C3A5124850D79FC9E66E2CA79677C377D7F31631AD3022BA159C5D9E3BE'
    $tools = Join-Path $buildRoot 'tools'
    Expand-Archive $ahkZip $tools
    Expand-Archive $compilerZip (Join-Path $tools 'Compiler')
    $compiler = Join-Path $tools 'Compiler\Ahk2Exe.exe'
    $base = Join-Path $tools 'AutoHotkey64.exe'
    $package = Join-Path $buildRoot 'tes3np'
    $null = New-Item $package -ItemType Directory
    $executable = Join-Path $package 'tes3np.exe'
    $arguments = '/in "' + (Join-Path $projectRoot 'tes3np.ahk') + '" /out "' + $executable + '" /icon "' + (Join-Path $projectRoot 'assets\icons\tes3np.ico') + '" /base "' + $base + '" /compress 0 /silent verbose'
    $process = Start-Process $compiler -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0 -or !(Test-Path $executable)) { throw 'Launcher compilation failed.' }
    # AutoHotkey parses every included function before this no-GUI check exits.
    $check = Start-Process $executable -ArgumentList '/ErrorStdOut --check' -PassThru
    if (!$check.WaitForExit(30000)) { $check.Kill(); throw 'Compiled launcher validation timed out.' }
    if ($check.ExitCode -ne 0) { throw 'Compiled launcher validation failed.' }
    foreach ($folder in @('assets', 'patches')) {
        Copy-Item (Join-Path $projectRoot $folder) $package -Recurse
    }
    $scripts = Join-Path $package 'scripts'
    $null = New-Item $scripts -ItemType Directory
    foreach ($worker in @('import-macro.ps1', 'patch-tes3mp.ps1')) {
        Copy-Item (Join-Path $PSScriptRoot $worker) $scripts
    }
    # Imported AHK v2 macros need an interpreter; ship it beside its license.
    $runtime = Join-Path $package 'runtime'
    $null = New-Item $runtime -ItemType Directory
    Copy-Item $base $runtime
    $license = Get-ChildItem $tools -File | Where-Object { $_.Name -match '^(license|copying)(\..*)?$' } | Select-Object -First 1
    if (!$license) { throw 'AutoHotkey license is missing from the official archive.' }
    Copy-Item $license.FullName (Join-Path $runtime 'LICENSE.txt')
    Copy-Item (Join-Path $projectRoot 'docs\INSTALLATION.md') (Join-Path $package 'INSTALLATION.md')
    Set-Content (Join-Path $package 'START-HERE.txt') @'
TES3NP - Nerevarine Prophecies Launcher

1. Extract this entire folder into your TES3MP 0.8.1 Win64 folder.
2. Double-click tes3np.exe. Keep its accompanying folders together.
3. Choose Patch Tes3mp if shown, check the locations, and click Install / Repair.
4. Choose Start New Adventure or Returning Fetcher to play.

You need Morrowind GOTY and TES3MP installed. AutoHotkey is included;
you do not need to install it separately. See INSTALLATION.md for help.
'@ -Encoding UTF8
    $archive = Join-Path $OutputDirectory 'tes3np-windows.zip'
    if (Test-Path $archive) { Remove-Item $archive }
    Compress-Archive $package $archive -CompressionLevel Optimal
    Write-Output "Built $archive"
}
finally {
    Remove-Item $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}
