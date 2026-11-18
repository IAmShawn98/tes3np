using System.Runtime.InteropServices;
using Microsoft.Web.WebView2.WinForms;
using static GameChatNative;

internal sealed partial class GameChatWindow
{
    // A single cancellable background transfer per Chat Host. The signed
    // CDN query remains in memory, never in a command line or log file.
    int expansionAutoDownloading;

    CancellationTokenSource? expansionAutoDownloadCancellation;

    readonly string expansionAutoDownloadFolder=Path.Combine(ChatDataRoot,"expansion-downloads");

    static bool IsOfficialExpansionDownloadUrl(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            !Uri.TryCreate(value, UriKind.Absolute, out var uri))
            return false;
        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            (uri.Host != "cdn.discordapp.com" && uri.Host != "media.discordapp.net") ||
            uri.UserInfo.Length != 0 || !uri.AbsolutePath.StartsWith("/attachments/", StringComparison.Ordinal))
            return false;
        try {
            var filename=Uri.UnescapeDataString(
                System.IO.Path.GetFileName(uri.AbsolutePath));
            return filename.EndsWith(".zip", StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    // Each click is an independent request; a cancelled browser download
    // cannot leave a busy flag set or disable a second attempt.
    void RequestExpansionDownload(string? url, string origin)
    {
        if (!IsOfficialExpansionDownloadUrl(url))
        {
            Log("EXPANSION | Download request rejected: invalid ZIP URL ("+origin+").");
            return;
        }
        string freshUrl=url!;
        // The original Discord popup stays open and is never rebuilt per
        // download. Cross-process WebView2 teardown on every click could
        // deadlock the launcher after one or two attempts.
        _=Task.Run(()=>{
            try {
                using var started=System.Diagnostics.Process.Start(
                    new System.Diagnostics.ProcessStartInfo {
                        FileName=freshUrl,
                        UseShellExecute=true
                    });
                if (started==null)
                    Log("EXPANSION | Shell returned no process handle ("+origin+").");
                else
                    Log("EXPANSION | ZIP sent to default browser ("+origin+").");
            }
            catch (Exception ex) {
                Log("EXPANSION | Browser ZIP handoff failed ("+origin+"): "+ex.GetType().Name);
            }
        });
    }

    // Command 13 is accepted only for the CURRENT authenticated Discord
    // preview slot. No generic external URL or arbitrary file path is
    // accepted from the launcher.
    void StartExpansionAutoDownload(IntPtr slot)
    {
        if (slot == IntPtr.Zero || slot != expansionDownloadsParent ||
            !IsWindow(slot) || !IsWindow(owner) || closingChat ||
            !discordChannelReady || discordLoginVisible ||
            !IsOfficialExpansionDownloadUrl(expansionPublishedZipUrl)
            || expansionLatestZipUrl != expansionPublishedZipUrl)
        {
            Log("EXPANSION | Automatic download denied: no authenticated current ZIP.");
            if (slot==expansionDownloadsParent && IsWindow(owner))
                PostMessage(owner,0x8338,new IntPtr(-1),Handle);
            return;
        }
        if (System.Threading.Interlocked.CompareExchange(ref expansionAutoDownloading,1,0)!=0)
        {
            PostMessage(owner,0x8338,new IntPtr(-1),Handle);
            return;
        }
        var cancellation=new CancellationTokenSource(TimeSpan.FromHours(4));
        expansionAutoDownloadCancellation=cancellation;
        string url=expansionPublishedZipUrl!;
        string expectedChecksum;
        lock (expansionLinkPublishLock)
            expectedChecksum = expansionZipChecksums.GetValueOrDefault(new Uri(url).AbsolutePath, "");
        IntPtr sender=Handle; // Capture HWND on the WinForms thread.
        PostMessage(owner,0x8338,IntPtr.Zero,sender);
        _=Task.Run(()=>DownloadExpansionZipAsync(url,slot,sender,cancellation,expectedChecksum));
    }

    async Task DownloadExpansionZipAsync(string url,IntPtr slot,IntPtr sender,
        CancellationTokenSource cancellation, string expectedChecksum)
    {
        string? partial=null,completed=null;
        bool accepted=false;
        try
        {
            Directory.CreateDirectory(expansionAutoDownloadFolder);
            // Never trust a CDN-supplied filename for a local path.
            string stem="tes3np-"+Guid.NewGuid().ToString("N");
            partial=Path.Combine(expansionAutoDownloadFolder,stem+".partial");
            completed=Path.Combine(expansionAutoDownloadFolder,stem+".zip");
            using var handler=new HttpClientHandler { AllowAutoRedirect=false,UseCookies=false };
            using var client=new HttpClient(handler) { Timeout=System.Threading.Timeout.InfiniteTimeSpan };
            using var response=await client.GetAsync(url,
                HttpCompletionOption.ResponseHeadersRead,cancellation.Token);
            response.EnsureSuccessStatusCode();
            const long maxZipBytes=16L*1024*1024*1024;
            long? declared=response.Content.Headers.ContentLength;
            if (declared.HasValue && (declared.Value<=0 || declared.Value>maxZipBytes))
                throw new InvalidDataException("ZIP size outside allowed range.");
            var drive=new DriveInfo(Path.GetPathRoot(expansionAutoDownloadFolder)!);
            long space=drive.AvailableFreeSpace;
            if (space<512L*1024*1024 ||
                (declared.HasValue && declared.Value>space-512L*1024*1024))
                throw new IOException("Insufficient disk space for Expansion Pack download.");
            await using (var input=await response.Content.ReadAsStreamAsync(cancellation.Token))
            await using (var output=new FileStream(partial,FileMode.CreateNew,FileAccess.Write,
                FileShare.None,131072,useAsync:true))
            {
                byte[] buffer=new byte[131072];
                long received=0;
                int previousPercent=-1;
                long lastReport=Environment.TickCount64;
                int count;
                while ((count=await input.ReadAsync(buffer,cancellation.Token))!=0)
                {
                    received+=count;
                    if (received>maxZipBytes || received>space-512L*1024*1024)
                        throw new IOException("Expansion Pack download exceeded available space.");
                    await output.WriteAsync(buffer.AsMemory(0,count),cancellation.Token);
                    int percent=declared.HasValue
                        ? (int)Math.Clamp(received*100/declared.Value,1,99) : 0;
                    long now=Environment.TickCount64;
                    if (percent!=previousPercent && now-lastReport>=250)
                    {
                        PostMessage(owner,0x8338,new IntPtr(percent),sender);
                        previousPercent=percent;
                        lastReport=now;
                    }
                }
                if (received==0 || (declared.HasValue && received!=declared.Value))
                    throw new InvalidDataException("ZIP download was incomplete.");
                await output.FlushAsync(cancellation.Token);
            }
            // Reject error pages masquerading as ZIPs before importing.
            using (var check=File.OpenRead(partial))
            {
                byte[] prefix=new byte[4];
                if (check.Read(prefix,0,4)!=4 || prefix[0]!=0x50 ||
                    prefix[1]!=0x4B || prefix[2]!=0x03 || prefix[3]!=0x04)
                    throw new InvalidDataException("Downloaded file is not a ZIP archive.");
            }
            string checksum = ExpansionZipChecksum.ReadDownloaded(partial);
            if (checksum.Length == 0 || (expectedChecksum.Length != 0 && checksum != expectedChecksum))
                throw new InvalidDataException("The downloaded Expansion Pack plugin differs from the selected ZIP.");
            cancellation.Token.ThrowIfCancellationRequested();
            File.Move(partial,completed);
            partial=null;
            string payload=slot.ToInt64().ToString(
                System.Globalization.CultureInfo.InvariantCulture)+"|"+completed+"|"+checksum;
            IntPtr utf16=IntPtr.Zero;
            try
            {
                utf16=Marshal.StringToHGlobalUni(payload);
                var data=new COPYDATASTRUCT {
                    dwData=new IntPtr(0x8337),
                    cbData=checked((payload.Length+1)*2),
                    lpData=utf16
                };
                // Bounded IPC; AHK queues the importer after returning.
                IntPtr delivered=SendCopyDataTimeout(owner,0x004A,sender,
                    ref data,0x0002,1500,out var acknowledged);
                accepted=delivered!=IntPtr.Zero && acknowledged!=IntPtr.Zero;
            }
            finally { if (utf16!=IntPtr.Zero) Marshal.FreeHGlobal(utf16); }
            if (accepted) Log("EXPANSION | Verified ZIP transferred to installer.");
            else Log("EXPANSION | Download completed but installer did not acknowledge.");
        }
        catch (OperationCanceledException)
        {
            Log("EXPANSION | Automatic download cancelled or timed out.");
        }
        catch (Exception ex)
        {
            // Never log signed CDN URLs, private paths or exception messages.
            Log("EXPANSION | Automatic download failed: "+ex.GetType().Name);
        }
        finally
        {
            if (partial!=null) try { File.Delete(partial); } catch { }
            if (!accepted && completed!=null) try { File.Delete(completed); } catch { }
            // Closing the embedded download view clears its slot and
            // is an intentional cancellation. A timeout cancels the same
            // token but leaves the slot alive: report that as a failure
            // so the launcher presents Try Again / Choose ZIP / Cancel.
            if (!accepted && expansionDownloadsParent==slot)
                PostMessage(owner,0x8338,new IntPtr(-1),sender);
            if (ReferenceEquals(expansionAutoDownloadCancellation,cancellation))
                expansionAutoDownloadCancellation=null;
            System.Threading.Interlocked.Exchange(ref expansionAutoDownloading,0);
            cancellation.Dispose();
        }
    }

    // Share the validated signed CDN URL with the AHK-owned dialog
    // exactly once per discovered/updated ZIP. Its native retry button
    // must NOT depend on this WinForms message loop or a WebView repaint.
    void PublishExpansionUrlToLauncher(string url, IReadOnlyList<string> history)
    {
        if (!IsOfficialExpansionDownloadUrl(url)) return;
        IntPtr slot=expansionDownloadsParent;
        if (slot==IntPtr.Zero || !IsWindow(slot) || !IsWindow(owner))
            return;
        // Snapshot sender HWND while on the WinForms UI thread. Never
        // access Control.Handle from the background IPC worker.
        IntPtr sender=Handle;
        int revision = Interlocked.Increment(ref expansionLinkRevision);
        _ = Task.Run(async () => {
            var current = ReadExpansionChecksumAsync(url);
            var previous = Task.WhenAll(history.Select(async prior => {
                string priorChecksum = await ReadExpansionChecksumAsync(prior).ConfigureAwait(false);
                string filename = Uri.UnescapeDataString(new Uri(prior).Segments[^1]);
                var version = System.Text.RegularExpressions.Regex.Match(filename,
                    @"^NP[ _.-]+Expansion[ _.-]+Pack[ _.-]+(v\d{1,3}(?:\.\d{1,3}){1,3}[a-z]{0,3})\.zip$",
                    System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                return priorChecksum.Length != 0 && version.Success
                    ? priorChecksum + "=" + version.Groups[1].Value.ToLowerInvariant() : "";
            }));
            string checksum = await current.ConfigureAwait(false);
            string[] older = await previous.ConfigureAwait(false);
            lock (expansionLinkPublishLock)
            {
                // A previously queued signed URL must never replace a
                // newer ZIP or a link from a freshly recreated dialog.
                if (expansionLatestZipUrl!=url || expansionDownloadsParent!=slot
                    || revision != Volatile.Read(ref expansionLinkRevision))
                    return;
                expansionPublishedZipUrl = url;
                PublishExpansionLink(slot, sender, url, checksum, string.Join(",", older.Where(x => x.Length != 0)));
            }
        });
    }

    async Task<string> ReadExpansionChecksumAsync(string url)
    {
        var uri = new Uri(url);
        lock (expansionLinkPublishLock)
            if (expansionZipChecksums.TryGetValue(uri.AbsolutePath, out string? cached))
                return cached;
        string checksum = await ExpansionZipChecksum.ReadAsync(uri).ConfigureAwait(false);
        if (checksum.Length != 0)
        {
            lock (expansionLinkPublishLock)
            {
                if (expansionZipChecksums.Count >= 24)
                    expansionZipChecksums.Clear();
                expansionZipChecksums[uri.AbsolutePath] = checksum;
            }
        }
        return checksum;
    }
}
