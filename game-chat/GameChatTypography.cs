using System.Drawing;
using System.Drawing.Text;
using System.Runtime.InteropServices;

// Use the exact launcher font asset. GDI and GDI+ are process-private;
// WebView2 gets the same embedded bytes in TES3NP-owned or scoped themed presentations.
internal static class GameChatTypography
{
    const string ResourceName = "tes3np.GameChat.MysticCards.ttf";
    const string FallbackFace = "Georgia";
    // All launcher-owned text shares one theme face.
    static readonly Lazy<byte[]> FontBytes = new(() =>
    {
        using var stream = typeof(GameChatTypography).Assembly.GetManifestResourceStream(ResourceName);
        if (stream == null) return Array.Empty<byte>();
        using var bytes = new MemoryStream();
        stream.CopyTo(bytes);
        return bytes.ToArray();
    });

    [DllImport("gdi32.dll")]
    static extern IntPtr AddFontMemResourceEx(IntPtr font, uint size, IntPtr reserved, out uint count);
    [DllImport("gdi32.dll")]
    static extern bool RemoveFontMemResourceEx(IntPtr handle);

    // GDI+ requires this memory and collection to outlive all generated fonts.
    // One immutable registration per process; the OS reclaims it at process exit.
    sealed class ThemeRegistration
    {
        internal readonly PrivateFontCollection Collection;
        internal readonly IntPtr Memory, Handle;
        internal readonly FontFamily Family;
        internal ThemeRegistration(PrivateFontCollection collection, IntPtr memory, IntPtr handle, FontFamily family)
        {
            Collection = collection; Memory = memory; Handle = handle; Family = family;
        }
    }

    static readonly Lazy<ThemeRegistration?> NativeTheme = new(() =>
    {
        IntPtr memory = IntPtr.Zero, handle = IntPtr.Zero;
        PrivateFontCollection? collection = null;
        try
        {
            byte[] data = FontBytes.Value;
            if (data.Length == 0) return null;
            memory = Marshal.AllocHGlobal(data.Length);
            Marshal.Copy(data, 0, memory, data.Length);
            handle = AddFontMemResourceEx(memory, (uint)data.Length, IntPtr.Zero, out uint count);
            if (handle == IntPtr.Zero || count == 0) throw new InvalidOperationException("Theme font unavailable.");
            collection = new PrivateFontCollection();
            collection.AddMemoryFont(memory, data.Length);
            FontFamily family = collection.Families.First(f => f.Name == "Mystic Cards");
            return new ThemeRegistration(collection, memory, handle, family);
        }
        catch
        {
            collection?.Dispose();
            if (handle != IntPtr.Zero) RemoveFontMemResourceEx(handle);
            if (memory != IntPtr.Zero) Marshal.FreeHGlobal(memory);
            return null;
        }
    });

    internal static string ThemeFace => NativeTheme.Value?.Family.Name ?? FallbackFace;

    internal static Font ThemeFont(float size, FontStyle style)
    {
        if (NativeTheme.Value is { } theme)
        {
            try { return new Font(theme.Family, size, style); }
            catch (ArgumentException) { return new Font(theme.Family, size, FontStyle.Regular); }
        }
        return new Font(FallbackFace, size, style);
    }

    // Load the public bundled font directly from bytes in the browser. No
    // remote font URL, network request or CSP changes on Discord's origin.
    static readonly Lazy<string> BrowserFontScript = new(() => FontBytes.Value.Length == 0 ? "" :
        "try { if (!Array.from(document.fonts).some(f => f.family === 'TES3NP Theme')) {" +
        "const face = new FontFace('TES3NP Theme', Uint8Array.from(atob('" +
        Convert.ToBase64String(FontBytes.Value) +
        "'), c => c.charCodeAt(0))); document.fonts.add(face); face.load().catch(() => document.fonts.delete(face)); } } catch {}");
    internal static string BrowserFontInstall => BrowserFontScript.Value;

    internal static string WebFontCss => FontBytes.Value.Length == 0 ? "" :
        "@font-face{font-family:'TES3NP Theme';src:url(data:font/ttf;base64," +
        Convert.ToBase64String(FontBytes.Value) + ") format('truetype');font-display:swap;}";
}
