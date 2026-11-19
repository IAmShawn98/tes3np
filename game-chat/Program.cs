internal static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        if (GameChatWindow.TryRunDiscordReactionPicker(args)) return;
        if (args.Length == 1 && args[0] == "--check-chat-archive")
        {
            Environment.ExitCode = GameChatWindow.CheckChatArchivePersistence();
            return;
        }
        if (args.Length < 1 || !long.TryParse(args[0], out long owner)) return;
        int baseWidth = args.Length > 1 && int.TryParse(args[1], out int width) && width > 0
            ? width : 960;
        ApplicationConfiguration.Initialize();
        var chat = new GameChatWindow(new IntPtr(owner), baseWidth);
        Application.Run(chat);
        chat.WaitForChatArchiveOnExit();
    }
}
