# RealDebrid Pipeline

How the pieces fit together when you add a new show/movie.

## The flow

```
User adds series in Sonarr
        │
        ▼
Sonarr asks Prowlarr "find me episodes of X"
        │
        ▼
Prowlarr fans out to all enabled indexers:
   ├─ 1337x, LimeTorrents, TPB, Nyaa.si (generic public torrent trackers)
   └─ Zilean (scrapes DebridMediaManager — only RD-cached hashes)
        │
        ▼
Each indexer returns candidate releases (torrent magnet hashes)
        │
        ▼
Sonarr ranks them by Quality Profile + Custom Format scores
        │
        ▼
Sonarr sends the top-ranked hash to rdt-client (the "download client")
        │
        ▼
rdt-client calls RealDebrid API:
   "please add this magnet"
        │
        ┌─── RD says "OK, cached, here's the download link" ───┐
        │                                                       │
        │   (Zilean-sourced hashes hit this path)               │
        ▼                                                       │
rdt-client downloads the cached file from RD                    │
        │                                                       │
        ▼                                                       │
Files land in /media/tv_shows/...                               │
        │                                                       │
        ▼                                                       │
Sonarr imports + renames + moves to final location              │
        │                                                       │
        ▼                                                       │
Jellyfin picks them up on next library scan                     │
                                                                │
        ┌─── RD says "Infringing file" ─────────────────────────┘
        │
        │   (Most generic-torrent-indexer hashes hit this path)
        ▼
rdt-client marks failed; Sonarr re-searches the next-best release
        │
        ▼
Repeat until something works, or RSS sync gives up
```

## Why Zilean is essential

**Without Zilean:**
- Sonarr picks the highest-quality release from generic indexers
- That release is some random recently-uploaded magnet
- RealDebrid has either never seen it (slow / fails) or flagged it as infringing (rejected immediately)
- Sonarr eventually finds *something* that works, but the success rate is low and the queue piles up with rejects

**With Zilean:**
- Zilean only returns hashes already present in RD's cache (sourced from DebridMediaManager's community-maintained cache index)
- A cached hash means "RD has successfully fetched this file for someone before"
- Reject rate drops near zero — files become available within seconds

That's why the session debug ended with switching to Zilean + cleaning up the rdt-client pile from when the generic indexers were primary.

## Why some "Infringing file" rejects still happen even with Zilean

RD's blocklist is dynamic. A hash that was cached and downloadable yesterday can be DMCA'd today. Zilean's snapshot doesn't reflect this in real-time. Expect occasional rejects — Sonarr will retry with the next release.

## Network topology

All these components live on the `traefik` docker network and reach each other by container name:

- Prowlarr → `http://sonarr:8989`, `http://radarr:7878`, `http://zilean:8181`
- Sonarr/Radarr → `http://prowlarr:9696`, `http://rdt-client:6500`
- Bazarr → `http://sonarr:8989`, `http://radarr:7878`

No call goes through Traefik / Authelia internally — those are user-facing only.

## What does NOT happen

- rdt-client never talks to indexers directly
- Zilean doesn't itself download anything; it's a metadata/search service
- RealDebrid is opaque from the rest — only rdt-client knows the RD API token
