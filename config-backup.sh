#!/usr/bin/env bash
set -euo pipefail

BACKUP_BASE="/mnt/unraid_backups/media-server/configs"
NTFY_URL="http://192.168.0.119/media-server-backup-cron"
LOG_FILE="/home/josh/media/config-backup.log"
FAILED=()
WARNED=()

# Timeout guardrails to avoid one stuck share hanging the whole run
RSYNC_TIMEOUT_SEC=900         # hard cap per service (15 min)
RSYNC_IO_TIMEOUT_SEC=120      # rsync stalls on I/O >120s fail fast

# Base rsync options (applies to all services)
# --no-owner/--no-group added because unraid_backups mount does not permit chown/chgrp
RSYNC_BASE_OPTS=(
  -av --delete --no-specials --no-devices --no-owner --no-group
  --exclude='*.sock' --exclude='*.pid' --exclude='ipc-socket'
  --timeout="$RSYNC_IO_TIMEOUT_SEC"
)

# Active services based on docker-compose.yml + existing /opt/appdata dirs

services=(
  "prowlarr:/opt/appdata/prowlarr:${BACKUP_BASE}/prowlarr"
  "bazarr:/opt/appdata/bazarr:${BACKUP_BASE}/bazarr"
  "sonarr:/opt/appdata/sonarr:${BACKUP_BASE}/sonarr"
  "radarr:/opt/appdata/radarr:${BACKUP_BASE}/radarr"
  "seerr:/opt/appdata/seerr:${BACKUP_BASE}/seerr"
  "qbittorrent:/opt/appdata/qbittorrent:${BACKUP_BASE}/qbittorrent"
  "tdarr-server:/opt/appdata/tdarr/server:${BACKUP_BASE}/tdarr/server"
  "tdarr-configs:/opt/appdata/tdarr/configs:${BACKUP_BASE}/tdarr/configs"
  "tdarr-logs:/opt/appdata/tdarr/logs:${BACKUP_BASE}/tdarr/logs"
  "arm:/opt/appdata/arm:${BACKUP_BASE}/arm"
  "jellyfin:/opt/appdata/jellyfin:${BACKUP_BASE}/jellyfin"
  "gluetun:/opt/appdata/gluetun:${BACKUP_BASE}/gluetun"
  "flaresolverr:/opt/appdata/flaresolverr:${BACKUP_BASE}/flaresolverr"
  "profilarr:/opt/appdata/profilarr:${BACKUP_BASE}/profilarr"
)

# Preflight: fail fast if backup target is unavailable or not writable
TIMESTAMP=$(date)
if [[ ! -d "$BACKUP_BASE" ]]; then
  msg="Backup preflight failed at ${TIMESTAMP}: destination path missing (${BACKUP_BASE})."
  echo "$msg"
  curl -s -H "Title: ❌ Media Server Backup Preflight Failed" -H "Priority: high" -d "$msg" "$NTFY_URL" >/dev/null || true
  echo "$msg" >> "$LOG_FILE"
  exit 2
fi

if ! timeout 20s bash -c "mkdir -p '$BACKUP_BASE' && test -w '$BACKUP_BASE'"; then
  msg="Backup preflight failed at ${TIMESTAMP}: destination not writable or mount unresponsive (${BACKUP_BASE})."
  echo "$msg"
  curl -s -H "Title: ❌ Media Server Backup Preflight Failed" -H "Priority: high" -d "$msg" "$NTFY_URL" >/dev/null || true
  echo "$msg" >> "$LOG_FILE"
  exit 3
fi

preflight_probe="$BACKUP_BASE/.backup-preflight-$$"
if ! timeout 20s bash -c "echo ok > '$preflight_probe' && rm -f '$preflight_probe'"; then
  msg="Backup preflight failed at ${TIMESTAMP}: destination probe write failed (${BACKUP_BASE})."
  echo "$msg"
  curl -s -H "Title: ❌ Media Server Backup Preflight Failed" -H "Priority: high" -d "$msg" "$NTFY_URL" >/dev/null || true
  echo "$msg" >> "$LOG_FILE"
  exit 4
fi

for entry in "${services[@]}"; do
  IFS=":" read -r service src dst excludes_str <<< "$entry"
  echo "Backing up $service..."
  if [[ ! -d "$src" ]]; then
    WARNED+=("${service}(source-missing)")
    echo "Skipping $service: source path missing ($src)"
    continue
  fi

  mkdir -p "$dst"

  # Build exclude args from colon-separated excludes
  exclude_args=()
  IFS=":" read -ra excludes <<< "$excludes_str"
  for ex in "${excludes[@]}"; do
    [[ -n "$ex" ]] && exclude_args+=(--exclude="$ex")
  done

  # Service-specific tweaks
  extra_opts=()
  [[ "$service" == "seerr" ]] && extra_opts+=(--copy-links)
  [[ "$service" == tdarr* ]] && extra_opts+=(--inplace)

  # Run rsync with hard wall-clock timeout so hung CIFS/NFS doesn't block all backups
  rsync_output=""
  rsync_rc=0
  rsync_output="$(timeout --signal=TERM --kill-after=20s "${RSYNC_TIMEOUT_SEC}s" \
    rsync "${RSYNC_BASE_OPTS[@]}" "${extra_opts[@]}" "${exclude_args[@]}" "$src/" "$dst/" 2>&1)" || rsync_rc=$?

  # Keep output visible in cron logs
  [[ -n "$rsync_output" ]] && echo "$rsync_output"

  # Outcome classification
  if [[ $rsync_rc -eq 0 ]]; then
    continue
  elif [[ $rsync_rc -eq 124 || $rsync_rc -eq 137 ]]; then
    # timeout(1): 124 on timeout, 137 if kill-after hit
    WARNED+=("${service}(timeout)")
  elif [[ $rsync_rc -eq 24 ]]; then
    # vanished source files (transient)
    WARNED+=("${service}(vanished)")
  else
    FAILED+=("$service")
  fi
done

TIMESTAMP=$(date)

if [ ${#FAILED[@]} -eq 0 ]; then
  if [ ${#WARNED[@]} -eq 0 ]; then
    curl -s \
      -H "Title: ✅ Media Server Backup Complete" \
      -H "Priority: low" \
      -d "All configs backed up successfully at ${TIMESTAMP}." \
      "$NTFY_URL"
  else
    curl -s \
      -H "Title: ⚠️ Media Server Backup Complete (with warnings)" \
      -H "Priority: default" \
      -d "Backup completed at ${TIMESTAMP}. Warnings: ${WARNED[*]}." \
      "$NTFY_URL"
  fi
else
  curl -s \
    -H "Title: ❌ Media Server Backup Failed" \
    -H "Priority: high" \
    -d "Backup completed at ${TIMESTAMP} with failures: ${FAILED[*]} (warnings: ${WARNED[*]})." \
    "$NTFY_URL"
fi

echo "Backup completed at ${TIMESTAMP}; failed=${FAILED[*]:-none}; warned=${WARNED[*]:-none}" >> "$LOG_FILE"
