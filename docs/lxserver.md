# LXServer — Technical Service Documentation

**App Name**: `lxserver`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Upstream Repository**: [https://github.com/XCQ0607/lxserver](https://github.com/XCQ0607/lxserver)  
**Role Path**: `/opt/saltbox_mod/roles/lxserver`  

---

## 1. Overview & Architecture

LXServer (LX Music Sync Server & WebPlayer Enhanced Edition) is a multi-functional Node.js application built to complement the popular LX Music ecosystem:
- **Data Synchronization**: Synchronizes user playlists, track favorites, and playback settings between desktop clients and mobile apps via WebSocket / HTTP.
- **WebDAV Backup**: Automatically creates periodic database backups to WebDAV storage.
- **Embedded WebPlayer**: Offers a built-in web-based music player and downloader that can stream tracks and index local music files.
- **Console Dashboard**: Administrative console located at `/music` for managing accounts and synchronization keys.

Within the Saltbox ecosystem:
- Runs as a standalone Docker container attached to the `saltbox` Docker bridge network.
- Automated reverse proxy routing through Traefik v2 with Cloudflare DNS TLS certificates.
- Protected behind Authelia Single Sign-On (SSO) via `traefik_default_sso_middleware`.

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `lxserver` | Accessible via `https://lxserver.<yourdomain.tld>` |
| **Internal Web Port** | `9527` | Internal Express/WebSocket server port forwarded to Traefik |
| **AppData Path** | `/opt/lxserver` | App persistent storage (`data`, `logs`, `cache`, `music`) |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |
| **Admin Console** | `/music` | Administrative user/sync dashboard |
| **Web Player** | `/` | Web music player interface |

---

## 3. Host Inventory Overrides

To connect LXServer directly to the host's MergerFS unified music library and redirect logs/cache, add the following override block to `/srv/git/saltbox/inventories/host_vars/localhost.yml`:

```yaml
### lxserver
lxserver_role_docker_volumes_custom:
  - "/mnt/unionfs/Media/Music/library:/server/music:rw"
  - "{{ app_log_dir }}:/server/logs"
  - "{{ app_cache_dir }}:/server/cache"
```

---

## 4. Deployment & Lifecycle

To deploy or update LXServer:
```bash
sb install mod-lxserver
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags lxserver
```

To view container logs or inspect state:
```bash
docker logs -f lxserver
docker ps --filter "name=lxserver"
```

---

## 5. Troubleshooting & Debug Log Reference

### Issue: Duplicate Container Mount Point Collision (`/server/music`)

During installation via `sb install mod-lxserver`, the task fails with:

```text
FAILED - RETRYING: [localhost]: lxserver : Resources | Tasks | Docker | Create Docker Container | Create Docker Container (1 retries left).
FAILED - RETRYING: [localhost]: lxserver : Resources | Tasks | Docker | Create Docker Container | Create Docker Container (0 retries left).
[ERROR]: Task failed: Module failed: The mount point "/server/music" appears twice in the volumes option
Origin: /srv/git/saltbox/resources/tasks/docker/create_docker_container.yml:237:3

235   when: ('container:' in _docker_vars._docker_network_mode)
236
237 - name: Resources | Tasks | Docker | Create Docker Container | Create Docker Container # noqa args[module]
      ^ column 3

fatal: [localhost]: FAILED! => {"attempts": 2, "changed": false, "msg": "The mount point \"/server/music\" appears twice in the volumes option"}
```

#### Cause
Saltbox's Docker resource module evaluates volumes by concatenating defaults and overrides:
```yaml
_docker_volumes: "{{ lookup('role_var', '_docker_volumes_default') + lookup('role_var', '_docker_volumes_custom') }}"
```
If `/server/music` is declared inside `roles/lxserver/defaults/main.yml` in `lxserver_role_docker_volumes_default` AND also defined in `localhost.yml` in `lxserver_role_docker_volumes_custom`, Docker receives two entries targeting container destination `/server/music`, causing `community.docker.docker_container` to abort execution.

#### Resolution
1. Keep `lxserver_role_docker_volumes_default` strictly confined to essential baseline storage:
   ```yaml
   lxserver_role_docker_volumes_default:
     - "{{ lxserver_role_paths_location }}/data:/server/data"
   ```
2. Map host music libraries, logs, and caches exclusively via `lxserver_role_docker_volumes_custom` in `/srv/git/saltbox/inventories/host_vars/localhost.yml`:
   ```yaml
   lxserver_role_docker_volumes_custom:
     - "/mnt/unionfs/Media/Music/library:/server/music:rw"
     - "{{ app_log_dir }}:/server/logs"
     - "{{ app_cache_dir }}:/server/cache"
   ```

