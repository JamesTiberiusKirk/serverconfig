# Server Config Docs

Runbooks and reference for the parts of this stack that aren't captured in compose files — settings that live inside each app's UI/database and have to be re-done on a fresh install.

## Where to start

Re-setup order (each depends on the previous):

1. `runbooks/01-prowlarr.md` — connect Prowlarr to Sonarr/Radarr, add Zilean
2. `runbooks/02-sonarr.md` — quality profile + language CF
3. `runbooks/03-radarr.md` — quality profile + native language filter
4. `runbooks/04-bazarr.md` — language profile + OpenSubtitles
5. `runbooks/05-rdt-client.md` — barely anything to do, mostly cleanup tips
6. `runbooks/06-jellyfin-notes.md` — what to know, what can't be done

## Reference

- `reference/realdebrid-pipeline.md` — how the pieces fit together
- `reference/quality-profile-strategy.md` — why we use `Best available`

## Why these docs exist

The compose files describe **services**. They don't describe:
- Which API keys live where (and which way they get out of sync)
- What quality profile rules to tick
- Which Custom Format to create and what score
- How to wire a non-built-in indexer

These notes capture the UI work from the session that built it, so a re-setup doesn't repeat the same debugging.
