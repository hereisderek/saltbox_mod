# Duplicati — Technical Service Documentation

**App Name**: `duplicati`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/duplicati`  

---

## 1. Overview & Architecture

Duplicati (Encrypted backup client backing up /srv and /opt configurations to secondary storage.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `duplicati` | Accessible via `https://duplicati.<yourdomain.tld>` |
| **Internal Web Port** | `8200` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/duplicati` | Persistent application data (`server_appdata_path/duplicati`) |
| **Default Image** | `lscr.io/linuxserver/duplicati` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### duplicati overrides
duplicati_role_docker_volumes_custom: []
duplicati_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update Duplicati:
```bash
sb install mod-duplicati
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags duplicati
```
