# Saltbox Environment & Project Guidelines

This workspace manages a custom Saltbox environment and its Ansible roles.

> **Authoritative Guides**: For complete technical specifications, see:
> - [`AGENTS.md`](file:///opt/saltbox_mod/AGENTS.md) — Main repository agent instructions
> - [`.ai-instructions/00_index.md`](file:///opt/saltbox_mod/.ai-instructions/00_index.md) — Modular architecture, role, and override index

---

## Architecture & Infrastructure
- **OS/Host:** Ubuntu OS running as an LXC container inside Proxmox VE (PVE).
- **Core Stack:** Various Saltbox and Sandbox apps running primarily as Docker containers.
- **Routing & Networking:** Traefik acts as the reverse proxy. Domains are hosted on Cloudflare (mixed: some proxied, some DNS-only).
- **Storage Tiering:** 
  - Two-tier storage with no remote cloud storage.
  - **Tier 1 (SSD Cache):** `/mnt/local/Media/` - Used for active downloads and fast caching.
  - **Tier 2 (HDD Warehouse):** `/mnt/remote/media/Media/` - Long-term media storage.
  - **UnionFS / MergerFS:** `/mnt/unionfs/Media/` - Unified media view for servers (Emby).
  - **High-Speed Cache/Logs:** `/media/cache/` (logs, cache, metadata).
  - **Data Flow:** Finished downloads land on the SSD cache and are periodically moved to the HDD warehouse via `/opt/saltbox_mod/scripts/saltbox_sync.sh`.

---

## App Configurations (Saltbox & Docker)
- **Saltbox Managed:** Services are installed and configured through [Saltbox](https://docs.saltbox.dev/), managed via Ansible.
  - **Local Variables & Overrides:** All custom host variables and overrides belong in `/srv/git/saltbox/inventories/host_vars/localhost.yml` (can be edited via `sb edit inventory`).
  - **Global Settings:** Global settings are located in `/srv/git/saltbox/` (`settings.yml`, `adv_settings.yml`, `accounts.yml`).
- App configuration volumes are primarily located under `/opt/<app>`.
- To interact with apps, prefer native Docker commands (e.g., `docker ps`, `docker logs <container>`) or docker-compose if applicable. 
- Running apps include: `traefik`, `qbittorrent`, `emby`, `radarr`, `sonarr`, `lidarr`, `bazarr`, `prowlarr`, `nextcloud`, `immich`, `paperless`, `homepage`, `healthchecks`, `dockge`, and others.

---

## Deployment & Execution
- **Ansible Roles:** Custom Saltbox modifications and Ansible roles are maintained in `/opt/saltbox_mod/roles/<role>/`.
- Custom roles follow standard Ansible folder structures (`roles/<role_name>/{tasks,defaults}/main.yml`).
- **Deploying Mod Roles:**
  ```bash
  sb install mod-<app_name>
  # or
  sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags <app_name>
  ```
- **Sync Script:** `/opt/saltbox_mod/scripts/saltbox_sync.sh` manages SSD to HDD movement, guarded with flock, and monitored via Healthchecks.io.

---

## External Documentation References
- **Saltbox Inventory**: [https://docs.saltbox.dev/saltbox/inventory/](https://docs.saltbox.dev/saltbox/inventory/)
- **Adding Your Own Containers**: [https://docs.saltbox.dev/advanced/your-own-containers/](https://docs.saltbox.dev/advanced/your-own-containers/)
- **Container Healthchecks**: [https://docs.saltbox.dev/advanced/healthchecks/](https://docs.saltbox.dev/advanced/healthchecks/)
- **Traefik Template Module**: [https://docs.saltbox.dev/reference/modules/traefik_template/#usage](https://docs.saltbox.dev/reference/modules/traefik_template/#usage)

---

## Conventions
- Before suggesting structural changes, verify the current container configuration using `docker ps` or by inspecting the mounts in `/opt/<app>`.
- Keep in mind the two-tiered storage architecture when writing or modifying paths for any media-related scripts.
- **Local Testing:** When troubleshooting remote access issues, services hosted on this machine can be queried locally by overriding the DNS resolver using `curl` (e.g., `curl -vkI --resolve <subdomain>.<domain>:443:127.0.0.1 https://<subdomain>.<domain>/`).