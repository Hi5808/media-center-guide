# 6. Auto-import timer (closes the manual-download gap)

Sonarr/Radarr auto-import releases **they grabbed themselves**. But if you *manually* add a
magnet in Transmission for a title that's already in your Sonarr/Radarr library, nothing
automatically pulls it in. A tiny systemd timer closes that gap by nudging both apps to scan
the staging dir every few minutes.

## Install

Copy the script and units from this repo:

- [`scripts/media-autoimport.sh`](../scripts/media-autoimport.sh)
- [`config-examples/media-autoimport.service`](../config-examples/media-autoimport.service)
- [`config-examples/media-autoimport.timer`](../config-examples/media-autoimport.timer)

```bash
sudo install -m 755 scripts/media-autoimport.sh /usr/local/bin/media-autoimport.sh
sudo install -m 644 config-examples/media-autoimport.service /etc/systemd/system/
sudo install -m 644 config-examples/media-autoimport.timer   /etc/systemd/system/
# edit the script to insert your <TAILSCALE_IP> / API keys
sudo sed -i 's/<TAILSCALE_IP>/100.x.y.z/; s/<SONARR_API_KEY>/.../; s/<RADARR_API_KEY>/.../' \
  /usr/local/bin/media-autoimport.sh
sudo systemctl daemon-reload
sudo systemctl enable --now media-autoimport.timer
```

## What it does

Every 5 minutes it POSTs:

- `DownloadedEpisodesScan` to Sonarr on `/srv/torrents`
- `DownloadedMoviesScan` to Radarr on `/srv/torrents`

both with `importMode: Copy` (a hardlink when same-filesystem).

## Limits

- The title **must already be added** in Sonarr/Radarr for the scan to match it. Brand-new
  titles: add them in Sonarr/Radarr first (or just use their built-in search — the normal
  path).
- Multi-season **packs** still hit the folder-name rejection from
  [chapter 4](04-sonarr-radarr.md) and need the `ManualImport` force.

## Check it

```bash
systemctl status media-autoimport.timer
journalctl -u media-autoimport.service --since "1 hour ago"
```
