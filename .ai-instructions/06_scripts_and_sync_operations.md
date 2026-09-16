# 06. Scripts & Media Synchronization Operations

This document details the operation, architecture, monitoring, and debugging of the automated media synchronization scripts in `/opt/saltbox_mod/scripts/`.

---

## 1. Script Architecture & Purpose

- **Primary Sync Script**: `/opt/saltbox_mod/scripts/saltbox_sync.sh`
- **Post-Sync Helper**: `/opt/saltbox_mod/scripts/saltbox_sync_samba.sh`

### What `saltbox_sync.sh` Does:
1. **Mount Verification**: Validates that both `/mnt/local` (Tier 1 SSD) and `/mnt/remote/media` (Tier 2 HDD) are active mountpoints. If unmounted, the script aborts safely to prevent writing to root storage.
2. **Junk File Cleanup**: Purges OS junk files (`._*`, `.DS_Store`, `.localized`) from source directories before syncing.
3. **Optimized Rsync**: Uses `rsync --files-from` compiled dynamically from source files to transfer new media without scanning multi-terabyte remote targets.
4. **Source Age Deletion**: Deletes source files on the SSD older than `DELETE_AGE_MIN` (default: 90 minutes) once safely copied to the HDD warehouse, and cleans empty directories.
5. **Post-Sync Samba Trigger**: Launches `/opt/saltbox_mod/scripts/saltbox_sync_samba.sh` inside a named detached GNU Screen session (`saltbox_sync_samba`).
6. **Concurrent Run Protection**: Protected with `flock` at `/tmp/saltbox_sync.lock`.

---

## 2. Healthchecks.io Integration & Monitoring

The script integrates two distinct pings with [Healthchecks.io](https://healthchecks.io/):

1. **Check Ping (`CHECK_PING_URL`)**:
   - URL: `https://hc-ping.com/c68cb883-d088-44ba-80e5-dc1b360dcd35`
   - Triggered: Every time the script runs an evaluation (either automatic 30-minute interval or manual trigger).
   - Payload: Sends a plain-text status payload containing:
     - Run mode (Auto vs Force)
     - Disk space free on `/mnt/local`
     - Time elapsed since last sync
     - Decision (`ShouldRun: YES` or `ShouldRun: NO`)
     - Timestamp
2. **Sync Result Ping (`PING_URL`)**:
   - Triggered: Only when files were actually transferred, created, or deleted.
   - Payload: Posts the entire synchronization log file as the HTTP POST body.

---

## 3. Usage & CLI Flags

```bash
# 1. Automatic run (evaluates space threshold and time threshold):
/opt/saltbox_mod/scripts/saltbox_sync.sh

# 2. Forced immediate run (bypasses space and time checks):
/opt/saltbox_mod/scripts/saltbox_sync.sh -f

# 3. Install systemd timer and service (requires root / sudo):
sudo /opt/saltbox_mod/scripts/saltbox_sync.sh -i
# or
sudo /opt/saltbox_mod/scripts/saltbox_sync.sh --install-service
```

---

## 4. Key Script Variables

| Variable | Default Value | Purpose |
|---|---|---|
| `SOURCE_DIR` | `/mnt/local/Media/` | Source media ingest path (SSD) |
| `DEST_DIR` | `/mnt/remote/media/Media/` | Destination archive path (HDD) |
| `WATCH_DIR` | `/mnt/local` | Mount monitored for free space |
| `LOG_DIR` | `/media/cache/logs/script` | Output location for sync logs |
| `STATE_FILE` | `/opt/saltbox_mod/scripts/last_sync.state` | Epoch seconds of last execution |
| `LOCK_FILE` | `/tmp/saltbox_sync.lock` | Mutex lock preventing overlapping runs |
| `THRESHOLD_SPACE_GB` | `50` | Triggers sync if free space falls below 50 GB |
| `THRESHOLD_TIME_SEC` | `3600` | Triggers sync if more than 1 hour since last run |
| `DELETE_AGE_MIN` | `90` | Source retention window in minutes |

---

## 5. GNU Screen Management for Background Tasks

The post-sync Samba script runs in a detached GNU Screen session named `saltbox_sync_samba`.

```bash
# List all active screen sessions:
screen -ls

# Reattach to the Samba sync screen session:
screen -r saltbox_sync_samba

# Detach from within screen:
# Press Ctrl+A, then press D

# Kill / terminate the session manually:
screen -S saltbox_sync_samba -X quit
```

---

## 6. Systemd Service & Timer Management

When installed via `-i`, the script is managed by systemd:
- Service unit: `/etc/systemd/system/saltbox-sync.service`
- Timer unit: `/etc/systemd/system/saltbox-sync.timer` (runs every 30 minutes)

### Useful Systemd Commands:
```bash
# Check timer schedule:
systemctl list-timers --all | grep saltbox-sync

# Check timer status:
systemctl status saltbox-sync.timer

# View execution logs:
journalctl -u saltbox-sync.service -n 50 --no-pager

# Trigger manual service run via systemd:
sudo systemctl start saltbox-sync.service

# Follow live log files:
tail -F /media/cache/logs/script/sync_*.log
```
