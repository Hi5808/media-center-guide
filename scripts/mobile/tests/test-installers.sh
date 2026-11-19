#!/usr/bin/env bash
# Tests for install-native.sh and termux-start.sh. No packages, no network, no services.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; fails=$((fails+1)); }
has() { grep -qF -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 (missing: $2)"; }

# 1. systemd: unit files written with the right ExecStart and user
ROOT_PREFIX="$T/sd" SKIP_SYSTEM=1 INIT=systemd bash "$HERE/install-native.sh" >/dev/null 2>&1
has "$T/sd/etc/systemd/system/media-jellyfin.service" "ExecStart=/opt/media/jellyfin/jellyfin" "systemd jellyfin ExecStart"
has "$T/sd/etc/systemd/system/media-sonarr.service" "User=media" "systemd sonarr runs as media user"
has "$T/sd/etc/systemd/system/media-radarr.service" "Restart=on-failure" "systemd radarr restarts on failure"
has "$T/sd/etc/systemd/system/media-watchdog.timer" "OnUnitActiveSec=1min" "systemd watchdog timer every minute"
has "$T/sd/etc/systemd/system/media-watchdog.service" "power-watchdog.sh" "systemd watchdog calls power-watchdog.sh"

# 2. OpenRC: init scripts with supervise-daemon
ROOT_PREFIX="$T/rc" SKIP_SYSTEM=1 INIT=openrc bash "$HERE/install-native.sh" >/dev/null 2>&1
has "$T/rc/etc/init.d/media-prowlarr" "supervisor=\"supervise-daemon\"" "openrc uses supervise-daemon"
has "$T/rc/etc/init.d/media-transmission" "command=\"transmission-daemon\"" "openrc transmission command"

# 3. runit: run scripts with chpst
ROOT_PREFIX="$T/rv" SKIP_SYSTEM=1 INIT=runit bash "$HERE/install-native.sh" >/dev/null 2>&1
has "$T/rv/etc/sv/media-radarr/run" "exec chpst -u media" "runit uses chpst"
[ -x "$T/rv/etc/sv/media-radarr/run" ] && ok "runit run script is executable" || bad "runit run script not executable"

# 4. Missing URLs skip apps (no download attempted, nothing extracted)
out="$(SKIP_SYSTEM=1 INIT=none INSTALL_ROOT="$T/opt" bash "$HERE/install-native.sh" 2>&1)"
echo "$out" | grep -q "skipping jellyfin: set JELLYFIN_URL" && ok "missing URL skips with message" || bad "missing URL not reported"
[ ! -e "$T/opt/jellyfin" ] && ok "no app extracted without URL" || bad "app extracted without URL"

# 5. DRY_RUN with URL prints the download plan and changes nothing
out="$(DRY_RUN=1 SKIP_SYSTEM=1 INIT=none INSTALL_ROOT="$T/opt" SONARR_URL="https://example.invalid/sonarr.tar.gz" bash "$HERE/install-native.sh" 2>&1)"
echo "$out" | grep -q "DRY: curl -fL 'https://example.invalid/sonarr.tar.gz'" && ok "DRY_RUN shows download plan" || bad "DRY_RUN plan missing"
[ ! -e "$T/opt" ] && ok "DRY_RUN changes nothing" || bad "DRY_RUN created files"

# 6. Unknown init is reported, no service files written
out="$(ROOT_PREFIX="$T/unk" SKIP_SYSTEM=1 INIT=bogus bash "$HERE/install-native.sh" 2>&1)"
echo "$out" | grep -q "unknown init" && ok "unknown init reported" || bad "unknown init not reported"

# 7. termux-start.sh: starts a service via a stub binary, logs output, and skips when already running
mkdir -p "$T/bin"
printf '#!/bin/sh\necho STUB_TRANSMISSION_RUNNING\nsleep 300\n' > "$T/bin/transmission-daemon"; chmod +x "$T/bin/transmission-daemon"
( PATH="$T/bin:$PATH" LOG_DIR="$T/log" PIDDIR="$T/pid" CONFIG_ROOT="$T/cfg" timeout 4 bash "$HERE/termux-start.sh" >"$T/start.out" 2>&1 ) || true
grep -q "started transmission" "$T/start.out" && ok "termux-start launches transmission stub" || bad "termux-start did not launch"
sleep 1; has "$T/log/transmission.log" "STUB_TRANSMISSION_RUNNING" "service output goes to log"
[ -f "$T/pid/transmission.pid" ] && ok "pidfile written" || bad "no pidfile"
( PATH="$T/bin:$PATH" LOG_DIR="$T/log" PIDDIR="$T/pid" CONFIG_ROOT="$T/cfg" timeout 2 bash "$HERE/termux-start.sh" >"$T/start2.out" 2>&1 ) || true
grep -q "started transmission" "$T/start2.out" && bad "restarted a live service" || ok "live pid is not restarted"

pid="$(cat "$T/pid/transmission.pid")"
kill "$pid" 2>/dev/null; pkill -f "$T/bin/transmission-daemon" 2>/dev/null
for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
( PATH="$T/bin:$PATH" LOG_DIR="$T/log" PIDDIR="$T/pid" CONFIG_ROOT="$T/cfg" timeout 2 bash "$HERE/termux-start.sh" >"$T/start3.out" 2>&1 ) || true
grep -q "started transmission" "$T/start3.out" && ok "dead pid is restarted" || bad "dead service not restarted"
pkill -f "$T/bin/transmission-daemon" 2>/dev/null

echo
[ "$fails" -eq 0 ] && echo "All installer tests passed." || { echo "$fails test(s) failed."; exit 1; }
