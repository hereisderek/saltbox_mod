# Saltbox Mod Agent & Coding Guidance

This document is the **single source of truth and authoritative instruction guide** for AI coding agents and contributors working in `/opt/saltbox_mod` and the broader Saltbox environment on this host.

---

## 1. Core Operating Principles & Governance

### A. Workspace Boundaries & Upstream Hygiene
- **Upstream Saltbox (`/srv/git/saltbox`)**: Tracks the upstream Saltbox repository. It must remain clean and pristine so that upstream updates can be pulled without conflicts.
- **Custom Codebase (`/opt/saltbox_mod`)**: **ALL** custom Ansible roles, playbooks (`saltbox_mod.yml`), helper scripts (`scripts/`), and technical service documentation (`docs/`) must reside within `/opt/saltbox_mod`. Never place custom application roles or non-upstream scripts directly inside `/srv/git/saltbox`.
- **CRITICAL APPROVAL POLICY**:
  > [!CAUTION]
  > Any changes to `/srv/git/saltbox/inventories/host_vars/localhost.yml` and any configuration files under `/srv/git/saltbox` (which are gitignored) **REQUIRE EXPLICIT USER APPROVAL** before being modified. Do not edit these files autonomously without presenting the planned modification and obtaining user consent.

### B. General Templates vs. Machine-Specific Overrides
- **Roles & Templates Must Be General**:
  Role defaults (`defaults/main.yml`), tasks (`tasks/main.yml`), and templates (`templates/*.j2`) inside `/opt/saltbox_mod/roles/` must remain **generic, clean, and portable**. They must use standard upstream defaults (e.g., standard internal ports, default `/config` volume paths, standard environment variables).
- **User-Specific Customization Belongs in Inventory**:
  **Never** hardcode machine-specific `/mnt/...` storage paths, host user tokens, or personal directory layouts into role defaults or tasks. Any adaptation to the user's specific host layout must be configured via variable overrides in `/srv/git/saltbox/inventories/host_vars/localhost.yml` (using `*_role_docker_volumes_custom`, `*_role_paths_folders_list_custom`, `*_role_docker_envs_custom`, etc.).

### C. Documentation Workflow for Custom Services
Whenever a custom service is created or updated in `saltbox_mod`:
1. **README Entry**: Add a concise introduction and install tag in [`/opt/saltbox_mod/README.md`](file:///opt/saltbox_mod/README.md).
2. **Dedicated Technical Doc**: Create a dedicated, in-depth technical markdown document under [`/opt/saltbox_mod/docs/<service>.md`](file:///opt/saltbox_mod/docs/) covering upstream source, internal port mappings, volume contracts, Traefik/Authelia configuration, and inventory override examples.

### D. Git Commit & Push Policy
> [!CAUTION]
> **DO NOT COMMIT OR PUSH UNLESS EXPLICITLY ASKED BY THE USER.**
> Never run `git commit` or `git push` autonomously. All code, configuration, and documentation edits must remain as local working changes for the user to inspect and test. Only commit or push when the user explicitly instructs you to do so.

### E. Safe Experimentation & Testing with Helloworld
> [!IMPORTANT]
> **AVOID EXPERIMENTING ON LIVE / PRODUCTION SERVICES.**
> When testing new Ansible role patterns, debug hooks, template resolution logic, or container tasks:
> 1. Use [`roles/helloworld`](file:///opt/saltbox_mod/roles/helloworld) as the sandbox / testbed.
> 2. Run and verify the changes against `helloworld` (`sb install mod-helloworld` or `ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags helloworld`).
> 3. Once proven to work correctly without side effects, apply the verified pattern to the target service.

---

## 2. Environment & Architecture Overview

- **Host Virtualization**: Ubuntu OS running inside an LXC container on Proxmox VE (PVE).
- **Primary Orchestration**: [Saltbox](https://docs.saltbox.dev/) (upstream repository at `/srv/git/saltbox`), managing containerized applications with Ansible and Docker.
- **Docker Engine**: Docker CE with `overlay2` storage driver and custom data root at `/media/data/docker`. IPv6 enabled (`docker_ipv6: true`).
- **Role Ecosystem**:
  - **Upstream Saltbox**: `/srv/git/saltbox/roles` (core media stack, infrastructure: Traefik, Authelia, Cloudflare DNS).
  - **Sandbox (Community)**: `/opt/sandbox/roles` (community-contributed roles).
  - **Saltbox Mod (Custom/Local)**: `/opt/saltbox_mod/roles` (user-created custom roles and modifications maintained in this checkout, author: `hereisderek`).
- **Ansible Configuration (`/opt/saltbox_mod/ansible.cfg`)**:
  - `inventory = /srv/git/saltbox/inventories/local`
  - `roles_path = roles:/srv/git/saltbox/roles:/srv/git/saltbox/resources/roles:/opt/sandbox/roles`
  - `filter_plugins`, `lookup_plugins`, `library` linked directly to `/srv/git/saltbox`.
  - Python interpreter: `/srv/ansible/venv/bin/python3`.

---

## 3. Media Library `/mnt` & Storage Tiering Standards

All services requiring access to the media library on this host must adhere to the standardized two-tier storage and high-speed cache hierarchy:

### Storage Architecture
```
[ Ingest / Torrent Downloads ]
               │
               ▼
   ┌───────────────────────┐
   │   Tier 1: SSD Cache   │   Path: /mnt/local/Media/
   │   (Rapid Intake/I/O)  │   Used for: Active torrents, unzipping, temporary cache
   └───────────┬───────────┘
               │
               │ Periodic automated rsync via saltbox_sync.sh
               ▼
   ┌───────────────────────┐
   │ Tier 2: HDD Warehouse │   Path: /mnt/remote/media/Media/
   │  (Long-Term Storage)  │   Used for: Permanent Movies, TV, Music, YouTube archives
   └───────────────────────┘
               │
               ├───────────────────────────────────────┐
               ▼                                       ▼
   ┌───────────────────────┐               ┌───────────────────────┐
   │       MergerFS        │               │ High-Speed SSD Cache  │
   │  /mnt/unionfs/Media   │               │     /media/cache      │
   │ (Unified read access) │               │   (Logs, cache, meta) │
   └───────────────────────┘               └───────────────────────┘
```

1. **Tier 1 (SSD Cache)**: `/mnt/local/Media/` — Ingest point for downloading clients (`qbittorrent`, `sabnzbd`). High I/O performance prevents thrashing mechanical disks during intensive downloads.
2. **Tier 2 (HDD Warehouse)**: `/mnt/remote/media/Media/` — Bulk permanent storage (`Movies/`, `TV/`, `Music/`, `Youtube/`, `photos/`, `Recording/`).
3. **MergerFS / UnionFS & Write Policy**:
   - Mount path: `/mnt/unionfs/Media/` — Unified filesystem merging Tier 1 and Tier 2.
   - **Write Policy (`custom_mount_branch: "/mnt/remote/media=NC:"`)**: Configured with `=NC` (No Create), ensuring writes through `/mnt/unionfs/` never create files directly on mechanical storage and always land on the local SSD tier.
   - **Recycle Bin Pattern**: Arr applications map `/mnt/unionfs/Media/deleted/{TV,Movies,Music}` into `_paths_folders_list_custom` to prevent accidental unrecoverable media deletion.
4. **High-Speed Cache, Logs & Metadata (`/media/cache`)**:
   - Fast application cache: `/media/cache/cache/{{ _var_prefix }}` (`{{ app_cache_dir }}`)
   - Application logs: `/media/cache/logs/{{ _var_prefix }}` (`{{ app_log_dir }}`)
   - Artwork & metadata: `/media/cache/metadata/{{ _var_prefix }}` (`{{ app_metadata_dir }}`)
   - Persistent app data: `/media/data/app/{{ _var_prefix }}` (`{{ app_data_dir }}`) — e.g. Paperless-ngx
   - SSD state backups: `/mnt/backups/ssd-data/app/{{ _var_prefix }}` (`{{ ssd_app_backup_dir }}`) — e.g. Nextcloud data
   - HDD archive backups: `/mnt/remote/media/Backups/{{ _var_prefix }}` (`{{ app_backup_dir }}`) — e.g. Duplicati
5. **Container AppData Root**: `/opt/<app_name>` (`{{ server_appdata_path }}/<app_name>`).
6. **Data Movement Engine**: Automated script at `/opt/saltbox_mod/scripts/saltbox_sync.sh` (systemd timer `saltbox-sync.timer` or manual `-f`).

---

## 4. Inventory & Variable Override Conventions

All custom variable overrides belong in:
```filepath
/srv/git/saltbox/inventories/host_vars/localhost.yml
```
*(CLI shortcut: `sb edit inventory` — Requires explicit approval before modifying)*.

### Rules for Variables:
1. **Never override `_default` variables directly**:
   Always append or override using `_custom` lists and mappings:
   - `<role>_role_docker_volumes_custom`
   - `<role>_role_docker_envs_custom`
   - `<role>_role_paths_folders_list_custom`
   - `<role>_role_docker_ports_custom`
   - `<role>_role_docker_devices_custom`
   - `<role>_role_docker_commands_custom`
   *(Exception: When migrating an upstream container image family with fundamentally different volume structures, such as switching qBittorrent to Hotio `ghcr.io/hotio/qbittorrent`, `_docker_volumes_default` is intentionally adapted in `localhost.yml`).*
2. **Docker Debugging Tasks (`mod_resources_tasks_path`)**:
   `localhost.yml` defines `debug_docker_create_container: true` and `mod_resources_tasks_path: "/opt/saltbox_mod/resources/tasks"`. Roles include `{{ mod_resources_tasks_path }}/docker/debug_docker_create_container.yml` directly before creating the container. All diagnostic tasks are wrapped in a single conditional block (`when: debug_docker_create_container | default(false) | bool`), skipping completely with zero overhead when disabled.

3. **Dynamic `_var_prefix` Resolution**:
   Saltbox sets `_var_prefix` to the active role name dynamically during execution. In `localhost.yml`, referencing `app_log_dir` or `app_metadata_dir` evaluates automatically to that specific role's directory.
4. **Precedence Hierarchy**:
   1. Instance-Scoped: `<instance_name>_<setting>`
   2. Role-Scoped: `<role_name>_role_<setting>`
   3. Inventory Host Variables (`localhost.yml`)
   4. Saltbox Global Defaults (`/srv/git/saltbox/defaults/settings.yml.default`)
   5. Role Defaults (`defaults/main.yml`)

---

## 5. Role Authoring Standard in `/opt/saltbox_mod`

### A. Role File Hierarchy
```
/opt/saltbox_mod/roles/<role_name>/
├── defaults/
│   └── main.yml                       # Generic defaults with role_var lookups
├── tasks/
│   └── main.yml                       # Task execution orchestration
└── <role_name>_ai_instruction.md       # Quick AI instruction note
```

### B. Conventions & Naming Rules
- Use `snake_case` for role directories, Ansible role names, and variable prefixes.
- Use lowercase `kebab-case` for literal Ansible tags in `saltbox_mod.yml`.
- Check both Saltbox and Sandbox to prevent role or tag collisions.
- Every `lookup('role_var', ...)` in defaults must specify an explicit `role='<role_name>'` target.
- In assertions, prefer boolean Jinja tests (`is search(...)`, `is match(...)`) over filters that return strings or `none`.

### C. Generic Blueprint for `defaults/main.yml`
```yaml
---
##################################################################################
# Title:         Saltbox Mod: Roles | <role_name> | Defaults                     #
# Author(s):     hereisderek                                                     #
# URL:           https://github.com/hereisderek/saltbox_mod                      #
##################################################################################

################################
# Basics
################################
<role_name>_name: <role_name>

################################
# Paths
################################
<role_name>_role_paths_folder: "{{ <role_name>_name }}"
<role_name>_role_paths_location: "{{ server_appdata_path }}/{{ <role_name>_role_paths_folder }}"
<role_name>_role_paths_folders_list:
  - "{{ <role_name>_role_paths_location }}"

################################
# Web
################################
<role_name>_role_web_subdomain: "{{ <role_name>_name }}"
<role_name>_role_web_domain: "{{ user.domain }}"
<role_name>_role_web_port: "8080" # Generic internal container port
<role_name>_role_web_url: "{{ 'https://' + (lookup('role_var', '_web_subdomain', role='<role_name>') + '.' + lookup('role_var', '_web_domain', role='<role_name>') if (lookup('role_var', '_web_subdomain', role='<role_name>') | length > 0) else lookup('role_var', '_web_domain', role='<role_name>')) }}"

################################
# DNS
################################
<role_name>_role_dns_record: "{{ lookup('role_var', '_web_subdomain', role='<role_name>') }}"
<role_name>_role_dns_zone: "{{ lookup('role_var', '_web_domain', role='<role_name>') }}"
<role_name>_role_dns_proxy: "{{ dns_proxied }}"

################################
# Traefik (Reverse Proxy & Auth)
################################
<role_name>_role_traefik_sso_middleware: "{{ traefik_default_sso_middleware }}"
<role_name>_role_traefik_middleware_default: "{{ traefik_default_middleware }}"
<role_name>_role_traefik_middleware_custom: ""
<role_name>_role_traefik_certresolver: "{{ traefik_default_certresolver }}"
<role_name>_role_traefik_enabled: true
<role_name>_role_traefik_api_enabled: false
<role_name>_role_traefik_api_endpoint: ""

################################
# Docker
################################
<role_name>_role_docker_container: "{{ <role_name>_name }}"

# Image
<role_name>_role_docker_image_pull: true
<role_name>_role_docker_image_repo: "ghcr.io/vendor/<role_name>"
<role_name>_role_docker_image_tag: "latest"
<role_name>_role_docker_image: "{{ lookup('role_var', '_docker_image_repo', role='<role_name>') }}:{{ lookup('role_var', '_docker_image_tag', role='<role_name>') }}"

# Envs
<role_name>_role_docker_envs_default:
  PUID: "{{ uid }}"
  PGID: "{{ gid }}"
  TZ: "{{ tz }}"
<role_name>_role_docker_envs_custom: {}
<role_name>_role_docker_envs: "{{ lookup('role_var', '_docker_envs_default', role='<role_name>') | combine(lookup('role_var', '_docker_envs_custom', role='<role_name>')) }}"

# Volumes (Keep generic! Map /config only. User maps /mnt/... in inventory)
<role_name>_role_docker_volumes_default:
  - "{{ <role_name>_role_paths_location }}:/config"
<role_name>_role_docker_volumes_custom: []
<role_name>_role_docker_volumes: "{{ lookup('role_var', '_docker_volumes_default', role='<role_name>') + lookup('role_var', '_docker_volumes_custom', role='<role_name>') }}"

# Ports (Do not bind host ports by default unless required)
<role_name>_role_docker_ports_defaults: []
<role_name>_role_docker_ports_custom: []
<role_name>_role_docker_ports: "{{ lookup('role_var', '_docker_ports_defaults', role='<role_name>') + lookup('role_var', '_docker_ports_custom', role='<role_name>') }}"

# Network & Hostname
<role_name>_role_docker_hostname: "{{ <role_name>_name }}"
<role_name>_role_docker_networks_alias: "{{ <role_name>_name }}"
<role_name>_role_docker_networks_default: []
<role_name>_role_docker_networks_custom: []
<role_name>_role_docker_networks: "{{ docker_networks_common + lookup('role_var', '_docker_networks_default', role='<role_name>') + lookup('role_var', '_docker_networks_custom', role='<role_name>') }}"

# Operations
<role_name>_role_docker_restart_policy: unless-stopped
<role_name>_role_docker_state: started
```

### D. Blueprint for `tasks/main.yml`
```yaml
---
- name: Add DNS record
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/dns/tasker.yml"
  vars:
    dns_record: "{{ lookup('role_var', '_dns_record') }}"
    dns_zone: "{{ lookup('role_var', '_dns_zone') }}"
    dns_proxy: "{{ lookup('role_var', '_dns_proxy') }}"

- name: Remove existing Docker container
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/docker/remove_docker_container.yml"

- name: Create directories
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/directories/create_directories.yml"

- name: Debug Docker container creation
  ansible.builtin.include_tasks: "{{ mod_resources_tasks_path }}/docker/debug_docker_create_container.yml"

- name: Create Docker container
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/docker/create_docker_container.yml"
```

### E. Multi-Container Stacks
If an application requires PostgreSQL, MariaDB, or Redis, include the existing upstream Saltbox role via `ansible.builtin.include_role` with a dedicated instance name (e.g. `postgres_instances: ["{{ <role_name>_name }}-postgres"]`). Do not create ad-hoc database containers.

### F. Registering and Deploying
1. Add to [`/opt/saltbox_mod/saltbox_mod.yml`](file:///opt/saltbox_mod/saltbox_mod.yml):
   ```yaml
   - { role: <app_name>, tags: ['<app_name>'] }
   ```
2. Update documentation:
   - Add summary to [`README.md`](file:///opt/saltbox_mod/README.md).
   - Add detailed specification to [`docs/<app_name>.md`](file:///opt/saltbox_mod/docs/).
3. Deploy:
   ```bash
   sb install mod-<app_name>
   # or
   sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags <app_name>
   ```

### G. Critical Gotcha: Preventing Duplicate Container Mount Points
Saltbox combines container volume mounts using list concatenation:
```yaml
_docker_volumes: "{{ lookup('role_var', '_docker_volumes_default') + lookup('role_var', '_docker_volumes_custom') }}"
```
If a destination path (e.g., `/server/music`) is defined in both `<role>_role_docker_volumes_default` and overridden in `localhost.yml` under `<role>_role_docker_volumes_custom`, Docker's container creation task fails with:
```
[ERROR]: Task failed: Module failed: The mount point "/server/music" appears twice in the volumes option
fatal: [localhost]: FAILED! => {"attempts": 2, "changed": false, "msg": "The mount point \"/server/music\" appears twice in the volumes option"}
```
**Architectural Rule**:
- In `defaults/main.yml`, `<role>_role_docker_volumes_default` must **only** mount non-customizable baseline paths (e.g., `/server/data` or `/config`).
- Do **not** pre-populate media libraries (`/server/music`), log paths (`/server/logs`), or cache paths (`/server/cache`) in `_docker_volumes_default` if they are meant to be mapped to the host's unified media library or system paths.
- Inject all host media mappings and directory redirects cleanly via `<role>_role_docker_volumes_custom` in `localhost.yml`.

---

## 6. Reverse Proxy, Authelia & Container Healthchecks

- **Traefik Reverse Proxy**: Traefik labels are automatically generated by `create_docker_container.yml` when `<role>_role_traefik_enabled: true`. Entrypoints: `web` (80 -> redirect to HTTPS) and `websecure` (443).
- **Authelia SSO Middleware**: Bound via `<role>_role_traefik_sso_middleware: "{{ traefik_default_sso_middleware }}"`. To disable SSO for public access, set to `""`.
- **API Router Bypass**: For apps requiring unauthenticated webhook/API endpoints:
  ```yaml
  <role>_role_traefik_api_enabled: true
  <role>_role_traefik_api_endpoint: "PathPrefix(`/api`) || PathPrefix(`/ping`)"
  ```
- **Container Healthchecks**: Injected via `localhost.yml` ([docs](https://docs.saltbox.dev/advanced/healthchecks/)):
  ```yaml
  <role_name>_docker_healthcheck:
    test: ["CMD", "curl", "--fail", "http://localhost:{{ <role_name>_web_port }}"]
    interval: 10s
    timeout: 5s
    retries: 10
    start_period: 10s
  ```

---

## 7. Adding Non-Role Containers (Docker Compose, Dockge & CLI)

According to official Saltbox docs ([Your Own Containers](https://docs.saltbox.dev/advanced/your-own-containers/)):

1. **Docker Compose**:
   - Best for standalone web apps before turning into a full role.
   - Standard directory: `/opt/<app_name>/compose.yaml`.
   - Template generator:
     ```bash
     sb install generate-traefik-template
     ```
   - Docker network must attach to `saltbox` (`external: true`).
2. **Dockge (Port 5001)**:
   - Deployed at port `5001` via `sb install mod-dockge`. Stacks directory at `/opt/stacks/<stack_name>/compose.yaml`.
   - Managed securely behind Authelia SSO.
3. **Docker CLI / Shell Functions**:
   - For ephemeral CLI tools (e.g. `yt-dlp`, `speedtest`), define shell functions inside `shell_zsh_zshrc_block_custom` in `localhost.yml`.

---

## 8. Media Synchronization Scripts & Operations

- **Sync Script**: `/opt/saltbox_mod/scripts/saltbox_sync.sh`
- **Samba Post-Sync Helper**: `/opt/saltbox_mod/scripts/saltbox_sync_samba.sh`
- **Functionality**:
  - Validates mounts (`/mnt/local` and `/mnt/remote/media`).
  - Purges junk files (`._*`, `.DS_Store`, `.localized`).
  - Runs optimized `rsync --files-from` to avoid full remote scanning.
  - Deletes aged source files on SSD (>90 minutes) once copied.
  - Starts post-sync Samba indexing in a detached GNU Screen session (`saltbox_sync_samba`).
  - Protected with `flock` (`/tmp/saltbox_sync.lock`).
- **Healthchecks.io Dual Pings**:
  - `CHECK_PING_URL`: Evaluated every run with status payload.
  - `PING_URL`: Sent only when files were actually transferred/deleted, sending the full sync log.
- **GNU Screen Commands**:
  - `screen -ls`: list sessions
  - `screen -r saltbox_sync_samba`: reattach
  - `Ctrl-A, D`: detach
  - `screen -S saltbox_sync_samba -X quit`: kill session
- **Systemd Management**:
  - Timer: `systemctl status saltbox-sync.timer`
  - Manual start: `sudo systemctl start saltbox-sync.service`
  - Forced CLI run: `/opt/saltbox_mod/scripts/saltbox_sync.sh -f`

---

## 9. Official Documentation & Reference Links

- **Saltbox Inventory**: [https://docs.saltbox.dev/saltbox/inventory/](https://docs.saltbox.dev/saltbox/inventory/)
- **Adding Your Own Containers**: [https://docs.saltbox.dev/advanced/your-own-containers/](https://docs.saltbox.dev/advanced/your-own-containers/)
- **Container Healthchecks**: [https://docs.saltbox.dev/advanced/healthchecks/](https://docs.saltbox.dev/advanced/healthchecks/)
- **Traefik Template Module**: [https://docs.saltbox.dev/reference/modules/traefik_template/#usage](https://docs.saltbox.dev/reference/modules/traefik_template/#usage)
- **Saltbox Core Documentation**: [https://docs.saltbox.dev/](https://docs.saltbox.dev/)
- **Saltbox Core GitHub**: [https://github.com/saltyorg/Saltbox](https://github.com/saltyorg/Saltbox)
- **Saltbox Mod GitHub**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)

---

## 10. Modular Reference Links

- [`00_index.md`](file:///opt/saltbox_mod/.ai-instructions/00_index.md): Modular instructions index.
- [`01_architecture_and_storage.md`](file:///opt/saltbox_mod/.ai-instructions/01_architecture_and_storage.md): Storage hierarchy, two tiers, and host paths.
- [`02_inventory_and_overrides.md`](file:///opt/saltbox_mod/.ai-instructions/02_inventory_and_overrides.md): `localhost.yml` override patterns and scoping rules.
- [`03_role_authoring_guide.md`](file:///opt/saltbox_mod/.ai-instructions/03_role_authoring_guide.md): Complete role design blueprint.
- [`04_traefik_proxy_and_healthchecks.md`](file:///opt/saltbox_mod/.ai-instructions/04_traefik_proxy_and_healthchecks.md): Reverse proxy, Authelia SSO, and healthcheck recipes.
- [`05_custom_containers_and_compose.md`](file:///opt/saltbox_mod/.ai-instructions/05_custom_containers_and_compose.md): Traefik compose template, Dockge, and shell CLI integration.
- [`06_scripts_and_sync_operations.md`](file:///opt/saltbox_mod/.ai-instructions/06_scripts_and_sync_operations.md): Rsync media synchronization and Healthchecks.io reporting.
