# AI Instructions: Restreamer (Saltbox Mod Role)

## Overview
**App Name:** Restreamer  
**Description:** A complete streaming server solution for capturing and distributing live video streams (RTMP, SRT, HLS, etc.).  
**Role Path:** `/opt/saltbox_mod/roles/restreamer`  
**Installation Command:** `sb install mod-restreamer`

## Architecture & Configuration
This role is built to the modern Saltbox standard using the `_role_var` schema (e.g., `restreamer_role_docker_...`), which allows users to dynamically override settings from their Saltbox inventory (`/srv/git/saltbox/inventories/host_vars/localhost.yml`).

### Common Overrides
To modify this app's settings globally securely, users should set variables in their `localhost.yml` inventory:
* **Docker Image:** Uses `datarhei/restreamer`.
  * `restreamer_role_docker_image_tag`: Will default to `vaapi-latest` (if Intel GPU is detected), `cuda-latest` (if Nvidia GPU is detected), or `latest` (CPU only).
* **Ports Used:**
  * **Web UI:** Port `8080` internally for the web interface and API. Traefik automatically reverse proxies this (no manual port exposing needed for the UI).
  * **Streaming Ports:** `1935` (RTMP), `1936` (RTMPS), `6000:6000/udp` (SRT). These are added via `restreamer_role_docker_ports_custom` so external streaming software can reach the ingest.
* **Storage Paths:**
  * `/opt/restreamer` (default mapping)
  * `/core/config`: Restreamer configuration data.
  * `/core/data`: Restreamer static files / disk access.

### Hardware Acceleration (GPU Transcoding)
Restreamer relies heavily on hardware transcoding for efficient streaming.
* In `tasks/main.yml`, there is an automatic fallback that checks the host for existing devices (`/dev/dri`, `/dev/video0`, `/dev/snd`). 
* Only valid device nodes actually present on the host OS will be passed through to the Docker container, thus avoiding "not a device node" crash loops.
* This mapping happens dynamically. If `docker_device_binds_list` detects any valid devices, they are passed to the container.

### Proxy & SSO (Traefik + Authelia)
* By default, `restreamer_role_traefik_enabled: true` ensures Traefik manages the routing.
* UI and API paths (`/api` and `/ui`) are correctly handled by Traefik rules.
* **Authentication:** Restreamer has its own internal API and User authentication natively managed by the application. `restreamer_role_docker_envs_default` provisions this dynamically using `user.name` and `user.pass` from Saltbox settings.
* It CAN be put behind the Authelia SSO layer via the `restreamer_role_traefik_sso_middleware: "{{ traefik_default_sso_middleware }}"` setting, but normally API connections might break if SSO blocks external incoming streams without bypass rules.

## Maintenance Notes
* **Prefixes:** Remember to always use `restreamer_role_...` for variables in the `defaults/main.yml` definition.
* **Validating Deployment:** If `docker ps` shows continuous restarting, run `sb install mod-restreamer` to re-synchronize variables and clear bad configurations safely. If you must inspect generated values, use the updated `/opt/saltbox_mod/resources/tasks/docker/debug_docker_create_container.yml` via setting `debug_docker_create_container: true`.
