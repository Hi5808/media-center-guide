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

## Clean naming

For reliable matching, files must look like:

```
/srv/media/tv/The Series Name (2017)/Season 01/The Series Name - S01E01 - Title.mkv
```

i.e. **one series folder with season subfolders** — *not* the flat
`ShowName Season 1 S01 (release junk)` folders torrents arrive in (each of those parses as a
separate series). **You don't do this by hand — Sonarr/Radarr produce this structure for you**
(next chapter).
