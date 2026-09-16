# Solara 2.0 — Technical Service Documentation

**App Name**: `solara`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Upstream Repository**: [https://github.com/akudamatata/Solara](https://github.com/akudamatata/Solara)  
**Role Path**: `/opt/saltbox_mod/roles/solara`  

---

## 1. Overview & Architecture

Solara 2.0 (光域) is a modern web music streaming player built with Apple fluid aurora aesthetics, glassmorphism, dynamic lyrics, and top chart discovery radars:
- **Dual-Engine Architecture**: Express frontend server proxies streaming audio pipelines and high-frequency read/writes, while a background Wrangler engine handles micro API requests with BoringSSL fingerprinting.
- **Dynamic Chart Radar**: Dynamically polls top charts (Trending, Hot, New Songs) with real-time deduplication.
- **Synced Lyrics & MediaSession**: Smooth scrolling lyric highlighting with auto-centering, full lock-screen media integration, and multi-bitrate audio switching (128K / 192K / 320K / FLAC lossless).
- **Persistent Storage**: Local SQLite database storing song favorites, user playlists, and playback history.

Within the Saltbox ecosystem:
- Deployed as a container on the `saltbox` Docker bridge network.
- Automated reverse proxy routing through Traefik v2 with Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `solara` | Accessible via `https://solara.<yourdomain.tld>` |
| **Internal Web Port** | `8787` | Internal standalone Node.js server port forwarded to Traefik |
| **AppData Path** | `/opt/solara` | Persistent application data (`/opt/solara/data` mapped to `/data`) |
| **Container Init** | `true` | Solves SIGTERM handling for Node/Wrangler processes |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |
| **API Base URL** | `https://music-api.gdstudio.xyz/api.php` | Default upstream music aggregation API |

---

## 3. Host Inventory Overrides

To customize API endpoints, language, or persistence in `/srv/git/saltbox/inventories/host_vars/localhost.yml`:

```yaml
### solara
solara_role_docker_envs_custom:
  API_BASE_URL: "https://music-api.gdstudio.xyz/api.php"
  # language: "ENG"
```

---

## 4. Deployment & Lifecycle

To deploy or update Solara:
```bash
sb install mod-solara
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags solara
```

To view container logs or inspect state:
```bash
docker logs -f solara
docker ps --filter "name=solara"
```
