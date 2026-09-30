# AI Instruction Note for Octo-Fiesta

**App Name**: `octo-fiesta` (`octo_fiesta`)
**Author**: `hereisderek`
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)
**Upstream Repository**: [https://github.com/filipton/octo-fiesta](https://github.com/filipton/octo-fiesta)

## Description
Octo-Fiesta is a Subsonic API proxy server that sits in front of Navidrome. When a client
requests a song that isn't in the local library, it transparently fetches it from a
configured streaming provider (Deezer, Qobuz, Tidal, Yandex, or Apple Music via alacarte),
downloads it into the shared music library, and streams it back - the track is then a
permanent, locally-owned part of the library.

## Architecture
Single container, `.NET 9` / ASP.NET, listening internally on port `8080` (`octo_fiesta_role_web_port`).
- Traefik subdomain: `https://<octo_fiesta_role_web_subdomain>.<domain>/` (defaults to `octo`
  in `localhost.yml`, since it's the client-facing endpoint clients point their Subsonic app at).
- Docker network alias: also reachable on the `saltbox` network as `subsonic` (via
  `octo_fiesta_role_docker_networks_alias_custom` in `localhost.yml`), in addition to its
  container name `octo-fiesta`.
- Talks to Navidrome (`Subsonic__Url`) over the internal Docker network using Navidrome's own
  network alias `navidrome:4533` - never over the public URL. Configured in
  `octo_fiesta_role_subsonic_url` (defaults/main.yml), built from
  `octo_fiesta_role_subsonic_container` / `octo_fiesta_role_subsonic_port` so it can be
  repointed if the Navidrome instance name ever changes.
- `Subsonic__AdminUsername` / `Subsonic__AdminPassword` default to the shared Saltbox
  `user.name` / `user.pass` account (must be a real Navidrome admin account with that
  username/password for admin-gated actions like triggering library scans).

## Authelia SSO
Deliberately **off** (`octo_fiesta_role_traefik_sso_middleware: ""`), matching the upstream
Sandbox `navidrome` role. Subsonic clients authenticate via the Subsonic API's own
salt/token or basic-auth scheme, which cannot complete an interactive Authelia login
redirect - enabling SSO here would lock out every Subsonic client.

## Music Provider Credentials
`Subsonic__MusicService` defaults to `Deezer`, but no provider credentials (Deezer ARL,
Qobuz token/ID, Tidal OAuth, Yandex OAuth) are set by default - these are personal secrets
the user must supply themselves via `octo_fiesta_role_docker_envs_custom` in `localhost.yml`.
See the upstream `.env.example` for the full list of `Subsonic__*` / `Deezer__*` / `Qobuz__*`
/ `Tidal__*` / `Yandex__*` settings and how they map to environment variables (Ansible env
keys use `__` in place of dotnet's `:` config-section separator).

## Volumes
- `/config`: role's own appdata dir (`octo_fiesta_role_paths_location`), generic default.
- `/app/downloads`: **not** mapped by default (kept out of role defaults per the
  "no host media paths in role defaults" rule) - mapped in `localhost.yml` via
  `octo_fiesta_role_docker_volumes_custom` into the Tier 1 SSD ingest path
  (`/mnt/local/Media/Music/library`), same convention as qbittorrent/sabnzbd. `saltbox_sync.sh`
  carries files up to `/mnt/remote/media`, where the `/mnt/unionfs` merged view (which
  Navidrome scans) picks them up.

  **Do not** mount `/mnt/unionfs/...` directly into `/app/downloads` - confirmed (not just
  suspected) root cause via `strace`: octo-fiesta registers a recursive
  `FileSystemWatcher` on the downloads path before the web server starts, and .NET's
  Linux implementation walks the whole tree synchronously, one directory at a time,
  single-threaded (`lstat`/`inotify_add_watch`/`openat`/`getdents64`/`close` per dir).
  `/mnt/unionfs` is a mergerfs union (`func.readdir=seq`, configured on the Proxmox host
  `pve.local`) that includes two rclone network remotes (`china` SFTP, `gdrive` Google
  Drive RO) - every `readdir` fans out sequentially across all branches including both
  remotes, and some of those calls genuinely block for seconds (`getdents64` caught at
  5.07s and 3.6s in the trace). Across a library with hundreds of subdirectories that adds
  up to minutes-to-hours before the app ever starts listening - not a true hang/deadlock,
  just unusably slow, and non-deterministic (depends how many directories land on a cold
  remote lookup). Independent of `--user`, and identical for any subfolder tested, not
  just the full library root. See "Known Issues" in `docs/octo_fiesta.md` for the full
  writeup, including the exact strace evidence.
