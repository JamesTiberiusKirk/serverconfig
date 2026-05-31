# Bazarr

Subtitle automation. Fresh installs have no language, no profile, no providers — all three need setup before anything works.

## Step 1: Enable a Language

1. **Settings → Languages**
2. **Languages Filter** (multi-select at top): click → type "Eng" → select **English** from dropdown. Pill appears.
3. **Save** (top of page)

Until at least one language is enabled, the "Add New Profile" button doesn't appear.

## Step 2: Create a Languages Profile

1. **Settings → Languages** → scroll to **Languages Profile** section
2. Click **Add New Profile**
3. **Name:** `English`
4. **Add Language** → row appears with `English`, `Normal or hearing-impaired`, `Always`
5. Leave **Must contain** and **Must not contain** empty
6. **Save** the profile

## Step 3: Set defaults for new shows/movies

Still in **Settings → Languages**, scroll to **Default Language Profiles For Newly Added Shows**:

1. Toggle **Series** ON → pick `English` profile
2. Toggle **Movies** ON → pick `English` profile
3. **Save**

## Step 4: Set up OpenSubtitles.com provider

OpenSubtitles.com requires:
- A free user account
- A registered API consumer (for dev mode quota of 100/day)

### Create OpenSubtitles account + consumer

1. Sign up at https://www.opensubtitles.com (free, takes a minute)
2. Once logged in, visit https://www.opensubtitles.com/en/consumers
3. **NEW CONSUMER**
4. **Name:** `bazarrhomelab` (alphanumeric only — no hyphens/underscores)
5. Leave **Allow anonymous downloads** ✅
6. Tick **Under dev** ✅ (raises quota from 5/day to 100/day for unauthenticated use)
7. **Save**
8. Copy the generated API key from the consumer row

### Wire into Bazarr

1. **Settings → Providers → +** (in the Enabled Providers section)
2. **Provider:** OpenSubtitles.com
3. **Username:** your OS account username
4. **Password:** your OS account password
5. **Use Hash:** ON (default — matches by file hash, most accurate)
6. AI/machine-translated toggles: leave OFF (low quality)
7. **Enable**
8. **Save** (top of page)

Note: Bazarr bundles its own OS API consumer key — you don't paste the consumer key from step 4 into Bazarr. Step 4 mainly exists to lift your account's daily quota.

## Step 5: Bulk-assign profile to existing series

1. **Series → Mass Edit**
2. Tick header checkbox to select all
3. **Change Profile** dropdown → `English`
4. **Save**

## Step 6: Bulk-assign profile to existing movies

Same as above but in **Movies → Mass Edit**.

## What to expect after setup

- **Wanted** count balloons immediately (Bazarr identified every existing media file without subs)
- Bazarr works through the backlog respecting OpenSubtitles' 100/day quota — full catalog can take ~10 days
- Once caught up, ongoing fetches are ~a few per day for new grabs only

## "System 5" badge

Almost always 5 dismissable **Announcements** about deprecated providers (OpenSubtitles.org shutting down, Animetosho, etc.), not actual errors. Visit **System → Announcements** and dismiss to clear the badge.
