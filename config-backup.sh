#!/bin/bash

# ==============================================================================
# Backup service configs from /opt/appdata to /mnt/unraid_backsups/<Service>/config
# ==============================================================================

# Array of services where "local_path:remote_path"
declare -A services=(
  [prowlarr]="/opt/appdata/prowlarr:/mnt/unraid_backsups/Prowlarr/config"
  [bazarr]="/opt/appdata/bazarr:/mnt/unraid_backsups/Bazarr/config"
  [sonarr]="/opt/appdata/sonarr:/mnt/unraid_backsups/Sonarr/config"
  [radarr]="/opt/appdata/radarr:/mnt/unraid_backsups/Radarr/config"
  [jellyfin]="/opt/appdata/jellyfin:/mnt/unraid_backsups/Jellyfin/config"
  [plex]="/opt/appdata/plex:/mnt/unraid_backsups/Plex/config"
  [seerr]="/opt/appdata/seerr:/mnt/unraid_backsups/Seerr/config"
  [qbittorrent]="/opt/appdata/qbittorrent:/mnt/unraid_backsups/qbittorrent/config"
  [tdarr-server]="/opt/appdata/tdarr/server:/mnt/unraid_backsups/Tdarr/server"
  [tdarr-configs]="/opt/appdata/tdarr/configs:/mnt/unraid_backsups/Tdarr/configs"
  [tdarr-logs]="/opt/appdata/tdarr/logs:/mnt/unraid_backsups/Tdarr/logs"
  [arm]="/opt/appdata/arm:/mnt/unraid_backsups/ARM/config"
)

# Run rsync for each service
for service in "${!services[@]}"; do
  IFS=":" read -r src dst <<< "${services[$service]}"
  echo "Backing up $service config..."
  rsync -av --delete "$src/" "$dst/"
done

# Optional: Log time
echo "Backup completed at $(date)" >> /var/log/opt-config-backup.log
