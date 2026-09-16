# saltbox_mod

Environment for managing custom Ansible roles within a Saltbox host.

## Installation

```bash
sb install saltbox-mod
```

Alternatively:
```bash
git clone https://github.com/saltyorg/saltbox_mod.git /opt/saltbox_mod
```

## Usage

### From Scratch

1. Create folders for the Ansible role:

    ```bash
    mkdir -p /opt/saltbox_mod/roles/newrole/{defaults,tasks}
    ```

1. Place the defaults and tasks files in there:

    ```bash
    touch /opt/saltbox_mod/roles/newrole/{defaults,tasks}/main.yml
    ```

1. Code your role by adding variables and tasks to the respective files.

1. (_Legacy_*) Optionally, add custom variables into `settings.yml`:

    ```bash
    /opt/saltbox_mod/settings.yml
    ```
   
   &ast; Use of the [Inventory system](https://docs.saltbox.dev/saltbox/inventory) is now preferred over this method.
    
1. Add the Ansible role and tags to the `saltbox_mod.yml` playbook:

    To edit:

    ```bash
    $EDITOR /opt/saltbox_mod/saltbox_mod.yml
    ```

    Add the following line in the appropriate section under `roles:`:

    ```yaml
        - { role: newrole, tags: ['newrole'] }
    ```

    Final result:

    ```yaml
    ---
    - hosts: localhost
      module_defaults:
        ansible.builtin.setup:
          fact_path: "/srv/git/saltbox/ansible_facts.d"
      vars_files:
        - settings.yml
        - ['/srv/git/saltbox/accounts.yml', '/srv/git/saltbox/defaults/accounts.yml.default']
        - ['/srv/git/saltbox/settings.yml', '/srv/git/saltbox/defaults/settings.yml.default']
        - ['/srv/git/saltbox/adv_settings.yml', '/srv/git/saltbox/defaults/adv_settings.yml.default']
      roles:
        # Reqs
        - { role: pre_tasks, tags: ['always', 'pre_tasks'] }
        # Apps Start
        - { role: helloworld, tags: ['helloworld'] }
        - { role: myrole, tags: ['myrole'] }
        - { role: newrole, tags: ['newrole'] }
        # Apps End
    ```

    Caution: The `pre_tasks` role is required and should not be removed.

1. Deploy the Ansible role:

    ```bash
    sb install mod-newrole
    ```

    Alternatively :
    ```bash
    sudo ansible-playbook saltbox_mod.yml --tags newrole
    ```

---

### From an Existing Role

Steps 1 to 3 can be simplified by using the `helloworld` role as a template.
It should be usable without too much modification for most web apps that use a single web port.

```bash
cp -r /opt/saltbox_mod/roles/helloworld /opt/saltbox_mod/roles/newrole && \
sed -i 's/helloworld/newrole/g' /opt/saltbox_mod/roles/newrole/*/main.yml
```

Then edit the defaults settings:

```bash
$EDITOR /opt/saltbox_mod/roles/newrole/defaults/main.yml
```

At the very minimum, you may expect to have to update the following variables:

```yaml
newrole_web_port:
newrole_docker_image:
newrole_docker_envs_default:
newrole_docker_volumes_default:
```

Proceed to step 4.

---

## Custom Services Catalog

This repository maintains custom Ansible roles and integrations extending the stock Saltbox environment:

| Service | Tag | Description | Detailed Technical Docs |
|---|---|---|---|
| **Calibre-Web Automated** | `calibre-web-automated` | eBook library manager with ThemePark integration and universal calibre mod | [docs/calibre_web_automated.md](docs/calibre_web_automated.md) |
| **Calibre-Web Downloader** | `calibre-web-automated-downloader` | Automated book downloader integrating Anna's Archive with Cloudflare bypass | [docs/calibre_web_automated_downloader.md](docs/calibre_web_automated_downloader.md) |
| **DDNS Updater** | `ddns_updater` | Dynamic DNS updater supporting multiple external DNS providers | [docs/ddns_updater.md](docs/ddns_updater.md) |
| **Dockge** | `dockge` | Self-hosted Docker Compose stack manager with web UI (`/opt/stacks`) | [docs/dockge.md](docs/dockge.md) |
| **Duplicati** | `duplicati` | Encrypted backup system backing up `/srv` and `/opt` to secondary storage | [docs/duplicati.md](docs/duplicati.md) |
| **LXServer** | `lxserver` | LX Music data synchronization server and WebPlayer with music library streaming | [docs/lxserver.md](docs/lxserver.md) |
| **MeTube** | `metube` | Web GUI for downloading video and audio from YouTube using yt-dlp | [docs/metube.md](docs/metube.md) |
| **Music-Tag-Web** | `music-tag-web` | Web-based audio metadata and ID3 tagging editor for the music library | [docs/music_tag_web.md](docs/music_tag_web.md) |
| **Restreamer** | `restreamer` | Live video streaming server with VA-API hardware acceleration | [docs/restreamer.md](docs/restreamer.md) |
| **Scrypted** | `scrypted` | High-performance home security camera video integration platform and NVR | [docs/scrypted.md](docs/scrypted.md) |
| **Simple SQ Music Plus** | `simple_sq_music_plus` | Music streaming and library management platform | [docs/simple_sq_music_plus.md](docs/simple_sq_music_plus.md) |
| **SOCKS5 Proxy** | `socks5-proxy` | Lightweight SOCKS5 proxy routed through Gluetun VPN container mode | [docs/socks5_proxy.md](docs/socks5_proxy.md) |
| **Solara** | `solara` | Modern web music player with dynamic synchronized lyrics and chart radars | [docs/solara.md](docs/solara.md) |
| **TubeSync** | `tubesync` | Syncs YouTube channels and playlists locally into organized media libraries | [docs/tubesync.md](docs/tubesync.md) |
| **YouTube-DL Material** | `youtubedl` | Web-based YouTube video downloader with MongoDB backend | [docs/youtubedl.md](docs/youtubedl.md) |
| **YTDL-Sub** | `ytdl-sub` | Scheduled YouTube subscription scraper into Plex/Emby library structure | [docs/ytdl_sub.md](docs/ytdl_sub.md) |

### Deployment Quick Reference
Deploy any of the above custom roles using the `sb` CLI:
```bash
sb install mod-<service_tag>
# Example:
sb install mod-lxserver
sb install mod-solara
```
Or directly with Ansible:
```bash
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags <service_tag>
```

> For comprehensive developer instructions, workspace boundaries, storage conventions, and inventory override mechanics, consult [AGENTS.md](AGENTS.md).

