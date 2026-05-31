# Sonarr

TV automation. Assumes Prowlarr is wired up first (see `01-prowlarr.md`).

## Create the `Best available` Quality Profile

Sonarr's built-in profiles either don't include 4K (`HD-1080p`) or *only* include 4K with no fallback (`Ultra-HD` — Sonarr waits forever for 4K that never appears).

`Best available` allows everything HD up through 4K Bluray Remux, with cutoff at the top:

1. **Settings → Profiles → Quality Profiles → +**
2. **Name:** `Best available`
3. **Upgrades Allowed:** ✅
4. Tick (top→bottom in the list):
   - Bluray-2160p Remux
   - Bluray-2160p
   - WEB 2160p (WEBDL/WEBRip)
   - HDTV-2160p
   - Bluray-1080p Remux
   - Bluray-1080p
   - WEB 1080p
   - Bluray-720p
   - WEB 720p
   - HDTV-1080p
   - HDTV-720p
5. Leave **Raw-HD, Bluray-576p, Bluray-480p, DVD, WEB 480p, SDTV** unticked.
6. **Upgrade Until:** `Bluray-2160p Remux` (or `WEB 2160p` if you want to skip 50–100GB remuxes)
7. **Save**

See `../reference/quality-profile-strategy.md` for the reasoning.

## Create the `Not English` (Not Original Language) Custom Format

Sonarr v4 removed the per-series Language dropdown. Foreign-language releases (Italian dubs etc.) sneak through unless filtered via Custom Format.

1. **Settings → Custom Formats → +** (scroll to bottom of CF grid to find the `+` tile inside the scrollable section)
2. **Name:** `Not English` (or `Language: Not English`)
3. Leave **Include in renaming format** unticked
4. **Conditions → +** → pick **Language**
5. In the Add Condition – Language dialog:
   - **Name:** `Not Original Language`
   - **Language:** `Original` (this makes it adapt per series — English shows want English, anime wants Japanese)
   - **Except Language:** ✅ (matches when audio is NOT the selected language)
   - **Negate:** ❌ unticked
   - **Required:** ❌ unticked (irrelevant for single-condition CF)
6. **Save** the condition → **Save** the CF

## Apply the CF to the profile

1. **Settings → Profiles → Quality Profiles → Best available**
2. Scroll to Custom Formats list
3. Find `Not English` → set score to **`-10000`**
4. **Save**

This makes any release with non-original-language audio score so low Sonarr rejects it outright.

## Assign profile to new series

When adding a series: pick `Best available` in the Quality Profile dropdown. Also tick **Start search for missing episodes** and **Start search for cutoff unmet episodes** to grab everything immediately.

## Assign profile to existing series

No bulk-edit tool in Sonarr's UI. Either:
- Edit each series one at a time (Series → click series → Edit), or
- Use the API: `PUT /api/v3/series` with updated profile ID, see Sonarr's Swagger docs.
