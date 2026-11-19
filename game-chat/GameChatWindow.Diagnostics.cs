internal sealed partial class GameChatWindow
{
    const string ChatBuild = "chat-responsive-layout-20261117";

    readonly string logPath = Path.Combine(ChatDataRoot, "chat-host.log");

    readonly object diagnosticLogLock = new();

    void TrimChatDiagnosticLog()
    {
        const int retainedBytes = 1024 * 1024;
        if (new FileInfo(logPath).Length <= 2 * retainedBytes) return;
        string temporary = logPath + ".trim.tmp";
        try
        {
            using (var input = File.OpenRead(logPath))
            {
                input.Seek(-retainedBytes, SeekOrigin.End);
                int value;
                do { value = input.ReadByte(); } while (value >= 0 && value != '\n');
                using var output = File.Create(temporary);
                input.CopyTo(output);
            }
            File.Move(temporary, logPath, true);
        }
        finally
        {
            try { File.Delete(temporary); } catch { }
        }
    }

    void Log(string message)
    {
        try
        {
            // Keep useful event details without leaving privacy placeholder fields.
            // The private Discord chat archive has a separate writer and is unchanged.
            string safe = System.Text.RegularExpressions.Regex.Replace(message,
                @"(?i)\[(?:credential|user|identity|secret|url|path|network path|email|IP|identifier|Discord ID) omitted\]", "");
            safe = System.Text.RegularExpressions.Regex.Replace(safe,
                @"(?i)\b(?:Account|User|Windows\s+User(?:name)?|Password|Token|Secret|Authorization|Cookie|Api[-_]?Key)\s*[:=][^|\r\n]*", "");
            safe = System.Text.RegularExpressions.Regex.Replace(safe,
                @"(?i)%(?:LOCALAPPDATA|APPDATA|USERPROFILE)%(?:[/\\][^\r\n|]*)?", "");
            safe = System.Text.RegularExpressions.Regex.Replace(safe,
                @"(?i)\b(?:https?|wss?)://[^\s|]+", "");
            safe = System.Text.RegularExpressions.Regex.Replace(safe,
                @"(?i)\b[A-Z]:[/\\][^\r\n|]*", "");
            safe = System.Text.RegularExpressions.Regex.Replace(safe,
                @"\\\\[^\r\n|]*", "");
            safe = System.Text.RegularExpressions.Regex.Replace(safe,
                @"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", "");
            safe = System.Text.RegularExpressions.Regex.Replace(safe,
                @"\b(?:\d{1,3}\.){3}\d{1,3}\b", "");
            safe = System.Text.RegularExpressions.Regex.Replace(safe,
                @"\b\d{16,21}\b", "");
            string windowsUser = Environment.UserName;
            if (windowsUser.Length >= 3)
                safe = System.Text.RegularExpressions.Regex.Replace(safe,
                    @"(?i)(?<![\p{L}\p{N}_])" + System.Text.RegularExpressions.Regex.Escape(windowsUser) + @"(?![\p{L}\p{N}_])", "");
            var parts = new System.Collections.Generic.List<string>();
            foreach (string piece in safe.Replace('\r', ' ').Replace('\n', ' ').Split('|'))
            {
                string item = System.Text.RegularExpressions.Regex.Replace(piece,
                    @"(?i)\b(?:Executable(?:\s+path)?|Source\s+path|Destination|Install|Stage|Path|Folder|File|URL|Mail|Email)\s*[:=]\s*$", "");
                item = item.Trim(' ', '\t', ':', '=');
                if (item.Length > 0) parts.Add(item);
            }
            safe = string.Join(" | ", parts);
            if (safe.Length == 0) return;
            Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
            lock (diagnosticLogLock)
            {
                File.AppendAllText(logPath, DateTime.Now.ToString("s") + " | " +
                    ChatBuild + " | " + safe + Environment.NewLine);
                TrimChatDiagnosticLog();
            }
        }
        catch { }
    }
}
