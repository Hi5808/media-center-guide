#!/usr/bin/env bash
# detect-init.sh — print the init system this host runs: systemd | openrc | runit | unknown.
#
# Used by the mobile install and service layer to pick the right service files.
# Paths can be overridden for testing: RUN_ROOT (default /run), SV_DIR (default /etc/sv).

set -u
RUN_ROOT="${RUN_ROOT:-/run}"
SV_DIR="${SV_DIR:-/etc/sv}"

if [ -d "$RUN_ROOT/systemd/system" ]; then
  echo systemd
elif [ -d "$RUN_ROOT/openrc" ] || command -v rc-service >/dev/null 2>&1; then
  echo openrc
elif [ -d "$SV_DIR" ] && command -v sv >/dev/null 2>&1; then
  echo runit
else
  echo unknown
fi
