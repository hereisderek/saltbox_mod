# Saltbox Mod AI Instructions Index

Welcome to the AI instructions and system reference guide for `/opt/saltbox_mod` and the host's Saltbox infrastructure.

## Navigation Map

1. **[01. Architecture & Storage Tiering](file:///opt/saltbox_mod/.ai-instructions/01_architecture_and_storage.md)**
   - Proxmox LXC container environment, Docker runtime, overlay2 setup.
   - Storage tiers: SSD Cache (`/mnt/local/Media`), HDD Warehouse (`/mnt/remote/media/Media`), MergerFS (`/mnt/unionfs/Media`).
   - Host path variables: `root_data_dir`, `root_cache_dir`, `app_log_dir`, `app_cache_dir`, `app_metadata_dir`, `app_data_dir`.
   - App data directories in `/opt/<app>`.

2. **[02. Saltbox Inventory & Overrides](file:///opt/saltbox_mod/.ai-instructions/02_inventory_and_overrides.md)**
   - Official documentation: [https://docs.saltbox.dev/saltbox/inventory/](https://docs.saltbox.dev/saltbox/inventory/)
   - Central override file: `/srv/git/saltbox/inventories/host_vars/localhost.yml`.
   - Override rules: Precedence (Instance-scoped vs Role-scoped), merging with `_custom` lists/dicts.
   - Host patterns: Dynamic `_var_prefix` resolution, volume mounts, GPU passthrough.

3. **[03. Role Authoring Guide](file:///opt/saltbox_mod/.ai-instructions/03_role_authoring_guide.md)**
   - Standard directory structure for custom roles in `/opt/saltbox_mod/roles/<app>/`.
   - Detailed blueprint for `defaults/main.yml` and `tasks/main.yml`.
   - The `lookup('role_var', ...)` engine.
   - Multi-container architecture (PostgreSQL, MariaDB, Redis).
   - Registering in `saltbox_mod.yml` and deploying via `sb install mod-<app>`.

4. **[04. Traefik Proxy, Authelia SSO & Container Healthchecks](file:///opt/saltbox_mod/.ai-instructions/04_traefik_proxy_and_healthchecks.md)**
   - Traefik v2 reverse proxy routing, Cloudflare DNS integration, TLS certresolvers.
   - Authelia SSO protection via `traefik_default_sso_middleware`.
   - Official documentation: [https://docs.saltbox.dev/advanced/healthchecks/](https://docs.saltbox.dev/advanced/healthchecks/)
   - Docker container healthcheck syntax, intervals, retries, and recipes.

5. **[05. Custom Containers & Docker Compose](file:///opt/saltbox_mod/.ai-instructions/05_custom_containers_and_compose.md)**
   - Official documentation: [https://docs.saltbox.dev/advanced/your-own-containers/](https://docs.saltbox.dev/advanced/your-own-containers/)
   - Official documentation: [https://docs.saltbox.dev/reference/modules/traefik_template/#usage](https://docs.saltbox.dev/reference/modules/traefik_template/#usage)
   - Running compose stacks under `/opt/<app>/compose.yaml` with Traefik integration.
   - Managing stacks with Dockge (`/opt/stacks`).
   - Adding Docker CLI functions in shell config.

6. **[06. Scripts & Media Synchronization Operations](file:///opt/saltbox_mod/.ai-instructions/06_scripts_and_sync_operations.md)**
   - In-depth guide to `/opt/saltbox_mod/scripts/saltbox_sync.sh` and `/opt/saltbox_mod/scripts/saltbox_sync_samba.sh`.
   - Healthchecks.io ping reporting (`PING_URL` and `CHECK_PING_URL`).
   - GNU Screen management commands.
   - Systemd timers and service debugging.

7. **[07. Multiple App Instances Architecture & Authoring Guide](file:///opt/saltbox_mod/.ai-instructions/07_multiple_instances_architecture.md)**
   - Official documentation: [https://docs.saltbox.dev/reference/multiple-instances/](https://docs.saltbox.dev/reference/multiple-instances/)
   - Orchestration loop pattern (`main.yml` -> `main2.yml`).
   - Variable resolution precedence (`role_var.py`, `docker_vars.py`, `role_web.py`).
   - Resource isolation: paths, network aliases, DNS, Traefik routes, and port arbitration.
   - Authoring and validating custom roles for multi-instance compatibility.

---

## Important File Paths

| Resource | Path | Description |
|---|---|---|
| **Saltbox Core** | `/srv/git/saltbox` | Upstream Saltbox playbook, roles, resources, plugins |
| **Inventory Host Vars** | `/srv/git/saltbox/inventories/host_vars/localhost.yml` | User variable overrides and host customizations |
| **Sandbox Community** | `/opt/sandbox` | Community roles and role guidance |
| **Saltbox Mod** | `/opt/saltbox_mod` | Local custom roles, playbooks, and helper scripts |
| **Mod Playbook** | `/opt/saltbox_mod/saltbox_mod.yml` | Ansible playbook executing custom mod roles |
| **Ansible Config** | `/opt/saltbox_mod/ansible.cfg` | Ansible configuration loading plugins and roles |
| **Sync Script** | `/opt/saltbox_mod/scripts/saltbox_sync.sh` | SSD to HDD media rsync and cleanup script |
