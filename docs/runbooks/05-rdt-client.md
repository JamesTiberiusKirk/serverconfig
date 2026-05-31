# rdt-client (RealDebrid Client)

Acts as the "download client" Sonarr/Radarr hand torrents to. It then asks RealDebrid to fetch + cache them, and rdt-client downloads from RD to local disk.

## Setup

Compose already has the right env (PUID/PGID, volumes for `/data/db` and `/data/downloads`). First-run UI walks you through:
- RealDebrid API token (from https://real-debrid.com/apitoken)
- Download paths
- Local user/pass for the rdt-client web UI

That's it for setup. rdt-client doesn't need wiring into Prowlarr/Zilean — Sonarr/Radarr talk to it directly.

## Sonarr/Radarr → rdt-client wiring

In Sonarr (and Radarr) → **Settings → Download Clients**:
- **qBittorrent** (rdt-client emulates the qBittorrent API)
- **Host:** `rdt-client`
- **Port:** `6500`
- **Username/Password:** rdt-client's local creds
- **Category:** `tv-sonarr` (Sonarr) / `radarr` (Radarr)
- **Test → Save**

These are usually configured by `media-bootstrap` on first deploy.

## Queue cleanup (after RD reject pile-up)

If the rdt-client queue has hundreds of "Could not add to provider: Infringing file" entries (typically from generic torrent indexers before Zilean was added):

1. Open rdt-client web UI
2. Tick header checkbox to select all visible torrents
3. Bottom toolbar → **Delete Selected**
4. In the confirmation dialog, tick **Select All** (delete from client + provider + local files)
5. **Delete selected**

Sonarr's queue is a *mirror* of rdt-client's queue — Sonarr items that point at deleted rdt torrents will clear automatically within seconds. Don't try to bulk-delete via Sonarr's API; it doesn't work because the items aren't really Sonarr-owned.

## Disabling the built-in login (optional)

rdt-client has its own user/password login that sits *behind* Authelia, giving you double-auth. If the route is already gated by Authelia (it is, via `authelia@file` middleware on the Traefik label), you can drop rdt's internal login:

- rdt-client → **Settings → General → Authentication Type → None** → Save

Then only Authelia gates access — single sign-on flow.

## RDT-client does not support OIDC

Verified against the source: no `AddOpenIdConnect` anywhere. Username/password only. Authelia integration is at the proxy layer, not native.
