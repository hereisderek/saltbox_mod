# Music-Tag-Web — Technical Service Documentation

**App Name**: `music_tag_web`  
**Author**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Upstream Repository**: [https://github.com/xhongc/music-tag-web](https://github.com/xhongc/music-tag-web)  
**Role Path**: `/opt/saltbox_mod/roles/music_tag_web`  

---

## 1. Overview & Architecture

Music-Tag-Web is a web-based music tagging and metadata editing tool. It supports batch editing ID3 tags, lyrics scraping, album artwork downloading, and organizing large audio libraries.

Within the Saltbox ecosystem:
- Built with the modernized `role_var` schema.
- Integrated into Traefik with automated HTTPS certificates and Authelia SSO protection.
- Connects directly to the user's unified music library mounted through MergerFS (`/mnt/unionfs/Media/Music/`).

---

## 2. Key Configurations & Port Mappings

| Parameter | Default Value | Description |
|---|---|---|
| **Subdomain** | `music-tag` | Accessible via `https://music-tag.<yourdomain.tld>` |
| **Internal Web Port** | `8002` | Port forwarded to Traefik router |
| **Data Directory** | `/opt/music_tag_web` | Persistent application data and configuration |
| **Media Mount** | `/mnt/unionfs/Media/Music/library:/app/media:rw` | Unified music library read-write access |
| **SSO Protection** | Enabled | Routed through `traefik_default_sso_middleware` (Authelia) |
| **Execution Command** | `["/start"]` | Container launch binary |

---

## 3. Host Inventory Overrides

To customize or add media mount points, configure `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit approval)*:

```yaml
### music_tag_web overrides
music_tag_web_role_docker_volumes_custom:
  - "/mnt/remote/media/Media/Music:/app/remote_media:rw"
```

---

## 4. Deployment & Lifecycle

To deploy or update Music-Tag-Web:
```bash
sb install mod-music-tag-web
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags music-tag-web
```
