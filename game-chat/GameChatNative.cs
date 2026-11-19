using System.Runtime.InteropServices;

internal static class GameChatNative
{
    [DllImport("user32.dll", SetLastError = true)] internal static extern IntPtr SetParent(IntPtr child, IntPtr parent);

    [DllImport("user32.dll")] internal static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(IntPtr hwnd);

    [DllImport("user32.dll")] internal static extern bool GetClientRect(IntPtr hwnd, out RECT rect);

    [DllImport("user32.dll")] internal static extern IntPtr GetParent(IntPtr hwnd);

    [StructLayout(LayoutKind.Sequential)] internal struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    internal static extern IntPtr SetWindowOwner64(IntPtr hwnd, int index, IntPtr value);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    internal static extern int SetWindowOwner32(IntPtr hwnd, int index, int value);

    internal static void SetNativeWindowOwner(IntPtr hwnd, IntPtr ownerHwnd)
    {
        const int GWLP_HWNDPARENT = -8;
        if (IntPtr.Size == 8) SetWindowOwner64(hwnd, GWLP_HWNDPARENT, ownerHwnd);
        else SetWindowOwner32(hwnd, GWLP_HWNDPARENT, ownerHwnd.ToInt32());
    }

    internal delegate void WinEventCallback(IntPtr hook, uint eventType, IntPtr hwnd,
        int objectId, int childId, uint eventThread, uint eventTime);

    [DllImport("user32.dll")] internal static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax,
        IntPtr module, WinEventCallback callback, uint processId, uint threadId, uint flags);

    [DllImport("user32.dll")] internal static extern bool UnhookWinEvent(IntPtr hook);

    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

    [DllImport("user32.dll")] internal static extern bool MoveWindow(IntPtr hwnd, int x, int y, int w, int h, bool repaint);

    [DllImport("user32.dll")] internal static extern bool IsWindow(IntPtr hwnd);

    [DllImport("user32.dll")] internal static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")] internal static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("dwmapi.dll")] internal static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    internal const int DWMWA_CLOAK = 13;

    [DllImport("user32.dll", EntryPoint = "PostMessageW")] internal static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)] internal struct COPYDATASTRUCT
    {
        public IntPtr dwData;
        public int cbData;
        public IntPtr lpData;
    }

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", SetLastError = true)]
    internal static extern IntPtr SendCopyDataTimeout(IntPtr hwnd, uint msg, IntPtr sender,
        ref COPYDATASTRUCT data, uint flags, uint milliseconds, out IntPtr result);

    [DllImport("user32.dll")] internal static extern int GetWindowLong(IntPtr hwnd, int index);

    [DllImport("user32.dll")] internal static extern int SetWindowLong(IntPtr hwnd, int index, int value);

    [DllImport("user32.dll")] internal static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] internal static extern int GetWindowLongEx(IntPtr hwnd, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW")] internal static extern int SetWindowLongEx(IntPtr hwnd, int index, int value);

    [DllImport("user32.dll", SetLastError = true)] internal static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint colorKey, byte alpha, uint flags);

    internal const int GWL_EXSTYLE = -20, WS_EX_LAYERED = 0x80000;

    internal const int WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000;

    internal const uint LWA_ALPHA = 2;

    internal const int GWL_STYLE = -16, WS_CHILD = 0x40000000, WS_POPUP = unchecked((int)0x80000000);

    [DllImport("user32.dll")] internal static extern IntPtr GetLastActivePopup(IntPtr hwnd);

    [DllImport("user32.dll")] internal static extern bool IsWindowEnabled(IntPtr hwnd);

    [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")] internal static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")] internal static extern short GetAsyncKeyState(int virtualKey);

    [DllImport("gdi32.dll")] internal static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);

    [DllImport("gdi32.dll")] internal static extern bool DeleteObject(IntPtr handle);

    [DllImport("user32.dll")] internal static extern int SetWindowRgn(IntPtr hwnd, IntPtr region, bool redraw);
}
