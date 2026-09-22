# qBittorrent Mod — Technical Service Documentation

**App Name**: `qbittorrent`
**Author**: `hereisderek` (modifications), `salty` (upstream role)
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)
**Upstream Repository**: [https://github.com/saltyorg/Saltbox](https://github.com/saltyorg/Saltbox)
**Role Path**: `/opt/saltbox_mod/roles/qbittorrent`

> Rewritten 2026-09-22. See `.ai-instructions/08_qbittorrent_mod_and_auth_bypass.md` for the full architectural writeup this doc summarizes.

---

## 1. Overview & Architecture

The `qbittorrent` mod role deploys qBittorrent independently of upstream Saltbox's own `/opt/saltbox` qbittorrent role, sharing as much of upstream's task logic as possible:

- **Upstream Inheritance**: pure pass-through subtasks (`hosts.yml`, `host_installs.yml`, `legacy.yml`) are symlinked; `pre-install`/`post-install` are local wrapper files that import upstream's own tasks (absolute path) and then chain this mod's own settings on top — see § 6.
- **Docker-only**: upstream's host-install (bare-metal `qbittorrent-nox`) mode is not supported by this mod.
- **Isolated Mod Storage**: `qbittorrent_role_paths_folder` always appends `_mod` (`/opt/qbittorrent_mod`, `/opt/qbittorrent2_mod`), preventing collisions with upstream Saltbox's own `/opt/qbittorrent{,2,...}` data. Note this only isolates *data* — the Docker *container name* matches upstream's convention (`qbittorrent`), so the two can't run at the same time under the same instance name.
- **Multiple Instances**: full support for Saltbox's multi-instance architecture (`qbittorrent_instances: ["qbittorrent", "qbittorrent2", ...]`) — see `.ai-instructions/07_multiple_instances_architecture.md`.
- **Both Docker image families, one host layout**: `saltydk/qbittorrent` (default) and `ghcr.io/hotio/qbittorrent` are both supported, auto-detected from `qbittorrent_role_docker_image_repo`. Both are mounted from the *same* two host directories (`{{ paths_location }}/qBittorrent` and `{{ paths_location }}/data`) — only the container-side mount path differs — so switching images is just a container recreate, never a data migration.
- **Alternative WebUI (VueTorrent)**: gated automated download, extraction, and enabling of a third-party WebUI.
- **Authentication Bypass**: qBittorrent's own login can be bypassed for requests already authenticated by Traefik + Authelia, scoped to trusted networks only (see § 4 — **never** widen this to all IPs, it would also unlock the Authelia-bypassed API router).
- **All settings applied via plain `ini_file`**, same mechanism upstream's own tasks use — written to `qBittorrent.conf` while the container is stopped, immediately before it (re)starts. See § 6 for why this is reliable (it was mid-rewrite briefly assumed *not* to be, based on a contaminated test — corrected after a clean re-test).

---

## 2. Key Configurations & Default Values

| Parameter | Default Value | Description |
|---|---|---|
| `qbittorrent_instances` | `["qbittorrent"]` | List of instances to deploy |
| `qbittorrent_role_paths_folder` | `"{{ qbittorrent_name }}_mod"` | Storage directory under `/opt` (`/opt/qbittorrent_mod`) |
| `qbittorrent_role_paths_data_location` | `"{{ paths_location }}/data"` | Canonical, image-agnostic session/runtime data directory |
| `qbittorrent_role_docker_image_repo` | `saltydk/qbittorrent` | Docker image repo (can be overridden to `ghcr.io/hotio/qbittorrent`) |
| `qbittorrent_role_is_hotio` | auto-detected | `true` when `hotio` appears in the image repo |
| `qbittorrent_role_alt_webui_enabled` | `false` | Enable automated third-party WebUI installation |
| `qbittorrent_role_alt_webui_url` | `https://github.com/VueTorrent/VueTorrent` | GitHub repo or archive download URL |
| `qbittorrent_role_alt_webui_dir` | `"{{ paths_location }}/webui"` | Host path for extracted WebUI |
| `qbittorrent_role_auth_bypass_enabled` | `false` | Bypass qBittorrent's own login prompt for whitelisted, reverse-proxied requests |
| `qbittorrent_role_auth_subnet_whitelist` | `"172.19.0.0/16"` | Subnets allowed to bypass qBittorrent authentication — **do not set to `0.0.0.0/0, ::/0`**, see § 4 |
| `qbittorrent_role_reverse_proxy_enabled` | `true` | Trust `X-Forwarded-For` from the subnet below to resolve the real client IP |
| `qbittorrent_role_reverse_proxies_list` | `"172.19.0.0/16"` | The `saltbox` docker network, where Traefik lives |
| `qbittorrent_role_traefik_sso_middleware` | `"authelia@docker"` | SSO protection middleware |
| `qbittorrent_role_traefik_api_enabled` | `true` | Enable dedicated unauthenticated API router |
| `qbittorrent_role_traefik_api_endpoint` | `PathPrefix(/api)...` | Paths that bypass Authelia SSO |

Note: the WebUI username/password are **not** configurable through this mod — they're left entirely to upstream's own post-install step (`user.name` / `user.pass`, set once on first bootstrap). See § 6.

---

## 3. Host Inventory Overrides (`localhost.yml`)

### 3.1. Using the Hotio Image
```yaml
qbittorrent_role_docker_image_repo: "ghcr.io/hotio/qbittorrent"
```
No other changes needed — the volume list, conf path, and data path all resolve automatically.

### 3.2. Enabling Alternative WebUI (VueTorrent)
```yaml
qbittorrent_role_alt_webui_enabled: true
qbittorrent_role_alt_webui_url: "https://github.com/VueTorrent/VueTorrent"
```

### 3.3. Disabling qBittorrent Login Behind Authelia
Because Authelia already authenticates traffic at the reverse proxy gateway for the *main* WebUI router, enabling this eliminates the redundant secondary login prompt for that router:
```yaml
qbittorrent_role_auth_bypass_enabled: true
# Optionally widen beyond Traefik's own network to your LAN/VPN ranges:
qbittorrent_role_auth_subnet_whitelist: "192.168.1.0/24, 10.0.0.0/8, 172.19.0.0/16"
```
> [!CAUTION]
> Never set this to `0.0.0.0/0, ::/0`. See § 4 for why — the short version is that the `-api` Traefik router intentionally bypasses Authelia, and qBittorrent's own whitelist is the only thing still guarding it.

### 3.4. Multiple Instances Configuration
```yaml
qbittorrent_instances:
  - "qbittorrent"
  - "qbittorrent2"

# Instance-scoped overrides (note: no "_role" segment)
qbittorrent2_alt_webui_enabled: true
qbittorrent2_auth_bypass_enabled: true
qbittorrent2_docker_image_repo: "ghcr.io/hotio/qbittorrent"
```

---

## 4. Traefik & Authelia Authentication Control

### 4.1. Disable Authelia for the Entire Application
```yaml
qbittorrent_role_traefik_sso_middleware: ""
# Or for a secondary instance:
qbittorrent2_traefik_sso_middleware: ""
```

### 4.2. Keep Application Behind Authelia, But Open Specific Paths (API / Webhooks)
```yaml
qbittorrent_role_traefik_api_enabled: true
qbittorrent_role_traefik_api_endpoint: "PathPrefix(`/api`) || PathPrefix(`/sync`) || PathPrefix(`/public`)"
```
This router (`<instance>-api` / `<instance>-api-http`) uses `traefik_middleware_api`, which **excludes** Authelia, so `*arr` apps can hit qBittorrent's API with qBittorrent's own credentials. It forwards to the same backend process as the Authelia-gated main router — qBittorrent can't distinguish which Traefik router a request came through. This is exactly why `qbittorrent_role_auth_subnet_whitelist` must stay scoped to real internal/VPN CIDRs: widening it to all IPs would also disable qBittorrent's own auth on this already-Authelia-bypassed path, leaving the API open to the whole internet.

### 4.3. Manage Bypasses at the Authelia Level (ACL Rules)
```yaml
authelia_role_access_control_rules:
  - domain: "qbittorrent.{{ user.domain }}"
    resources:
      - "^/api/.*$"
      - "^/public/.*$"
    policy: bypass
  - domain:
      - "*.{{ user.domain }}"
      - "{{ user.domain }}"
    policy: one_factor
```

---

## 5. Deployment & Verification

```bash
sudo /srv/ansible/venv/bin/ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags qbittorrent
```

Inspect the container and configuration:
```bash
docker ps --filter "name=qbittorrent"
cat /opt/qbittorrent_mod/qBittorrent/qBittorrent.conf
```

Confirm the WebUI settings actually applied:
```bash
docker logs qbittorrent --tail 20   # should NOT show a temporary-password banner
grep -E "AuthSubnetWhitelist|ReverseProxySupportEnabled|AlternativeUIEnabled" /opt/qbittorrent_mod/qBittorrent/qBittorrent.conf
```

---

## 6. How settings actually get applied (and how that was verified)

All `WebUI\*` settings — auth-subnet whitelist, reverse-proxy trust, alt-WebUI enable, and (via upstream's own tasks) the password — are written into `qBittorrent.conf` with `community.general.ini_file` while the container is stopped, immediately before it's (re)started. This is the same mechanism upstream's own Saltbox role has always used.

Mid-rewrite, a test that appeared to show this *not* persisting led to briefly rebuilding this role around live API calls (`POST /api/v2/app/setPreferences`) instead. That test turned out to be contaminated — a duplicate-key bug from a broken regex, and several container restarts happening in quick succession while other things were being tested concurrently. A clean, isolated re-test settled it:

```bash
# 1. Confirm fully stopped
docker ps -a --filter name=qbittorrent --format "{{.Status}}"   # Exited

# 2. Single clean edit, verify exactly one line resulted
sed -i 's|^WebUI\\AuthSubnetWhitelist=.*|WebUI\\AuthSubnetWhitelist=10.99.99.0/24|' /opt/qbittorrent_mod/qBittorrent/qBittorrent.conf
grep -c "AuthSubnetWhitelist=" /opt/qbittorrent_mod/qBittorrent/qBittorrent.conf   # 1

# 3. Start, then re-read the same key
docker start qbittorrent
grep "AuthSubnetWhitelist=" /opt/qbittorrent_mod/qBittorrent/qBittorrent.conf   # matches what was written
```

Done this way, `WebUI\Password_PBKDF2`, `WebUI\AuthSubnetWhitelist`, `WebUI\AlternativeUIEnabled`, and `WebUI\ReverseProxySupportEnabled` all persisted exactly as written, and login with a manually-set password succeeded. **If a setting ever appears not to stick, suspect the test method (concurrent redeploys, a duplicate key, editing the wrong file) before suspecting `ini_file` — re-run the three-step test above in isolation first.**
