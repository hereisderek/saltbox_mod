#!/usr/bin/env bash

# Get the full path of the script
SCRIPT_PATH=$(realpath "$0")

# Check if the script is already running using the script path
#if ps -ef | grep -q "[^]]$SCRIPT_PATH"; then
#    echo "Script is already running. Exiting."
#    exit 1
#fi

log_dir="/media/cache/logs/script" 
log_file_name="sync_$(date '+%Y-%m-%d_%H-%M-%S').log"
log_file="${log_dir}/${log_file_name}"
ping_url="https://hc-ping.com/4dbc165b-f88e-4523-b8c9-95585f0e65d3"


start_time=$(date +%s)

mkdir -p $log_dir; /bin/rm -rfv "$log_file" 

# printf "disk usage pre moving\n" | tee -a "$log_file"
# df -h /mnt/local /mnt/remote/media | tee -a "$log_file"
# printf "\n" | tee -a "$log_file"

printf "removing rubish..\n"| tee -a "$log_file"
find /mnt/local/ -type f "(" -name "._*" -o -name ".DS_Store" -o -name ".localized" ")" -exec sh -c "echo deleting \"{}\"; rm -rf \"{}\"; " \;| tee -a "$log_file"
printf "\n" | tee -a "$log_file"

# printf "copying metadata..\n" | tee -a "$log_file"
# rsync -avhP /mnt/local/tmp/metadata /mnt/remote/media/tmp/metadata | tee -a "$log_file"
# printf "\n" | tee -a "$log_file"

printf "copying media..\n"| tee -a "$log_file"
rsync -ah --info=stats2,progress2,NAME --stats  /mnt/local/Media/ /mnt/remote/media/Media/ | tee -a "$log_file"
printf "\n" | tee -a "$log_file"

printf "removing old media from local.."| tee -a "$log_file"
find /mnt/local/Media/ -type f -mmin +90 -exec sh -c "printf \" \n {}\"; rm -rf \"{}\"; " \;| tee -a "$log_file"
find /mnt/local/Media/ -empty -type d -mmin +90 -delete| tee -a "$log_file"
printf "\n\n" | tee -a "$log_file"

sync; sleep 0.2

printf "disk usage post moving\n" | tee -a "$log_file"
df -h /mnt/local /mnt/remote/media | tee -a "$log_file"
printf "\n" | tee -a "$log_file"


end_time=$(date +%s)
duration=$((end_time - start_time))
duration_h=$(printf "%02d:%02d:%02d" $((duration / 3600)) $(((duration % 3600) / 60)) $((duration % 60)))

printf "total duration: ${duration_h}\n" | tee -a "$log_file"
curl -fsS -m 10 --retry 5 -X POST --data-binary @${log_file}  -o /dev/null  "$ping_url" #> /dev/null 2>&1

sleep 3
