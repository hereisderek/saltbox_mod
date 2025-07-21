#!/bin/bash

# Script to update qBittorrent tracker list
# This script fetches tracker lists from multiple URLs, merges them,
# removes duplicates, and updates the qBittorrent configuration file
QBITTORRENT_CONF="/opt/qbittorrent.bak/qBittorrent/qBittorrent.conf"
TRACKER_URLS=(
    "https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt"
    "https://cf.trackerslist.com/best.txt"
)
SECTION="[BitTorrent]"
SETTING="Session\\\\AdditionalTrackers"

# Check if config file exists
if [ ! -f "$QBITTORRENT_CONF" ]; then
    echo "Error: qBittorrent config file not found at $QBITTORRENT_CONF"
    exit 1
fi

# Create temporary file for merged trackers
TEMP_FILE=$(mktemp)

# Download and merge tracker lists
echo "Downloading and merging tracker lists..."
for url in "${TRACKER_URLS[@]}"; do
    echo "Fetching trackers from: $url"
    if curl -s --fail "$url" >> "$TEMP_FILE"; then
        echo "Successfully downloaded trackers from $url"
    else
        echo "Warning: Failed to download trackers from $url, skipping..."
    fi
done

# Check if we got any trackers
if [ ! -s "$TEMP_FILE" ]; then
    echo "Error: No trackers were downloaded from any source."
    rm "$TEMP_FILE"
    exit 1
fi


# Process trackers: remove empty lines, sort, remove duplicates, and replace newlines with '\n'
echo "Processing tracker list..."
TRACKERS=$(grep -v "^$" "$TEMP_FILE" | sort | uniq | tr '\n' '\\n')

echo "Total unique trackers: $(echo -e "$TRACKERS" | grep -c "announce")"
echo "Trackers list:"
echo -e "$TRACKERS"

# Clean up temp file
rm "$TEMP_FILE"

# Create a backup of the config file
# BACKUP_FILE="${QBITTORRENT_CONF}.bak.$(date +%Y%m%d%H%M%S)"
# cp "$QBITTORRENT_CONF" "$BACKUP_FILE"
# echo "Created backup at $BACKUP_FILE"

# Update the config file
echo "Updating qBittorrent config file..."
# Check if the BitTorrent section exists
if ! grep -q "^\[BitTorrent\]$" "$QBITTORRENT_CONF"; then
    echo "Adding [BitTorrent] section..."
    echo -e "\n[BitTorrent]" >> "$QBITTORRENT_CONF"
fi

# Check if the AdditionalTrackers setting exists
if grep -q "Session\\\\AdditionalTrackers=" "$QBITTORRENT_CONF"; then
    # Use perl for more reliable handling of backslashes in regex replacements
    perl -i -pe "s|Session\\\\AdditionalTrackers=.*|Session\\\\AdditionalTrackers=$TRACKERS|" "$QBITTORRENT_CONF"
else
    # Add the setting to the [BitTorrent] section
    perl -i -pe "s|^\[BitTorrent\]$|\[BitTorrent\]\nSession\\\\AdditionalTrackers=$TRACKERS|" "$QBITTORRENT_CONF"
fi

# Check if update was successful
if [ $? -eq 0 ]; then
    echo "Successfully updated tracker list in qBittorrent config file."
    echo "Total trackers added: $(echo -e "$TRACKERS" | grep -c "announce")"
else
    echo "Error: Failed to update tracker list."
    echo "Restoring backup..."
    cp "$BACKUP_FILE" "$QBITTORRENT_CONF"
    exit 1
fi

echo "Done!"