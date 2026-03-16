# Saltbox Environment & Project Guidelines

This workspace manages a custom Saltbox environment and its Ansible roles.

## Architecture & Infrastructure
- **OS/Host:** Ubuntu OS running as an LXC container inside Proxmox (PVE).
- **Core Stack:** Various Saltbox and Sandbox apps running primarily as Docker containers.
- **Routing & Networking:** Traefik acts as the reverse proxy. Domains are hosted on Cloudflare (mixed: some proxied, some DNS-only).
- **Storage Tiering:** 
  - Two-tier storage with no remote cloud storage.
  - **Tier 1 (SSD Cache):** `/mnt/local/Media/` - Used for active downloads and fast caching.
  - **Tier 2 (HDD Warehouse):** `/mnt/remote/media/Media/` - Long-term media storage.
  - **Data Flow:** Finished downloads land on the SSD cache and are periodically moved to the HDD warehouse via the `saltbox_sync.sh` script.

## App Configurations (Saltbox & Docker)
- **Saltbox Managed:** Pretty much all the services are installed and configured through [Saltbox](https://docs.saltbox.dev/), which implies they are managed via Ansible.
  - **Local Variables:** Overrides and host-specific local variables are set in `/srv/git/saltbox/inventories/host_vars/localhost.yml`.
  - **Global Settings:** Other general settings are located in the `.yml` files directly under the `/srv/git/saltbox/` directory.
- App configuration volumes and setups for these managed services are mostly located in `/opt/`.
- To interact with apps, prefer native Docker commands (e.g., `docker ps`, `docker logs <container>`) or docker-compose if applicable. 
- Running apps include: `traefik`, `qbittorrent`, `emby`, `radarr`, `sonarr`, `lidarr`, `bazarr`, `prowlarr`, `nextcloud`, `immich`, `paperless`, `homepage`, `healthchecks`, and others.

## Deployment & Execution
- **Ansible Roles:** Custom Saltbox modifications and Ansible roles are maintained in `/opt/saltbox_mod/`.
- Custom roles follow standard Ansible folder structures (`roles/<role_name>/{tasks,defaults}/main.yml`).
- **Sync Script:** The script `/opt/saltbox_mod/scripts/saltbox_sync.sh` manages the SSD to HDD movement and utilizes a lock file, rsync, and optionally Healthchecks.io.

## Conventions
- Before suggesting structural changes, verify the current container configuration using `docker ps` or by inspecting the mounts in `/opt/<app>`.
- Keep in mind the two-tiered storage architecture when writing or modifying paths for any media-related scripts.
- **Local Testing:** When troubleshooting remote access issues, services hosted on this machine can be queried locally by overriding the DNS resolver using `curl`. (e.g., `curl -vkI --resolve <subdomain>.<domain>:443:127.0.0.1 https://<subdomain>.<domain>/`).