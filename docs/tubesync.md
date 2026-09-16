# TubeSync — Technical Service Documentation

**App Name**: `tubesync`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/tubesync`  

---

## 1. Overview & Architecture

TubeSync (Syncs YouTube channels and playlists locally into organized media directories.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `tubesync` | Accessible via `https://tubesync.<yourdomain.tld>` |
| **Internal Web Port** | `4848` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/tubesync` | Persistent application data (`server_appdata_path/tubesync`) |
| **Default Image** | `meeb/tubesync` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### tubesync overrides
tubesync_role_docker_volumes_custom: []
tubesync_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update TubeSync:
```bash
sb install mod-tubesync
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags tubesync
```
