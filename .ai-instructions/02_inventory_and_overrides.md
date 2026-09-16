# 02. Saltbox Inventory & Overrides

This document details the configuration override mechanics of the Saltbox Inventory System, referencing the official [Saltbox Inventory Documentation](https://docs.saltbox.dev/saltbox/inventory/) and the real host settings in `/srv/git/saltbox/inventories/host_vars/localhost.yml`.

---

## 1. Official Documentation Reference

- **URL**: [https://docs.saltbox.dev/saltbox/inventory/](https://docs.saltbox.dev/saltbox/inventory/)
- **Quick CLI Access**:
  ```bash
  sb edit inventory
  ```
- **Primary Inventory File**:
  ```filepath
  /srv/git/saltbox/inventories/host_vars/localhost.yml
  ```

---

## 2. Why the Inventory System Exists

In modern Saltbox (and Sandbox / Saltbox Mod), roles do not modify upstream git checkouts or local git branches. Instead:
- All upstream role configurations remain pristine under git control.
- All machine-specific settings, mount points, image versions, resource allocations, and feature toggles are centralized in `localhost.yml`.
- Upgrades and git pulls never cause merge conflicts.

---

## 3. Scoping & Precedence Rules

When a role variable is evaluated (e.g. during `sb install <app>` or `sb install mod-<app>`), Ansible determines the value in the following strict order of precedence (highest priority first):

1. **Instance-Scoped Override** (Priority 1):
   - Format: `<instance_name>_<setting>`
   - Use case: When multiple instances of an app run on one host (e.g., `sonarr4k` vs `sonarr`).
   - Example:
     ```yaml
     sonarr4k_docker_image_tag: "nightly"
     ```
2. **Role-Scoped Override** (Priority 2):
   - Format: `<role_name>_role_<setting>`
   - Use case: Sets or overrides a parameter for every container spawned by that role.
   - Example:
     ```yaml
     sonarr_role_docker_image_tag: "nightly"
     ```
3. **Inventory Host Variables** (Priority 3):
   - Top-level variables defined in `localhost.yml` (e.g., `app_log_dir`, `user_id`, `root_cache_dir`).
4. **Saltbox Global Defaults** (Priority 4):
   - `/srv/git/saltbox/defaults/settings.yml.default`
   - `/srv/git/saltbox/defaults/adv_settings.yml.default`
5. **Role Defaults** (Priority 5):
   - Declared inside `/opt/saltbox_mod/roles/<role>/defaults/main.yml`.

---

## 4. Crucial Rule: `_default` vs `_custom` Lists & Dictionaries

Saltbox splits multi-item variables (lists and mappings) into two parts:
- `<role>_role_<property>_default` (Maintained by the role author)
- `<role>_role_<property>_custom` (Maintained by the user in `localhost.yml`)

The role combines them automatically using Jinja lookups:
```yaml
<role>_role_docker_volumes: "{{ lookup('role_var', '_docker_volumes_default', role='<role>') + lookup('role_var', '_docker_volumes_custom', role='<role>') }}"
<role>_role_docker_envs: "{{ lookup('role_var', '_docker_envs_default', role='<role>') | combine(lookup('role_var', '_docker_envs_custom', role='<role>')) }}"
```

> [!WARNING]
> **NEVER** redefine or override `<role>_role_docker_volumes_default` in `localhost.yml`! Doing so completely replaces the core container mounts (such as `/config` or internal application roots). Always append using `<role>_role_docker_volumes_custom` and `<role>_role_docker_envs_custom`.

---

## 5. Active Patterns & Formulas on this Host

### A. Offloading Logs, Caches, and Metadata from `/opt`
To preserve NVMe endurance and keep `/opt` backups compact, the host redirects logs, covers, and caches to `/media/cache/` using the dynamic `_var_prefix`:

```yaml
# Arr stack (Sonarr, Radarr, Lidarr, Bazarr)
sonarr_role_paths_folders_list_custom:
  - "{{ app_metadata_dir }}/MediaCover"
  - "{{ app_log_dir }}"
  - "/mnt/unionfs/Media/deleted/TV"

sonarr_role_docker_volumes_custom:
  - "{{ app_metadata_dir }}/MediaCover:/config/MediaCover"
  - "{{ app_log_dir }}:/config/logs"
```

### B. Emby Media Server Customizations
Hardware acceleration, external cache, and log redirects:
```yaml
emby_role_dns_proxy: false
emby_role_docker_image_repo: "xinjiawei1/emby_unlockd"
emby_role_docker_envs_custom:
  UID: "{{ uid }}"
  GID: "{{ gid }}"
  GIDLIST: "{{ gid }},{{ vgid }},{{ rgid }}"
emby_role_paths_folders_list_custom:
  - "{{ app_cache_dir }}"
  - "{{ app_metadata_dir }}"
  - "{{ app_log_dir }}"
emby_role_docker_volumes_custom:
  - "{{ app_cache_dir }}:/config/cache"
  - "{{ app_metadata_dir }}:/config/metadata"
  - "{{ app_log_dir }}:/config/logs"
```

### C. Immich Photos Custom Storage & Render Devices
Mounting remote HDD photo archives and passing Intel QuickSync GPU:
```yaml
immich_role_paths_folders_list_custom:
  - "{{ app_metadata_dir }}/thumbs"
  - "/mnt/remote/media/photos/immich-external-library"

immich_role_docker_volumes_custom:
  - "{{ immich_paths_location }}:/config"
  - "/mnt/remote/media/photos/immich:/photos"
  - "/mnt/remote/media/photos/immich/external-library:/external-library"
  - "{{ app_metadata_dir }}/thumbs:/photos/thumbs"

immich_role_docker_groups:
  - "{{ rgid }}"
  - "{{ vgid }}"
  - "{{ gid }}"
immich_role_docker_devices: 
  - "/dev/dri/renderD128:/dev/dri/renderD128"
```

### D. Routing Containers Through VPN (Gluetun)
To force a container's network traffic through Gluetun (e.g. `socks5_proxy`):
```yaml
gluetun_role_docker_networks_alias_custom:
  - "socks5-proxy"

socks5_proxy_role_docker_network_mode: "container:gluetun"
```

---

## 6. How to Apply Inventory Changes

Whenever you edit `/srv/git/saltbox/inventories/host_vars/localhost.yml`, the changes take effect only after redeploying the affected role(s):

- For core Saltbox apps:
  ```bash
  sb install <app_name>
  ```
- For Sandbox apps:
  ```bash
  sb install sandbox-<app_name>
  ```
- For Saltbox Mod apps:
  ```bash
  sb install mod-<app_name>
  # or
  sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags <app_name>
  ```
