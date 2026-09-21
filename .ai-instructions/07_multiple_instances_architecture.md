# 07. Multiple App Instances Architecture & Authoring Guide

This document details the technical architecture of Saltbox's generalized multi-instance system ([Saltbox Multiple App Instances](https://docs.saltbox.dev/reference/multiple-instances/)), explaining how multiple instances are orchestrated, how variable precedence resolves dynamically, and how custom roles in `/opt/saltbox_mod` must be authored or adapted to support multiple instances without breaking isolation.

---

## 1. Overview & Architecture Philosophy

Saltbox previously managed secondary instances using dedicated "ArrX" roles (e.g. `sonarr2`, `radarr4k`, etc.). In modern Saltbox, this was replaced with an **inventory-driven, generalized multi-instance architecture**:

1. A single role definition (e.g., `sonarr`, `qbittorrent`, `deluge`) can deploy 1 to $N$ independent, parallel instances.
2. The list of desired instances is declared centrally in `/srv/git/saltbox/inventories/host_vars/localhost.yml`.
3. Running standard deployment commands (`sb install <role>`) iterates over the instance list, creating fully isolated containers, paths, network aliases, DNS records, and Traefik reverse-proxy routes.

---

## 2. Core Technical Building Blocks

### A. The Loop Orchestrator Pattern (`main.yml` $\rightarrow$ `main2.yml`)

Roles supporting multiple instances split their task execution into two tiers:

1. **Role Defaults (`defaults/main.yml`)**:
   Defines the default single-instance list:
   ```yaml
   <role>_instances: ["<role>"]
   ```

2. **Entrypoint Orchestrator (`tasks/main.yml`)**:
   Loops through `<role>_instances`, assigning the loop variable to `<role>_name` and delegating to the worker playbook:
   ```yaml
   - name: "Execute <role> roles"
     ansible.builtin.include_tasks: main2.yml
     vars:
       <role>_name: "{{ instance }}"
     loop: "{{ <role>_instances }}"
     loop_control:
       loop_var: instance
   ```

3. **Worker Playbook (`tasks/main2.yml`)**:
   Executes the actual provisioning tasks (DNS, directory creation, container deployment) for that single instance identity `<role>_name`.

---

### B. Dynamic Variable Resolution: `role_var` & `docker_vars`

To eliminate hardcoded per-instance playbooks, Saltbox uses custom Ansible lookup plugins in `/srv/git/saltbox/lookup_plugins/`:

#### 1. `role_var.py`
Whenever a role property is needed (e.g., image tags, paths, ports, or custom settings), the role calls:
```jinja2
{{ lookup('role_var', '_<property_suffix>', role='<role_name>') }}
```
The plugin inspects the Ansible variable space in strict hierarchical order:

| Priority | Scope | Candidate Variable Name | Example (`instance = "sonarr4k"`, `role = "sonarr"`, `suffix = "_docker_image_tag"`) |
| :---: | :--- | :--- | :--- |
| **1** | **Instance-Scoped** | `<instance_name><suffix>` | `sonarr4k_docker_image_tag` |
| **2** | **Role-Scoped** | `<role_name>_role<suffix>` | `sonarr_role_docker_image_tag` |
| **3** | **Default** | Plugin `default=` value | Value provided in lookup call |

- **Normalization**: The plugin automatically handles hyphens and underscores (e.g. checking both `qbittorrent-vpn_...` and `qbittorrent_vpn_...`).
- **Circular Reference Guard**: Tracks an execution stack (`__saltbox_role_var_stack__`) to detect and halt recursive variable resolutions.

#### 2. `docker_vars.py`
In `/srv/git/saltbox/resources/tasks/docker/create_docker_container.yml`, container specifications (environment variables, volumes, labels, networks, and resources) are resolved in bulk using `lookup('docker_vars', specs=...)`, enforcing identical instance-over-role precedence.

#### 3. `role_web.py`
Resolves web hostnames, subdomains, domains, and full URLs per instance:
```jinja2
{{ lookup('role_web', role='<role_name>', scheme='https') }}
```

---

### C. Resource & Workload Isolation

To ensure that instances run completely independently without collisions, every resource derives its identity from `<role>_name`:

1. **Storage / AppData Directories**:
   ```yaml
   <role>_role_paths_folder: "{{ <role>_name }}"
   <role>_role_paths_location: "{{ server_appdata_path }}/{{ <role>_role_paths_folder }}"
   ```
   Each instance gets its own directory (e.g., `/opt/sonarr` vs `/opt/sonarr4k`), preventing database lockups or corrupted configs.

2. **Docker Containers & Hostnames**:
   - Container name is `{{ <role>_name }}` (`docker run --name sonarr4k ...`).
   - Hostname defaults to `{{ <role>_name }}`.
   - Network alias defaults to `{{ <role>_name }}` on the bridge network so other containers address them directly by name (e.g., `http://sonarr4k:8989`).

3. **Traefik Reverse Proxy & Routing**:
   - Subdomain defaults to `{{ <role>_name }}` (`sonarr4k.yourdomain.tld`).
   - Traefik router names, service names, and certificate configurations are uniquely keyed to the instance name, ensuring independent TLS certificates and routing.

4. **DNS Records**:
   DNS records are created for each instance via:
   ```yaml
   - name: Add DNS record
     ansible.builtin.include_tasks: "{{ resources_tasks_path }}/dns/tasker.yml"
     vars:
       dns_record: "{{ lookup('role_var', '_dns_record') }}"
       dns_zone: "{{ lookup('role_var', '_dns_zone') }}"
       dns_proxy: "{{ lookup('role_var', '_dns_proxy') }}"
   ```
   > [!IMPORTANT]
   > Do **NOT** use `lookup('vars', role_name + '_dns_record')`. That looks up the base role name instead of the instance name and causes all instances to overwrite the primary instance's DNS record.

---

### D. Host Port Arbitration (`port_assignment.py`)

For roles that publish host ports (e.g., BitTorrent peer listening ports or web UIs running in host networking mode), multiple instances cannot bind to identical host ports.

Saltbox provides a custom module `/srv/git/saltbox/library/port_assignment.py`:
```yaml
- name: Assign ports
  port_assignment:
    base_path: "{{ server_appdata_path }}"
    namespace: qbittorrent
    owner: "{{ qbittorrent_name }}"
    claims:
      peer:
        low_bound: "{{ lookup('role_var', '_port_peer_low_bound', role='qbittorrent') }}"
        high_bound: "{{ lookup('role_var', '_port_peer_high_bound', role='qbittorrent') }}"
        protocols: ["tcp", "udp"]
  register: qbittorrent_port_assignment
```
- **State Registry**: Stores allocations persistently under `{{ server_appdata_path }}`.
- **Collision Checking**: Queries host sockets and Docker container daemon port bindings to find free ports.
- **Port Stability**: Re-allocates the previously assigned port for that `owner` on subsequent runs unless a conflict occurs.

---

## 3. Inventory Configuration Rules (`localhost.yml`)

### A. Defining Instances
In `/srv/git/saltbox/inventories/host_vars/localhost.yml`:
```yaml
sonarr_instances: ["sonarr", "sonarr4k", "sonarranime"]
```

### B. Setting Global vs Instance-Scoped Overrides
- **Role-Scoped (Applies to all instances of the role)**:
  Format: `<role_name>_role_<suffix>`
  ```yaml
  sonarr_role_docker_image_tag: "nightly"
  ```
- **Instance-Scoped (Fine-tunes a specific instance)**:
  Format: `<instance_name>_<suffix>` (Notice: The `_role` segment is dropped for instance-scoped overrides!)
  ```yaml
  sonarr4k_docker_image_tag: "develop"
  ```

#### Example: Fine-Tuning a Second qBittorrent Instance (`qbittorrent2`)
If you want a global configuration for all instances, but specific tweaks for `qbittorrent2`:
```yaml
# 1. Base configuration applied to all qbittorrent instances:
qbittorrent_role_docker_volumes_default:
  - "{{ lookup('role_var', '_paths_location', role='qbittorrent') }}/qBittorrent:/config/config"
  - "{{ lookup('role_var', '_paths_location', role='qbittorrent') }}/data:/config/data"
  - "{{ server_appdata_path }}/scripts:/scripts"
qbittorrent_role_paths_folders_list_custom:
  - "{{ app_log_dir }}"
  - "{{ lookup('role_var', '_paths_location', role='qbittorrent') }}/data"
  - "{{ lookup('role_var', '_paths_location', role='qbittorrent') }}/qBittorrent"
qbittorrent_role_docker_volumes_custom:
  - "{{ app_log_dir }}:/config/data/logs"

# 2. Fine-tuned overrides for qbittorrent2 ONLY:
qbittorrent2_docker_volumes_custom:
  - "{{ app_log_dir }}:/config/data/logs"
  - "/mnt/remote/special:/special"
```
Because upstream Saltbox evaluates `lookup('role_var', '_docker_volumes_custom', role='qbittorrent')`, during the `qbittorrent2` loop iteration it checks `qbittorrent2_docker_volumes_custom` first. If present, it uses the fine-tuned list exclusively for that instance.


### C. Dynamic Host Paths & `app_name`
In `localhost.yml`, host paths are defined dynamically:
```yaml
app_name: "{{ traefik_role_var | default(role_name) }}"
app_log_dir: "{{ log_dir }}/{{ app_name }}"
app_cache_dir: "{{ cache_dir }}/{{ app_name }}"
app_metadata_dir: "{{ metadata_dir }}/{{ app_name }}"
app_data_dir: "{{ root_data_dir }}/app/{{ app_name }}"
```
Because Saltbox sets `traefik_role_var: "{{ lookup('vars', role_name + '_name', default=role_name) }}"`, during execution of `sonarr4k`, `app_name` evaluates to `sonarr4k`. All custom logs, caches, and appdata directories isolate automatically.

### D. Critical Pitfall: Hardcoding Static Paths in `_default` Overrides
> [!CAUTION]
> If overriding default paths or volumes for a multi-instance role (such as qBittorrent image family changes), **NEVER** use static paths or non-lookup role variables:
>
> ❌ **Broken (Collides all instances into one directory or fails with undefined var)**:
> ```yaml
> qbittorrent_role_docker_volumes_default:
>   - "{{ qbittorrent_paths_location }}/qBittorrent:/config/config"
> ```
>
>  **Correct & Multi-Instance Safe**:
> ```yaml
> qbittorrent_role_docker_volumes_default:
>   - "{{ lookup('role_var', '_paths_location', role='qbittorrent') }}/qBittorrent:/config/config"
>   - "{{ lookup('role_var', '_paths_location', role='qbittorrent') }}/data:/config/data"
>   - "{{ server_appdata_path }}/scripts:/scripts"
> ```

---

## 4. Role Authoring Checklist for Saltbox Mod Roles

To make a custom role in `/opt/saltbox_mod/roles/<role>/` fully compatible with multiple instances:

1. **Variables Prefix**:
   All variables in `defaults/main.yml` must use `<role>_role_<suffix>` and resolve dynamic lookups via `lookup('role_var', ...)`:
   ```yaml
   <role>_name: "<role>"
   <role>_role_paths_folder: "{{ <role>_name }}"
   <role>_role_paths_location: "{{ server_appdata_path }}/{{ <role>_role_paths_folder }}"
   <role>_role_web_subdomain: "{{ <role>_name }}"
   <role>_role_web_domain: "{{ user.domain }}"
   <role>_role_dns_record: "{{ lookup('role_var', '_web_subdomain', role='<role>') }}"
   <role>_role_dns_zone: "{{ lookup('role_var', '_web_domain', role='<role>') }}"
   <role>_role_dns_proxy: "{{ dns_proxied }}"
   <role>_role_docker_container: "{{ <role>_name }}"
   ```

2. **DNS Task in `tasks/main.yml` (or `main2.yml`)**:
   ```yaml
   - name: Add DNS record
     ansible.builtin.include_tasks: "{{ resources_tasks_path }}/dns/tasker.yml"
     vars:
       dns_record: "{{ lookup('role_var', '_dns_record') }}"
       dns_zone: "{{ lookup('role_var', '_dns_zone') }}"
       dns_proxy: "{{ lookup('role_var', '_dns_proxy') }}"
   ```

3. **Optional Native Instance Loop**:
   If the role should natively support a list of instances, add to `defaults/main.yml`:
   ```yaml
   <role>_instances: ["<role>"]
   ```
   And structure `tasks/main.yml` to loop over `main2.yml`:
   ```yaml
   - name: "Execute <role> roles"
     ansible.builtin.include_tasks: main2.yml
     vars:
       <role>_name: "{{ instance }}"
     loop: "{{ <role>_instances }}"
     loop_control:
       loop_var: instance
   ```

4. **Ad-Hoc Single Instance Support**:
   Even without `main2.yml`, adhering to items 1 & 2 allows users to deploy secondary instances via:
   ```bash
   sb install mod-<role> -e <role>_name=<instance_name>
   ```
