# Radarr

Movie automation. Mostly mirrors Sonarr, with one key difference: Radarr **kept** a native Language dropdown on the Quality Profile, so no Custom Format is needed for language filtering.

## Create the `Best available` Quality Profile

1. **Settings → Profiles → Quality Profiles → +** (the first/top `+` tile — there's also a second `+` for Release Profiles below, don't click that one)
2. **Name:** `Best available`
3. **Upgrades Allowed:** ✅
4. Tick:
   - Remux-2160p
   - Bluray-2160p
   - WEB 2160p
   - HDTV-2160p
   - Remux-1080p
   - Bluray-1080p
   - WEB 1080p
   - HDTV-1080p
   - Bluray-720p
   - WEB 720p
   - HDTV-720p
5. **Upgrade Until:** auto-picks the top ticked quality (`Remux-2160p`). Confirm.
6. **Language:** `Original` (built-in filter — defaults to "Original" meaning whatever the movie's original audio language is. Done.)
7. Leave Custom Format scores at default (0)
8. **Save**

No Custom Format needed for language. Radarr v5+ handles it natively.

## Bulk-assign profile to existing movies

1. Top toolbar → **Edit Movies** (enters Mass Editor mode)
2. Top toolbar → **Select All**
3. Bottom toolbar → **Edit**
4. **Quality Profile:** `Best available`
5. Leave other dropdowns at "No Change"
6. **Apply Changes**

All existing movies get re-evaluated against the new profile. Cutoff-unmet items will be searched.

## Trigger upgrade search on existing movies

After changing profile, Radarr won't auto-search the whole library. To find upgrades for movies now under the new cutoff:

- **Wanted → Cutoff Unmet → Search All**

Or wait for the next RSS sync (~15min cycle).
