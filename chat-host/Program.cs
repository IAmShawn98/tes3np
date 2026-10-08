using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;

internal static class Program
{
    const string Channel = "https://discord.com/channels/509601787901116437/1384271857842130994";
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr hwnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hwnd, int index, int value);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    const int GWL_STYLE = -16, WS_CHILD = 0x40000000, WS_POPUP = unchecked((int)0x80000000);
    const string Css = """
        :root, body, #app-mount { background: #201a15 !important; color: #e5d0a4 !important; }
        [class*="guilds_"], [class*="sidebar_"], [class*="sidebarList_"],
        [class*="membersWrap_"], [class*="members_"], [class*="panels_"],
        [class*="form_"], [class*="channelTextArea_"], [class*="toolbar_"],
        [class*="title_"], [class*="header_"], [class*="notice_"],
        [class*="chatHeaderBar_"], [class*="jumpToPresentBar_"],
        [class*="newMessagesBar_"], [class*="typing_"],
        [class*="avatar_"], [class*="botTag_"], [class*="buttons_"] { display:none !important; }
        [class*="base_"], [class*="content_"], [class*="chat_"],
        [class*="chatContent_"], [class*="messagesWrapper_"],
        [class*="scroller_"] { width:100% !important; min-width:0 !important; max-width:100% !important;
           margin:0 !important; padding-left:0 !important; }
        [class*="message_"] { min-height:0 !important; padding:2px 4px !important;
           margin:0 !important; background:transparent !important; }
        [class*="messageContent_"], [class*="markup_"] { font: 11px/1.27 Georgia, serif !important;
           color:#e5d0a4 !important; white-space:pre-wrap !important; overflow-wrap:anywhere !important; }
        [class*="username_"] { font: bold 10px Georgia, serif !important; color:#d3ab68 !important; }
        [class*="timestamp_"], [class*="divider_"], [class*="repliedMessage_"],
        [class*="messageAccessories_"], [class*="reaction_"] { display:none !important; }
        ::-webkit-scrollbar { width:5px !important; }
        ::-webkit-scrollbar-thumb { background:#85683d !important; }
        """;
    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length < 1 || !long.TryParse(args[0], out long owner)) return;
        ApplicationConfiguration.Initialize();
        Application.Run(new ChatHost(new IntPtr(owner)));
    }
    sealed class ChatHost : Form
    {
        readonly IntPtr owner;
        readonly WebView2 web = new() { Dock = DockStyle.Fill };
        readonly System.Windows.Forms.Timer watch = new() { Interval = 500 };
        bool docked;
        bool signInExpanded;
        bool channelReady;
        public ChatHost(IntPtr owner)
        {
            this.owner = owner;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            BackColor = System.Drawing.Color.FromArgb(32,26,21);
            Controls.Add(web);
            Width = 260; Height = 330;
            Shown += async (_, _) =>
            {
                try
                {
                    string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "tes3np", "chat-webview2");
                    Directory.CreateDirectory(data);
                    var env = await CoreWebView2Environment.CreateAsync(null, data);
                    await web.EnsureCoreWebView2Async(env);
                    web.CoreWebView2.Settings.AreDevToolsEnabled = false;
                    web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                    web.CoreWebView2.NavigationCompleted += async (_, _) =>
                    {
                        await UpdateViewMode();
                    };
                    web.CoreWebView2.LaunchingExternalUri += (_, e) =>
                    {
                        // Discord's desktop-app handoff must not steal navigation.
                        e.Cancel = true;
                    };
                    web.CoreWebView2.NewWindowRequested += (_, e) =>
                    {
                        e.Handled = true;
                        if (e.Uri.StartsWith("https://discord.com/", StringComparison.OrdinalIgnoreCase))
                            web.CoreWebView2.Navigate(e.Uri);
                    };
                    web.CoreWebView2.Navigate(Channel);
                }
                catch (Exception ex)
                {
                    MessageBox.Show("WebView2 chat unavailable: " + ex.Message + "\nInstall Microsoft Edge WebView2 Runtime.", "tes3np Chat");
                }
            };
            watch.Tick += (_, _) =>
            {
                if (!IsWindow(owner)) { Close(); return; }
                if (!docked && !signInExpanded && channelReady) DockToLauncher();
            };
            watch.Start();
        }
        async Task ApplyCss()
        {
            if (web.CoreWebView2 == null) return;
            var js = "(() => { const css = " + System.Text.Json.JsonSerializer.Serialize(Css) +
                "; let style=document.getElementById('tes3np-chat-style'); if(!style){style=document.createElement('style');style.id='tes3np-chat-style';document.head.appendChild(style);} style.textContent=css; })()";
            try { await web.CoreWebView2.ExecuteScriptAsync(js); } catch { }
        }
        async Task UpdateViewMode()
        {
            if (web.CoreWebView2 == null) return;
            // Only compact the authenticated channel. Leave login and all
            // authorization screens readable at full size.
            var url = web.CoreWebView2.Source;
            bool atChannel = url.StartsWith(Channel, StringComparison.OrdinalIgnoreCase);
            bool login = url.StartsWith("https://discord.com/login", StringComparison.OrdinalIgnoreCase)
                || url.StartsWith("https://discord.com/register", StringComparison.OrdinalIgnoreCase);
            bool messages = false, handoff = false;
            try
            {
                messages = await web.CoreWebView2.ExecuteScriptAsync(
                    "!!document.querySelector('[data-list-id=chat-messages]')") == "true";
                handoff = await web.CoreWebView2.ExecuteScriptAsync(
                    "!!document.body?.innerText?.includes('opened the link in your Discord app')") == "true";
            }
            catch { }
            channelReady = atChannel && messages && !handoff;
            if (channelReady)
            {
                signInExpanded = false;
                await ApplyCss();
                if (!docked) DockToLauncher();
                return;
            }
            if (login || handoff || !messages)
            {
                if (!signInExpanded)
                {
                    signInExpanded = true;
                    docked = false;
                    SetParent(Handle, IntPtr.Zero);
                    int style = GetWindowLong(Handle, GWL_STYLE);
                    SetWindowLong(Handle, GWL_STYLE, (style | WS_POPUP) & ~WS_CHILD);
                    MoveWindow(Handle, 180, 100, 900, 720, true);
                    ShowInTaskbar = true;
                    Text = "tes3np — Discord Sign In";
                }
            }
        }
        void DockToLauncher()
        {
            if (!IsWindow(owner)) return;
            var hwnd = Handle;
            SetParent(hwnd, owner);
            int style = GetWindowLong(hwnd, GWL_STYLE);
            SetWindowLong(hwnd, GWL_STYLE, (style | WS_CHILD) & ~WS_POPUP);
            MoveWindow(hwnd, 125, 315, 260, 330, true);
            ShowWindow(hwnd, 5);
            docked = true;
        }
    }
}
