using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    const int ServerUpdateBodyLimit = 3800;
    const string ServerUpdatesRtfHeader = @"{\rtf1\ansi\ansicpg1252\uc1{\fonttbl{\f0 Georgia;}}" +
        @"{\colortbl;\red241\green238\blue232;\red217\green196\blue156;\red101\green82\blue55;" +
        @"\red184\green169\blue142;}\f0\fs21";

    static string FormatUpdatesFallback(ServerUpdate[] posts, string? status)
    {
        if (status != null || posts.Length == 0)
            return FormatFallbackStatus(status ?? "Loading server updates…");

        var rtf = new StringBuilder(ServerUpdatesRtfHeader);
        bool firstEntry = true;
        foreach (var post in posts)
        {
            var when = DiscordTimestamp(ulong.Parse(post.Id, CultureInfo.InvariantCulture)).ToLocalTime();
            rtf.Append(firstEntry ? @"\pard\qc" : @"\pard\qc\sb85");
            rtf.Append(@"\sa0\fs18\cf3 \u9472?\u9472?\u9472?  \cf2 ");
            AppendServerUpdatesRtfText(rtf, when.ToString(ServerUpdatesDateFormat).AsSpan());
            rtf.Append(@"  \cf3\u9472?\u9472?\u9472?\par ");
            firstEntry = false;
            bool firstBlock = true;
            int remaining = ServerUpdateBodyLimit;
            foreach (var block in post.Blocks!.Take(120))
            {
                if (remaining == 0) break;
                if (block?.Runs is not { Length: > 0 }) continue;
                bool heading = block.Style == "heading" ||
                    (string.IsNullOrEmpty(block.Style) &&
                     block.Runs.All(run => string.IsNullOrWhiteSpace(run?.Text) || run.Bold));
                rtf.Append(@"\pard\cf1\fs21\sa70 ");
                if (block.Style == "bullet" || block.Style == "number")
                {
                    rtf.Append(@"\li230\fi-225\tx230 ");
                    if (block.Style == "bullet") rtf.Append(@"\u8226?");
                    else rtf.Append(Math.Clamp(block.Number, 1, 999)).Append('.');
                    rtf.Append(@"\tab ");
                }
                if (heading) rtf.Append(firstBlock ? @"\fs23 " : @"\sb45\fs23 ");
                foreach (var run in block.Runs.Take(240))
                {
                    if (remaining == 0) break;
                    if (string.IsNullOrEmpty(run?.Text)) continue;
                    bool bold = run.Bold || heading;
                    if (bold) rtf.Append(@"{\b ");
                    int length = Math.Min(run.Text.Length, remaining);
                    AppendServerUpdatesRtfText(rtf, run.Text.AsSpan(0, length));
                    if (bold) rtf.Append('}');
                    remaining -= length;
                }
                rtf.Append(@"\par ");
                firstBlock = false;
            }
            if (post.Reactions is { Length: > 0 } reactions)
            {
                rtf.Append(@"\pard\cf2\fs18\sa40 ");
                foreach (var reaction in reactions.Take(25))
                {
                    AppendServerUpdatesRtfText(rtf, reaction.Name.AsSpan());
                    rtf.Append(' ').Append(reaction.Count).Append("  ");
                }
                rtf.Append(@"\par ");
            }
        }
        return rtf.Append('}').ToString();
    }

    static int? FindNewestServerUpdatesDateDivider(string text)
    {
        const string strokes = "───";
        int? newest = null;
        using var lines = new StringReader(text);
        int offset = 0;
        while (lines.ReadLine() is { } line)
        {
            var content = line.AsSpan().Trim();
            if (content.Length > 6 && content.StartsWith(strokes) && content.EndsWith(strokes))
            {
                var label = content[3..^3].Trim();
                if (DateTime.TryParseExact(label, ServerUpdatesDateFormat, null,
                        System.Globalization.DateTimeStyles.None, out _))
                    newest = offset;
            }
            // RichEdit character positions count each paragraph break once.
            offset += line.Length + 1;
        }
        return newest;
    }

    static string FormatFallbackStatus(string text)
    {
        var rtf = new StringBuilder(ServerUpdatesRtfHeader).Append(@"\pard\cf4 ");
        AppendServerUpdatesRtfText(rtf, text.AsSpan());
        return rtf.Append('}').ToString();
    }

    static void AppendServerUpdatesRtfText(StringBuilder rtf, ReadOnlySpan<char> text)
    {
        foreach (char ch in text)
        {
            switch (ch)
            {
                case '\\':
                case '{':
                case '}': rtf.Append('\\').Append(ch); break;
                case '\n': rtf.Append(@"\line "); break;
                case '\t': rtf.Append(@"\tab "); break;
                default:
                    if (char.IsControl(ch)) break;
                    if (ch <= '\x7e') rtf.Append(ch);
                    else rtf.Append(@"\u").Append(((short)ch).ToString(System.Globalization.CultureInfo.InvariantCulture)).Append('?');
                    break;
            }
        }
    }


    sealed partial class LatestUpdatesPanel
    {
        readonly Panel fallbackClip = new() { Dock = DockStyle.Fill, BackColor = FeedBackground };
        readonly RichTextBox fallbackFeed = new()
        {
            BackColor = FeedBackground, ReadOnly = true, BorderStyle = BorderStyle.None,
            DetectUrls = false, ScrollBars = RichTextBoxScrollBars.ForcedVertical
        };
        int? fallbackLanding;

        void LayoutFallback(int width, int height)
        {
            if (feedVisible) return;
            var before = ReadFallbackScroll();
            uint dpi = GetDpiForWindow(fallbackFeed.Handle);
            int nativeBar = GetSystemMetricsForDpi(2, dpi == 0 ? 96 : dpi);
            fallbackFeed.SetBounds(0, 0, width + nativeBar, height);
            fallbackFeed.ZoomFactor = (float)Math.Clamp(PanelScale * 96 / (dpi == 0 ? 96 : dpi), 0.25, 3);
            if (FallbackFollowsNewest(before.Position, before.Maximum)) LandOnFallbackNewest();
        }

        void UpdateFallback(string value)
        {
            using var payload = JsonDocument.Parse(value);
            string? status = payload.RootElement.TryGetProperty("status", out var text) ? text.GetString() : null;
            var before = ReadFallbackScroll();
            bool follow = FallbackFollowsNewest(before.Position, before.Maximum);
            fallbackFeed.Rtf = FormatUpdatesFallback(host.displayedServerUpdates, status);
            if (follow) LandOnFallbackNewest();
            else ScrollFallback("to", before.Position);
        }

        bool FallbackFollowsNewest(int position, int maximum) =>
            position == fallbackLanding || position >= maximum - Px(12);

        void LandOnFallbackNewest()
        {
            if (FindNewestServerUpdatesDateDivider(fallbackFeed.Text) is not int start) return;
            fallbackFeed.Select(start, 0);
            fallbackFeed.ScrollToCaret();
            var scroll = new FallbackPoint();
            SendMessageW(fallbackFeed.Handle, 0x04DD, IntPtr.Zero, ref scroll); // EM_GETSCROLLPOS
            int dateTop = fallbackFeed.GetPositionFromCharIndex(start).Y;
            ScrollFallback("to", Math.Max(0, scroll.Y + dateTop - Px(2)));
            fallbackLanding = ReadFallbackScroll().Position;
        }

        (int Total, int Page, int Position, int Maximum) ReadFallbackScroll()
        {
            if (!fallbackFeed.IsHandleCreated) return (1, 1, 0, 0);
            var info = new FallbackScrollInfo { Size = 28, Mask = 7 };
            if (!GetScrollInfo(fallbackFeed.Handle, 1, ref info)) return (1, 1, 0, 0);
            int total = Math.Max(1, info.Max - info.Min + 1);
            int page = Math.Clamp((int)info.Page, 1, total);
            return (total, page, Math.Max(0, info.Pos - info.Min), total - page);
        }

        void ScrollFallback(string mode, int pixels)
        {
            var scroll = new FallbackPoint();
            if (mode == "by") SendMessageW(fallbackFeed.Handle, 0x04DD, IntPtr.Zero, ref scroll);
            scroll.Y = Math.Max(0, scroll.Y + pixels);
            SendMessageW(fallbackFeed.Handle, 0x04DE, IntPtr.Zero, ref scroll); // EM_SETSCROLLPOS
            scrollbar.Invalidate();
        }

        [StructLayout(LayoutKind.Sequential)]
        struct FallbackScrollInfo { internal uint Size, Mask; internal int Min, Max; internal uint Page; internal int Pos, TrackPos; }

        [StructLayout(LayoutKind.Sequential)]
        struct FallbackPoint { internal int X, Y; }

        [DllImport("user32.dll")] static extern bool GetScrollInfo(IntPtr hwnd, int bar, ref FallbackScrollInfo info);
        [DllImport("user32.dll")] static extern int GetSystemMetricsForDpi(int index, uint dpi);
        [DllImport("user32.dll")] static extern IntPtr SendMessageW(IntPtr hwnd, uint message, IntPtr wParam, ref FallbackPoint lParam);
    }
}
