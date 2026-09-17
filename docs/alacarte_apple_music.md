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

ALACarte is a self-hosted Apple Music downloader with a modern web UI, lossless ALAC-to-FLAC conversion, real-time download queueing, lyrics fetching (`.lrc` sidecars), duplicate prevention, and Navidrome quick-scan integration.

In `saltbox_mod`, it is orchestrated as a **single unified Saltbox service** managing two collaborating containers on the `saltbox` Docker bridge network:

```
                  ┌──────────────────────────────────────────────┐
                  │                 Traefik v2                   │
                  │  https://alacarte-apple-music.<yourdomain>   │
                  │       (Authelia SSO Middleware)              │
                  └──────────────────────┬───────────────────────┘
                                         │ Internal HTTP (Port 7373)
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │      alacarte-apple-music (Web & Amdp)       │
                  │        ghcr.io/hereisderek/alacarte-web      │
                  │  - React Web UI + Node.js 22 Backend         │
                  │  - apple-music-dl binary + MP4Box + FLAC     │
                  │  - Volumes: /config, /wrapper-data, /music   │
                  │  - ZERO /var/run/docker.sock exposure!       │
                  └──────────────┬───────────────────────────────┘
                                 │ Internal HTTP Supervisor (40020)
                                 │ DRM Decryption TCP (10020, 20020, 30020)
                                 ▼
                  ┌──────────────────────────────────────────────┐
                  │   alacarte-apple-music-wrapper (FairPlay)    │
                  │      ghcr.io/hereisderek/alacarte-wrapper    │
                  │  - FairPlay DRM Decryption daemon (chroot)   │
                  │  - Built-in process supervisor (port 40020)  │
                  │  - Devices: /dev/null, urandom, random, zero │
                  │  - Volumes: /app/rootfs/data                 │
                  └──────────────────────────────────────────────┘
```

### Security & Hardening: Elimination of Docker Socket
Upstream `sosjalapeno/alacarte` mounts `/var/run/docker.sock` to stop and spin up temporary containers on the host during Apple ID logins. This fork eliminates the docker socket entirely:
- The wrapper container runs an internal process supervisor on port `40020`.
- The web container interacts with the supervisor via direct HTTP calls to orchestrate login and restart the daemon inside its own container boundary.
- Containers run fully unprivileged with no host Docker engine access.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `alacarte-apple-music` | Accessible via `https://alacarte-apple-music.<yourdomain.tld>` |
| **Internal Web Port** | `7373` | Internal web container port forwarded to Traefik |
| **Wrapper Ports** | `10020`, `20020`, `30020`, `40020` | Decryption, M3U8, account token, and supervisor ports |
| **AppData Path** | `/opt/alacarte-apple-music` | Root application data directory (`{{ server_appdata_path }}/alacarte-apple-music`) |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |
| **Web Image** | `ghcr.io/hereisderek/alacarte-web:latest` | Automated multi-stage build from the hardened fork |
| **Wrapper Image** | `ghcr.io/hereisderek/alacarte-wrapper:latest` | Automated build with login supervisor (`linux/amd64`) |

---

## 3. Host Inventory Overrides

To customize variables (e.g. mapping your media library or disabling internal auth behind Authelia), add overrides in `/srv/git/saltbox/inventories/host_vars/localhost.yml`:

```yaml
### alacarte_apple_music
alacarte_apple_music_role_web_subdomain: "alacarte"
alacarte_apple_music_role_paths_folders_list_custom:
  - "{{ app_cache_dir }}/staging"
alacarte_apple_music_role_docker_volumes_custom:
  - "/mnt/unionfs/Media/Music/library:/music:rw"
  - "{{ app_cache_dir }}/staging:/tmp/alacarte-staging"
alacarte_apple_music_role_docker_envs_custom:
  AUTH_DISABLED: "true" # Skip secondary login behind Authelia SSO
```

---

## 4. Deployment & Lifecycle

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
1. Open `https://alacarte-apple-music.<yourdomain.tld>`.
2. If `AUTH_DISABLED: false` (default), retrieve the initial setup token from container logs:
   ```bash
   docker logs alacarte-apple-music | grep -i "setup token"
   ```
   Enter the token and create your local admin account.
3. In the UI, navigate to **Settings → Apple Account**.
4. Enter your Apple ID email and password (with an active Apple Music subscription) and your storefront region.
5. If prompted for 2FA, enter the 6-digit verification code within 2 minutes.
6. Once the status shows **Ready**, search and download music directly to your library!

### Inspection & Debugging
```bash
# View web logs
docker logs -f alacarte-apple-music

# View wrapper logs
docker logs -f alacarte-apple-music-wrapper

# Verify container status
docker ps --filter "name=alacarte-apple-music"
```
