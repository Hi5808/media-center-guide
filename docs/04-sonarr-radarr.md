# 4. Sonarr & Radarr — automation (organize + rename)

**Sonarr** (TV) and **Radarr** (movies) are near-identical. They watch for releases, tell
Transmission to grab them, then **hardlink + rename** completed files into your clean
libraries. Install both the same way.

## Install (official tarballs, run as `debian-transmission`)

Running them as the **same user** as the downloads is what makes hardlinks (not copies) work
and avoids `fs.protected_hardlinks` denials.

See the full install + systemd unit scripts:

- [`scripts/install-sonarr.sh`](../scripts/install-sonarr.sh)
- [`scripts/install-radarr.sh`](../scripts/install-radarr.sh)

Each script downloads the official tarball to `/opt/{Sonarr,Radarr}`, puts data in
`/var/lib/{sonarr,radarr}` (owned by `debian-transmission`), and installs a systemd unit with
`Restart=on-failure`. After running:

```bash
sudo systemctl enable --now sonarr radarr
```

- Sonarr UI: `http://<TAILSCALE_IP>:8989`
- Radarr UI: `http://<TAILSCALE_IP>:7878`

Grab each service's **API key** from **Settings → General** (`<SONARR_API_KEY>`,
`<RADARR_API_KEY>`), stored in `/var/lib/{sonarr,radarr}/config.xml`.

## Configure (UI or API)

Either click through the UI (Settings) or use the API. Both approaches set the same three
things:

### 1. Root folder

- Sonarr → `/srv/media/tv`
- Radarr → `/srv/media/movies`

### 2. Download client → Transmission

Settings → Download Clients → **+ Transmission**:

| Field    | Value            |
|----------|------------------|
| Host     | `127.0.0.1`      |
| Port     | `9091`           |
| URL Base | `/transmission/` |
| Username | `<DL_USER>`      |
| Password | `<DL_PASS>`      |
| Use SSL  | off              |

### 3. Quality profile

The default **"Any"** profile is fine to start.

### Scripted alternative

[`scripts/configure-sonarr.py`](../scripts/configure-sonarr.py) does all three over the
Sonarr v3 API (`X-Api-Key` header). Point the `BASE`/`KEY`/`DL_*` variables at your setup
first. The Radarr API is the same shape (categories differ) if you want to adapt it.

## Add a title

In the UI: **Add New**, search, pick the right year, **Add** (optionally tick *Search for
missing episodes* to grab immediately). Sonarr/Radarr will search your indexers (next
chapter), grab in Transmission, and auto-import into the clean library.

> Adding a series triggers a metadata fetch from Sonarr's proxy (`skyhook.sonarr.tv`). If that
> upstream is briefly slow you may see a timeout/`500` — just retry; the add is idempotent by
> TVDB id.

## Gotcha: multi-season "pack" folders

If you *manually* drop a pack like `Show S01-S04 (...)` into staging, Sonarr's
`DownloadedEpisodesScan` infers **one** season from the folder name and rejects the rest
("Episode NxNN was unexpected considering the ... folder name") — only S01 imports. Releases
Sonarr grabs **itself** are named per-episode and don't hit this. To force a stubborn pack:

```bash
# 1. let Sonarr parse each file
GET /api/v3/manualimport?folder=<path>&filterExistingFiles=true
# 2. import with explicit ids per file
POST /api/v3/command
{ "name":"ManualImport",
  "files":[{"path":...,"seriesId":...,"episodeIds":[...],"quality":...,"languages":[...]}],
  "importMode":"Copy" }
```

(`importMode: Copy` becomes a hardlink when source and dest share a filesystem.)

## Optional: skip the login prompts on a tailnet-only box

Sonarr/Radarr/Prowlarr default to `Forms` auth, so every service is a separate sign-in — four
logins to cross one dashboard. If the firewall already limits these ports to `tailscale0`
(chapter 1), the tailnet *is* the authentication boundary and the forms are redundant. Each app
exposes `External`, which hands auth off to the network/reverse proxy in front of it:

```bash
for a in sonarr radarr prowlarr; do
  f=/var/lib/$a/config.xml
  sudo cp "$f" "$f.bak-noauth"      # keep a way back
  sudo sed -i 's#<AuthenticationMethod>.*</AuthenticationMethod>#<AuthenticationMethod>External</AuthenticationMethod>#' "$f"
  sudo systemctl restart $a
done
```

Verify the UI answers directly instead of redirecting to `/login`:

```bash
for p in 8989 7878 9696; do
  curl -s -o /dev/null -w "$p -> %{http_code}\n" -L http://127.0.0.1:$p/
done                                  # expect 200, 200, 200
```

> **Only do this if the ports are genuinely not on the LAN.** Check with
> `sudo ufw status verbose` — if a rule reads `8989 ALLOW IN <LAN_SUBNET>` rather than
> `Anywhere on tailscale0`, anyone on your Wi-Fi gets an unauthenticated Sonarr. Restore a
> login with the `.bak-noauth` copy.

### Don't "fix" this by changing `BindAddress`

It's tempting to narrow `<BindAddress>` from `*` to loopback + `<TAILSCALE_IP>` instead of
using the firewall. The field takes **one** address, not a list — and whichever single value you
pick breaks something: loopback kills tailnet access, and the Tailscale IP kills the
`127.0.0.1` calls that Homepage's widgets and the Sonarr↔Prowlarr/Transmission wiring all use.
Leave `BindAddress` at `*` and let UFW do the filtering.

## Jellyfin is the exception

Jellyfin has no equivalent switch — it always authenticates against its own user database. The
closest you get is clearing a user's password (Dashboard → Users), which turns the login screen
into a one-click avatar pick. That is a real reduction in security for that account, so it's a
deliberate choice, not a default to copy.
