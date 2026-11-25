internal static class GameChatWeb
{
    internal static Lazy<string> Page(string fileName) => new(() =>
    {
        string resourceName = "tes3np.GameChat.Web." + fileName;
        using var stream = typeof(GameChatWeb).Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException("Missing Game Chat browser resource: " + fileName);
        using var reader = new StreamReader(stream);
        string text = reader.ReadToEnd();
        // Embed the font only in our own local documents, never Discord's origin.
        return fileName is "message-feed.html" or "server-updates.html"
            ? text.Replace("/* TES3NP_THEME_FONT */", GameChatTypography.WebFontCss, StringComparison.Ordinal)
            : text;
    });
}
