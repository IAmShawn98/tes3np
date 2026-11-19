# Parse helpers without executing installers or imported scripts.
param()
$ErrorActionPreference = 'Stop'
$failed = $false
$research = Join-Path (Split-Path -Parent $PSScriptRoot) 'research/markerless'
Get-ChildItem -LiteralPath $PSScriptRoot, $research -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in $parseErrors) {
        $failed = $true
        Write-Host ($_.Name + ':' + $parseError.Extent.StartLineNumber + ': ' + $parseError.Message)
    }
}
if ($failed) { exit 1 }
Write-Host 'All PowerShell helpers parsed. No scripts were executed.'
exit 0
