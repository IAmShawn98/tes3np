function Stage-MarkerlessConsole([string]$Executable, [string]$Dependencies, [string]$Destination, $Candidate) {
    if (!(Test-Path -LiteralPath $Executable -PathType Leaf) -or
        (GetTes3npSha256 $Executable) -ine $Candidate.executableSha256) {
        throw 'The selected EXE must be the exact console markerless build that passed testing.'
    }
    if (!(Test-Path -LiteralPath $Dependencies -PathType Container)) {
        throw 'The matching markerless DLL directory was not found.'
    }

    $directory = Get-Item -LiteralPath $Dependencies
    $root = $directory.FullName.TrimEnd('\', '/')
    $items = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
    if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        ($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })) {
        throw 'Select the verified DLL directory directly, without junctions or symlinks.'
    }

    $files = @($items | Where-Object { !$_.PSIsContainer })
    if ($files.Count -ne $Candidate.dllCount -or ($files | Where-Object { $_.Extension -ine '.dll' })) {
        throw "Expected the verified directory containing exactly $($Candidate.dllCount) DLL files."
    }
    foreach ($name in $Candidate.requiredDlls) {
        if (!(Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf)) {
            throw "The matching DLL directory is missing $name."
        }
    }

    $null = New-Item -ItemType Directory -Path $Destination -Force
    $targetExe = Join-Path $Destination 'tes3mp.exe'
    Copy-Item -LiteralPath $Executable -Destination $targetExe
    if ((GetTes3npSha256 $targetExe) -ine $Candidate.executableSha256) {
        throw 'The tested executable changed during staging.'
    }
    $entries = @( [ordered]@{ path = 'tes3mp.exe'; sha256 = $Candidate.executableSha256 } )
    foreach ($file in ($files | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        $target = Join-Path $Destination $relative
        $hash = GetTes3npSha256 $file.FullName
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
        Copy-Item -LiteralPath $file.FullName -Destination $target
        if ((GetTes3npSha256 $target) -ine $hash) { throw "DLL changed during staging: $relative" }
        $entries += [ordered]@{ path = $relative; sha256 = $hash.ToLowerInvariant() }
    }
    return @{ files = $entries }
}

function Test-PackagedMarkerlessConsole([string]$Executable) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = '--help'
    $info.WorkingDirectory = Split-Path -Parent $Executable
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(15000)) {
            $process.Kill()
            throw 'Packaged markerless client --help timed out.'
        }
        if (!$stdout.Wait(2000) -or !$stderr.Wait(2000) -or $process.ExitCode -ne 0 -or
            $stdout.Result -notmatch 'Allowed options') {
            $code = '0x{0:X8}' -f $process.ExitCode
            throw "Packaged markerless client did not print --help (exit $code)."
        }
    }
    finally {
        $process.Dispose()
    }
}
