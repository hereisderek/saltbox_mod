# Saltbox Inventory & Override Guide

This document summarizes the official [Saltbox Inventory documentation](https://docs.saltbox.dev/saltbox/inventory/) to guide users on how to properly override and customize Saltbox roles.

## Core Concepts
The Saltbox inventory system allows you to manipulate variables centrally without modifying the core roles themselves. This ensures that custom configurations are persistent across updates and prevents `git merge` conflicts.

**All custom overrides should be placed in:**
```filepath
/srv/git/saltbox/inventories/host_vars/localhost.yml
```
*Tip: You can quickly edit this file using the command: `sb edit inventory`.*

After editing the inventory, explicitly apply the changes by running the install command for the affected role(s). For official Sandbox apps use `sb install sandbox-<app>`, and for custom mod apps use `sb install mod-<app>`.

## Override Variables & Data Types
Most applications feature exposed variables configured inside their respective `defaults/main.yml` files. These variables follow standard YAML data typing:
- **String:** `app_role_docker_image_tag: "latest"`
- **Boolean:** `app_role_setting_enabled: false`
- **Integer:** `app_role_cache_size: 2048`
- **List:** `[]`
- **Dictionary:** `{}`

### 1. Simple Replacements
To override a fundamental string or boolean globally for an application, specify the variable and new value in `localhost.yml`.
*Example: Changing the Sonarr docker image to nightly:*
```yaml
sonarr_role_docker_image_tag: "nightly"
```

### 2. Using `_custom` Lists & Dictionaries
If a variable lists multiple items (like Docker Volumes, Environment Variables, or Ports), Saltbox splits these into `_default` and `_custom`.
**Important:** Do NOT map against `_default` arrays if you want to keep the base application logic intact. Instead, use the `_custom` list to append your entries.

*Example: Adding a new mount to code-server without destroying the defaults:*
```yaml
code_server_role_docker_volumes_custom:
  - "/srv:/host_srv"
  - "/home:/host_home"
```

## Scoping Overrides (Multiple Instances)
If you deploy multiple instances of an app (like `sonarr` and `sonarr4k`), you can scope overrides globally (the entire role) or locally (just for a specific instance). 

1. **Role-Scoped (Global):**
   Applies to every deployed container governed by the role.
   *Syntax:* `<app>_role_<variable>`
   ```yaml
   sonarr_role_setting_enabled: false
   ```

2. **Instance-Scoped (Local):**
   Overrides configurations strictly for one specific deployment. If both role and instance-level overrides are defined, the instance scope takes priority.
   *Syntax:* `<instance_name>_<variable>`
   ```yaml
   sonarr4k_setting_enabled: true
   ```