# AI Instruction Note for Solara

**App Name**: `solara`  
**Author**: `hereisderek`  
**Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Source Repo**: [https://github.com/akudamatata/Solara](https://github.com/akudamatata/Solara)  

## Description
This role sets up Solara 2.0, a sleek modern web music player designed with Apple fluid aurora aesthetics, dynamic lyric synchronization, chart radars, and dual-engine architecture (Express + Wrangler API proxy).

## Key Configurations
1. **Web Port**: Container listens internally on port `8787`.
2. **Subdomain**: Routes automatically under `solara.<yourdomain.tld>` via Traefik.
3. **Authentication**: Secured behind Authelia SSO via `traefik_default_sso_middleware`.
4. **Data Persistence**: Stores SQLite database (favorites, playlists, playback records) under `/data` (mapped to `{{ server_appdata_path }}/solara/data`).
5. **Container Init**: Uses `solara_role_docker_init: true` for proper SIGTERM signal handling and graceful shutdown.
