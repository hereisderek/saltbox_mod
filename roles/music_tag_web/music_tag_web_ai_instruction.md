# AI Instruction Note for Music-Tag-Web

**App Name**: `music_tag_web`
**Author**: `hereisderek`
**Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)
**Source Repo**: [https://github.com/xhongc/music-tag-web](https://github.com/xhongc/music-tag-web)

## Description
This role updates the previously existent old-standard module into the modern Saltbox `role_var` schema.

## Key Configurations
1.  **Media Directories**: Uses `/mnt/unionfs/Media/Music/library` which gets mounted to `/app/media:rw`. Users can customize additional paths or changes via `music_tag_web_role_docker_volumes_custom` variables.
2.  **Web Port**: Traefik automatically hooks into Port `8002` (internal web UI). To proxy over standard port 8001 adjust `music_tag_web_role_web_port` to match exactly what your container is listening on internally.
3.  **Command Execution**: Employs an exact overriding command `["/start"]` inside string variables. 
4.  **Traefik and SSO**: Seamlessly routes via Authelia using `traefik_default_sso_middleware` and runs under subdomain `music-tag`.