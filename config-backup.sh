#!/bin/bash

# ==============================================================================
# Backup service configs from /opt to /media/josh/Media/<Service>/config
# ==============================================================================

# Array of services where "local_path:remote_path"
declare -A services=(
  [jellyfin]="/opt/jellyfin_config:/media/josh/Media/Jellyfin/config"
  [jellyseerr]="/opt/jellyseerr_config:/media/josh/Media/Jellyseerr/config"
  [sonarr]="/opt/sonarr_config:/media/josh/Media/Sonarr/config"
  [radarr]="/opt/radarr_config:/media/josh/Media/Radarr/config"
  [prowlarr]="/opt/prowlarr_config:/media/josh/Media/Prowlarr/config"
  [bazarr]="/opt/bazarr_config:/media/josh/Media/Bazarr/config"
  [lazylibrarian]="/opt/lazylibrarian_config:/media/josh/Media/Lazylibrarian/config"
  [qbittorrent]="/opt/qbittorrent_config:/media/josh/Media/qbittorrent/config"
  [tdarr-server]="/opt/tdarr/server:/media/josh/Media/Tdarr/server"
  [tdarr-configs]="/opt/tdarr/configs:/media/josh/Media/Tdarr/configs"
  [tdarr-logs]="/opt/tdarr/logs:/media/josh/Media/Tdarr/logs"
  [arm]="/media/josh/Media/ARM/config:/media/josh/Media/ARM/config"   # already mapped there, but mirror if needed
  [calibre]="/opt/calibre_config:/media/josh/Media/Calibre/config"
  [calibre-web]="/opt/calibre-web_config:/media/josh/Media/Calibre-Web/config"
)

# Run rsync for each service
for service in "${!services[@]}"; do
  IFS=":" read -r src dst <<< "${services[$service]}"
  echo "Backing up $service config..."
  rsync -av --delete "$src/" "$dst/"
done

# Optional: Log time
echo "Backup completed at $(date)" >> /var/log/opt-config-backup.log
