# 01. Architecture & Storage Tiering

This document details the system infrastructure, storage hierarchy, filesystem layouts, and path conventions implemented on this host.

---

## 1. Host Infrastructure & Docker Runtime

- **Virtualization**: Ubuntu OS operating inside a Proxmox VE (PVE) LXC container.
- **Container Engine**: Docker CE with `overlay2` storage driver.
- **Docker Data Root**: Custom mapped to `/media/data/docker` (configured via `docker_config_custom` in inventory).
- **IPv6 Networking**: Enabled (`docker_ipv6: true`).
- **Core Network**: Docker bridge network named `saltbox` (`docker_networks_name_common`). All web-facing containers attach to this network to communicate with Traefik.
- **GPU Acceleration**:
  - Intel QuickSync / VA-API device node: `/dev/dri/renderD128` (and `/dev/dri`).
  - Passed to containers like Emby, Immich, Restreamer.
  - Transcoding groups: Video (`vgid`), Render (`rgid`), Default (`gid`), mapped via `emby_role_docker_envs_custom` (`GIDLIST: "{{ gid }},{{ vgid }},{{ rgid }}"`) or `immich_role_docker_groups`.

---

## 2. Storage Tiering (Two-Tier Model)

The host operates on a two-tier storage model without reliance on remote cloud drives:

```
[ Active Ingest / Downloads ]
             │
             ▼
 ┌────────────────────────┐
 │   Tier 1: SSD Cache    │  Path: /mnt/local/Media/
 │  (Fast Ingest / Cache) │  Used by: qBittorrent, unpackerr, temporary intake
 └───────────┬────────────┘
             │
             │ Periodic sync & cleanup via saltbox_sync.sh
             ▼
 ┌────────────────────────┐
 │  Tier 2: HDD Warehouse │  Path: /mnt/remote/media/Media/
 │   (Bulk Long-Term)     │  Used for: Movies, TV, Music, YouTube, Photos
 └────────────────────────┘
             │
             ├────────────────────────────────────────┐
             ▼                                        ▼
 ┌────────────────────────┐              ┌────────────────────────┐
 │       MergerFS         │              │    High-Speed SSD      │
 │   /mnt/unionfs/Media   │              │     Cache/Metadata     │
 │ (Unified read access)  │              │      /media/cache      │
 └────────────────────────┘              └────────────────────────┘
```

### Storage Breakdown

1. **Tier 1 (SSD Cache)**:
   - Location: `/mnt/local/Media/`
   - Purpose: Ingest point for downloading clients (`qbittorrent`, `sabnzbd`). High I/O performance ensures torrent seeding and file extraction do not thrash mechanical drives.
2. **Tier 2 (HDD Warehouse)**:
   - Location: `/mnt/remote/media/Media/`
   - Subdirectories:
     - `Movies/`: Archival movie library
     - `TV/`: Archival television library
     - `Music/`: Long-term music files
     - `Youtube/`: Video archive from `ytdl-sub` and `youtubedl`
     - `photos/`: Stored under `/mnt/remote/media/photos/` for Immich
     - `Recording/`: NVR recordings (e.g. Scrypted)
     - `Backups/`: Central long-term backup repository (`root_backup_dir`)
3. **MergerFS / UnionFS**:
   - Location: `/mnt/unionfs/Media/`
   - Branches: Merges `/mnt/local` (Read/Write) and `/mnt/remote/media` (Non-CoW/Archive).
   - Serves unified media paths to media players and servers (e.g., Emby, Jellyfin, Music-Tag-Web).

---

## 3. Host Dynamic Path Conventions

The inventory file (`/srv/git/saltbox/inventories/host_vars/localhost.yml`) defines a standardized hierarchy of high-speed NVMe/SSD paths:

```yaml
root_data_dir: "/media/data"
root_cache_dir: "/media/cache"
ssd_root_backup_dir: "/mnt/backups/ssd-data"
root_backup_dir: "/mnt/remote/media/Backups"

log_dir: "{{ root_cache_dir }}/logs"
cache_dir: "{{ root_cache_dir }}/cache"
metadata_dir: "{{ root_cache_dir }}/metadata"

app_log_dir: "{{ log_dir }}/{{ _var_prefix }}"
app_cache_dir: "{{ cache_dir }}/{{ _var_prefix }}"
app_metadata_dir: "{{ metadata_dir }}/{{ _var_prefix }}"
app_data_dir: "{{ root_data_dir }}/app/{{ _var_prefix }}"

ssd_app_backup_dir: "{{ ssd_root_backup_dir }}/app/{{ _var_prefix }}"
app_backup_dir: "{{ root_backup_dir }}/{{ _var_prefix }}"

shared_metadata_dir: "{{ metadata_dir }}/shared"
```

### How `_var_prefix` Works
When Saltbox runs `create_docker_container.yml`, it dynamically defines:
```yaml
_var_prefix: "{{ var_prefix if (var_prefix is defined) else role_name }}"
```
Because Jinja resolves variables lazily during task execution, any reference to `app_log_dir` or `app_metadata_dir` in `localhost.yml` automatically evaluates to that application's directory name!
- For `sonarr`: resolves to `/media/cache/logs/sonarr` and `/media/cache/metadata/sonarr`.
- For `radarr`: resolves to `/media/cache/logs/radarr` and `/media/cache/metadata/radarr`.
- For `emby`: resolves to `/media/cache/logs/emby` and `/media/cache/metadata/emby`.

---

## 4. Application Configuration Paths (`/opt/<app>`)

All container persistent configuration directories (`/config`) are rooted under `/opt/`:
- `/opt/sonarr`
- `/opt/radarr`
- `/opt/qbittorrent`
- `/opt/emby`
- `/opt/traefik`
- `/opt/authelia`
- `/opt/immich`
- `/opt/dockge`
- `/opt/stacks` (Dockge compose stacks)

### Directory Creation Policy
In custom Saltbox mod roles, directories MUST be declared in `<role>_role_paths_folders_list` and created via:
```yaml
- name: Create directories
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/directories/create_directories.yml"
```
Do not invoke raw `mkdir` shell commands in Ansible roles.

---

## 5. Summary of Key Host Directories

| Directory Path | Filesystem / Type | Purpose |
|---|---|---|
| `/opt/<app>` | NVMe / Host OS | App persistent config, databases, settings |
| `/opt/saltbox_mod` | Git repository | Custom Ansible roles, playbooks, local sync scripts |
| `/srv/git/saltbox` | Git repository | Core upstream Saltbox framework and inventory |
| `/opt/sandbox` | Git repository | Community Sandbox roles repository |
| `/mnt/local/Media` | SSD (Tier 1) | Active downloading, unzipping, rapid ingest |
| `/mnt/remote/media/Media` | HDD (Tier 2) | Permanent media archive |
| `/mnt/unionfs/Media` | MergerFS | Unified view of Tier 1 + Tier 2 |
| `/media/cache` | High-speed SSD | Transcoding cache, metadata, app log sinks |
| `/media/data` | High-speed SSD | Persistent app data (Paperless, Docker root) |
| `/mnt/backups/ssd-data` | Dedicated Backup Disk | Fast SSD-based app state backups |
| `/mnt/remote/media/Backups` | Dedicated Backup Disk | Long-term comprehensive backups (Duplicati) |
