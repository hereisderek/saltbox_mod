#!/bin/bash

# Description:
# This script is a wrapper to run the sync_local_to_remote.sh script in a detached screen session.
# It ensures that only one instance of the sync session is running at a time.
# Intended to be run via cron.

script_dir=$(dirname $(readlink -f $0))

if ! /usr/bin/screen -list | /bin/grep -q "sync_download"; then
    printf "Starting sync_local_to_remote.sh in screen session\n"
    /usr/bin/screen -mdS sync_download ${script_dir}/sync_local_to_remote.sh
fi


# to add this to crontab, run `crontab -e` and add the following line:

# command="*/30 * * * * /opt/saltbox_mod/scripts/sync_local_to_remote_async.sh"
# (crontab -l ; echo "${command} ${url}") | crontab - ;crontab -l