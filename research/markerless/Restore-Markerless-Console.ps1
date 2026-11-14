param(
    [ValidatePattern('^[0-9a-fA-F]{8}$')][string]$BuildId = '6588eb15',
    [string]$WorkRoot = (Join-Path $env:LOCALAPPDATA 'TES3MP-Markerless-Build')
)

$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'console-build.log'

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}

function Get-WindowsSubsystem([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw 'Expected a Windows executable.' }
        $stream.Position = 0x3c
        $pe = $reader.ReadUInt32()
        $stream.Position = $pe
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw 'Expected a Windows x64 executable.'
        }
        $stream.Position = $pe + 24
        if ($reader.ReadUInt16() -ne 0x20b) { throw 'Expected a Windows x64 PE header.' }
        $stream.Position = $pe + 24 + 68
        return $reader.ReadUInt16()
    } finally {
        $reader.Dispose()
    }
}

Start-Transcript -LiteralPath $log -Force | Out-Null
try {
    $root = Join-Path $WorkRoot $BuildId
    $source = Join-Path $root 'tes3mp'
    $build = Join-Path $source 'MSVC2019_64'
    $original = Join-Path $root 'output\markerless\tes3mp.exe'
    $binary = Join-Path $build 'Release\tes3mp.exe'
    $cache = Join-Path $build 'CMakeCache.txt'
    $cmake = Join-Path $WorkRoot 'cmake-3.31.10\Lib\site-packages\cmake\data\bin\cmake.exe'
    if (!(Test-Path -LiteralPath $cmake -PathType Leaf)) {
        $cmake = (Get-Command cmake.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    }
    $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $gitExe = if ($git) { $git.Source } else { Join-Path $env:ProgramFiles 'Git\cmd\git.exe' }
    foreach ($file in @($original, $binary, $cache, $gitExe)) {
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing existing build file: $file" }
    }

    $revision = & $gitExe -C $source rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $revision -ne '68954091c54d0596037c4fb54d2812313b7582a1') {
        throw 'The source folder is not the pinned TES3MP 0.8.1 checkout.'
    }
    $markerlessPatch = Join-Path $PSScriptRoot 'tes3mp-0.8.1-markerless-experimental.patch'
    Invoke-Checked $gitExe @('-C', $source, 'apply', '--reverse', '--check', $markerlessPatch)
    if (Select-String -LiteralPath $cache -SimpleMatch 'CMAKE_GENERATOR:INTERNAL=Visual Studio 17 2022' -Quiet) {
        Write-Host 'Using the existing Visual Studio 2022 build.'
    } else {
        throw 'The existing build does not use the Visual Studio 2022 generator.'
    }

    $consolePatch = Join-Path $PSScriptRoot 'tes3mp-release-console.patch'
    $cmakeSource = Get-Content -LiteralPath (Join-Path $source 'CMakeLists.txt') -Raw
    if ($cmakeSource -match '(?m)^ *set_target_properties\(tes3mp PROPERTIES LINK_FLAGS_RELEASE "/SUBSYSTEM:WINDOWS"\)') {
        Invoke-Checked $gitExe @('-C', $source, 'apply', '--check', $consolePatch)
        Invoke-Checked $gitExe @('-C', $source, 'apply', $consolePatch)
    } else {
        Invoke-Checked $gitExe @('-C', $source, 'apply', '--reverse', '--check', $consolePatch)
    }

    $env:RAKNET_ROOT = (Join-Path $root 'crabnet-install').Replace('\', '/')
    $env:FFMPEG_HOME = (Join-Path $build 'deps\FFmpeg').Replace('\', '/')
    Write-Host 'Building the markerless Release client with the native Windows console.'
    Invoke-Checked $cmake @('--build', $build, '--config', 'Release', '--target', 'tes3mp', '--parallel', '2')
    if ((Get-WindowsSubsystem $binary) -ne 3) { throw 'The resulting executable is not a Windows console application.' }

    $stamp = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $output = Join-Path $root "output\markerless-console-$stamp"
    New-Item -ItemType Directory -Path $output | Out-Null
    $exe = Join-Path $output 'tes3mp.exe'
    Copy-Item -LiteralPath $binary -Destination $exe
    Copy-Item -LiteralPath $consolePatch, $markerlessPatch -Destination $output
    $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  tes3mp.exe" | Set-Content -LiteralPath (Join-Path $output 'tes3mp.exe.sha256') -Encoding ASCII
    Write-Host "Verified Windows console executable: $exe"
    Write-Host "SHA-256: $hash"
    Write-Host 'In Game Client Settings, choose this EXE and reuse verified-dependencies-781d661c.'
    if ($env:OS -eq 'Windows_NT') { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $exe) }
} catch {
    Write-Host "STOPPED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Stop-Transcript | Out-Null
}
