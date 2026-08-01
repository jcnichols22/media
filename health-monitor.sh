#!/usr/bin/env bash
set -euo pipefail

cd /home/josh/media

NTFY_BASE_URL="http://192.168.0.119"
NTFY_TOPIC="media-server-health"
NTFY_URL="${NTFY_BASE_URL}/${NTFY_TOPIC}"

STATE_DIR="/home/josh/media/state"
STATE_FILE="${STATE_DIR}/health-monitor.state"
LOG_FILE="/home/josh/media/health-monitor.log"

DISK_WARN_THRESHOLD=85

mkdir -p "$STATE_DIR"

issues=()
warns=()

# Port sync — non-fatal, only warns on failure
fi

# Container status/health from compose scope (pipe-delimited, no JSON parsing)
while IFS=$'\t' read -r svc state status health; do
  [[ -z "$svc" || "$svc" == "SERVICE" ]] && continue
  if [[ "$state" != "running" ]]; then
    issues+=("${svc}:state=${state}")
  fi
  if [[ "$health" == "unhealthy" ]]; then
    issues+=("${svc}:health=unhealthy")
  fi
done < <(docker compose ps --format "{{.Service}}\t{{.State}}\t{{.Status}}\t{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" 2>/dev/null)

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
  if echo "$last_line" | grep -Eqi 'preflight failed|failed=[1-9]'; then
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
    body="Status: ${status}
Issues: ${issues[*]:-none}
Warnings: ${warns[*]:-none}
Time: $(date)"
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
