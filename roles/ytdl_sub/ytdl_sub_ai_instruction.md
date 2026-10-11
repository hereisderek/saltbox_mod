# AI Instruction Note for YTDL-Sub

**App Name**: `ytdl_sub` | **Container**: `ytdl-sub` | **Author**: `hereisderek`  
**Upstream**: https://github.com/jmbannon/ytdl-sub | **Docs**: [docs/ytdl_sub.md](../../docs/ytdl_sub.md)

## Key Architecture & Conventions
1. **Container & Cron**: Runs `ghcr.io/jmbannon/ytdl-sub:ubuntu-latest` driven by internal cron (`0 */6 * * *`). AppData at `/opt/ytdl-sub` (`/config`), media root at `/mnt/unionfs/Media/Youtube/ytdl-sub` (`/ytdl_sub`).
2. **Category Layout**:
   - `channels/`: YouTube channels via `Jellyfin TV Show by Date`.
   - `courses/`: Online learning series via `Jellyfin TV Show Collection | season_by_collection__episode_by_playlist_index`. Subdirectories: `linkedin-learning/`, `coursera/`, `deeplearning/`, `udemy/`.
   - `mv/`: Music videos via `Jellyfin Music Videos`.
3. **Storage Tiering & The Zero-Remount Policy**:
   - Local SSD cache on PVE ZFS (`/mnt/storage/media/Media/Youtube/ytdl-sub/`).
   - Remote HDD warehouse on SFTP (`china-sftp:/vol8/1002/Storage/Media/Youtube/ytdl-sub/`).
   - **NEVER** trigger unmount/remount on host FUSE mounts.
   - Any directory restructuring or file moving across categories must be synchronized on both local PVE and remote SFTP via `rclone moveto` to avoid cache invalidation or re-syncing.
4. **Cookie Authentication**:
   - Stored at `/opt/ytdl-sub/cookies/<site>.txt` (mapped to `/config/cookies/<site>.txt`).
   - Required for platforms like LinkedIn Learning, Coursera, Udemy.
5. **Subscription Syntax Gotchas**:
   - When specifying plugins (such as `ytdl_options.cookiefile`) inside a subscription, **DO NOT** use the `~` prefix on the subscription title. Place variables inside `overrides:` and plugin configurations at the root of the subscription dictionary.
   - LinkedIn Learning collections (`/collections/<id>`) are not supported natively by `yt-dlp` and must be expanded into individual course slugs.
6. **Validation & Verification**:
   - Validate subscriptions before leaving changes:  
     `docker exec ytdl-sub ytdl-sub inspect -l 0 --match "<Name>" /config/subscriptions.yaml`
   - Test dry-run:  
     `docker exec ytdl-sub ytdl-sub --dry-run sub /config/subscriptions.yaml`
