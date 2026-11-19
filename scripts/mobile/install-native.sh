#!/usr/bin/env bash
# install-native.sh — install the media stack natively on an arm64 Linux phone or tablet.
#
# Steps: packages -> service user -> data dirs -> app tarballs -> service definitions.
# Works with systemd, OpenRC, or runit. INIT=none installs only (used by Termux,
# where termux-start.sh supervises the services).
#
# App download URLs are NOT built in. Set them yourself, after checking the release page:
#   JELLYFIN_URL  SONARR_URL  RADARR_URL  PROWLARR_URL
# Apps without a URL are skipped with a message.
#
# Environment:
#   DRY_RUN=1     print every action, change nothing
#   SKIP_SYSTEM=1 skip packages, user, and directories (for tests)
#   ROOT_PREFIX   prefix for service-file destinations (default empty = real /etc, /run)
#   INIT          systemd | openrc | runit | none (default: detect)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib-services.sh
. "$HERE/lib-services.sh"

DRY_RUN="${DRY_RUN:-0}"
SKIP_SYSTEM="${SKIP_SYSTEM:-0}"
ROOT_PREFIX="${ROOT_PREFIX:-}"
INIT="${INIT:-$(bash "$HERE/detect-init.sh")}"

log()  { echo "[install] $*"; }
run()  { if [ "$DRY_RUN" = 1 ]; then echo "DRY: $*"; else "$@"; fi; }
warn() { echo "[install] WARNING: $*" >&2; }

# --- Checks -----------------------------------------------------------------
arch="$(uname -m)"
case "$arch" in
  aarch64|arm64) log "architecture: $arch" ;;
  x86_64) warn "architecture x86_64: this installer targets arm64 devices; continuing for testing" ;;
  *) echo "[install] unsupported architecture: $arch" >&2; exit 1 ;;
esac
log "init system: $INIT"

# --- Packages ---------------------------------------------------------------
install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    run apt-get install -y transmission-daemon curl ca-certificates
  elif command -v apk >/dev/null 2>&1; then
    run apk add transmission-daemon curl ca-certificates
  elif command -v pacman >/dev/null 2>&1; then
    run pacman -S --noconfirm transmission-cli curl ca-certificates
  elif command -v dnf >/dev/null 2>&1; then
    run dnf install -y transmission-daemon curl ca-certificates
  else
    warn "no supported package manager (apt, apk, pacman, dnf). Install transmission-daemon yourself"
  fi
}

if [ "$SKIP_SYSTEM" != 1 ]; then
  install_packages
  id "$SVC_USER" >/dev/null 2>&1 || run useradd -r -m -d "$CONFIG_ROOT" -s /usr/sbin/nologin "$SVC_USER"
  run install -d -o "$SVC_USER" -g "$SVC_USER" "$CONFIG_ROOT" "$INSTALL_ROOT" \
      "$DATA_ROOT/torrents" "$DATA_ROOT/media/tv" "$DATA_ROOT/media/movies"
  for s in $SERVICES; do
    run install -d -o "$SVC_USER" -g "$SVC_USER" "$CONFIG_ROOT/$s"
  done
  # Seed download-only Transmission settings only if none exist yet.
  if [ ! -f "$CONFIG_ROOT/transmission/settings.json" ] && [ -f "$HERE/../../config-examples/transmission-settings.json" ]; then
    run install -D -o "$SVC_USER" -g "$SVC_USER" "$HERE/../../config-examples/transmission-settings.json" "$CONFIG_ROOT/transmission/settings.json"
  fi
fi

# --- App tarballs -----------------------------------------------------------
fetch_app() {  # fetch_app <service> <url>
  local svc="$1" url="$2" tmp
  tmp="$(mktemp -d)"
  log "downloading $svc"
  if [ "$DRY_RUN" = 1 ]; then echo "DRY: curl -fL '$url' | tar -xz -C $INSTALL_ROOT"; rm -rf "$tmp"; return 0; fi
  curl -fL --max-time 900 -o "$tmp/app.tar.gz" "$url" || { warn "download failed for $svc"; rm -rf "$tmp"; return 1; }
  mkdir -p "$tmp/x" && tar -xzf "$tmp/app.tar.gz" -C "$tmp/x" || { warn "extract failed for $svc"; rm -rf "$tmp"; return 1; }
  # Tarballs have one top-level directory; move it under INSTALL_ROOT.
  local top; top="$(ls "$tmp/x" | head -1)"
  rm -rf "${INSTALL_ROOT:?}/$svc"
  mkdir -p "$INSTALL_ROOT"
  mv "$tmp/x/$top" "$INSTALL_ROOT/$svc" 2>/dev/null || mv "$tmp/x/$top" "$INSTALL_ROOT/$top"
  rm -rf "$tmp"
  log "installed $svc into $INSTALL_ROOT"
}

for s in $SERVICES; do
  var="$(svc_url_var "$s")"
  [ -z "$var" ] && continue          # transmission: from packages
  url="${!var:-}"
  if [ -z "$url" ]; then
    warn "skipping $s: set $var to the arm64 tarball URL from the release page"
    continue
  fi
  fetch_app "$s" "$url" || warn "$s not installed"
done

# --- Service definitions ----------------------------------------------------
write_unit() {  # write_unit <path> ; reads content from stdin
  local path="$ROOT_PREFIX$1"
  if [ "$DRY_RUN" = 1 ]; then echo "DRY: write $path"; sed 's/^/    /'; return 0; fi
  mkdir -p "$(dirname "$path")" && cat > "$path"
}

systemd_unit() {  # systemd_unit <svc>
  cat <<UNIT
[Unit]
Description=media-$1
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
ExecStart=$(svc_cmd "$1")
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT
}

case "$INIT" in
  systemd)
    for s in $SERVICES; do
      systemd_unit "$s" | write_unit "/etc/systemd/system/media-$s.service"
    done
    cat <<WD | write_unit "/etc/systemd/system/media-watchdog.service"
[Unit]
Description=media power/heat watchdog

[Service]
Type=oneshot
ExecStart=$HERE/power-watchdog.sh
WD
    cat <<TM | write_unit "/etc/systemd/system/media-watchdog.timer"
[Unit]
Description=run media watchdog every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
TM
    if [ "$SKIP_SYSTEM" != 1 ] && [ -z "$ROOT_PREFIX" ]; then
      run systemctl daemon-reload
      for s in $SERVICES; do run systemctl enable --now "media-$s.service"; done
      run systemctl enable --now media-watchdog.timer
    fi
    ;;
  openrc)
    for s in $SERVICES; do
      cat <<RC | write_unit "/etc/init.d/media-$s"
#!/sbin/openrc-run
name="media-$s"
command="$(svc_cmd "$s" | cut -d' ' -f1)"
command_args="$(svc_cmd "$s" | cut -s -d' ' -f2-)"
command_user="$SVC_USER"
supervisor="supervise-daemon"
depend() { need net; }
RC
    done
    if [ "$SKIP_SYSTEM" != 1 ] && [ -z "$ROOT_PREFIX" ]; then
      for s in $SERVICES; do run rc-update add "media-$s" default; run rc-service "media-$s" start; done
    fi
    warn "OpenRC: schedule power-watchdog.sh yourself (cron or a loop); no timer is written"
    ;;
  runit)
    for s in $SERVICES; do
      cat <<RUN | write_unit "/etc/sv/media-$s/run"
#!/bin/sh
exec chpst -u $SVC_USER $(svc_cmd "$s")
RUN
      [ "$DRY_RUN" = 1 ] || chmod +x "$ROOT_PREFIX/etc/sv/media-$s/run" 2>/dev/null
      if [ "$SKIP_SYSTEM" != 1 ] && [ -z "$ROOT_PREFIX" ]; then run ln -sfn "/etc/sv/media-$s" "/etc/service/media-$s"; fi
    done
    warn "runit: schedule power-watchdog.sh yourself; no timer is written"
    ;;
  none)
    log "INIT=none: services not registered. Start them with termux-start.sh (or your own supervisor)."
    ;;
  *)
    warn "unknown init '$INIT'. Services not registered."
    ;;
esac

log "done"
