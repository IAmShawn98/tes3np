internal static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--server-map")
        {
            Environment.ExitCode = ServerMapHost.Run(args);
            return;
        }
        if (args.Length == 1 && args[0] == "--check-map-policy")
        {
            Environment.ExitCode = ServerMapHost.CheckPolicy();
            return;
        }
        if (GameChatWindow.TryRunDiscordReactionPicker(args)) return;
        if (args.Length == 1 && args[0] == "--check-chat-archive")
        {
            Environment.ExitCode = GameChatWindow.CheckChatArchivePersistence();
            return;
        }
        if (args.Length == 1 && args[0] == "--check-happy-hour-history")
        {
            Environment.ExitCode = GameChatWindow.CheckHappyHourHistoryCoverage();
            return;
        }
        if (args.Length == 1 && args[0] == "--check-chat-owner-visibility")
        {
            ApplicationConfiguration.Initialize();
            Environment.ExitCode = GameChatNative.CheckChatOwnerVisibility();
            return;
        }
        if (args.Length == 1 && args[0] == "--check-server-status")
        {
            Environment.ExitCode = GameChatWindow.CheckServerStatusCoverage();
            return;
        }
        if (args.Length < 1 || !long.TryParse(args[0], out long owner)) return;
        int baseWidth = args.Length > 1 && int.TryParse(args[1], out int width) && width > 0
            ? width : 960;
        ApplicationConfiguration.Initialize();
        Application.SetDefaultFont(GameChatTypography.ThemeFont(9, System.Drawing.FontStyle.Regular));
        var chat = new GameChatWindow(new IntPtr(owner), baseWidth);
        Application.Run(chat);
        chat.WaitForChatArchiveOnExit();
    }
}
