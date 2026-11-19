#!/usr/bin/env bash
# termux-start.sh — run INSIDE the Debian userland (proot) on Android.
#
# Starts every service that is not already running, then runs the power watchdog
# once a minute. There is no systemd in proot, so this script is the supervisor.
# Logs go to /var/log/media/<service>.log.
#
# Stop everything: pkill -f termux-start.sh; pkill -f 'Sonarr|Radarr|Prowlarr|jellyfin|transmission-daemon'

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-services.sh
. "$HERE/lib-services.sh"

LOG_DIR="${LOG_DIR:-/var/log/media}"
PIDDIR="${PIDDIR:-/run/media}"
mkdir -p "$LOG_DIR" "$PIDDIR"

start_service() {
  local s="$1" pidfile="$PIDDIR/$1.pid" cmd
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    return 0
  fi
  cmd="$(svc_cmd "$s")" || return 1
  # shellcheck disable=SC2086
  nohup $cmd >> "$LOG_DIR/$s.log" 2>&1 &
  echo $! > "$pidfile"
  echo "[termux-start] started $s (pid $(cat "$pidfile"))"
}

while true; do
  for s in $SERVICES; do
    # Skip apps whose binary is not installed yet.
    bin="$(svc_cmd "$s" | cut -d' ' -f1)"
    [ -x "$bin" ] || command -v "$bin" >/dev/null 2>&1 || continue
    start_service "$s"
  done
  HERE="$HERE" bash "$HERE/power-watchdog.sh" || true
  sleep 60
done
