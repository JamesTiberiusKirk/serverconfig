# Prowlarr

Prowlarr is the indexer aggregator. It syncs indexers into Sonarr/Radarr over their APIs.

## Critical: API keys for Sonarr/Radarr Apps

Most common failure mode. Prowlarr stores Sonarr/Radarr API keys in its **Apps** config. If those Sonarr/Radarr keys are ever rotated, **Prowlarr's stored copy goes stale** and indexer sync silently fails (in the Prowlarr logs you'll see `401 Unauthorized` against `http://sonarr:8989/api/v3/indexer/schema`).

**Re-setup:**

1. Get current API keys from Sonarr (Settings → General) and Radarr (Settings → General).
2. Prowlarr → **Settings → Apps** → click **Sonarr** → paste current key into `API Key` → **Test** (must go green) → **Save**.
3. Same for Radarr.

**Symptom of stale keys:** indexer count in Sonarr/Radarr is fewer than in Prowlarr; new indexers added in Prowlarr never appear in Sonarr/Radarr.

## Adding Zilean as an indexer

Zilean isn't in Prowlarr's built-in indexer list (as of 2.3.5.x) — add it as a Generic Torznab:

1. Prowlarr → **Indexers → Add Indexer** → search for "zilean"
2. If it doesn't appear, click **Generic Torznab** instead.
3. Configure:
   - **URL:** `http://zilean:8181/torznab`
   - **API Key:** leave empty (Zilean is unauthenticated within the docker network)
   - **Seed Ratio:** leave empty
   - **VIP Expiration:** leave empty
4. **Test** → **Save**.

Zilean exposes Movies (`2000`) and TV (`5000`) categories, which match Sonarr/Radarr's sync category lists. No category config needed on the indexer.

## Forcing a sync

After adding an indexer, Prowlarr's auto-sync may not run immediately. Force it:

Prowlarr → **Indexers** page → top toolbar → **Sync App Indexers**.

After ~10 seconds, check Sonarr → **Settings → Indexers** to confirm the indexer appears with the `(Prowlarr)` suffix.

## Why Zilean matters

Generic torrent indexers (1337x, LimeTorrents, TPB) return random hashes. RealDebrid rejects most of them with "Infringing file". Zilean returns only hashes **already cached on RD** — so reject rate drops to near zero. See `../reference/realdebrid-pipeline.md`.
