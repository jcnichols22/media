#!/usr/bin/env bash
set -euo pipefail

# Monthly backup restore confidence check (non-destructive)
# - restores a small subset of backup files to /tmp
# - validates expected files exist
# - alerts via ntfy only if something is wrong (success is low-priority optional)

NTFY_BASE_URL="http://192.168.0.119"
NTFY_TOPIC="media-server-backup-verify"
NTFY_URL="${NTFY_BASE_URL}/${NTFY_TOPIC}"

BACKUP_BASE="/mnt/unraid_backups/media-server/configs"
SERVICE="sonarr"  # pick a representative service config
SRC_DIR="${BACKUP_BASE}/${SERVICE}"
LOG_FILE="/home/josh/media/backup-restore-check.log"

TS="$(date '+%F %T')"
TMP_DIR="/tmp/restore-check-${SERVICE}-$$"

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
notify(){
  local title="$1" priority="$2" body="$3"
  curl -s -H "Title: ${title}" -H "Priority: ${priority}" -d "$body" "$NTFY_URL" >/dev/null || true
}

cleanup(){ rm -rf "$TMP_DIR" 2>/dev/null || true; }
trap cleanup EXIT

log "Starting restore-check for ${SERVICE}"

# Preflight checks
if ! mountpoint -q /mnt/unraid_backups; then
  msg="Backup verify failed at ${TS}: /mnt/unraid_backups is not mounted."
  log "$msg"
  notify "❌ Backup Restore Check Failed" "high" "$msg"
  exit 2
fi

if [[ ! -d "$SRC_DIR" ]]; then
  msg="Backup verify failed at ${TS}: source dir missing (${SRC_DIR})."
  log "$msg"
  notify "❌ Backup Restore Check Failed" "high" "$msg"
  exit 3
fi

mkdir -p "$TMP_DIR"

# Restore a small, meaningful subset (fast + representative)
# Sonarr: config.xml and sqlite db family if present
set +e
rsync -a --timeout=60 \
  --include='config.xml' \
  --include='*.db' \
  --include='*.db-shm' \
  --include='*.db-wal' \
  --exclude='*' \
  "$SRC_DIR/" "$TMP_DIR/" >/tmp/restore-check-rsync.out 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  msg="Backup verify failed at ${TS}: rsync subset restore failed (rc=${rc}) for ${SERVICE}."
  log "$msg"
  log "rsync output: $(tail -n 5 /tmp/restore-check-rsync.out | tr '\n' ' ')"
  notify "❌ Backup Restore Check Failed" "high" "$msg"
  exit 4
fi

# Validate restored content
missing=()
[[ -f "$TMP_DIR/config.xml" ]] || missing+=("config.xml")
# at least one DB artifact should exist
if ! ls "$TMP_DIR"/*.db "$TMP_DIR"/*.db-shm "$TMP_DIR"/*.db-wal >/dev/null 2>&1; then
  missing+=("db-artifact")
fi

if (( ${#missing[@]} > 0 )); then
  msg="Backup verify failed at ${TS}: missing restored files (${missing[*]}) for ${SERVICE}."
  log "$msg"
  notify "❌ Backup Restore Check Failed" "high" "$msg"
  exit 5
fi

log "Restore-check success for ${SERVICE}; subset restored to ${TMP_DIR} and validated"
notify "✅ Backup Restore Check Passed" "low" "Restore-check passed at ${TS} for ${SERVICE}."
exit 0
