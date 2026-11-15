# 2. Transmission — download-only client

## Install

```bash
sudo apt update
sudo apt install -y transmission-daemon
```

This creates the **`debian-transmission`** system user used by every service in this guide.

## Staging directory

```bash
sudo install -d -o debian-transmission -g debian-transmission /srv/torrents
sudo install -d -o debian-transmission -g debian-transmission /srv/torrents/.incomplete
```

## Configure (download-only, no seeding)

The daemon **rewrites its config on exit**, so you must stop it before editing:

```bash
sudo systemctl stop transmission-daemon
sudoedit /etc/transmission-daemon/settings.json
```

Key settings (full example: [`config-examples/transmission-settings.json`](../config-examples/transmission-settings.json)):

| Setting                      | Value              | Why                                         |
|------------------------------|--------------------|---------------------------------------------|
| `download-dir`               | `/srv/torrents`    | staging on the fast disk                    |
| `incomplete-dir`             | `/srv/torrents/.incomplete` | partial files                      |
| `incomplete-dir-enabled`     | `true`             |                                             |
| `speed-limit-up`             | `0`                | **no upload**                               |
| `speed-limit-up-enabled`     | `true`             |                                             |
| `ratio-limit`                | `0`                | stop at ratio 0                             |
| `ratio-limit-enabled`        | `true`             | **stop seeding the instant it completes**   |
| `idle-seeding-limit`         | `1`                | belt-and-suspenders idle stop               |
| `idle-seeding-limit-enabled` | `true`             |                                             |
| `rpc-authentication-required`| `true`             |                                             |
| `rpc-username`               | `<DL_USER>`        |                                             |
| `rpc-password`               | `<DL_PASS>`        | typed plain; daemon hashes it on next start |
| `rpc-whitelist`              | `127.0.0.1,<LAN_SUBNET-as-glob>` | e.g. `127.0.0.1,192.168.1.*` |
| `rpc-bind-address`           | `0.0.0.0`          | binds IPv4                                  |

Start it again:

```bash
sudo systemctl start transmission-daemon
sudo systemctl enable transmission-daemon
```

## Survive crashes

```bash
sudo mkdir -p /etc/systemd/system/transmission-daemon.service.d
printf '[Service]\nRestart=on-failure\n' | \
  sudo tee /etc/systemd/system/transmission-daemon.service.d/restart.conf
sudo systemctl daemon-reload
```

## AppArmor (Ubuntu) — the big gotcha

On Ubuntu, AppArmor confines `transmission-daemon` to a **path whitelist** that does **not**
include `/srv`. Writing there fails with `Permission denied (13)` **and the denied write can
SEGV-crash the daemon**. Allow your download path:

```bash
sudo tee /etc/apparmor.d/local/transmission >/dev/null <<'EOF'
owner /srv/torrents/ rw,
owner /srv/torrents/** rwk,
EOF
sudo apparmor_parser -r /etc/apparmor.d/transmission
```

> Any **new** download path you add later needs its own line here.

## CLI note

The daemon binds **IPv4 only**, so `localhost` (which may resolve to `::1`) can fail to
connect. Always use `127.0.0.1`:

```bash
transmission-remote 127.0.0.1 -n <DL_USER>:<DL_PASS> -l
```

## Verify

Open `http://<TAILSCALE_IP>:9091`, log in, add a test magnet (e.g. a Linux ISO), confirm it
downloads to `/srv/torrents` and **stops** at completion.
