# Saltbox Mod Agent & Coding Guidance

This document is the primary instruction and authoritative reference for AI coding agents and contributors working in `/opt/saltbox_mod` and the broader Saltbox environment on this host.

---

## 1. Environment & Architecture Overview

- **Host Environment**: Ubuntu running inside an LXC container on Proxmox VE (PVE).
- **Primary Orchestration**: [Saltbox](https://docs.saltbox.dev/) (upstream repository at `/srv/git/saltbox`), managing containerized applications with Ansible and Docker.
- **Role Ecosystem**:
  - **Upstream Saltbox**: `/srv/git/saltbox/roles` (core media stack, core infrastructure: Traefik, Authelia, Cloudflare DNS, etc.).
  - **Sandbox (Community)**: `/opt/sandbox/roles` (community-contributed roles).
  - **Saltbox Mod (Custom/Local)**: `/opt/saltbox_mod/roles` (user-created custom roles and modifications maintained in this checkout, author: `hereisderek`).
- **Ansible Configuration**: Defined in `/opt/saltbox_mod/ansible.cfg`:
  - `inventory = /srv/git/saltbox/inventories/local`
  - `roles_path = roles:/srv/git/saltbox/roles:/srv/git/saltbox/resources/roles:/opt/sandbox/roles`
  - `filter_plugins`, `lookup_plugins`, `library` linked directly to `/srv/git/saltbox`.
  - Python interpreter: `/srv/ansible/venv/bin/python3`.

---

## 2. Storage Tiering & Filesystem Layout

This system uses a dedicated multi-tier storage design without cloud remote mounts:

1. **Tier 1 (SSD Cache)**:
   - Root path: `/mnt/local/Media/`
   - Purpose: Fast local disk for active torrent downloads, ingest, and unpack operations.
2. **Tier 2 (HDD Warehouse)**:
   - Root path: `/mnt/remote/media/Media/`
   - Purpose: Long-term bulk media library storage.
3. **MergerFS / UnionFS**:
   - Mount path: `/mnt/unionfs/Media/`
   - Combines local and remote tiers for seamless consumer application access.
4. **Cache & Metadata Paths** (High-speed NVMe/SSD):
   - Fast cache: `/media/cache/cache` (`{{ cache_dir }}`)
   - App logs: `/media/cache/logs/{{ _var_prefix }}` (`{{ app_log_dir }}`)
   - App metadata / covers: `/media/cache/metadata/{{ _var_prefix }}` (`{{ app_metadata_dir }}`)
   - Persistent app data: `/media/data/app/{{ _var_prefix }}` (`{{ app_data_dir }}`)
   - SSD Backups: `/mnt/backups/ssd-data/app/{{ _var_prefix }}` (`{{ ssd_app_backup_dir }}`)
   - HDD Backups: `/mnt/remote/media/Backups/{{ _var_prefix }}` (`{{ app_backup_dir }}`)
5. **App Configuration Root**:
   - Container configuration directories reside primarily in `/opt/<app_name>` (mapped to `{{ server_appdata_path }}/<app_name>`).
6. **Data Movement Engine**:
   - Script: `/opt/saltbox_mod/scripts/saltbox_sync.sh`
   - Triggered periodically via systemd timer (`saltbox-sync.timer`) or manually (`-f`).
   - Automatically moves aged downloads from Tier 1 to Tier 2 and triggers Samba index sync in a detached screen session.

---

## 3. Inventory & Variable Override System

All custom settings and overrides MUST be placed in:
```filepath
/srv/git/saltbox/inventories/host_vars/localhost.yml
```
*(Can be opened quickly via the CLI command `sb edit inventory`)*.

### Key Rules for Variables:
1. **Never override `_default` variables directly**:
   - Always append or override via `_custom` lists and dictionaries (e.g. `<role>_role_docker_volumes_custom`, `<role>_role_docker_envs_custom`, `<role>_role_paths_folders_list_custom`).
2. **Dynamic Variable Resolution (`_var_prefix`)**:
   - The Saltbox core container tasks set `_var_prefix: "{{ var_prefix if (var_prefix is defined) else role_name }}"`.
   - This allows global templated paths like `app_log_dir: "{{ log_dir }}/{{ _var_prefix }}"` in `localhost.yml` to automatically resolve to the specific role name during execution.
3. **Precedence Hierarchy**:
   1. Instance-scoped overrides: `<instance_name>_<variable>`
   2. Role-scoped overrides: `<role>_role_<variable>`
   3. Inventory global variables: `localhost.yml`
   4. Saltbox global defaults: `/srv/git/saltbox/{settings,adv_settings,accounts}.yml`
   5. Role defaults: `<role>/defaults/main.yml`

---

## 4. Role Authoring in `/opt/saltbox_mod`

When creating or modifying roles under `/opt/saltbox_mod/roles/<role_name>/`:

### A. Folder Structure
```
/opt/saltbox_mod/roles/<role_name>/
├── defaults/
│   └── main.yml
├── tasks/
│   └── main.yml
└── <role_name>_ai_instruction.md   # (Recommended documentation note)
```

### B. Role Defaults Standard (`defaults/main.yml`)
Order the sections strictly as follows:
1. **Basics**: `<role>_name: <role>`
2. **Paths**: `<role>_role_paths_folder`, `<role>_role_paths_location`, `<role>_role_paths_folders_list`
3. **Web**: `<role>_role_web_subdomain`, `<role>_role_web_domain`, `<role>_role_web_port`, `<role>_role_web_url`
4. **DNS**: `<role>_role_dns_record`, `<role>_role_dns_zone`, `<role>_role_dns_proxy`
5. **Traefik**: `<role>_role_traefik_sso_middleware` (set to `{{ traefik_default_sso_middleware }}` for Authelia SSO, or `""` for public), certresolver, enabled flags.
6. **Docker**:
   - Image (`_repo`, `_tag`, `_image`)
   - Envs (`_default`, `_custom`, combined with `lookup('role_var', ...)` and `combine`)
   - Volumes (`_default`, `_custom`, combined with `+`)
   - Ports (`_defaults`, `_custom` - avoid publishing host ports unless required)
   - Networks (`docker_networks_common + _networks_default + _networks_custom`)
   - Restart policy (`unless-stopped`) and state (`started`)

### C. Standard Tasks Flow (`tasks/main.yml`)
Use the standardized Saltbox task helpers:
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

- name: Create Docker container
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/docker/create_docker_container.yml"
```

### D. Multi-Container / Backend Stacks
When an app requires a database or cache (PostgreSQL, MariaDB, Redis):
- Do NOT run inline database containers.
- Include the official Saltbox roles via `ansible.builtin.include_role` with custom instances (e.g. `postgres_instances: ["{{ <role>_name }}-postgres"]`).

### E. Registering and Deploying
1. Register the role in `/opt/saltbox_mod/saltbox_mod.yml`:
   ```yaml
   - { role: <app_name>, tags: ['<app_name>'] }
   ```
2. Deploy the role:
   ```bash
   sb install mod-<app_name>
   # or
   sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags <app_name>
   ```

---

## 5. Adding Non-Role Containers (Docker Compose & CLI)

According to official Saltbox docs ([Your Own Containers](https://docs.saltbox.dev/advanced/your-own-containers/)):

1. **Docker Compose**:
   - Preferred for standalone web apps not yet turned into roles.
   - Standard directory: `/opt/<app_name>/compose.yaml`.
   - Use the template generator: `sb install generate-traefik-template` or inspect [Traefik Template Reference](https://docs.saltbox.dev/reference/modules/traefik_template/#usage).
   - Docker network must attach to `saltbox`.
   - Include Traefik labels for automatic routing and Authelia SSO.
2. **Dockge**:
   - Deployed at port `5001` via `sb install mod-dockge`. Stacks directory at `/opt/stacks`.
3. **Docker CLI / Shell Functions**:
   - For ephemeral CLI tools (e.g. `yt-dlp`, `speedtest`), define shell functions inside `shell_zsh_zshrc_block_custom` in `localhost.yml`.

---

## 6. Official Documentation & References

- **Saltbox Documentation**: [https://docs.saltbox.dev/](https://docs.saltbox.dev/)
- **Saltbox Inventory & Overrides**: [https://docs.saltbox.dev/saltbox/inventory/](https://docs.saltbox.dev/saltbox/inventory/)
- **Adding Your Own Containers**: [https://docs.saltbox.dev/advanced/your-own-containers/](https://docs.saltbox.dev/advanced/your-own-containers/)
- **Container Healthchecks**: [https://docs.saltbox.dev/advanced/healthchecks/](https://docs.saltbox.dev/advanced/healthchecks/)
- **Traefik Template Module**: [https://docs.saltbox.dev/reference/modules/traefik_template/#usage](https://docs.saltbox.dev/reference/modules/traefik_template/#usage)
- **Saltbox Core GitHub**: [https://github.com/saltyorg/Saltbox](https://github.com/saltyorg/Saltbox)
- **Saltbox Mod GitHub**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)

---

## 7. Modular Instruction Index

For in-depth details on each subsystem, refer to the files in `/opt/saltbox_mod/.ai-instructions/`:
- [`00_index.md`](file:///opt/saltbox_mod/.ai-instructions/00_index.md): Table of contents and reference guide.
- [`01_architecture_and_storage.md`](file:///opt/saltbox_mod/.ai-instructions/01_architecture_and_storage.md): LXC, storage tiers (SSD/HDD/MergerFS), and directory mappings.
- [`02_inventory_and_overrides.md`](file:///opt/saltbox_mod/.ai-instructions/02_inventory_and_overrides.md): `localhost.yml`, scopes, rules, and host-specific path formulas.
- [`03_role_authoring_guide.md`](file:///opt/saltbox_mod/.ai-instructions/03_role_authoring_guide.md): Full step-by-step role implementation specification.
- [`04_traefik_proxy_and_healthchecks.md`](file:///opt/saltbox_mod/.ai-instructions/04_traefik_proxy_and_healthchecks.md): Reverse proxying, middleware, SSO, and healthcheck syntax.
- [`05_custom_containers_and_compose.md`](file:///opt/saltbox_mod/.ai-instructions/05_custom_containers_and_compose.md): Traefik compose template, Dockge, and shell integration.
- [`06_scripts_and_sync_operations.md`](file:///opt/saltbox_mod/.ai-instructions/06_scripts_and_sync_operations.md): Media synchronization, GNU screen, and Healthchecks.io monitoring.
