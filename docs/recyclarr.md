# Recyclarr — Technical Service Documentation

**App Name**: `recyclarr`
**Deployment Source**: Sandbox community role (`/opt/sandbox/roles/recyclarr`, author `BeansIsFat`) — **not** a `saltbox_mod`-authored role. This doc lives here purely as this host's reference notes; there is no corresponding role under `/opt/saltbox_mod/roles`.
**Upstream Project**: [https://github.com/recyclarr/recyclarr](https://github.com/recyclarr/recyclarr) · [https://recyclarr.dev](https://recyclarr.dev)
**Image**: `ghcr.io/recyclarr/recyclarr:8` (running `8.3.2` as of writing)
**Host Config Path**: `/opt/recyclarr` (bind-mounted to `/config` in the container)

---

## 1. What it does

Recyclarr automatically syncs [TRaSH Guides](https://trash-guides.info/) custom formats, quality profiles, and quality-size definitions into Radarr/Sonarr via their APIs. It runs once via its own internal cron (`CRON_SCHEDULE=@daily` env var, set by the Sandbox role) and can also be triggered manually.

## 2. Inventory Overrides (`localhost.yml`)

The Sandbox role's own default only mounts `{{ recyclarr_role_paths_location }}:/config` (i.e. `/opt/recyclarr:/config`, everything in one place). This host overrides that to spread cache/logs/repositories onto the SSD cache tier per this repo's [storage tiering standard](../AGENTS.md#3-media-library-mnt--storage-tiering-standards):

```yaml
## recyclarr
# NOTE: /config/cache must stay on the same filesystem as /config itself - Recyclarr 8's
# startup migration renames files from /config/cache into /config/state and /config/resources,
# which fails with "Cross-device link" if /config/cache is a separate mount. See § 5.
recyclarr_role_paths_folders_list_custom:
 - "{{ app_cache_dir }}/repositories"
 - "{{ app_log_dir }}"
recyclarr_role_docker_volumes_custom:
 - "{{ app_cache_dir }}/repositories:/config/repositories"
 - "{{ app_log_dir }}:/config/logs"
```

> [!NOTE]
> `/config/cache` (and therefore `/config/state` + `/config/resources`) is **not** mapped to a separate mount — it's left inside the default `/opt/recyclarr:/config` mount on purpose. See § 5 for why. `/config/logs` and `/config/repositories` are unrelated to the migration and stay split onto the SSD cache tier as before.

## 3. Application Config (`recyclarr.yml`)

Recyclarr's own YAML config (not Ansible) lives at `/opt/recyclarr/recyclarr.yml`, with secrets factored out into `/opt/recyclarr/secrets.yml` and referenced via `!secret <name>`:

```yaml
sonarr:
  series:
    base_url: !secret sonarr_url   # http://sonarr:8989
    api_key: !secret key
radarr:
  movies:
    base_url: !secret radarr_url   # http://radarr:7878
    api_key: !secret key
```

`secrets.yml` already points at this host's actual `sonarr`/`radarr` containers (Docker network hostnames, since Recyclarr shares the `saltbox` network) and its `key:` value matches both apps' real `<ApiKey>` from their respective `/opt/{sonarr,radarr}/config.xml` — **confirmed by diff, values not otherwise reproduced here.** No change was needed there; it was already wired up correctly.

The config defines custom quality-size limits (targeting 1080p as the sweet spot, 2160p heavily penalized) and custom-format scoring (AV1/x265 preferred over x264, remux/BR-DISK/3D blocked, lossless audio penalized) — see `/opt/recyclarr/AI_INSTRUCTIONS.md` and `/opt/recyclarr/CONFIGURATION_SUMMARY.md` on the host for the full rationale already written up there.

`radarr4k_url` / `sonarr4k_url` secrets exist for a possible future 4K instance pair but nothing currently references them — only `radarr` and `sonarr` containers exist on this host.

## 4. Manual Sync

```bash
docker exec -ti recyclarr recyclarr sync            # apply
docker exec -ti recyclarr recyclarr sync --preview   # dry run, no API writes
```

## 5. Known Issue: Cross-Device Migration Failure (found 2026-09-26)

**Symptom**: every Recyclarr invocation — including the daily cron sync — fails immediately, before doing anything useful:

```
Error: Migration step failed: Move cache directory to state
Error: Reason: Cross-device link
Error:   - Ensure Recyclarr has permission to read/write /config/cache and /config/state
Error:   - Manually move /config/cache/sonarr and /config/cache/radarr to /config/state
Error:   - Manually move /config/cache/resources to /config/resources
Error:   - Delete /config/cache after moving contents
```

**Root cause**: Recyclarr 8 moved its cached repo clones from `/config/cache/*` to `/config/state/*` and `/config/resources/*`. It does this move with a plain filesystem `rename()`, which only works within a single filesystem/device. This host's `recyclarr_role_docker_volumes_custom` (§ 2) bind-mounts `/config/cache` from a *different* underlying mount (`{{ app_cache_dir }}/cache`, on the SSD cache tier) than `/config` itself (`/opt/recyclarr`), so the rename hits `EXDEV` and the migration aborts every time.

**Confirmed impact**: the daily cron sync (`@daily`) had been failing silently since at least 2026-09-24 — `docker logs recyclarr` showed the same error on every scheduled run, so no quality-profile/custom-format changes from TRaSH Guides had been landing in Radarr/Sonarr since then.

### Status: FIXED 2026-09-26

**Remediation log** (all commands run against `saltbox.local`, root where noted):

1. Copied the orphaned resources cache onto the same filesystem as `/config`, verified byte-identical before deleting anything:
   ```bash
   mkdir -p /opt/recyclarr/resources
   cp -a /media/cache/cache/recyclarr/cache/resources/. /opt/recyclarr/resources/
   diff -rq /media/cache/cache/recyclarr/cache/resources /opt/recyclarr/resources
   # -> COPY VERIFIED IDENTICAL
   ```
2. Removed the now-migrated leftover directory (listed its full contents first — only the cloned `trash-guides`/`config-templates` git repos, already copied and verified above):
   ```bash
   rm -rf /media/cache/cache/recyclarr/cache
   ```
3. Removed the `/config/cache` line from `recyclarr_role_paths_folders_list_custom` and `recyclarr_role_docker_volumes_custom` in **both**:
   - `/srv/git/saltbox/inventories/host_vars/localhost.yml` (the deployed file — edited directly, other unrelated pending diffs in that file were left untouched)
   - this repo's mirrored copy, `proxmox-services/docs/localhost.yml` (symlinked in as `saltbox_mod/localhost.yml`)
4. Recreated the container with the new volume list. `sudo sb install recyclarr` doesn't resolve (that tag belongs to Saltbox proper); the correct tag for a Sandbox-sourced role is `sandbox-<role>`:
   ```bash
   sudo sb install sandbox-recyclarr
   # -> Playbook /opt/sandbox/sandbox.yml executed successfully.
   ```
5. Verified the new mounts (`/config/cache` no longer a separate bind — `/config` is once again a single `/opt/recyclarr` mount, only `logs` and `repositories` still split onto the cache tier) and ran a dry-run sync:
   ```bash
   docker exec recyclarr recyclarr sync --preview
   # -> Migrate: Move cache directory to state        (no error this time)
   # -> movies: Processing Radarr server movies ... Completed
   # -> series: Processing Sonarr server series ... Completed
   ```
   (`--preview` = dry run, no writes to Radarr/Sonarr. The existing `@daily` cron will perform the first real sync automatically.)

**One pre-existing, unrelated warning noticed during verification** (not fixed, not blocking): `recyclarr.yml` still sets `replace_existing_custom_formats: true` under both `sonarr:` and `radarr:`, which Recyclarr 8 deprecated and now ignores (`[WRN] [DEPRECATED] The 'replace_existing_custom_formats' option has been removed...`, see [upgrade guide](https://recyclarr.dev/guide/upgrade-guide/v8.0/#replace-existing-removed)). Harmless no-op today; worth pruning from `/opt/recyclarr/recyclarr.yml` next time that file is touched.
