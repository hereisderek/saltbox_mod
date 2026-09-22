# qBittorrent Mod — Technical Service Documentation

**App Name**: `qbittorrent`  
**Author**: `hereisderek` (modifications), `salty` (upstream role)  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Upstream Repository**: [https://github.com/saltyorg/Saltbox](https://github.com/saltyorg/Saltbox)  
**Role Path**: `/opt/saltbox_mod/roles/qbittorrent`  

---

## 1. Overview & Architecture

The `qbittorrent` mod role enhances Saltbox's upstream qBittorrent role while maximizing upstream synchronization and zero code duplication through upstream task inclusion and template symlinking:
- **Upstream Inheritance**: Directly includes upstream subtasks (`hosts.yml`, `host_installs.yml`, `legacy.yml`, `post-install/main.yml`) and symlinks templates (`qbittorrent.yml.j2`, `qbittorrent.service.j2`), ensuring upstream fixes and enhancements are inherited automatically.
- **Isolated Mod Storage**: Automatically appends `_mod` to `qbittorrent_role_paths_folder` (`/opt/qbittorrent_mod`, `/opt/qbittorrent2_mod`), preventing filesystem conflicts with upstream Saltbox's `/opt/qbittorrent`.
- **Multiple Instances**: Full support for Saltbox multi-app instances (`qbittorrent_instances: ["qbittorrent", "qbittorrent2", ...]`) with isolated AppData directories, ports, and WebUIs.
- **Hotio Base Image**: Native support for `ghcr.io/hotio/qbittorrent` with auto-detected volume mappings (`/config/config` and `/config/data`) and automatic layout migration of `BT_backup`.
- **Alternative WebUI (VueTorrent)**: Gated automated download, extraction, mounting, and configuration of third-party WebUIs.
- **Authentication Bypass**: Configurable bypass of qBittorrent's internal login verification for requests arriving through Traefik and protected by Authelia.

---

## 2. Key Configurations & Default Values

| Parameter | Default Value | Description |
|---|---|---|
| `qbittorrent_instances` | `["qbittorrent"]` | List of instances to deploy |
| `qbittorrent_role_paths_folder` | `"{{ qbittorrent_name }}_mod"` | Storage directory under `/opt` (`/opt/qbittorrent_mod`) |
| `qbittorrent_role_docker_image_repo` | `saltydk/qbittorrent` | Docker image repo (can be overridden to `ghcr.io/hotio/qbittorrent`) |
| `qbittorrent_role_alt_webui_enabled` | `false` | Enable automated third-party WebUI installation |
| `qbittorrent_role_alt_webui_url` | `https://github.com/VueTorrent/VueTorrent` | GitHub repo or archive download URL |
| `qbittorrent_role_alt_webui_dir` | `"{{ paths_location }}/webui"` | Host path for extracted WebUI |
| `qbittorrent_role_auth_bypass_enabled` | `false` | Disable qBittorrent login prompt behind reverse proxy |
| `qbittorrent_role_auth_subnet_whitelist` | `"0.0.0.0/0, ::/0"` | Subnets allowed to bypass qBittorrent authentication |
| `qbittorrent_role_traefik_sso_middleware` | `"authelia@docker"` | SSO protection middleware |
| `qbittorrent_role_traefik_api_enabled` | `true` | Enable dedicated unauthenticated API router |
| `qbittorrent_role_traefik_api_endpoint` | `PathPrefix(/api)...` | Paths that bypass Authelia SSO |

---

## 3. Host Inventory Overrides (`localhost.yml`)

### 3.1. Using the Hotio Image
```yaml
# Use Hotio base image with automated volume mapping
qbittorrent_role_docker_image_repo: "ghcr.io/hotio/qbittorrent"
```

### 3.2. Enabling Alternative WebUI (VueTorrent)
```yaml
qbittorrent_role_alt_webui_enabled: true
qbittorrent_role_alt_webui_url: "https://github.com/VueTorrent/VueTorrent"
```

### 3.3. Disabling qBittorrent Login Behind Authelia
Because Authelia already authenticates traffic at the reverse proxy gateway, enabling authentication bypass eliminates the redundant secondary login prompt:
```yaml
qbittorrent_role_auth_bypass_enabled: true
# Optional: restrict to internal networks:
# qbittorrent_role_auth_subnet_whitelist: "192.168.1.0/24, 10.0.0.0/8, 172.19.0.0/16"
```

### 3.4. Multiple Instances Configuration
```yaml
# Deploy two independent instances
qbittorrent_instances:
  - "qbittorrent"
  - "qbittorrent2"

# Specific overrides for second instance
qbittorrent2_alt_webui_enabled: true
qbittorrent2_auth_bypass_enabled: true
qbittorrent2_docker_image_repo: "ghcr.io/hotio/qbittorrent"
```

---

## 4. Traefik & Authelia Authentication Control

### 4.1. Disable Authelia for the Entire Application
To remove Authelia from the main web router and make the entire subdomain public:
```yaml
qbittorrent_role_traefik_sso_middleware: ""

# Or for a secondary instance:
qbittorrent2_traefik_sso_middleware: ""
```

### 4.2. Keep Application Behind Authelia, But Open Specific Paths (API / Webhooks)
Saltbox automatically configures a dedicated Traefik API router (`<role>-api`) using `traefik_middleware_api` (which excludes Authelia). To expose specific URL endpoints publicly:
```yaml
qbittorrent_role_traefik_api_enabled: true
qbittorrent_role_traefik_api_endpoint: "PathPrefix(`/api`) || PathPrefix(`/sync`) || PathPrefix(`/public`)"
```

### 4.3. Manage Bypasses at the Authelia Level (ACL Rules)
If you prefer Authelia to manage the path rules:
```yaml
authelia_role_access_control_rules:
  # Bypass specific regex paths on the subdomain
  - domain: "qbittorrent.{{ user.domain }}"
    resources:
      - "^/api/.*$"
      - "^/public/.*$"
    policy: bypass

  # Default rule for remainder of domain
  - domain:
      - "*.{{ user.domain }}"
      - "{{ user.domain }}"
    policy: one_factor
```

---

## 5. Deployment & Verification

Run the playbook via `saltbox_mod`:
```bash
sudo /srv/ansible/venv/bin/ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags qbittorrent
```

Inspect the container and configuration:
```bash
docker ps --filter "name=qbittorrent"
cat /opt/qbittorrent_mod/qBittorrent/qBittorrent.conf
```
