#!/bin/bash

combined_string=""
saltbox=("autoscan" "btop" "portainer" "iperf3" "nethogs") #"core" 
sandbox=("jellyseerr" "duplicati" "speedtest" "sshwifty" "stash" "immich" "recyclarr" "reposilite" "nextcloud")
mod=("restreamer" "youtubedl")

append_and_combine() {
    local list=("$@")
    local append_string="${list[-1]}"
    unset list[-1]
    for item in "${list[@]}"
    do
        combined_string+="${append_string}${item} "
    done
}



# Combine all three lists
append_and_combine "${saltbox[@]}" ""
append_and_combine "${sandbox[@]}" "sandbox-"
append_and_combine "${mod[@]}" "mod-"

echo $combined_string
# sleep 2
sb install  $combined_string