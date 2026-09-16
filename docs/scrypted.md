# Scrypted — Technical Service Documentation

**App Name**: `scrypted`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/scrypted`  

---

## 1. Overview & Architecture

Scrypted (High-performance home security camera video integration platform and NVR.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `scrypted` | Accessible via `https://scrypted.<yourdomain.tld>` |
| **Internal Web Port** | `11080` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/scrypted` | Persistent application data (`server_appdata_path/scrypted`) |
| **Default Image** | `koush/scrypted` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### scrypted overrides
scrypted_role_docker_volumes_custom: []
scrypted_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update Scrypted:
```bash
sb install mod-scrypted
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags scrypted
```
