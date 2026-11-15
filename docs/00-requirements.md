# 0. Requirements

## Hardware / OS

- A Linux server that stays on (this guide was built on **Ubuntu 24.04 / 26.04**, `systemd`).
  Any Debian/Ubuntu derivative works; adapt package names for other distros.
- A fast disk for download staging (NVMe recommended) mounted so that `/srv/torrents` and
  `/srv/media` live on the **same filesystem** (required for instant hardlinks).
- Enough space: downloads + the organized copy share space only briefly thanks to hardlinks,
  but plan for your library size.

## Accounts / software

- `sudo` on the server.
- A free [Tailscale](https://tailscale.com) account (for private access from your other
  devices).
- These packages/apps, installed in later chapters:
  - `transmission-daemon` (apt)
  - `jellyfin` (official Jellyfin apt repo)
  - Sonarr, Radarr, Prowlarr (official tarballs / `Servarr`)
  - Docker (for the Homepage dashboard)

## Check disk before you start

```bash
df -h /srv
```

Make sure `/srv` has room and is on the disk you intend. If `/srv` isn't on your fast disk,
either mount the fast disk there or change every `/srv/...` path in this guide to match.

## The service user

Everything runs as **`debian-transmission`** (created automatically by the
`transmission-daemon` package). Install Transmission first so the user exists, then point the
other services at it. This single-owner model is deliberate — see the README's "Why this
design".
