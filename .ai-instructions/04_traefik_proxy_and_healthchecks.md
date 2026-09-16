# 04. Traefik Proxy, Authelia SSO & Container Healthchecks

This document details Traefik reverse proxy configuration, Single Sign-On (SSO) integration via Authelia, and container healthchecks based on official Saltbox specifications.

---

## 1. Traefik Reverse Proxy Routing

In the Saltbox environment, Traefik functions as the central reverse proxy managing TLS termination, automated Let's Encrypt certificates via Cloudflare DNS challenges, security headers, and authentication.

### How Traefik Integrates with Roles
When an Ansible role sets `<role>_role_traefik_enabled: true`, the task `create_docker_container.yml` automatically applies standard Traefik container labels:

```
traefik.enable: true
traefik.http.routers.<name>-http.entrypoints: web
traefik.http.routers.<name>-http.rule: Host(`<subdomain>.<domain>`)
traefik.http.routers.<name>-http.middlewares: redirect-to-https@docker

traefik.http.routers.<name>.entrypoints: websecure
traefik.http.routers.<name>.rule: Host(`<subdomain>.<domain>`)
traefik.http.routers.<name>.tls.certresolver: cfdns
traefik.http.services.<name>.loadbalancer.server.port: <port>
```

### Authelia SSO Protection
- **Enabled (Default)**:
  ```yaml
  <role>_role_traefik_sso_middleware: "{{ traefik_default_sso_middleware }}"
  ```
  This attaches the Authelia forward-auth middleware (`authelia@docker`), requiring users to authenticate before accessing the web interface.
- **Disabled (Publicly Accessible)**:
  ```yaml
  <role>_role_traefik_sso_middleware: ""
  ```
  Disables SSO, allowing direct access (e.g. for external webhooks, public services, or restreamer endpoints).

### API Endpoints & Authelia Bypass
If an application contains a mobile app API or webhook endpoint that must bypass Authelia authentication:
```yaml
<role>_role_traefik_api_enabled: true
<role>_role_traefik_api_endpoint: "PathPrefix(`/api`) || PathPrefix(`/ping`)"
```
This registers a high-priority router with `globalHeaders` and `secureHeaders` but without the SSO middleware.

---

## 2. Container Healthchecks

- **Official Documentation**: [https://docs.saltbox.dev/advanced/healthchecks/](https://docs.saltbox.dev/advanced/healthchecks/)

Saltbox allows injecting custom Docker healthchecks into any container via `/srv/git/saltbox/inventories/host_vars/localhost.yml`.

### Healthcheck Syntax
```yaml
<rolename>_docker_healthcheck:
  test: ["healthcheck", "in", "command", "notation"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s
```

### Parameters:
- `test`: Command list. Begins with `CMD` (preferred) or `CMD-SHELL`.
- `interval`: Time between healthcheck runs.
- `timeout`: Maximum duration before considering the check timed out.
- `retries`: Consecutive failures required before marking the container unhealthy.
- `start_period`: Grace period after container boot during which failures do not count against the retry limit.

---

## 3. Standard Healthcheck Recipes

The following recipes from the official Saltbox documentation can be dropped into `localhost.yml`:

### Arr Stack (Sonarr, Radarr, Lidarr, Prowlarr, Whisparr)
```yaml
sonarr_docker_healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:{{ sonarr_web_port }}/login"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s

radarr_docker_healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:{{ radarr_web_port }}/login"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s

prowlarr_docker_healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:{{ prowlarr_web_port }}/login"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s

lidarr_docker_healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:{{ lidarr_web_port }}/login"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s

whisparr_docker_healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:{{ whisparr_web_port }}/login"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s
```

### Databases
```yaml
postgres_docker_healthcheck:
  test: ["CMD-SHELL", "pg_isready", "-d", "{{ postgres_docker_env_db }}"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s
```

### Web Tools & Utilities
```yaml
duplicati_docker_healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:{{ duplicati_web_port }}"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s

elasticsearch_docker_healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:9200"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s

homeassistant_docker_healthcheck:
  test: ["CMD", "curl", "--fail", "http://localhost:{{ homeassistant_web_port }}"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s

firefox_docker_healthcheck:
  test: ["CMD", "wget", "--spider", "http://localhost:{{ firefox_web_port }}"]
  interval: 10s
  timeout: 5s
  retries: 10
  start_period: 10s
```
