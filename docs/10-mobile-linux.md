# 10. Mobile Linux (phones & tablets)

This chapter adapts the stack to a **phone or tablet** that runs Linux, so the device can host
and serve the media center itself. It is a different environment from a server: it runs on a
battery, heats up, sleeps, and often sits on a mobile network. The services stay the same. The
host setup changes.

> Read [chapter 0 (requirements)](00-requirements.md) and the [Docker chapter](09-docker-compose.md)
> for background. Everything here assumes you have already read the bare-metal chapters.

---

## Is a phone a good server?

**Yes for a personal, single-household library. Not for anything you need 24/7 with no supervision.**

| Concern | Why it matters | What to do |
|---|---|---|
| **Power / battery** | Runs off a battery that is constantly charging. Some devices swell or degrade when kept at 100%. | Keep it plugged in on a stable charger. Set a charge limit if the device supports it (see [preflight](#preflight-check)). |
| **Heat** | Sustained load (downloads, unpacking, library scans) throttles the CPU. | Use **Direct Play** only (no transcoding). Keep the device ventilated, not in a case, not on a bed. |
| **Sleep** | Phones suspend aggressively, which stops every service. | Mask suspend/hibernate targets and disable screen-off power management. |
| **Storage** | Internal storage is small and often slow. A microSD card is slower still and wears out. | Put `/srv/data` on a **USB-C SSD** (see [storage](#storage-on-an-external-ssd)). Keep staging and library on **one** disk so hardlinks work. |
| **Network** | Mobile data is usually NAT'd and changes IP. | Use **Wi-Fi** at home. [Tailscale](01-tailscale.md) still works through NAT, so your other devices reach the box with the same tailnet IP. |
| **Portability** | It can be lost, stolen, or left on a train. | Use full-disk encryption, a screen lock, and a Tailscale device key with an expiry. Revoke the device in the Tailscale admin console if it goes missing. |

**Best candidates:** a **tablet** (bigger battery, more RAM, easier to keep flat and cool) or an
**older phone** you do not mind dedicating. Pick **arm64 (aarch64)** hardware with **at least
4 GB RAM**. Sonarr, Radarr, Prowlarr, Jellyfin, and Transmission together use noticeably more
memory than a bare Transmission box.

---

## Choose your path

| Path | Device | What it is | Good for | Caveats |
|---|---|---|---|---|
| **A. Linux-native host** | Phone or tablet with a real Linux distro (e.g. postmarketOS, or a Debian-based mobile image) | A normal Linux userland with systemd or OpenRC, close to chapters 1–8 | The most "server-like" option | Device support varies widely; kernels are often vendor-patched; check your device's maturity first |
| **B. Android + Termux** | Any Android phone/tablet | Termux runs a terminal; `proot-distro` gives you a Debian/Ubuntu userland inside it | Easiest to get running on a device you already have | Android kills background apps aggressively; you must opt out of battery optimization; not a true Linux host |
| **C. Client only** | Any phone or tablet | Install the Tailscale app and open Jellyfin, Sonarr, Radarr from the browser or Jellyfin app | Most people | Not a server at all. Run the stack on a separate box or on Path A/B above |

> **Ubuntu Touch and similar container-confined phone OSes are not recommended as hosts.** Their
> apps run in sandboxes that limit background services, so the daemons here will not stay up
> reliably. Use them as clients (Path C) instead.

The rest of this chapter covers host preparation that applies to all paths, then path-specific
notes.

---

## Preflight check

Run the included check script on the device **before** you install anything. It reports
architecture, RAM, storage layout, battery, temperature, and whether suspend is still enabled:

```bash
bash scripts/check-mobile-host.sh
```

Each line is `PASS`, `WARN`, or `FAIL`. A `FAIL` means the device will not run the stack as
written. A `WARN` means it will run but you should fix it first. The script only reads system
state. It changes nothing.

---

## Architecture and software

- **Use arm64 (`aarch64`).** Every component in this guide has arm64 builds. Do not plan around
  32-bit ARM (`armhf`) without checking each app's release page first.
- **Check the packages for your distro before you start.** Examples from our research at the time
  of writing:
  - Tailscale has an **aarch64** package in Alpine's community repository (`apk add tailscale`).
  - Jellyfin publishes **official arm64 builds** (`.deb` and tarball). An Alpine aarch64
    `jellyfin` package was **not confirmed** — check `apk search jellyfin` on your release, or use
    the official tarball.
  - Sonarr publishes **arm64** packages on its download page. Radarr's and Prowlarr's 32-bit ARM
    status was **not confirmed** — use arm64.
  - Transmission is packaged on most distros. Confirm with your package manager.

  Re-check these against your device's release. Package availability changes between releases.

- **Install the `*arr` apps from their official tarballs** (chapter 4 and 5). Their .NET runtime
  is bundled, so you do not install .NET separately.

---

## Storage on an external SSD

A phone's internal storage is too small for a library and a microSD card is too slow and fragile.
Use a **USB-C SSD** (or a USB-C to SATA/NVMe enclosure), powered by its own supply when it is large.

1. Plug in the drive and find it:
   ```bash
   lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
   ```
2. Format it **once** as ext4 (this erases it, so triple-check the device name):
   ```bash
   sudo mkfs.ext4 -L mediadata /dev/sdX1
   ```
3. Mount it by **UUID** with `nofail`, so the device still boots if the drive is unplugged:
   ```bash
   sudo blkid /dev/sdX1                       # note the UUID
   echo 'UUID=<UUID>  /srv/data  ext4  defaults,nofail,x-systemd.device-timeout=10s  0  2' \
     | sudo tee -a /etc/fstab
   sudo mkdir -p /srv/data && sudo mount -a
   ```
4. Create the single data tree (one filesystem = instant hardlinks, as in the
   [docker chapter](09-docker-compose.md#the-one-rule-that-makes-hardlinks-work)):
   ```bash
   sudo install -d -o "$(id -u)" -g "$(id -g)" /srv/data/torrents /srv/data/media/tv /srv/data/media/movies
   ```

Then point the paths in chapters 2–6 at `/srv/data/...` instead of `/srv/...`. Or symlink
`/srv` to `/srv/data` if you prefer to keep the original paths.

> **Filesystem and drive choice.** ext4 works well. Avoid exFAT for the library because it does not
> support hardlinks or Unix permissions. Use **one** drive for staging and library. If you split
> them, imports become full copies, which costs space and time.

---

## Keep it awake and stop it sleeping

On a systemd-based distro:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Also set the device's **screen-off / display power** to never, and turn off automatic suspend
in the desktop shell. On a phone with no desktop shell, use the device's settings for
"stay awake while charging" or equivalent. Some vendor kernels also have a `wakelock` or power
profile. Check your device's documentation.

On **OpenRC** (Alpine/postmarketOS), disable any suspend-on-idle service your image enables and
keep the device on AC power. There is no single command that covers every image, so verify with
`bash scripts/check-mobile-host.sh` after you change it.

**Charge limit (if supported):** many phones expose a charge threshold in sysfs. The preflight
script reports it. Where it exists, set it to around 80% to reduce battery wear:

```bash
echo 80 | sudo tee /sys/class/power_supply/<battery>/charge_control_end_threshold
```

Make it persistent with a small systemd unit or an OpenRC script, because sysfs settings do not
survive a reboot.

---

## Services: what changes from the desktop guide

Keep the same services and ports, with these adjustments:

### Transmission (chapter 2)

- Keep the **download-only** settings from [`config-examples/transmission-settings.json`](../config-examples/transmission-settings.json).
- **Lower concurrency** to keep heat and I/O down. Set `download-queue-size` to `2` and
  `queue-stalled-enabled` to `true` so stalled torrents do not hold slots.
- Keep `rpc-whitelist` limited to your Tailscale range (`100.*`), as in the main guide.

### Jellyfin (chapter 3)

- **Turn off transcoding for remote users, and rely on Direct Play.** Transcoding is the single
  biggest cause of heat and throttling on a small device. In **Dashboard → Playback**, disable
  hardware and software transcoding for remote clients, or cap the remote bitrate limit below what
  your client can direct-play.
- Limit library scans to scheduled times, not continuous scanning.
- Jellyfin's own memory use is modest. Its library database lives on the external SSD, so keep
  the Jellyfin data directory on `/srv/data` or a path on the same drive.

### Sonarr, Radarr, Prowlarr (chapters 4–5)

- Only the paths change (see [storage](#storage-on-an-external-ssd)).
- Keep **one** RSS sync interval rather than several short ones. Shorter intervals wake the CPU
  more often.

### Homepage (chapter 7) — optional

Homepage is a small Node app, but on a constrained device you can skip it. The phone's browser
bookmarks to each service do the same job. If you do run it, run it on the device with the
Tailscale IP only.

---

## Phone-specific notes

### Path B: Android + Termux

Termux is not a Linux distro, but a Debian or Ubuntu userland runs inside it through `proot-distro`.
The services run inside that userland. The critical part is keeping Android from killing them.

1. Install **Termux** and **Termux:Boot** (F-Droid is the usual source) and **Tailscale** from the
   Play Store or F-Droid.
2. In Android settings, set **Termux**, **Termux:Boot**, and **Tailscale** to **unrestricted**
   battery use (or "Don't optimize"). Without this, Android stops them when the screen turns off.
3. In Termux, hold a wake lock while the services run:
   ```bash
   termux-wake-lock
   ```
4. Install a Debian/Ubuntu userland:
   ```bash
   pkg install proot-distro
   proot-distro install debian
   proot-distro login debian
   ```
5. Inside the Debian userland, follow the arm64 steps above. Start the services in a `tmux` session
   or with a `runit`-style supervisor, since there is no systemd inside `proot`.
6. Use **Termux:Boot** to start the services after a reboot. Put a script in `~/.termux/boot/`.

**Tailscale on Android:** the Tailscale app is the VPN for the whole device, so services inside
Termux should be reachable at the device's `100.x` address. Test this first. Bind the services to
that address, not to `0.0.0.0`. Confirm with `tailscale ip -4` from another device.

> Android will still throttle or kill background work when the device is under memory pressure.
> If a service disappears, check the battery settings from step 2 before you debug anything else.

### Path A: Linux-native phones and tablets

- Expect the vendor kernel to be missing features the stack wants, such as some `cgroup` or
  `overlay` options if you use Docker. This is one reason the bare-metal chapters are a better fit
  than the Docker chapter on these devices.
- Use the distro's own power management where it exists. Mask the suspend targets as above.
- Check the device's wiki for the battery charge limit and for the USB-C port's power and data
  roles, since many phones default to charge-only.

### Path C: Phone as a client

Install the Tailscale app, join the same tailnet, then open:

- Jellyfin: `http://<TAILSCALE_IP>:8096` (or the official Jellyfin app)
- Sonarr / Radarr / Prowlarr / Transmission: their ports on `<TAILSCALE_IP>`
- Homepage (if run): `http://<TAILSCALE_IP>:7575`

This is the simplest option, and it keeps the host where it can run reliably.

---

## Security

The same rule as the main guide applies: **nothing is exposed to the public internet.** Access is
only over Tailscale.

- Enable **full-disk encryption** on the device and the external SSD if the device will be
  carried. Without it, anyone who steals the device or the drive can read the library and
  credentials.
- Set a **Tailscale key expiry** for the server node in the admin console. Revoke it if the
  device is lost.
- Use **strong, unique passwords** for Jellyfin, Sonarr, Radarr, and Prowlarr, and keep the API
  keys out of any file you commit. Use the placeholders from the
  [README](../README.md#conventions--placeholders) in anything shared.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Services stop when the screen turns off | Suspend or battery optimization | Mask the suspend targets; set Termux/Tailscale to unrestricted battery use |
| Playback stutters on remote devices | Transcoding under thermal throttling | Turn off remote transcoding; use Direct Play; lower the remote bitrate limit |
| Device gets hot and slow | Too many simultaneous torrents, or scans running | Lower `download-queue-size`; schedule library scans |
| Boot hangs or drops to emergency shell | External SSD missing and no `nofail` on its fstab entry | Add `nofail` and `x-systemd.device-timeout=10s`, as in [storage](#storage-on-an-external-ssd) |
| Imports copy files instead of hardlinking | Staging and library on different filesystems | Put both on the same drive under `/srv/data` |
| Out-of-memory kills (`dmesg`) | Too many `*arr` apps or Jellyfin on a 4 GB device | Run fewer apps at once; skip Homepage; add zram swap if your kernel supports it |
| Tailscale connects, but services are unreachable | Service bound to the wrong interface, or Termux isolation | Bind to the `100.x` address; confirm `tailscale ip -4` |

For anything else, see the general [gotchas](08-gotchas.md).
