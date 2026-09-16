# 01. Architecture & Storage Tiering

This document details the system infrastructure, storage hierarchy, filesystem layouts, and path conventions implemented on this host based on the live setup in `/srv/git/saltbox/inventories/host_vars/localhost.yml`.

---

## 1. Host Infrastructure & Docker Runtime

- **Virtualization**: Ubuntu OS operating inside a Proxmox VE (PVE) LXC container.
- **Container Engine**: Docker CE with `overlay2` storage driver.
- **Docker Data Root**: Custom mapped to `/media/data/docker` (configured via `docker_config_custom` in inventory).
- **IPv6 Networking**: Enabled (`docker_ipv6: true`).
- **Startup Delays**: `docker_containers_startup_delay: 30`, `docker_service_sleep: 30` to prevent load spikes during boot.
- **Core Network**: Docker bridge network named `saltbox` (`docker_networks_name_common`). All web-facing containers attach to this network to communicate with Traefik.
- **Debugging Tasks**: `debug_docker_create_container: true` using `mod_resources_tasks_path: "/opt/saltbox_mod/resources/tasks"`.
- **GPU Acceleration**:
  - Intel QuickSync / VA-API device node: `/dev/dri/renderD128` (and `/dev/dri`).
  - Transcoding groups: Video (`vgid`), Render (`rgid`), Default (`gid`), mapped via `emby_role_docker_envs_custom` (`GIDLIST: "{{ gid }},{{ vgid }},{{ rgid }}"`), `immich_role_docker_groups`, or `restreamer_docker_groups`.

---

## 2. Storage Tiering (Two-Tier Model) & MergerFS Policies

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

### MergerFS Write Policy (`custom_mount_branch`)
In `localhost.yml`:
```yaml
custom_mount_branch: "/mnt/remote/media=NC:"
```
- The `=NC` policy (**No Create**) instructs MergerFS that writes through `/mnt/unionfs/Media/` must **never** create new files directly on `/mnt/remote/media`.
- Instead, all newly created files fall through to the Read/Write local SSD branch (`/mnt/local=RW:`).
- Once media finishes downloading and unpacks, the `saltbox_sync.sh` engine moves aged files (>90 minutes) from Tier 1 to Tier 2.

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
     - `Youtube/`: Video archive managed by `ytdl-sub` and `youtubedl` (`/mnt/remote/media/Media/Youtube/{{ ytdl_sub_name }}`)
     - `photos/`: Immich photo archives (`/mnt/remote/media/photos/immich` and `/mnt/remote/media/photos/immich-external-library`)
     - `Recording/`: NVR recordings managed by Scrypted (`/mnt/remote/media/Media/Recording/scrypted`)
     - `Backups/`: Central long-term backup repository (`root_backup_dir: /mnt/remote/media/Backups`)
3. **MergerFS / UnionFS**:
   - Location: `/mnt/unionfs/Media/`
   - Serves unified media paths to media players and servers (e.g., Emby, Jellyfin, Music-Tag-Web).
   - Recycle Bin Folders: `/mnt/unionfs/Media/deleted/{TV,Movies,Music}` are mapped in Arr apps to prevent immediate unrecoverable deletions.

---

## 3. Host Dynamic Path Hierarchy

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

### Specific Host Storage Assignments
- **Paperless-ngx**: Persistent database and document archive stored on high-speed NVMe: `paperless_ngx_role_paths_location: "{{ app_data_dir }}"` (`/media/data/app/paperless_ngx`).
- **Nextcloud**: Data files stored on dedicated SSD backup storage: `nextcloud_role_file_location: "{{ ssd_root_backup_dir }}/nextcloud"` (`/mnt/backups/ssd-data/nextcloud`).
- **Duplicati**: Backs up read-only `/srv` and `/opt` into `{{ root_backup_dir }}/duplicati` (`/mnt/remote/media/Backups/duplicati`).
- **Note on `log_path`**: Ansible global log cannot be placed on certain FUSE/network mounts; `localhost.yml` keeps `# log_path: "/media/cache/saltbox.log"` commented out, leaving logging to `./saltbox_mod.log` as defined in `ansible.cfg`.

---

## 4. Summary of Key Host Directories

| Directory Path | Filesystem / Disk Type | Purpose |
|---|---|---|
| `/opt/<app>` | NVMe (Host OS) | App persistent configs, sqlite databases, settings |
| `/opt/saltbox_mod` | Git repository | Custom Ansible roles, playbooks, local sync scripts |
| `/srv/git/saltbox` | Git repository | Upstream Saltbox framework and inventory |
| `/opt/sandbox` | Git repository | Community Sandbox roles repository |
| `/mnt/local/Media` | SSD (Tier 1) | Active downloading, unzipping, rapid ingest |
| `/mnt/remote/media/Media` | HDD (Tier 2) | Permanent media archive |
| `/mnt/unionfs/Media` | MergerFS (`=NC`) | Unified media view; writes fall back to Tier 1 |
| `/media/cache` | High-speed SSD | Transcoding cache, metadata, app log sinks |
| `/media/data` | High-speed SSD | Persistent app data (Paperless, Docker root) |
| `/mnt/backups/ssd-data` | Dedicated Fast Disk | SSD state backups & Nextcloud data store |
| `/mnt/remote/media/Backups` | Dedicated Archive Disk | Long-term comprehensive backups (Duplicati) |
