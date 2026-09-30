# AI Instruction Note for Feishin

**App Name**: `feishin` | **Upstream**: https://github.com/jeffvli/feishin
Web client for Navidrome/Jellyfin/Subsonic servers. Stateless container, internal port `9180`, no volumes.
Configured via env vars (`SERVER_*`, `REMOTE_URL`, `ANALYTICS_DISABLED`) set in `localhost.yml`
through `feishin_role_docker_envs_custom`. Deploy: `sb install mod-feishin`.
