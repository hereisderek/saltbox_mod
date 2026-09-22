# Status

## Open Issues

- **Root can't write through `/mnt/unionfs` (Proxmox bind mount)**: `derek` (UID 1000, mapped 1:1 to the same host UID per the LXC's `lxc.idmap`) can write to `/mnt/unionfs/downloads/...` fine; `root` (mapped to host UID 100000, the standard unprivileged shift) gets `Permission denied` on the same paths, even after adding `root` to the `derek` group inside the container (confirmed via `id root` showing the membership, but writes still failed — Proxmox's `mp:` bind-mount idmap translation for this mount doesn't appear to honor supplementary groups the way a plain kernel bind mount would). Not resolved; worked around for deployment by pre-creating `/mnt/unionfs/downloads/torrents/qbittorrent_mod/{completed,incoming,watched,torrents}` as `derek` before running the playbook (Ansible's directory task is a no-op if the dir already has the right owner/group, so it never needs root to write there). If this comes up again for other roles/paths, it needs actual investigation on the Proxmox host side (`root@pve.local`, LXC 2010 `saltbox`), not another container-side workaround.
- Note: adding `root` to the `derek` group also briefly broke SSH key login for `derek` (sshd's `StrictModes` refuses when `$HOME` is group-writable by a group with more than one member). Fixed by `chmod g-w /home/derek` inside the LXC (via `pct exec`, since SSH was down) — this is a permanent, correct fix and doesn't need reverting.

## Resolved

### 2026-09-22 — qbittorrent_mod role rewritten from scratch

Context: the user backed up and deleted both `/opt/qbittorrent` (upstream) and `/opt/qbittorrent_mod` (this repo's instance) on the server, then asked for the mod role to be redone: import upstream's tasks directly (minimize drift), support both the default and hotio Docker images with correct mount handling, keep host folder structure stable under `/opt/qbittorrent_mod`, support multiple instances, and make sure the reverse-proxy auth-bypass whitelist actually works.

**What changed** (full writeup: [.ai-instructions/08_qbittorrent_mod_and_auth_bypass.md](.ai-instructions/08_qbittorrent_mod_and_auth_bypass.md), [docs/qbittorrent.md](docs/qbittorrent.md)):
- Pure pass-through upstream subtasks (`hosts.yml`, `host_installs.yml`, `legacy.yml`) are symlinked; `pre-install`/`post-install` are local wrapper files that import upstream's own tasks and chain this mod's settings on top, timed exactly like upstream's own tasks (write to `qBittorrent.conf` while stopped, immediately before start).
- Both Docker image families (`saltydk/qbittorrent` default, `ghcr.io/hotio/qbittorrent`) now mount from the *same* two host directories (`{{ paths_location }}/qBittorrent` and `{{ paths_location }}/data`) — switching images is just a container recreate, never a data migration.
- Auth-subnet whitelist stayed scoped to real internal ranges only (`172.19.0.0/16` = Traefik's docker network, by default) — **deliberately not** widened to `0.0.0.0/0`, since the `-api` Traefik router intentionally bypasses Authelia and qBittorrent's own whitelist is the only thing still guarding it.

**Root cause found mid-build (the reason the first deploy attempt silently used wrong paths)**: Saltbox's `pre_tasks` role unconditionally loads *every* role's `defaults/main.yml` under `/srv/git/saltbox/roles/*` via `include_vars` — a higher Ansible variable-precedence tier than any role's own defaults. Since this mod reuses upstream's exact `qbittorrent_role_*` variable names, upstream's un-suffixed `qbittorrent_role_paths_folder` (etc.) silently won over this role's own `_mod`-suffixed intent. Fixed with explicit `set_fact` overrides (`tasks/subtasks/mod_var_overrides.yml`) at a high enough precedence tier to actually stick. This diagnosis held up and is correct.

**A detour that turned out to be wrong, corrected same day**: while testing, `ini_file` edits appeared not to persist across a container restart, which led to briefly rebuilding the password/whitelist logic around live qBittorrent API calls instead. A clean, isolated re-test (confirm fully stopped → single verified edit → start → re-read) showed this was wrong — the original test was contaminated by a duplicate-key bug and several rapid, concurrent restarts. **Reverted back to plain `ini_file`**, matching upstream's own approach; the API-based `webui_settings.yml` was deleted. Full account of both the false lead and the correction in `.ai-instructions/08_...` § 4.

**Two real bugs found and fixed along the way** (independent of the above detour):
- `mod_var_overrides.yml` (above) — confirmed correct, kept.
- The `AuthSubnetWhitelist`/`ReverseProxySupportEnabled`/`AlternativeUIEnabled` `ini_file` tasks needed to actually be wired into the pre-install/post-install/alt-webui chain (they'd been dropped when those chains were temporarily rewritten to import upstream directly) — fixed by restoring local wrapper files (`pre-install/main.yml`, `post-install/main.yml`, `post-install/settings/main.yml`) plus a new shared `mod_settings.yml`.

**Final verified state**: `sb install mod-qbittorrent` (`ansible-playbook saltbox_mod.yml --tags qbittorrent`) completes with `failed=0`. Container up and stable, `WebUI\Username=derek`, `AuthSubnetWhitelistEnabled=true`, `ReverseProxySupportEnabled=true`, `AlternativeUIEnabled=true` (VueTorrent active), no temporary-password banner on restart. Public URL responds in ~0.3s.

### 2026-09-22 (earlier) — qbittorrent.hereisderek.dpdns.org inaccessible / "wrong password"

Superseded by the rewrite above. The live conf's `WebUI\Password_PBKDF2` wasn't sticking at the time, but (per the correction above) that was very likely due to the role's *broken variable resolution* (wrong paths, settings never actually applied where expected) rather than `ini_file` itself being unreliable. DNS/Traefik/container health were never the actual problem, despite the reported slowness — that lined up with redeploy churn during troubleshooting.

### qbittorrent settings in `localhost.yml` — mod vs. upstream ambiguity

`localhost.yml` is shared by both the upstream `/opt/saltbox` playbook and this repo's `/opt/saltbox_mod` playbook, and both deploy their own independent qBittorrent instance. There was no way to tell at a glance which `qbittorrent_*` variables belonged to which.

**Fix**: added a header comment above the qbittorrent block in `localhost.yml` (synced to both the local copy and `derek@saltbox.local:/srv/git/saltbox/inventories/host_vars/localhost.yml`) clarifying the convention already implied by the `role_var` lookup plugin: plain `qbittorrent_*` = upstream Saltbox's own instance, `qbittorrent_role_*` = this repo's (saltbox_mod) instance.
