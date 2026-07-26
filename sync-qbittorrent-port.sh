#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/home/josh/media/state"
STATE_FILE="${STATE_DIR}/qbittorrent-port-sync.state"
CONFIG_FILE="/opt/appdata/qbittorrent/qBittorrent/qBittorrent.conf"

mkdir -p "$STATE_DIR"

if ! docker ps --format '{{.Names}}' | grep -qx gluetun; then
  exit 0
fi

if ! docker ps --format '{{.Names}}' | grep -qx qbittorrent; then
  exit 0
fi

forwarded_port="$(docker exec gluetun sh -lc 'cat /tmp/gluetun/forwarded_port 2>/dev/null || echo 0' | tr -d '\r')"

if [[ ! "$forwarded_port" =~ ^[0-9]+$ ]] || [[ "$forwarded_port" -eq 0 ]]; then
  exit 0
fi

current_session_port="$(sed -n 's/^Session\\Port=//p' "$CONFIG_FILE" | head -n 1)"
current_connection_port="$(sed -n 's/^Connection\\PortRangeMin=//p' "$CONFIG_FILE" | head -n 1)"

if [[ "$current_session_port" == "$forwarded_port" && "$current_connection_port" == "$forwarded_port" ]]; then
  printf 'last_synced_port=%s\n' "$forwarded_port" > "$STATE_FILE"
  exit 0
fi

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

awk -v port="$forwarded_port" '
  /^Session\\Port=|^SessionPort=/ {
    print "Session\\Port=" port
    next
  }
  /^Connection\\PortRangeMin=|^ConnectionPortRangeMin=/ {
    print "Connection\\PortRangeMin=" port
    next
  }
  { print }
' "$CONFIG_FILE" > "$tmp_file"

install -m 0644 "$tmp_file" "$CONFIG_FILE"
docker restart qbittorrent >/dev/null

printf 'last_synced_port=%s\n' "$forwarded_port" > "$STATE_FILE"
printf '%s synced qbittorrent listening port to %s\n' "$(date)" "$forwarded_port"