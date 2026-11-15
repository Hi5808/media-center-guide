#!/usr/bin/env bash
# Thin wrapper — installs Prowlarr via the generic Servarr installer.
set -euo pipefail
cd "$(dirname "$0")"
exec sudo ./install-servarr.sh prowlarr
