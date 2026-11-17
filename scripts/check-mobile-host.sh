#!/usr/bin/env bash
# check-mobile-host.sh — preflight for running the media stack on a phone or tablet.
#
# Read-only: reports on system state and changes nothing.
# Output: one line per check, prefixed PASS / WARN / FAIL.
#   FAIL = the stack will not run as written.
#   WARN = it will run, but fix this first.
#
# Usage: bash scripts/check-mobile-host.sh [DATA_ROOT]
#   DATA_ROOT defaults to /srv/data (see docs/10-mobile-linux.md).

set -u

DATA_ROOT="${1:-/srv/data}"
MIN_RAM_GB=4
MAX_TEMP_C=70

pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; }

# --- Architecture -----------------------------------------------------------
arch="$(uname -m)"
case "$arch" in
  aarch64|arm64) pass "architecture: $arch (arm64)" ;;
  armv7l|armv6l|armhf) warn "architecture: $arch (32-bit ARM). Check each app's release page; arm64 is the tested path" ;;
  x86_64|amd64) pass "architecture: $arch (x86_64, works too)" ;;
  *) fail "architecture: $arch is not supported by the guide's packages" ;;
esac

# --- RAM --------------------------------------------------------------------
if [ -r /proc/meminfo ]; then
  mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  mem_gb=$(( (mem_kb + 524288) / 1048576 ))   # round to nearest GiB
  if [ "$mem_gb" -ge "$MIN_RAM_GB" ]; then
    pass "memory: ~${mem_gb} GiB (>= ${MIN_RAM_GB} GiB)"
  else
    warn "memory: ~${mem_gb} GiB. Under ${MIN_RAM_GB} GiB, run fewer apps at once"
  fi
else
  warn "memory: /proc/meminfo not readable"
fi

# --- Data root and hardlink filesystem --------------------------------------
if [ -d "$DATA_ROOT" ]; then
  if [ -d "$DATA_ROOT/torrents" ] && [ -d "$DATA_ROOT/media" ]; then
    dev_t="$(stat -c %d "$DATA_ROOT/torrents")"
    dev_m="$(stat -c %d "$DATA_ROOT/media")"
    if [ "$dev_t" = "$dev_m" ]; then
      pass "hardlinks: torrents/ and media/ share one filesystem"
    else
      fail "hardlinks: torrents/ and media/ are on different filesystems. Imports will copy"
    fi
  else
    warn "hardlinks: $DATA_ROOT/torrents or $DATA_ROOT/media missing (create per chapter 10)"
  fi
  fstype="$(stat -f -c %T "$DATA_ROOT" 2>/dev/null)"
  case "$fstype" in
    ext4|xfs|btrfs) pass "filesystem: $fstype at $DATA_ROOT" ;;
    msdos|vfat|exfat|fuseblk) fail "filesystem: $fstype at $DATA_ROOT does not support hardlinks or Unix permissions" ;;
    *) warn "filesystem: '${fstype:-unknown}' at $DATA_ROOT. Confirm it supports hardlinks" ;;
  esac
  free_gb="$(df -BG --output=avail "$DATA_ROOT" 2>/dev/null | tail -1 | tr -dc '0-9')"
  if [ -n "$free_gb" ] && [ "$free_gb" -ge 50 ]; then
    pass "free space at $DATA_ROOT: ${free_gb} GiB"
  elif [ -n "$free_gb" ]; then
    warn "free space at $DATA_ROOT: ${free_gb} GiB. Consider more for a real library"
  fi
else
  warn "$DATA_ROOT does not exist yet (create it per chapter 10)"
fi

# --- Battery and charge limit -----------------------------------------------
battery_found=0
for ps in /sys/class/power_supply/*; do
  [ -r "$ps/type" ] || continue
  if [ "$(cat "$ps/type")" = "Battery" ]; then
    battery_found=1
    name="$(basename "$ps")"
    cap="$(cat "$ps/capacity" 2>/dev/null || echo '?')"
    status="$(cat "$ps/status" 2>/dev/null || echo '?')"
    pass "battery $name: ${cap}% (${status})"
    if [ -w "$ps/charge_control_end_threshold" ] || [ -r "$ps/charge_control_end_threshold" ]; then
      thr="$(cat "$ps/charge_control_end_threshold" 2>/dev/null)"
      pass "charge limit available on $name (currently ${thr}%). Set ~80% to reduce wear"
    else
      warn "no charge limit exposed for $name. Keep it on a stable charger and watch for swelling"
    fi
  fi
done
[ "$battery_found" -eq 0 ] && pass "no battery reported (mains-powered or no power_supply data)"

ac_online=0
for ps in /sys/class/power_supply/*; do
  [ -r "$ps/type" ] || continue
  if [ "$(cat "$ps/type")" != "Battery" ] && [ "$(cat "$ps/online" 2>/dev/null)" = "1" ]; then
    ac_online=1
  fi
done
if [ "$ac_online" -eq 1 ]; then
  pass "external power connected"
else
  [ "$battery_found" -eq 1 ] && warn "not on external power. Plug in before running as a server"
fi

# --- Temperature ------------------------------------------------------------
max_c=""
for t in /sys/class/thermal/thermal_zone*/temp; do
  [ -r "$t" ] || continue
  v="$(cat "$t" 2>/dev/null)"
  case "$v" in ''|*[!0-9]*) continue ;; esac
  c=$(( v >= 1000 ? v / 1000 : v ))
  if [ -z "$max_c" ] || [ "$c" -gt "$max_c" ]; then max_c="$c"; fi
done
if [ -n "$max_c" ]; then
  if [ "$max_c" -ge "$MAX_TEMP_C" ]; then
    warn "hottest thermal zone: ${max_c} C. Improve airflow; expect throttling"
  else
    pass "hottest thermal zone: ${max_c} C"
  fi
else
  warn "no thermal sensors readable. Check temperatures another way"
fi

# --- Suspend / sleep --------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
  masked=0
  for target in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    state="$(systemctl is-enabled "$target" 2>/dev/null || true)"
    [ "$state" = "masked" ] && masked=$((masked + 1))
  done
  if [ "$masked" -eq 4 ]; then
    pass "suspend/hibernate: all four sleep targets masked"
  else
    warn "suspend/hibernate: $masked of 4 targets masked. Run: sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target"
  fi
else
  warn "systemctl not found. On OpenRC, disable suspend-on-idle manually (see chapter 10)"
fi

# --- Tailscale --------------------------------------------------------------
if command -v tailscale >/dev/null 2>&1; then
  ts4="$(tailscale ip -4 2>/dev/null | head -1)"
  if [ -n "$ts4" ]; then
    pass "tailscale connected: $ts4"
  else
    warn "tailscale installed but no 100.x address. Run 'sudo tailscale up'"
  fi
else
  warn "tailscale not installed (chapter 1)"
fi

echo
echo "Done. Fix every FAIL before you install the services. Re-run after changes."
