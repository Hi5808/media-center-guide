# 7. Homepage — single dashboard

[Homepage](https://gethomepage.dev) gives you **one page** with live widgets for every service
plus host CPU/mem/disk. Runs in Docker.

## Install Docker

```bash
sudo apt install -y docker.io
sudo systemctl enable --now docker
```

## Config

Put the three YAML files from this repo in `/opt/homepage/config/`:

- [`config-examples/homepage-settings.yaml`](../config-examples/homepage-settings.yaml) → `settings.yaml`
- [`config-examples/homepage-services.yaml`](../config-examples/homepage-services.yaml) → `services.yaml`
- [`config-examples/homepage-widgets.yaml`](../config-examples/homepage-widgets.yaml) → `widgets.yaml`

```bash
sudo mkdir -p /opt/homepage/config
sudo cp config-examples/homepage-settings.yaml /opt/homepage/config/settings.yaml
sudo cp config-examples/homepage-services.yaml /opt/homepage/config/services.yaml
sudo cp config-examples/homepage-widgets.yaml  /opt/homepage/config/widgets.yaml
# insert your IP + API keys
sudo -e /opt/homepage/config/services.yaml
```

## Run (host network, port 7575)

Port **7575** avoids common clashes (e.g. 3000 = Gitea, 8096 = Jellyfin). `--network host`
lets the widgets reach services on `localhost`.

```bash
sudo docker run -d --name homepage --restart unless-stopped \
  --network host \
  -e PORT=7575 \
  -e HOMEPAGE_ALLOWED_HOSTS="<TAILSCALE_IP>:7575,localhost:7575,127.0.0.1:7575" \
  -v /opt/homepage/config:/app/config \
  -v /srv:/srv:ro \
  ghcr.io/gethomepage/homepage:latest
```

Open **`http://<TAILSCALE_IP>:7575`**. Edit a YAML and `sudo docker restart homepage` (it also
hot-reloads).

## Jellyfin widget gotcha

Homepage's built-in `type: jellyfin` widget calls `/emby/*` with `?api_key=` query auth — but
recent Jellyfin **dropped `/emby`** (`404`) and **rejects query api_key** (`401`). So it errors.

**Fix:** use a `type: customapi` widget hitting `/Items/Counts` with **header** auth. Already
done in the example `services.yaml`:

```yaml
- Jellyfin:
    icon: jellyfin.png
    href: http://<TAILSCALE_IP>:8096
    widget:
      type: customapi
      url: http://localhost:8096/Items/Counts
      method: GET
      headers:
        Authorization: MediaBrowser Token="<JELLYFIN_API_KEY>"
      mappings:
        - field: SeriesCount;  label: Shows
        - field: MovieCount;   label: Movies
        - field: EpisodeCount; label: Episodes
```

This shows library counts instead of now-playing, and doesn't 404/401. The Sonarr, Radarr,
Prowlarr and Transmission widgets use Homepage's native types and work as-is with their API
keys.
