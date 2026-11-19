using System.Drawing;
using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    sealed class BufferedScrollbar : Panel
    {
        public BufferedScrollbar()
        {
            DoubleBuffered = true;
            ResizeRedraw = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer, true);
        }
    }

    sealed class ScrollbarFreeRichTextBox : RichTextBox
    {
        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.Style &= ~0x00200000; // WS_VSCROLL
                cp.Style &= ~0x00100000; // WS_HSCROLL
                return cp;
            }
        }
    }

    int ChatFirstLine() => browserScrollTop;

    int ChatLineCount() => Math.Max(1, browserScrollHeight);

    int ChatVisibleLines() => Math.Max(1, browserClientHeight);

    int ChatThumbY(int height, out int thumbHeight) =>
        GoldScrollbarThumbY(height, ChatLineCount(), ChatVisibleLines(), browserScrollTop, out thumbHeight);

    static int GoldScrollbarThumbY(int height, int total, int visible, int top, out int thumbHeight)
    {
        int track = Math.Max(1, height - 54);
        thumbHeight = Math.Clamp((int)((long)track * Math.Min(total, visible) / total), Math.Min(20, track), track);
        return 27 + (int)((long)Math.Clamp(top, 0, Math.Max(0, total-visible))
            * (track-thumbHeight) / Math.Max(1,total-visible));
    }

    void ScrollChatToThumb(int y, int dragOffset)
    {
        if (!messageBrowserReady) return;
        int height = ChatUnits(goldScrollbar.Height);
        int track = Math.Max(1, height - 54);
        ChatThumbY(height, out int thumbHeight);
        double fraction = (double)Math.Clamp(y-dragOffset-27,0,Math.Max(1,track-thumbHeight)) /
            Math.Max(1,track-thumbHeight);
        _ = messageBrowser.CoreWebView2.ExecuteScriptAsync(
            "window.scrollFraction(" + fraction.ToString(System.Globalization.CultureInfo.InvariantCulture) + ")");
        if (fraction > 0.05) historyCatchupActive = false;
        if (fraction <= 0.01)
        {
            userScrolledChat = true;
            RequestOlderMessages(forceTop: true);
        }
    }

    // A separate clipped viewport prevents the WebView's negative Y offset
    // from covering the custom frame and title.
    readonly Panel frameSurface = new() { BackColor = System.Drawing.Color.FromArgb(164, 128, 69), Margin = Padding.Empty };

    readonly Panel chatViewport = new() { BackColor = System.Drawing.Color.FromArgb(9, 8, 7), Margin = Padding.Empty };

    static System.Drawing.Bitmap? LoadTexture(string filename)
    {
        try
        {
            string encoded = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, filename)).Trim();
            using var stream = new MemoryStream(Convert.FromBase64String(encoded));
            using var bitmap = new System.Drawing.Bitmap(stream);
            return new System.Drawing.Bitmap(bitmap);
        }
        catch { return null; }
    }

    readonly System.Drawing.Bitmap? borderTexture = LoadTexture("border-texture.b64") ?? LoadEmbeddedBorderTexture();

    static System.Drawing.Bitmap? LoadEmbeddedBorderTexture()
    {
        // Fallback when the published ChatHost does not include border-texture.b64.
        using var stream = new MemoryStream(Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAFgAAAAPCAMAAABXwPhJAAAAYFBMVEW2n22vlmGtjlWli1eihU+ggEybgU+afkuae0mZeUeUeUiVdkaSc0OOdEeMcESKbkKJbECIZzuBaUGAZTyAYjl/XTZ3Xjl0WzZ1WDRzUi9rVDRnTS5hRSpMPSdGNSJAMyFUiQp4AAADLklEQVR42o2T19qgKAyGFekl9CKg//3f5cTZ2TnYo+VRkBTU5P2O4zrP6zqP8/h34Aav40QH/9a/9gttuJL/l2AlY9xQYaVXylKmJFiFJmsjO40+iaIAxgZ0WUWZMdYoIix3UToQQjLJIEpFqYmYZ4TghFDhzRG9gARpzt5tXpZJO+47Gt3vXQgHDJPQclmRKV2c7qPUonWfvcGYoXQlRbjvOygYo5aoHVyEqtKOWKhLrs3dAayvVn5hePBYpborNU450dnDCAzw4DHvWoHm1VIKIdvYwNR74cHmXjUWwTtQRmk8guO+zeYSgOe07h0pi3UvT0hMvHUQzAllSVg7tz0MsdFrl5J3XkhPZdsrXLKMf1zRwMyCSimx7JdbT/cYGigx7dnAS1jvZicVF2AthOOGnDTvZ63nJiZiSso+RawwpXY+S0MP+63EhouIpAn1mh5aC4cFzsnrYlmUZo4yUqzLEgMidUd4T5aePsBaLu4Sy8V1692B0oapUvpMuXl/L1uioFfLhOgUDpqKw7a65mUMICS+bvX5FoaF0pyn2fpPo4qK3K1vUhVw3In0vJ4bp51u7wNSEN2yLZ7nwmT0Umg4qMwtVqXzHWME7vFHUsJWtsGIl+cV0lxtLMl0CTaPEILnCdzaaQwnvPd7puGJsqOUwKENG4IUyR2MwoeB0DjX4r4SXRy/v92WyoA/wHTzdQXFfMCgUWvWX+2cGaNwjZSCGVUqUe97OB4WUhe5T0ewsdY7ettvpMXRnimnLBTjh6KjMMFoLEbWqHMFWwsGScQ4BS9t+dqDNLFSQxjjrsH5WgcSjAd/fNE8ntucDAyVJRmuFEVCosLCGaoUs7jZu9zPYAdEg+AnZw3qgDvEzmkC9zORtjpRVAQVyFM/ytrVjjDeZTwQciVUsbVMnadiNDgUnpL2JDLsp813qKAJ4amFYAkOgZQmR1hAEBEKDIosMoIEH6nvde9e9m5t5J7XSqnPOcDfo6yFzeotYwdzf1Z/no/MjLB1VLFHweJ+zrJmW3uuiTpZYyHj8zne3+Pn5+d9nwfn53m/Z7y/5XP8/LGj433++H7b/zr+m/CF/QJdHU47F3ZmuwAAAABJRU5ErkJggg=="));
        using var image = new System.Drawing.Bitmap(stream);
        return new System.Drawing.Bitmap(image);
    }

    readonly System.Drawing.Bitmap? scrollbarTexture = LoadTexture("scrollbar-texture.b64");

    readonly Panel messageClip = new() { BackColor = System.Drawing.Color.FromArgb(10, 9, 8), Margin = Padding.Empty };

    readonly BufferedScrollbar goldScrollbar = new() { BackColor = System.Drawing.Color.FromArgb(11, 10, 8), Margin = Padding.Empty };

    void EnforceChatClip()
    {
        if (discordLoginVisible || web.Parent != chatViewport ||
            !web.IsHandleCreated || chatViewport.ClientSize.Width < 1) return;
        // Native clipping remains effective when WebView2 recreates its
        // composition surface after Discord finishes loading.
        var region = CreateRectRgn(0, ChatPixels(HeaderCrop), web.Width, web.Height);
        if (region == IntPtr.Zero) return;
        if (SetWindowRgn(web.Handle, region, true) == 0)
        {
            DeleteObject(region);
            Log("Unable to set WebView clip region");
        }
        // Frame is now a browser overlay, not a competing native HWND.
    }

    // Clip the Discord header outside the visible child window.
    const int HeaderCrop = 48;

    double chatScale = 1;

    Font? loadingFont;

    static int Pixels(int value, double scale) =>
        Math.Max(1, (int)Math.Round(value * scale, MidpointRounding.AwayFromZero));

    int ChatPixels(int value) => Pixels(value, chatScale);

    int ChatUnits(int pixels) => (int)Math.Floor(pixels / chatScale);

    static void SetBrowserScale(WebView2 browser, double scale)
    {
        // WebView2 already accounts for Windows DPI. Apply only the
        // remaining zoom needed to match the native popup's geometry.
        double zoom = scale * 96 / browser.DeviceDpi;
        if (Math.Abs(browser.ZoomFactor - zoom) > 0.005)
            browser.ZoomFactor = zoom;
    }

    void UpdateChatScale(double scale)
    {
        if (chatScale == scale && loadingFont != null) return;
        chatScale = scale;
        if (loadingFont == null)
        {
            loadingFont = new Font("Georgia", 10, FontStyle.Regular);
            nativeMessages.Font = loadingFont;
        }
        FitWebView();
        goldScrollbar.Invalidate();
        Invalidate();
    }

    void FitWebView()
    {
        if (discordLoginVisible)
        {
            // The sign-in browser is sized by its dedicated popup panel.
            return;
        }
        frameSurface.SetBounds(0, 0, ClientSize.Width, ClientSize.Height);
        int composerSpace = nativeMode ? ChatPixels(ChatComposerSpace) : 0;
        messageClip.SetBounds(ChatPixels(23), ChatPixels(60),
            Math.Max(1, ClientSize.Width - ChatPixels(60)), Math.Max(1, ClientSize.Height - ChatPixels(78) - composerSpace));
        nativeMessages.SetBounds(0, 0, messageClip.Width, messageClip.Height);
        messageBrowser.SetBounds(0, 0, messageClip.Width, messageClip.Height);
        goldScrollbar.SetBounds(Math.Max(0, ClientSize.Width - ChatPixels(37)), ChatPixels(56),
            ChatPixels(20), Math.Max(1, ClientSize.Height - ChatPixels(74) - composerSpace));
        FitChatComposer();
        chatViewport.SetBounds(ChatPixels(14), ChatPixels(49),
            Math.Max(1, ClientSize.Width - ChatPixels(28)), Math.Max(1, ClientSize.Height - ChatPixels(63)));
        frameSurface.Invalidate();
        chatViewport.SendToBack();
        if (nativeMessages.Visible) messageClip.BringToFront();
        goldScrollbar.BringToFront();
        // The original viewport is only used on a saved-session startup.
        // After an interactive login the source stays in its detached card.
        chatViewport.Visible = web.Parent == chatViewport && !nativeMode && !connectingChat;

        if (web.Parent != chatViewport) return;
        int crop = ChatPixels(HeaderCrop);
        web.SetBounds(0, -crop, chatViewport.ClientSize.Width, chatViewport.ClientSize.Height + crop);
        SetBrowserScale(web, chatScale);
        EnforceChatClip();
    }

    WinEventCallback? launcherLocationCallback;

    IntPtr launcherLocationHook;
    IntPtr launcherForegroundHook;

    bool repositionQueued;

    void WatchLauncherMovement()
    {
        if (launcherLocationHook != IntPtr.Zero || launcherForegroundHook != IntPtr.Zero || !IsWindow(owner)) return;
        const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
        uint threadId = GetWindowThreadProcessId(owner, out uint processId);
        launcherLocationCallback = (hook, eventType, hwnd, objectId, childId, eventThread, eventTime) =>
        {
            if (closingChat || IsDisposed || !IsHandleCreated || objectId != 0 || childId != 0) return;
            if (eventType == EVENT_SYSTEM_FOREGROUND)
            {
                KeepServerUpdatesInLauncherStack();
                return;
            }
            if (hwnd != owner) return;
            // Keep the Happy Hour banner aligned on EVERY owner movement
            // event, even if a chat reposition is already queued.
            // Native SetWindowPos runs immediately; BeginInvoke below is
            // retained only for the more expensive Game Chat layout.
            PositionHappyHourBanner();
            if (repositionQueued) return;
            repositionQueued = true;
            try
            {
                BeginInvoke((Action)(() =>
                {
                    repositionQueued = false;
                    if (!closingChat && !IsDisposed)
                    {
                        PositionChatWindows();
                        PositionServerUpdatesPanel();
                    }
                }));
            }
            catch (InvalidOperationException) { repositionQueued = false; }
        };
        // Observe the launcher's native movement, rather than waiting for the
        // 500ms Discord polling timer. Hook only the launcher's UI thread.
        launcherLocationHook = SetWinEventHook(0x800B, 0x800B, IntPtr.Zero,
            launcherLocationCallback, processId, threadId, 0);
        if (launcherLocationHook == IntPtr.Zero)
            Log("Launcher movement hook unavailable; using polling fallback.");
        launcherForegroundHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, IntPtr.Zero,
            launcherLocationCallback, 0, 0, 0);
    }

    bool docked;

    readonly string layoutFile = Path.Combine(AppContext.BaseDirectory, "chat.ini");

    DateTime layoutStamp;

    int chatWidth = 390, chatHeight = 498;

    byte chatOpacity = 255;

    static int ReadInt(string line, string key, int fallback) =>
        line.StartsWith(key + "=", StringComparison.OrdinalIgnoreCase)
        && int.TryParse(line[(key.Length + 1)..].Trim(), out var v) ? v : fallback;

    void LoadLayout()
    {
        if (!File.Exists(layoutFile)) return;
        var stamp = File.GetLastWriteTimeUtc(layoutFile);
        if (stamp == layoutStamp) return;
        foreach (var raw in File.ReadAllLines(layoutFile))
        {
            var line = raw.Trim();
            if (line.StartsWith(";") || line.StartsWith("[") || line.Length == 0) continue;
            chatWidth = Math.Clamp(ReadInt(line, "Width", chatWidth), 160, 700);
            chatHeight = Math.Clamp(ReadInt(line, "Height", chatHeight), 140, 700);
            chatOpacity = (byte)Math.Clamp(ReadInt(line, "Opacity", chatOpacity), 120, 255);
        }
        layoutStamp = stamp;
        if (docked) { PositionChatWindows(); ApplyWindowOpacity(); }
        Log("Layout reloaded");
    }

    void ApplyWindowOpacity()
    {
        if (!IsHandleCreated) return;
        var ex = GetWindowLongEx(Handle, GWL_EXSTYLE);
        if (chatOpacity == 255) { SetWindowLongEx(Handle, GWL_EXSTYLE, ex & ~WS_EX_LAYERED); return; }
        SetWindowLongEx(Handle, GWL_EXSTYLE, ex | WS_EX_LAYERED);
        if (!SetLayeredWindowAttributes(Handle, 0, chatOpacity, LWA_ALPHA))
            Log("Layered alpha failed: " + Marshal.GetLastWin32Error());
    }

    static double OwnerLayoutScale(int ownerWidth, int baseWidth, uint dpi) =>
        Math.Clamp(ownerWidth * 96d / (baseWidth * (dpi == 0 ? 96d : dpi)), 0.5, 1.0);

    static double FitPopupScale(double requested, int width, int height, Rectangle work, int margin = 0) =>
        Math.Min(requested, Math.Min(Math.Max(1, work.Width - margin * 2) / (double)width,
            Math.Max(1, work.Height - margin * 2) / (double)height));

    static Rectangle DockBounds(RECT ownerBounds, Rectangle work, Size size, int dockWidth)
    {
        // Prefer the left dock, choose the right when it fits, otherwise
        // use the side with more room and keep the whole popup onscreen.
        int leftSpace = ownerBounds.Left - work.Left;
        int rightSpace = work.Right - ownerBounds.Right;
        bool dockLeft = leftSpace >= dockWidth ||
            (rightSpace < dockWidth && leftSpace >= rightSpace);
        int x = dockLeft ? ownerBounds.Left - size.Width : ownerBounds.Right;
        int y = ownerBounds.Top + (ownerBounds.Bottom - ownerBounds.Top - size.Height) / 2;
        return new Rectangle(Math.Clamp(x, work.Left, work.Right - size.Width),
            Math.Clamp(y, work.Top, work.Bottom - size.Height), size.Width, size.Height);
    }

    void PositionChatWindows()
    {
        // Native owner movement covers scale previews and their rollback.
        // Chat polling also repairs placement if the native hook is unavailable.
        PositionHappyHourBanner();
        if (!IsWindow(owner) || !GetWindowRect(owner, out var bounds) ||
            bounds.Right <= bounds.Left || IsIconic(owner)) return;
        var work = Screen.FromHandle(owner).WorkingArea;
        if (work.Width <= 0 || work.Height <= 0) return;
        double launcherScale = OwnerLayoutScale(bounds.Right - bounds.Left, launcherBaseWidth, GetDpiForWindow(owner));
        int dockHeight = chatHeight + (nativeMode ? ChatComposerSpace : 0);
        double scale = FitPopupScale(launcherScale, chatWidth, dockHeight, work);
        int sideWidth = Math.Max(bounds.Left - work.Left, work.Right - bounds.Right);
        if (sideWidth >= Math.Min(220, Pixels(chatWidth, 0.5)))
            scale = Math.Min(scale, sideWidth / (double)chatWidth);
        UpdateChatScale(scale);
        var size = new Size(ChatPixels(chatWidth), ChatPixels(dockHeight));
        PositionDiscordSignIn(bounds, work);
        var target = DockBounds(bounds, work, size, size.Width);
        if (chatOpen && Bounds != target)
            MoveWindow(Handle, target.X, target.Y, target.Width, target.Height, true);
    }

    void DockToLauncher()
    {
        if (!IsWindow(owner)) return;
        var dockClock = System.Diagnostics.Stopwatch.StartNew();
        Log("STARTUP | Dock begin");
        var hwnd = Handle;
        SetParent(hwnd, IntPtr.Zero);
        Log("STARTUP | SetParent completed in " + dockClock.ElapsedMilliseconds + "ms");
        int style = GetWindowLong(hwnd, GWL_STYLE);
        SetWindowLong(hwnd, GWL_STYLE, (style | WS_POPUP) & ~WS_CHILD);
        ShowInTaskbar = false;
        // Native owner relationship keeps the chat above the launcher and
        // prevents it from becoming an independent Alt+Tab application.
        Log("STARTUP | Setting native owner");
        SetNativeWindowOwner(hwnd, owner);
        Log("STARTUP | Native owner set in " + dockClock.ElapsedMilliseconds + "ms");
        int chatExStyle = GetWindowLongEx(hwnd, GWL_EXSTYLE);
        SetWindowLongEx(hwnd, GWL_EXSTYLE,
            (chatExStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW);
        ApplyWindowOpacity();
        docked = true;
        WatchLauncherMovement();
        Log("STARTUP | Movement hook ready in " + dockClock.ElapsedMilliseconds + "ms");
        PositionChatWindows();
        SetChatOpen(chatDisplayMode == "Always Shown");
        // The owner, layout and saved visibility are now authoritative.
        // A first-run Automatic/Hidden panel is already SW_HIDE; an
        // Always Shown panel is now correctly docked before its first paint.
        if (startupPresentationPending)
        {
            startupPresentationPending = false;
            SetStartupWindowCloak(false);
        }
        Log("STARTUP | Chat position and visibility ready in " + dockClock.ElapsedMilliseconds + "ms");
        // Actual launcher movement repairs the missing frame pixels on layered AHK windows.
        // Reproduce that exact compositor event once, then restore its original position.
        if (GetWindowRect(owner, out var bounds))
        {
            const uint SWP_NOSIZE_NOZORDER_NOACTIVATE = 0x0001 | 0x0004 | 0x0010;
            Log("STARTUP | Owner compositor refresh begin");
            SetWindowPos(owner, IntPtr.Zero, bounds.Left + 1, bounds.Top, 0, 0, SWP_NOSIZE_NOZORDER_NOACTIVATE);
            Log("STARTUP | Owner compositor refresh first step in " + dockClock.ElapsedMilliseconds + "ms");
            SetWindowPos(owner, IntPtr.Zero, bounds.Left, bounds.Top, 0, 0, SWP_NOSIZE_NOZORDER_NOACTIVATE);
            Log("STARTUP | Owner compositor refresh completed in " + dockClock.ElapsedMilliseconds + "ms");
        }
        Log($"Docked chat ({chatWidth}x{chatHeight})");
    }
}
