using System.Text.RegularExpressions;
using Jint;
using Microsoft.Extensions.Logging;

namespace GdStudioProxy;

/// <summary>
/// Computes the site's <c>s=</c> signature. The API host redirects to the site, so the site's own script
/// (crc32.min.js) is downloaded from there and run in Jint, since the scheme may change at any time.
/// If that fails, <see cref="Md5"/> is used instead.
/// </summary>
internal sealed partial class Signer(HttpClient http, string api, ILogger log)
{
    private const string FallbackVersion = "2026.09.25";
    private static readonly TimeSpan ClockTtl = TimeSpan.FromSeconds(300);
    private static readonly TimeSpan MinReloadGap = TimeSpan.FromSeconds(5);

    private sealed record Site(string Origin, string Host, string Version, Engine? Engine, DateTime LoadedAt);
    private sealed record Clock(long Server, long Local);

    private readonly SemaphoreSlim _loadLock = new(1, 1);
    private Site? _site;
    private volatile Clock? _clock;
    private DateTime _clockFetchedAt;

    /// <summary>
    /// Loads the site script and the server clock ahead of the first request, so that request only pays for the signing.
    /// Never throws: if it fails, the first real request simply does the same work itself.
    /// </summary>
    public async Task WarmUpAsync()
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            var site = await GetSiteAsync(reload: false, CancellationToken.None);
            await RefreshClockAsync(site, CancellationToken.None);
            log.LogInformation("warm-up done in {Ms} ms, the first signed request will not wait for the site", watch.ElapsedMilliseconds);
        }
        catch (Exception ex)
        {
            log.LogWarning(ex, "warm-up failed after {Ms} ms, the first signed request will load the site itself", watch.ElapsedMilliseconds);
        }
    }

    /// <summary>Signs <paramref name="input"/> (already url-encoded), or only resolves the site origin when it is null.</summary>
    public async Task<(string Origin, string? Value)> SignAsync(string? input, bool reload, CancellationToken ct)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        // The load is not tied to this caller: if the caller gives up (timeout) it keeps running,
        // so the next request finds the site ready instead of starting over.
        var site = await GetSiteAsync(reload, CancellationToken.None).WaitAsync(ct);
        log.LogInformation("site ready in {Ms} ms (origin {Origin}, version {Version}, engine {Engine})",
            watch.ElapsedMilliseconds, site.Origin, site.Version, site.Engine != null ? "script" : "built-in");
        if (input == null) return (site.Origin, null);

        await RefreshClockAsync(site, ct);
        if (site.Engine != null)
        {
            try
            {
                lock (site.Engine) return (site.Origin, site.Engine.Invoke("crc32", input).AsString());
            }
            catch (Exception ex)
            {
                log.LogWarning(ex, "site signer failed, using the built-in one");
            }
        }
        return (site.Origin, Md5.Sign(NowSeconds(), site.Host, site.Version, input));
    }

    private long NowSeconds()
    {
        var local = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var c = _clock;
        return c == null ? local : c.Server + (local - c.Local);
    }

    private async Task RefreshClockAsync(Site site, CancellationToken ct)
    {
        if (_clock != null && DateTime.UtcNow - _clockFetchedAt < ClockTtl) return;
        try
        {
            var text = await http.GetStringAsync($"{site.Origin}/time", ct);
            if (long.TryParse(text.Trim(), out var server))
            {
                _clock = new Clock(server, DateTimeOffset.UtcNow.ToUnixTimeSeconds());
                _clockFetchedAt = DateTime.UtcNow;
                log.LogInformation("server clock fetched: server={Server}, local={Local}, offset={Offset}s",
                    server, _clock.Local, server - _clock.Local);
            }
        }
        catch (Exception ex)
        {
            log.LogWarning(ex, "server time unavailable, using the local clock");
        }
    }

    private async Task<Site> GetSiteAsync(bool reload, CancellationToken ct)
    {
        var current = _site;
        if (current != null && !reload) return current;
        await _loadLock.WaitAsync(ct);
        try
        {
            // someone else loaded it while we waited, or it was reloaded moments ago
            if (_site != null && (_site != current || DateTime.UtcNow - _site.LoadedAt < MinReloadGap)) return _site;
            return _site = await LoadSiteAsync(ct);
        }
        finally
        {
            _loadLock.Release();
        }
    }

    private async Task<Site> LoadSiteAsync(CancellationToken ct)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        log.LogInformation("loading the site to find the signer (from {Api})", api);
        using var page = await http.GetAsync($"{new Uri(api).GetLeftPart(UriPartial.Authority)}/", ct); // redirects to the site
        log.LogInformation("site page: {Status} from {Uri} in {Ms} ms", (int)page.StatusCode, page.RequestMessage?.RequestUri, watch.ElapsedMilliseconds);
        page.EnsureSuccessStatusCode();
        var siteUri = page.RequestMessage!.RequestUri!;
        var html = await page.Content.ReadAsStringAsync(ct);
        var scripts = ScriptSrc().Matches(html).Select(m => new Uri(siteUri, m.Groups[1].Value)).ToList();

        var version = FallbackVersion;
        var playerUri = scripts.FirstOrDefault(u => u.AbsolutePath.EndsWith("player.js"));
        if (playerUri != null)
        {
            var m = VersionField().Match(await http.GetStringAsync(playerUri, ct));
            if (m.Success) version = m.Groups[1].Value;
        }

        Engine? engine = null;
        var crcUri = scripts.FirstOrDefault(u => u.AbsolutePath.Contains("crc32"));
        if (crcUri != null)
        {
            try { engine = BuildEngine(await http.GetStringAsync(crcUri, ct), siteUri.Host, version); }
            catch (Exception ex) { log.LogWarning(ex, "site script unusable, using the built-in signer"); }
        }
        else
        {
            log.LogWarning("site script not found, using the built-in signer");
        }

        var origin = siteUri.GetLeftPart(UriPartial.Authority);
        log.LogInformation("signing via {Origin} (version {Version}, {Mode}), site load took {Ms} ms", origin, version, engine != null ? "site script" : "built-in", watch.ElapsedMilliseconds);
        return new Site(origin, siteUri.Host, version, engine, DateTime.UtcNow);
    }

    // The script expects a browser: window.location, mkPlayer.version and a synchronous GET /time via XMLHttpRequest.
    private Engine BuildEngine(string script, string host, string version)
    {
        var engine = new Engine(o => o.TimeoutInterval(TimeSpan.FromSeconds(5)));
        engine.SetValue("__now", new Func<string>(() => NowSeconds().ToString()));
        engine.SetValue("__host", host);
        engine.SetValue("__version", version);
        engine.Execute("""
            var window = globalThis; window.window = window;
            var location = { hostname: __host }; window.location = location;
            var mkPlayer = { version: __version };
            var navigator = {}; var document = {};
            function setTimeout() { return 0; } function clearTimeout() {}
            function XMLHttpRequest() {}
            XMLHttpRequest.prototype.open = function () {};
            XMLHttpRequest.prototype.setRequestHeader = function () {};
            XMLHttpRequest.prototype.getResponseHeader = function () { return null; };
            XMLHttpRequest.prototype.send = function () { this.status = 200; this.readyState = 4; this.responseText = this.response = __now(); };
            """);
        engine.Execute(script);
        engine.Invoke("crc32", "x"); // fail now, not on the first real request
        return engine;
    }

    [GeneratedRegex("src=\"([^\"]+\\.js[^\"]*)\"")]
    private static partial Regex ScriptSrc();

    [GeneratedRegex("version:\"([^\"]+)\"")]
    private static partial Regex VersionField();
}
