#!/usr/bin/env bash
# lib-services.sh — shared definitions for the mobile installers. Source it, do not run it.
#
# Defines the services, their run commands, and default paths. Every value can be
# overridden from the environment.

INSTALL_ROOT="${INSTALL_ROOT:-/opt/media}"     # app binaries (tarballs extract here)
DATA_ROOT="${DATA_ROOT:-/srv/data}"            # torrents/ and media/ (one filesystem)
CONFIG_ROOT="${CONFIG_ROOT:-/var/lib/media}"   # per-app config and databases
SVC_USER="${SVC_USER:-media}"
SERVICES="transmission jellyfin sonarr radarr prowlarr"

# Run command for a service (foreground, so a supervisor can own it).
# Flags are the standard ones for each app; check them against the release you install.
svc_cmd() {
  case "$1" in
    transmission) echo "transmission-daemon -f -g $CONFIG_ROOT/transmission -e $CONFIG_ROOT/transmission/log.txt" ;;
    jellyfin)     echo "$INSTALL_ROOT/jellyfin/jellyfin --datadir $CONFIG_ROOT/jellyfin --cachedir $CONFIG_ROOT/jellyfin/cache" ;;
    sonarr)       echo "$INSTALL_ROOT/Sonarr/Sonarr -nobrowser -data=$CONFIG_ROOT/sonarr" ;;
    radarr)       echo "$INSTALL_ROOT/Radarr/Radarr -nobrowser -data=$CONFIG_ROOT/radarr" ;;
    prowlarr)     echo "$INSTALL_ROOT/Prowlarr/Prowlarr -nobrowser -data=$CONFIG_ROOT/prowlarr" ;;
    *) return 1 ;;
  esac
}

# Download URL variable name for each app (empty means transmission, which comes from the package manager).
svc_url_var() {
  case "$1" in
    jellyfin) echo JELLYFIN_URL ;;
    sonarr)   echo SONARR_URL ;;
    radarr)   echo RADARR_URL ;;
    prowlarr) echo PROWLARR_URL ;;
    *) echo "" ;;
  esac
}
