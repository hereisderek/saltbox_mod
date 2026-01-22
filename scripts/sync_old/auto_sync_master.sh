#!/bin/bash

# Description:
# This script acts as a master controller for the saltbox auto-sync service.
# It monitors disk space on a watched directory and enforces a maximum time interval between syncs.
# It triggers the actual sync script (sync_local_to_remote.sh) when conditions are met.
# It can install itself as a systemd service and handles signals for manual triggers.

# --- Configuration ---
SYNC_SCRIPT="/opt/saltbox_mod/scripts/sync_local_to_remote.sh"
WATCH_DIR="/mnt/local"
THRESHOLD_GB=50
MAX_INTERVAL_SEC=7200      # 2 Hours
CHECK_INTERVAL_SEC=1800    # 30 Minutes
SERVICE_USER="derek"
SERVICE_GROUP="derek"
SERVICE_NAME="saltbox-autosync.service"
# ---------------------

# --- State ---
last_run=0
DRY_RUN=false

# --- Function: The Sync Execution ---
execute_sync() {
    local reason=$1
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] TRIGGER: $reason"
    
    if [ "$DRY_RUN" = true ]; then
        echo "  -> [DRY RUN] Would execute: $SYNC_SCRIPT"
        sleep 2
    else
        if [ -x "$SYNC_SCRIPT" ]; then
            "$SYNC_SCRIPT"
        else
            echo "  -> ERROR: $SYNC_SCRIPT not found or not executable."
        fi
    fi
    
    last_run=$(date +%s)
    echo "  -> Sync cycle finished. Timer reset (Next check in $((CHECK_INTERVAL_SEC / 60))m)."
}

# --- Signal Traps ---
# USR1: Standard check (check space first)
trap 'check_and_upload_signal' SIGUSR1
# USR2: Forced upload (skip space check)
trap 'execute_sync "EXTERNAL SIGNAL (Forced Upload -f)"' SIGUSR2

check_and_upload_signal() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] LOG: --upload signal received. Checking space..."
    local avail=$(df -BG "$WATCH_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ -n "$avail" ] && [ "$avail" -lt "$THRESHOLD_GB" ]; then
        execute_sync "EXTERNAL SIGNAL (--upload) - Space is low: ${avail}G < ${THRESHOLD_GB}G"
    else
        echo "  -> Space is sufficient (${avail}G >= ${THRESHOLD_GB}G). Skipping upload."
    fi
}

# --- Function: Install Service ---
install_service() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: Installation requires root (sudo)."
        exit 1
    fi

    SCRIPT_PATH=$(realpath "$0")
    echo "Installing systemd service..."

    cat <<EOF > "/etc/systemd/system/$SERVICE_NAME"
[Unit]
Description=Saltbox Auto-Sync Master Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_GROUP
ExecStart=$SCRIPT_PATH
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
    echo "Service '$SERVICE_NAME' installed and started as user '$SERVICE_USER'."
    exit 0
}

# --- Argument Parsing ---
FORCE_UPLOAD=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -i|--install) install_service ;;
        --dry-run) 
            DRY_RUN=true
            CHECK_INTERVAL_SEC=10
            MAX_INTERVAL_SEC=30
            ;;
        -f) FORCE_UPLOAD=true ;;
        --upload)
            PID=$(systemctl show -p MainPID "$SERVICE_NAME" | cut -d= -f2)
            if [ "$PID" -ne 0 ] && kill -0 "$PID" 2>/dev/null; then
                if [ "$FORCE_UPLOAD" = true ]; then
                    echo "Force signaling service (PID $PID) to sync NOW..."
                    kill -USR2 "$PID"
                else
                    echo "Signaling service (PID $PID) to check space and sync..."
                    kill -USR1 "$PID"
                fi
                exit 0
            else
                echo "Service not running. Executing manual logic..."
                if [ "$FORCE_UPLOAD" = true ]; then
                    execute_sync "MANUAL RUN (Forced)"
                else
                    check_and_upload_signal
                fi
                exit 0
            fi
            ;;
    esac
    shift
done

# --- Main Loop ---
run_master_loop() {
    echo "--- Auto-Sync Master Started (PID: $$) ---"
    echo "User: $(whoami) | Watching: $WATCH_DIR"
    
    while true; do
        current_time=$(date +%s)
        time_diff=$((current_time - last_run))
        available_gb=$(df -BG "$WATCH_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
        
        if [ "$time_diff" -ge "$MAX_INTERVAL_SEC" ]; then
            execute_sync "TIMER (Reached ${MAX_INTERVAL_SEC}s)"
        elif [ -n "$available_gb" ] && [ "$available_gb" -lt "$THRESHOLD_GB" ]; then
            execute_sync "LOW DISK SPACE (${available_gb}G < ${THRESHOLD_GB}G)"
        fi

        sleep "$CHECK_INTERVAL_SEC" & wait $!
    done
}

run_master_loop