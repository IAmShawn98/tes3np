internal static class GameChatWeb
{
    internal static Lazy<string> Page(string fileName) => new(() =>
    {
        string resourceName = "tes3np.GameChat.Web." + fileName;
        using var stream = typeof(GameChatWeb).Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException("Missing Game Chat browser resource: " + fileName);
        using var reader = new StreamReader(stream);
        string text = reader.ReadToEnd();
        // Local pages use CSS; our scoped Discord presentation scripts use
        // a binary FontFace, without changing the site's security settings.
        if (fileName is "message-feed.html" or "server-updates.html")
            return text.Replace("/* TES3NP_THEME_FONT */", GameChatTypography.WebFontCss, StringComparison.Ordinal);
        return text.Contains("/* TES3NP_THEME_FONT_LOAD */", StringComparison.Ordinal)
            ? text.Replace("/* TES3NP_THEME_FONT_LOAD */", GameChatTypography.BrowserFontInstall, StringComparison.Ordinal)
            : text;
    });
}
