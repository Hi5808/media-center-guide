#!/usr/bin/env bash
# power-watchdog.sh — pause heavy work when the device is hot or low on battery,
# resume when it recovers. Device-neutral: reads the standard Linux sysfs interfaces
# (/sys/class/power_supply and /sys/class/thermal), which most phones and SBCs expose.
#
# Run it periodically (systemd timer, cron, OpenRC/runit loop). Each run decides once.
#
# Decision (with hysteresis, so it does not flap):
#   PAUSE  if hottest zone >= MAX_TEMP_C, or on battery and capacity < MIN_BATTERY
#   RESUME only when hottest zone <= RESUME_TEMP_C and (on AC or capacity >= RESUME_BATTERY)
#   otherwise keep the current state.
#
# Actions: PAUSE_CMD / RESUME_CMD (default: Transmission queue via transmission-remote).
#
# Environment (all optional):
#   SYSFS_CLASS    default /sys/class           (power_supply and thermal live under it)
#   MAX_TEMP_C     default 70    RESUME_TEMP_C default 60
#   MIN_BATTERY    default 20    RESUME_BATTERY default 30
#   STATE_FILE     default /run/media-watchdog.state
#   PAUSE_CMD      default "transmission-remote -t all -S"
#   RESUME_CMD     default "transmission-remote -t all -s"
#   DRY_RUN=1      print actions instead of running them

set -u
SYSFS_CLASS="${SYSFS_CLASS:-/sys/class}"
MAX_TEMP_C="${MAX_TEMP_C:-70}"
RESUME_TEMP_C="${RESUME_TEMP_C:-60}"
MIN_BATTERY="${MIN_BATTERY:-20}"
RESUME_BATTERY="${RESUME_BATTERY:-30}"
STATE_FILE="${STATE_FILE:-/run/media-watchdog.state}"
PAUSE_CMD="${PAUSE_CMD:-transmission-remote -t all -S}"
RESUME_CMD="${RESUME_CMD:-transmission-remote -t all -s}"
DRY_RUN="${DRY_RUN:-0}"

# --- Read sensors -----------------------------------------------------------
read_hottest_c() {
  local max="" zone v c
  for zone in "$SYSFS_CLASS"/thermal/thermal_zone*/temp; do
    [ -r "$zone" ] || continue
    v="$(cat "$zone" 2>/dev/null)"
    case "$v" in ''|*[!0-9]*) continue ;; esac
    c=$(( v >= 1000 ? v / 1000 : v ))   # sysfs is millidegrees on most devices
    if [ -z "$max" ] || [ "$c" -gt "$max" ]; then max="$c"; fi
  done
  echo "$max"
}

# Sets BAT_CAP (percent or empty) and ON_AC (1 when external power is present).
read_power() {
  BAT_CAP=""
  ON_AC=0
  local ps type
  for ps in "$SYSFS_CLASS"/power_supply/*; do
    [ -r "$ps/type" ] || continue
    type="$(cat "$ps/type")"
    if [ "$type" = "Battery" ]; then
      [ -z "$BAT_CAP" ] && BAT_CAP="$(cat "$ps/capacity" 2>/dev/null)"
    elif [ "$(cat "$ps/online" 2>/dev/null)" = "1" ]; then
      ON_AC=1
    fi
  done
}

# --- Decide -----------------------------------------------------------------
current="running"
[ -r "$STATE_FILE" ] && current="$(cat "$STATE_FILE")"

temp="$(read_hottest_c)"
read_power

# Unknown temperature or battery counts as "fine": never pause on missing data alone.
hot=0; [ -n "$temp" ] && [ "$temp" -ge "$MAX_TEMP_C" ] && hot=1
cool=1; [ -n "$temp" ] && [ "$temp" -gt "$RESUME_TEMP_C" ] && cool=0
low=0
if [ -n "$BAT_CAP" ] && [ "$ON_AC" -eq 0 ] && [ "$BAT_CAP" -lt "$MIN_BATTERY" ]; then low=1; fi
ok_power=1
if [ -n "$BAT_CAP" ] && [ "$ON_AC" -eq 0 ] && [ "$BAT_CAP" -lt "$RESUME_BATTERY" ]; then ok_power=0; fi

next="$current"
if [ "$current" = "running" ] && { [ "$hot" -eq 1 ] || [ "$low" -eq 1 ]; }; then
  next="paused"
elif [ "$current" = "paused" ] && [ "$cool" -eq 1 ] && [ "$ok_power" -eq 1 ]; then
  next="running"
fi

echo "temp=${temp:-n/a}C battery=${BAT_CAP:-n/a}% ac=$ON_AC state=$current -> $next"

# --- Act on transitions only -------------------------------------------------
if [ "$next" != "$current" ]; then
  if [ "$next" = "paused" ]; then cmd="$PAUSE_CMD"; else cmd="$RESUME_CMD"; fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN: would run: $cmd"
  else
    # shellcheck disable=SC2086
    if command -v "${cmd%% *}" >/dev/null 2>&1; then
      $cmd || echo "warning: action failed: $cmd" >&2
    else
      echo "warning: '${cmd%% *}' not installed; state recorded but no action taken" >&2
    fi
  fi
  if [ "$DRY_RUN" != "1" ]; then
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
    echo "$next" > "$STATE_FILE"
  fi
fi
