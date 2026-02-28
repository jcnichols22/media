#!/bin/bash

# ==============================================================================
# Backup service configs from /opt/appdata to /mnt/unraid_backups/media-server/configs/<Service>
# ==============================================================================

BACKUP_BASE="/mnt/unraid_backups/media-server/configs"
NTFY_URL="http://192.168.0.119/media-server-backup-cron"
FAILED=()

# Base rsync options (applies to all services)
RSYNC_BASE_OPTS="-av --delete --no-specials --no-devices --exclude=*.sock --exclude=*.pid --exclude=ipc-socket"

# Each entry: "src:dst[:exclude1:exclude2:...]"
services=(
  "prowlarr:/opt/appdata/prowlarr:${BACKUP_BASE}/prowlarr"
  "bazarr:/opt/appdata/bazarr:${BACKUP_BASE}/bazarr"
  "sonarr:/opt/appdata/sonarr:${BACKUP_BASE}/sonarr"
  "radarr:/opt/appdata/radarr:${BACKUP_BASE}/radarr"
  "jellyfin:/opt/appdata/jellyfin:${BACKUP_BASE}/jellyfin:cache:transcodes"
  "plex:/opt/appdata/plex:${BACKUP_BASE}/plex:Library/Application Support/Plex Media Server/Cache:Library/Application Support/Plex Media Server/Codecs:Library/Application Support/Plex Media Server/Crash Reports"
  "seerr:/opt/appdata/seerr:${BACKUP_BASE}/seerr"
  "qbittorrent:/opt/appdata/qbittorrent:${BACKUP_BASE}/qbittorrent"
  "tdarr-server:/opt/appdata/tdarr/server:${BACKUP_BASE}/tdarr/server"
  "tdarr-configs:/opt/appdata/tdarr/configs:${BACKUP_BASE}/tdarr/configs"
  "tdarr-logs:/opt/appdata/tdarr/logs:${BACKUP_BASE}/tdarr/logs"
  "arm:/opt/appdata/arm:${BACKUP_BASE}/arm"
)

for entry in "${services[@]}"; do
  IFS=":" read -r service src dst excludes_str <<< "$entry"
  echo "Backing up $service..."
  mkdir -p "$dst"

  # Build exclude args from colon-separated excludes
  exclude_args=()
  IFS=":" read -ra excludes <<< "$excludes_str"
  for ex in "${excludes[@]}"; do
    [[ -n "$ex" ]] && exclude_args+=(--exclude="$ex")
  done

  # seerr: CIFS doesn't support symlinks, copy them as files instead
  # tdarr: filenames with () break rsync temp files on CIFS, use --inplace
  extra_opts=()
  [[ "$service" == "seerr" ]] && extra_opts+=(--copy-links)
  [[ "$service" == tdarr* ]] && extra_opts+=(--inplace)

  if ! rsync $RSYNC_BASE_OPTS "${extra_opts[@]}" "${exclude_args[@]}" "$src/" "$dst/"; then
    FAILED+=("$service")
  fi
done

TIMESTAMP=$(date)

if [ ${#FAILED[@]} -eq 0 ]; then
  curl -s \
    -H "Title: ✅ Media Server Backup Complete" \
    -H "Priority: low" \
    -d "All configs backed up successfully at ${TIMESTAMP}." \
    "$NTFY_URL"
else
  curl -s \
    -H "Title: ❌ Media Server Backup Failed" \
    -H "Priority: high" \
    -d "Backup completed at ${TIMESTAMP} with failures: ${FAILED[*]}" \
    "$NTFY_URL"
fi

echo "Backup completed at ${TIMESTAMP}" >> /var/log/opt-config-backup.log
