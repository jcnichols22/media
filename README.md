# Media Stack Docker Compose Setup

This repository runs a home media stack with Docker Compose, including VPN-routed downloading, media automation, streaming, request management, transcoding, and disc ripping.

## Current Services

| Service | Purpose | Port(s) |
|---|---|---|
| gluetun | ProtonVPN WireGuard tunnel for qBittorrent | 8080, 6881/tcp, 6881/udp |
| qbittorrent | Torrent client (routed through gluetun) | 8080 (via gluetun) |
| prowlarr | Indexer manager | 9696 |
| sonarr | TV automation | 8989 |
| radarr | Movie automation | 7878 |
| bazarr | Subtitle automation | 6767 |
| jellyfin | Media server | 8096, 7359/udp, 1900/udp |
| plex | Media server | host network |
| seerr | Request management | 5055 |
| jellyplex-watched | Plex/Jellyfin watched-state sync | (no published ports) |
| tdarr | Transcoding + health checks (Intel QuickSync) | 8265, 8266 |
| arm-rippers | Automated Ripping Machine | 8090 |

## Tdarr Configuration

- Tdarr runs as a single container with the built-in node enabled.
- `internalNode=true` is enabled in `docker-compose.yml`.
- No separate `tdarr-node` service is used.
- Intel QuickSync is passed through via `/dev/dri`.

## Paths and Storage

- Media root (`ARRPATH`) is set in `.env` to `/mnt/unraid_media/`.
- App configs are stored on native storage under `/opt/appdata/<service>`.
- Tdarr uses:
    - `/opt/appdata/tdarr/server`
    - `/opt/appdata/tdarr/configs`
    - `/opt/appdata/tdarr/logs`
    - `/transcode_cache` (temp/transcode workspace)

## Prerequisites

- Docker and Docker Compose plugin installed.
- Existing media directory tree under `/mnt/unraid_media/`.
- Config directories under `/opt/appdata/` with write permissions for your Docker user.
- Valid `.env` file in this repository.

## Start / Update the Stack

```bash
docker compose up -d --remove-orphans
```

## Stop the Stack

```bash
docker compose down
```

## Service URLs

| Service | URL |
|---|---|
| qBittorrent | http://localhost:8080 |
| Prowlarr | http://localhost:9696 |
| Sonarr | http://localhost:8989 |
| Radarr | http://localhost:7878 |
| Bazarr | http://localhost:6767 |
| Jellyfin | http://localhost:8096 |
| Seerr | http://localhost:5055 |
| Tdarr | http://localhost:8265 |
| ARM | http://localhost:8090 |

## Backups

- `config-backup.sh` backs up app configs from `/opt/appdata` to `/mnt/unraid_backups/media-server/configs`.
- Tdarr backup targets include:
    - `/opt/appdata/tdarr/server`
    - `/opt/appdata/tdarr/configs`
    - `/opt/appdata/tdarr/logs`

## Useful Commands

```bash
docker compose ps
docker compose logs -f tdarr
docker compose restart tdarr
docker compose config
```

## Notes

- Keep app databases/configs on native Linux storage (not mergerfs/FUSE) to avoid SQLite locking/corruption issues.
- If you remove or rename services, run with `--remove-orphans` to clean old containers.
