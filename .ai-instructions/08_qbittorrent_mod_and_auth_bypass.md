# 08. qBittorrent Mod, Upstream Inheritance & Authentication Bypass

This guide details the architecture of the custom `qbittorrent` mod role (`/opt/saltbox_mod/roles/qbittorrent`), how it inherits from upstream Saltbox while avoiding code duplication, how it supports both the default and hotio Docker images, and how authentication bypass works across qBittorrent, Traefik, and Authelia.

> Rewritten 2026-09-22. Mid-rewrite, a rushed/contaminated test (concurrent
> rapid iteration, a duplicate-key bug) produced a false conclusion that
> `WebUI\*` settings must be applied via the qBittorrent API instead of
> `ini_file`, and the role was briefly built around that. A clean, controlled
> re-test (stop -> single clean edit -> start, verified byte-for-byte) proved
> that conclusion wrong: plain `ini_file` edits applied while the container is
> stopped persist reliably, exactly as upstream's own tasks already assume.
> The role below uses `ini_file` throughout - no API calls. Kept as a
> cautionary note for future debugging: if something here looks like it
> "doesn't persist," verify with an isolated, single-variable test before
> concluding the mechanism is broken - see § 4 for what that test looked like.

---

## 1. Upstream Inheritance & Code Minimization Architecture

Rather than maintaining a duplicate copy of Saltbox's upstream qBittorrent role, `/opt/saltbox_mod/roles/qbittorrent` imports upstream's task files directly:

1. **Pure pass-through subtasks - symlinked** (byte-identical to upstream, no mod logic needed):
   - `tasks/subtasks/host_installs.yml -> /srv/git/saltbox/roles/qbittorrent/tasks/subtasks/host_installs.yml`
   - `tasks/subtasks/hosts.yml -> /srv/git/saltbox/roles/qbittorrent/tasks/subtasks/hosts.yml`
   - `tasks/subtasks/legacy.yml -> /srv/git/saltbox/roles/qbittorrent/tasks/subtasks/legacy.yml`
   - `templates/qbittorrent.service.j2`, `templates/qbittorrent.yml.j2` (host-install-only templates; symlinked for completeness even though this mod doesn't use host-install mode)

2. **Pre-install / post-install - local wrapper files that chain upstream + our own settings**:
   - `tasks/subtasks/pre-install/main.yml` -> `include_tasks` upstream's own file (absolute path) then, only `when: qbittorrent_role_paths_conf_stat.stat.exists` (redeploys), includes `../mod_settings.yml`.
   - `tasks/subtasks/post-install/main.yml` -> a local re-implementation of upstream's wait/stop/settings/start sequence (Docker-only, host-install branches dropped). It can't just import upstream's file directly: upstream's own post-install/main.yml does `include_tasks: "settings/main.yml"`, a *relative* reference that resolves against upstream's own directory when included that way - which would silently skip our mod settings.
   - `tasks/subtasks/post-install/settings/main.yml` -> `include_tasks` upstream's settings file (absolute path) then unconditionally includes `../../mod_settings.yml`.
   - `tasks/subtasks/mod_settings.yml` -> the actual mod-specific `ini_file` tasks, shared by both call sites above (see § 3).

   This mirrors upstream's own timing exactly: settings are written to `qBittorrent.conf` *before* the container (re)starts, via the same `ini_file` module upstream's own tasks use.

3. **Docker-only**: `qbittorrent_role_host_install` is always `false` for this mod; upstream's host-install (bare-metal `qbittorrent-nox`) code path is intentionally not wired up here. Use the upstream saltbox role directly (`sb install qbittorrent`) if you need that.

4. **Isolated mod logic** (genuinely mod-specific, not upstream pass-through):
   - `tasks/main2.yml`: orchestrates DNS, port claim, mod variable overrides, data-layout normalization, directory creation, pre/post-install, alt WebUI.
   - `tasks/subtasks/mod_var_overrides.yml`: forces `_mod`-suffixed paths and the unified volume list to actually win - see § 1.1, this is not optional boilerplate.
   - `tasks/subtasks/mod_settings.yml`: the auth-bypass/reverse-proxy `ini_file` settings - see § 3.
   - `tasks/subtasks/data_layout.yml`: one-time safety-net migration for a legacy on-disk layout (see § 2.2).
   - `tasks/subtasks/alt_webui.yml`: downloads/extracts a third-party WebUI (e.g. VueTorrent), then does its own brief stop -> enable via `ini_file` -> start cycle (it needs to run after the files are on disk, so it can't share the pre/post-install timing above).

### 1.1. Why `mod_var_overrides.yml` exists: Saltbox's global variable pre-load

Saltbox's `pre_tasks` role (`/srv/git/saltbox/roles/pre_tasks/tasks/subtasks/variables.yml`) unconditionally globs **every** role under `/srv/git/saltbox/roles/*/defaults` and loads them all via `include_vars`, on every single playbook run - regardless of which roles are actually in that play. `include_vars` sits at a *higher* Ansible variable-precedence tier than any role's own `defaults/main.yml`.

Since this mod deliberately reuses upstream's exact `qbittorrent_role_*` variable names, upstream's own `qbittorrent_role_paths_folder: "{{ qbittorrent_name }}"` (no `_mod`) and `qbittorrent_role_docker_volumes_default` (plain single `/config` mount) get loaded this way too - and silently win over this role's `defaults/main.yml` for those same names, no matter what this repo says. `localhost.yml` (host_vars) is loaded by the same `pre_tasks` step, right after the role-defaults loop, so an explicit user override there still correctly wins - it's only this role's own *built-in* defaults that lose, for any variable name it shares with upstream.

`mod_var_overrides.yml` works around this with `set_fact` (a higher-still precedence tier) for exactly the variables where this role's intended value differs from upstream's: `qbittorrent_role_paths_folder`, `qbittorrent_role_paths_folders_list`, and `qbittorrent_role_docker_volumes`. It runs first thing in `main2.yml`, before anything else in the role reads those values.

This was diagnosed live on 2026-09-22 by adding a temporary debug task that printed `lookup('role_var', '_paths_folder', role='qbittorrent')` and the raw `qbittorrent_role_paths_folder` fact side by side - the role_var lookup returned `qbittorrent_mod` as expected, but the raw fact (and therefore anything derived from it, like the docker volumes) came back as plain `qbittorrent`, matching upstream's un-suffixed default exactly. This one is real and confirmed - unlike the API detour in § 4, this diagnosis held up under a clean re-test.

---

## 2. Key Features of the Mod Role

### 2.1. Isolated Paths Suffix (`_mod`)
In `defaults/main.yml`:
```yaml
qbittorrent_role_paths_folder: "{{ qbittorrent_name }}_mod"
qbittorrent_role_paths_location: "{{ server_appdata_path }}/{{ qbittorrent_role_paths_folder }}"
```
For instance `qbittorrent`, AppData resides at `/opt/qbittorrent_mod`. For instance `qbittorrent2`, at `/opt/qbittorrent2_mod`. This guarantees zero collision with upstream Saltbox's own `/opt/qbittorrent{,2,...}` data.

Note this only isolates **data**. The Docker **container name** is still just `{{ qbittorrent_name }}` (e.g. `qbittorrent`), matching upstream's own convention - so installing this mod's `qbittorrent` instance will replace a running upstream `qbittorrent` container (or vice versa). You cannot run both at once under the same instance name, but switching between them never touches the other's data directory.

### 2.2. Unified Volume Layout for Both Image Families
The default (`saltydk/qbittorrent`) and hotio (`ghcr.io/hotio/qbittorrent`) images expect different container-side paths - the default image wants a single `/config` directory; hotio wants `/config/config` (app profile) and `/config/data` (session/runtime state) split apart. Older versions of this role handled that by literally moving/copying files between two different **host** layouts whenever you switched images.

This version instead keeps the **host** layout identical for both image families - always:
- `{{ paths_location }}/qBittorrent` - the app profile / conf directory
- `{{ paths_location }}/data` - session/runtime data (BT_backup, GeoDB, rss, network_state.conf, ...)

and only changes which **container path** each is mounted at, based on `qbittorrent_role_is_hotio` (auto-detected from `qbittorrent_role_docker_image_repo`):

| | hotio | default (saltydk) |
|---|---|---|
| `{{ paths_location }}/qBittorrent` | `/config/config` | part of `/config` (whole dir mounted) |
| `{{ paths_location }}/data` | `/config/data` | `/config/qBittorrent/data` (mounted over the default image's own nested data dir) |

So switching `qbittorrent_role_docker_image_repo` and redeploying is just a container recreate with a different volume list - **no file copying, no data duplication, no risk of a partial/failed migration**. `qBittorrent.conf` itself always lives at the same host path (`{{ paths_location }}/qBittorrent/qBittorrent.conf`) regardless of image, so `qbittorrent_role_paths_conf` never changes either.

`tasks/subtasks/data_layout.yml` is only a one-time safety net: if it finds data left nested under the *old* pre-rewrite layout (`{{ paths_location }}/qBittorrent/data`) and nothing has claimed the canonical `{{ paths_location }}/data` yet, it moves (not copies) it into place. On a fresh instance this is a no-op.

### 2.3. Automated Third-Party WebUI (e.g. VueTorrent)
Controlled by gated flag `qbittorrent_role_alt_webui_enabled`. `alt_webui.yml` downloads/extracts the release into `{{ paths_location }}/webui` (bound to `/config/webui`), then stops the container, sets `WebUI\AlternativeUIEnabled=true` and `WebUI\RootFolder` via `ini_file`, and starts it back up.

---

## 3. Auth-Bypass / Reverse-Proxy Settings (`mod_settings.yml`)

`tasks/subtasks/mod_settings.yml` is a small, shared `ini_file` task list (imported by both pre-install and post-install/settings - see § 1) that sets:

- `WebUI\LocalHostAuth` - `false` when `qbittorrent_role_auth_bypass_enabled`, else `true`.
- `WebUI\AuthSubnetWhitelistEnabled` / `WebUI\AuthSubnetWhitelist` - the bypass toggle and CIDR list (`qbittorrent_role_auth_subnet_whitelist`).
- `WebUI\ReverseProxySupportEnabled` / `WebUI\TrustedReverseProxiesList` - trust `X-Forwarded-For` from `qbittorrent_role_reverse_proxies_list` (default: `172.19.0.0/16`, the `saltbox` docker network) to resolve the real client IP for the whitelist check above, instead of Traefik's own container IP.

**Username/password are intentionally left alone here.** Upstream's own post-install (`Generate Password Hash`, fresh installs only) already sets `WebUI\Username` to `user.name` and the password hash from `user.pass`, and that persists correctly (§ 4). Resetting it on every redeploy would silently overwrite a password the user changed by hand via the WebUI - upstream's own design avoids that, and so does this mod.

### > [!CAUTION] Never set the whitelist to `0.0.0.0/0, ::/0`
This role's Traefik labels define **two** routers per instance:
- `qbittorrent` / `qbittorrent-http` - the main WebUI, gated by `authelia@docker`.
- `qbittorrent-api` / `qbittorrent-api-http` - `PathPrefix(/api) || /command || /query || /login || /sync`, which **intentionally bypasses Authelia** (`qbittorrent_role_traefik_api_enabled`) so `*arr` apps and other automation can talk to qBittorrent's API using qBittorrent's own credentials.

Both routers forward to the **same qBittorrent process**, which cannot tell them apart. If the auth-subnet whitelist is widened to `0.0.0.0/0, ::/0`, qBittorrent's own login stops being enforced on the `-api` router too - and since Authelia isn't in front of that router either, the API (including creating a session without a password) becomes reachable by anyone on the internet.

Keep the whitelist scoped to real internal/VPN ranges only. This mod's default (`qbittorrent_role_auth_subnet_whitelist: "172.19.0.0/16"`) only ever bypasses the login for requests Traefik itself made (i.e. already-Authelia-authenticated browser sessions hitting the main router) - it deliberately does **not** widen to cover arbitrary public client IPs, because there is no static CIDR that could safely do that without also opening the `-api` router.

### Enabling in `localhost.yml`
```yaml
qbittorrent_role_auth_bypass_enabled: true
# Optionally widen beyond Traefik's own network to your LAN/VPN ranges:
qbittorrent_role_auth_subnet_whitelist: "192.168.1.0/24, 10.0.0.0/8, 172.19.0.0/16"
```

---

## 4. `ini_file` while stopped *does* persist - how this was actually verified

Earlier in this rewrite, a test that appeared to show `ini_file` edits not persisting (leading to a since-reverted API-based `webui_settings.yml`) turned out to be contaminated: a duplicate-key bug from a broken regex, plus several restarts happening in quick succession while other things were being tested at the same time. The clean re-test, done in isolation:

1. `docker ps -a` confirmed the container fully `Exited` before touching the conf file.
2. A single `sed -i` in-place edit of one key (verified with `grep -c` that exactly one line existed afterward, and that file ownership was untouched).
3. `docker start`, then re-read the same key straight back out of the conf file.

Done this way, every setting tested - `WebUI\Password_PBKDF2`, `WebUI\AuthSubnetWhitelist`, `WebUI\AlternativeUIEnabled`, `WebUI\ReverseProxySupportEnabled` - persisted exactly as written, and a fresh login with a manually-set password succeeded. This matches upstream's own long-standing assumption (all of its settings tasks use plain `ini_file` around a stop/start), and it's why this role does the same rather than reaching for the API.

**Takeaway for future debugging**: if a setting "isn't sticking" here, suspect the test methodology (concurrent redeploys, an editor script leaving a duplicate key, editing the wrong file) before suspecting `ini_file`/qBittorrent itself. Re-run the isolated three-step test above before changing the mechanism.

---

## 5. Traefik & Authelia Routing Patterns

### 5.1. Entire App Open vs Behind Authelia
Every role defines `{{ role_name }}_role_traefik_sso_middleware` (default `authelia@docker`).
```yaml
qbittorrent_role_traefik_sso_middleware: ""   # removes Authelia from the whole app
```

### 5.2. Keep App Behind Authelia, But Open Part of the URL (Path Bypass)
```yaml
qbittorrent_role_traefik_api_enabled: true
qbittorrent_role_traefik_api_endpoint: "PathPrefix(`/api`) || PathPrefix(`/command`) || PathPrefix(`/sync`) || PathPrefix(`/public`)"
```
Requests matching this rule use `traefik_middleware_api` (no Authelia). Everything else routes through `authelia@docker`. This is the router qBittorrent's own auth-subnet whitelist must NOT be widened enough to cover (see § 3).

### 5.3. Authelia ACL Rules
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

## 6. Multiple Instances

This role natively supports Saltbox's [multiple-instances architecture](https://docs.saltbox.dev/reference/multiple-instances/) - see `.ai-instructions/07_multiple_instances_architecture.md` for the general mechanism. In `localhost.yml`:
```yaml
qbittorrent_instances: ["qbittorrent", "qbittorrent2"]

# Applies to all instances:
qbittorrent_role_docker_image_repo: "ghcr.io/hotio/qbittorrent"

# qbittorrent2 only (note: no "_role" segment for instance-scoped overrides):
qbittorrent2_docker_image_repo: "saltydk/qbittorrent"
qbittorrent2_alt_webui_enabled: true
```
Every path, container name, DNS record, and Traefik router is keyed off `qbittorrent_name` (the per-instance loop variable), and `qbittorrent_role_paths_folder` always appends `_mod`, so `qbittorrent2` gets its own isolated `/opt/qbittorrent2_mod`.
