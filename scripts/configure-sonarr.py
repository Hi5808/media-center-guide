#!/usr/bin/env python3
"""Configure Sonarr over its v3 API: root folder, Transmission download client,
and show the quality profile id. Idempotent-ish; safe to re-run.

Fill in the placeholders below, then: python3 configure-sonarr.py
The Radarr API has the same shape (swap the port, key, and category ranges).
"""
import json
import urllib.request
import urllib.error

BASE = "http://<TAILSCALE_IP>:8989/api/v3"
KEY = "<SONARR_API_KEY>"
DL_USER = "<DL_USER>"
DL_PASS = "<DL_PASS>"
ROOT = "/srv/media/tv"


def req(method, path, data=None):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(
        BASE + path, data=body, method=method,
        headers={"X-Api-Key": KEY, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(r, timeout=120) as f:
            t = f.read().decode()
            return f.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


# 1. Root folder
print("rootfolder:", req("POST", "/rootfolder", {"path": ROOT})[0])

# 2. Download client: Transmission
dc = {
    "enable": True, "protocol": "torrent", "priority": 1,
    "name": "Transmission", "implementation": "Transmission",
    "configContract": "TransmissionSettings",
    "fields": [
        {"name": "host", "value": "127.0.0.1"},
        {"name": "port", "value": 9091},
        {"name": "urlBase", "value": "/transmission/"},
        {"name": "username", "value": DL_USER},
        {"name": "password", "value": DL_PASS},
        {"name": "useSsl", "value": False},
    ],
}
print("downloadclient:", req("POST", "/downloadclient?forceSave=true", dc)[0])

# 3. Quality profile id (use the first one, usually "Any")
_, profs = req("GET", "/qualityprofile")
print("qualityProfileId:", profs[0]["id"], profs[0]["name"])
