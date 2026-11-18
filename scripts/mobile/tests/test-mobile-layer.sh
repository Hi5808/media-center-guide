#!/usr/bin/env bash
# Tests for scripts/mobile/ using a fake sysfs tree. No hardware or services needed.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WD="$HERE/power-watchdog.sh"
DI="$HERE/detect-init.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0

ok()   { echo "ok    $*"; }
bad()  { echo "FAIL  $*"; fails=$((fails+1)); }

# make_device <temp_mC> <battery_pct|none> <on_ac 0|1>
make_device() {
  rm -rf "$T/sys"; mkdir -p "$T/sys/thermal/thermal_zone0" "$T/sys/power_supply/bat" "$T/sys/power_supply/usb"
  echo "$1" > "$T/sys/thermal/thermal_zone0/temp"
  if [ "$2" != "none" ]; then
    echo Battery > "$T/sys/power_supply/bat/type"; echo "$2" > "$T/sys/power_supply/bat/capacity"
  else
    echo Battery > "$T/sys/power_supply/bat/type"; echo 100 > "$T/sys/power_supply/bat/capacity"
  fi
  echo USB > "$T/sys/power_supply/usb/type"; echo "$3" > "$T/sys/power_supply/usb/online"
}

# run_wd: run watchdog once in dry-run mode, return its output
run_wd() {
  SYSFS_CLASS="$T/sys" STATE_FILE="$T/state" DRY_RUN=1 bash "$WD" 2>&1
}

expect_state() {  # expect_state <name> <expected_state>
  local got; got="$(cat "$T/state" 2>/dev/null || echo running)"
  [ "$got" = "$2" ] && ok "$1 -> $2" || bad "$1: expected $2, got $got"
}

# Real run (not dry) to exercise state persistence, with a stub action command.
run_real() {
  SYSFS_CLASS="$T/sys" STATE_FILE="$T/state" PAUSE_CMD="echo PAUSED_ACTION" RESUME_CMD="echo RESUMED_ACTION" bash "$WD" 2>&1
}
reset_state() { rm -f "$T/state"; }

# 1. Hot device pauses
reset_state; make_device 75000 90 1; run_real >/dev/null; expect_state "hot (75C) pauses" paused

# 2. Hysteresis: cooled to 65C is still above RESUME_TEMP_C=60, stays paused
make_device 65000 90 1; run_real >/dev/null; expect_state "65C stays paused (hysteresis)" paused

# 3. Cools to 55C on AC with battery OK: resumes
make_device 55000 90 1; out="$(run_real)"; expect_state "55C on AC resumes" running
echo "$out" | grep -q RESUMED_ACTION && ok "resume action ran" || bad "resume action did not run"

# 4. Low battery on battery power pauses
make_device 40000 15 0; run_real >/dev/null; expect_state "15% on battery pauses" paused

# 5. Low battery but on AC does NOT pause
reset_state; make_device 40000 15 1; run_real >/dev/null; expect_state "15% on AC does not pause" running

# 6. Pause at 15% on battery, then 25% on battery stays paused (below RESUME_BATTERY=30)
reset_state; make_device 40000 15 0; run_real >/dev/null
make_device 40000 25 0; run_real >/dev/null; expect_state "25% on battery stays paused" paused

# 7. Battery at 35% on battery, cool: resumes
make_device 40000 35 0; run_real >/dev/null; expect_state "35% on battery, cool, resumes" running

# 8. No sensors, no battery: never pauses on missing data
reset_state; rm -rf "$T/sys"; mkdir -p "$T/sys"; run_real >/dev/null; expect_state "no sensors does not pause" running

# 9. Dry run never writes state
reset_state; make_device 80000 90 1; run_wd >/dev/null; [ ! -e "$T/state" ] && ok "dry run writes no state" || bad "dry run wrote state"

# 10. Missing transmission-remote is reported, state still recorded
reset_state; make_device 80000 90 1
out="$(SYSFS_CLASS="$T/sys" STATE_FILE="$T/state" PAUSE_CMD="no-such-cmd-xyz -t all -S" bash "$WD" 2>&1)"
echo "$out" | grep -q "not installed" && ok "missing command warns" || bad "missing command not reported"
expect_state "missing command still records state" paused

# 11. detect-init: systemd / openrc / runit / unknown using fake roots
mkdir -p "$T/r1/systemd/system"; [ "$(RUN_ROOT="$T/r1" SV_DIR="$T/none" bash "$DI")" = systemd ] && ok "detects systemd" || bad "systemd not detected"
mkdir -p "$T/r2/openrc";         [ "$(RUN_ROOT="$T/r2" SV_DIR="$T/none" bash "$DI")" = openrc ] && ok "detects openrc" || bad "openrc not detected"
mkdir -p "$T/r3" "$T/sv";        [ "$(RUN_ROOT="$T/r3" SV_DIR="$T/sv" bash "$DI")" = unknown ] && ok "no runit tool -> unknown" || bad "runit check"
[ "$(RUN_ROOT="$T/r3" SV_DIR="$T/none" bash "$DI")" = unknown ] && ok "empty root -> unknown" || bad "unknown case"

echo
[ "$fails" -eq 0 ] && echo "All tests passed." || { echo "$fails test(s) failed."; exit 1; }
