# 08. qBittorrent Mod, Upstream Inheritance & Authentication Bypass

This guide details the architecture of the custom `qbittorrent` mod role (`/opt/saltbox_mod/roles/qbittorrent`), how it inherits from upstream Saltbox while avoiding code duplication, and how authentication bypass works across qBittorrent, Traefik, and Authelia.

---

## 1. Upstream Inheritance & Code Minimization Architecture

Rather than maintaining a completely duplicate copy of Saltbox's upstream qBittorrent role, `/opt/saltbox_mod/roles/qbittorrent` uses a **hybrid inheritance pattern**:

1. **Unchanged Subtasks & Templates via Symlinks**:
   - `subtasks/hosts.yml -> /srv/git/saltbox/roles/qbittorrent/tasks/subtasks/hosts.yml`
   - `subtasks/host_installs.yml -> /srv/git/saltbox/roles/qbittorrent/tasks/subtasks/host_installs.yml`
   - `subtasks/legacy.yml -> /srv/git/saltbox/roles/qbittorrent/tasks/subtasks/legacy.yml`
   - `subtasks/post-install/main.yml -> /srv/git/saltbox/roles/qbittorrent/tasks/subtasks/post-install/main.yml`
   - `templates/qbittorrent.service.j2 -> /srv/git/saltbox/roles/qbittorrent/templates/qbittorrent.service.j2`
   - `templates/qbittorrent.yml.j2 -> /srv/git/saltbox/roles/qbittorrent/templates/qbittorrent.yml.j2`
   Whenever upstream updates these files, the mod role automatically consumes the updates without manual copying or merge conflicts.

2. **Chained Settings Execution**:
   - `subtasks/pre-install/main.yml`: Executes upstream's `pre-install/main.yml` first via `include_tasks`, then appends the mod's specific settings (`AlternativeUIEnabled`, `AuthSubnetWhitelistEnabled`, `LocalHostAuth`).
   - `subtasks/post-install/settings/main.yml`: Executes upstream's `settings/main.yml` first, then appends the mod's specific settings.
   Any new configuration parameters or changes upstream adds in future updates are immediately applied.

3. **Isolated Mod Logic**:
   - `subtasks/alt_webui.yml`: Standalone task handling third-party WebUI downloads and configuration.
   - `main2.yml`: Orchestrates DNS, port claims, Hotio migration checks, upstream pre/docker/post tasks, and Alt WebUI tasks.

---

## 2. Key Features of the Mod Role

### 2.1. Isolated Paths Suffix (`_mod`)
In `defaults/main.yml`:
```yaml
qbittorrent_role_paths_folder: "{{ qbittorrent_name }}_mod"
qbittorrent_role_paths_location: "{{ server_appdata_path }}/{{ qbittorrent_role_paths_folder }}"
```
For instance `qbittorrent`, AppData resides at `/opt/qbittorrent_mod`.  
For instance `qbittorrent2`, AppData resides at `/opt/qbittorrent2_mod`.  
This guarantees zero collision with upstream Saltbox's `/opt/qbittorrent`.

### 2.2. Native Hotio Base Image Support
Hotio images (`ghcr.io/hotio/qbittorrent`) separate configuration and data (`/config/config` and `/config/data`).
- `qbittorrent_role_is_hotio`: Auto-detects if `hotio` is in the image repo name.
- `qbittorrent_role_docker_volumes_default`: Automatically configures the appropriate volume mappings:
  - If Hotio: mounts `/qBittorrent:/config/config` and `/data:/config/data`.
  - If standard (LinuxServer/Saltydk): mounts `_paths_location:/config`.
- `tasks/main2.yml`: Includes automatic migration that safely copies existing `BT_backup` data to `/data/BT_backup` if switching to Hotio layout.

### 2.3. Automated Third-Party WebUI (e.g. VueTorrent)
Controlled by gated flag `qbittorrent_role_alt_webui_enabled`:
- `qbittorrent_role_alt_webui_url`: URL of the GitHub repository or archive (defaults to `https://github.com/VueTorrent/VueTorrent`).
- Dynamically queries GitHub for the latest release asset or uses GitHub's direct release download.
- Extracts into `{{ paths_location }}/webui` and binds to `/config/webui`.
- Configures `WebUI\AlternativeUIEnabled=true` and points `WebUI\RootFolder` to `/config/webui/vuetorrent`.

---

## 3. Disabling qBittorrent Login Behind Authelia

When qBittorrent is reverse-proxied by Traefik with Authelia SSO, users are already authenticated before traffic hits the container. Asking for credentials a second time is redundant.

qBittorrent uses three parameters to allow trusted IP networks to bypass its internal login:
```ini
[Preferences]
WebUI\AuthSubnetWhitelistEnabled=true
WebUI\AuthSubnetWhitelist=0.0.0.0/0, ::/0
WebUI\LocalHostAuth=false
```

Because Saltbox sets `ReverseProxySupportEnabled=true` and `TrustedReverseProxiesList=172.19.0.0/16`, qBittorrent extracts the client IP from `X-Forwarded-For`. Setting `0.0.0.0/0, ::/0` allows any client that has successfully passed Authelia to enter the WebUI directly.

### Enabling in `localhost.yml`:
```yaml
qbittorrent_role_auth_bypass_enabled: true

# Optional: restrict to specific subnets if desired
# qbittorrent_role_auth_subnet_whitelist: "192.168.1.0/24, 10.0.0.0/8, 172.19.0.0/16"
```

---

## 4. Traefik & Authelia Routing Patterns

### 4.1. Entire App Open vs Behind Authelia
In Saltbox, every role defines its SSO middleware variable:
`{{ role_name }}_role_traefik_sso_middleware: "{{ traefik_default_sso_middleware }}"` (`authelia@docker`).

- **To remove Authelia from the entire application**:
  Set the middleware to an empty string in `localhost.yml`:
  ```yaml
  qbittorrent_role_traefik_sso_middleware: ""
  ```
  For a secondary instance:
  ```yaml
  qbittorrent2_traefik_sso_middleware: ""
  ```

### 4.2. Keep App Behind Authelia, But Open Part of the URL (Path Bypass)
Saltbox generates a dedicated **API router** for applications that bypasses the SSO middleware.

In `localhost.yml`:
```yaml
# Enable API routing (default is true for qbittorrent)
qbittorrent_role_traefik_api_enabled: true

# Define the Traefik Path rule for endpoints that should be public:
qbittorrent_role_traefik_api_endpoint: "PathPrefix(`/api`) || PathPrefix(`/command`) || PathPrefix(`/sync`) || PathPrefix(`/public`)"
```
- Requests matching `_traefik_api_endpoint` use `traefik_middleware_api` (which excludes Authelia).
- All other requests (e.g. root `/`) route through `authelia@docker`.

### 4.3. Authelia Access Control Rules (ACL)
You can also configure bypasses directly inside Authelia in `localhost.yml`:
```yaml
authelia_role_access_control_rules:
  # Bypass specific regex path on a domain:
  - domain: "qbittorrent.{{ user.domain }}"
    resources:
      - "^/api/.*$"
      - "^/public/.*$"
    policy: bypass

  # Default rule for remainder of domain:
  - domain:
      - "*.{{ user.domain }}"
      - "{{ user.domain }}"
    policy: one_factor
```
Authelia evaluates rules sequentially from top to bottom and applies `policy: bypass` to matching resources without requiring login.
