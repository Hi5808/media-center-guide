#!/usr/bin/env bash
# Generic installer for a Servarr app (Sonarr / Radarr / Prowlarr) from the
# official tarball, running as the debian-transmission user, with a systemd unit.
#
# Usage:  sudo ./install-servarr.sh <sonarr|radarr|prowlarr>
#
# Mirrors the layout in the docs: /opt/<App>, data /var/lib/<app>, Restart=on-failure.
set -euo pipefail

APP="${1:?usage: install-servarr.sh <sonarr|radarr|prowlarr>}"
USER="debian-transmission"

case "$APP" in
  sonarr)   NAME="Sonarr";   URL="https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux&arch=x64" ;;
  radarr)   NAME="Radarr";   URL="https://radarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64" ;;
  prowlarr) NAME="Prowlarr"; URL="https://prowlarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64" ;;
  *) echo "unknown app: $APP" >&2; exit 1 ;;
esac

# The debian-transmission user must exist first (install transmission-daemon).
id "$USER" >/dev/null 2>&1 || { echo "user $USER missing — install transmission-daemon first"; exit 1; }

apt-get update
apt-get install -y curl sqlite3

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $NAME ..."
curl -fsSL "$URL" -o "$tmp/$APP.tar.gz"
tar -xzf "$tmp/$APP.tar.gz" -C "$tmp"

# The tarball extracts to a top-level dir matching $NAME.
systemctl stop "$APP" 2>/dev/null || true
rm -rf "/opt/$NAME"
mv "$tmp/$NAME" "/opt/$NAME"

install -d -o "$USER" -g "$USER" "/var/lib/$APP"
chown -R "$USER":"$USER" "/opt/$NAME"

cat >"/etc/systemd/system/$APP.service" <<EOF
[Unit]
Description=$NAME
After=network-online.target

[Service]
User=$USER
Group=$USER
Type=simple
ExecStart=/opt/$NAME/$NAME -nobrowser -data=/var/lib/$APP
Restart=on-failure
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$APP"
echo "$NAME installed and started. API key will be in /var/lib/$APP/config.xml once it initializes."
