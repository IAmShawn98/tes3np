[CmdletBinding()]
param(
    [ValidateSet('Missed', 'Hotfix')]
    [string]$Scenario = 'Missed'
)

$ErrorActionPreference = 'Stop'

# UI-only test. A normal launcher opened with --test-update-badge registers
# the message handler. No published release feed, INI or game files are touched.
$testWindow = 'tes3np - Nerevarine Prophecies Launcher [Badge Test]'
if (-not ('TES3NPHistoryTestNative' -as [type])) {
    $native = @'
using System;
using System.Runtime.InteropServices;
public static class TES3NPHistoryTestNative {
    [DllImport("user32.dll", EntryPoint="FindWindowW", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr FindWindow(string className, string windowName);

    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, UInt32 message, UIntPtr wParam, IntPtr lParam,
        UInt32 flags, UInt32 timeoutMs, out UIntPtr result);
}
'@
    Add-Type -TypeDefinition $native -ErrorAction Stop
}

$hwnd = [TES3NPHistoryTestNative]::FindWindow('AutoHotkeyGUI', $testWindow)
for ($attempt = 0; $attempt -lt 20 -and $hwnd -eq [IntPtr]::Zero; $attempt++) {
    Start-Sleep -Milliseconds 250
    $hwnd = [TES3NPHistoryTestNative]::FindWindow('AutoHotkeyGUI', $testWindow)
}
if ($hwnd -eq [IntPtr]::Zero) {
    throw 'Update UI test launcher not found. Run tes3np.exe --test-update-badge before injecting synthetic history.'
}

$scenarios = @{ Missed = [uint32]1; Hotfix = [uint32]2 }
$result = [UIntPtr]::Zero
$sent = [TES3NPHistoryTestNative]::SendMessageTimeout(
    $hwnd, [uint32]0x8042, [UIntPtr]([uint32]$scenarios[$Scenario]),
    [IntPtr]::Zero, [uint32]2, [uint32]5000, [ref]$result)
if ($sent -eq [IntPtr]::Zero) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "Update UI test did not respond (Win32 error $code). No update was installed."
}
if ($result.ToUInt64() -ne 1) {
    throw 'Update UI test rejected the request. Close any open update preview and try again.'
}

Write-Host "PASS: Opened $Scenario synthetic history in real launcher (no download or install)."
