#!/bin/bash

# Back up service configs from /opt to /media/josh/Media/<Service>/config

rsync -av --delete /opt/jellyfin_config/ /media/josh/Media/Jellyfin/config/
rsync -av --delete /opt/jellyseerr_config/ /media/josh/Media/Jellyseerr/config/
rsync -av --delete /opt/sonarr_config/ /media/josh/Media/Sonarr/config/
rsync -av --delete /opt/radarr_config/ /media/josh/Media/Radarr/config/
rsync -av --delete /opt/prowlarr_config/ /media/josh/Media/Prowlarr/config/
rsync -av --delete /opt/readarr_config/ /media/josh/Media/Readarr/config/
rsync -av --delete /opt/qbittorrent_config/ /media/josh/Media/qbittorrent/config/

# Optional: Log time
echo "Backup completed at $(date)" >> /var/log/opt-config-backup.log
