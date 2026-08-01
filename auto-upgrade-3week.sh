#!/usr/bin/env bash
set -euo pipefail

cd /home/josh/media

# ===== Config =====
ANCHOR_DATE="2026-04-11"   # Saturday anchor; every 3 weeks from this date
NTFY_BASE_URL="http://192.168.0.119"
NTFY_TOPIC="media-server-upgrades"
NTFY_URL="${NTFY_BASE_URL}/${NTFY_TOPIC}"
LOG_FILE="/home/josh/media/auto-upgrade.log"
LOCK_FILE="/tmp/media-auto-upgrade.lock"

# Exclude gluetun+qbittorrent from unattended upgrades (higher blast radius)
services=(
  arm-rippers
  bazarr
  flaresolverr
  gluetun
  jellyfin
  jellyplex-watched
  plex
  profilarr
  prowlarr
  qbittorrent
  radarr
  seerr
  sonarr
  tdarr
)

declare -A repo_by_service=(
  [flaresolverr]="ghcr.io/flaresolverr/flaresolverr"
  [profilarr]="santiagosayshey/profilarr"
  [bazarr]="linuxserver/bazarr"
  [sonarr]="linuxserver/sonarr"
  [radarr]="linuxserver/radarr"
  [prowlarr]="linuxserver/prowlarr"
  [seerr]="ghcr.io/seerr-team/seerr"
  [jellyfin]="linuxserver/jellyfin"
  [plex]="plexinc/pms-docker"
  [tdarr]="ghcr.io/haveagitgat/tdarr_acc"
  [qbittorrent]="lscr.io/linuxserver/qbittorrent"
  [arm-rippers]="1337server/automatic-ripping-machine"
  [jellyplex-watched]="ghcr.io/luigi311/jellyplex-watched"
  [gluetun]="qmcgaw/gluetun"
)

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

send_ntfy() {
  local title="$1" priority="$2" body="$3"
  curl -s \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -d "$body" \
    "$NTFY_URL" >/dev/null || true
}

if [[ -e "$LOCK_FILE" ]]; then
  log "Another run appears active (lock: $LOCK_FILE). Exiting."
  exit 0
fi
trap 'rm -f "$LOCK_FILE"' EXIT
: > "$LOCK_FILE"

# ===== 3-week gate =====
if [[ "${FORCE_RUN:-0}" != "1" ]]; then
  now_epoch=$(date +%s)
  anchor_epoch=$(date -d "$ANCHOR_DATE 00:00:00" +%s)
  if (( now_epoch < anchor_epoch )); then
    log "Now is before anchor date; skipping."
    exit 0
  fi
  weeks=$(( (now_epoch - anchor_epoch) / 604800 ))
  if (( weeks % 3 != 0 )); then
    log "Not a 3-week slot (weeks since anchor=$weeks); skipping."
    exit 0
  fi
fi

log "Starting scheduled upgrade cycle"
if ! docker compose config -q; then
  log "Compose invalid before run; aborting"
  send_ntfy "❌ Media Auto-Upgrade Aborted" "high" "Compose validation failed before upgrade at $(date)."
  exit 1
fi

upgraded=()
failed=()
skipped=()

for svc in "${services[@]}"; do
  repo="${repo_by_service[$svc]:-}"
  if [[ -z "$repo" ]]; then
    failed+=("$svc(no-repo-map)")
    continue
  fi

  # Current digest from compose (handles both @sha256 and :latest)
  current_line=$(grep -E "^[[:space:]]*image:[[:space:]]*${repo}(@sha256:[0-9a-f]{64})?" docker-compose.yml | head -n1 || true)
  if [[ -z "$current_line" ]]; then
    skipped+=("$svc(not-in-compose)")
    continue
  fi
  if echo "$current_line" | grep -q '@sha256:'; then
    current_digest=$(echo "$current_line" | sed -E 's#.*@sha256:([0-9a-f]{64}).*#\1#')
  else
    current_digest=$(docker manifest inspect "${repo}:latest" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for m in d.get('manifests',[]):
    p=m.get('platform',{})
    if p.get('architecture')=='amd64' and p.get('os')=='linux':
        print(m['digest'].replace('sha256:',''))
        sys.exit(0)
if d.get('manifests'): print(d['manifests'][0]['digest'].replace('sha256:',''))
" 2>/dev/null || true)
    if [[ -z "$current_digest" ]]; then
      skipped+=("$svc(digest-lookup)")
      continue
    fi
  fi

  # Latest digest
  latest_digest=$(docker manifest inspect "${repo}:latest" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for m in d.get('manifests',[]):
    p=m.get('platform',{})
    if p.get('architecture')=='amd64' and p.get('os')=='linux':
        print(m['digest'].replace('sha256:',''))
        sys.exit(0)
if d.get('manifests'): print(d['manifests'][0]['digest'].replace('sha256:',''))
" 2>/dev/null || true)
  if [[ -z "$latest_digest" ]]; then
    failed+=("$svc(digest-lookup)")
    continue
  fi

  if [[ "$latest_digest" == "$current_digest" ]]; then
    skipped+=("$svc(up-to-date)")
    continue
  fi

  log "Upgrading $svc: ${current_digest:0:12} -> ${latest_digest:0:12}"

  backup="docker-compose.yml.bak.auto-${svc}-$(date +%Y%m%d-%H%M%S)"
  cp docker-compose.yml "$backup"

  # Replace digest for this repo only
  python3 /tmp/upgrade_replace_digest.py "${repo}" "${latest_digest}" docker-compose.yml

  if ! docker compose config -q; then
    log "Compose invalid after editing $svc; rolling back"
    cp "$backup" docker-compose.yml
    failed+=("$svc(compose-invalid)")
    continue
  fi

  if ! docker compose pull "$svc"; then
    log "Pull failed for $svc; rolling back"
    cp "$backup" docker-compose.yml
    failed+=("$svc(pull-failed)")
    continue
  fi

  if ! docker compose up -d "$svc"; then
    log "Recreate failed for $svc; rolling back"
    cp "$backup" docker-compose.yml
    docker compose up -d "$svc" || true
    failed+=("$svc(recreate-failed)")
    continue
  fi

  # Basic post-check with retries for slow-starting services (e.g. gluetun)
  max_wait=90
  waited=0
  state=unknown
  health=unknown
  while (( waited < max_wait )); do
    state=$(docker inspect -f '{{.State.Status}}' "$svc" 2>/dev/null || echo unknown)
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$svc" 2>/dev/null || echo unknown)
    if [[ "$state" == "running" && "$health" != "unhealthy" ]]; then
      break
    fi
    sleep 15
    waited=$((waited + 15))
  done

  if [[ "$state" != "running" || "$health" == "unhealthy" ]]; then
    log "Post-check failed for $svc (state=$state health=$health) after ${waited}s; rolling back"
    cp "$backup" docker-compose.yml
    docker compose up -d "$svc" || true
    failed+=("$svc(postcheck-${state}-${health})")
    continue
  fi

  upgraded+=("$svc")
  log "Upgrade ok for $svc"
done

summary="upgraded=${upgraded[*]:-none}; failed=${failed[*]:-none}; skipped=${skipped[*]:-none}"
log "Cycle complete: $summary"

if (( ${#failed[@]} > 0 )); then
  send_ntfy "⚠️ Media Auto-Upgrade Completed With Failures" "default" "${summary}\nTime: $(date)"
else
  send_ntfy "✅ Media Auto-Upgrade Completed" "low" "${summary}\nTime: $(date)"
fi
