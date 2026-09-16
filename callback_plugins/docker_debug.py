from __future__ import annotations

DOCUMENTATION = """
    name: docker_debug
    type: notification
    short_description: Debug Docker container creation and volume diagnostics in Saltbox Mod
    description:
      - Automatically displays Docker container parameters prior to creation when debug_docker_create_container is true.
      - Detects duplicate destination volume mounts and warns before Docker aborts.
      - On failure, formats detailed diagnostics and troubleshooting guidance.
"""

from ansible.plugins.callback import CallbackBase
from ansible.utils.display import Display
from ansible import constants as C

display = Display()


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'notification'
    CALLBACK_NAME = 'docker_debug'
    CALLBACK_NEEDS_ENABLED = False

    def __init__(self):
        super(CallbackModule, self).__init__()
        self._play = None
        self._variable_manager = None

    def v2_playbook_on_play_start(self, play):
        self._play = play
        if hasattr(play, 'get_variable_manager'):
            self._variable_manager = play.get_variable_manager()

    def _is_debug_enabled(self, task_vars: dict) -> bool:
        val = task_vars.get('debug_docker_create_container', False)
        return val is True or str(val).lower() in ('true', 'yes', '1')

    def _parse_volumes(self, raw_volumes) -> list[tuple[str, str, str]]:
        """Parse volume strings into (host, container, mode) tuples."""
        parsed = []
        if not raw_volumes or not isinstance(raw_volumes, list):
            return parsed

        for v in raw_volumes:
            if not isinstance(v, str):
                continue
            parts = v.split(':')
            if len(parts) >= 2:
                host_path = parts[0]
                container_path = parts[1]
                mode = parts[2] if len(parts) > 2 else 'rw'
                parsed.append((host_path, container_path, mode))
        return parsed

    def v2_runner_on_start(self, host, task):
        try:
            # Trigger specifically on the container creation task
            task_name = task.get_name()
            if "Create Docker Container | Create Docker Container" not in task_name:
                return

            if not self._variable_manager or not self._play:
                return

            task_vars = self._variable_manager.get_vars(play=self._play, host=host, task=task)
            if not self._is_debug_enabled(task_vars):
                return

            docker_vars = task_vars.get('_docker_vars', {})
            container_name = (
                docker_vars.get('_docker_container')
                or task_vars.get('_instance_name')
                or task_vars.get('role_name')
                or 'unknown'
            )
            image = docker_vars.get('_docker_image') or task_vars.get('_docker_image') or 'N/A'
            raw_volumes = task_vars.get('_docker_volumes') or docker_vars.get('_docker_volumes') or []
            ports = task_vars.get('_docker_ports') or docker_vars.get('_docker_ports') or []
            networks = docker_vars.get('_docker_networks') or task_vars.get('_docker_networks') or []

            # Analyze volumes for duplicate destination mount points
            parsed_vols = self._parse_volumes(raw_volumes)
            dest_counts: dict[str, list[str]] = {}
            for h, c, m in parsed_vols:
                dest_counts.setdefault(c, []).append(f"{h}:{c}:{m}")

            duplicates = {dest: mounts for dest, mounts in dest_counts.items() if len(mounts) > 1}

            # Header Banner
            display.display("\n" + "=" * 78, color=C.COLOR_HIGHLIGHT)
            display.display(f" [SALTBOX MOD DOCKER DEBUG] Creating Container: {container_name}", color=C.COLOR_HIGHLIGHT)
            display.display(f" Image:    {image}", color=C.COLOR_HIGHLIGHT)
            display.display(f" Networks: {networks}", color=C.COLOR_HIGHLIGHT)

            if ports:
                display.display(f" Ports:    {ports}", color=C.COLOR_HIGHLIGHT)

            # Display Volumes
            display.display(" Configured Volumes:", color=C.COLOR_HIGHLIGHT)
            if not raw_volumes:
                display.display("   (No volumes configured)", color=C.COLOR_HIGHLIGHT)
            else:
                for idx, v in enumerate(raw_volumes, 1):
                    # Flag duplicate lines in warn color
                    is_dup = False
                    for d_mounts in duplicates.values():
                        if any(v in m or m.startswith(v) for m in d_mounts):
                            is_dup = True
                            break
                    if is_dup:
                        display.display(f"   [{idx}] ⚠️  {v}  <-- DUPLICATE DESTINATION", color=C.COLOR_WARN)
                    else:
                        display.display(f"   [{idx}] {v}", color=C.COLOR_HIGHLIGHT)

            # Alert if duplicates detected
            if duplicates:
                display.display("-" * 78, color=C.COLOR_WARN)
                display.display(" ⚠️  WARNING: Duplicate container mount destinations detected!", color=C.COLOR_WARN)
                for dest, mounts in duplicates.items():
                    display.display(f"   Mount point '{dest}' is mapped {len(mounts)} times:", color=C.COLOR_WARN)
                    for m in mounts:
                        display.display(f"     - {m}", color=C.COLOR_WARN)
                display.display(" This will trigger a fatal Docker engine collision:", color=C.COLOR_WARN)
                display.display(" 'The mount point appears twice in the volumes option'", color=C.COLOR_WARN)
                display.display(" Check defaults/main.yml (_default) and localhost.yml (_custom).", color=C.COLOR_WARN)

            display.display("=" * 78 + "\n", color=C.COLOR_HIGHLIGHT)

        except Exception as e:
            display.warning(f"[docker_debug callback error] {e}")

    def v2_runner_on_failed(self, result, ignore_errors=False):
        try:
            task = result._task
            if task.action not in ('community.docker.docker_container', 'docker_container'):
                return

            res = getattr(result, '_result', {})
            msg = res.get('msg', '')

            # If failed due to duplicate mount point
            if 'appears twice in the volumes option' in msg:
                display.display("\n" + "#" * 78, color=C.COLOR_ERROR)
                display.display(" [SALTBOX MOD] Docker Container Creation Aborted!", color=C.COLOR_ERROR)
                display.display(f" Error: {msg}", color=C.COLOR_ERROR)
                display.display("-" * 78, color=C.COLOR_ERROR)
                display.display(" Root Cause: A container destination path is mounted multiple times.", color=C.COLOR_ERROR)
                display.display(" Rule: Keep roles/<role>/defaults/main.yml _docker_volumes_default minimal.", color=C.COLOR_ERROR)
                display.display("       Do not define media/logs/cache paths in _default if overriding via _custom.", color=C.COLOR_ERROR)
                display.display("#" * 78 + "\n", color=C.COLOR_ERROR)

        except Exception as e:
            display.warning(f"[docker_debug callback error on failed] {e}")
