using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;

internal static class Program
{
    const string ChatBuild = "chat-layout-20261008-b";
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
        /* TES3NP compact, read-only message feed */
        :root, html, body, #app-mount {
          background: #17130e !important; color: #ead6aa !important;
          overflow: hidden !important;
        }
        [class*="guilds_"], [class*="sidebar_"], [class*="sidebarList_"],
        [class*="membersWrap_"], [class*="members_"], [class*="panels_"],
        [class*="form_"], [class*="channelTextArea_"], [class*="toolbar_"],
        [class*="notice_"], [class*="titleWrapper_"], [class*="upperContainer_"],
        [class*="chatHeaderBar_"], [class*="jumpToPresentBar_"],
        [class*="newMessagesBar_"], [class*="typing_"],
        [class*="avatar_"], [class*="botTag_"], [class*="buttons_"],
        [class*="channelName_"], [class*="chatHeader_"], [class*="searchBar_"],
        [class*="topic_"], [class*="titleContainer_"], [class*="threadSidebar_"],
        [class*="sidebarRegion_"], [class*="pageHeader_"],
        [class*="scrollerSpacer_"], [class*="welcomeMessage_"] {
          display: none !important;
        }
        [class*="base_"], [class*="content_"], [class*="chat_"],
        [class*="chatContent_"], [class*="messagesWrapper_"],
        [class*="scroller_"], [class*="scrollerContent_"] {
          width: 100% !important; min-width: 0 !important; max-width: 100% !important;
          margin: 0 !important; padding-left: 0 !important;
          padding-right: 0 !important; border: 0 !important;
        }
        [data-list-id="chat-messages"] { padding: 4px 0 8px !important; }
        [class*="message_"] {
          min-height: 0 !important; padding: 5px 10px !important;
          margin: 0 !important; background: transparent !important;
          border: 0 !important; box-shadow: none !important;
        }
        [class*="messageContent_"], [class*="markup_"] {
          font: 13px/1.4 Georgia, "Palatino Linotype", serif !important;
          color: #ead6aa !important; white-space: pre-wrap !important;
          overflow-wrap: anywhere !important; letter-spacing: .08px !important;
        }
        [class*="username_"] {
          font: bold 12px/1.35 Georgia, serif !important;
          color: #d8b26d !important; letter-spacing: .2px !important;
        }
        [class*="timestamp_"], [class*="divider_"], [class*="repliedMessage_"],
        [class*="messageAccessories_"], [class*="reaction_"],
        [class*="buttonContainer_"], [class*="messageToolbar_"] {
          display: none !important;
        }
        ::-webkit-scrollbar { width: 7px !important; }
        ::-webkit-scrollbar-track { background: #211a13 !important; }
        ::-webkit-scrollbar-thumb {
          background: #876a43 !important; border: 1px solid #3c2b1b !important;
          border-radius: 3px !important;
        }
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
        readonly string cssFile = Path.Combine(AppContext.BaseDirectory, "chat.css");
        readonly string layoutFile = Path.Combine(AppContext.BaseDirectory, "chat.ini");
        DateTime cssStamp = DateTime.MinValue, layoutStamp = DateTime.MinValue;
        int chatX = 54, chatY = 278, chatWidth = 266, chatHeight = 342;
        string userCss = Css;
        static int ReadInt(string line, string key, int fallback) =>
            line.StartsWith(key + "=", StringComparison.OrdinalIgnoreCase)
            && int.TryParse(line[(key.Length + 1)..].Trim(), out var v) ? v : fallback;
        void LoadLayout()
        {
            if (!File.Exists(layoutFile)) return;
            var stamp = File.GetLastWriteTimeUtc(layoutFile);
            if (stamp == layoutStamp) return;
            layoutStamp = stamp;
            foreach (var raw in File.ReadAllLines(layoutFile))
            {
                var line = raw.Trim();
                if (line.StartsWith(";") || line.StartsWith("[") || line.Length == 0) continue;
                chatX = ReadInt(line, "X", chatX);
                chatY = ReadInt(line, "Y", chatY);
                chatWidth = Math.Clamp(ReadInt(line, "Width", chatWidth), 160, 700);
                chatHeight = Math.Clamp(ReadInt(line, "Height", chatHeight), 140, 700);
            }
            if (docked) MoveWindow(Handle, chatX, chatY, chatWidth, chatHeight, true);
            Log("Layout reloaded");
        }
        async Task LoadCss()
        {
            if (!File.Exists(cssFile)) return;
            var stamp = File.GetLastWriteTimeUtc(cssFile);
            if (stamp == cssStamp) return;
            cssStamp = stamp;
            userCss = File.ReadAllText(cssFile);
            await ApplyCss();
            Log("CSS reloaded");
        }

        readonly Label version = new() { Text = "TES3NP CHAT • " + ChatBuild, Dock = DockStyle.Top, Height = 24, ForeColor = System.Drawing.Color.FromArgb(225, 191, 125), BackColor = System.Drawing.Color.FromArgb(35, 26, 18), TextAlign = System.Drawing.ContentAlignment.MiddleCenter, Font = new System.Drawing.Font("Georgia", 9f, System.Drawing.FontStyle.Bold) };
        readonly string logPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "tes3np", "chat-host.log");
        void Log(string message) { try { Directory.CreateDirectory(Path.GetDirectoryName(logPath)!); File.AppendAllText(logPath, DateTime.Now.ToString("s") + " | " + ChatBuild + " | " + message + Environment.NewLine); } catch { } }
        public ChatHost(IntPtr owner)
        {
            this.owner = owner;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            BackColor = System.Drawing.Color.FromArgb(32,26,21);
            Controls.Add(web);
            Controls.Add(version);
            Log("Host launched; owner=" + owner);
            Width = 266; Height = 342;
            LoadLayout();

            Shown += async (_, _) =>
            {
                // Let WinForms finish showing the top-level host before parenting it.
                BeginInvoke((Action)(() => DockToLauncher()));
                try
                {
                    string data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "tes3np", "chat-webview2");
                    Directory.CreateDirectory(data);
                    var env = await CoreWebView2Environment.CreateAsync(null, data);
                    await web.EnsureCoreWebView2Async(env);
                    await LoadCss();
                    Log("WebView2 initialized");
                    web.CoreWebView2.Settings.AreDevToolsEnabled = false;
                    web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                    // Install styling before Discord's SPA renders, and keep
                    // it in place as React replaces DOM nodes.
                    await web.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(
                        "(() => { const css = " + System.Text.Json.JsonSerializer.Serialize(userCss) +
                        "; const install=()=>{if(!document.head)return;let s=document.getElementById('tes3np-chat-style');if(!s){s=document.createElement('style');s.id='tes3np-chat-style';document.head.appendChild(s)}s.textContent=css};install();document.addEventListener('DOMContentLoaded',install);new MutationObserver(()=>{if(!document.getElementById('tes3np-chat-style'))install()}).observe(document,{childList:true,subtree:true});})()");
                    web.CoreWebView2.NavigationCompleted += async (_, _) => await UpdateViewMode();
                    web.CoreWebView2.NewWindowRequested += (_, e) =>
                    {
                        e.Handled = true;
                        if (e.Uri.StartsWith("https://discord.com/", StringComparison.OrdinalIgnoreCase))
                            web.CoreWebView2.Navigate(e.Uri);
                    };
                    web.CoreWebView2.Navigate(Channel);
                    Log("Navigating to channel");
                }
                catch (Exception ex)
                {
                    Log("ERROR " + ex);
                    MessageBox.Show("WebView2 chat unavailable: " + ex.Message + "\nInstall Microsoft Edge WebView2 Runtime.", "tes3np Chat");
                }
            };
            watch.Tick += async (_, _) =>
            {
                if (!IsWindow(owner)) { Close(); return; }
                try { LoadLayout(); await LoadCss(); } catch (Exception ex) { Log("Reload error: " + ex.Message); }
                if (!docked && !signInExpanded) DockToLauncher();
            };
            watch.Start();
        }
        async Task ApplyCss()
        {
            if (web.CoreWebView2 == null) return;
            var js = "(() => { const css = " + System.Text.Json.JsonSerializer.Serialize(userCss) +
                "; let style=document.getElementById('tes3np-chat-style'); if(!style){style=document.createElement('style');style.id='tes3np-chat-style';document.head.appendChild(style);} style.textContent=css; })()";
            try { await web.CoreWebView2.ExecuteScriptAsync(js); } catch (Exception ex) { Log("CSS error: " + ex.Message); }
        }
        async Task UpdateViewMode()
        {
            if (web.CoreWebView2 == null) return;
            var url = web.CoreWebView2.Source;
            Log("Navigation completed: " + url);
            bool login = url.StartsWith("https://discord.com/login", StringComparison.OrdinalIgnoreCase)
                || url.StartsWith("https://discord.com/register", StringComparison.OrdinalIgnoreCase);
            if (login && !signInExpanded)
            {
                signInExpanded = true;
                docked = false;
                SetParent(Handle, IntPtr.Zero);
                int style = GetWindowLong(Handle, GWL_STYLE);
                SetWindowLong(Handle, GWL_STYLE, (style | WS_POPUP) & ~WS_CHILD);
                MoveWindow(Handle, 180, 100, 900, 720, true);
                ShowInTaskbar = true;
                Text = "tes3np — Discord Sign In";
                return;
            }
            if (!login && signInExpanded)
            {
                signInExpanded = false;
                DockToLauncher();
            }
            if (!login)
                await ApplyCss();
        }
        void DockToLauncher()
        {
            if (!IsWindow(owner) || signInExpanded) return;
            var hwnd = Handle;
            int style = GetWindowLong(hwnd, GWL_STYLE);
            SetWindowLong(hwnd, GWL_STYLE, (style | WS_CHILD) & ~WS_POPUP);
            SetParent(hwnd, owner);
            MoveWindow(hwnd, chatX, chatY, chatWidth, chatHeight, true);
            ShowWindow(hwnd, 5);
            docked = true;
            Log("Docked 54,278 266x342");
        }
    }
}
