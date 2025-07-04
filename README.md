# Media Management Docker Compose Setup

This Docker Compose configuration provides a comprehensive media management stack using popular LinuxServer.io containers. It includes automation tools for movies, TV shows, books, and downloads, as well as media servers and download clients.

---

## Included Services

| Service         | Description                                   | Port(s)                    | Status   |
|-----------------|-----------------------------------------------|----------------------------|----------|
| **Radarr**      | Movie collection manager and downloader        | 7878                       | Active   |
| **Sonarr**      | TV series collection manager and downloader    | 8989                       | Active   |
| **Prowlarr**    | Indexer manager for Radarr, Sonarr, etc.      | 9696                       | Active   |
| **Bazarr**      | Subtitle downloader for movies and TV shows    | 6767                       | Active   |
| **Readarr**     | Book collection manager and downloader         | 8787                       | Active   |
| **qBittorrent** | Torrent client with Web UI                    | 8080, 6881                 | Active   |
| **Jellyfin**    | Media server for streaming movies and TV shows | 8096, 8920                 | Active   |

### Not Currently Active (Commented Out)

- **Lidarr**: Music manager
- **Tdarr**: Media transcoder
- **Plex**: Media server
- **Audiobookshelf**: Audiobook manager

---

## Features

- **User and Group IDs:** All containers run with `PUID=1000` and `PGID=1000` to match host user permissions.
- **Timezone:** Set to `Etc/UTC` by default; adjust as needed.
- **Persistent Storage:** Configurations and media files are mapped to `/media/josh/Media1/...` on the host.
- **Automatic Restart:** Containers restart unless stopped manually.
- **Optional Volumes:** Movie, TV, book, and download folders are optionally mounted for media access.

---

## Folder Structure on Host

```
├── Radarr/
│   ├── config/
│   └── movies/
├── Sonarr/
│   ├── config/
│   └── tvseries/
├── Prowlarr/
│   └── config/
├── Bazarr/
│   └── config/
├── Readarr/
│   ├── config/
│   └── books/
├── qBittorrent/
│   ├── config/
│   └── downloads/
├── Jellyfin/
│   └── config/
```

---

## How to Use

### Prerequisites

- Docker and Docker Compose installed on your system.
- Media directories created and accessible under `/media/josh/Media1/`.

### Setup

1. **Clone or create the `docker-compose.yml` file** with the provided configuration.
2. **Adjust environment variables if needed:**
   - Change `PUID` and `PGID` to match your user.
   - Set your timezone (`TZ`).
   - Modify volume paths if your media is stored elsewhere.
3. **Start the stack:**

   ```bash
   docker-compose up -d
   ```

### Access Services via Web UI

| Service         | URL                        |
|-----------------|---------------------------|
| Radarr          | http://localhost:7878      |
| Sonarr          | http://localhost:8989      |
| Prowlarr        | http://localhost:9696      |
| Bazarr          | http://localhost:6767      |
| Readarr         | http://localhost:8787      |
| qBittorrent     | http://localhost:8080      |
| Jellyfin        | http://localhost:8096      |

---

## Notes

- **Optional Volumes:** Some volumes are marked optional and can be removed if you do not use those features.
- **Inactive Services:** Lidarr, Tdarr, Plex, and Audiobookshelf are included but commented out. Uncomment and configure if you want to enable them.
- **Ports:** Ensure no port conflicts on your host machine.
- **Permissions:** Make sure the user running Docker has read/write access to the media directories.

---

## Troubleshooting

- If containers fail to start, verify the volume paths and permissions.
- Check container logs with:

  ```bash
  docker logs <container_name>
  ```

- Adjust `PUID` and `PGID` if permission issues occur.

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

---

Enjoy your automated media management system! If you have any questions or need help setting up additional services, feel free