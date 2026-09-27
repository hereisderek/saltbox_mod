# ALACarte (Apple Music Downloader) — Technical Service Documentation

**App Name**: `alacarte-apple-music`  
**Ansible Role Name**: `alacarte_apple_music`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Hardened Fork Repository**: [https://github.com/hereisderek/alacarte-apple-music](https://github.com/hereisderek/alacarte-apple-music)  
**Upstream Repository**: [https://github.com/sosjalapeno/alacarte](https://github.com/sosjalapeno/alacarte)  
**Role Path**: `/opt/saltbox_mod/roles/alacarte_apple_music`  

---

## 1. Overview & Architecture

ALACarte is a self-hosted Apple Music downloader with a modern web UI, lossless ALAC-to-FLAC conversion, real-time download queueing, lyrics fetching (`.lrc` sidecars), duplicate prevention, Navidrome quick-scan integration, and a dedicated batch track/playlist import service.

In `saltbox_mod`, it is orchestrated as a **single unified Saltbox service** managing three collaborating containers on the `saltbox` Docker bridge network:

```
                            ┌──────────────────────────────────────────────┐
                            │                 Traefik v2                   │
                            │           https://alacarte.<domain>          │
                            └──────────────────────┬───────────────────────┘
                                                   │
                   ┌───────────────────────────────┴───────────────────────────────┐
                   │ PathPrefix(`/import`)                         Default / Other │
                   │ (Authelia SSO: enabled by default)            (Authelia SSO)  │
                   ▼                                                               ▼
┌──────────────────────────────────────┐                       ┌──────────────────────────────────────┐
│     alacarte-apple-music-importer    │                       │       alacarte-apple-music (Web)     │
│   ghcr.io/hereisderek/alacarte-      │  HTTP /api/internal/  │   ghcr.io/hereisderek/alacarte-web   │
│              importer                │──────────────────────▶│  - Port: 7373                        │
│  - Port: 8080                        │  (INTERNAL_API_KEY)   │  - Zero docker.sock                  │
│  - BASE_PATH: /import                │                       └──────────────────┬───────────────────┘
│  - AUTH_ENABLED: false               │                                          │
└──────────────────────────────────────┘                                          │ HTTP 40020 (Supervisor)
                                                                                  │ TCP 10020/20020/30020
                                                                                  ▼
                                                               ┌──────────────────────────────────────┐
                                                               │     alacarte-apple-music-wrapper     │
                                                               │ ghcr.io/hereisderek/alacarte-wrapper │
                                                               │  - FairPlay DRM daemon               │
                                                               └──────────────────────────────────────┘
```

### Unblocked Inter-Container Communication
All three containers reside on the shared internal Docker network (`saltbox`):
- **Web ↔ Wrapper**: The web container connects directly to `alacarte-apple-music-wrapper` via internal ports `40020` (supervisor HTTP) and `10020`/`20020`/`30020` (FairPlay DRM). No `/var/run/docker.sock` is required.
- **Importer ↔ Web**: The importer calls `/api/internal/*` on the web backend directly over the private Docker network (`http://alacarte-apple-music:7373`) using the shared `INTERNAL_API_KEY` (`x-internal-key` header). This communication never touches Traefik or the public internet, so it is never blocked by Authelia or reverse-proxy authentication walls.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `alacarte-apple-music` | Main hostname (`https://<subdomain>.<domain>`) |
| **Internal Web Port** | `7373` | Internal web container port routed to `/` |
| **Internal Importer Port** | `8080` | Internal importer container port routed to `/import` |
| **Wrapper Ports** | `10020`, `20020`, `30020`, `40020` | Decryption, M3U8, account token, and supervisor ports |
| **AppData Path** | `/opt/alacarte-apple-music` | Root application data directory (`{{ server_appdata_path }}/alacarte-apple-music`) |
| **SSO Protection (Web)** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |
| **SSO Protection (Importer)** | Enabled | Defaults to Authelia; can be set to `""` in `localhost.yml` to make `/import` public |
| **Web Image** | `ghcr.io/hereisderek/alacarte-web:latest` | Automated multi-stage build from the hardened fork |
| **Wrapper Image** | `ghcr.io/hereisderek/alacarte-wrapper:latest` | Automated build with login supervisor (`linux/amd64`) |
| **Importer Image** | `ghcr.io/hereisderek/alacarte-importer:latest` | Batch track and playlist import service |

---

## 3. Host Inventory Overrides (`localhost.yml`)

All user-specific configurations belong in `/srv/git/saltbox/inventories/host_vars/localhost.yml`:

```yaml
### alacarte_apple_music
alacarte_apple_music_role_web_subdomain: "alacarte"

# Staging cache and media library mounts
alacarte_apple_music_role_paths_folders_list_custom:
  - "{{ app_cache_dir }}/staging"
  - "{{ server_local_folder_path }}/Media/Music/library/apple"
  - "/mnt/unionfs/Media/Music/library/apple"

alacarte_apple_music_role_docker_volumes_custom:
  - "/mnt/unionfs/Media/Music/library/apple:/music:rw"
  - "{{ app_cache_dir }}/staging:/tmp/alacarte-staging"

# Web container environment overrides
alacarte_apple_music_role_docker_envs_custom:
  AUTH_DISABLED: "true" # Bypass secondary web password behind Authelia
  AMDL_MUSIC_PATH: "/music"

# Enable importer container (default is false)
alacarte_apple_music_role_importer_enabled: true

# Importer Authelia SSO wall flag:
# Defaults to true (behind Authelia). Set to false to make /import publicly accessible while / remains protected by Authelia.
alacarte_apple_music_role_importer_sso_enabled: false

# Importer environment variable overrides (e.g. User-Agents or rate limit pacing)
alacarte_apple_music_role_importer_envs_custom:
  IMPORTER_USER_AGENT: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  SPOTIFY_USER_AGENT: ""
  KKBOX_USER_AGENT: ""
  IMPORTER_SEARCH_PACING_MS: "500"
```

---

## 4. Traefik Routing Configuration

### Docker Provider (Default)
Traefik labels are assigned automatically:
1. **Web UI Router**:
   - Rule: `Host("alacarte.<domain>")`
   - Target: `alacarte-apple-music:7373`
   - Middlewares: `secureHeaders@file`, Authelia SSO (`authelia@docker`)
2. **Importer Router**:
   - Rule: `Host("alacarte.<domain>") && PathPrefix("/import")`
   - Target: `alacarte-apple-music-importer:8080`
   - Middlewares: Configurable independently via `alacarte_apple_music_role_importer_traefik_sso_middleware`
   - Traefik automatically gives this router higher priority due to the longer rule path.

### Dynamic File Provider Sample (`/opt/traefik/alacarte-apple-music.yml.bak`)
A disabled reference template is deployed to `/opt/traefik/alacarte-apple-music.yml.bak`. Because of the `.bak` extension, Traefik ignores it by default. If you prefer file-based routing over Docker labels:
1. Copy or rename the file:
   ```bash
   sudo cp /opt/traefik/alacarte-apple-music.yml.bak /opt/traefik/alacarte-apple-music.yml
   ```
2. Disable Docker labels by setting `alacarte_apple_music_role_traefik_enabled: false` and `alacarte_apple_music_role_importer_traefik_enabled: false` in `localhost.yml`.

---

## 5. Deployment & Lifecycle

### Installation
Deploy using the `sb` CLI:
```bash
sb install mod-alacarte-apple-music
```
Or directly with Ansible:
```bash
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags alacarte-apple-music
```

### First-Time Apple Login Flow
1. Open `https://alacarte.<yourdomain.tld>`.
2. If `AUTH_DISABLED: false` (default), retrieve the initial setup token from container logs:
   ```bash
   docker logs alacarte-apple-music | grep -i "setup token"
   ```
   Enter the token and create your local admin account.
3. In the UI, navigate to **Settings → Apple Account**.
4. Enter your Apple ID email and password (with an active Apple Music subscription) and your storefront region.
5. If prompted for 2FA, enter the 6-digit verification code within 2 minutes.
6. Once the status shows **Ready**, search and download music directly to your library!

### Using the Batch Importer
1. Navigate to `https://alacarte.<yourdomain.tld>/import`.
2. Paste plain-text song lists (`Title - Artist`) or supported playlist links (Spotify, KKBOX, Qishui, etc.).
3. The importer matches tracks against the Apple Music catalog and enqueues downloads directly to the main ALACarte backend.

### Inspection & Debugging
```bash
# View web logs
docker logs -f alacarte-apple-music

# View wrapper logs
docker logs -f alacarte-apple-music-wrapper

# View importer logs
docker logs -f alacarte-apple-music-importer

# Verify container status
docker ps --filter "name=alacarte-apple-music"
```
