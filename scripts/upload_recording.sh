ROOT_DIR=/mnt/remote/media/Media/Recording/shinobi
CAM_DIR="${ROOT_DIR}/Fd9HY20KVX/livingroom"
PROGRESS_DIR=/mnt/tmp/recording/progress
COMPLETE_DIR=/mnt/tmp/recording/complete
TODAY=$(date +'%Y-%m-%d')
MAX_DURATION=$((12*60*60)) # 12 hours in seconds

mkdir -p $OUT_DIR

files_sorted=$(ls "$directory" | sort)

# Get today's date in the format YYYY-MM-DD
today=$(date +'%Y-%m-%d')

# Initialize variables for tracking combined duration and processed files
combined_duration=0
processed_files=""


# Function to extract the date and hour from the filename
extract_date_hour() {
    local filename="$1"
    local date_hour=$(echo "$filename" | cut -dT -f2 | cut -d- -f1-2)
    echo "$date_hour"
}

# Function to extract date from filename
extract_date() {
    echo "$1" | cut -d 'T' -f 1
}



# Function to combine files and split if necessary
combine_and_split() {
    local input_files="$1"
    local output_file="$2"
    printf "Combining %s into %s\n" "$input_files" "$output_file"
    # Combine input files into one video
    ffmpeg -f concat -safe 0 -i <(printf "file '$directory/%s'\n" $input_files) -c copy "$output_file"
}



# Process each video file
for file in "$directory"/*.mp4; do
    # Extract date from filename
    date=$(basename "$file" | cut -d 'T' -f 1)
    # Skip files from today
    if [[ "$date" == "$today" ]]; then
        continue
    fi
    # Check if file has already been processed
    if echo "$processed_files" | grep -q "$date"; then
        continue
    fi
    # Initialize variables for combining videos on the same day
    input_files=""
    output_file="$output_directory/${date}_combined.mp4"
    # Process all files from the same day
    for f in "$directory"/*"$date"*.mp4; do
        # Extract timestamp from filename
        timestamp=$(basename "$f" | cut -d 'T' -f 2 | cut -d '.' -f 1 | tr '-' ':')
        # Calculate duration of current video
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f")
        # Check if adding this file would exceed 12 hours
        if (( $(echo "$total_duration + $duration > 43200" | bc -l) )); then
            # If adding this file would exceed 12 hours, combine and split
            combine_and_split "$input_files" "$output_file"
            # Reset variables for next segment
            input_files="$f"
            output_file="$output_directory/${date}_$(date -d "$timestamp" +'%Y-%m-%d_%H-%M-%S').mp4"
            total_duration=0
        else
            # Add file to list of input files
            input_files+="|$f"
            total_duration=$(echo "$total_duration + $duration" | bc -l)
        fi
        # Mark file as processed
        processed_files+=" $date"
    done
    # Combine remaining files if any
    if [[ -n "$input_files" ]]; then
        combine_and_split "$input_files" "$output_file"
    fi
done



combine_videos() {
    if [ -n "$processed_files" ]; then
        combined_filename="$directory/combined_$(date -d "$date" +'%Y-%m-%d').mp4"
        ffmpeg -f concat -safe 0 -i <(printf "file '$directory/%s'\n" $processed_files) -c copy "$combined_filename"
        processed_files=""
        combined_duration=0
    fi
}






# Loop through each file
for file in $(files_sorted); do
    filename=$(basename "$file")
    date=$(echo "$filename" | cut -d 'T' -f 1)

    # Skip files from today
    if [ "$date" == "$today" ]; then
        continue
    fi

    # Check if combining videos would exceed 12 hours
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file")
    combined_duration=$(echo "$combined_duration + $duration" | bc)

    if (( $(echo "$combined_duration > 43200" | bc -l) )); then
        combine_videos
    fi

    # Add file to the list of processed files
    processed_files="$processed_files $filename"
done




# ls| cut -d 'T' -f 1|sort -u