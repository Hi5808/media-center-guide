#!/usr/bin/env bash
# Nudge Sonarr and Radarr to scan the shared staging dir and import any
# manually-added downloads whose title is already in the library.
# Installed to /usr/local/bin/media-autoimport.sh and run by media-autoimport.timer.
set -euo pipefail

HOST="<TAILSCALE_IP>"
STAGING="/srv/torrents"

SONARR_URL="http://${HOST}:8989"
SONARR_KEY="<SONARR_API_KEY>"
RADARR_URL="http://${HOST}:7878"
RADARR_KEY="<RADARR_API_KEY>"

scan() {
  local url="$1" key="$2" cmd="$3"
  curl -fsS -X POST "${url}/api/v3/command" \
    -H "X-Api-Key: ${key}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${cmd}\",\"path\":\"${STAGING}\",\"importMode\":\"Copy\"}" \
    >/dev/null || echo "WARN: ${cmd} on ${url} failed" >&2
}

scan "$SONARR_URL" "$SONARR_KEY" "DownloadedEpisodesScan"
scan "$RADARR_URL" "$RADARR_KEY" "DownloadedMoviesScan"
