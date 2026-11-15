# 9. Docker Compose variant (great for SBCs / RK3588)

If you'd rather not install five services by hand — especially on an **arm64 SBC** (Raspberry
Pi, Radxa Rock 5B / RK3588, Orange Pi 5, etc.) — the [`docker-compose/`](../docker-compose/)
folder brings the whole stack up with one command. Every image is **multi-arch
(amd64 + arm64)**, so it runs unchanged on these boards.

## Why Compose on an SBC

- One `docker compose up -d` instead of five installs; trivial to move between boards.
- `linuxserver.io` images bundle the right arm64 binaries and a shared `PUID/PGID` model that
  keeps hardlinks working.
- Easy to pin/upgrade versions and to blow away + recreate without touching your data.

## Prerequisites

```bash
# Docker + compose plugin
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # re-login after this
# Tailscale on the HOST (not in a container)
curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up
```

## Bring it up

```bash
cd docker-compose
cp .env.example .env
nano .env                     # set PUID/PGID, TZ, DATA_ROOT, DL_PASS, BIND_IP

# create the single data tree (one filesystem = instant hardlinks)
sudo install -d -o "$(id -u)" -g "$(id -g)" \
  /srv/data/torrents /srv/data/media/tv /srv/data/media/movies

# (optional but recommended) seed download-only Transmission settings before first start
mkdir -p config/transmission
cp ../config-examples/transmission-settings.json config/transmission/settings.json

docker compose up -d
docker compose ps
```

Want the Cloudflare solver (for 1337x/EZTV)? Start with the extras profile:

```bash
docker compose --profile extras up -d
```

## The one rule that makes hardlinks work

All the `*arr` services and Transmission share **one `PUID/PGID`** and mount the **same
`DATA_ROOT`**, so `/data/torrents` (staging) and `/data/media` (library) are on one filesystem
with one owner. That's what lets Sonarr/Radarr **hardlink** imports instead of copying — instant
and space-free. Don't split them onto different mounts.

> **Container paths vs. the bare-metal guide:** inside the containers the tree is `/data/...`
> (not `/srv/...`). So in Sonarr set the root folder to **`/data/media/tv`**, in Radarr
> **`/data/media/movies`**, and point the Transmission download client at host **`transmission`**
> port **9091** (service name resolves on the compose network). Everything else in
> [chapter 4](04-sonarr-radarr.md) and [chapter 5](05-prowlarr.md) applies.

## Privacy / firewall

By default `BIND_IP=127.0.0.1`, so nothing is exposed off-box. Two good options:

- Set `BIND_IP` to your **Tailscale IP** (`100.x.y.z`) to bind the UIs straight to the tailnet.
- Or `BIND_IP=0.0.0.0` **plus** the `tailscale0`-only UFW rules from
  [chapter 1](01-tailscale.md) so the firewall gates access.

Then set `HOMEPAGE_ALLOWED_HOSTS` in `.env` to include `100.x.y.z:7575`.

## RK3588 / Rockchip hardware transcoding (optional)

Software transcode works out of the box on any arm64 board. For **hardware** decode/encode on
RK3588 (Mali/RKMPP/RKVDEC):

1. Confirm a render node on the host: `ls -l /dev/dri` (you want `renderD128`).
2. Uncomment the `devices:` block under `jellyfin` in
   [`compose.yaml`](../docker-compose/compose.yaml). On **mainline** kernels `/dev/dri` is
   usually enough (VA-API). On **vendor BSP** kernels you often also need:
   ```yaml
   devices:
     - /dev/dri:/dev/dri
     - /dev/mpp_service:/dev/mpp_service
     - /dev/rga:/dev/rga
     - /dev/dma_heap:/dev/dma_heap
   ```
3. In Jellyfin → **Dashboard → Playback**, enable **VA-API** (or use an RKMPP-enabled Jellyfin
   image if your board needs the Rockchip MPP path).

Hardware transcode support on RK3588 varies by kernel/BSP — if it won't initialize, fall back to
software transcode (leave the devices block commented). It won't block the rest of the stack.

## Updating

```bash
docker compose pull
docker compose up -d
```

Pinned tags in `compose.yaml` keep upgrades deliberate; bump them when you want a newer release.
