# Saltbox App Role Creation Guide

When a user asks: "Create a new saltbox app for `<app_name>`", follow this exact structure.

## 1. Directory Structure

For a new application named `<app_name>`, create:
* `/opt/saltbox_mod/roles/<app_name>/tasks/main.yml`
* `/opt/saltbox_mod/roles/<app_name>/defaults/main.yml`

*Note: Replace `<app_name>` with the lowercase, no-spaces ID of the app (e.g., `immich`, `emby`, `metube`).*

## 2. Using `tasks/main.yml`

This file executes the standardized tasks to set up DNS, clear out old instances, map directories, set devices (GPU/Intel rendering), and spin up the container.

```yaml
---
- name: Add DNS record
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/dns/tasker.yml"
  vars:
    dns_record: "{{ lookup('role_var', '_dns_record') }}"
    dns_zone: "{{ lookup('role_var', '_dns_zone') }}"
    dns_proxy: "{{ lookup('role_var', '_dns_proxy') }}"

- name: Remove existing Docker container
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/docker/remove_docker_container.yml"

- name: Create directories
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/directories/create_directories.yml"

# Optional: Un-comment if the app requires hardware transcoding (Intel/Nvidia)
# - name: Docker Devices Task
#   ansible.builtin.include_tasks: "{{ resources_tasks_path }}/docker/set_docker_devices_variable.yml"
#   when: use_intel or use_nvidia

- name: Create Docker container
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/docker/create_docker_container.yml"
```

## 3. Designing `defaults/main.yml`

This is where the magic happens. All variables must be heavily templated and rely on the `role_var` lookup plugin so they can be overridden globally by the user if needed.

Prefix all variables with `<app_name>_role_`. The standard `resources_tasks_path/docker/create_docker_container.yml` loop will automatically resolve properties matching these patterns.

### Key Aspects to Implement:

#### Flexibility Using Variables
Variables are split between `_default` and `_custom`, and then combined using `role_var` lookups. This ensures the app runs perfectly out-of-the-box but gracefully handles user-injected overrides (from `settings.yml`).

#### Reverse Proxy (Traefik) Setup
Proxying is automatically achieved via generated Docker labels inside `create_docker_container.yml` when `_traefik_enabled: true` is set. The service defines `_web_port` and the router takes care of the rest.

#### Authelia Authentication Setup
To put the app behind Authelia, you bind the `_traefik_sso_middleware` variable to `{{ traefik_default_sso_middleware }}`. To disable it easily, you would set it to an empty string `""`.

### Sample `defaults/main.yml` Structure

```yaml
---
################################
# Basics
################################
<app_name>_name: <app_name>

################################
# Paths
################################
<app_name>_role_paths_folder: "{{ <app_name>_name }}"
<app_name>_role_paths_location: "{{ server_appdata_path }}/{{ <app_name>_role_paths_folder }}"
<app_name>_role_paths_folders_list:
  - "{{ <app_name>_role_paths_location }}"

################################
# Web
################################
<app_name>_role_web_subdomain: "{{ <app_name>_name }}"
<app_name>_role_web_domain: "{{ user.domain }}"
<app_name>_role_web_port: "8080" # <-- Replace with internal docker port
<app_name>_role_web_url: "{{ 'https://' + (lookup('role_var', '_web_subdomain', role='<app_name>') + '.' + lookup('role_var', '_web_domain', role='<app_name>') if (lookup('role_var', '_web_subdomain', role='<app_name>') | length > 0) else lookup('role_var', '_web_domain', role='<app_name>')) }}"

################################
# DNS
################################
<app_name>_role_dns_record: "{{ lookup('role_var', '_web_subdomain', role='<app_name>') }}"
<app_name>_role_dns_zone: "{{ lookup('role_var', '_web_domain', role='<app_name>') }}"
<app_name>_role_dns_proxy: "{{ dns_proxied }}"

################################
# Traefik (Reverse Proxy & Auth)
################################
# To protect via Authelia, this MUST be `{{ traefik_default_sso_middleware }}`. To bypass, set to `""`.
<app_name>_role_traefik_sso_middleware: "{{ traefik_default_sso_middleware }}"
<app_name>_role_traefik_middleware_default: "{{ traefik_default_middleware }}"
<app_name>_role_traefik_middleware_custom: ""
<app_name>_role_traefik_certresolver: "{{ traefik_default_certresolver }}"
<app_name>_role_traefik_enabled: true
<app_name>_role_traefik_api_enabled: false
<app_name>_role_traefik_api_endpoint: ""

################################
# Docker
################################
<app_name>_role_docker_container: "{{ <app_name>_name }}"

# Image
<app_name>_role_docker_image_pull: true
<app_name>_role_docker_image_repo: "ghcr.io/vendor/image" # <-- Replace with real image
<app_name>_role_docker_image_tag: "latest" # <-- Replace with relevant tag or latest
<app_name>_role_docker_image: "{{ lookup('role_var', '_docker_image_repo', role='<app_name>') }}:{{ lookup('role_var', '_docker_image_tag', role='<app_name>') }}"

# Envs
<app_name>_role_docker_envs_default:
  PUID: "{{ uid }}"
  PGID: "{{ gid }}"
  TZ: "{{ tz }}"

<app_name>_role_docker_envs_custom: {}
<app_name>_role_docker_envs: "{{ lookup('role_var', '_docker_envs_default', role='<app_name>') | combine(lookup('role_var', '_docker_envs_custom', role='<app_name>')) }}"

# Volumes
<app_name>_role_docker_volumes_default:
  - "{{ <app_name>_role_paths_location }}:/config" # <-- Adjust mount points accordingly

<app_name>_role_docker_volumes_custom: []
<app_name>_role_docker_volumes: "{{ lookup('role_var', '_docker_volumes_default', role='<app_name>') + lookup('role_var', '_docker_volumes_custom', role='<app_name>') }}"

# Ports (Usually avoid exposing custom ports directly in Saltbox to force traefik routing)
<app_name>_role_docker_ports_defaults: []
<app_name>_role_docker_ports_custom: []
<app_name>_role_docker_ports: "{{ lookup('role_var', '_docker_ports_defaults', role='<app_name>') + lookup('role_var', '_docker_ports_custom', role='<app_name>') }}"

# Network & Hostname
<app_name>_role_docker_hostname: "{{ <app_name>_name }}"
<app_name>_role_docker_networks_alias: "{{ <app_name>_name }}"
<app_name>_role_docker_networks_default: []
<app_name>_role_docker_networks_custom: []
<app_name>_role_docker_networks: "{{ docker_networks_common + lookup('role_var', '_docker_networks_default', role='<app_name>') + lookup('role_var', '_docker_networks_custom', role='<app_name>') }}"

# Operations
<app_name>_role_docker_restart_policy: unless-stopped
<app_name>_role_docker_state: started
```

## 4. Multi-Container Applications (Complex Stacks)

If the app requires a database or redis cache (like `immich` or `nextcloud`), do not declare them directly alongside the main app. Instead:
1. Import and utilize existing Saltbox native roles where possible (e.g., `ansible.builtin.include_role: name=redis`).
2. Override those roles' variables so they become dedicated instances for your app (e.g., pass `<app>_name-redis` to `redis_instances` and map their `paths_folder`).

Example inside `tasks/main.yml` for adding a Postgres DB dependency:
```yaml
- name: "Import Postgres Role for <app_name>"
  ansible.builtin.include_role:
    name: postgres
  vars:
    postgres_instances: ["{{ <app_name>_name }}-postgres"]
    postgres_role_docker_image_tag: "14"
    postgres_role_paths_folder: "{{ <app_name>_name }}"
    postgres_role_paths_location: "{{ server_appdata_path }}/{{ <app_name>_name }}/postgres"
    postgres_role_docker_env_db: "{{ <app_name>_name }}"
    postgres_role_docker_env_user_include: "custom_user"
    postgres_role_docker_env_password_include: "custom_pass"
```

## 5. Exposing to Users

Finally, remember to let the user know they need to add the role to their playbook (e.g., `/opt/saltbox_mod/saltbox_mod.yml` or standard `/srv/git/saltbox/saltbox.yml` tags list):

```yaml
    - { role: <app_name>, tags: ['<app_name>'] }
```

To deploy and install the mod role you just created or modified, instruct the user to run:
`sb install mod-<app_name>`

## 6. Author
Auther is hereisderek, and the repo is https://github.com/hereisderek/saltbox_mod. update author for any newly implemented roles accordingly.
