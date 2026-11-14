using System;
using System.Buffers.Binary;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

internal static class ExpansionZipChecksum
{
    private const int EndRecordSize = 22;
    private const int MaxTail = EndRecordSize + ushort.MaxValue;
    private const int MaxDirectory = 4 * 1024 * 1024;
    private const string Plugin = "NP Expansion Pack.esp";

    internal static async Task<string> ReadAsync(Uri url)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(4));
        using var client = new HttpClient(new HttpClientHandler {
            AllowAutoRedirect = false, UseCookies = false
        });
        try
        {
            return await ReadAsync(client, url, timeout.Token).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is HttpRequestException or OperationCanceledException or IOException or InvalidDataException)
        {
            return "";
        }
    }

    internal static async Task<string> ReadAsync(HttpClient client, Uri url, CancellationToken token)
    {
        var (tail, length) = await ReadRangeAsync(client, url, null, MaxTail, null, token).ConfigureAwait(false);
        var end = FindEndRecord(tail);
        if (end < 0 || U16(tail, end + 4) != 0 || U16(tail, end + 6) != 0
            || U16(tail, end + 8) != U16(tail, end + 10))
            return "";

        long endOffset = length - tail.Length + end;
        long directoryLimit = endOffset;
        ulong entries = U16(tail, end + 10);
        ulong size = U32(tail, end + 12);
        ulong offset = U32(tail, end + 16);
        if (entries == ushort.MaxValue || size == uint.MaxValue || offset == uint.MaxValue)
        {
            const int locatorSize = 20;
            const int zip64Size = 56;
            if (endOffset < locatorSize)
                return "";

            byte[] locator = end >= locatorSize
                ? tail[(end - locatorSize)..end]
                : (await ReadRangeAsync(client, url, endOffset - locatorSize, locatorSize, length, token)
                    .ConfigureAwait(false)).Bytes;
            if (U32(locator, 0) != 0x07064b50 || U32(locator, 4) != 0 || U32(locator, 16) != 1
                || endOffset < locatorSize + zip64Size || U64(locator, 8) > (ulong)(endOffset - locatorSize - zip64Size))
                return "";

            directoryLimit = (long)U64(locator, 8);
            int zip64InTail = (int)(directoryLimit - (length - tail.Length));
            byte[] record = directoryLimit >= length - tail.Length
                ? tail[zip64InTail..(zip64InTail + zip64Size)]
                : (await ReadRangeAsync(client, url, directoryLimit, zip64Size, length, token)
                    .ConfigureAwait(false)).Bytes;
            if (U32(record, 0) != 0x06064b50 || U64(record, 4) < 44
                || U64(record, 4) != (ulong)(endOffset - locatorSize - directoryLimit - 12)
                || U32(record, 16) != 0 || U32(record, 20) != 0 || U64(record, 24) != U64(record, 32))
                return "";
            entries = U64(record, 32);
            size = U64(record, 40);
            offset = U64(record, 48);
        }

        const int centralHeaderSize = 46;
        if (size > MaxDirectory || entries == 0 || entries > size / centralHeaderSize
            || offset > (ulong)directoryLimit || size > (ulong)directoryLimit - offset)
            return "";

        long tailOffset = length - tail.Length;
        byte[] directory = offset >= (ulong)tailOffset
            ? tail[(int)((long)offset - tailOffset)..(int)((long)(offset + size) - tailOffset)]
            : (await ReadRangeAsync(client, url, (long)offset, (int)size, length, token).ConfigureAwait(false)).Bytes;
        return FindPluginChecksum(directory, (int)entries);
    }

    private static async Task<(byte[] Bytes, long Length)> ReadRangeAsync(
        HttpClient client, Uri url, long? start, int count, long? expectedLength, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Range = new RangeHeaderValue(start, start is long from ? from + count - 1 : count);
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token)
            .ConfigureAwait(false);
        var range = response.Content.Headers.ContentRange;
        if (response.StatusCode != HttpStatusCode.PartialContent || range?.Unit != "bytes"
            || range.Length is not long length || length <= 0
            || (expectedLength.HasValue && length != expectedLength.Value))
            throw new InvalidDataException("No bounded ZIP response.");

        long first = start ?? Math.Max(0, length - count);
        long last = start.HasValue ? first + count - 1 : length - 1;
        if (range.From != first || range.To != last || last >= length)
            throw new InvalidDataException("Unexpected ZIP range.");

        byte[] bytes = new byte[checked((int)(last - first + 1))];
        using var stream = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
        await stream.ReadExactlyAsync(bytes, token).ConfigureAwait(false);
        return (bytes, length);
    }

    private static int FindEndRecord(byte[] tail)
    {
        for (int at = tail.Length - EndRecordSize; at >= 0; at--)
            if (U32(tail, at) == 0x06054b50 && U16(tail, at + 20) == tail.Length - at - EndRecordSize)
                return at;
        return -1;
    }

    private static string FindPluginChecksum(byte[] directory, int entries)
    {
        string checksum = "";
        int at = 0;
        for (int i = 0; i < entries; i++)
        {
            const int headerSize = 46;
            if (at > directory.Length - headerSize || U32(directory, at) != 0x02014b50)
                return "";
            int nameSize = U16(directory, at + 28);
            int end = at + headerSize + nameSize + U16(directory, at + 30) + U16(directory, at + 32);
            if (end > directory.Length || nameSize == 0)
                return "";

            string name = Encoding.UTF8.GetString(directory, at + headerSize, nameSize);
            if (name.Equals(Plugin, StringComparison.OrdinalIgnoreCase)
                || name.Equals("Data Files/" + Plugin, StringComparison.OrdinalIgnoreCase)
                || name.EndsWith("/Data Files/" + Plugin, StringComparison.OrdinalIgnoreCase))
            {
                if (checksum.Length != 0 || (U16(directory, at + 8) & 1) != 0
                    || ((U32(directory, at + 38) >> 16) & 0xF000) == 0xA000
                    || name.StartsWith('/') || name.Contains('\\') || name.Contains(':')
                    || Array.IndexOf(name.Split('/'), "..") >= 0)
                    return "";
                checksum = U32(directory, at + 16).ToString("X8", CultureInfo.InvariantCulture);
            }
            at = end;
        }
        return at == directory.Length ? checksum : "";
    }

    private static ushort U16(byte[] bytes, int offset) => BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(offset));
    private static uint U32(byte[] bytes, int offset) => BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset));
    private static ulong U64(byte[] bytes, int offset) => BinaryPrimitives.ReadUInt64LittleEndian(bytes.AsSpan(offset));
}
