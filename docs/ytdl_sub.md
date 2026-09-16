# YTDL-Sub — Technical Service Documentation

**App Name**: `ytdl_sub`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/ytdl_sub`  

---

## 1. Overview & Architecture

YTDL-Sub (Automated scheduled YouTube subscription scraper and downloader into Plex/Emby libraries.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `ytdl-sub` | Accessible via `https://ytdl-sub.<yourdomain.tld>` |
| **Internal Web Port** | `N/A (Cron)` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/ytdl_sub` | Persistent application data (`server_appdata_path/ytdl_sub`) |
| **Default Image** | `jmbannon/ytdl-sub` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### ytdl_sub overrides
ytdl_sub_role_docker_volumes_custom: []
ytdl_sub_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update YTDL-Sub:
```bash
sb install mod-ytdl-sub
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags ytdl-sub
```
