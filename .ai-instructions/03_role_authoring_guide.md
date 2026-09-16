# 03. Role Authoring Guide for Saltbox Mod

This document is the definitive guide for developing, testing, and deploying custom Ansible roles within `/opt/saltbox_mod`.

---

## 1. Directory Structure

When creating a new role named `<app_name>` (use lowercase, snake_case, no spaces or special characters):

```
/opt/saltbox_mod/roles/<app_name>/
├── defaults/
│   └── main.yml                       # All default variables & lookups
├── tasks/
│   └── main.yml                       # Execution orchestration tasks
└── <app_name>_ai_instruction.md       # Role summary & modification notes
```

Optional subdirectories:
- `templates/`: Jinja2 template files (`*.j2`) when an application requires a rendered configuration file.
- `files/`: Static configuration files or scripts copied to the host.

---

## 2. Blueprint for `defaults/main.yml`

Variables MUST use the `role_var` lookup plugin so they can be seamlessly overridden via `/srv/git/saltbox/inventories/host_vars/localhost.yml`. Order top-level sections as follows:

```yaml
---
##################################################################################
# Title:         Saltbox Mod: Roles | <app_name> | Defaults                      #
# Author(s):     hereisderek                                                     #
# URL:           https://github.com/hereisderek/saltbox_mod                      #
##################################################################################

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
<app_name>_role_web_port: "8080" # <-- Replace with container internal listening port
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
# Set to '{{ traefik_default_sso_middleware }}' for Authelia protection, or '""' to make publicly accessible.
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
<app_name>_role_docker_image_repo: "ghcr.io/vendor/<app_name>"
<app_name>_role_docker_image_tag: "latest"
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
  - "{{ <app_name>_role_paths_location }}:/config"
<app_name>_role_docker_volumes_custom: []
<app_name>_role_docker_volumes: "{{ lookup('role_var', '_docker_volumes_default', role='<app_name>') + lookup('role_var', '_docker_volumes_custom', role='<app_name>') }}"

# Ports (Do not publish host ports unless direct access outside Traefik is strictly required)
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

---

## 3. Blueprint for `tasks/main.yml`

The tasks file utilizes standardized Saltbox resource helpers loaded via `{{ resources_tasks_path }}`:

```yaml
---
##################################################################################
# Title:         Saltbox Mod: Roles | <app_name> | Tasks                         #
# Author(s):     hereisderek                                                     #
# URL:           https://github.com/hereisderek/saltbox_mod                      #
##################################################################################

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

# Optional: Enable hardware transcoding / GPU acceleration when required
# - name: Docker Devices Task
#   ansible.builtin.include_tasks: "{{ resources_tasks_path }}/docker/set_docker_devices_variable.yml"
#   when: use_intel or use_nvidia

- name: Create Docker container
  ansible.builtin.include_tasks: "{{ resources_tasks_path }}/docker/create_docker_container.yml"
```

---

## 4. Multi-Container Applications (Database / Redis Stacks)

If the application requires an external database or Redis cache:
1. Do **not** declare an ad-hoc inline database container in your role.
2. Utilize existing upstream Saltbox roles via `ansible.builtin.include_role`.
3. Pass customized instances and paths so the database runs as an isolated companion service.

### Example: PostgreSQL Dependency inside `tasks/main.yml`
```yaml
- name: "Import Postgres Role for <app_name>"
  ansible.builtin.include_role:
    name: postgres
  vars:
    postgres_instances: ["{{ <app_name>_name }}-postgres"]
    postgres_role_docker_image_tag: "16"
    postgres_role_paths_folder: "{{ <app_name>_name }}"
    postgres_role_paths_location: "{{ server_appdata_path }}/{{ <app_name>_name }}/postgres"
    postgres_role_docker_env_db: "{{ <app_name>_name }}"
    postgres_role_docker_env_user_include: "{{ <app_name>_name }}"
    postgres_role_docker_env_password_include: "{{ user.pass }}"
```

---

## 5. Registering & Deploying the Role

### Step 1: Add to `saltbox_mod.yml`
Open `/opt/saltbox_mod/saltbox_mod.yml` and add the role under `roles:`:
```yaml
    - { role: <app_name>, tags: ['<app_name>'] }
```

### Step 2: Create Role AI Instruction Note
Create `/opt/saltbox_mod/roles/<app_name>/<app_name>_ai_instruction.md` explaining:
- Upstream source image / repository.
- Default internal ports and paths.
- Auth setup (Authelia SSO or public).
- Modifiable inventory overrides.

### Step 3: Deploy
```bash
sb install mod-<app_name>
# or
sudo ansible-playbook /opt/saltbox_mod/saltbox_mod.yml --tags <app_name>
```
