# GD Studio Music API: `s=` signature

Findings from reverse-engineering https://music.gdstudio.xyz/ (client JS as of `mkPlayer.version` 2026.09.25).
The public API doc (https://music-api.gdstudio.xyz/api.php) does not mention `s=`.

**Status: verified working (2026-09-29)** from Node, from C# and end to end inside octo-fiesta. Signed `types=search&source=apple` returns 200 with results; a wrong `s=` returns 401.

Two ways to produce the signature, both verified to give identical output for the same server time:

1. **Run the site's own script** (preferred: survives algorithm changes), see [Running the site's script](#running-the-sites-script).
2. **Re-implement it** with the modified MD5 below (fallback).

## Endpoints

| Host | `s=` checked? | `source=apple` |
|------|---------------|----------------|
| `https://music.gdstudio.xyz/api.php` | **Yes**, missing or wrong gives `401 {"detail":"Invalid request."}` | Supported |
| `https://music-api.gdstudio.xyz/api.php` | No (ignored) | **Not supported**, gives `400 "Value of source is not supported."` |

Use `music.gdstudio.xyz/api.php` for Apple. No cookies, Referer or special headers are needed.

The root of the API host redirects to the site (`GET https://music-api.gdstudio.xyz/` gives `301 Location: https://music.gdstudio.xyz`; `/api.php` on it does not redirect). So the site host can be discovered from the API host, which is what the octo-fiesta plugin does. The site's front-end calls the relative URL `api.php`, so the API path is the same on both hosts.

## Where it comes from

- `js/ajax.js` appends `&s=` + `crc32(...)` to every API call, e.g. for search: `d = urlEncode(rem.wd)` then `"...&name=" + d + "&s=" + crc32(String(d))`.
- `js/crc32.min.js` (jsjiami-obfuscated, about 56 KB, linked from the site's index page as `js/crc32.min.js?v=<date>`) defines `crc32()` and its own `md5()`. Despite the name it is **not CRC32**; it is a wrapper around a **modified MD5**.
- `js/player.js` holds `mkPlayer={api:"api.php",...,version:"2026.09.25",...}`, the source of `ver` below.
- `GET /time` on the site returns the server's Unix time in seconds (plain text, e.g. `1790654916`).

## Algorithm

```js
s = md5x( timeBucket + "|" + hostname + "|" + ver + "|" + input )
      .slice(-8).toUpperCase()
```

| Part | Value |
|------|-------|
| `timeBucket` | `String(unixSeconds).slice(0, 9)`, i.e. a 10-second bucket. `unixSeconds` comes from `_0xgt_impl()`, which does a **synchronous `XMLHttpRequest` GET `/time`** (server time) and reads `responseText`. In practice it equals the local clock to within a second or two; if the request fails the script falls back to `Date.now()` (milliseconds; the first 9 digits are the same). |
| `hostname` | `location.hostname`, i.e. `music.gdstudio.xyz` |
| `ver` | `mkPlayer.version` (`"2026.09.25"`) with each dot-part zero-padded to 2 digits, joined: `20260925`. Changes when the site JS is updated. |
| `input` | The value sent in the request (see below) |
| `md5x` | **MD5 with one altered round constant**, see next section |

### The MD5 twist

The site's `md5` is standard MD5 except **`K[29] = 0xfcfea3f8`** (standard is `0xfcefa3f8`, transposed digits).
Standard MD5 gives wrong signatures and 401s. Oracle values from the site's own `md5`:

```
md5x("")    = c4e06cfe8f2923edbb6f2a04b7215560   (std: d41d8cd98f00b204e9800998ecf8427e)
md5x("abc") = 9ef90af686e68195b6f6d89b69d3c584   (std: 900150983cd24fb0d6963f7d28e17f72)
md5x("179065411|music.gdstudio.xyz|20260925|hello") = 6260605d66c5c014a1714a5a4e03908e
```

If this stops working, re-diff the constants in `js/crc32.min.js` against the standard table (init vector, shifts and `K[i] = floor(abs(sin(i+1)) * 2^32)`); the twist may move.

### `input` per request type

| `types=` | `input` |
|----------|---------|
| `search`, `search_album`, `search_playlist` | `urlEncode(name)` (verified live for `search`) |
| `url` | `urlEncode(id)` |
| `pic` | `urlEncode(pic_id)` |
| `lyric` | `urlEncode(lyric_id)` |
| `playlist`, `userlist` | `urlEncode(id)` |
| `embeat_*` | `urlEncode(...)` of the payload (from code; not verified live) |

`urlEncode` = `encodeURIComponent` plus escaping `( ) * ' !` (`%28 %29 %2A %27 %21`), which leaves only `A-Za-z0-9 - _ . ~` unescaped: identical to C#'s `Uri.EscapeDataString`. The sign input is the encoded string, not the raw one (identical for plain ASCII like `hello`).

The value is taken from the request: `name` for `search*`/`embeat*` types, `id` for the rest (the `pic_id`/`lyric_id` mentioned above are passed as `id=`).

Request shapes:

```
types=search&count=20&source=apple&pages=1&name=<name>&s=<sig>
types=url&id=<appleTrackId>&source=apple&br=<br>&s=<sig>
```

## Running the site's script

`crc32.min.js` can be executed outside a browser (Node `vm`, or Jint in C#), so the signature keeps working when the site changes the algorithm, constants or version. Steps:

1. `GET https://music-api.gdstudio.xyz/`, follow the redirect, note the final host (`hostname`).
2. From the returned HTML take the `<script src>` URLs for `player.js` (read `version:"..."`) and `crc32.min.js`.
3. Create a JS engine with these globals, then run the script and call the global `crc32(input)`:

```js
var window = globalThis; window.window = window;
var location = { hostname: "<site host>" }; window.location = location;
var mkPlayer = { version: "<version from player.js>" };
var navigator = {}; var document = {};
function setTimeout() { return 0; } function clearTimeout() {}
function XMLHttpRequest() {}
XMLHttpRequest.prototype.open = function () {};
XMLHttpRequest.prototype.setRequestHeader = function () {};
XMLHttpRequest.prototype.getResponseHeader = function () { return null; };
XMLHttpRequest.prototype.send = function () {
  this.status = 200; this.readyState = 4;
  this.responseText = this.response = __now();   // host function: current server Unix seconds as a string
};
```

Notes:

- `mkPlayer` must be defined before running the script; without it `crc32` takes a decoy branch and returns nothing useful.
- The XHR is synchronous, so fetch `/time` beforehand (or keep an offset) and return it from the stub. Calling `/time` per signature is unnecessary: cache the server time and advance it with the local clock (300 s worked fine in octo-fiesta).
- Call `crc32("x")` once after loading to fail early if the script has changed in a way the stubs don't cover.
- The engine is not thread-safe; serialize calls.
- Set a time limit on the engine (5 s used) as the script is obfuscated third-party code.
- In the Node `vm` test `setTimeout` also had to be provided; without it `_0xgt_impl` throws `setTimeout is not defined`.

Verified: for the same server time the script output equals the reference implementation below (e.g. `crc32("hello")` = `11C6FD68` in C#/Jint and `hardSign` in Node at server time 1790656080..1790656082).

## Reference implementation (fallback)

```js
const HOST = "music.gdstudio.xyz";
const VER = "2026.09.25"; // mkPlayer.version

const K = [...Array(64)].map((_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32) >>> 0);
K[29] = 0xfcfea3f8; // the twist: standard is 0xfcefa3f8
const S = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
const rol = (x, n) => (x << n) | (x >>> (32 - n));

export function md5x(str) {
  const b = Buffer.from(str, "utf8"), len = b.length;
  const n = ((len + 8) >> 6) + 1, w = new Array(n * 16).fill(0);
  for (let i = 0; i < len; i++) w[i >> 2] |= b[i] << ((i % 4) * 8);
  w[len >> 2] |= 0x80 << ((len % 4) * 8);
  w[n * 16 - 2] = len * 8;
  let a0 = 0x67452301, b0 = 0xefcdab89 | 0, c0 = 0x98badcfe | 0, d0 = 0x10325476;
  for (let o = 0; o < w.length; o += 16) {
    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) {
      let F, g;
      if (i < 16) { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
      else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      const t = D; D = C; C = B;
      B = (B + rol((A + F + K[i] + w[o + g]) | 0, S[(i >> 4) * 4 + (i % 4)])) | 0;
      A = t;
    }
    a0 = (a0 + A) | 0; b0 = (b0 + B) | 0; c0 = (c0 + C) | 0; d0 = (d0 + D) | 0;
  }
  return [a0, b0, c0, d0]
    .map(v => Buffer.from([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >>> 24) & 255]).toString("hex"))
    .join("");
}

const urlEncode = s => encodeURIComponent(s).replace(/[()*'!]/g, c => "%" + c.charCodeAt(0).toString(16).toUpperCase());

export function sign(input) {
  const t = String(Math.floor(Date.now() / 1000)).slice(0, 9);
  const ver = VER.split(".").map(p => p.padStart(2, "0")).join("");
  return md5x(`${t}|${HOST}|${ver}|${urlEncode(input)}`).slice(-8).toUpperCase();
}

// const name = "hello";
// fetch(`https://${HOST}/api.php?types=search&count=2&source=apple&pages=1&name=${urlEncode(name)}&s=${sign(name)}`)
```

## Behaviour of the public host

`music-api.gdstudio.xyz` does not check `s=`: `source=netease` works with a bad or missing signature there. On `music.gdstudio.xyz` the signature is required for every source (even `netease` gets 401 without it), so only route to the site host when a source is not served openly.

## Integration in octo-fiesta

octo-fiesta itself only has a neutral hook (`GDStudioHandlerPlugin`): if `/config/gdstudio-proxy.dll` exists (path override `GDStudio__Plugin`), every public `DelegatingHandler` in it is added to the GDStudio HTTP client. Nothing about signing is in the octo-fiesta source or docs.

The plugin (`apple/`, built with `apple/build.sh` into `apple/dist/`: `gdstudio-proxy.dll`, `Jint.dll`, `Acornima.dll`, all three go into `/config`) is a C# class library:

- Requests to the GDStudio API whose `source` is not in `GDStudio__PublicSources` (default `netease,joox,bilibili`) are re-sent to the site host with `&s=` appended. All other parameters stay untouched; a caller-supplied `s=` is kept; everything else (downloads, public sources) passes through.
- The signer runs the site's script in Jint (steps above), caches it and reloads it once when upstream answers 401; server `/time` is cached for 300 s and advanced with the local clock.
- If the script can't be loaded or run, the built-in modified MD5 is used, with the host and version taken from the site (defaults: `music.gdstudio.xyz`, `2026.09.25`).
- It reads `GDStudio__Api`, `GDStudio__Proxy` (used for the plugin's own requests) and `GDStudio__PublicSources`.
- Loaded assemblies: dependencies are resolved next to the plugin, except ones the host already has, to keep type identity.

Verified by running octo-fiesta with `GDStudio__Source=apple`: with the plugin in place startup validation logged `signing via https://music.gdstudio.xyz (... site script)` and passed; without it, the same setup failed.

## Verification log (2026-09-29)

- `search`, `source=apple`, `name=hello`, signed: 200, first hit `Hello (Single Edit)` (id `551901361`).
- Same request with `s=DEADBEEF` or no `s`: 401.
- `types=url&id=551901361&source=apple&br=320`, signed: 200 but `{"url":"","br":-1,"size":0}`. The signature is accepted, but no stream URL came back; other `br` values or tracks are untested.
- `source=apple` on `music-api.gdstudio.xyz`: 400 `{"detail":"Value of source is not supported."}` regardless of `s=`.
- Site script run in Node `vm` and in Jint: output matches the reference implementation for the same server time.
- A plain-standard-MD5 implementation of the formula gave wrong signatures (401 on every request); the altered `K[29]` was found by diffing the round constants extracted from `crc32.min.js` against the standard table, and confirmed against the site's own `md5("")`, `md5("abc")`.
- Not tested: the 401 reload path (no way found to make upstream return 401 for a valid signature), adjacent time buckets.

## Open questions

- Whether the server accepts adjacent time buckets (clock skew tolerance); only the current bucket was tested.
- `VER`, the MD5 twist and the stubs the script needs are moving targets: re-read `mkPlayer.version` and `js/crc32.min.js` if requests start returning 401.
- Why `types=url` for Apple returned an empty URL.
- Rate limit per the API doc: 50 requests / 5 minutes.
