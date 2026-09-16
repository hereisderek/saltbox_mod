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
