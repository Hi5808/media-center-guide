# 1. Tailscale — private networking

[Tailscale](https://tailscale.com) puts your server and your other devices on one private
network (a "tailnet") with stable IPs, no port-forwarding, and no exposure to the public
internet. We then lock every service's firewall rule to the Tailscale interface only.

## Install & bring up

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Follow the login URL. Then note your server's tailnet IP:

```bash
tailscale ip -4      # e.g. 100.x.y.z  -> this is <TAILSCALE_IP>
```

Install the Tailscale app on your laptop/phone and log into the same account. You can now reach
the server from anywhere at `<TAILSCALE_IP>`.

## Firewall: tailnet-only

Enable UFW and allow the service ports **only on the `tailscale0` interface**. This is the key
privacy step — the UIs are never reachable from the public internet or even the local LAN.

```bash
sudo ufw allow in on tailscale0 to any port 8096 proto tcp   # Jellyfin
sudo ufw allow in on tailscale0 to any port 8989 proto tcp   # Sonarr
sudo ufw allow in on tailscale0 to any port 7878 proto tcp   # Radarr
sudo ufw allow in on tailscale0 to any port 9696 proto tcp   # Prowlarr
sudo ufw allow in on tailscale0 to any port 7575 proto tcp   # Homepage dashboard
sudo ufw allow in on tailscale0 to any port 5055 proto tcp   # Seerr (optional)
sudo ufw allow in on tailscale0 to any port 9091 proto tcp   # Transmission (optional; see note)
sudo ufw allow OpenSSH
sudo ufw enable
sudo ufw status verbose
```

> **Transmission on the LAN (not recommended):** you *can* reach the Transmission web UI from
> LAN machines by replacing its rule with
> `sudo ufw allow from <LAN_SUBNET> to any port 9091 proto tcp`. Keep it on `tailscale0` like
> the rest unless you specifically need that — Transmission's RPC is often left
> unauthenticated behind the whitelist, so a LAN rule hands every device on your Wi-Fi an open
> download client.

From here on, every UI is at `http://<TAILSCALE_IP>:<port>`.
