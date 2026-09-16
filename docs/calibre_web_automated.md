# Calibre-Web Automated — Technical Service Documentation

**App Name**: `calibre_web_automated`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/calibre_web_automated`  

---

## 1. Overview & Architecture

Calibre-Web Automated (Calibre-Web eBook library manager with ThemePark integration and universal calibre docker mod.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `calibre-web-automated` | Accessible via `https://calibre-web-automated.<yourdomain.tld>` |
| **Internal Web Port** | `8083` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/calibre_web_automated` | Persistent application data (`server_appdata_path/calibre_web_automated`) |
| **Default Image** | `crocodilestick/calibre-web-automated` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### calibre_web_automated overrides
calibre_web_automated_role_docker_volumes_custom: []
calibre_web_automated_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update Calibre-Web Automated:
```bash
sb install mod-calibre-web-automated
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags calibre-web-automated
```
