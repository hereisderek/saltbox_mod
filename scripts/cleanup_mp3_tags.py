import os
import sys
import subprocess
import re

patterns = ["ifulicn.com", "wusunk.com"]

def get_tags(filepath):
    try:
        if not os.path.exists(filepath):
            return ""
        result = subprocess.run(["id3v2", "-l", filepath], capture_output=True)
        return result.stdout.decode('utf-8', errors='replace')
    except Exception as e:
        print(f"Error reading tags for {filepath}: {e}")
        return ""

def process_file(filepath):
    output = get_tags(filepath)
    if not output:
        return

    frames_to_remove = []
    remove_v1 = False
    
    # Matches frames like "TIT2 (Title/songname/content description): Value"
    v2_frame_regex = re.compile(r"^([A-Z0-9]{3,4})\s+\(.*\):\s+(.*)$")
    
    for line in output.splitlines():
        match = v2_frame_regex.match(line)
        if match:
            frame_id = match.group(1)
            value = match.group(2)
            
            for pattern in patterns:
                if pattern in value:
                    if frame_id not in frames_to_remove:
                        frames_to_remove.append(frame_id)
                        break
        else:
            # Check non-V2 lines (likely V1 output) for patterns
            for pattern in patterns:
                if pattern in line:
                    remove_v1 = True
                    break
    
    if remove_v1:
        print(f"Cleaning ID3v1 tags from {os.path.basename(filepath)}")
        try:
            subprocess.run(["id3v2", "-s", filepath], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"Error removing ID3v1 tags for {filepath}: {e}")

    if frames_to_remove:
        print(f"Cleaning {len(frames_to_remove)} ID3v2 tags from {os.path.basename(filepath)}")
        for frame in frames_to_remove:
            cmd = ["id3v2", "-r", frame, filepath]
            try:
                subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except subprocess.CalledProcessError as e:
                print(f"Error removing tag {frame} for {filepath}: {e}")

def process_directory(directory):
    print(f"Scanning {directory}...")
    count = 0
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.lower().endswith(".mp3"):
                process_file(os.path.join(root, file))
                count += 1
    print(f"Processed {count} MP3 files.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: python3 {os.path.basename(sys.argv[0])} <file_or_directory> [file_or_directory ...]")
        sys.exit(1)
    
    for target in sys.argv[1:]:
        if os.path.isfile(target):
            process_file(target)
        elif os.path.isdir(target):
            process_directory(target)
        else:
            print(f"Error: {target} is not a valid file or directory")
