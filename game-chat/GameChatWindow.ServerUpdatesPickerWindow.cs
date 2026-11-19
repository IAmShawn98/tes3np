using System.Drawing;
using System.Text;
using System.Text.Json;

internal sealed partial class GameChatWindow
{
    static readonly Lazy<Dictionary<string, string>> PickerGlyphs = new(() =>
        JsonSerializer.Deserialize<Dictionary<string, string>>(GameChatWeb.Page("discord-emoji-shortcodes.json").Value) ?? []);
    sealed record BundledEmoji(string Glyph, string[] Aliases);
    static readonly string[] PickerCommonAliases = ["thumbsup", "heart", "fire", "joy", "rofl", "eyes", "tada", "wave", "clap", "100"];
    static readonly Lazy<BundledEmoji[]> BundledEmojiCatalog = new(() => PickerGlyphs.Value
        .GroupBy(item => item.Value, StringComparer.Ordinal)
        .Select(group => new BundledEmoji(group.Key, group.Select(item => item.Key).OrderBy(alias => alias.Length).ToArray()))
        .OrderBy(item =>
        {
            int priority = Array.FindIndex(PickerCommonAliases, alias => item.Aliases.Contains(alias));
            return priority >= 0 ? priority : PickerCommonAliases.Length;
        })
        .ThenBy(item => item.Aliases[0], StringComparer.Ordinal).ToArray());
    NativeServerUpdatePicker? nativeServerUpdatePicker;

    async Task<string?> ShowServerUpdatePicker(LatestUpdatesPanel panel, string postId)
    {
        await Task.Yield();
        if (panel != serverUpdatesPanel || !CanShowServerUpdates || !displayedServerUpdates.Any(post => post.Id == postId))
            return "This update is no longer available.";
        if (nativeServerUpdatePicker is { } current)
        {
            current.Activate();
            return null;
        }
        if (workingServerUpdateReaction) return "Wait for the current reaction to finish.";
        var hostContext = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
        var picker = new NativeServerUpdatePicker(panel.RectangleToScreen(panel.ClientRectangle),
            Math.Max(96, (int)GameChatNative.GetDpiForWindow(owner)));
        nativeServerUpdatePicker = picker;
        void PostToHost(Action callback)
        {
            try { hostContext.Post(_ => callback(), null); }
            catch (InvalidOperationException) { }
        }
        try
        {
            picker.Start((kind, key, query) => PostToHost(async () =>
            {
                if (nativeServerUpdatePicker != picker) return;
                if (kind == "picker-close")
                {
                    StopServerUpdatePicker();
                    Log("SERVER UPDATES | Picker closed");
                    return;
                }
                bool trace = kind is "picker" or "picker-select" or "picker-local";
                if (trace) Log("SERVER UPDATES | Picker action started: " + kind);
                PickerReply result;
                try { result = await ActOnServerUpdatePicker(panel, new(kind, postId, key, Query: query)); }
                catch (Exception ex)
                {
                    Log("SERVER UPDATES | Picker action: " + ex.GetType().Name);
                    CloseServerUpdatePicker();
                    result = new(Error: "Discord could not update the emoji list.");
                }
                if (trace) Log("SERVER UPDATES | Picker action returned: " + kind);
                if (nativeServerUpdatePicker != picker) return;
                if (result.Close) StopServerUpdatePicker();
                else picker.Reply(kind, result);
            }), error => PostToHost(() => Log("SERVER UPDATES | Picker window: " + error.GetType().Name)));
        }
        catch (Exception ex)
        {
            nativeServerUpdatePicker = null;
            Log("SERVER UPDATES | Picker startup: " + ex.GetType().Name);
            return "The emoji picker could not open.";
        }
        return null;
    }

    void StopServerUpdatePicker(bool resume = true)
    {
        var picker = nativeServerUpdatePicker;
        nativeServerUpdatePicker = null;
        picker?.Close();
        CloseServerUpdatePicker(resume);
    }

    static string DisplayPickerGlyph(PickerEmoji emoji)
    {
        if (emoji.Text.EnumerateRunes().Any(rune => rune.Value >= 0x1F000 ||
                rune.Value is >= 0x2190 and <= 0x27FF || rune.Value is 0x00A9 or 0x00AE or 0x20E3)) return emoji.Text;
        string Normalize(string name) => name.Trim().Trim(':').ToLowerInvariant().Replace(' ', '_').Replace('-', '_');
        if (PickerGlyphs.Value.TryGetValue(Normalize(emoji.Name), out var glyph) ||
            PickerGlyphs.Value.TryGetValue(Normalize(emoji.Text), out glyph)) return glyph;
        return "◇";
    }

    sealed class NativeServerUpdatePicker(Rectangle anchor, int dpi)
    {
        readonly TaskCompletionSource<EmojiPickerForm?> formReady = new(TaskCreationOptions.RunContinuationsAsynchronously);
        int stopped;
        IntPtr windowHandle;

        internal bool HasForeground(IntPtr hwnd) => hwnd != IntPtr.Zero && hwnd == Volatile.Read(ref windowHandle);

        internal void Start(Action<string, string?, string?> action, Action<Exception> reportError)
        {
            var thread = new Thread(() =>
            {
                try
                {
                    if (Volatile.Read(ref stopped) != 0) return;
                    using var form = new EmojiPickerForm(anchor, dpi, action);
                    form.Shown += (_, _) =>
                    {
                        Interlocked.Exchange(ref windowHandle, form.Handle);
                        formReady.TrySetResult(form);
                        if (Volatile.Read(ref stopped) != 0) form.Close();
                        else form.LoadChoices();
                    };
                    Application.Run(form);
                }
                catch (Exception ex) { reportError(ex); }
                finally
                {
                    Interlocked.Exchange(ref windowHandle, IntPtr.Zero);
                    formReady.TrySetResult(null);
                    action("picker-close", null, null);
                }
            }) { IsBackground = true, Name = "TES3NP emoji picker" };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
        }

        internal void Reply(string kind, PickerReply reply) => _ = PostToWindow(form => form.ApplyReply(kind, reply));
        internal void Activate() => _ = PostToWindow(form => form.Activate());
        internal void Close()
        {
            Interlocked.Exchange(ref stopped, 1);
            _ = PostToWindow(form => form.Close());
        }

        async Task PostToWindow(Action<EmojiPickerForm> action)
        {
            var form = await formReady.Task.ConfigureAwait(false);
            if (form == null) return;
            try { form.BeginInvoke(action, form); }
            catch (InvalidOperationException) { }
        }
    }

    sealed class EmojiPickerForm : Form
    {
        static readonly Color Ink = Color.FromArgb(18, 14, 10);
        static readonly Color Gold = Color.FromArgb(226, 197, 144);
        static readonly SemaphoreSlim IconDownloads = new(4);
        readonly Action<string, string?, string?> dispatch;
        readonly TextBox search = new() { Dock = DockStyle.Fill, PlaceholderText = "Search emoji", MaxLength = 64,
            AccessibleName = "Search emoji", BackColor = Ink, ForeColor = Gold };
        readonly FlowLayoutPanel grid = new() { Dock = DockStyle.Fill, AutoScroll = true, BackColor = Ink };
        readonly Label detail = new() { Dock = DockStyle.Fill, AutoEllipsis = true, TextAlign = ContentAlignment.MiddleLeft,
            Text = "Loading emoji…", ForeColor = Gold };
        readonly Button more = new() { Dock = DockStyle.Fill, Text = "More emoji", Visible = false };
        readonly Button catalogButton = new() { Dock = DockStyle.Fill, Text = "Discord emoji" };
        readonly System.Windows.Forms.Timer debounce = new() { Interval = 220 };
        readonly Font glyphFont = new("Segoe UI Emoji", 20, FontStyle.Regular);
        readonly CancellationTokenSource icons = new();
        readonly int cellSize, iconSize;
        string currentQuery = "";
        BundledEmoji[] localChoices = [];
        int localOffset;
        bool pending, resourcesDisposed, discordCatalog;

        internal EmojiPickerForm(Rectangle anchor, int dpi, Action<string, string?, string?> dispatch)
        {
            this.dispatch = dispatch;
            int Scale(int value) => value * dpi / 96;
            cellSize = Scale(39);
            iconSize = Scale(27);
            Text = "Add a reaction";
            StartPosition = FormStartPosition.Manual;
            FormBorderStyle = FormBorderStyle.SizableToolWindow;
            AutoScaleMode = AutoScaleMode.None;
            ShowInTaskbar = false;
            KeyPreview = true;
            BackColor = Color.FromArgb(33, 26, 17);
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4,
                Padding = new Padding(Scale(8)) };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, Scale(34)));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, Scale(27)));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, Scale(31)));
            var filters = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Margin = Padding.Empty };
            filters.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            filters.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, Scale(115)));
            filters.Controls.Add(search, 0, 0);
            filters.Controls.Add(catalogButton, 1, 0);
            layout.Controls.Add(filters, 0, 0);
            layout.Controls.Add(grid, 0, 1);
            layout.Controls.Add(detail, 0, 2);
            layout.Controls.Add(more, 0, 3);
            Controls.Add(layout);
            StyleButton(more);
            StyleButton(catalogButton);

            var screen = Screen.FromRectangle(anchor).WorkingArea;
            int width = Math.Min(430 * dpi / 96, screen.Width);
            int height = Math.Min(420 * dpi / 96, screen.Height);
            int x = anchor.Right + width <= screen.Right ? anchor.Right + Scale(4) : anchor.Left - width - Scale(4);
            Bounds = new Rectangle(Math.Clamp(x, screen.Left, screen.Right - width),
                Math.Clamp(anchor.Top, screen.Top, screen.Bottom - height), width, height);

            search.TextChanged += (_, _) => { debounce.Stop(); debounce.Start(); };
            debounce.Tick += (_, _) => { debounce.Stop(); SearchIfChanged(); };
            more.Click += (_, _) => LoadMore();
            catalogButton.Click += (_, _) => ToggleCatalog();
            grid.Scroll += (_, _) =>
            {
                var vertical = grid.VerticalScroll;
                if (more.Visible && vertical.Visible && vertical.Value + vertical.LargeChange >= vertical.Maximum - cellSize)
                    if (discordCatalog) Request("picker-more");
            };
            KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; Close(); } };
        }

        internal void LoadChoices()
        {
            search.Select();
            LoadBundledChoices();
        }

        void ToggleCatalog()
        {
            if (pending) return;
            discordCatalog = !discordCatalog;
            catalogButton.Text = discordCatalog ? "Standard emoji" : "Discord emoji";
            currentQuery = "";
            ClearChoices();
            more.Visible = false;
            if (discordCatalog) Request("picker");
            else Request("picker-leave");
        }

        void LoadBundledChoices()
        {
            currentQuery = search.Text.Trim();
            string alias = currentQuery.Trim(':').Replace(' ', '_').Replace('-', '_');
            localChoices = BundledEmojiCatalog.Value.Where(item => alias.Length == 0 ||
                item.Glyph.Contains(alias, StringComparison.Ordinal) ||
                item.Aliases.Any(name => name.Contains(alias, StringComparison.OrdinalIgnoreCase))).ToArray();
            ClearChoices();
            localOffset = 0;
            LoadMore();
            detail.Text = localChoices.Length == 0 ? "No emoji found." : "";
        }

        void LoadMore()
        {
            if (discordCatalog) { Request("picker-more"); return; }
            const int pageSize = 72;
            grid.SuspendLayout();
            try
            {
                foreach (var item in localChoices.Skip(localOffset).Take(pageSize))
                    AddChoice(new(item.Glyph, item.Aliases[0], item.Glyph, null, item.Glyph, 0));
                localOffset += pageSize;
            }
            finally { grid.ResumeLayout(true); }
            more.Visible = localOffset < localChoices.Length;
        }

        void Request(string kind, string? key = null, string? query = null)
        {
            if (pending) return;
            pending = true;
            detail.Text = kind == "picker-select" ? "Adding reaction…" : "Loading emoji…";
            dispatch(kind, key, query);
        }

        void SearchIfChanged()
        {
            string query = search.Text.Trim();
            if (pending || query == currentQuery) return;
            if (!discordCatalog) { LoadBundledChoices(); return; }
            currentQuery = query;
            Request("picker-search", query: query);
        }

        internal void ApplyReply(string kind, PickerReply reply)
        {
            pending = false;
            if (kind == "picker-leave") { LoadBundledChoices(); return; }
            if (reply.Items is { } items)
            {
                grid.SuspendLayout();
                try
                {
                    if (kind == "picker-search") ClearChoices();
                    foreach (var emoji in items) AddChoice(emoji);
                }
                finally { grid.ResumeLayout(true); }
                more.Visible = reply.More;
            }
            detail.Text = reply.Error ?? (grid.Controls.Count == 0 ? "No emoji found." : "");
            SearchIfChanged();
        }

        static void StyleButton(Button button)
        {
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderColor = Color.FromArgb(98, 76, 46);
            button.FlatAppearance.MouseOverBackColor = Color.FromArgb(69, 54, 34);
            button.BackColor = Color.FromArgb(40, 31, 20);
            button.ForeColor = Gold;
        }

        void AddChoice(PickerEmoji emoji)
        {
            var button = new Button { Font = glyphFont, Size = new Size(cellSize, cellSize), Margin = new Padding(2),
                AccessibleName = emoji.Name, Text = DisplayPickerGlyph(emoji), UseCompatibleTextRendering = true };
            StyleButton(button);
            button.MouseEnter += (_, _) => { if (!pending) detail.Text = emoji.Name; };
            button.Enter += (_, _) => { if (!pending) detail.Text = emoji.Name; };
            button.Click += (_, _) => Request(discordCatalog ? "picker-select" : "picker-local", emoji.Key);
            grid.Controls.Add(button);
            if (emoji.Image != null && ulong.TryParse(emoji.Key, out ulong id))
                _ = LoadCustomIcon(button, id, icons.Token);
        }

        async Task LoadCustomIcon(Button button, ulong id, CancellationToken cancel)
        {
            try
            {
                await IconDownloads.WaitAsync(cancel).ConfigureAwait(false);
                try
                {
                    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancel);
                    timeout.CancelAfter(TimeSpan.FromSeconds(8));
                    using var response = await imageHttp.GetAsync($"https://cdn.discordapp.com/emojis/{id}.png?size=64",
                        System.Net.Http.HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
                    if (!response.IsSuccessStatusCode || response.Content.Headers.ContentLength > 262144) return;
                    using var body = await response.Content.ReadAsStreamAsync(timeout.Token).ConfigureAwait(false);
                    using var bytes = new MemoryStream();
                    byte[] buffer = new byte[8192];
                    int read;
                    while ((read = await body.ReadAsync(buffer.AsMemory(), timeout.Token).ConfigureAwait(false)) > 0)
                    {
                        if (bytes.Length + read > 262144) return;
                        bytes.Write(buffer, 0, read);
                    }
                    if (cancel.IsCancellationRequested) return;
                    byte[] imageData = bytes.ToArray();
                    BeginInvoke((Action)(() => ApplyCustomIcon(button, imageData)));
                }
                finally { IconDownloads.Release(); }
            }
            catch (Exception) { }
        }

        void ApplyCustomIcon(Button button, byte[] imageData)
        {
            if (button.IsDisposed) return;
            try
            {
                using var bytes = new MemoryStream(imageData, false);
                using var original = Image.FromStream(bytes);
                if (original.Width > 256 || original.Height > 256) return;
                button.Image = new Bitmap(original, iconSize, iconSize);
                button.Text = "";
            }
            catch (ArgumentException) { }
        }

        void ClearChoices()
        {
            foreach (var button in grid.Controls.OfType<Button>().ToArray())
            {
                button.Image?.Dispose();
                button.Dispose();
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && !resourcesDisposed)
            {
                resourcesDisposed = true;
                icons.Cancel();
                icons.Dispose();
                debounce.Dispose();
                ClearChoices();
                glyphFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
