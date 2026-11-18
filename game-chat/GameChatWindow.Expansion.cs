using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    // Same NP Discord guild as Game Chat, but a different channel and raw WebView2.
    const string ExpansionChannel = "https://discord.com/channels/509601787901116437/1555049936800718928";

    Form? expansionDownloadsWindow;

    WebView2? expansionDownloadsBrowser;

    IntPtr expansionDownloadsParent = IntPtr.Zero;

    WebView2? initializingExpansionBrowser;

    // The latest *validated* signed URL lives only in this ChatHost
    // session; native retry never depends on a responsive WebView2.
    string? expansionLatestZipUrl;

    string? expansionPublishedZipUrl;

    readonly Dictionary<string, string> expansionZipChecksums = new(StringComparer.Ordinal);

    int expansionLinkRevision;

    // Discord feature dialogs reuse the existing Chat Host authentication.
    int pendingExpansionPrompt;
    ulong expansionPromptGeneration;

    bool restoreChatAfterExpansionPrompt;

    readonly object expansionLinkPublishLock=new();

    // Preserve Discord's React tree and grid intact behind an opaque card.
    // Extract ONLY the latest visible official ZIP attachment and link to
    // its actual Discord CDN URL. Never create a fake download link.
    // The Discord message list is virtualized. Only show a ZIP after we
    // reach the newest messages; compare real Discord snowflake IDs rather
    // than treating the last rendered anchor as the latest upload. A
    // bounded backfill handles archives where the ZIP is off-screen.
    // Discord can still change its DOM; the manual channel link remains.
    static readonly Lazy<string> ExpansionDownloadsFocusScript = GameChatWeb.Page("expansion-downloads.js");

    void CloseEmbeddedExpansionDownloads(IntPtr requestedParent = default)
    {
        if (requestedParent != IntPtr.Zero && requestedParent != expansionDownloadsParent)
            return;
        try { expansionAutoDownloadCancellation?.Cancel(); }
        catch (ObjectDisposedException) { }
        expansionDownloadsParent=IntPtr.Zero;
        expansionLatestZipUrl=null;
        expansionPublishedZipUrl=null;
        Interlocked.Increment(ref expansionLinkRevision);
        var window=expansionDownloadsWindow;
        expansionDownloadsWindow=null;
        expansionDownloadsBrowser=null;
        if (window is { IsDisposed: false }) {
            try { window.Dispose(); }
            catch (Exception ex) { Log("EXPANSION | Child cleanup: "+ex.GetType().Name); }
        }
    }

    void CheckExpansionDownloadSilently(IntPtr placeholder)
    {
        if (discordChannelReady && !discordLoginVisible && !closingChat)
            ShowEmbeddedExpansionDownloads(placeholder);
        else if (IsWindow(placeholder) && IsWindow(owner))
            PublishExpansionLink(placeholder, Handle, "", "");
    }

    void ShowEmbeddedExpansionDownloads(IntPtr placeholder)
    {
        if (!discordChannelReady || discordLoginVisible || closingChat)
        {
            Log("EXPANSION | Refused unauthenticated embedded Discord surface.");
            return;
        }
        if (closingChat || !IsWindow(owner) || !IsWindow(placeholder)) return;
        if (expansionDownloadsParent==placeholder &&
            expansionDownloadsWindow is { IsDisposed: false }) return;
        CloseEmbeddedExpansionDownloads();
        try
        {
            var window=new Form {
                Text="tes3np Expansion ZIP",FormBorderStyle=FormBorderStyle.None,
                ShowInTaskbar=false,StartPosition=FormStartPosition.Manual,
                BackColor=System.Drawing.Color.FromArgb(27,27,31),
                AutoScaleMode=AutoScaleMode.None
            };
            var browser=new WebView2 { Dock=DockStyle.Fill };
            window.Controls.Add(browser);
            // Register before native reparenting so even a failed SetParent
            // disposes the newly created Form and WebView2 together.
            expansionDownloadsWindow=window;
            expansionDownloadsBrowser=browser;
            expansionDownloadsParent=placeholder;
            IntPtr handle=window.Handle;
            int style=GetWindowLong(handle,GWL_STYLE);
            const int WS_CLIPSIBLINGS=0x04000000;
            SetWindowLong(handle,GWL_STYLE,
                (style | WS_CHILD | WS_CLIPSIBLINGS) & ~WS_POPUP);
            SetParent(handle,placeholder);
            if (GetParent(handle)!=placeholder)
                throw new InvalidOperationException("Discord browser did not attach to the dialog.");
            PositionEmbeddedExpansionDownloads();
            ShowWindow(handle,5);
            _=InitializeExpansionDownloadsBrowser();
            Log("EXPANSION | Embedded newest ZIP in plugin-mismatch dialog.");
        }
        catch(Exception ex)
        {
            Log("EXPANSION | Cannot mount browser: "+ex.GetType().Name);
            CloseEmbeddedExpansionDownloads();
        }
    }

    void HideEmbeddedExpansionDownloads(IntPtr placeholder)
    {
        // Never tear down or reparent a live WebView2 because a download
        // started. Hiding its native child keeps the shared Discord
        // environment and Game Chat untouched, and lets the launcher-owned
        // ZIP button handle subsequent clicks independently.
        if (placeholder==IntPtr.Zero || placeholder!=expansionDownloadsParent ||
            expansionLatestZipUrl==null || !IsWindow(placeholder))
            return;
        var window=expansionDownloadsWindow;
        if (window==null || window.IsDisposed || !window.IsHandleCreated)
            return;
        ShowWindow(window.Handle,0); // SW_HIDE; no Dispose and no new Form
        Log("EXPANSION | Discovery WebView hidden; launcher-native ZIP card remains.");
    }

    void PositionEmbeddedExpansionDownloads()
    {
        var window=expansionDownloadsWindow;
        if (window==null || window.IsDisposed || !window.IsHandleCreated ||
            !IsWindow(expansionDownloadsParent)) return;
        if (!GetClientRect(expansionDownloadsParent,out var box)) return;
        MoveWindow(window.Handle,0,0,Math.Max(1,box.Right-box.Left),
            Math.Max(1,box.Bottom-box.Top),true);
    }

    void PublishExpansionLink(IntPtr slot, IntPtr sender, string url, string checksum, string history = "")
    {
        string payload = slot.ToInt64().ToString(System.Globalization.CultureInfo.InvariantCulture) + "|"
            + (url.Length == 0 ? "|" : url + "|" + checksum + "|" + history);
        IntPtr utf16 = IntPtr.Zero;
        try
        {
            utf16=Marshal.StringToHGlobalUni(payload);
            var data=new COPYDATASTRUCT {
                dwData=new IntPtr(0x8335),
                cbData=checked((payload.Length+1)*2),
                lpData=utf16
            };
            // SMTO_ABORTIFHUNG. Bounded IPC keeps the Chat Host
            // independent if AHK's owner window becomes busy.
            IntPtr delivered=SendCopyDataTimeout(owner,0x004A,sender,
                ref data,0x0002,1500,out var result);
            if (delivered==IntPtr.Zero || result==IntPtr.Zero)
                Log("EXPANSION | Native ZIP retry link handoff was not acknowledged.");
            else
                Log("EXPANSION | Native ZIP retry link synchronized.");
        }
        catch (Exception ex)
        {
            Log("EXPANSION | Native ZIP link handoff failed: "+ex.GetType().Name);
        }
        finally
        {
            if (utf16!=IntPtr.Zero) Marshal.FreeHGlobal(utf16);
        }
    }

    async Task InitializeExpansionDownloadsBrowser()
    {
        var browser=expansionDownloadsBrowser;
        var env=discordEnvironment;
        if (browser==null || browser.IsDisposed || env==null ||
            ReferenceEquals(initializingExpansionBrowser, browser) || browser.CoreWebView2!=null ||
            closingChat || !IsWindow(expansionDownloadsParent)) return;
        initializingExpansionBrowser=browser;
        try
        {
            await browser.EnsureCoreWebView2Async(env);
            if (closingChat || !ReferenceEquals(browser, expansionDownloadsBrowser) ||
                browser.IsDisposed || browser.CoreWebView2==null) return;
            await browser.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(
                ExpansionDownloadsFocusScript.Value);
            if (closingChat || !ReferenceEquals(browser, expansionDownloadsBrowser) || browser.IsDisposed) return;
            browser.CoreWebView2.WebMessageReceived+=(sender,args)=>{
                if (closingChat || !ReferenceEquals(browser, expansionDownloadsBrowser) ||
                    !Uri.TryCreate(args.Source, UriKind.Absolute, out var source) ||
                    !string.Equals(source.GetLeftPart(UriPartial.Path).TrimEnd('/'), ExpansionChannel,
                        StringComparison.OrdinalIgnoreCase)) return;
                try {
                    using var json=System.Text.Json.JsonDocument.Parse(args.WebMessageAsJson);
                    if (!json.RootElement.TryGetProperty("type",out var kind)) return;
                    string? type=kind.GetString();
                    if (type=="expansion-layout" && json.RootElement.TryGetProperty("status",out _))
                    {
                        Log("EXPANSION | ZIP card status updated.");
                    }
                    else if ((type=="expansion-available" || type=="expansion-download") &&
                        json.RootElement.TryGetProperty("url",out var requested) &&
                        requested.ValueKind==System.Text.Json.JsonValueKind.String)
                    {
                        string? link=requested.GetString();
                        if (!IsOfficialExpansionDownloadUrl(link))
                        {
                            Log("EXPANSION | Rejected invalid Discord ZIP link.");
                            return;
                        }
                        // A new post or refreshed CDN signature replaces the
                        // stored URL. Never persist it or log its auth query.
                        if (type == "expansion-available")
                        {
                            var history = new List<string>();
                            if (json.RootElement.TryGetProperty("history", out var entries)
                                && entries.ValueKind == System.Text.Json.JsonValueKind.Array)
                            {
                                foreach (var entry in entries.EnumerateArray().Take(3))
                                {
                                    string? older = entry.ValueKind == System.Text.Json.JsonValueKind.String
                                        ? entry.GetString() : null;
                                    if (IsOfficialExpansionDownloadUrl(older) && older != link)
                                        history.Add(older!);
                                }
                            }
                            expansionLatestZipUrl = link;
                            PublishExpansionUrlToLauncher(link!, history);
                        }
                        if (type=="expansion-download")
                            RequestExpansionDownload(link,"embedded-card");
                    }
                }
                catch (Exception ex) {
                    Log("EXPANSION | Invalid download message: "+ex.GetType().Name);
                }
            };
            browser.CoreWebView2.NavigationCompleted+=async (_,e)=>{
                Log("EXPANSION | Discord page "+(e.IsSuccess?"loaded":"failed: "+e.WebErrorStatus));
                if (!e.IsSuccess || browser.IsDisposed || browser.CoreWebView2==null) return;
                try { await browser.CoreWebView2.ExecuteScriptAsync(ExpansionDownloadsFocusScript.Value); }
                catch (Exception ex) { Log("EXPANSION | Card refresh: "+ex.GetType().Name); }
            };
            // Defensive only: downloads are dispatched through WebMessageReceived.
            // An unexpected WebView2 download must not silently replace the
            // authenticated channel or navigate away from this ZIP card.
            browser.CoreWebView2.DownloadStarting+=(_,e)=>{
                Log("EXPANSION | Unexpected in-WebView download; deferring to default browser.");
                e.Cancel=true;
            };
            browser.CoreWebView2.Navigate(ExpansionChannel);
        }
        catch(Exception ex) { if (!closingChat) Log("EXPANSION | Embed load failed: "+ex.GetType().Name); }
        finally
        {
            if (ReferenceEquals(initializingExpansionBrowser, browser)) initializingExpansionBrowser=null;
        }
    }

    // Launcher command 12 retries a pending authenticated Expansion
    // request; a lost launcher acknowledgement cannot strand the menu.
    void RetryAuthenticatedExpansionPrompt(int mode)
    {
        if ((mode != 1 && mode != 2) || closingChat || !IsWindow(owner)) return;
        if (pendingExpansionPrompt == 0)
        {
            RequestAuthenticatedExpansionPrompt(mode);
            return;
        }
        if (discordLoginVisible) RevealDiscordSignInWindow();
        _ = ResolvePendingExpansionPromptAsync();
    }

    // Launcher command 10 requests an Expansion Pack download dialog.
    // Only confirmed Game Chat channel authentication allows the dialog.
    // Signed-out users see the already-established branded login screen.
    void RequestAuthenticatedExpansionPrompt(int mode)
    {
        if ((mode != 1 && mode != 2) || closingChat || !IsWindow(owner)) return;
        if (pendingExpansionPrompt != 0) return;
        pendingExpansionPrompt = mode;
        expansionPromptGeneration++;
        restoreChatAfterExpansionPrompt = !chatOpen;
        if (!discordChannelReady) discordSignInRequested = true;
        if (discordLoginVisible) RevealDiscordSignInWindow();
        // The previous channelReady flag may be stale after a sign-out.
        // Independently probe the live Discord DOM before revealing any
        // Discord-backed popup, even for previously signed-in users.
        _ = ResolvePendingExpansionPromptAsync();
    }

    async Task ResolvePendingExpansionPromptAsync()
    {
        if (pendingExpansionPrompt == 0 || closingChat || IsDisposed) return;
        ulong requestGeneration = expansionPromptGeneration;
        ulong navigationId = discordNavigationId;
        if (discordChannelReady && !discordLoginVisible && web.CoreWebView2 != null)
        {
            if (discordNavigationInProgress) return;
            var core = web.CoreWebView2;
            try
            {
                string before = core.Source ?? "";
                if (IsGameChatRoute(before))
                {
                    string live = await core.ExecuteScriptAsync(
                        "(() => !!document.querySelector('[data-list-id=chat-messages]'))()")
                        .WaitAsync(TimeSpan.FromSeconds(4));
                    if (!IsCurrentExpansionPrompt(requestGeneration, navigationId)) return;
                    if (live == "true" &&
                        string.Equals(core.Source, before, StringComparison.OrdinalIgnoreCase))
                    {
                        CompletePendingExpansionPrompt();
                        return;
                    }
                }
            }
            catch (Exception ex)
            {
                Log("EXPANSION | Live Discord authorization check: " + ex.GetType().Name);
            }
            // Never trust a ready flag if the live channel DOM disappeared.
            if (!IsCurrentExpansionPrompt(requestGeneration, navigationId)) return;
            SuspendHappyHourUntilDiscordReturns("live expansion authentication check");
        }
        if (pendingExpansionPrompt == 0 || closingChat || IsDisposed) return;
        lastChatActivity = DateTime.Now;
        SetChatOpen(true);
        Log("EXPANSION | Waiting for existing Discord Game Chat authentication.");
        // Normal navigation/polling reveals the established branded
        // Discord login; do not reset the profile or open a new browser.
    }

    bool IsCurrentExpansionPrompt(ulong requestGeneration, ulong navigationId) =>
        pendingExpansionPrompt != 0 && requestGeneration == expansionPromptGeneration &&
        navigationId == discordNavigationId && !discordNavigationInProgress && !closingChat && !IsDisposed;

    void CancelPendingExpansionPrompt(bool notifyLauncher = true)
    {
        if (pendingExpansionPrompt == 0) return;
        pendingExpansionPrompt = 0;
        restoreChatAfterExpansionPrompt = false;
        // A launcher-initiated close already cleared its own pending state.
        // Don't send a stale zero acknowledgement into a rapidly reopened
        // dialog; user-initiated login cancellation still informs launcher.
        if (notifyLauncher && IsWindow(owner))
            PostMessage(owner, 0x8336, IntPtr.Zero, Handle);
    }

    void CompletePendingExpansionPrompt()
    {
        if (pendingExpansionPrompt == 0 || !discordChannelReady ||
            discordLoginVisible || closingChat || !IsWindow(owner)) return;
        int mode = pendingExpansionPrompt;
        pendingExpansionPrompt = 0;
        PostMessage(owner, 0x8336, new IntPtr(mode), Handle);
        if (restoreChatAfterExpansionPrompt && chatDisplayMode != "Always Shown")
            SetChatOpen(false);
        restoreChatAfterExpansionPrompt = false;
        Log("EXPANSION | Authenticated download prompt approved.");
    }
}
