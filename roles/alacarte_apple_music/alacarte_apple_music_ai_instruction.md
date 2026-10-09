# AI Instruction Note for ALACarte (Apple Music Downloader)

**App Name**: `alacarte-apple-music` (`alacarte_apple_music`)  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Hardened Fork**: [https://github.com/hereisderek/alacarte-apple-music](https://github.com/hereisderek/alacarte-apple-music)  
**Upstream Repository**: [https://github.com/sosjalapeno/alacarte](https://github.com/sosjalapeno/alacarte)  

## Description
This role deploys ALACarte, a self-hosted Apple Music downloader with a polished web UI, ALAC-to-FLAC conversion, real-time download queueing, lyrics support (`.lrc`), duplicate prevention, Navidrome quick-scan integration, and a dedicated batch track/playlist import service.

## Architecture
Managed as a **single unified Saltbox service** orchestrating three collaborating Docker containers over the `saltbox` bridge network:
1. **`alacarte-apple-music` (Web UI & Downloader)**: Runs Node.js 22 + React SPA + `apple-music-dl` runner on internal port `7373`. Exposes Web UI routed via Traefik at `https://alacarte.<domain>/`.
2. **`alacarte-apple-music-wrapper` (FairPlay Decryptor Daemon)**: Runs FairPlay decryption daemon (`linux/amd64`) with an internal supervisor on port `40020` (and decryption ports `10020`, `20020`, `30020`).
3. **`alacarte-apple-music-importer` (Batch Importer Service)**: Runs batch track/playlist import service on internal port `8080`, mounted under `BASE_PATH: /import`. Routed via Traefik at `https://alacarte.<domain>/import`. Talks to `web` via `/api/internal/*` using shared `INTERNAL_API_KEY`.

## Key Highlights & Security Hardening
- **NO Docker Socket Required**: The fork eliminates the upstream `/var/run/docker.sock` requirement. The web backend communicates directly with the wrapper supervisor over HTTP port `40020`.
- **Pre-built GHCR Images**: Uses automated upstream-synced container images:
  - `ghcr.io/hereisderek/alacarte-web:latest`
  - `ghcr.io/hereisderek/alacarte-wrapper:latest`
  - `ghcr.io/hereisderek/alacarte-importer:latest`
- **Unified Traefik Subdomain Routing**:
  - Web UI: `https://<subdomain>.<domain>/`
  - Importer: `https://<subdomain>.<domain>/import`
- **Authelia SSO & Access Control**:
  - Web portal protected behind Authelia SSO by default. Can set `AUTH_DISABLED: "true"` in `localhost.yml` to skip secondary in-app auth.
  - Importer creation is gated by `alacarte_apple_music_role_importer_enabled` (default `false`). Set to `true` in `localhost.yml` to enable.
  - Importer SSO is gated by `alacarte_apple_music_role_importer_sso_enabled` (default `true`). Set to `false` in `localhost.yml` to make the `/import` page publicly accessible while keeping the main web UI private behind Authelia.
- **Unblocked Internal Inter-Container Communication**:
  - `importer` communicates directly with `web` over the private Docker network (`http://alacarte-apple-music:7373`) using `INTERNAL_API_KEY` header `x-internal-key`, bypassing Traefik/Authelia.
  - `web` communicates directly with `wrapper` over the private Docker network (`http://alacarte-apple-music-wrapper:40020`).
- **Apple API 429 & IPv6 Flags (Both Default to `false`)**:
  - Apple's edge CDN aggressively blocks/rate-limits residential IPv4 blocks (`42900 Request is forbidden`).
  - Two distinct flags are supported in `localhost.yml` (both default to `false` if absent):
    1. Global `docker_ipv6: false`: controls IPv6 enablement on the `saltbox` Docker network bridge.
    2. Role-specific `alacarte_apple_music_role_ipv6_enabled: false`: when set to `true`, injects `NODE_OPTIONS: "--dns-result-order=ipv6first"` into `web` and `importer` containers to prioritize IPv6 for Apple API requests.
    3. If role IPv6 is enabled while `saltbox` network lacks IPv6, Ansible emits a warning to enable `docker_ipv6: true`.
- **Custom Overrides**:
  - Override parser user agents (`IMPORTER_USER_AGENT`, `SPOTIFY_USER_AGENT`, `KKBOX_USER_AGENT`, etc.) and search pacing via `alacarte_apple_music_role_importer_envs_custom` in `localhost.yml`.
  - Sample disabled Traefik dynamic file config available at `/opt/traefik/alacarte-apple-music.yml.bak`.
