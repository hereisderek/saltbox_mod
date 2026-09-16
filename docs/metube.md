# MeTube — Technical Service Documentation

**App Name**: `metube`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/metube`  

---

## 1. Overview & Architecture

MeTube (Web GUI for youtube-dl and yt-dlp with playlist support and audio extraction.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `metube` | Accessible via `https://metube.<yourdomain.tld>` |
| **Internal Web Port** | `8081` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/metube` | Persistent application data (`server_appdata_path/metube`) |
| **Default Image** | `alexta69/metube` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### metube overrides
metube_role_docker_volumes_custom: []
metube_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update MeTube:
```bash
sb install mod-metube
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags metube
```
