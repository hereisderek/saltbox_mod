# YTDL-Sub — Technical Service & Operations Guide

**App Name**: `ytdl_sub`  
**Container Name**: `ytdl-sub`  
**Author / Maintainer**: `hereisderek`  
**Saltbox Mod Repository**: [https://github.com/hereisderek/saltbox_mod](https://github.com/hereisderek/saltbox_mod)  
**Role Path**: `/opt/saltbox_mod/roles/ytdl_sub`  
**Upstream Project**: [https://github.com/jmbannon/ytdl-sub](https://github.com/jmbannon/ytdl-sub)  
**Documentation**: [https://ytdl-sub.readthedocs.io/](https://ytdl-sub.readthedocs.io/)  

---

## 1. Overview & Architecture

`ytdl-sub` is an automated tool that downloads and formats media from YouTube, SoundCloud, LinkedIn Learning, and other platforms into media libraries structured for Jellyfin, Plex, Kodi, or Emby.

### Within the Saltbox Ecosystem:
- **Deployment**: Managed as an automated container under Docker CE (`overlay2` data root at `/media/data/docker`).
- **Scheduling**: Managed via internal cron (`CRON_SCHEDULE="0 */6 * * *"`, `CRON_RUN_ON_START="true"`). The entrypoint script `/cron` invokes `ytdl-sub sub /config/subscriptions.yaml`.
- **Application Directory**: `/opt/ytdl-sub` mounted as `/config` inside the container.
- **Media Root**: `/mnt/unionfs/Media/Youtube/ytdl-sub` mounted as `/ytdl_sub`.
- **High-Speed Cache & Logs**: Application cache (`/config/.cache`), metadata working directory (`/config/.ytdl-sub-working-directory`), and run logs (`/config/logs`) are mapped to NVMe flash at `/media/cache/`.

---

## 2. Directory Hierarchy & Category Standards

All downloads must be organized under standardized top-level categories within the unified media library:

```
/ytdl_sub/                          # Host: /mnt/unionfs/Media/Youtube/ytdl-sub
├── channels/                       # YouTube Channels (Chronological TV shows)
│   ├── <Channel Name>/
│   │   ├── Season 2024/
│   │   │   ├── s2024.eMMDD - <Title>.mkv
│   │   │   └── s2024.eMMDD - <Title>.nfo
│   │   ├── poster.jpg
│   │   └── tvshow.nfo
├── courses/                        # Online Learning & Modular Courses
│   ├── linkedin-learning/          # LinkedIn Learning courses
│   ├── coursera/                   # Coursera courses
│   ├── deeplearning/               # DeepLearning.AI courses
│   └── udemy/                      # Udemy courses
├── mv/                             # Music Videos (Jellyfin Music Videos structure)
├── movies/                         # YouTube Movies & Documentaries
└── music/                          # YouTube Music releases & albums
```

### Storage Architecture & Remote Sync
1. **Tier 1 (SSD Cache)**: PVE ZFS local storage at `/mnt/storage/media/Media/Youtube/ytdl-sub/`.
2. **Tier 2 (HDD Warehouse)**: Remote NAS warehouse at `china-sftp:/vol8/1002/Storage/Media/Youtube/ytdl-sub/`.
3. **MergerFS / UnionFS**: Unified read/write mount at `/mnt/unionfs/Media/Youtube/ytdl-sub` using `NC` (No Create) branch policy, ensuring writes only occur on Tier 1 SSD.
4. **Data Sync Engine**: `/opt/saltbox_mod/scripts/saltbox_sync.sh` rsyncs staged downloads to Tier 2 and cleans up aged local copies (>90 min).

> [!CAUTION]
> **Zero Remount Constraint**:
> Never unmount, remount, or restart mount services (`mergerfs`, `rclone`). When reorganizing categories or moving media (e.g. moving channels from legacy `tv_shows/` to `channels/`), you **must** mirror moves server-side on both local PVE and remote SFTP using `rclone moveto` to keep the VFS cache coherent and avoid multi-gigabyte re-syncs.

---

## 3. Cookie Management & Authentication

Many video platforms (LinkedIn Learning, Coursera, Udemy, age-gated/private YouTube) require active session cookies.

### Storage Convention
All cookie files must reside on the host at:
```filepath
/opt/ytdl-sub/cookies/
```
Inside the container, this is accessible at:
```filepath
/config/cookies/
```

### Standard File Naming
- `linkedin.txt` — LinkedIn Learning session (`.linkedin.com`)
- `coursera.txt` — Coursera session (`.coursera.org`)
- `deeplearning.txt` — DeepLearning.AI session (`.deeplearning.ai`)
- `udemy.txt` — Udemy session (`.udemy.com`)
- `youtube.txt` (or `/config/cookie.txt`) — YouTube session

### Extracting & Exporting Cookies from macOS Chrome
macOS encrypts Chrome cookies using AES-128-CBC with a PBKDF2-derived key stored in Keychain (`Chrome Safe Storage`).

To extract and format them into standard Netscape cookie format:
```python
import hashlib, os, shutil, sqlite3
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.padding import PKCS7

# Retrieve Keychain password via: security find-generic-password -s "Chrome Safe Storage" -w
password = b'<KEYCHAIN_PASSWORD>'
key = hashlib.pbkdf2_hmac('sha1', password, b'saltysalt', 1003, dklen=16)
iv = b' ' * 16

# Chrome DB copy
tmp_db = '/tmp/chrome_cookies.db'
shutil.copy2(
    os.path.expanduser(
        '~/Library/Application Support/Google/Chrome/<Profile>/Cookies'
    ),
    tmp_db,
)
conn = sqlite3.connect(tmp_db)
c = conn.cursor()
c.execute(
    'SELECT host_key, path, is_secure, expires_utc, name, encrypted_value FROM'
    ' cookies WHERE host_key LIKE ?',
    ('%.linkedin.com%',),
)

lines = ['# Netscape HTTP Cookie File', '']
for host_key, path, is_secure, expires_utc, name, enc in c.fetchall():
  if enc.startswith(b'v10'):
    enc = enc[3:]
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    dec = cipher.decryptor().update(enc) + cipher.decryptor().finalize()
    unp = PKCS7(128).unpadder()
    val = (unp.update(dec) + unp.finalize())[32:].decode(
        'utf-8', errors='replace'
    )

    subdomain = 'TRUE' if host_key.startswith('.') else 'FALSE'
    secure = 'TRUE' if is_secure else 'FALSE'
    exp = int((expires_utc / 1000000) - 11644473600) if expires_utc > 0 else 0
    lines.append(f'{host_key}\t{subdomain}\t{path}\t{secure}\t{exp}\t{name}\t{val}')

conn.close()
os.remove(tmp_db)
with open('/tmp/linkedin.txt', 'w') as f:
  f.write('\n'.join(lines) + '\n')
```

Deploy the exported file to Saltbox:
```bash
scp /tmp/linkedin.txt saltbox.local:/opt/ytdl-sub/cookies/
ssh saltbox.local "chmod 644 /opt/ytdl-sub/cookies/linkedin.txt"
```

---

## 4. Subscriptions Configuration (`subscriptions.yaml`)

Path: `/opt/ytdl-sub/subscriptions.yaml`

### Global Presets (`__preset__`)
Defines default download directories, throttle protection, chapter embedding, and multi-language subtitle rules:

```yaml
__preset__:
  overrides:
    chunk_max_downloads: 20
    tv_show_directory: "/ytdl_sub/channels"
    movies_directory: "/ytdl_sub/movies"
    music_directory: "/ytdl_sub/music"
    music_video_directory: "/ytdl_sub/mv"
    only_recent_date_range: "3months"
    only_recent_max_files: 30

  ytdl_options:
    cookiefile: "/config/cookie.txt"

  subtitles:
    embed_subtitles: True
    languages:
      - "en"
      - "zh"
    allow_auto_generated_subtitles: True

  chapters:
    embed_chapters: True

  plugin(s):
    embed_thumbnail: True
    throttle_protection:
      sleep_per_download_s:
        min: 1.2
        max: 7.8
      sleep_per_subscription_s:
        min: 5.0
        max: 8.1
```

---

### Category 1: YouTube Channels
Use `Jellyfin TV Show by Date` to organize entries by chronological upload seasons:

```yaml
Jellyfin TV Show by Date:

  = Technology | = Hardware | = Electronics:
    "Ben Eater": "https://www.youtube.com/@BenEater"

  = Technology | = Software Engineering | = Android | = Kotlin | Only Recent Archive:
    "~Philipp Lackner":
      url: "https://www.youtube.com/@PhilippLackner"
      only_recent_date_range: "20months"
```

---

### Category 2: Online Courses
Use `Jellyfin TV Show Collection | season_by_collection__episode_by_playlist_index` for structured, sequential courses:

> [!IMPORTANT]
> **LinkedIn Learning Collections**:
> `yt-dlp` does **not** natively resolve `/learning/collections/<id>` URLs. Collections must be expanded into individual course slugs (`https://www.linkedin.com/learning/<course-slug>`) before adding to `subscriptions.yaml`.

```yaml
Jellyfin TV Show Collection | season_by_collection__episode_by_playlist_index:

  # --- LinkedIn Learning ---
  = Course | = LinkedIn Learning:
    "PLC Sequencer Logic":
      overrides:
        tv_show_directory: "/ytdl_sub/courses/linkedin-learning"
        s01_name: "PLC Sequencer Logic"
        s01_url: "https://www.linkedin.com/learning/plc-sequencer-logic"
      ytdl_options:
        cookiefile: "/config/cookies/linkedin.txt"

  # --- Coursera ---
  = Course | = Coursera:
    "Machine Learning":
      overrides:
        tv_show_directory: "/ytdl_sub/courses/coursera"
        s01_name: "Supervised Machine Learning"
        s01_url: "https://www.coursera.org/learn/machine-learning-slug"
      ytdl_options:
        cookiefile: "/config/cookies/coursera.txt"

  # --- Udemy ---
  = Course | = Udemy:
    "Docker Mastery":
      overrides:
        tv_show_directory: "/ytdl_sub/courses/udemy"
        s01_name: "Docker Mastery"
        s01_url: "https://www.udemy.com/course/docker-mastery/"
      ytdl_options:
        cookiefile: "/config/cookies/udemy.txt"
```

---

## 5. Operations & CLI Diagnostics

### 1. Dry Run (Preview Changes)
Simulate subscription runs without writing files or downloading media:
```bash
docker exec ytdl-sub ytdl-sub --dry-run sub /config/subscriptions.yaml
```

### 2. Inspecting Subscription Variables
Verify variable expansion, genre tags, and paths for a specific subscription:
```bash
docker exec ytdl-sub ytdl-sub inspect -l 0 --match "PLC Sequencer Logic" /config/subscriptions.yaml
```

### 3. Immediate Download Trigger
Trigger an immediate execution pass manually:
```bash
docker exec ytdl-sub /cron
# or
docker exec ytdl-sub ytdl-sub sub /config/subscriptions.yaml
```

### 4. Viewing Run Logs
Logs are kept persistently under `/media/cache/logs/ytdl-sub`:
```bash
tail -f /media/cache/logs/ytdl-sub/ytdl-sub.log
```
