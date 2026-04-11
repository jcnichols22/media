#!/usr/bin/env bash
set -euo pipefail

cd /home/josh/media

echo "=== Media Stack Status Check ==="
echo "Host: $(hostname)"
echo "Time: $(date)"
echo

echo "-- Docker Compose Services --"
docker compose ps --format "table {{.Service}}\t{{.State}}\t{{.Status}}"
echo

echo "-- Key Health (gluetun, plex, seerr, arm-rippers) --"
for c in gluetun plex seerr arm-rippers; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
    st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo unknown)
    hl=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo unknown)
    echo "$c: state=$st health=$hl"
  else
    echo "$c: missing"
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
echo "-- Last Health Monitor Result --"
if [[ -f /home/josh/media/health-monitor.log ]]; then
  tail -n 1 /home/josh/media/health-monitor.log
else
  echo "No health-monitor.log found"
fi

echo
echo "-- Last Auto-Upgrade Result --"
if [[ -f /home/josh/media/auto-upgrade.log ]]; then
  tail -n 1 /home/josh/media/auto-upgrade.log
else
  echo "No auto-upgrade.log found"
fi

echo
echo "Status check complete."
