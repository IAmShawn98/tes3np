internal static class GameChatWeb
{
    internal static Lazy<string> Page(string fileName) => new(() =>
    {
        string resourceName = "tes3np.GameChat.Web." + fileName;
        using var stream = typeof(GameChatWeb).Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException("Missing Game Chat browser resource: " + fileName);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    });
}
