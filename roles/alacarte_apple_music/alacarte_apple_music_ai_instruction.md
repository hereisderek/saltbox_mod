# AI Instruction Note for ALACarte (Apple Music Downloader)

**App Name**: `alacarte-apple-music` (`alacarte_apple_music`)  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Hardened Fork**: [https://github.com/hereisderek/alacarte-apple-music](https://github.com/hereisderek/alacarte-apple-music)  
**Upstream Repository**: [https://github.com/sosjalapeno/alacarte](https://github.com/sosjalapeno/alacarte)  

## Description
This role deploys ALACarte, a self-hosted Apple Music downloader with a polished web UI, ALAC-to-FLAC conversion, real-time download queueing, lyrics support (`.lrc`), duplicate prevention, and Navidrome quick-scan integration.

## Architecture
Managed as a **single unified Saltbox service** orchestrating two collaborating Docker containers over the `saltbox` bridge network:
1. **`alacarte-apple-music` (Web UI & Downloader)**: Runs Node.js 22 + React SPA + `apple-music-dl` runner on internal port `7373`. Exposes Web UI routed via Traefik.
2. **`alacarte-apple-music-wrapper` (FairPlay Decryptor Daemon)**: Runs FairPlay decryption daemon (`linux/amd64`) with an internal supervisor on port `40020` (and decryption ports `10020`, `20020`, `30020`).

## Key Highlights & Security Hardening
- **NO Docker Socket Required**: The fork eliminates the upstream `/var/run/docker.sock` requirement. The web backend communicates directly with the wrapper supervisor over HTTP port `40020`.
- **Pre-built GHCR Images**: Uses automated upstream-synced container images (`ghcr.io/hereisderek/alacarte-web:latest` and `ghcr.io/hereisderek/alacarte-wrapper:latest`).
- **Authelia SSO Integration**: Protected behind Authelia SSO by default. Can toggle `AUTH_DISABLED: "true"` in `localhost.yml` to skip the secondary internal password gate.
- **Media Volume**: Map your music library via `alacarte_apple_music_role_docker_volumes_custom` in `/srv/git/saltbox/inventories/host_vars/localhost.yml` (e.g. `/mnt/unionfs/Media/Music:/music`).
