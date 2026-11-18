using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Web.WebView2.Core;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const string DiscordLoginUrl = "https://discord.com/login";
    const uint DiscordAccountData = 0x8339;
    const uint DiscordSignOutFailed = 0x833A;

    enum DiscordAccountStatus { Checking, SignedOut, SignedIn, SigningOut }
    sealed record DiscordAccount(string Name, string? Avatar);

    static readonly Lazy<string> ReadDiscordAccount = GameChatWeb.Page("discord-account.js");
    DiscordAccountStatus discordAccountStatus;
    DiscordAccount? discordAccount;
    byte[]? discordAvatarPng;
    bool discordAccountDirty;
    bool readingDiscordAccount;
    DateTime nextDiscordAccountCheck;
    int discordAccountRevision;
    bool signingOutDiscord => discordAccountStatus == DiscordAccountStatus.SigningOut;

    void SetDiscordAccountStatus(DiscordAccountStatus status)
    {
        if (status == discordAccountStatus) return;
        discordAccountStatus = status;
        if (status == DiscordAccountStatus.SignedOut)
        {
            discordAccountRevision++;
            discordAccount = null;
            discordAvatarPng = null;
            nextDiscordAccountCheck = DateTime.MinValue;
        }
        discordAccountDirty = true;
    }

    async Task RefreshDiscordAccount(CoreWebView2 core, ulong navigationId, string url)
    {
        if (!IsDiscordAppRoute(url) || readingDiscordAccount || signingOutDiscord ||
            DateTime.UtcNow < nextDiscordAccountCheck) return;
        readingDiscordAccount = true;
        nextDiscordAccountCheck = DateTime.UtcNow.AddSeconds(discordAccount == null ? 2 : 15);
        try
        {
            string result = await core.ExecuteScriptAsync(ReadDiscordAccount.Value).WaitAsync(TimeSpan.FromSeconds(3));
            if (closingChat || signingOutDiscord || discordNavigationInProgress ||
                navigationId != discordNavigationId || !string.Equals(url, core.Source, StringComparison.OrdinalIgnoreCase))
                return;
            var profile = JsonSerializer.Deserialize<DiscordAccount>(result);
            if (string.IsNullOrWhiteSpace(profile?.Name) || profile.Name.Length > 128) return;
            string name = Regex.Replace(profile.Name, @"\p{Cc}+", "").Trim();
            if (name.Length == 0) return;
            var current = new DiscordAccount(name, NormalizeDiscordAvatar(profile.Avatar));
            SetDiscordAccountStatus(DiscordAccountStatus.SignedIn);
            if (current != discordAccount)
            {
                discordAccount = current;
                discordAvatarPng = null;
                discordAccountDirty = true;
                discordAccountRevision++;
            }
            if (discordAvatarPng == null && current.Avatar is { } avatar)
                _ = ReadDiscordAvatar(avatar, discordAccountRevision);
        }
        catch (Exception ex) { if (!closingChat) Log("Discord account display: " + ex.GetType().Name); }
        finally { readingDiscordAccount = false; }
    }

    static string? NormalizeDiscordAvatar(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var url) || url.Scheme != Uri.UriSchemeHttps ||
            (url.Host != "cdn.discordapp.com" && url.Host != "media.discordapp.net") ||
            !url.IsDefaultPort || url.UserInfo.Length != 0) return null;
        string path = url.AbsolutePath;
        if (!Regex.IsMatch(path, @"^/(?:avatars/\d+/(?:a_)?[a-fA-F0-9]+|embed/avatars/\d+|guilds/\d+/users/\d+/avatars/(?:a_)?[a-fA-F0-9]+)\.(?:gif|png|webp|jpg|jpeg|avif)$",
                RegexOptions.CultureInvariant | RegexOptions.IgnoreCase)) return null;
        return "https://cdn.discordapp.com" + Path.ChangeExtension(path, ".png") + "?size=64";
    }

    async Task ReadDiscordAvatar(string url, int revision)
    {
        try
        {
            await FetchChatImage(url);
            if (closingChat || signingOutDiscord || revision != discordAccountRevision ||
                !imageCache.TryGetValue(url, out var image)) return;
            using var square = new Bitmap(image, 64, 64);
            using var png = new MemoryStream();
            square.Save(png, ImageFormat.Png);
            if (png.Length > 32_768) return;
            discordAvatarPng = png.ToArray();
            discordAccountDirty = true;
        }
        catch (Exception ex) { if (!closingChat) Log("Discord avatar display: " + ex.GetType().Name); }
    }

    void PublishDiscordAccount()
    {
        if (!discordAccountDirty || closingChat || !IsHandleCreated || !IsWindow(owner)) return;
        // WM_COPYDATA carries a state, UTF-16 display name and optional 64px PNG.
        // Keep the name and image in memory and acknowledge delivery before reuse.
        bool signedIn = discordAccountStatus == DiscordAccountStatus.SignedIn;
        byte[] name = Encoding.Unicode.GetBytes(signedIn ? discordAccount?.Name ?? "" : "");
        byte[] avatar = signedIn ? discordAvatarPng ?? [] : [];
        using var payload = new MemoryStream(8 + name.Length + avatar.Length);
        using var writer = new BinaryWriter(payload);
        writer.Write((int)discordAccountStatus);
        writer.Write(name.Length);
        writer.Write(name);
        writer.Write(avatar);
        byte[] bytes = payload.ToArray();
        var pin = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            var data = new COPYDATASTRUCT { dwData = new IntPtr(DiscordAccountData), cbData = bytes.Length,
                lpData = pin.AddrOfPinnedObject() };
            var delivered = SendCopyDataTimeout(owner, 0x004A, Handle, ref data, 0x0003, 200, out var result);
            discordAccountDirty = delivered == IntPtr.Zero || result == IntPtr.Zero;
        }
        finally { pin.Free(); }
    }

    void OpenDiscordAccountSignIn()
    {
        if (signingOutDiscord || discordAccountStatus == DiscordAccountStatus.SignedIn) return;
        discordSignInRequested = true;
        if (web.CoreWebView2 is not { } core) return;
        // Let an existing authenticated page finish checking before navigating away.
        if (discordAccountStatus == DiscordAccountStatus.Checking) return;
        ShowDiscordSignIn();
        RevealDiscordSignInWindow();
        if (!string.Equals(core.Source, DiscordLoginUrl, StringComparison.OrdinalIgnoreCase))
            core.Navigate(DiscordLoginUrl);
    }

    async Task SignOutDiscord()
    {
        if (closingChat || signingOutDiscord || discordAccountStatus != DiscordAccountStatus.SignedIn ||
            web.CoreWebView2 is not { } core) return;

        SetDiscordAccountStatus(DiscordAccountStatus.SigningOut);
        discordAccountRevision++;
        PublishDiscordAccount();
        SuspendHappyHourUntilDiscordReturns("signed out in the launcher");
        DismissDiscordSignIn();
        CloseEmbeddedExpansionDownloads();
        SetChatOpen(false);
        lastFeed = "";
        feedInitialized = false;

        // Unload the Discord document before clearing the launcher-only browser
        // profile so scripts in the old account cannot repopulate its storage.
        const string blank = "about:blank";
        var unloaded = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnBlankLoaded(object? sender, CoreWebView2NavigationCompletedEventArgs e)
        {
            if (e.NavigationId == discordNavigationId && core.Source == blank)
                unloaded.TrySetResult(e.IsSuccess);
        }
        core.NavigationCompleted += OnBlankLoaded;
        try
        {
            core.Navigate(blank);
            if (!await unloaded.Task.WaitAsync(TimeSpan.FromSeconds(5)))
                throw new InvalidOperationException("Could not unload the previous Discord account.");
            if (closingChat || IsDisposed) return;
            await core.Profile.ClearBrowsingDataAsync(CoreWebView2BrowsingDataKinds.AllSite);
            if (closingChat || IsDisposed) return;
            freshDiscordProfile = false;
            SetDiscordAccountStatus(DiscordAccountStatus.SignedOut);
            ShowDiscordSignIn();
            core.Navigate(DiscordLoginUrl);
        }
        catch (Exception ex)
        {
            if (closingChat || IsDisposed) return;
            Log("Discord sign-out: " + ex.GetType().Name);
            if (signingOutDiscord)
            {
                SetDiscordAccountStatus(DiscordAccountStatus.SignedIn);
                nextDiscordAccountCheck = DateTime.MinValue;
                PostMessage(owner, DiscordSignOutFailed, IntPtr.Zero, Handle);
                try { core.Navigate(Channel); }
                catch (Exception recoveryError) { Log("Discord sign-out recovery: " + recoveryError.GetType().Name); }
            }
        }
        finally
        {
            if (!closingChat && !IsDisposed) core.NavigationCompleted -= OnBlankLoaded;
        }
    }
}
