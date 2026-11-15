# 8. Gotchas & troubleshooting

A consolidated list of the non-obvious things that bite. Most are documented in-place in the
chapter they belong to; this is the quick reference.

## Transmission

- **AppArmor blocks `/srv` (Ubuntu).** Writes fail `Permission denied (13)` and the denied
  write can **SEGV-crash** the daemon. Fix: add your download path to
  `/etc/apparmor.d/local/transmission` and `apparmor_parser -r`. Every new download path needs
  its own line. → [chapter 2](02-transmission.md)
- **IPv4-only bind.** `transmission-remote localhost` may resolve to `::1` and fail. Use
  `127.0.0.1`.
- **Config rewritten on exit.** Always `systemctl stop transmission-daemon` before editing
  `settings.json`, or your edits are clobbered.
- **"inactive" for an uninstalled unit.** `systemctl status` on an unknown unit can look like a
  stopped service. Confirm it's actually installed with `dpkg -l | grep transmission`.

## Permissions / hardlinks

- **Run Sonarr/Radarr/Prowlarr as `debian-transmission`.** Different users + default
  `fs.protected_hardlinks=1` → imports fall back to slow copies or fail. One owner for
  downloads *and* library fixes it.
- **Keep staging and library on one filesystem** or you get copies, not hardlinks (slow, double
  space).
- **Category subfolders must exist.** Sonarr labels its grabs `tv-sonarr` and Radarr uses
  `radarr`, so Transmission downloads into `/srv/torrents/tv-sonarr` and `/srv/torrents/radarr`.
  If those don't exist you get a health warning ("… cannot see this directory"). Create them:
  ```bash
  sudo install -d -o debian-transmission -g debian-transmission \
    /srv/torrents/tv-sonarr /srv/torrents/radarr
  ```

## Jellyfin

- **Content type is permanent.** A mixed "Movies and Shows" library reads each season folder as
  a movie → identical junk titles. Delete + recreate as the correct type. → [chapter 3](03-jellyfin.md)
- **Auth header, not query.** `?api_key=` → `401`; `/emby` prefix → `404`. Use
  `Authorization: MediaBrowser Token="<key>"`. This breaks Homepage's native Jellyfin widget;
  use a `customapi` widget instead. → [chapter 7](07-homepage.md)
- **Naming.** `Series (Year)/Season NN/…` matches cleanly; flat release folders each parse as a
  new series. Let Sonarr/Radarr produce the structure.

## Sonarr / Radarr

- **Multi-season packs** only import S01 via auto-scan; force with `ManualImport` + explicit
  `episodeIds`. → [chapter 4](04-sonarr-radarr.md)
- **Metadata proxy timeouts.** Adding a series/movie fetches from `skyhook.sonarr.tv`; a brief
  upstream slowdown gives a timeout/`500`. Retry — adds are idempotent by TVDB/TMDB id.

## Prowlarr

- **Cloudflare indexers** (1337x, EZTV) need FlareSolverr. The listed public indexers work
  without it.
- **YTS is movies-only** — it won't sync into Sonarr; that's expected.
- **API add** needs `appProfileId: 1` + `enable: true`.

## Discovery / request layer (Jellyseerr)

- **Jellyseerr does not work with Jellyfin 12.x (yet).** Distros like **Ubuntu 26.04 ship
  Jellyfin 12.4**, which dropped the legacy API that Jellyseerr depends on. Symptoms, in order
  as you work around each one:
  - Sign-in fails because Jellyfin 12 **rejects the `X-Emby-Authorization` header** (HTTP 400)
    and accepts only the modern `Authorization: MediaBrowser ...` header. Jellyseerr still sends
    the legacy header.
  - If you proxy/translate that header, login succeeds but you then hit **`NO_ADMIN_USER`** —
    Jellyseerr's admin check reads an **older user-object schema** that Jellyfin 12 changed. A
    header proxy can't fix a response-body schema difference.
  - Both `fallenbagel/jellyseerr:latest` **and** `:develop` fail identically as of late 2026.
- **Options if you want the unified "one search page":**
  1. Wait for Jellyseerr to add Jellyfin 12 support, or
  2. Run the official **Jellyfin 10.10 LTS** (not the distro's 12.x) — the version the whole
     *arr/requester ecosystem supports — then Jellyseerr works fully.
- **Until then, the robust workflow is two tiles:** add titles in **Radarr** (movies) /
  **Sonarr** (TV); watch in **Jellyfin**. No third-party handshake involved, nothing to break.
- **Diagnosing which header your Jellyfin accepts** (useful for any Jellyfin-integration tool):
  ```bash
  # 200 = accepted, 400 = rejected
  curl -s -o /dev/null -w "%{http_code}\n" -X POST http://<host>:8096/Users/AuthenticateByName \
    -H 'Content-Type: application/json' \
    -H 'X-Emby-Authorization: MediaBrowser Client="t", Device="t", DeviceId="t", Version="1"' \
    -d '{"Username":"<user>","Pw":"<pass>"}'
  ```

## Don't grab from Prowlarr's Search tab

Prowlarr's **Search** tab is for *testing indexers only* — it has **no download client** of its
own unless you add one, so clicking "grab" there gives **"torrent downloader not configured."**
Always add titles in **Radarr/Sonarr** (which have the Transmission client wired up); Prowlarr
just feeds indexers to them in the background. (You *can* add a download client to Prowlarr —
Settings → Download Clients — if you want its Search-tab grabs to work, but it's not the normal
flow.)

## Firewall

- Rules are bound to **`tailscale0`**. If a service is unreachable, confirm you're connecting
  over Tailscale (to `<TAILSCALE_IP>`), not the LAN IP, and that `ufw status` shows the rule on
  `tailscale0`.

## Useful checks

```bash
df -h /srv                                   # space before big downloads
systemctl status transmission-daemon jellyfin sonarr radarr prowlarr
journalctl -u sonarr --since "1 hour ago"
sudo docker logs --tail 50 homepage
```
