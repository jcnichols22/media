# Media Stack Docker Compose Setup

This repository runs a home media stack with Docker Compose, including VPN-routed downloading, media automation, streaming, request management, transcoding, and disc ripping.

## Current Services

| Service | Purpose | Port(s) |
|---|---|---|
| gluetun | ProtonVPN WireGuard tunnel for qBittorrent | 8080, 6881/tcp, 6881/udp |
| qbittorrent | Torrent client (routed through gluetun) | 8080 (via gluetun) |
| prowlarr | Indexer manager | 9696 |
| flaresolverr | Cloudflare bypass proxy for indexers | 8191 |
| profilarr | Syncs Sonarr/Radarr CFs/profiles | 6868 |
| sonarr | TV automation | 8989 |
| radarr | Movie automation | 7878 |
| bazarr | Subtitle automation | 6767 |
| jellyfin | Media server | 8096, 7359/udp, 1900/udp |
| plex | Media server | host network |
| seerr | Request management | 5055 |
| jellyplex-watched | Plex/Jellyfin watched-state sync | (no published ports) |
| tdarr | Transcoding + health checks (Intel QuickSync) | 8265, 8266 |
| arm-rippers | Automated Ripping Machine | 8090 |

## Image Management Policy (Pinned Digests)

This stack now uses digest-pinned images in `docker-compose.yml` (for example `image: repo/name@sha256:...`) for reproducible, controlled updates.

**Policy:**
- Do not use `:latest` directly in compose.
- Upgrade in small batches with post-checks and rollback readiness.
- If an upgrade fails, restore prior digest and recreate only affected services.

## Change Management Rule (Important)

**After any stack change, update this README in the same session.**

At minimum, document:
1. What changed (services/images/config)
2. Why it changed
3. Validation performed
4. Rollback notes (if relevant)

Treat this file as the operational runbook, not just setup notes.

## Controlled Upgrade Workflow

1. Backup compose file:
   ```bash
   cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d-%H%M%S)
   ```
2. Update target service digest(s) in compose.
3. Validate:
   ```bash
   docker compose config -q
   ```
4. Pull + recreate only target services:
   ```bash
   docker compose pull <service...>
   docker compose up -d <service...>
   ```
5. Verify health/logs:
   ```bash
   docker compose ps <service...>
   docker logs --tail 80 <service>
   ```
6. If failed, rollback immediately:
   - restore previous compose
   - `docker compose up -d <service...>`

## Tdarr Configuration

- Tdarr runs as a single container with the built-in node enabled.
- `internalNode=true` is enabled in `docker-compose.yml`.
- No separate `tdarr-node` service is used.
- Intel QuickSync is passed through via `/dev/dri`.

## Paths and Storage

- Media root (`ARRPATH`) is set in `.env` to `/mnt/unraid_media/`.
- App configs are stored on native storage under `/opt/appdata/<service>`.
- Anime is separated from standard libraries with dedicated paths:
  - `/mnt/unraid_media/Radarr/anime-movies`
  - `/mnt/unraid_media/Sonarr/anime-tvshows`
- Tdarr uses:
  - `/opt/appdata/tdarr/server`
  - `/opt/appdata/tdarr/configs`
  - `/opt/appdata/tdarr/logs`
  - `/transcode_cache` (temp/transcode workspace)

## Anime Separation Setup

After pulling the updated compose file, add separate root folders in each app:

1. Sonarr: add root folder `/data/anime-tvshows` (in addition to `/data/tvshows`).
2. Radarr: add root folder `/data/anime-movies` (in addition to `/data/movies`).
3. Bazarr: map anime series/movies from `/data/anime-tvshows` and `/data/anime-movies`.
4. Jellyfin/Plex: create separate libraries that point to:
   - `/data/AnimeTVShows`
   - `/data/AnimeMovies`

Then deploy changes:

```bash
docker compose up -d --remove-orphans
```

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
| FlareSolverr | http://localhost:8191 |
| Profilarr | http://localhost:6868 |
| Sonarr | http://localhost:8989 |
| Radarr | http://localhost:7878 |
| Bazarr | http://localhost:6767 |
| Jellyfin | http://localhost:8096 |
| Seerr | http://localhost:5055 |
| Tdarr | http://localhost:8265 |
| ARM | http://localhost:8090 |

## Backups

- `config-backup.sh` backs up app configs from `/opt/appdata` to `/mnt/unraid_backups/media-server/configs`.
- Preflight checks now fail fast if backup destination is unavailable/unwritable.
- Per-service rsync timeout guards prevent a single stuck mount from hanging all backups.
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
docker compose logs -f profilarr
```

## Notes

- Keep app databases/configs on native Linux storage (not mergerfs/FUSE) to avoid SQLite locking/corruption issues.
- If you remove or rename services, run with `--remove-orphans` to clean old containers.
