using System.Net;
using System.Web;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace GdStudioProxy;

/// <summary>
/// Sends API calls for sources that aren't public to the site host with the <c>s=</c> signature appended.
/// Public sources and everything that isn't an API call go through untouched, and no parameter is ever changed.
/// Settings come from the host's GDStudio config section: Api, Proxy and PublicSources (default netease,joox,bilibili).
/// </summary>
public sealed class SigningHandler : DelegatingHandler
{
    // shared, so the downloaded script and clock survive the client factory recycling handlers
    private static Signer? _signer;
    private static readonly object InitLock = new();

    private readonly Uri _api;
    private readonly HashSet<string> _publicSources;
    private readonly ILogger _log;
    private readonly Signer _sign;

    public SigningHandler(IConfiguration config, ILoggerFactory loggers)
    {
        var section = config.GetSection("GDStudio");
        _api = new Uri(section["Api"] is { Length: > 0 } a ? a : "https://music-api.gdstudio.xyz/api.php");
        _publicSources = (section["PublicSources"] is { Length: > 0 } p ? p : "netease,joox,bilibili")
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        _log = loggers.CreateLogger("GdStudioProxy");
        lock (InitLock)
        {
            if (_signer == null)
            {
                _signer = new Signer(CreateHttpClient(section["Proxy"]), _api.ToString(), _log);
                // Only when a configured source actually needs signing (e.g. apple), start loading now, at launch
                var sources = (section["Source"] is { Length: > 0 } src ? src : "netease")
                    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                if (sources.Any(x => !_publicSources.Contains(x)))
                {
                    _log.LogInformation("a configured source needs signing, warming up the signer now");
                    _ = _signer.WarmUpAsync();
                }
            }
            _sign = _signer;
        }
    }

    private static HttpClient CreateHttpClient(string? proxy)
    {
        var handler = new SocketsHttpHandler { PooledConnectionLifetime = TimeSpan.FromMinutes(5) };
        if (!string.IsNullOrWhiteSpace(proxy))
        {
            handler.Proxy = new WebProxy(new Uri(proxy.Trim()));
            handler.UseProxy = true;
        }
        return new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        if (!NeedsSigning(request, out var input, out var alreadySigned))
        {
            var passthrough = await base.SendAsync(request, ct);
            await LogResponseAsync("passthrough", request.RequestUri, passthrough, watch, ct);
            return passthrough;
        }

        var response = await SendSignedAsync(request, input, alreadySigned, reload: false, ct);
        if (response.StatusCode == HttpStatusCode.Unauthorized && !alreadySigned)
        {
            _log.LogWarning("got 401 from the signed request, reloading the site script and retrying once");
            response.Dispose();
            response = await SendSignedAsync(request, input, alreadySigned, reload: true, ct); // the scheme may have changed
        }
        return response;
    }

    private async Task<HttpResponseMessage> SendSignedAsync(HttpRequestMessage original, string input, bool alreadySigned, bool reload, CancellationToken ct)
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        (string Origin, string? Value) sig;
        try
        {
            sig = await _sign.SignAsync(alreadySigned ? null : input, reload, ct);
            _log.LogInformation("signed in {Ms} ms (reload={Reload}, callerSigned={Caller}, origin={Origin}, s={Sig})",
                watch.ElapsedMilliseconds, reload, alreadySigned, sig.Origin, sig.Value ?? "(none)");
        }
        catch (OperationCanceledException)
        {
            _log.LogWarning("signing cancelled after {Ms} ms (host timeout or caller cancelled)", watch.ElapsedMilliseconds);
            throw;
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "signing unavailable after {Ms} ms, sending the request unsigned", watch.ElapsedMilliseconds);
            var unsigned = await base.SendAsync(original, ct);
            await LogResponseAsync("unsigned-fallback", original.RequestUri, unsigned, watch, ct);
            return unsigned;
        }

        var uri = original.RequestUri!;
        var target = $"{sig.Origin}{uri.AbsolutePath}{uri.Query}" + (sig.Value == null ? "" : $"&s={sig.Value}");
        using var signed = new HttpRequestMessage(original.Method, target);
        foreach (var h in original.Headers) signed.Headers.TryAddWithoutValidation(h.Key, h.Value);
        var result = await base.SendAsync(signed, ct);
        await LogResponseAsync("signed", signed.RequestUri, result, watch, ct);
        if (result.IsSuccessStatusCode)
        {
            result = await PostProcessResponseAsync(result, uri, sig.Origin, ct);
        }
        return result;
    }

    private async Task<HttpResponseMessage> PostProcessResponseAsync(HttpResponseMessage response, Uri requestUri, string origin, CancellationToken ct)
    {
        var query = HttpUtility.ParseQueryString(requestUri.Query);
        var types = query["types"];
        var source = query["source"] ?? "";

        if (types == "url")
        {
            try
            {
                var body = await response.Content.ReadAsStringAsync(ct);
                var node = System.Text.Json.Nodes.JsonNode.Parse(body);
                if (node is System.Text.Json.Nodes.JsonObject obj && obj["url"]?.GetValue<string>() is { } urlStr)
                {
                    if (!urlStr.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
                        !urlStr.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                    {
                        var resolved = $"{origin.TrimEnd('/')}/{urlStr.TrimStart('/')}";
                        obj["url"] = resolved;
                        var newContent = new StringContent(node.ToJsonString(), System.Text.Encoding.UTF8, "application/json");
                        var newResponse = new HttpResponseMessage(response.StatusCode) { Content = newContent };
                        foreach (var h in response.Headers) newResponse.Headers.TryAddWithoutValidation(h.Key, h.Value);
                        response.Dispose();
                        _log.LogInformation("rewrote relative download url to {Url}", resolved);
                        return newResponse;
                    }
                }
            }
            catch (Exception ex)
            {
                _log.LogWarning(ex, "failed to post-process url response");
            }
        }
        else if (types == "search" && source.StartsWith("apple", StringComparison.OrdinalIgnoreCase))
        {
            var queryName = query["name"]?.Trim();
            if (!string.IsNullOrWhiteSpace(queryName))
            {
                try
                {
                    var body = await response.Content.ReadAsStringAsync(ct);
                    var node = System.Text.Json.Nodes.JsonNode.Parse(body);
                    if (node is System.Text.Json.Nodes.JsonArray arr)
                    {
                        var modified = false;
                        foreach (var item in arr)
                        {
                            if (item is System.Text.Json.Nodes.JsonObject track && track["artist"] is System.Text.Json.Nodes.JsonArray artists)
                            {
                                var hasName = artists.Any(a => string.Equals(a?.GetValue<string>(), queryName, StringComparison.OrdinalIgnoreCase));
                                if (!hasName)
                                {
                                    artists.Add(queryName);
                                    modified = true;
                                }
                            }
                        }
                        if (modified)
                        {
                            var newContent = new StringContent(node.ToJsonString(), System.Text.Encoding.UTF8, "application/json");
                            var newResponse = new HttpResponseMessage(response.StatusCode) { Content = newContent };
                            foreach (var h in response.Headers) newResponse.Headers.TryAddWithoutValidation(h.Key, h.Value);
                            response.Dispose();
                            _log.LogInformation("attached queried artist '{Name}' to Apple search results", queryName);
                            return newResponse;
                        }
                    }
                }
                catch (Exception ex)
                {
                    _log.LogWarning(ex, "failed to post-process search response");
                }
            }
        }

        return response;
    }

    // Logs what was sent and what came back. The body is only read (buffered, so the caller can still read it)
    // for non-2xx answers, to show why the API rejected the request.
    private async Task LogResponseAsync(string mode, Uri? uri, HttpResponseMessage response, System.Diagnostics.Stopwatch watch, CancellationToken ct)
    {
        var query = uri == null ? null : HttpUtility.ParseQueryString(uri.Query);
        var summary = $"{mode} {uri?.Host}{uri?.AbsolutePath} types={query?["types"]} source={query?["source"]} " +
                      $"name/id=\"{Trunc(query?["name"] ?? query?["id"], 60)}\" hasSig={query?["s"] != null}";
        if (response.IsSuccessStatusCode)
        {
            _log.LogInformation("{Summary} -> {Status} in {Ms} ms", summary, (int)response.StatusCode, watch.ElapsedMilliseconds);
            return;
        }
        string body;
        try
        {
            await response.Content.LoadIntoBufferAsync(ct);
            body = Trunc(await response.Content.ReadAsStringAsync(ct), 300);
        }
        catch (Exception ex) { body = "(body unreadable: " + ex.Message + ")"; }
        _log.LogWarning("{Summary} -> {Status} in {Ms} ms, body: {Body}", summary, (int)response.StatusCode, watch.ElapsedMilliseconds, body);
    }

    private static string Trunc(string? v, int max) => v == null ? "" : v.Length <= max ? v : v[..max] + "...";

    private bool NeedsSigning(HttpRequestMessage request, out string input, out bool alreadySigned)
    {
        input = "";
        alreadySigned = false;
        var uri = request.RequestUri;
        if (request.Method != HttpMethod.Get || uri == null || !uri.IsAbsoluteUri ||
            !string.Equals(uri.GetLeftPart(UriPartial.Path), _api.GetLeftPart(UriPartial.Path), StringComparison.OrdinalIgnoreCase))
            return false;

        var query = HttpUtility.ParseQueryString(uri.Query);
        var source = query["source"];
        // "<source>_album" is the album search of <source>, so it is public whenever <source> is
        var baseSource = source != null && source.EndsWith("_album", StringComparison.OrdinalIgnoreCase) ? source[..^"_album".Length] : source;
        var isPublic = baseSource != null && _publicSources.Contains(baseSource);
        _log.LogInformation("api call types={Types} source={Source} -> {Decision}",
            query["types"], source, source == null ? "no source, passthrough" : isPublic ? "public source, passthrough" : "NOT in public list, will sign");
        if (source == null || isPublic) return false;

        alreadySigned = query["s"] != null; // a caller-supplied s= is kept as it is
        var type = query["types"] ?? "";
        var value = type.StartsWith("search") || type.StartsWith("embeat") ? query["name"] : query["id"];
        input = Uri.EscapeDataString(value ?? ""); // same as the site's urlEncode
        return true;
    }
}
