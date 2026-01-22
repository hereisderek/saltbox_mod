#!/usr/bin/env bash

# Description:
# This script performs the synchronization of media files from local storage to remote storage.
# It uses rsync for transfer, cleans up temporary files, and manages logging.
# It includes locking to prevent concurrent runs and reports status to Healthchecks.io.

# Strict bash options
set -euo pipefail

# Check for required commands
for cmd in realpath rsync curl find df tee date mkdir rm grep mountpoint awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found. Aborting." >&2
        exit 1
    fi
done

# Locking Mechanism
LOCKFILE="/tmp/media_sync.lock"
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo "Script is already running. Exiting."
    exit 1
fi

# Configuration
log_dir="/media/cache/logs/script"
log_file_name="sync_$(date '+%Y-%m-%d_%H-%M-%S').log"
log_file="${log_dir}/${log_file_name}"
ping_url="https://hc-ping.com/4dbc165b-f88e-4523-b8c9-95585f0e65d3"
source_dir="/mnt/local/Media/"
dest_dir="/mnt/remote/media/Media/"
start_time=$(date +%s)

mkdir -p "$log_dir"
find "$log_dir" -name "sync_*.log" -mtime +7 -delete

log_ts() {
    printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$log_file"
}

# Check mounts
if ! mountpoint -q /mnt/local || ! mountpoint -q /mnt/remote/media; then
    log_ts "Error: Mount points missing. Aborting."
    exit 1
fi

log_ts "Cleaning up junk..."
find "$source_dir" -type f \( -name "._*" -o -name ".DS_Store" -o -name ".localized" \) -delete

log_ts "Syncing: $source_dir -> $dest_dir"
# Capture rsync output in memory
rsync_result=$(rsync -ah --stats --info=name1 "$source_dir" "$dest_dir" 2>&1 | tee -a "$log_file") || true

log_ts "Cleaning up empty local directories..."
find "$source_dir" -empty -type d -mmin +90 -delete

sync; sleep 0.2

# --- Stats Parsing ---
# Extract counts
rsync_created=$(awk '/Number of created files:/ {print $5}' <<< "$rsync_result" | tr -d ',' | grep . || echo 0)
rsync_deleted=$(awk '/Number of deleted files:/ {print $5}' <<< "$rsync_result" | tr -d ',' | grep . || echo 0)
rsync_transferred=$(awk '/Number of regular files transferred:/ {print $6}' <<< "$rsync_result" | tr -d ',' | grep . || echo 0)

# Extract Size (Human Readable)
# Rsync outputs "Total transferred file size: 1.23G bytes"
rsync_size=$(awk -F': ' '/Total transferred file size:/ {print $2}' <<< "$rsync_result" | sed 's/ bytes//' | grep . || echo "0")

total_changes=$((rsync_created + rsync_deleted + rsync_transferred))

end_time=$(date +%s)
duration_h=$(printf "%02d:%02d:%02d" $(( (end_time-start_time) / 3600 )) $(( ((end_time-start_time) % 3600) / 60 )) $(( (end_time-start_time) % 60 )))

# --- Final Summary Generation ---
if [ "$total_changes" -gt 0 ]; then
    SUMMARY="
=========================================
          SYNC CHANGE SUMMARY            
=========================================
Folder:      $source_dir
Files Sent:  $rsync_transferred
Created:     $rsync_created
Deleted:     $rsync_deleted
Total Size:  $rsync_size
Duration:    $duration_h
========================================="
    
    # Print summary to console and log
    echo "$SUMMARY" | tee -a "$log_file"
    
    log_ts "Changes detected. Sending log to Healthchecks..."
    curl -fsS -m 15 --retry 3 -X POST --data-binary @"${log_file}" "$ping_url" > /dev/null 2>&1
else
    log_ts "No changes. Total duration: ${duration_h}. Skipping ping."
fi


log_ts "Disk usage post-sync:"
df -h /mnt/local /mnt/remote/media | tee -a "$log_file"