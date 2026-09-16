# Restreamer — Technical Service Documentation

**App Name**: `restreamer`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/restreamer`  

---

## 1. Overview & Architecture

Restreamer (Self-hosted live video streaming server with VA-API hardware acceleration and multi-destination streaming.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `restreamer` | Accessible via `https://restreamer.<yourdomain.tld>` |
| **Internal Web Port** | `8080` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/restreamer` | Persistent application data (`server_appdata_path/restreamer`) |
| **Default Image** | `datarhei/restreamer` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### restreamer overrides
restreamer_role_docker_volumes_custom: []
restreamer_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update Restreamer:
```bash
sb install mod-restreamer
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags restreamer
```
