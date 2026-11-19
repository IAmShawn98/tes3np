using System.Drawing;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    ServerUpdatePickerWindow? serverUpdatePicker;

    sealed class ServerUpdatePickerWindow : Form
    {
        readonly Label status = new()
        {
            Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter,
            Text = "Opening Discord…", BackColor = Color.FromArgb(27, 25, 23), ForeColor = Color.Gainsboro
        };

        internal WebView2 Browser { get; } = new() { Dock = DockStyle.Fill };
        internal string MessageId { get; }

        internal ServerUpdatePickerWindow(string messageId, Rectangle anchor, int dpi)
        {
            MessageId = messageId;
            Text = "Add a reaction";
            FormBorderStyle = FormBorderStyle.SizableToolWindow;
            StartPosition = FormStartPosition.Manual;
            ShowInTaskbar = false;
            Controls.Add(Browser);
            Controls.Add(status);
            status.BringToFront();

            var screen = Screen.FromRectangle(anchor).WorkingArea;
            int width = Math.Min(960 * dpi / 96, screen.Width);
            int height = Math.Min(720 * dpi / 96, screen.Height);
            int x = anchor.Right + width <= screen.Right ? anchor.Right : anchor.Left - width;
            Bounds = new Rectangle(Math.Clamp(x, screen.Left, screen.Right - width),
                Math.Clamp(anchor.Top, screen.Top, screen.Bottom - height), width, height);
        }

        internal void RevealBrowser()
        {
            status.Hide();
            if (ActiveForm == this || ContainsFocus) Browser.Focus();
        }

        internal void ShowFailure(string text)
        {
            status.Text = text;
            status.Show();
            status.BringToFront();
        }
    }

    bool IsCurrentServerUpdatePicker(ServerUpdatePickerWindow picker) =>
        CanShowServerUpdates && picker == serverUpdatePicker && !picker.IsDisposed;

    async Task<string?> OpenServerUpdatePicker(LatestUpdatesPanel panel, ServerUpdateAction request)
    {
        // Leave the embedded renderer's WebView2 event before activating a different window.
        await Task.Yield();
        if (panel != serverUpdatesPanel || !CanShowServerUpdates || discordEnvironment is not { } environment)
            return "Discord is still loading.";

        if (serverUpdatePicker is { IsDisposed: false } existing && existing.MessageId == request.Id)
        {
            existing.Activate();
            return null;
        }

        CloseServerUpdatePicker();
        var anchor = panel.RectangleToScreen(panel.ClientRectangle);
        var picker = new ServerUpdatePickerWindow(request.Id, anchor, Math.Max(96, (int)GetDpiForWindow(owner)));
        serverUpdatePicker = picker;
        picker.FormClosed += (_, _) =>
        {
            if (serverUpdatePicker == picker) serverUpdatePicker = null;
            if (ServerUpdatesAuthenticated) nextServerUpdatesCheck = DateTime.MinValue;
        };

        try
        {
            // Keep the picker modeless, with its own top-level window and input focus.
            picker.Show();
            picker.Activate();
            await picker.Browser.EnsureCoreWebView2Async(environment).WaitAsync(TimeSpan.FromSeconds(8));
            if (!IsCurrentServerUpdatePicker(picker)) return null;
            var core = picker.Browser.CoreWebView2;
            ConfigureServerUpdatesBrowser(core);
            core.Navigate(ServerUpdatesChannel + "/" + request.Id);

            var locate = request with { Kind = "picker-target" };
            var deadline = DateTime.UtcNow.AddSeconds(10);
            while (DateTime.UtcNow < deadline)
            {
                await Task.Delay(250);
                if (!IsCurrentServerUpdatePicker(picker)) return null;
                if (!IsServerUpdatesRoute(core.Source) && !IsServerUpdatesMessageRoute(core.Source)) continue;
                string located = await RunServerUpdateAction(core, locate);
                if (!IsCurrentServerUpdatePicker(picker)) return null;
                if (located != "\"ready\"") continue;

                picker.RevealBrowser();
                // Discord positions its popover against the real, visible viewport.
                for (int attempt = 0; attempt < 3; attempt++)
                {
                    await Task.Delay(150);
                    if (!IsCurrentServerUpdatePicker(picker) ||
                        (!IsServerUpdatesRoute(core.Source) && !IsServerUpdatesMessageRoute(core.Source))) return null;
                    if (await RunServerUpdateAction(core, request) == "\"clicked\"") return null;
                }
                return IsCurrentServerUpdatePicker(picker) ? "Use Add Reaction on the opened Discord post." : null;
            }

            picker.ShowFailure("Discord could not find the post. Close this window and try again.");
        }
        catch (Exception ex)
        {
            if (!IsCurrentServerUpdatePicker(picker)) return null;
            picker.ShowFailure("Discord could not open the reaction picker. Close this window and try again.");
            Log("SERVER UPDATES | Emoji picker: " + ex.GetType().Name + " 0x" + ex.HResult.ToString("X8"));
        }
        return null;
    }

    void CloseServerUpdatePicker()
    {
        var picker = serverUpdatePicker;
        serverUpdatePicker = null;
        if (picker is { IsDisposed: false }) picker.Close();
    }
}
