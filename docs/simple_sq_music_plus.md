# Simple SQ Music Plus — Technical Service Documentation

**App Name**: `simple_sq_music_plus`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Upstream Source**: [https://github.com/59799517/simple_sq_music_plus](https://github.com/59799517/simple_sq_music_plus)  
**Role Path**: `/opt/saltbox_mod/roles/simple_sq_music_plus`  

---

## 1. Overview & Architecture

Simple SQ Music Plus is a personal music management and streaming service containerized from `registry.cn-hangzhou.aliyuncs.com/sqdockler/simple_sq_music_plus`.

Within the Saltbox ecosystem:
- Designed to integrate with Traefik reverse proxy and Authelia SSO.
- Stores persistent configuration and application state in `{{ server_appdata_path }}/simple_sq_music_plus`.
- Standard architecture uses a single container deployment or a multi-container stack with MySQL backend.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `simple-sq-music-plus` | Accessible via `https://simple-sq-music-plus.<yourdomain.tld>` |
| **Internal Web Port** | `80` | Container internal HTTP web port |
| **AppData Path** | `/opt/simple_sq_music_plus` | Persistent app data mapped to `/config` |
| **Docker Image** | `registry.cn-hangzhou.aliyuncs.com/sqdockler/simple_sq_music_plus:latest` | Upstream image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To adjust port, database credentials, or custom media volumes, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit approval)*:

```yaml
### simple_sq_music_plus overrides
simple_sq_music_plus_role_web_port: "8080"

simple_sq_music_plus_role_docker_volumes_custom:
  - "/mnt/unionfs/Media/Music:/music:ro"
```

---

## 4. Deployment & Lifecycle

To deploy or update Simple SQ Music Plus:
```bash
sb install mod-simple_sq_music_plus
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags simple_sq_music_plus
```
