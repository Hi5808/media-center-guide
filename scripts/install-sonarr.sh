#!/usr/bin/env bash
# Thin wrapper — installs Sonarr via the generic Servarr installer.
set -euo pipefail
cd "$(dirname "$0")"
exec sudo ./install-servarr.sh sonarr
