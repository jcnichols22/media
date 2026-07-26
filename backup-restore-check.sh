#!/usr/bin/env bash
set -euo pipefail

NTFY_BASE_URL="http://192.168.0.119"
NTFY_TOPIC="media-server-backup-verify"
NTFY_URL="${NTFY_BASE_URL}/${NTFY_TOPIC}"

BACKUP_BASE="/mnt/unraid_backups/media-server/configs"
LOG_FILE="/home/josh/media/backup-restore-check.log"
TMP_BASE="/tmp/restore-check-$$"

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
notify(){
  local title="$1" priority="$2" body="$3"
  curl -s -H "Title: ${title}" -H "Priority: ${priority}" -d "$body" "$NTFY_URL" >/dev/null || true
}
cleanup(){ rm -rf "$TMP_BASE" 2>/dev/null || true; }
trap cleanup EXIT

# Active services aligned with config-backup.sh
# Store optional key files to test restoreability
services=(
  "prowlarr:prowlarr:config.xml:*.db"
  "bazarr:bazarr:config.yaml:*.db"
  "sonarr:sonarr:config.xml:*.db"
  "radarr:radarr:config.xml:*.db"
  "seerr:seerr:settings.json"
  "qbittorrent:qbittorrent:qBittorrent.conf:qBittorrent/BT_backup/*.fastresume"
  "tdarr-server:tdarr/server:Tdarr_Node_Config.json:Tdarr/Backups/*.zip"
  "tdarr-configs:tdarr/configs:Tdarr_Server_Config.json"
  "tdarr-logs:tdarr/logs:Tdarr_Server_Log.txt:Tdarr_Node_Log.txt"
  "arm:arm:arm.yaml"
  "flaresolverr:flaresolverr"
  "profilarr:profilarr:profilarr.db"
)

WORKER_TIMEOUT_SEC=90
FAILED=()
WARNED=()
TS="$(date '+%F %T')"
log "Starting restore-check for all services at ${TS}"

if ! mountpoint -q /mnt/unraid_backups; then
  msg="Backup verify failed: /mnt/unraid_backups is not mounted."
  log "$msg"; notify "❌ Backup Restore Check Failed" "high" "$msg"; exit 2
fi
if [[ ! -d "$BACKUP_BASE" ]]; then
  msg="Backup verify failed: backup base dir missing (${BACKUP_BASE})."
  log "$msg"; notify "❌ Backup Restore Check Failed" "high" "$msg"; exit 3
fi

mkdir -p "$TMP_BASE"

for entry in "${services[@]}"; do
  IFS=":" read -r service subdir patterns_str <<< "$entry"
  SRC_DIR="${BACKUP_BASE}/${subdir}"
  TMP_DIR="${TMP_BASE}/${service}"

  if [[ ! -d "$SRC_DIR" ]]; then
    log "Restore-check failed for ${service}: backup source missing (${SRC_DIR}). Update config-backup.sh or remove this service."
    FAILED+=("${service}(source-missing)")
    continue
  fi

  mkdir -p "$TMP_DIR"

  include_args=(--include='*/')
  if [[ -n "${patterns_str:-}" ]]; then
    IFS=":" read -ra raw_patterns <<< "$patterns_str"
    for p in "${raw_patterns[@]}"; do
      [[ -n "$p" ]] && include_args+=(--include="$p")
    done
  fi

  set +e
  timeout --signal=TERM --kill-after=20s "${WORKER_TIMEOUT_SEC}s" \
    rsync -a --timeout=60 "${include_args[@]}" --exclude='*' "$SRC_DIR/" "$TMP_DIR/"
  rc=$?
  set -e

  if [[ $rc -ne 0 ]] && [[ -z "$(find "$TMP_DIR" -type f 2>/dev/null | head -1)" ]]; then
    reason="timeout"
    [[ $rc -eq 0 ]] && reason="no-matching-files"
    log "Restore-check failed for ${service}: ${reason}"
    FAILED+=("${service}(${reason})")
    rm -rf "$TMP_DIR" 2>/dev/null || true
    continue
  fi

  # Distinguish truly empty service (ok) from a service that should have files but doesn't
  file_count="$(find "$TMP_DIR" -type f 2>/dev/null | wc -l)"
  file_count="$(echo "$file_count" | tr -d '[:space:]')"
  if [[ "${file_count:-0}" -eq 0 ]]; then
    log "Restore-check passed for ${service}: empty service (no files to validate)."
    WARNED+=("${service}(empty)")
  else
    log "Restore-check passed for ${service} (${file_count} files validated)."
  fi

  rm -rf "$TMP_DIR" 2>/dev/null || true
done

TS_END="$(date '+%F %T')"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  notify "✅ Backup Restore Check Passed" "low" "Restore-check passed at ${TS_END} for all services. Warned: ${WARNED[*]:-none}."
  log "All services passed restore-check at ${TS_END}; warned: ${WARNED[*]:-none}"
else
  notify "❌ Backup Restore Check Failed" "high" "Restore-check failed at ${TS_END} for: ${FAILED[*]}."
  log "Restore-check failures at ${TS_END}: ${FAILED[*]}"
fi
exit 0
