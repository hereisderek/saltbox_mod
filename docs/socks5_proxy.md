# SOCKS5 Proxy — Technical Service Documentation

**App Name**: `socks5_proxy`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/socks5_proxy`  

---

## 1. Overview & Architecture

SOCKS5 Proxy (Lightweight SOCKS5 proxy routed through Gluetun VPN container mode.)

Within the Saltbox ecosystem:
- Runs as a Docker container managed by the Saltbox orchestration framework.
- Attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with automated Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `socks5-proxy` | Accessible via `https://socks5-proxy.<yourdomain.tld>` |
| **Internal Web Port** | `1080` | Internal container listening port forwarded to Traefik |
| **AppData Path** | `/opt/socks5_proxy` | Persistent application data (`server_appdata_path/socks5_proxy`) |
| **Default Image** | `serjs/go-socks5-proxy` | Container image repository |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize configuration for your host, edit `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit user approval)*:

```yaml
### socks5_proxy overrides
socks5_proxy_role_docker_volumes_custom: []
socks5_proxy_role_docker_envs_custom: {}
```

---

## 4. Deployment & Lifecycle

To deploy or update SOCKS5 Proxy:
```bash
sb install mod-socks5-proxy
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags socks5-proxy
```
