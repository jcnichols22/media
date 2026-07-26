# Media Server Recovery Runbook

## Scope
This runbook is for recovering the Docker media stack on `ThePensive` using `/home/josh/media/docker-compose.yml`.

Topology assumption:
- This host runs core automation services.
- `jellyfin` and `plex` run in separate Proxmox LXCs.

## Critical Paths
- Compose repo: `/home/josh/media`
- Service configs: `/opt/appdata/<service>`
- Backup source of configs: `/mnt/unraid_backups/media-server/configs`
- Backup scripts/logs:
  - `/home/josh/media/config-backup.sh`
  - `/home/josh/media/config-backup.log`
  - `/home/josh/media/backup-restore-check.sh`
  - `/home/josh/media/backup-restore-check.log`

## Fast Triage
```bash
cd /home/josh/media
./status-check.sh
```

## Recovery Order (recommended)
1. **Host basics**: disk, mount, docker daemon healthy
2. **VPN path**: `gluetun` healthy
3. **Downloader path**: `qbittorrent` (depends on gluetun)
4. **Core apps**: sonarr/radarr/prowlarr/bazarr/seerr
5. **Media servers (separate LXCs)**: restore and start jellyfin, plex in their own containers
6. **Aux services**: tdarr, arm-rippers, jellyplex-watched, profilarr, flaresolverr

## Common Incident Playbooks

### A) Backup share/mount issue
```bash
sudo /usr/local/sbin/media-backup-mount-recover
```
Then rerun backup:
```bash
sudo /usr/local/sbin/media-backup-run
```

### B) Stuck backup run
```bash
sudo /usr/local/sbin/media-backup-stop
```

### C) Service unhealthy after upgrade
1. Restore previous `docker-compose.yml` (from repo history or latest known-good backup)
2. Recreate only impacted service(s):
```bash
docker compose up -d <service>
```
3. Verify:
```bash
docker compose ps <service>
docker logs --tail 100 <service>
```

### D) Full stack restart
```bash
cd /home/josh/media
docker compose up -d --remove-orphans
docker compose ps
```

### E) Restore Jellyfin/Plex from backup (preserve users/history/plugins)

Run these on each media-server LXC, not on this automation host.

1. Stop the media server container/service.
2. Snapshot existing config path as a safety backup.
3. Restore config from backup source.
4. Fix ownership/permissions.
5. Start service and validate users/history/plugins.

Jellyfin example:
```bash
systemctl stop jellyfin || true
docker stop jellyfin || true

ts=$(date +%Y%m%d-%H%M%S)
cp -a /opt/appdata/jellyfin /opt/appdata/jellyfin.pre-restore-$ts
rsync -a --delete /mnt/unraid_backups/media-server/configs/jellyfin/ /opt/appdata/jellyfin/
chown -R 1000:1000 /opt/appdata/jellyfin

systemctl start jellyfin || true
docker start jellyfin || true
```

Plex example:
```bash
docker stop plex || true

ts=$(date +%Y%m%d-%H%M%S)
cp -a /opt/appdata/plex /opt/appdata/plex.pre-restore-$ts
rsync -a --delete \
  --exclude='Library/Application Support/Plex Media Server/Cache' \
  --exclude='Library/Application Support/Plex Media Server/Codecs' \
  --exclude='Library/Application Support/Plex Media Server/Crash Reports' \
  /mnt/unraid_backups/media-server/configs/plex/ /opt/appdata/plex/
chown -R 1000:1000 /opt/appdata/plex

docker start plex || true
```

Post-restore verification:
```bash
docker logs --tail 100 jellyfin
docker logs --tail 100 plex
```

## Validation Checklist After Recovery
- `docker compose ps` shows all required services running
- `gluetun` healthy and `qbittorrent` up
- Plex/Jellyfin reachable from their dedicated LXCs
- Latest backup/health monitor logs are clean
- ntfy topics receiving expected notifications:
  - `media-server-health`
  - `media-server-backup-cron`
  - `media-server-backup-verify`
  - `media-server-upgrades`

## Notes
- Keep `gluetun + qbittorrent` upgrades manual (not unattended).
- Keep README and this runbook updated after any operational change.
