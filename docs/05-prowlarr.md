# 5. Prowlarr — indexer manager

Prowlarr manages your torrent **indexers** in one place and pushes them to Sonarr and Radarr
automatically, so you configure search sites once.

## Install

Same pattern as Sonarr/Radarr — official tarball, run as `debian-transmission`:

- [`scripts/install-prowlarr.sh`](../scripts/install-prowlarr.sh)

```bash
sudo systemctl enable --now prowlarr
```

UI: `http://<TAILSCALE_IP>:9696`. API key (`<PROWLARR_API_KEY>`) under **Settings → General**.

## Wire Prowlarr → Sonarr and Radarr

**Settings → Apps → + Sonarr** (and again **+ Radarr**):

| Field               | Sonarr                     | Radarr                     |
|---------------------|----------------------------|----------------------------|
| Prowlarr Server     | `http://127.0.0.1:9696`    | `http://127.0.0.1:9696`    |
| *Arr* Server        | `http://127.0.0.1:8989`    | `http://127.0.0.1:7878`    |
| API Key             | `<SONARR_API_KEY>`         | `<RADARR_API_KEY>`         |
| Sync Categories     | 5000–5050 (TV)             | 2000–2090 (Movies)         |

Prowlarr now pushes every indexer you add to the right app. Force a sync anytime:

```bash
curl -X POST "http://<TAILSCALE_IP>:9696/api/v1/command" \
  -H "X-Api-Key: <PROWLARR_API_KEY>" -H "Content-Type: application/json" \
  -d '{"name":"ApplicationIndexerSync"}'
```

## Add indexers

**Indexers → Add Indexer**. Public indexers that work without extra tooling:

- **The Pirate Bay** (TV + movies)
- **YTS** (movies only — won't sync into Sonarr)
- **LimeTorrents**
- **Nyaa.si** (anime)
- **Knaben** (aggregator)

> **Cloudflare-blocked** indexers (e.g. **1337x**, **EZTV**) need a
> [FlareSolverr](https://github.com/FlareSolverr/FlareSolverr) proxy — see below. Worth adding:
> they're often far better-seeded than the no-proxy indexers, which matters a lot for obscure
> or older titles where the others only return dead torrents.

### FlareSolverr (unlock 1337x, EZTV, and other Cloudflare indexers)

FlareSolverr solves the Cloudflare challenge so Prowlarr can query those indexers. Run it as a
container:

```bash
docker run -d --name flaresolverr --restart unless-stopped \
  -e LOG_LEVEL=info -e TZ=<your/tz> \
  -p 8191:8191 \
  ghcr.io/flaresolverr/flaresolverr:latest
```

Then wire it into Prowlarr:

1. **Settings → Indexer Proxies → + → FlareSolverr.** Host `http://localhost:8191` (or
   `http://127.0.0.1:8191`). Give it a **tag**, e.g. `flaresolverr`. Save.
2. **Add the indexer** (1337x, EZTV, …) as usual, and put the **same `flaresolverr` tag** on it.
   Prowlarr routes only tagged indexers through the proxy. **Test** — it should pass now.
3. Prowlarr auto-syncs them to Sonarr/Radarr. Force it if impatient:
   `POST /api/v1/command {"name":"ApplicationIndexerSync"}`.

> FlareSolverr adds latency (each query solves a challenge), so searches through these indexers
> are slower — fine for the much better seeded results. If a search seems to hang, give it
> 20–40 s.
>
> **Payoff:** on a poorly-seeded title where the no-proxy indexers returned only dead torrents,
> adding EZTV/1337x can jump a search from ~45 results to ~100 with live 720p copies (21+
> seeders), turning a stuck download into a working one.

### API shape (if scripting)

Adding an indexer over the API needs `appProfileId: 1` and `enable: true` on the schema object,
`POST /api/v1/indexer?forceSave=true`.

## Verify end-to-end

In Sonarr, add a show with *Search for missing episodes* on. Within a minute you should see
grabs appear in **Activity → Queue**, downloading in Transmission, then importing to
`/srv/media/tv`. Check:

```bash
# queue
curl -s "http://<TAILSCALE_IP>:8989/api/v3/queue?pageSize=50" -H "X-Api-Key: <SONARR_API_KEY>"
# history (grabbed/imported events)
curl -s "http://<TAILSCALE_IP>:8989/api/v3/history/series?seriesId=<ID>" -H "X-Api-Key: <SONARR_API_KEY>"
```

**Fully-automatic flow is now live:** add in Sonarr/Radarr → Prowlarr search → Transmission
grab → auto import + rename → Jellyfin.
