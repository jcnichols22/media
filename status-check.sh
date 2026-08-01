#!/usr/bin/env bash
set -euo pipefail

cd /home/josh/media

echo "=== Media Stack Status Check ==="
echo "Host: $(hostname)"
echo "Time: $(date)"
echo

echo "-- Docker Compose Services --"
docker compose ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}" 2>/dev/null || docker compose ps 2>/dev/null
echo

echo "-- Container Health Detail --"
for c in $(docker compose ps --format "{{.Service}}" 2>/dev/null); do
  name=$(docker ps --filter "label=com.docker.compose.service=${c}" --format "{{.Names}}" | head -n 1)
  if [[ -n "$name" ]]; then
    state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo unknown)
    health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || echo unknown)
    printf "%-20s state=%-10s health=%s\n" "$c" "$state" "$health"
  fi
done
echo

echo "-- Disk Usage --"
df -h / | awk 'NR==1 || NR==2'
if mountpoint -q /mnt/unraid_backups; then
  df -h /mnt/unraid_backups | awk 'NR==1 || NR==2'
else
  echo "/mnt/unraid_backups: not mounted"
fi
echo

echo "-- Last Backup Result --"
if [[ -f /home/josh/media/config-backup.log ]]; then
  tail -n 1 /home/josh/media/config-backup.log
else
  echo "No config-backup.log found"
fi
echo

echo "-- Last Auto-Upgrade Result --"
if [[ -f /home/josh/media/auto-upgrade.log ]]; then
  tail -n 1 /home/josh/media/auto-upgrade.log
else
  echo "No auto-upgrade.log found"
fi
echo

echo "-- Last Health Monitor Result --"
if [[ -f /home/josh/media/health-monitor.log ]]; then
  tail -n 1 /home/josh/media/health-monitor.log
else
  echo "No health-monitor.log found"
fi
echo

echo "Status check complete."
