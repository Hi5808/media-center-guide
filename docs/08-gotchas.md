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

## Homepage: Transmission tile shows nothing / errors

- **Use `127.0.0.1`, not `localhost`, in the Transmission widget `url`.** Transmission binds
  **IPv4 only**, but Node (Homepage) resolves `localhost` to `::1` (IPv6) first, so the widget
  silently fails to connect while every other tile works (those services listen on both
  stacks). Same root cause as the `transmission-remote` CLI gotcha above.
- The RPC itself is easy to verify from the host: `transmission-remote 127.0.0.1:9091 -n
  <user>:<pass> -st` should print session stats. If that works but the tile doesn't, it's the
  `localhost`/IPv6 issue, not auth.
- **Clicking the tile 403s (opens the Transmission web UI over Tailscale):** the widget reads
  fine from `127.0.0.1`, but opening the web UI in your browser comes from your **Tailscale IP
  (`100.x`)**, which Transmission's `rpc-whitelist` rejects (`403`). Add the Tailscale CGNAT
  range to the whitelist in `settings.json` (stop the daemon first):
  `"rpc-whitelist": "127.0.0.1,192.168.1.*,100.*"`. UFW still limits the port to `tailscale0`,
  so this stays private. Same applies to Sonarr/Radarr/Prowlarr only if you enabled their
  built-in IP filtering — by default they don't use one.

## Discovery / request layer (Seerr, formerly Jellyseerr)

This is the piece that gives you **one search page** instead of switching between Radarr (movies)
and Sonarr (TV): you search, click request, and Seerr hands it to the right \*arr. Jellyfin itself
can never do this — it has no indexer search and no download client, and no plugin adds them.

- **The project was renamed.** `fallenbagel/jellyseerr` is now **`seerr-team/seerr`** ("Seerr").
  Pull from **`ghcr.io/seerr-team/seerr`** and note the tags carry a `v` prefix
  (`v3.5.2`, not `3.5.2` — the unprefixed form fails with `not found` on pull). The old Docker
  Hub image `fallenbagel/jellyseerr` stops at **2.7.3** and publishes a literal
  `2.7.3-deprecated` tag, so anything still pinned there is on an abandoned image.

- **Seerr 3.5.2 works with Jellyfin 12.4.0.** Verified 2026-11-17: sign-in returns 200, the
  initial admin user is created, and the server is registered. Older Jellyseerr 2.x genuinely
  did not work with Jellyfin 12.x — if you are on 2.x, upgrade rather than downgrading
  Jellyfin. The fix landed in **v3.5.0** (28 Sep 2026) as
  *"(jellyfin-api) Update Authorization headers for Jellyfin (#3502)"*.

### The `NO_ADMIN_USER` trap (it is not about admin permissions)

If you set Seerr up by API rather than the web wizard, **`serverType` is required** in the
sign-in body. Omit it and you get `HTTP 500 {"message":"NO_ADMIN_USER"}` plus this log line:

```
[warn][Auth]: Failed sign-in attempt from user without admin permissions and no admin user exists
```

Both the error code and that message strongly suggest a permissions problem. It isn't one. In
`server/routes/auth.ts` the admin check and the server-type check are separate, and they report
**different** codes — `NOT_ADMIN` vs `NO_ADMIN_USER`:

```ts
if (account.User.Policy.IsAdministrator === false) {
  throw new ApiError(403, ApiErrorCode.NotAdmin);      // real permissions failure
}
if (body.serverType !== MediaServerType.JELLYFIN &&
    body.serverType !== MediaServerType.EMBY) {
  throw new ApiError(500, ApiErrorCode.NoAdminUser);   // just a missing field
}
```

`MediaServerType` is `PLEX = 1, JELLYFIN = 2, EMBY = 3`, so a working setup POST is:

```bash
curl -X POST http://127.0.0.1:5055/api/v1/auth/jellyfin \
  -H 'Content-Type: application/json' \
  -d '{"username":"<JF_ADMIN>","password":"<JF_PASS>","hostname":"127.0.0.1",
       "port":8096,"useSsl":false,"urlBase":"","serverType":2}'
```

> If you hit `NO_ADMIN_USER`, **check your request body before you suspect your Jellyfin user**.
> Confirm the account really is an admin with
> `curl -s $JF/Users -H 'Authorization: MediaBrowser Token="<token>"'` and look for
> `Policy.IsAdministrator: true`. On Jellyfin 12.4 that flag is present and correct in the
> sign-in response, in `/Users` and in `/Users/Me` — so if all three say `true`, the problem is
> on the Seerr request side, not the server.

### Jellyfin auth headers, if you're debugging any integration

Measured on **Jellyfin 12.4.0**, against `/Users/AuthenticateByName`:

| Header form | Result |
|-------------|--------|
| `X-Emby-Authorization: MediaBrowser ...` (legacy) | **400** "Error processing request." |
| `Authorization: MediaBrowser ...` (modern)        | **200** + user object with `Policy` |

```bash
# 200 = accepted, 400 = rejected
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://<host>:8096/Users/AuthenticateByName \
  -H 'Content-Type: application/json' \
  -H 'Authorization: MediaBrowser Client="t", Device="t", DeviceId="t", Version="1"' \
  -d '{"Username":"<user>","Pw":"<pass>"}'
```

Any tool still sending the legacy header will fail at sign-in on 12.x and needs updating.

### Housekeeping

- Seerr **mints a Jellyfin API key** during setup. If you tear a test install down, delete the
  orphaned key in **Jellyfin → Dashboard → API Keys**.
- A container run without a config volume loses its setup on removal — fine for a test, not for
  a real install. See the `seerr` service in
  [`docker-compose/compose.yaml`](../docker-compose/compose.yaml).

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

- **A stray LAN rule is how services quietly become public-ish.** `ufw status verbose` lists
  each rule's source; anything reading `<port> ALLOW IN <LAN_SUBNET>` is reachable by every
  device on your Wi-Fi, which matters a lot once you've turned the \*arr logins off. Drop one
  with:

  ```bash
  sudo ufw delete allow from <LAN_SUBNET> to any port 9091 proto tcp
  ```

  The rule must be deleted in the **same form it was added** — if it was created without
  `proto tcp`, the delete needs to omit it too, or UFW answers `Could not delete non-existent
  rule`. When in doubt, `sudo ufw status numbered` then `sudo ufw delete <n>`.

- **Loopback is never filtered**, so tightening these rules doesn't break service-to-service
  calls. After closing 9091 to the LAN, Transmission's RPC still answers locally — a `409`
  from `curl http://127.0.0.1:9091/transmission/rpc` is the *healthy* response (it means
  "missing session id"), not a failure.

## Useful checks

```bash
df -h /srv                                   # space before big downloads
systemctl status transmission-daemon jellyfin sonarr radarr prowlarr
journalctl -u sonarr --since "1 hour ago"
sudo docker logs --tail 50 homepage
```
