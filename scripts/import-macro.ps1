# Extract a local macro archive into a launcher-created staging folder.
param([Parameter(Mandatory=$true)][string]$Archive,
      [Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
$zip = $null
$stage = "Opening ZIP"
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ((Get-Item -LiteralPath $Archive).Length -gt 25MB) { throw 'Archive exceeds 25 MB.' }
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd([char]92) + [char]92
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    if ($zip.Entries.Count -gt 500) { throw 'Archive contains more than 500 entries.' }
    $total = 0L
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $stage = 'Checking ZIP paths'
    # Validate the complete archive before extracting any file.
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace([char]47, [char]92)
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains(':') -or [IO.Path]::IsPathRooted($name)) { throw 'Archive has an invalid path.' }
        foreach ($part in $name.Split([char]92)) {
            if ($part -eq '..' -or ($part -ne '' -and $part.TrimEnd([char[]]@([char]32, [char]46)) -ne $part)) { throw 'Archive has an unsafe path.' }
        }
        $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $name))
        if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive path escapes its package.' }
        if (-not $paths.Add($target)) { throw 'Archive has duplicate paths.' }
        $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
        if ($mode -eq 0xA000) { throw 'Symbolic links are not supported.' }
        $total += $entry.Length
        if ($entry.Length -gt 25MB -or $total -gt 50MB) { throw 'Expanded archive exceeds size limits.' }
    }
    $stage = 'Extracting ZIP files'
    foreach ($entry in $zip.Entries) {
        $target = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $entry.FullName.Replace([char]47, [char]92)))
        if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith([string][char]92)) {
            [IO.Directory]::CreateDirectory($target) | Out-Null
        } else {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            $inputStream = $entry.Open()
            $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew)
            try { $inputStream.CopyTo($outputStream) }
            finally { $outputStream.Dispose(); $inputStream.Dispose() }
        }
    }
    [IO.File]::WriteAllText([IO.Path]::Combine($root, '.import-success'), 'OK')
} catch {
    # Do not expose archive paths or payload text in diagnostics.
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $reason = $stage + ' failed (' + $_.Exception.GetType().Name + ').'
    $allowed = @('Archive exceeds 25 MB.', 'Archive contains more than 500 entries.', 'Archive has an invalid path.', 'Archive has an unsafe path.', 'Archive path escapes its package.', 'Archive has duplicate paths.', 'Symbolic links are not supported.', 'Expanded archive exceeds size limits.')
    if ($allowed -contains $_.Exception.Message) { $reason = $_.Exception.Message }
    [IO.File]::WriteAllText([IO.Path]::Combine($Destination, '.import-error'), $reason)
    exit 1
} finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
