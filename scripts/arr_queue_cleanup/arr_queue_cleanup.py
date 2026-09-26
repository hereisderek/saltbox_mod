#!/usr/bin/env python3
"""Remove stuck Sonarr/Radarr queue items (executable-payload releases, mismatched
season/episode packs, anything needing manual interaction) - deletes from the download
client and blocklists, so the app naturally re-grabs a different release on its next
RSS/search pass.

ponytail: blanket policy - any item requiring manual interaction gets nuked, not just
confirmed-malicious ones. A rare legitimate mismatch (needs manual episode mapping,
not deletion) gets swept up too. Add a targeted allowlist by statusMessages text if
that turns out to matter in practice.
"""
import json
import subprocess
import sys

APPS = [
    {"name": "sonarr", "container": "sonarr", "port": 8989, "config_xml": "/opt/sonarr/config.xml"},
    {"name": "radarr", "container": "radarr", "port": 7878, "config_xml": "/opt/radarr/config.xml"},
]

STUCK_STATES = {"importBlocked", "importPending"}


def get_api_key(config_xml: str) -> str:
    out = subprocess.run(
        ["sudo", "grep", "-oP", r"(?<=<ApiKey>).*(?=</ApiKey>)", config_xml],
        capture_output=True, text=True, check=True,
    )
    return out.stdout.strip()


def api_get(container: str, port: int, key: str, path: str) -> dict:
    out = subprocess.run(
        ["docker", "exec", container, "curl", "-s", "-H", f"X-Api-Key: {key}",
         f"http://localhost:{port}{path}"],
        capture_output=True, text=True, check=True,
    )
    return json.loads(out.stdout)


def api_bulk_delete(container: str, port: int, key: str, ids: list) -> str:
    payload = json.dumps({"ids": ids})
    local_tmp = f"/tmp/{container}_queue_bulk_delete.json"
    with open(local_tmp, "w") as f:
        f.write(payload)
    subprocess.run(["docker", "cp", local_tmp, f"{container}:/tmp/queue_bulk_delete.json"], check=True)
    out = subprocess.run(
        ["docker", "exec", container, "curl", "-s", "-X", "DELETE",
         "-H", f"X-Api-Key: {key}", "-H", "Content-Type: application/json",
         "--data-binary", "@/tmp/queue_bulk_delete.json",
         f"http://localhost:{port}/api/v3/queue/bulk?removeFromClient=true&blocklist=true&skipRedownload=false"],
        capture_output=True, text=True, check=True,
    )
    subprocess.run(["docker", "exec", container, "rm", "-f", "/tmp/queue_bulk_delete.json"])
    return out.stdout


def clean_app(app: dict, dry_run: bool) -> int:
    key = get_api_key(app["config_xml"])
    queue = api_get(app["container"], app["port"], key, "/api/v3/queue?pageSize=250")
    stuck = [r for r in queue.get("records", []) if r.get("trackedDownloadState") in STUCK_STATES]
    if not stuck:
        print(f"[{app['name']}] nothing stuck")
        return 0
    for r in stuck:
        reasons = [m.get("title") for m in r.get("statusMessages", [])][:1]
        print(f"[{app['name']}] {'would remove' if dry_run else 'removing'}: "
              f"{r.get('title')} (id={r['id']}) - {reasons}")
    if not dry_run:
        api_bulk_delete(app["container"], app["port"], key, [r["id"] for r in stuck])
    return len(stuck)


def main():
    dry_run = "--dry-run" in sys.argv
    total = 0
    for app in APPS:
        total += clean_app(app, dry_run)
    print(f"total stuck items {'found' if dry_run else 'cleaned'}: {total}")


if __name__ == "__main__":
    main()