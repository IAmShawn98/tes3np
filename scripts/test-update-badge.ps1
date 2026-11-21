[CmdletBinding()]
param(
    [ValidateSet('Unread', 'Viewed', 'None')]
    [string]$State = 'Unread'
)

$ErrorActionPreference = 'Stop'

# Connect only to a launcher explicitly started with --test-update-badge.
# No manifest, settings, profile, or game files are read or changed here.
$testWindow = 'tes3np - Nerevarine Prophecies Launcher [Badge Test]'
if (-not ('TES3NPBadgeTestNative' -as [type])) {
    $native = @'
using System;
using System.Runtime.InteropServices;
public static class TES3NPBadgeTestNative {
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

$hwnd = [TES3NPBadgeTestNative]::FindWindow('AutoHotkeyGUI', $testWindow)
if ($hwnd -eq [IntPtr]::Zero) {
    throw 'Badge Test launcher not found. Close TES3NP, then open tes3np.exe --test-update-badge before sending a state.'
}

$states = @{ Unread = [uint32]1; Viewed = [uint32]2; None = [uint32]3 }
$result = [UIntPtr]::Zero
# WM_APP + 0x41. The callback is registered only in explicit test mode.
$sent = [TES3NPBadgeTestNative]::SendMessageTimeout(
    $hwnd, [uint32]0x8041, [UIntPtr]([uint32]$states[$State]), [IntPtr]::Zero,
    [uint32]2, [uint32]5000, [ref]$result)
if ($sent -eq [IntPtr]::Zero) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "Badge Test did not respond (Win32 error $code). The real launcher was not modified."
}
if ($result.ToUInt64() -ne 1) {
    throw 'Badge Test launcher rejected the requested state. No update was installed.'
}

Write-Host "PASS: Live launcher update indicator set to $State (session only)."
