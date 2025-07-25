# Media Management Docker Compose Setup

This Docker Compose configuration provides a comprehensive media management stack using popular LinuxServer.io containers. It includes automation tools for movies, TV shows, books, downloads, media servers, download clients, and now supports transcoding and automated disc ripping.

---

## Included Services

| Service                  | Description                                         | Port(s)      | Status   |
|--------------------------|-----------------------------------------------------|--------------|----------|
| **Radarr**               | Movie collection manager and downloader             | 7878         | Active   |
| **Sonarr**               | TV series collection manager and downloader         | 8989         | Active   |
| **Prowlarr**             | Indexer manager for Radarr, Sonarr, etc.           | 9696         | Active   |
| **Bazarr**               | Subtitle downloader for movies and TV shows         | 6767         | Active   |
| **Readarr**              | Book collection manager and downloader              | 8787         | Active   |
| **qBittorrent**          | Torrent client with Web UI                          | 8080, 6881   | Active   |
| **Jellyfin**             | Media server for streaming movies and TV shows      | 8096, 8920   | Active   |
| **Tdarr**                | Automated media transcoding and health checking     | 8265, 8266   | Active   |
| **Automated Ripping Machine (ARM)** | Automated disc ripping and metadata fetching | 8081         | Active   |

---

## Features

- **User and Group IDs:** All containers run with `PUID=1000` and `PGID=1000` to match host user permissions.
- **Timezone:** Set to `Etc/UTC` by default; adjust as needed.
- **Persistent Storage:**
- **Config directories** are stored under `/opt` (e.g. `/opt/sonarr_config`) on a native Linux filesystem for reliability.
- **Media, downloads, and backup folders** are mapped to `/media/josh/Media/...` on the host.
- **Automatic Restart:** Containers restart unless stopped manually.
- **Optional Volumes:** Movie, TV, book, download, transcoding, and rip folders are optionally mounted for media access.

---

## Folder Structure on Host

```plaintext
/opt/
├── jellyfin_config/
├── jellyseerr_config/
├── sonarr_config/
├── radarr_config/
├── prowlarr_config/
├── readarr_config/
├── qbittorrent_config/
├── tdarr_config/
├── arm_config/

/media/josh/Media/
├── Jellyfin/
│ └── config/ # backup only
├── Jellyseerr/
│ └── config/ # backup only
├── Sonarr/
│ ├── config/ # backup only
│ └── tvseries/
├── Radarr/
│ ├── config/ # backup only
│ └── movies/
├── Prowlarr/
│ └── config/ # backup only
├── Readarr/
│ ├── config/ # backup only
│ └── books/
├── qBittorrent/
│ ├── config/ # backup only
│ └── downloads/
├── Tdarr/
│ ├── config/ # backup only
│ └── transcoded/
├── ARM/
│ ├── config/ # backup only
│ └── rips/
└── ...
```

---

## 🛈 Important: Why Configs Are NOT on mergerfs or /media/josh/Media/

- The directory `/media/josh/Media` is a **mergerfs (FUSE-based union filesystem) mount**.
- **FUSE filesystems, including mergerfs, do _not_ provide safe file locking for SQLite databases** (used by the config of most tools here).
- Running config databases on mergerfs can cause disk I/O errors, database corruption, or lost settings.
- **All containers’ `/config` directories are mapped to `/opt/*_config` on a native Linux filesystem** (e.g. ext4, xfs, btrfs).
- Backups of these config folders are made to `/media/josh/Media/<service>/config` by a cron-scheduled script, but these backups should only be restored to `/opt/` in case of disaster.

---

## How to Use

### Prerequisites

- Docker and Docker Compose installed on your system.
- Media directories created and accessible under `/media/josh/Media/`.
- Config directories created under `/opt`.

### Setup

1. **Clone or create the `docker-compose.yml` file** with the provided configuration.
2. **Adjust environment variables if needed:**
    - Change `PUID` and `PGID` to match your user.
    - Set your timezone (`TZ`).
    - Modify volume paths if your media or backup locations are stored elsewhere.
3. **Create config folders under `/opt/`** and set user permissions:

    ```bash
    sudo mkdir -p /opt/sonarr_config /opt/radarr_config /opt/readarr_config /opt/prowlarr_config /opt/qbittorrent_config /opt/jellyfin_config /opt/jellyseerr_config /opt/tdarr_config /opt/arm_config
    sudo chown -R 1000:1000 /opt/*
    ```

4. **Start the stack:**

    ```bash
    docker-compose up -d
    ```

---

### Access Services via Web UI

| Service         | URL                        |
|-----------------|---------------------------|
| Radarr          | <http://localhost:7878>      |
| Sonarr          | <http://localhost:8989>      |
| Prowlarr        | <http://localhost:9696>      |
| Bazarr          | <http://localhost:6767>      |
| Readarr         | <http://localhost:8787>      |
| qBittorrent     | <http://localhost:8080>      |
| Jellyfin        | <http://localhost:8096>      |
| Tdarr           | <http://localhost:8265>      |
| ARM             | <http://localhost:8081>      |

---

## Notes

- **Config folders** (`/config` in containers) must always be on a native disk. Only media content and backups go on mergerfs.
- **Backup script:** `/home/josh/media/backup-opt-configs.sh` copies `/opt/*_config` to `/media/josh/Media/<Service>/config` regularly for disaster recovery.
- **Ports:** Ensure no port conflicts on your host machine.
- **Permissions:** Make sure the user running Docker has read/write access to all the mapped directories.

---

## Troubleshooting

- If containers fail to start, verify the volume paths and permissions.
- Check container logs with:

    ```bash
    docker logs <container_name>
    ```

- Adjust `PUID` and `PGID` if permission issues occur.
- If restoring from a config backup, copy from `/media/josh/Media/<Service>/config` **to** `/opt/<service>_config/` and ensure permissions are correct.

---

## Useful Links

- [LinuxServer.io Docker Hub](https://hub.docker.com/u/linuxserver)
- [Radarr](https://radarr.video/)
- [Sonarr](https://sonarr.tv/)
- [Prowlarr](https://prowlarr.com/)
- [Bazarr](https://www.bazarr.media/)
- [Readarr](https://readarr.com/)
- [qBittorrent](https://www.qbittorrent.org/)
- [Jellyfin](https://jellyfin.org/)
- [Tdarr](https://tdarr.io/)
- [Automated Ripping Machine (ARM)](https://automatic-ripping-machine.github.io/)
- [mergerfs FAQ: databases](https://github.com/trapexit/mergerfs/wiki/FAQ#is-mergerfs-safe-for-databases)
- [SQLite How To Corrupt](https://sqlite.org/howtocorrupt.html#_file_locking_problems)

---

Enjoy your automated media management system!  
If you have any questions or need help setting up additional services, feel free to reach out.

_Last updated: July 2025 – config reliability improved by separating app configs from mergerfs!_
