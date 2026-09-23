# AI Quota Dashboard — Technical Service Documentation

**App Name**: `ai_quota_dashboard`  
**Author**: `hereisderek`  
**Upstream Repository**: [https://github.com/hereisderek/ai-quota-dashboard](https://github.com/hereisderek/ai-quota-dashboard)  
**Image**: `ghcr.io/hereisderek/ai-quota-dashboard:latest` (`:beta` for prereleases)  
**Role Path**: `/opt/saltbox_mod/roles/ai_quota_dashboard`  

---

## 1. Key Configurations

| Parameter | Default | Description |
|---|---|---|
| **Subdomain** | `ai-quota` | `https://ai-quota.<yourdomain.tld>` |
| **Internal Web Port** | `3456` | Container port forwarded by Traefik (no host port bound) |
| **Data Volume** | `/opt/ai_quota_dashboard/data:/data` | `quota.db` (SQLite), `accounts.json`, plugins |
| **PUBLIC_URL** | role `_web_url` | Used for OAuth redirect callbacks |
| **SSO Protection** | Enabled | `traefik_default_sso_middleware` (Authelia) |

The image runs as the `node` user (UID 1000); the host data dir must be writable by UID 1000.

## 2. Migrating Existing Data

`/data` may start empty (app bootstraps it). To bring an existing instance over, take a consistent SQLite snapshot (the DB runs in WAL mode) and copy the rest of the folder:

```bash
sqlite3 data/quota.db ".backup '/tmp/aiq/quota.db'"
rsync -a --exclude 'quota.db*' data/ /tmp/aiq/
rsync -a /tmp/aiq/ saltbox:/opt/ai_quota_dashboard/data/
```

## 3. Host Inventory Overrides

In `/srv/git/saltbox/inventories/host_vars/localhost.yml` *(requires explicit approval)*:

```yaml
ai_quota_dashboard_role_docker_image_tag: "beta"
ai_quota_dashboard_role_docker_envs_custom:
  POLL_INTERVAL_SECONDS: "120"
  DATA_RETENTION_DAYS: "30"
  # Drop Authelia and rely on the app's own login:
# ai_quota_dashboard_role_traefik_sso_middleware: ""
```

## 4. Deployment

```bash
sb install mod-ai-quota-dashboard
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags ai-quota-dashboard
```
