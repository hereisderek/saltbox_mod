# DDNS Updater — Technical Service Documentation

**App Name**: `ddns_updater`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/ddns_updater`  

---

## 1. Overview & Architecture

DDNS Updater (Lightweight container to update multiple dynamic DNS records from multiple providers.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `ddns-updater` | Accessible via `https://ddns-updater.<yourdomain.tld>` |
| **Internal Web Port** | `8000` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/ddns_updater` | Persistent application data (`server_appdata_path/ddns_updater`) |
| **Default Image** | `qmcgaw/ddns-updater` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### ddns_updater overrides
ddns_updater_role_docker_volumes_custom: []
ddns_updater_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update DDNS Updater:
```bash
sb install mod-ddns-updater
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags ddns-updater
```
