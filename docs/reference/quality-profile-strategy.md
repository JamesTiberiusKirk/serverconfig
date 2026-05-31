# Quality Profile Strategy

Why we built `Best available` instead of using Sonarr/Radarr's defaults.

## The default profiles are traps

`Ultra-HD` (default):
- Only ticks the three 2160p qualities (HDTV-2160p, WEB 2160p, Bluray-2160p)
- Cutoff is 2160p
- **Sonarr will wait forever for a 4K release.** Never grabs 1080p as an interim. For shows where 4K never appears or RD doesn't have it cached, you get nothing.

`HD-1080p` (default):
- Only ticks 1080p qualities
- Cutoff is 1080p
- Caps you at 1080p — even if a 4K version becomes available later, it won't upgrade.

Neither matches "give me whatever's best now, upgrade later when better arrives."

## What `Best available` does instead

- **Allows everything** from 720p HDTV up to 2160p Bluray Remux
- **Cutoff at the top** (Bluray-2160p Remux or just WEB 2160p if you want to skip 50–100GB remuxes)
- Sonarr/Radarr grab whatever quality is available **right now**, then re-evaluate on every RSS sync (~15 min). If a higher-tier release lands, they grab it and the old file is replaced atomically.

## Behavior

| Situation | Result |
|---|---|
| Only 1080p available, 4K never appears | Grabs 1080p, holds forever |
| 1080p available now, 4K appears next week | Grabs 1080p now, swaps to 4K when it lands |
| 4K available immediately | Grabs 4K, done |
| Old SD-only show (DS9 etc) | Won't grab — use the `Any` profile for those |

The `Any` profile still exists as a fallback for SD-only shows. Assign per-series as needed.

## Cutoff choice: Remux vs WEB

- **Bluray-2160p Remux** as cutoff: maximum quality, but file sizes 50–100 GB per episode/movie. Storage burner.
- **WEB 2160p** as cutoff: 15–30 GB per episode/movie, virtually indistinguishable on most TVs unless you're using a calibrated reference monitor.

Default chosen: **Remux-2160p**. Drop to **WEB 2160p** if storage is tight.

## Language filtering

Different between Sonarr and Radarr because of how the apps evolved:

- **Sonarr v4**: removed the per-series Language dropdown. Use a Custom Format with a Language condition (`Original` + `Except Language` ticked) at score `-10000`. See `runbooks/02-sonarr.md`.
- **Radarr v5+**: kept the native Language dropdown on the Quality Profile. Just set `Original` and the filter applies. No CF needed. See `runbooks/03-radarr.md`.

Both approaches achieve the same thing: reject foreign-language dubs (Italian, German, etc.) when the show is originally English.

## Custom Formats: when to bother

Beyond the language CF, **leave Custom Format scores at 0** unless you specifically want to bias toward:
- A specific streaming source (e.g. AMZN over NF for bitrate)
- HDR vs SDR variants
- A specific release group's quality reputation
- Avoiding x265 for client compatibility

TRaSH Guides has copy-paste presets for each of these. The configarr container auto-applies the TRaSH profile templates (`sonarr-v4-custom-formats-web-1080p`, `radarr-custom-formats-hd-bluray-web`) — those are SEPARATE named profiles, they won't touch `Best available`.
