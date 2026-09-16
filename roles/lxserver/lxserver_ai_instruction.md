# AI Instruction Note for LXServer

**App Name**: `lxserver`  
**Author**: `hereisderek`  
**Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Source Repo**: [https://github.com/XCQ0607/lxserver](https://github.com/XCQ0607/lxserver)  

## Description
This role sets up LX Music Sync Server & WebPlayer (Enhanced Edition), which provides desktop client synchronization, a WebDAV backup endpoint, and a web-based music player and downloader with access to local music libraries.

## Key Configurations
1. **Web Port**: Container listens internally on port `9527`.
2. **Subdomain**: Routes automatically under `lxserver.<yourdomain.tld>` via Traefik.
3. **Authentication**: Secured behind Authelia SSO via `traefik_default_sso_middleware`.
4. **Music Directory**: Container internal path is `/server/music`. To map the host's unified media library, configure `lxserver_role_docker_volumes_custom` in `localhost.yml`.
5. **Volume Architecture**: Do NOT put `/server/music`, `/server/logs`, or `/server/cache` into `lxserver_role_docker_volumes_default` to avoid duplicate mount collisions with `lxserver_role_docker_volumes_custom`.

