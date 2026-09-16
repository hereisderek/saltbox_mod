# Dockge — Technical Service Documentation

**App Name**: `dockge`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Upstream Repository**: [https://github.com/louislam/dockge](https://github.com/louislam/dockge)  
**Role Path**: `/opt/saltbox_mod/roles/dockge`  

---

## 1. Overview & Architecture

Dockge is a modern, lightweight, self-hosted Docker Compose stack manager designed by Louis Lam. It provides an intuitive web interface for authoring, starting, stopping, updating, and visualizing multi-container Docker Compose stacks.

Within the Saltbox ecosystem:
- Runs as a Docker container attached to the `saltbox` Docker bridge network.
- Reverse-proxied through Traefik v2 with TLS certificates automatically generated via Cloudflare DNS challenge.
- Protected behind Authelia Single Sign-On (SSO) using the `traefik_default_sso_middleware`.
- Mounts `/var/run/docker.sock` to interface directly with the host's Docker engine.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `dockge` | Accessible via `https://dockge.<yourdomain.tld>` |
| **Internal Web Port** | `5001` | Default container listening port forwarded to Traefik |
| **Stacks Directory** | `/opt/stacks` | Central storage directory for all managed `compose.yaml` stacks |
| **AppData Path** | `/opt/dockge` | Persistent storage for Dockge internal state and database |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |

---

## 3. Host Inventory Overrides

To customize Dockge for your host, define overrides in `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit approval)*:

```yaml
### dockge overrides
dockge_role_docker_envs_custom:
  DOCKGE_ENABLE_CONSOLE: "true"

dockge_role_docker_volumes_custom:
  - "/opt/stacks:/opt/stacks"
```

---

## 4. Deployment & Lifecycle

To deploy or update Dockge:
```bash
sb install mod-dockge
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags dockge
```

To view container logs or inspect state:
```bash
docker logs -f dockge
docker ps --filter "name=dockge"
```
