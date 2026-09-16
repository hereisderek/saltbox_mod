# 05. Custom Containers & Docker Compose

This document details how to deploy custom containers in the Saltbox environment using Docker Compose, the Traefik Template generator, Dockge, and shell functions, according to official Saltbox documentation.

---

## 1. Official Documentation References

- **Adding Your Own Containers**: [https://docs.saltbox.dev/advanced/your-own-containers/](https://docs.saltbox.dev/advanced/your-own-containers/)
- **Traefik Template Module**: [https://docs.saltbox.dev/reference/modules/traefik_template/#usage](https://docs.saltbox.dev/reference/modules/traefik_template/#usage)

---

## 2. Choosing the Deployment Method

| Method | Best For | Location | Pros / Cons |
|---|---|---|---|
| **Ansible Role (`saltbox_mod`)** | Long-term services, native integration | `/opt/saltbox_mod/roles/<app>` | Full integration with DNS, Traefik, Authelia, backups, inventory overrides. |
| **Docker Compose** | Testing new services, third-party compose stacks | `/opt/<app>/compose.yaml` | Fast setup; manual DNS record and compose lifecycle. |
| **Dockge Stacks** | GUI Compose stack management | `/opt/stacks/<app>/compose.yaml` | Web UI at port 5001, interactive container management. |
| **Docker CLI Function** | Ephemeral CLI utilities | `~/.zshrc` / inventory | Zero background memory usage; interactive execution. |

---

## 3. Deploying with Docker Compose & Traefik Template

### Step 1: Generate the Compose Template
Saltbox provides an automated tool to generate a Docker Compose file pre-configured with Traefik reverse proxy labels:

```bash
sb install generate-traefik-template
```
Answer the prompts for:
- Domain name (e.g., your configured base domain)
- App name (e.g., `myapp`)
- Application data path (e.g., `/opt/myapp`)

The template is saved to `/tmp/docker-compose.yml`.

### Step 2: Store in `/opt/<appname>/compose.yaml`
```bash
sudo mkdir -p /opt/myapp
sudo mv /tmp/docker-compose.yml /opt/myapp/compose.yaml
sudo chown -R 1000:1000 /opt/myapp
```

### Step 3: Complete Compose Template Cheat Sheet
Below is the standard, production-ready compose template compatible with the Saltbox network and Traefik:

```yaml
services:
  appname:
    restart: unless-stopped
    container_name: appname
    image: DOCKER/IMAGE:TAG
    hostname: appname
    environment:
      PUID: "1000"
      PGID: "1000"
      TZ: "Etc/UTC"
    volumes:
      - /opt/appname:/config
    networks:
      - saltbox
    labels:
      com.github.saltbox.saltbox_managed: true
      diun.enable: true
      traefik.enable: true

      # HTTP Router (Redirect to HTTPS)
      traefik.http.routers.appname-http.entrypoints: web
      traefik.http.routers.appname-http.middlewares: redirect-to-https@docker
      traefik.http.routers.appname-http.rule: Host(`appname.yourdomain.tld`)

      # HTTPS Router
      traefik.http.routers.appname.entrypoints: websecure
      traefik.http.routers.appname.middlewares: globalHeaders@file,secureHeaders@file,robotHeaders@file,cloudflarewarp@docker,authelia@docker
      traefik.http.routers.appname.rule: Host(`appname.yourdomain.tld`)
      traefik.http.routers.appname.tls.certresolver: cfdns

      # Service Port (Container internal listening port)
      traefik.http.services.appname.loadbalancer.server.port: 8080

networks:
  saltbox:
    external: true
```

> [!NOTE]
> To make the app public (bypassing Authelia login), remove `,authelia@docker` from `traefik.http.routers.appname.middlewares`.

---

## 4. Managing Stacks via Dockge

Dockge is installed as a custom role in `/opt/saltbox_mod` (`sb install mod-dockge`):
- **Web UI**: Listening on port `5001` behind Authelia SSO (`dockge.yourdomain.tld`).
- **Stacks Directory**: `/opt/stacks`.
- **Console Access**: Enabled via `dockge_role_docker_envs_custom: { DOCKGE_ENABLE_CONSOLE: "true" }` in `localhost.yml`.
- Each stack is placed in its own folder `/opt/stacks/<stack_name>/compose.yaml`.

---

## 5. Ephemeral Docker CLI Functions

For command-line tools that should not run as persistent background daemons (e.g. `yt-dlp` or `speedtest`), define interactive wrapper functions.

In `/srv/git/saltbox/inventories/host_vars/localhost.yml`:
```yaml
shell_zsh_zshrc_block_custom: |
  yt-dlp() {
    docker run --rm -it \
      -v "$(pwd)":/downloads:rw \
      -u $(id -u):$(id -g) \
      ghcr.io/jauderho/yt-dlp:latest "$@"
  }

  speedtest() {
    docker run --rm -it \
      gists/speedtest-cli "$@"
  }
```

Then run `yt-dlp <url>` or `speedtest` directly from your shell.
