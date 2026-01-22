# saltbox_sync.sh — Usage & Documentation 🔧

## Overview

**Script:** `/opt/saltbox_mod/scripts/saltbox_sync.sh`

This script synchronizes media from a local mount (`/mnt/local/Media/`) to a remote mount (`/mnt/remote/media/Media/`). It performs cleanup of junk files, runs `rsync` (using a file list for efficiency), deletes old source files after a retention window, logs activity, and optionally pings Healthchecks.io when changes occur.

## Key Features ✅

- Automatic mode: runs only when conditions are met (low disk space or time since last sync).
- Forced mode: run immediately (`-f`).
- Systemd service/timer install option (`-i` / `--install-service`) to run every 30 minutes.
- Safe locking to prevent concurrent runs (lockfile: `/tmp/saltbox_sync.lock`).
- Logs stored under `/media/cache/logs/script/`.
- Starts `/opt/saltbox_mod/scripts/saltbox_sync_samba.sh` after sync in a named detached GNU Screen session (`saltbox_sync_samba`) so you can reattach later. If the screen session is already running, it will be skipped. Samba helper output is written to `/media/cache/logs/script/samba_YYYY-MM-DD_HH-MM-SS.log`.

## Using GNU Screen (quick guide)

- List screen sessions:

```bash
screen -ls
```

- Reattach to the samba helper session:

```bash
screen -r saltbox_sync_samba
```

- Detach from a session (from within screen):

Press `Ctrl-a` then `d` (Ctrl-A D)

- Start the samba helper manually in a named detached session:

```bash
screen -dmS saltbox_sync_samba /opt/saltbox_mod/scripts/saltbox_sync_samba.sh
```

- Kill the session:

```bash
screen -S saltbox_sync_samba -X quit
```

Note: If `screen` is not installed the script falls back to running the helper with `nohup` in the background.

## Prerequisites

- `rsync`, `find`, `df`, `awk`, `curl`, and `flock` available on the system.
- Mounts present and mounted:
  - `/mnt/local` (source root)
  - `/mnt/remote/media` (destination root)
- Root privileges are required to install the systemd service/timer.

## Configuration (variables inside the script) ⚙️

- `SOURCE_DIR` — default: `/mnt/local/Media/`
- `DEST_DIR` — default: `/mnt/remote/media/Media/`
- `WATCH_DIR` — default: `/mnt/local` (used for df checks)
- `LOG_DIR` — default: `/media/cache/logs/script`
- `STATE_FILE` — default: `/opt/saltbox_mod/scripts/last_sync.state` (stores last-run epoch)
- `LOCK_FILE` — default: `/tmp/saltbox_sync.lock`
- `PING_URL` — Healthchecks ping URL
- Thresholds:
  - `THRESHOLD_SPACE_GB` — default: `50` (GB)
  - `THRESHOLD_TIME_SEC` — default: `3600` (seconds = 1 hour)
  - `DELETE_AGE_MIN` — default: `90` (minutes)
- `SERVICE_USER` / `SERVICE_GROUP` — account to run the systemd service (defaults to `derek`)

Edit these variables in the script if you need different paths, users, or thresholds.

## Usage

- Dry/automatic checks (no arguments): script decides whether to run based on space/time checks.

- Forced run (skip checks):

```bash
/opt/saltbox_mod/scripts/saltbox_sync.sh -f
```

- Install the systemd `service` and `timer` (requires root):

```bash
sudo /opt/saltbox_mod/scripts/saltbox_sync.sh -i
# or
sudo /opt/saltbox_mod/scripts/saltbox_sync.sh --install-service
```
The installation writes `saltbox-sync.service` and `saltbox-sync.timer` to `/etc/systemd/system/`, then enables and starts the timer (runs every 30 minutes).

## Logs & State

- Logs written to: `/media/cache/logs/script/sync_YYYY-MM-DD_HH-MM-SS.log`.
- Log rotation: logs older than 7 days are removed by the script.
- Last-run timestamp file: `/opt/saltbox_mod/scripts/last_sync.state` (epoch seconds).

## Behavior & Notes ⚠️

- The script first verifies both `/mnt/local` and `/mnt/remote/media` are mountpoints and will abort if not mounted.
- It removes junk files in the source (patterns: `._*`, `.DS_Store`, `.localized`).
- Uses `rsync` with `--files-from` generated from the source to avoid scanning large destinations.
- `rsync` is run with `--size-only` (faster but may miss content changes if size unchanged).
- After a successful `rsync`, files in the source older than `DELETE_AGE_MIN` minutes are deleted (including cleanup of empty dirs).
- If any changes were detected (transferred/created/deleted), the script posts the log to the configured Healthchecks.io `PING_URL`.
- A helper script `/opt/saltbox_mod/scripts/saltbox_sync_samba.sh` is invoked after the sync; review that script for additional post-sync behavior.

## Service Management & Debugging

- Check timer status:

```bash
systemctl status saltbox-sync.timer
systemctl list-timers --all | grep saltbox-sync
```

- Run service manually (as configured `User`):

```bash
sudo systemctl start saltbox-sync.service
sudo systemctl status saltbox-sync.service
journalctl -u saltbox-sync.service
```

- View live logs:

```bash
tail -F /media/cache/logs/script/sync_*.log
```

## Exit Codes / Failure Modes

- Exits with non-zero if mount checks fail, if `rsync` fails, or if the script is unable to acquire the lock.
- The install option exits after installing the service/timer.

## Tips & Recommendations 💡

- Change `SERVICE_USER`/`SERVICE_GROUP` before running the install if you want the timer/service to run as a different user.
- Review `--size-only` choice for `rsync` if you need content checksum validation (slower but more accurate).
- Consider increasing `DELETE_AGE_MIN` if active copying can take longer than the window.

---

*Generated from the source script on system.*
