# Self-Hosted Media Center (Transmission → Sonarr/Radarr → Jellyfin)

A complete, reproducible guide for a **fully-automated, download-only** media center on a
single Linux box, reachable privately over [Tailscale](https://tailscale.com), with **one
dashboard** for everything.

```
                         ┌──────────────────────────────────────────┐
                         │                Homepage                   │
                         │        single dashboard  (:7575)          │
                         └──────────────────────────────────────────┘
                                          ▲ widgets
          add a show/movie ──►  ┌─────────┴──────────┐
                                │ Sonarr (TV)  :8989 │
                                │ Radarr (film):7878 │
                                └─────────┬──────────┘
         search indexers  ◄──── Prowlarr :9696       │ grab
                                          │           ▼
                                ┌─────────┴──────────────────────┐
                                │ Transmission :9091 (download-  │
                                │ only, no seeding) → /srv/torrents
                                └─────────┬──────────────────────┘
                                          │ hardlink + rename
                                          ▼
                                /srv/media/{tv,movies}
                                          │
                                          ▼
                                ┌──────────────────┐
                                │ Jellyfin  :8096  │  serves to any device
                                └──────────────────┘
```

**What you get**

- Add a title in Sonarr/Radarr → it searches your indexers (via Prowlarr) → grabs the best
  release in Transmission → hardlinks + renames it into a clean library → Jellyfin serves it.
  No manual steps after the initial add.
- **Download-only**: every torrent stops the instant it completes — no seeding or sharing.
- **Private by default**: all web UIs are exposed *only* on the Tailscale interface, never to
  the public internet or even the LAN.
- **One pane of glass**: a Homepage dashboard with live widgets for every service plus host
  CPU/mem/disk.

> ⚠️ **Downloading copyrighted material may be illegal where you live.** This guide is for
> managing media you are legally entitled to (your own rips, public-domain works, Linux ISOs,
> etc.). You are responsible for how you use it.

---

## Contents

1. [Requirements](docs/00-requirements.md)
2. [Tailscale (private networking)](docs/01-tailscale.md)
3. [Transmission (download-only)](docs/02-transmission.md)
4. [Jellyfin (media server)](docs/03-jellyfin.md)
5. [Sonarr & Radarr (automation)](docs/04-sonarr-radarr.md)
6. [Prowlarr (indexers)](docs/05-prowlarr.md)
7. [Auto-import timer](docs/06-autoimport.md)
8. [Homepage (dashboard)](docs/07-homepage.md)
9. [Gotchas & troubleshooting](docs/08-gotchas.md)

Example config files live in [`config-examples/`](config-examples/) and helper scripts in
[`scripts/`](scripts/). **Every secret is a placeholder** — see below.

---

## Conventions / placeholders

Replace these everywhere they appear. **Never commit real values to a public repo.**

| Placeholder          | Meaning                                                  |
|----------------------|----------------------------------------------------------|
| `<TAILSCALE_IP>`     | Your server's Tailscale IP (e.g. `100.x.y.z`)            |
| `<LAN_SUBNET>`       | Your LAN subnet, e.g. `192.168.1.0/24`                   |
| `<DL_USER>`          | Transmission RPC username                                |
| `<DL_PASS>`          | Transmission RPC password                                |
| `<SONARR_API_KEY>`   | From Sonarr → Settings → General                         |
| `<RADARR_API_KEY>`   | From Radarr → Settings → General                         |
| `<PROWLARR_API_KEY>` | From Prowlarr → Settings → General                       |
| `<JELLYFIN_API_KEY>` | From Jellyfin → Dashboard → API Keys                     |

Paths used throughout:

- `/srv/torrents` — download staging (put this on your **fastest** disk; e.g. NVMe)
- `/srv/media/tv`, `/srv/media/movies` — organized libraries Jellyfin reads

All services run as the **`debian-transmission`** user so that downloads and the organized
library share one owner — this is what makes instant **hardlinks** (not slow copies) work and
avoids `fs.protected_hardlinks` denials.

## Why this design

- **One disk for staging + library** → Sonarr/Radarr hardlink instead of copy: imports are
  instant and use no extra space until you move files off to cold storage.
- **One service user** → no permission juggling between the downloader and the organizers.
- **Tailscale-only firewall** → your media center is on your private tailnet; nothing is
  reachable from the public internet, so you don't run a reverse proxy or open router ports.

## License

[MIT](LICENSE) — the documentation and scripts. Trademarks and the software it configures
(Jellyfin, Sonarr, etc.) belong to their respective projects.
