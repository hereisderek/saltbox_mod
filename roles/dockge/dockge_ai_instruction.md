# AI Instruction Note for Dockge

**App Name**: `dockge`
**Author**: `hereisderek`
**Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)
**Source Repo**: [https://github.com/louislam/dockge](https://github.com/louislam/dockge)

## Description
This role sets up Dockge, a self-hosted Docker compose manager.

## Key Configurations
1.  **Docker Socket**: Requires mapping `/var/run/docker.sock` to manage containers.
2.  **Stacks Directory**: Expects a centralized stacks directory (defaulted to `/opt/stacks`) where you place `compose.yaml` files.
3.  **Port**: Defaults to `5001`. Modify `dockge_role_web_port` or use custom variables if you need to access it outside of Traefik's routing.
4.  **Security**: Comes pre-configured securely behind Authelia via Saltbox's standard Traefik SSO middleware (`traefik_default_sso_middleware`).

## Instructions for Modification
If you intend on altering where the stacks are located, set `dockge_role_docker_envs_custom` and `dockge_role_docker_volumes_custom` in your `settings.yml` to override the `/opt/stacks` mount paths.