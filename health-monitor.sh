#!/usr/bin/env bash
set -euo pipefail

cd /home/josh/media

NTFY_BASE_URL="http://192.168.0.119"
NTFY_TOPIC="media-server-health"
NTFY_URL="${NTFY_BASE_URL}/${NTFY_TOPIC}"

STATE_DIR="/home/josh/media/state"
STATE_FILE="${STATE_DIR}/health-monitor.state"
LOG_FILE="/home/josh/media/health-monitor.log"
TMP_PS="/tmp/compose-ps.$$.jsonl"

DISK_WARN_THRESHOLD=85

mkdir -p "$STATE_DIR"

issues=()
warns=()

# Container status/health from compose scope
if docker compose ps --format json > "$TMP_PS" 2>/dev/null; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    service=$(echo "$line" | sed -n 's/.*"Service":"\([^"]*\)".*/\1/p')
    state=$(echo "$line" | sed -n 's/.*"State":"\([^"]*\)".*/\1/p')
    health=$(echo "$line" | sed -n 's/.*"Health":"\([^"]*\)".*/\1/p')

    [[ -z "$service" ]] && service="unknown"
    [[ -z "$state" ]] && state="unknown"

    if [[ "$state" != "running" ]]; then
      issues+=("${service}:state=${state}")
    fi
    if [[ "$health" == "unhealthy" ]]; then
      issues+=("${service}:health=unhealthy")
    fi
  done < "$TMP_PS"
else
  warns+=("compose-status-unavailable")
fi
rm -f "$TMP_PS"

# Explicit gluetun health check (high signal for qBittorrent path)
if docker ps --format '{{.Names}}' | grep -qx gluetun; then
  gl_health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' gluetun 2>/dev/null || echo unknown)"
  if [[ "$gl_health" != "healthy" ]]; then
    issues+=("gluetun:health=${gl_health}")
  fi
else
  issues+=("gluetun:missing")
fi

# Disk usage checks
root_use="$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')"
if [[ -n "$root_use" && "$root_use" -ge "$DISK_WARN_THRESHOLD" ]]; then
  warns+=("disk-root=${root_use}%")
fi

if mountpoint -q /mnt/unraid_backups; then
  backup_use="$(df -P /mnt/unraid_backups | awk 'NR==2{gsub("%","",$5); print $5}')"
  if [[ -n "$backup_use" && "$backup_use" -ge "$DISK_WARN_THRESHOLD" ]]; then
    warns+=("disk-backup=${backup_use}%")
  fi
else
  warns+=("backup-mount-not-mounted")
fi

# Recent backup script failures/preflight issues
if [[ -f /home/josh/media/config-backup.log ]]; then
  last_line="$(tail -n 1 /home/josh/media/config-backup.log || true)"
  if echo "$last_line" | grep -Eqi 'preflight failed|failed=[^n]'; then
    warns+=("backup-log-indicates-failure")
  fi
fi

status="ok"
if (( ${#issues[@]} > 0 )); then
  status="critical"
elif (( ${#warns[@]} > 0 )); then
  status="warning"
fi

payload="status=${status};issues=${issues[*]:-none};warns=${warns[*]:-none}"
hash="$(printf '%s' "$payload" | sha256sum | awk '{print $1}')"

prev_status="unknown"
prev_hash=""
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" || true
  prev_status="${PREV_STATUS:-unknown}"
  prev_hash="${PREV_HASH:-}"
fi

send=0
if [[ "$status" == "ok" ]]; then
  if [[ "$prev_status" != "ok" ]]; then
    send=1
    title="✅ Media Health Recovered"
    priority="default"
    body="All monitored checks recovered at $(date)."
  fi
else
  if [[ "$hash" != "$prev_hash" ]]; then
    send=1
    if [[ "$status" == "critical" ]]; then
      title="❌ Media Health Critical"
      priority="high"
    else
      title="⚠️ Media Health Warning"
      priority="default"
    fi
    body="Status: ${status}\nIssues: ${issues[*]:-none}\nWarnings: ${warns[*]:-none}\nTime: $(date)"
  fi
fi

if [[ $send -eq 1 ]]; then
  curl -s \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -d "$body" \
    "$NTFY_URL" >/dev/null || true
fi

echo "$(date) status=${status} issues=${issues[*]:-none} warns=${warns[*]:-none} sent=${send}" >> "$LOG_FILE"

cat > "$STATE_FILE" <<STATE
PREV_STATUS='${status}'
PREV_HASH='${hash}'
STATE
