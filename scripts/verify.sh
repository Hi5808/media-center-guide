#!/usr/bin/env bash
# Quick end-to-end health check. Set HOST to your <TAILSCALE_IP>.
set -uo pipefail
HOST="${1:-127.0.0.1}"

echo "== disk =="
df -h /srv 2>/dev/null || echo "  (/srv not found)"

echo "== services =="
for s in transmission-daemon jellyfin sonarr radarr prowlarr; do
  printf '  %-22s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null || echo '???')"
done

echo "== docker =="
docker ps --filter name=homepage --format '  {{.Names}}  {{.Status}}' 2>/dev/null || echo "  (docker not available)"

echo "== ports =="
for p in 8096 8989 7878 9696 9091 7575; do
  if curl -fsS -o /dev/null --max-time 5 "http://${HOST}:${p}" 2>/dev/null; then
    echo "  ${p} reachable"
  else
    echo "  ${p} NOT reachable (may need auth; that's fine if the service is up)"
  fi
done

echo "== category download dirs (Sonarr/Radarr) =="
for d in /srv/torrents/tv-sonarr /srv/torrents/radarr; do
  [ -d "$d" ] && echo "  ok  $d" || echo "  MISSING  $d  (create it, see docs/08-gotchas.md)"
done
