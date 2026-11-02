"""Guard TES3NP's Chat Host against recurring persistence/auth regressions.

These checks enforce cross-process architectural contracts, not C# syntax.
The Windows CI job also builds the Chat Host to catch compiler errors.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "chat-host" / "Program.cs").read_text(encoding="utf-8-sig")
app_state = (ROOT / "src" / "state.ahk").read_text(encoding="utf-8-sig")
reset_ui = (ROOT / "src" / "ui" / "v016-refinements.ahk").read_text(encoding="utf-8-sig")
bootstrap = (ROOT / "src" / "app" / "bootstrap.ahk").read_text(encoding="utf-8-sig")
jiub_ui = (ROOT / "src" / "ui" / "happy-hour.ahk").read_text(encoding="utf-8-sig")
errors = []


def expect(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


def section_between(text: str, start: str, end: str) -> str:
    """Return the guarded function section, or empty text if it was removed.

    Missing/renamed source must cause an explicit contract failure rather
    than crashing the entire build preflight with IndexError.
    """
    start_at = text.find(start)
    if start_at == -1:
        return ""
    end_at = text.find(end, start_at + len(start))
    if end_at == -1:
        return ""
    return text[start_at:end_at]


expect(
    "AHK must establish the Roaming AppData root",
    'AppDataDirectory := A_AppData "\\tes3np"' in app_state,
)
expect(
    "Chat Host must establish exactly one Roaming AppData root",
    source.count("SpecialFolder.ApplicationData") == 1
    and 'SpecialFolder.ApplicationData), "tes3np"' in source,
)
expect(
    "Chat Host must not read or write obsolete Local AppData Happy Hour markers",
    "SpecialFolder.LocalApplicationData" not in source
    and "LegacyHappyHourSeenFile" not in source
    and "happyHourSeenFile" not in source,
)
for name, expected in {
    "gameChatLogDirectory": 'Path.Combine(ChatDataRoot, "Logs")',
    "chatModeFile": 'Path.Combine(ChatDataRoot, "chat-display-mode.txt")',
    "logPath": 'Path.Combine(ChatDataRoot, "chat-host.log")',
}.items():
    expect(f"{name} must use canonical Roaming AppData", expected in source)
expect(
    "WebView2 profile must be under the canonical data root",
    'Path.Combine(ChatDataRoot, "chat-webview2")' in source,
)
expect(
    "No dead marker migration or popup-only state remains",
    "hadSavedChatArchiveAtStartup" not in source
    and "GetLastSeenHappyHour" not in source
    and "SaveLastSeenHappyHour" not in source,
)
expect(
    "Only indexed real Discord messages may create an event",
    "ulong candidate = LatestArchivedHappyHourId();" in source
    and "Math.Max(archivedId, previouslyVerifiedId)" not in source,
)
expect(
    "Activation text must belong to the Discord bot, not quoted player chat",
    'sourceAuthor.Contains("Yagrum", StringComparison.OrdinalIgnoreCase)' in source
    and 'entry.Value.User.Contains("Yagrum", StringComparison.OrdinalIgnoreCase)' in source,
)
expect(
    "A newer verified image must not be superseded by older text",
    "foreach (ulong imageId in verifiedHappyHourImageIds)" in source
    and "foreach (var entry in archivedChat.Reverse()) {\n                if (entry.Key <= latest) break;" in source,
)
expect(
    "Only the authentic Discord-backed Happy Hour banner remains",
    "ShowHappyHourBannerForMessage(ulong activationId)" in source
    and "ShowHappyHourBannerForMessage(latest);" in source
    and "ShowHappyHourAlert(" not in source
    and "happyHourAlert" not in source
    and "GoldText(" not in source
    and "CloseHappyHourPopup(" not in source
    and "happyHourDemoSeenFile" not in source
    and "GoldHappyHourWindow(480" not in source
    and "Form? happyHourAlert" not in source,
)
expect(
    "Banner presentation is independent of Discord authentication",
    "if (activationId == 0 || closingChat || IsDisposed) return;" in source
    and "void RefreshHappyHourBanner()\n        {\n            if ((!ShowExpiredHappyHourForAlphaTest &&" in source
    and "void DetectLatestHappyHour()\n        {\n            if (closingChat || IsDisposed) return;" in source,
)
expect(
    "Only authenticated Discord can fetch or page new messages",
    "if (!discordChannelReady || initialBackfillComplete" in source
    and "discordLoginVisible || !discordChannelReady) return;" in source
    and "void SuspendHappyHourUntilDiscordReturns(string reason)" in source,
)
expect(
    "Offline startup consults real archived messages, not login or marker state",
    "// Load it immediately, whether this browser is signed in or not.\n                DetectLatestHappyHour();" in source
    and "ulong latest = LatestArchivedHappyHourId();" in source
    and "LegacyHappyHourSeenFile" not in source,
)
expect(
    "Logging out must preserve a valid banner and its expiry timer",
    "Verified Happy Hour banner remains independent." in source
    and "Keep the existing genuine activation, its absolute expiry," in source
    and "ShowExpiredHappyHourForAlphaTest &&" in source,
)
expect(
    "Only real Discord snowflake IDs may determine expiry",
    "DiscordTimestamp(activationId).AddHours(1)" in source,
)
expect(
    "Legacy unguarded Happy Hour test mode must remain removed",
    "PreviewExpiredHappyHourForTesting" not in source
    and "activeHappyHourCutoff" not in source,
)
expect(
    "Expired Happy Hour alpha override stays disabled in production",
    "const bool ShowExpiredHappyHourForAlphaTest = false;" in source
    and "const bool ShowExpiredHappyHourForAlphaTest = true;" not in source
    and "if (latest > lastHappyHourMessageId &&" in source
    and "(ShowExpiredHappyHourForAlphaTest ||" in source
    and "(!ShowExpiredHappyHourForAlphaTest && ends <= DateTimeOffset.UtcNow)" in source
    and "HappyHourBannerTime(happyHourEndsAt)" in source
    and "Math.Max(0, Math.Ceiling((end - DateTimeOffset.UtcNow).TotalSeconds))" in source,
)
expect(
    "Historical Happy Hour search retains its bounded production one-hour window",
    "DateTimeOffset.UtcNow.AddDays(-7)" in source
    and "DateTimeOffset.UtcNow.AddHours(-1)" in source
    and "initialBackfillAttempts >= 500" in source
    and "TimeSpan.FromMinutes(6)" in source,
)

expect(
    "Archive must be written with replace-on-complete semantics",
    "WriteChatArchiveAtomically(GameChatIndexFile," in source
    and "WriteChatArchiveAtomically(GameChatLogFile," in source
    and "File.Move(temporary, path, true);" in source,
)
expect(
    "Fresh authentication initializes the native renderer before hiding it",
    "await InitMessageBrowser(env);" in source
    and "rendererNavigation.Task.WaitAsync(TimeSpan.FromSeconds(8))" in source
    and "messageBrowserReady = true;" in source,
)
expect(
    "First login reloads Discord channel once without launcher restart",
    "channelReloadAfterSignInPending = true;" in source
    and "channelReloadAfterSignInPending = false;" in source
    and "web.CoreWebView2.Reload();" in source
    and "bool keepChatVisible = chatOpen" in source,
)

expect(
    "Happy Hour banner must track launcher movement without a timer delay",
    "void PositionHappyHourBanner()" in source
    and "SetWindowPos(banner.Handle, IntPtr.Zero, x, y, width, height," in source
    and "PositionHappyHourBanner();\n                if (repositionQueued) return;" in source
    and "SetWinEventHook(0x800B, 0x800B" in source,
)
mismatch = (ROOT / "src" / "game" / "expansion-mismatch.ahk").read_text(encoding="utf-8-sig")
expect(
    "Original Expansion Pack enable/disable switch is restored",
    'LauncherExpansionToggle := AddStyledButton(LauncherGui, 0, 0, 190, 27, "Expansion Pack: Disabled", ToggleExpansionPack)' in bootstrap
    and 'RefreshExpansionPackToggle()' in bootstrap
    and '"Expansion Downloads", ToggleLauncherExpansionDownloads' not in bootstrap,
)
expect(
    "Mismatch dialog requests a child download view and disposes it on exit",
    'SendLauncherChatCommand(6, downloadSlot.Hwnd)' in mismatch
    and 'SendLauncherChatCommand(7, slotHwnd)' in mismatch
    and 'UploadExpansionFromFile()' in mismatch
    and 'Gui("+Owner" LauncherGui.Hwnd' in mismatch
    and 'SendLauncherChatCommand(command, targetHwnd := 0)' in bootstrap,
)
expect(
    "Same ChatHost process and existing Discord profile serve the popup",
    'const string ExpansionChannel = "https://discord.com/channels/509601787901116437/1555049936800718928";' in source
    and 'discordEnvironment = env;' in source
    and 'await browser.EnsureCoreWebView2Async(env);' in source
    and 'case 6: ShowEmbeddedExpansionDownloads(m.LParam); break;' in source
    and 'case 7: CloseEmbeddedExpansionDownloads(m.LParam); break;' in source
    and source.count("Application.Run(new ChatHost(") == 1
    and source.count('Path.Combine(ChatDataRoot, "chat-webview2")') == 1,
)
expect(
    "WebView is a native child of mismatch placeholder, not floating Discord window",
    "SetParent(handle,placeholder);" in source
    and "GetParent(handle)!=placeholder" in source
    and "PositionEmbeddedExpansionDownloads();" in source
    and "CloseEmbeddedExpansionDownloads();" in source
    and "ToggleExpansionDownloads()" not in source,
)
expect(
    "Only genuine ZIP attachment URL is presented without Discord grid changes",
    'const string ExpansionDownloadsFocusScript = """' in source
    and "document.querySelector('[data-list-id=\"chat-messages\"]')" in source
    and r"cdn\.discordapp\.com" in source
    and r"media\.discordapp\.net" in source
    and r"location.pathname.replace(/\/+$/,'')" in source
    and "link.href=file.url;" in source
    and "link.textContent=file.filename;" in source
    and "new MutationObserver(changes=>{" in source
    and "await browser.CoreWebView2.AddScriptToExecuteOnDocumentCreatedAsync(" in source
    and "grid-template-columns: minmax(0, 1fr) !important" not in source,
)

expect(
    "Future expansion ZIP selection is ordered by Discord message snowflakes",
    "const channel='/channels/509601787901116437/1555049936800718928';" in source
    and "function snowflake(message)" in source
    and r"chat-messages-\d+-(\d{15,22})" in source
    and "BigInt(row[1])" in source
    and "BigInt(single[1])" in source
    and "item.id>best.id" in source
    and "item.id===best.id && item.order>=best.order" in source
    and "const files=readCandidates(feed);" in source
    and "remember(files);" in source
    and "link.href=file.url;" in source
    and "phase='present'" in source
    and "goToPresent(scroller)" in source
    and "const maxBackfills=12, maxLoadingRetries=30, maxPresentRetries=18;" in source
    and "presentRetries<=maxPresentRetries" in source
    and "attributes:true,attributeFilter:['href']" in source
    and "new MutationObserver(changes=>{" in source
    and "lastFileKey===key" in source
    and "grid-template-columns:" not in source,
)

expect(
    "ZIP click is handed to default Windows browser without navigating embedded Discord",
    "link.addEventListener('click',event=>" in source
    and "event.preventDefault();" in source
    and "event.stopPropagation();" in source
    and "chrome.webview.postMessage({type:'expansion-download',url});" in source
    and "status.textContent='';" in source
    and "type==\"expansion-download\"" in source
    and "IsOfficialExpansionDownloadUrl(link)" in source
    and "Uri.TryCreate(value, UriKind.Absolute, out var uri)" in source
    and "Uri.UriSchemeHttps" in source
    and 'uri.Host != "cdn.discordapp.com"' in source
    and 'uri.Host != "media.discordapp.net"' in source
    and 'uri.AbsolutePath.StartsWith("/attachments/"' in source
    and 'filename.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)' in source
    and "UseShellExecute=true" in source
    and "Task.Run(()=>{" in source
    and "e.Cancel=true;" in source
    and "link.target='_self'" not in source,
)

expect(
    "Repeated ZIP downloads isolate launcher from WebView2 and ShellExecute",
    'TES3MPExpansionRequestDownload(downloadSlot.Hwnd, nativeStatus, "main-button")' in mismatch
    and 'TES3MPExpansionRequestDownload(downloadSlot.Hwnd, nativeStatus, "retry-button")' in mismatch
    and 'TES3MPExpansionRequestDownload(slotHwnd, statusControl, origin := "download")' in mismatch
    and 'global ExpansionMismatchFileButton := 0' in mismatch
    and 'global ExpansionMismatchDownloadSlot := 0' in mismatch
    and 'ExpansionMismatchDownloadSlot := downloadSlot' in mismatch
    and 'ExpansionMismatchDownloadSlot.Visible := false' in mismatch
    and 'ExpansionMismatchFileButton.Visible := true' in mismatch
    and 'SetTimer((*) => TES3MPExpansionActivateDownloadButton(slot), -30)' in mismatch
    and 'void HideEmbeddedExpansionDownloads(IntPtr placeholder)' in source
    and 'SendLauncherChatCommand(9, slotHwnd)' in mismatch
    and 'DllCall("SetWindowPos", "Ptr", ExpansionMismatchFileButton.Hwnd,' in mismatch
    and 'case 9: HideEmbeddedExpansionDownloads(m.LParam); break;' in source
    and 'void HideEmbeddedExpansionDownloads(IntPtr placeholder)' in source
    and 'ShowWindow(window.Handle,0);' in source
    and 'var browser=new WebView2 { Dock=DockStyle.Fill };' in source
    and "Run('rundll32.exe url.dll,FileProtocolHandler" in mismatch
    and 'Run(url)' not in mismatch
    and 'statusControl.Text := ""' in mismatch
    and 'OnMessage(0x004A, TES3MPExpansionZipAvailable)' in bootstrap
    and 'TES3MPExpansionZipAvailable(wParam, lParam, msg, hwnd)' in mismatch
    and 'ExpansionMismatchZipUrl := url' in mismatch
    and 'ExpansionMismatchZipUrl := ""' in mismatch
    and 'SendCopyDataTimeout(owner,0x004A,sender,' in source
    and 'ref data,0x0002,1500,out var result' in source
    and 'Marshal.StringToHGlobalUni(payload)' in source
    and 'Marshal.FreeHGlobal(utf16)' in source
    and '(WinGetPID("ahk_id " wParam) = EmbeddedChatPid)' in mismatch
    and 'PostMessage(owner,0x8335,popupSlot,IntPtr.Zero)' not in source
    and 'ExpansionMismatchRefreshPending' not in mismatch
    and 'ShowNativeExpansionDownloadCard(' not in source
    and 'setTimeout(()=>{scheduled=false;refresh();},150);' in source,
)

expect(
    "Plugin mismatch report identifies Expansion Pack versus other-plugin evidence without private fields",
    '"Your Plugins Don\'t Match the Servers"' in mismatch
    and '"Copy Diagnostic Info"' in mismatch
    and 'TES3MPCopyMismatchDiagnostics(nativeStatus)' in mismatch
    and 'report := TES3MPBuildMismatchDiagnostics()' in mismatch
    and 'TES3MPTryCopyMismatchReport(report, statusControl, limited)' in mismatch
    and 'A_Clipboard := report' in mismatch
    and '"Diagnostic Info Copied!"' in mismatch
    and 'if attempt < 3' in mismatch
    and 'TES3MPBuildMinimumMismatchDiagnostics()' in mismatch
    and 'TES3MPAnalyzeMismatchConfig(configText)' in mismatch
    and 'TES3MPAnalyzeMismatchLogText(raw)' in mismatch
    and 'TES3MPMismatchAssessment(info, markers, installed)' in mismatch
    and 'TES3MPRenderMismatchDiagnostics(info, markers, installed, version, stamp, fingerprint := 0)' in mismatch
    and 'result.MissingExpansion := true' in mismatch
    and 'result.MissingOther := true' in mismatch
    and 'result.MissingBaseMaster := true' in mismatch
    and 'info.OtherDuplicates += 1' in mismatch
    and 'info.ExpansionIndex != info.Total' in mismatch
    and 'if currentIndex = lastRejection\n            continue' in mismatch
    and 'markers.Status = "Read" && markers.Rejected' in mismatch
    and 'Other missing plugin specifically indicated:' in mismatch
    and 'Missing Expansion Pack specifically named:' in mismatch
    and 'Expansion Pack version verified: No (not checked)' in mismatch
    and 'OpenMW config check:' in mismatch
    and 'TES3MPReadSafeMismatchLogMarkers()' in mismatch
    and 'FileGetSize(config) > 1048576' in mismatch
    and 'file.Length - 65536' in mismatch
    and 'statusControl.Text := ""' in mismatch
    and "status.textContent='';" in source
    and 'Starting Download...' not in mismatch
    and 'Starting Download...' not in source
    and 'SAFE PLUGIN MISMATCH' not in mismatch
    and 'Privacy: No raw log' not in mismatch
    and 'Basic diagnostic info copied' not in mismatch
    and 'BuildLauncherDiagnostics()' not in mismatch
    and 'A_Clipboard := raw' not in mismatch
    and 'A_Clipboard := FileRead(' not in mismatch,
)
expect(
    "Windows build executes synthetic parser and report privacy fixtures",
    (ROOT / "scripts" / "test-expansion-diagnostics.ahk").is_file()
    and "test-expansion-diagnostics.ahk" in (
        ROOT / "scripts" / "build-windows.ps1"
    ).read_text(encoding="utf-8-sig")
    and "Plugin-mismatch diagnostic fixture tests failed" in (
        ROOT / "scripts" / "build-windows.ps1"
    ).read_text(encoding="utf-8-sig"),
)

expect(
    "Diagnostic reports are complete and standalone fixtures cannot emit unresolved-symbol warnings",
    'report := "TES3NP - Plugin Mismatch Diagnostics' in mismatch
    and 'report .= "Repeated additional content entries: "' in mismatch
    and 'report .= "Load-order wording near rejection: "' in mismatch
    and '    return report\n}' in mismatch
    and bool(section_between(
        mismatch,
        'TES3MPRenderMismatchDiagnostics(info, markers, installed, version, stamp, fingerprint := 0)\n{',
        'TES3MPNewExpansionFingerprintResult(status := "Not checked")\n{',
    ))
    and '    return "TES3NP - Plugin Mismatch Diagnostics' not in section_between(
        mismatch,
        'TES3MPRenderMismatchDiagnostics(info, markers, installed, version, stamp, fingerprint := 0)\n{',
        'TES3MPNewExpansionFingerprintResult(status := "Not checked")\n{',
    )
    and 'PatchConfigurationPath()' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'MismatchFixtureDisallow("configuration path")' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and all(marker in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig") for marker in (
        "global Client :=",
        "global LauncherGui := 0",
        "global EmbeddedChatPid := 0",
        'global DataFile := ""',
    ))
    and 'InStr(report, "Load-order wording near rejection: No")' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'TES3MPLastMismatchEvidence := TES3MPAnalyzeMismatchLogText(currentText)' in mismatch
    and 'TES3MPSelectMismatchLogEvidence(captured)' in mismatch
    and 'markers := TES3MPSelectMismatchLogEvidence(TES3MPLastMismatchEvidence)' in mismatch
    and 'Client evidence source: ' in mismatch
    and 'TES3MPLastMismatchEvidence := 0' in (
        ROOT / "src" / "game" / "session.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'chosen.Source = "Captured during failed login"' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'AutoHotkey fixture warnings detected; packaging stopped.' in (
        ROOT / "scripts" / "build-windows.ps1"
    ).read_text(encoding="utf-8-sig"),
)

expect(
    "Mismatch capture remains bounded to the current failed login and reports safe comparison categories",
    'Client.MismatchPending := true' in mismatch
    and 'Client.MismatchLogKey := key' in mismatch
    and 'key != Client.MismatchLogKey' in mismatch
    and 'Client.MismatchCaptureUntil := A_TickCount + 1500' in mismatch
    and 'TES3MPAccumulateMismatchDetailText(TES3MPLastMismatchEvidence, chunk)' in mismatch
    and 'TES3MPAccumulateMismatchLine(result, line)' in mismatch
    and 'Slot details (zero-based): ' in mismatch
    and 'if shown >= 12' in mismatch
    and 'result.SlotFlags[slot] := oldBits | newBits' in mismatch
    and 'TES3MPLastMismatchEvidence := 0' in (
        ROOT / "src" / "game" / "session.ahk"
    ).read_text(encoding="utf-8-sig"),
)
expect(
    "Expansion fingerprint uses Windows CNG and does not claim server version verification",
    'TES3MPFileSHA256(path)' in mismatch
    and 'bcrypt\\BCryptHashData' in mismatch
    and 'block := Buffer(1048576, 0)' in mismatch
    and 'Expansion ESP SHA-256: ' in mismatch
    and 'Expansion ESP size (bytes): ' in mismatch
    and 'Expansion Pack version verified: No (not checked)' in mismatch
    and 'known SHA-256 test vector' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig")
    and 'private comparison detail leaked' in (
        ROOT / "scripts" / "test-expansion-diagnostics.ahk"
    ).read_text(encoding="utf-8-sig"),
)

expansion_upload = (ROOT / "src" / "ui" / "expansion-upload.ahk").read_text(encoding="utf-8-sig")
expansion_worker = (ROOT / "scripts" / "import-expansion-pack.ps1").read_text(encoding="utf-8-sig")
expansion_build = (ROOT / "scripts" / "build-windows.ps1").read_text(encoding="utf-8-sig")
expansion_fixture = (ROOT / "scripts" / "test-import-expansion-folder.ps1").read_text(encoding="utf-8-sig")
expect(
    "Expansion source chooser offers explicit ZIP and extracted-folder options",
    '"Select ZIP (Recommended)"' in expansion_upload
    and '"Select Extracted Folder"' in expansion_upload
    and 'ChooseExpansionPackageSource(sourceGui, "zip")' in expansion_upload
    and 'ChooseExpansionPackageSource(sourceGui, "folder")' in expansion_upload
    and 'FileSelect(1, , "Choose the official NP Expansion Pack ZIP"' in expansion_upload
    and 'DirSelect(, 0, "Choose the extracted Expansion Pack folder containing Data Files")' in expansion_upload
    and 'InstallSelectedExpansionPackage(package)' in expansion_upload
    and 'StartExpansionImportWorker(package, morrowind, config)' in expansion_upload,
)
expect(
    "Folder imports use ZIP-equivalent allowlist, limits and unchanged rollback",
    'if ([IO.Directory]::Exists($Package)) {' in expansion_worker
    and "$folderIsDataFiles = $root.Name -ieq 'Data Files'" in expansion_worker
    and "elseif ($raw -match '(?i)(^|/)Data Files/(.+)$')" in expansion_worker
    and 'Get-ChildItem -LiteralPath $root.FullName -Recurse -Force -ErrorAction Stop' in expansion_worker
    and '[IO.FileAttributes]::ReparsePoint' in expansion_worker
    and 'AllowedAsset $relative' in expansion_worker
    and '$seen.Add($relative)' in expansion_worker
    and '$entryCount -gt 10000' in expansion_worker
    and '$total -gt 1073741824' in expansion_worker
    and 'Sha256 $target' in expansion_worker
    and 'if ($rollbackReady) {' in expansion_worker
    and 'CheckWorker $zip' in expansion_fixture
    and 'CheckWorker $packageRoot' in expansion_fixture
    and 'CheckWorker $payload' in expansion_fixture
    and 'CheckWorker $packageRoot ' in expansion_fixture
    and 'test-import-expansion-folder.ps1' in expansion_build,
)

expect(
    "Banner must stay owned by launcher and retain movement polling fallback",
    "SetNativeWindowOwner(banner.Handle, owner);" in source
    and "void PositionChatWindows()\n        {\n            // The existing chat polling is a safety net" in source
    and "bounds.Top - 48" in source,
)

expect(
    "Jiub Happy Hour face must use only the existing verified banner signal",
    "OnMessage(0x8334, LauncherHappyHourFaceStateChanged)" in jiub_ui
    and "PostMessage(owner, 0x8334, active ? new IntPtr(1) : IntPtr.Zero" in source
    and "NotifyLauncherHappyHourFace(true);" in source
    and "NotifyLauncherHappyHourFace(false);" in source
    and "HappyHourBannerVisible := visible" in jiub_ui,
)
expect(
    "Jiub Happy Hour face must follow banner close, hide and restore",
    'banner.FormClosed += (_, _) => {' in source
    and 'if (!happyHourBanner.Visible) {' in source
    and 'happyHourBanner.Show();\n                        // The verified banner is visible again after a launcher restore.\n                        NotifyLauncherHappyHourFace(true);' in source
    and 'happyHourBanner.Hide();\n                    // Keep Jiub\'s appearance in sync when the banner is hidden.\n                    NotifyLauncherHappyHourFace(false);' in source,
)
expect(
    "Jiub picture must be a bundled native launcher control, without a floating window",
    'asset := A_ScriptDir "\\assets\\happy-hour\\jiub-happy-hour.png"' in jiub_ui
    and (ROOT / "assets" / "happy-hour" / "jiub-happy-hour.png").is_file()
    and 'LauncherGui.Add("Picture"' in jiub_ui
    and ':= Gui(' not in jiub_ui
    and 'CreateHappyHourJiub()\n    CaptureLauncherControlLayout()' in bootstrap
    and 'HappyHourJiubPicture.Visible := HappyHourBannerVisible' in jiub_ui,
)




expect(
    "Static Happy Hour RGB pixie dust must be bundled and use the same banner state",
    (ROOT / "assets" / "happy-hour" / "pixie-dust.png").is_file()
    and 'asset := A_ScriptDir "\\assets\\happy-hour\\pixie-dust.png"' in jiub_ui
    and 'CreateHappyHourDust()' in jiub_ui
    and 'for offset in [[0, 0], [1, 0], [0, 1], [1, 1]]' in jiub_ui
    and 'w960 h720 Hidden Disabled BackgroundTrans +E0x20' in jiub_ui
    and 'for dust in HappyHourDustPictures' in jiub_ui
    and 'dust.Visible := HappyHourBannerVisible' in jiub_ui
    and 'HappyHourJiubPicture.Visible := HappyHourBannerVisible' in jiub_ui
    and 'SetTimer(AnimateHappyHour' not in jiub_ui,
)
expect(
    "Pixie dust must sit over background but under interactive launcher controls",
    (lambda front:
        front.index('LauncherGui.Add("Picture", "x0 y-4 w960 h720"')
        < front.index('CreateHappyHourDust()')
        < front.index('DragStrip := LauncherGui.Add(')
        < front.index('BuildButtonViewport()')
    )((ROOT / "src" / "ui" / "front-page.ahk").read_text(encoding="utf-8-sig")),
)

expect(
    "Vintage creatures are baked into the single launcher background",
    (lambda front, bootstrap:
        front.count('LauncherGui.Add("Picture", "x0 y-4 w960 h720"') == 1
        and "og-creatures-overlay.png" not in front
        and "og-creatures-overlay.png" not in bootstrap
        and not (ROOT / "assets" / "backgrounds" / "og-creatures-overlay.png").exists()
        and (ROOT / "assets" / "backgrounds" / "launcher.png").is_file()
        and front.index('LauncherGui.Add("Picture", "x0 y-4 w960 h720"')
            < front.index('CreateHappyHourDust()')
    )(
        (ROOT / "src" / "ui" / "front-page.ahk").read_text(encoding="utf-8-sig"),
        bootstrap,
    ),
)

expect(
    "Happy Hour banner has no dismiss button or dismissal state",
    'GoldButton("×"' not in source
    and 'dismissedHappyHourBannerId' not in source
    and 'happyHourBannerTitleInset.SetBounds(12, 7, width, 32)' in source,
)
expect(
    "Remove extra developer replay, special banner text and tray options",
    "--happy-hour-dev" not in source
    and "happyHourDevMode" not in source
    and "happyHourDevTicker" not in source
    and "HAPPY HOUR DEV PREVIEW" not in source
    and "Archived event - No live bonus" not in source
    and "HappyHourDevModeEnabled" not in jiub_ui
    and "A_TrayMenu.Add" not in jiub_ui
    and "--happy-hour-dev" not in
        (ROOT / "src" / "ui" / "embedded-chat.ahk").read_text(encoding="utf-8-sig"),
)
expect(
    "Jiub coordinates and native control remain intact",
    '"x438 y84 w120 h135 Hidden BackgroundTrans"' in jiub_ui
    and '#Include src\\ui\\happy-hour.ahk'
        in (ROOT / "tes3np.ahk").read_text(encoding="utf-8-sig")
    and 'HappyHourJiubPicture.Visible := HappyHourBannerVisible' in jiub_ui,
)

expect(
    "Full AppData reset must stop ChatHost before deletion",
    reset_ui.index("StopEmbeddedInGameChat()") >= 0
    and reset_ui.index("StopEmbeddedInGameChat()") < reset_ui.index("DirDelete(AppDataDirectory, true)"),
)
expect(
    "Full AppData reset must confirm ChatHost has exited before deleting user data",
    "chatPid := EmbeddedChatPid" in reset_ui
    and "stillRunning := ProcessWaitClose(chatPid, 5)" in reset_ui
    and "if stillRunning" in reset_ui
    and reset_ui.index("ProcessWaitClose(chatPid, 5)") < reset_ui.index("DirDelete(AppDataDirectory, true)"),
)
expect(
    "Reset shutdown must not recreate Roaming logs or scheduler settings",
    "LauncherDataResetting := true" in reset_ui
    and "if !LauncherDataResetting" in bootstrap
    and "ExitApp()" in reset_ui,
)
expect(
    "Reset mode must be part of centralized launcher state",
    "global LauncherDataResetting := false" in app_state,
)

if errors:
    print("Chat Host architectural contract violations:")
    for error in errors:
        print(" - " + error)
    sys.exit(1)

print("Chat Host contracts verified: Roaming AppData, verified offline Happy "
      "Hour cache, authenticated live fetching, first-login chat, native "
      "movement and atomic history writes.")
