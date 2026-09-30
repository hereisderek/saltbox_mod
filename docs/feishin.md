# Feishin

- Upstream: https://github.com/jeffvli/feishin (image `ghcr.io/jeffvli/feishin:latest`)
- Tag: `sb install mod-feishin` / `--tags feishin`
- Internal port: `9180` (`feishin_role_web_port`); Traefik at `https://feishin.<domain>`, Authelia SSO on by default.
- Volumes: none (stateless).

## Inventory override example (`localhost.yml`)

```yaml
feishin_role_docker_envs_custom:
  ANALYTICS_DISABLED: "true"
  SERVER_LOCK: "true"
  SERVER_NAME: "feishin"
  SERVER_TYPE: "subsonic"
  SERVER_URL: "https://octo.hereisderek.dpdns.org"  # browser calls this directly, must be public
```

## Auto-login (skip the Subsonic login form)

Feishin has no env var for default credentials. After the container is created, the role
`docker exec`s an `autologin.js` into `/usr/share/nginx/html/` and adds a `<script>` tag for it
to `index.html` (no bind mount; survives `docker restart`, redone on every role run). On first
load it seeds the browser's `store_authentication` localStorage entry with a Subsonic token
credential (`u=<user>&s=<salt>&t=md5(pass+salt)`).

```yaml
feishin_role_autologin_username: "derek"
feishin_role_autologin_password: "..."
```

Anyone who can load the page can read the token: keep Authelia SSO on and use a dedicated
low-privilege Navidrome user. Empty username/password disables it. If the form still shows
after a deploy, hard-reload (Feishin's service worker caches `index.html`).
