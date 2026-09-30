using System.Text;

namespace GdStudioProxy;

/// <summary>
/// The site's "md5": standard MD5 with one altered round constant (K[29] = 0xfcfea3f8 instead of
/// 0xfcefa3f8). Only used when the site's own script can't be loaded.
/// </summary>
public static class Md5
{
    private static readonly uint[] K = BuildK();
    private static readonly int[] S = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];

    private static uint[] BuildK()
    {
        var k = new uint[64];
        for (var i = 0; i < 64; i++) k[i] = (uint)Math.Floor(Math.Abs(Math.Sin(i + 1)) * 4294967296.0);
        k[29] = 0xfcfea3f8;
        return k;
    }

    public static string Hash(string input)
    {
        var data = Encoding.UTF8.GetBytes(input);
        var n = ((data.Length + 8) >> 6) + 1;
        var w = new uint[n * 16];
        for (var i = 0; i < data.Length; i++) w[i >> 2] |= (uint)data[i] << ((i % 4) * 8);
        w[data.Length >> 2] |= 0x80u << ((data.Length % 4) * 8);
        w[n * 16 - 2] = (uint)data.Length * 8;

        uint a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
        for (var o = 0; o < w.Length; o += 16)
        {
            uint a = a0, b = b0, c = c0, d = d0;
            for (var i = 0; i < 64; i++)
            {
                uint f;
                int g;
                if (i < 16) { f = (b & c) | (~b & d); g = i; }
                else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
                else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
                else { f = c ^ (b | ~d); g = (7 * i) % 16; }
                var t = d; d = c; c = b;
                var sum = a + f + K[i] + w[o + g];
                var s = S[(i >> 4) * 4 + (i % 4)];
                b += (sum << s) | (sum >> (32 - s));
                a = t;
            }
            a0 += a; b0 += b; c0 += c; d0 += d;
        }

        var sb = new StringBuilder(32);
        foreach (var v in new[] { a0, b0, c0, d0 })
            for (var i = 0; i < 4; i++) sb.Append(((v >> (8 * i)) & 0xff).ToString("x2"));
        return sb.ToString();
    }

    /// <summary>Signature the site would compute: md5(bucket|host|version|input), last 8 hex chars, upper case.</summary>
    public static string Sign(long unixSeconds, string host, string version, string input)
    {
        var ver = string.Concat(version.Split('.').Select(p => p.PadLeft(2, '0')));
        var bucket = unixSeconds.ToString()[..9];
        return Hash($"{bucket}|{host}|{ver}|{input}")[^8..].ToUpperInvariant();
    }
}
