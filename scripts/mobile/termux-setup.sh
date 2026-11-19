#!/usr/bin/env bash
# termux-setup.sh — run INSIDE Termux on an Android phone or tablet.
#
# Installs a Debian userland via proot-distro, installs the stack into it with
# install-native.sh (INIT=none), and sets up Termux:Boot to start everything after reboot.
#
# Before running:
#   1. Install Termux and Termux:Boot (F-Droid). Install the Tailscale app.
#   2. In Android settings, set Termux, Termux:Boot, and Tailscale to unrestricted battery use.
#   3. Clone this repo inside Termux:  pkg install git && git clone <repo> && cd media-center-guide
#   4. Run:  bash scripts/mobile/termux-setup.sh
#
# Set the app URLs first (see install-native.sh), e.g.  JELLYFIN_URL=... bash termux-setup.sh

set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

if [ -z "${PREFIX:-}" ] || ! echo "$PREFIX" | grep -q 'com.termux'; then
  echo "This must run inside Termux on Android." >&2
  exit 1
fi

echo "[termux] updating packages"
pkg update -y
pkg install -y proot-distro git curl

command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || echo "[termux] termux-wake-lock not found; install Termux:API or keep the app open once"

ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
if [ ! -d "$ROOTFS" ]; then
  echo "[termux] installing Debian userland (this takes a while)"
  proot-distro install debian
fi

echo "[termux] copying repo into the Debian userland"
mkdir -p "$ROOTFS/root"
rm -rf "$ROOTFS/root/media-center-guide"
cp -r "$REPO" "$ROOTFS/root/media-center-guide"

echo "[termux] installing the stack inside Debian"
proot-distro login debian -- env \
  INIT=none \
  JELLYFIN_URL="${JELLYFIN_URL:-}" SONARR_URL="${SONARR_URL:-}" \
  RADARR_URL="${RADARR_URL:-}" PROWLARR_URL="${PROWLARR_URL:-}" \
  bash /root/media-center-guide/scripts/mobile/install-native.sh

echo "[termux] setting up Termux:Boot"
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/start-media.sh" <<'BOOT'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock 2>/dev/null
proot-distro login debian -- bash /root/media-center-guide/scripts/mobile/termux-start.sh >> "$HOME/media-start.log" 2>&1 &
BOOT
chmod +x "$HOME/.termux/boot/start-media.sh"

echo "[termux] done. Start now with:"
echo "  proot-distro login debian -- bash /root/media-center-guide/scripts/mobile/termux-start.sh &"
echo "Note: power-watchdog reads Linux sysfs, which Android may not expose; check the logs."
