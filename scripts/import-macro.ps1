# Extract a local macro archive into a launcher-created staging folder.
param([Parameter(Mandatory=$true)][string]$Archive,
      [Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
$zip = $null
$root = $null
$stage = "Opening ZIP"
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    $directory = Get-Item -LiteralPath $destinationPath -Force
    if (!$directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Get-ChildItem -LiteralPath $destinationPath -Force | Select-Object -First 1)) {
        throw 'Macro staging must be an empty launcher-created directory.'
    }
    $root = $destinationPath
    if ((Get-Item -LiteralPath $Archive).Length -gt 25MB) { throw 'Archive exceeds 25 MB.' }
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    if ($zip.Entries.Count -gt 500) { throw 'Archive contains more than 500 entries.' }
    $total = 0L
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $directories = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $reserved = @('.import-success', '.import-error', '.tes3np-package.ini')
    $plan = @()
    $stage = 'Checking ZIP paths'
    # Validate the complete archive before extracting any file.
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName.Replace('\', '/')
        $isDirectory = $name.EndsWith('/')
        if ($isDirectory) { $name = $name.Substring(0, $name.Length - 1) }
        $parts = $name.Split('/')
        if ($parts[0] -in $reserved) { throw 'Archive contains a reserved launcher filename.' }
        foreach ($part in $parts) {
            if (!$part -or $part -match '[\x00-\x1F<>:"|?*]|[ .]$' -or
                $part -match '^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\s*\.|$)') {
                throw 'Archive has an unsafe path.'
            }
        }
        if (-not $paths.Add($name)) { throw 'Archive has duplicate paths.' }
        $directoryPath = $root
        $relative = ''
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($i -gt 0) { $relative += '/' }
            $relative += $parts[$i]
            $directoryPath = [IO.Path]::Combine($directoryPath, $parts[$i])
            if ($i -lt $parts.Count - 1 -or $isDirectory) {
                if ($files.Contains($relative)) { throw 'Archive has conflicting file and folder paths.' }
                [void]$directories.Add($relative)
            } else {
                if ($directories.Contains($relative)) { throw 'Archive has conflicting file and folder paths.' }
                [void]$files.Add($relative)
            }
        }
        $mode = ($entry.ExternalAttributes -shr 16) -band 0xF000
        if ($mode -eq 0xA000) { throw 'Symbolic links are not supported.' }
        $total += $entry.Length
        if ($entry.Length -gt 25MB -or $total -gt 50MB) { throw 'Expanded archive exceeds size limits.' }
        $plan += [pscustomobject]@{Entry=$entry; Target=$directoryPath; IsDirectory=$isDirectory}
    }
    $stage = 'Extracting ZIP files'
    $buffer = [byte[]]::new(65536)
    foreach ($item in $plan) {
        $target = $item.Target
        if ($item.IsDirectory) {
            [IO.Directory]::CreateDirectory($target) | Out-Null
        } else {
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            $inputStream = $item.Entry.Open()
            try {
                $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew)
                try {
                    $remaining = $item.Entry.Length
                    while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $remaining -= $count
                        if ($remaining -lt 0) { throw 'Extracted file does not match its declared size.' }
                        $outputStream.Write($buffer, 0, $count)
                    }
                    if ($remaining -ne 0) { throw 'Extracted file does not match its declared size.' }
                }
                finally { $outputStream.Dispose() }
            }
            finally { $inputStream.Dispose() }
        }
    }
    [IO.File]::WriteAllText([IO.Path]::Combine($root, '.import-success'), 'OK')
} catch {
    # Do not expose archive paths or payload text in diagnostics.
    $reason = $stage + ' failed (' + $_.Exception.GetType().Name + ').'
    $allowed = @('Archive exceeds 25 MB.', 'Archive contains more than 500 entries.', 'Archive has an unsafe path.',
        'Archive has duplicate paths.', 'Archive has conflicting file and folder paths.', 'Archive contains a reserved launcher filename.',
        'Symbolic links are not supported.', 'Expanded archive exceeds size limits.', 'Extracted file does not match its declared size.')
    if ($allowed -contains $_.Exception.Message) { $reason = $_.Exception.Message }
    if ($root) {
        try { [IO.File]::WriteAllText([IO.Path]::Combine($root, '.import-error'), $reason) } catch {}
    }
    exit 1
} finally {
    if ($null -ne $zip) { $zip.Dispose() }
}
