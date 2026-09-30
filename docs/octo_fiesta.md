# Octo-Fiesta — Technical Service Documentation

**App Name**: `octo_fiesta`
**Author**: `hereisderek`
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)
**Upstream Source**: [https://github.com/filipton/octo-fiesta](https://github.com/filipton/octo-fiesta)
**Role Path**: `/opt/saltbox_mod/roles/octo_fiesta`

---

## 1. Overview & Architecture

Octo-Fiesta is a Subsonic API proxy that sits in front of a Navidrome server. When a
requested song isn't in the local library, it transparently searches a configured
streaming provider (Deezer, Qobuz, Tidal, Yandex Music, or Apple Music via
[alacarte](https://github.com/sosjalapeno/alacarte)), downloads it into the shared music
library folder, and streams it back to the client. The file then persists as a normal,
locally-owned track — the next request for it (or Navidrome's own scan) picks it up
without ever going back out to the provider.

Point any Subsonic-compatible client (Aonsoku, Feishin, Supersonic, Navic, Substreamer,
etc.) at Octo-Fiesta's URL instead of Navidrome's directly.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `octo` | Accessible via `https://octo.<yourdomain.tld>/` |
| **Docker Network Alias** | `octo-fiesta` + `subsonic` | Reachable from other containers on the `saltbox` network as either name |
| **Internal Web Port** | `8080` | ASP.NET Kestrel listener (`ASPNETCORE_URLS`) |
| **AppData Path** | `/opt/octo-fiesta` | Persistent app data mapped to `/config` |
| **Docker Image** | `ghcr.io/filipton/octo-fiesta:dev` | Upstream image repository — no `latest` tag exists yet (no `v*` release cut) |
| **SSO Protection** | **Disabled** | Subsonic clients can't complete an Authelia browser login — same as the upstream Navidrome role |
| **Subsonic Upstream** | `http://navidrome:4533` | Internal Docker alias to the Sandbox `navidrome` role — never a public URL |

---

## 3. Host Inventory Overrides

Edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit approval)*:

```yaml
### octo_fiesta
octo_fiesta_role_web_subdomain: "octo"

# Reachable on the saltbox Docker network as "subsonic" in addition to "octo-fiesta"
octo_fiesta_role_docker_networks_alias_custom:
  - "subsonic"

# Downloaded tracks land in the Tier 1 SSD ingest path (same convention as qbittorrent/
# sabnzbd), then saltbox_sync.sh carries them up into /mnt/remote/media, from where the
# /mnt/unionfs merged view (which Navidrome scans) picks them up.
# Do NOT point this at /mnt/unionfs/... directly — see "Known Issues" below.
octo_fiesta_role_docker_volumes_custom:
  - "/mnt/local/Media/Music/library:/app/downloads:rw"

# Music provider credentials (personal secrets — not shipped in role defaults).
# This deployment supports multiple providers (Deezer, Qobuz, Tidal, Yandex, GDStudio,
# and Apple Music via alacarte).
#
# GDStudio with Apple source:
# Apple source requires request signing via the gdstudio-proxy plugin. The role
# automatically compiles roles/octo_fiesta/files/gdstudio-proxy-apple into dist/
# and deploys it to /config/gdstudio/gdstudio-proxy.dll.
octo_fiesta_role_docker_envs_custom:
  Subsonic__MusicService: "AppleMusic,GDStudio"
  AppleMusic__AlacarteUrl: "http://alacarte-apple-music:7373"
  AppleMusic__ApiToken: "<token from alacarte Settings -> octo-fiesta Integration>"
  GDStudio__Plugin: "/config/gdstudio/gdstudio-proxy.dll"
  GDSTUDIO__SOURCE: "apple"
  GDSTUDIO__TIMEOUT_SECONDS: "20"
  GDSTUDIO__DownloadPath: "/music/library/gdstudio"
  # Qobuz__UserAuthToken: ""
  # Qobuz__UserId: ""
  # Tidal__RefreshToken: ""
  # Yandex__OAuthToken: ""
  # Deezer__Arl: ""
```

`Subsonic__Url`, `Subsonic__AdminUsername`, and `Subsonic__AdminPassword` are already set
generically in the role's `defaults/main.yml` (internal Docker alias to `navidrome:4533`,
and the shared Saltbox `user.name` / `user.pass` account) — no override needed unless the
Navidrome instance or admin account differs from the Saltbox defaults.

### GDStudio & Apple Source (gdstudio-proxy plugin)

When using GDStudio with `GDSTUDIO__SOURCE: "apple"` (or other sources requiring request signing):
- **Generic Request Signing**: Sources that are not in GDStudio's public list (such as `apple`) require runtime `s=` signatures derived from the site JavaScript. The `gdstudio-proxy` plugin acts as a pure, transparent signing proxy: it appends the `s=` signature using an in-memory Jint JS engine, redirects to the site origin, and leaves response bodies and data completely untouched.
- **Relative Download URL Resolution**: Audio URLs returned by GDStudio as relative paths (e.g. `cache/apple_...m4a`) are resolved directly against the site origin (`https://music.gdstudio.xyz`) in octo-fiesta's `GDStudioDownloadService`.
- **Multilingual Artist Correlation**: Apple Music queries for non-Latin/CJK artist names (such as `周杰伦`) return Western/Romanized metadata (`Jay Chou`). Octo-fiesta's `GDStudioMetadataService` handles this by preserving the queried artist name on returned tracks, ensuring artist pages, top songs, and client search filters function seamlessly.

See the [upstream `.env.example`](https://github.com/filipton/octo-fiesta/blob/dev/.env.example)
for the full list of provider settings (`Deezer__*`, `Qobuz__*`, `Tidal__*`, `Yandex__*`,
`GDStudio__*`, `SquidWTF__*`) — Ansible env keys use `__` where dotnet config uses `:`, and each value
must be `key: "value"` (a YAML mapping entry) — `key=value` lines are silently swallowed
into an unrelated string and drop the whole `_envs_custom` dict.

---

## 4. Deployment & Lifecycle

```bash
sb install mod-octo-fiesta
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags octo-fiesta
```

### Tidal login (if using the Tidal provider)

Tidal uses OAuth instead of a static token. Run the login helper in a throwaway container
(not `docker exec` into the running one — that would fight the main process for port 8080)
so the tokens land in the token store on the same mounted `/config` volume:

```bash
docker run --rm -it --network saltbox \
  -v /opt/octo-fiesta:/config \
  ghcr.io/filipton/octo-fiesta:dev --tidal-login
```

---

## 5. Known Issues

### Never bind-mount `/mnt/unionfs/...` into this container

Bind-mounting the mergerfs/FUSE union path (`/mnt/unionfs/Media/...`) directly into
`/app/downloads` doesn't crash the container, but makes it effectively unusable at
startup: no log output, no listening socket on 8080, for as long as the library has
directories left to walk — with a large Apple Music library this is minutes to hours,
indistinguishable from a hang. Root cause confirmed by `strace`-ing the live process on
`saltbox.local` (2026-09-29):

- octo-fiesta registers a **recursive `FileSystemWatcher`** (`IncludeSubdirectories: true`)
  on `Library__DownloadPath` before the web server starts listening. .NET's Linux
  implementation of this walks the whole tree **synchronously, one directory at a time,
  single-threaded**: `lstat` → `inotify_add_watch` → `openat` → `getdents64` → `close`,
  then recurses — visible directly in the syscall trace.
- This host's `/mnt/unionfs` (`media-merged`) is a mergerfs union of 4 branches with
  `func.readdir=seq` (defined on the Proxmox host, `pve.local`, not inside this LXC):
  a local ZFS cache (RW), a local HDD (NC), and **two rclone-mounted network remotes**
  — `china` (SFTP) and `gdrive` (Google Drive, RO). `func.readdir=seq` means every
  `readdir` on the union is fanned out **sequentially across all 4 branches**, including
  both remotes.
- Most of those per-branch lookups are sub-millisecond (rclone's directory cache serves
  them), but a subset hit the network for real and take seconds — the trace caught
  individual `getdents64()` calls blocking for `5.07s` and `3.6s` apiece, mid-traversal.
- With a library holding many hundreds of artist/album subdirectories, and no bound on
  how many of those per-directory `getdents64` calls land on a cold/slow remote lookup,
  total watcher-registration time before the app ever starts listening is unbounded and,
  for a library this size, well beyond any reasonable startup wait.

This is not a permissions issue, not a mergerfs bug, and not something `--user` or a
different subfolder changes — reproduced identically down to the exact syscall pattern
regardless. It's the combination of octo-fiesta's synchronous recursive-watcher startup
design with this host's specific choice to include slow network remotes in the union
mergerfs walks sequentially.

**Fix**: mount a real, local-only filesystem (`/mnt/local/...`, or any plain ext4/ZFS
path with no FUSE/network branches involved) into `/app/downloads` instead, matching the
Tier 1 SSD ingest convention every other downloading client on this host already follows
(§3 of the top-level `AGENTS.md`). `saltbox_sync.sh` carries the files up into
`/mnt/remote/media` on its normal schedule, where the `/mnt/unionfs` merged *read* view
(which Navidrome scans) picks them up — Octo-Fiesta itself never touches the union mount.
