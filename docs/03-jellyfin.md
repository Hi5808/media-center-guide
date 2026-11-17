# 3. Jellyfin — media server

## Install (official repo)

```bash
curl -fsSL https://repo.jellyfin.org/install-debuntu.sh | sudo bash
sudo systemctl enable --now jellyfin
```

Jellyfin listens on `0.0.0.0:8096`; the Tailscale-only UFW rule from chapter 1 keeps it
private.

## First-run wizard

Open `http://<TAILSCALE_IP>:8096` and create your **admin account** (you own this password —
keep it safe). When it asks for libraries, you can skip and add them precisely below.

## Library folders

```bash
sudo install -d -o debian-transmission -g debian-transmission /srv/media/tv /srv/media/movies
```

The `jellyfin` user reads these via "other" permissions, so keep directories `755` and files
`644` (Sonarr/Radarr produce that by default).

## Add libraries with the RIGHT content type

**Critical:** a library's content type **cannot be changed after creation**. If you let the
wizard make a mixed "Movies and Shows" library, every *season folder* gets read as a separate
movie with identical, ugly titles. Create them explicitly typed:

- **Shows** → content type **TV Shows** → folder `/srv/media/tv`
- **Movies** → content type **Movies** → folder `/srv/media/movies`

Do this in **Dashboard → Libraries → Add Media Library**. Turn on **real-time monitoring** so
new files appear automatically.

> Have a second location (e.g. cold storage you move files to later)? Add it as an *additional
> folder* on the same typed library, or as a second **TV Shows** library pointing at that path.

### If you already made a mixed library (fix)

You must delete and recreate it. Via the API:

```bash
# delete
curl -X DELETE "http://<TAILSCALE_IP>:8096/Library/VirtualFolders?name=Shows" \
  -H 'Authorization: MediaBrowser Token="<JELLYFIN_API_KEY>"'
# recreate as tvshows
curl -X POST "http://<TAILSCALE_IP>:8096/Library/VirtualFolders?name=Shows&collectionType=tvshows&paths=/srv/media/tv&refreshLibrary=true" \
  -H 'Authorization: MediaBrowser Token="<JELLYFIN_API_KEY>"'
```

## API key (for the dashboard later)

**Dashboard → API Keys → +** creates `<JELLYFIN_API_KEY>`.

> **Auth gotcha:** recent Jellyfin builds **reject** the `?api_key=...` query-string form
> (`401`) and dropped the old `/emby` path prefix (`404`). Use the header form:
> `Authorization: MediaBrowser Token="<JELLYFIN_API_KEY>"`. This bites the Homepage widget —
> see [chapter 7](07-homepage.md).

## Optional: one-click sign-in on a tailnet-only box

Jellyfin is a **player**: it reads `/srv/media` and nothing else. It cannot search indexers or
download anything, and no plugin adds that — searching and grabbing live in Sonarr/Radarr, with
[Seerr](08-gotchas.md#discovery--request-layer-seerr-formerly-jellyseerr) on top if you want one
search box instead of two tiles.

Unlike Sonarr/Radarr/Prowlarr, Jellyfin also has **no switch to turn authentication off** — it always
checks its own user database, and there is no `External`/reverse-proxy mode to hand that job to
the network. So on a box where the tailnet is already the security boundary
([chapter 1](01-tailscale.md)), Jellyfin stays the one service that still asks.

The nearest thing to removing that prompt is giving your everyday user an **empty password**.
The login screen then lists the non-hidden users as tiles, and clicking yours signs you straight
in — no typing, and no re-typing when a client's token expires.

**Dashboard → Users → `<your user>` → Password**: clear both password fields and save. Then, on
each client, tick **Remember me** at sign-in so the token survives restarts.

Worth knowing before you do it:

- **This is a real reduction in security, not a cosmetic one.** Anyone who can reach port 8096
  becomes you — full library access, and server settings too if that user is an admin. It is
  only defensible while 8096 is `tailscale0`-only; re-check with `sudo ufw status verbose`
  (and see the stray-LAN-rule note in [chapter 8](08-gotchas.md)).
- **Keep a password on the admin account** and use a separate, non-admin user for watching.
  That way a blank password can't reconfigure the server, delete libraries, or mint API keys.
- **Don't do it for a user you expose by any other route** — a reverse proxy, a port forward, or
  a shared tailnet ACL.
- **Quick Connect is the gentler alternative** (Dashboard → General → Quick Connect): you
  approve a short code from an already-signed-in session instead of typing a password on a TV or
  console. Logins stay authenticated, they just stop being tedious where typing is painful.

To undo it, set a password again on the same screen; existing sessions keep working until they
expire.

## Clean naming

For reliable matching, files must look like:

```
/srv/media/tv/The Series Name (2017)/Season 01/The Series Name - S01E01 - Title.mkv
```

i.e. **one series folder with season subfolders** — *not* the flat
`ShowName Season 1 S01 (release junk)` folders torrents arrive in (each of those parses as a
separate series). **You don't do this by hand — Sonarr/Radarr produce this structure for you**
(next chapter).
