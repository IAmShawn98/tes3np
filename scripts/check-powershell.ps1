# Parse helpers without executing installers or imported scripts.
param()
$ErrorActionPreference = 'Stop'
$failed = $false
Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | ForEach-Object {
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
