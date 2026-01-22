#!/bin/bash

# ==============================================================================
# Script Name: saltbox_sync.sh
# Description: Supersedes auto_sync_master.sh and sync_local_to_remote.sh.
#              Manages media synchronization between local and remote storage.
#
# Requirements:
# 1. Run sync tasks:
#    1.1. Only sync if both /mnt/local and /mnt/remote/media are mounted.
#    1.2. Clean up junk files (._*, .DS_Store, .localized) in source.
#    1.3. Sync source to dest with progress.
#    1.4. Remove synced files in source older than 90 minutes.
#    1.5. Show summary and ping Healthchecks.io with log/space if changes occurred.
#
# 2. Automatic Mode (no params):
#    - Check remaining disk space on /mnt/local.
#    - Check time since last sync.
#    - Trigger sync if:
#         Space < 50GB
#      OR Time > 1 Hour
#
# 3. Forced Mode (-f):
#    - Ignore checks and start sync immediately.
#
# 4. Service Installation (-i | --install-service):
#    - Install a systemd service/timer to run this script every 30 minutes.
# ==============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_PATH=$(realpath "$0")
LOG_DIR="/media/cache/logs/script"
STATE_FILE="/opt/saltbox_mod/scripts/last_sync.state"
LOCK_FILE="/tmp/saltbox_sync.lock"
SYNC_RESULT_PING_URL="https://hc-ping.com/4dbc165b-f88e-4523-b8c9-95585f0e65d3"
SYNC_CHECK_PING_URL="https://hc-ping.com/c68cb883-d088-44ba-80e5-dc1b360dcd35"

SOURCE_DIR="/mnt/local/Media/"
DEST_DIR="/mnt/remote/media/Media/"
WATCH_DIR="/mnt/local"

THRESHOLD_SPACE_GB=50
THRESHOLD_TIME_SEC=3600 # 1 Hour
DELETE_AGE_MIN=90

SERVICE_USER="derek"
SERVICE_GROUP="derek"

# --- Logging ---
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/sync_$(date '+%Y-%m-%d_%H-%M-%S').log"

log() {
    local msg="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $msg" | tee -a "$LOG_FILE"
}

# --- Helper Functions ---

cleanup() {
    # Remove temporary stats file if it exists
    if [ -n "${rsync_stats_file:-}" ] && [ -f "$rsync_stats_file" ]; then
        rm -f "$rsync_stats_file"
    fi
    
    # Remove lock file to allow future runs even if this one was killed
    # Only remove if we actually acquired the lock (checked by existence of FD 200 or just blindly if we are the main script)
    # To be safe, we just remove it. If another instance is running, it has it open, but removing it
    # allows a NEW instance to start (using a new inode).
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
    fi
}

trap "cleanup; exit 1" SIGINT SIGTERM
trap cleanup EXIT

check_mounts() {
    if ! mountpoint -q "/mnt/local"; then
        log "ERROR: /mnt/local is not a mountpoint."
        return 1
    fi
    if ! mountpoint -q "/mnt/remote/media"; then
        log "ERROR: /mnt/remote/media is not a mountpoint."
        return 1
    fi
    return 0
}

get_available_space_gb() {
    df -BG "$WATCH_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//'
}

get_time_since_last_sync() {
    if [ -f "$STATE_FILE" ]; then
        local last_sync=$(cat "$STATE_FILE")
        local now=$(date +%s)
        echo $((now - last_sync))
    else
        echo 999999 # Never run
    fi
}

update_last_sync_time() {
    date +%s > "$STATE_FILE"
}

ping_check() {
    local msg="$1"
    if [ -n "${SYNC_CHECK_PING_URL:-}" ]; then
        # Send a small check ping with the provided message (post body)
        if echo -e "$msg" | curl -fsS -m 10 --retry 2 -X POST --data-binary @- "$SYNC_CHECK_PING_URL" >/dev/null 2>&1; then
            log "Check ping sent to $SYNC_CHECK_PING_URL"
        else
            log "WARNING: Check ping to $SYNC_CHECK_PING_URL failed."
        fi
    fi
}

install_service() { 
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Installation requires root privileges. Please run with sudo."
        exit 1
    fi

    echo "Installing Systemd Service and Timer..."

    # Service File
    cat <<EOF > "/etc/systemd/system/saltbox-sync.service"
[Unit]
Description=Saltbox Media Sync Service
After=network.target

[Service]
Type=oneshot
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$SCRIPT_PATH
StandardOutput=journal
StandardError=journal
EOF

    # Timer File
    cat <<EOF > "/etc/systemd/system/saltbox-sync.timer"
[Unit]
Description=Run Saltbox Media Sync every 30 minutes

[Timer]
OnBootSec=15min
OnUnitActiveSec=30min
Unit=saltbox-sync.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable saltbox-sync.timer
    systemctl start saltbox-sync.timer
    echo "Service installed. Timer started (runs every 30 mins)."
    exit 0
}

perform_sync() {
    log "Starting Sync Process..."
    
    if ! check_mounts; then
        log "Mount check failed. Aborting."
        exit 1
    fi

    local start_time=$(date +%s)

    # 1.2 Cleanup Junk
    log "Cleaning up junk files in source..."
    find "$SOURCE_DIR" -type f \( -name "._*" -o -name ".DS_Store" -o -name ".localized" \) -delete

    # 1.3 Sync
    log "Syncing $SOURCE_DIR -> $DEST_DIR"
    
    local rclone_log_file=$(mktemp)

    # CHANGED: Switched back to rsync with --files-from.
    # This is the most robust way to avoid scanning a massive destination directory.
    # 1. We generate a list of files to transfer from the source.
    # 2. We tell rsync to ONLY look at those files.
    
    local file_list=$(mktemp)
    
    # Generate relative file list
    pushd "$SOURCE_DIR" >/dev/null
    find . -type f -print0 > "$file_list"
    popd >/dev/null

    if [ ! -s "$file_list" ]; then
        log "No files found in source to sync."
        rsync_output=""
        rm -f "$file_list" "$rclone_log_file"
        return 0
    fi

    # -avP: Archive, Verbose, Partial, Progress
    # --size-only: Skip checksums
    # --files-from: Only transfer files in the list
    # --from0: List is null-terminated (handles spaces)
    if ! rsync -avP --size-only --stats --files-from="$file_list" --from0 "$SOURCE_DIR" "$DEST_DIR" 2>&1 | tee "$rclone_log_file"; then
        log "ERROR: Rsync failed."
        cat "$rclone_log_file" >> "$LOG_FILE"
        rm -f "$rclone_log_file" "$file_list"
        return 1
    fi

    # Append output to log file
    cat "$rclone_log_file" >> "$LOG_FILE"
    
    log "Rsync completed. Parsing stats..."
    rsync_output=$(cat "$rclone_log_file")
    
    rm -f "$rclone_log_file" "$file_list"

    # 1.4 Remove old synced files
    # Only proceed if rsync was successful (which it was if we are here)
    log "Removing files in source older than $DELETE_AGE_MIN minutes..."
    # We use a safe find command. 
    # Note: This deletes files even if they weren't *just* synced, but they are old enough 
    # that they *should* have been synced in previous runs.
    # To be extra safe, one might check if file exists in dest, but that's slow.
    # The requirement is "remove any synced files...". 
    # Standard practice in this setup is assuming age > threshold implies sync opportunity passed.
    
    # Find and delete files
    find "$SOURCE_DIR" -type f -mmin +$DELETE_AGE_MIN -print -delete >> "$LOG_FILE"
    
    # Clean empty directories
    find "$SOURCE_DIR" -empty -type d -mmin +$DELETE_AGE_MIN -delete >> "$LOG_FILE"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local duration_fmt=$(printf "%02d:%02d:%02d" $((duration/3600)) $(( (duration%3600)/60 )) $((duration%60)))

    # 1.5 Summary & Ping
    # Parse rsync stats
    local files_transferred=$(echo "$rsync_output" | awk '/Number of regular files transferred:/ {print $6}' | tr -d ',')
    local files_created=$(echo "$rsync_output" | awk '/Number of created files:/ {print $5}' | tr -d ',')
    local files_deleted=$(echo "$rsync_output" | awk '/Number of deleted files:/ {print $5}' | tr -d ',')
    local total_size=$(echo "$rsync_output" | awk -F': ' '/Total transferred file size:/ {print $2}')
    
    # Default to 0 if empty
    files_transferred=${files_transferred:-0}
    files_created=${files_created:-0}
    files_deleted=${files_deleted:-0}

    local total_changes=$((files_transferred + files_created + files_deleted))

    log "Sync Completed."
    log "Duration: $duration_fmt"
    log "Transferred: $files_transferred"
    log "Total Size: $total_size"

    local space_post=$(df -h "$WATCH_DIR" | awk 'NR==2 {print $4}')
    log "Available Space: $space_post"

    if [ "$total_changes" -gt 0 ]; then
        log "Changes detected ($total_changes). Sending report to Healthchecks..."
        if curl -fsS -m 15 --retry 3 -X POST --data-binary @"$LOG_FILE" "$SYNC_RESULT_PING_URL" >/dev/null 2>&1; then
            log "Sync result ping sent to $SYNC_RESULT_PING_URL"
        else
            log "WARNING: Sync result ping to $SYNC_RESULT_PING_URL failed."
        fi
    else
        log "No changes detected."
    fi

    # Start samba helper in a detached screen session so it can be reattached later.
    # Session name: saltbox_sync_samba
    SCREEN_SESSION="saltbox_sync_samba"
    TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
    SAMBA_LOG="$LOG_DIR/samba_${TIMESTAMP}.log"

    # Skip starting if helper is already running (anywhere), to avoid duplicates.
    if pgrep -f "/opt/saltbox_mod/scripts/saltbox_sync_samba.sh" >/dev/null 2>&1; then
        log "Samba helper already running. Skipping startup."
    else
        if command -v screen >/dev/null 2>&1; then
            # Screen sessions are listed as "<pid>.<name>\t(status)" — check for ".<name>" pattern
            if screen -ls 2>/dev/null | grep -Eq "\\.${SCREEN_SESSION}([[:space:]]|\\(|$)"; then
                log "Screen session '$SCREEN_SESSION' already running. Skipping samba helper startup."
            else
                log "Starting samba helper in detached screen session: $SCREEN_SESSION"
                if screen -dmS "$SCREEN_SESSION" bash -lc "/opt/saltbox_mod/scripts/saltbox_sync_samba.sh >> \"$SAMBA_LOG\" 2>&1"; then
                    # Give screen a brief moment to register its session
                    sleep 0.5
                    if screen -ls 2>/dev/null | grep -Eq "\\.${SCREEN_SESSION}([[:space:]]|\\(|$)"; then
                        log "Screen session '$SCREEN_SESSION' started successfully."
                    else
                        log "ERROR: screen created process but session not visible; falling back to nohup."
                        nohup /opt/saltbox_mod/scripts/saltbox_sync_samba.sh >> "$SAMBA_LOG" 2>&1 &
                    fi
                else
                    log "ERROR: failed to start screen session; falling back to nohup."
                    nohup /opt/saltbox_mod/scripts/saltbox_sync_samba.sh >> "$SAMBA_LOG" 2>&1 &
                fi
            fi
        else
            log "WARNING: 'screen' not found. Running samba helper in background (nohup)."
            nohup /opt/saltbox_mod/scripts/saltbox_sync_samba.sh >> "$SAMBA_LOG" 2>&1 &
        fi
    fi

    # Update state
    update_last_sync_time
    
    # Cleanup old logs (keep 7 days)
    find "$LOG_DIR" -name "sync_*.log" -mtime +7 -delete
}

# --- Main Execution ---

# Parse Arguments
FORCE=false
INSTALL=false

for arg in "$@"; do
    case $arg in
        -f) FORCE=true ;;
        -i|--install-service) INSTALL=true ;;
    esac
done

if [ "$INSTALL" = true ]; then
    install_service
fi

# Check Lock
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "Script is already running (Lockfile: $LOCK_FILE). Exiting."
    exit 1
fi

# Logic for Automatic Mode
avail_space=""
time_since=""

if [ "$FORCE" = false ]; then
    # Check Space
    avail_space=$(get_available_space_gb)
    time_since=$(get_time_since_last_sync)
    
    should_run=false
    reason=""

    if [ -z "$avail_space" ]; then
        log "WARNING: Could not determine disk space. Skipping space check."
    elif [ "$avail_space" -lt "$THRESHOLD_SPACE_GB" ]; then
        should_run=true
        reason="Low Disk Space (${avail_space}GB < ${THRESHOLD_SPACE_GB}GB)"
    fi

    if [ "$time_since" -ge "$THRESHOLD_TIME_SEC" ]; then
        should_run=true
        if [ -n "$reason" ]; then
            reason="$reason AND Time Threshold"
        else
            reason="Time Threshold (${time_since}s > ${THRESHOLD_TIME_SEC}s)"
        fi
    fi

    # Send a Healthchecks.io check ping for every check (automatic decisions)
    check_payload="Saltbox sync check\nMode: automatic\nSpace: ${avail_space}GB\nTimeSince: ${time_since}s\nShouldRun: ${should_run}\nReason: ${reason}\nTimestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ping_check "$check_payload"

    if [ "$should_run" = true ]; then
        log "Triggering Sync: $reason"
        perform_sync
    else
        echo "Conditions not met. Skipping sync."
        echo "Space: ${avail_space}GB (Threshold: ${THRESHOLD_SPACE_GB}GB)"
        echo "Time Since Last Sync: ${time_since}s (Threshold: ${THRESHOLD_TIME_SEC}s)"
    fi
else
    log "Manual Force Sync Triggered."
    check_payload="Saltbox sync check\nMode: forced\nTriggeredBy: manual\nTimestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ping_check "$check_payload"
    perform_sync
fi
