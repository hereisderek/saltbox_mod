# YouTube-DL Material — Technical Service Documentation

**App Name**: `youtubedl`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/youtubedl`  

---

## 1. Overview & Architecture

YouTube-DL Material (Material Design frontend for YouTube-DL with MongoDB backend.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `youtubedl` | Accessible via `https://youtubedl.<yourdomain.tld>` |
| **Internal Web Port** | `17442` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/youtubedl` | Persistent application data (`server_appdata_path/youtubedl`) |
| **Default Image** | `tzahi12345/youtubedl-material` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### youtubedl overrides
youtubedl_role_docker_volumes_custom: []
youtubedl_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update YouTube-DL Material:
```bash
sb install mod-youtubedl
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags youtubedl
```
