# AI Instruction Note for simple_sq_music_plus

**App Name**: `simple_sq_music_plus`
**Author**: `hereisderek`
**Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)
**Source Repo**: [https://github.com/59799517/simple_sq_music_plus](https://github.com/59799517/simple_sq_music_plus)

## Description
This role sets up `simple_sq_music_plus`, an application mapping to the `registry.cn-hangzhou.aliyuncs.com/sqdockler/simple_sq_music_plus` Docker image.

## Modifiable Overrides
1.  **Multiple Containers Database Setup Constraints**: The native docker-compose structure generally operates using an external MySQL (5.7) db and a secondary front-end `web` container. This base setup runs the primary core image (`simple_sq_music_plus_role_docker_image_repo: "registry.cn-hangzhou.aliyuncs.com/sqdockler/simple_sq_music_plus"`).
    - If you are building out the full stack, you may need to amend the single-container `create_docker_container.yml` standard to import the Postgres/MySQL roles inside your `simple_sq_music_plus` `tasks/main.yml` script as designated in the `copilot-instructions-saltbox-app.md` Multi-Container Stack segment.
2.  **Web Port**: The standard port falls back to `80`. If you review the upstream repository and notice a specific customized port mapping (e.g. 5000/8080), change it in the `simple_sq_music_plus_role_web_port` setting either system-wide or in custom overrides!