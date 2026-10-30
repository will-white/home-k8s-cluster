# Media Stack Tuning Checklist

Operational items that live **outside Recyclarr** but shape what actually gets
grabbed and how it lands. Recyclarr handles custom formats and quality profiles;
the items below are configured directly in each app's UI and are not declarative
in this repo.

Work top to bottom — each section is independent and safe to do in isolation.

---

## 1. Prowlarr indexer hygiene

> Why: Sonarr/Radarr break score ties by indexer priority. A "tier 1" private
> tracker release should always beat the same release from a public indexer,
> even when custom-format scores are equal.

**Indexer priorities** — Settings → Indexers → each indexer:
- Private trackers (if any): **priority 25** (highest).
- Curated public (e.g. tracker with good moderation): **priority 30**.
- General-purpose public: **priority 40–50** (default).
- Spam-prone public: **priority 50** (lowest) or disable entirely.

**Sync mode to apps** — Settings → Apps → each app:
- Sync Profile: **Standard** (push categories + URL).
- Sync Level: **Full Sync** — Prowlarr is the source of truth for indexer
  config. Manual edits in Sonarr/Radarr will be overwritten on next sync;
  this is intentional.

**Indexer health** — System → Status:
- Resolve every "Indexer X has stopped working" warning. A failing indexer
  means missed grabs you won't notice until something never lands.
- Set **Test on Save** behavior to enabled.

**Search rate limits**:
- For each indexer with a hard rate limit, set **Query Limit** so RSS sync
  doesn't burn the daily quota in the first hour.

### 1a. Current indexer roster

Track here as you add/remove indexers. Update the priority column once
you've decided based on observed quality.

| Indexer    | Type        | Scope        | Priority | Notes |
|------------|-------------|--------------|----------|-------|
| The Pirate Bay | Public  | General      | 40       | High noise floor; CFs do heavy lifting |
| FunFile    | Semi-priv.  | TV (scene)   | 25       | Older/scene TV strength |
| Nyaa       | Public      | Anime        | 30       | Pair with AnimeTosho if added |
| 1337x      | Public      | General      | 35       | Add — top public after TPB |
| TorrentGalaxy | Public   | General      | 30       | Add — clean release titles |
| EZTV       | Public      | TV only      | 30       | Add — TV-only, well-tagged |

### 1b. Adding a public indexer to Prowlarr (step by step)

The flow is identical for **1337x**, **TorrentGalaxy**, and **EZTV** — just
substitute the indexer name in step 2. Walk through it once with 1337x, then
repeat for the other two.

#### Step 1 — Open Prowlarr's Add Indexer dialog
1. Open Prowlarr in the browser (your usual ingress URL).
2. Left nav → **Indexers**.
3. Top-left → **Add Indexer**.

#### Step 2 — Find and select the indexer
1. In the search box, type the indexer name (`1337x`, `torrentgalaxy`, or
   `eztv`).
2. Click the matching entry. Prowlarr ships definitions for all three —
   you should not need to add a custom YAML.
3. Verify the description says "Public" (no API key required).

#### Step 3 — Configure
For all three indexers, the only fields you need to set are:

| Field                  | Value                                 |
|------------------------|---------------------------------------|
| Name                   | Leave default (e.g. `1337x`)          |
| Enable RSS Sync        | ✅ checked                             |
| Enable Automatic Search| ✅ checked                             |
| Enable Interactive Search | ✅ checked                          |
| Indexer Priority       | See roster table above (35 / 30 / 30) |
| Tags                   | Leave empty for now                   |

For **EZTV specifically**, also:
- Categories: confirm only TV categories are enabled (it has no movie content
  anyway, but Prowlarr will show all categories selected by default).

For **TorrentGalaxy specifically**:
- It has a Cloudflare challenge on some endpoints. If you see "FlareSolverr
  required" warnings later, you'll need to add FlareSolverr (separate app).
  Skip for now — only add it if TGx actually fails health checks.

#### Step 4 — Test
1. Click **Test** at the bottom of the dialog. Wait for the green checkmark.
2. If red, expand the error. Most common: indexer site is down (try in 30
   min) or your egress is blocked from the site (different problem).
3. Click **Save**.

#### Step 5 — Verify sync to Sonarr/Radarr
1. Prowlarr → **Settings → Apps**. You should already have Sonarr and
   Radarr listed.
2. For each, click the wrench/edit icon.
3. Confirm **Sync Level** is **Full Sync** (not "Add Only").
4. Click **Test**, then **Save**. This forces an immediate sync.
5. Open **Sonarr → Settings → Indexers** (and Radarr likewise) — the new
   indexer should appear within 30s, named with the `(Prowlarr)` suffix.

#### Step 6 — Sanity-check a search
1. Sonarr → **Activity → Queue → Manual Search** for any monitored episode.
2. Filter the results by indexer column. Confirm the new indexer is
   returning results and that result titles look like clean scene/p2p
   release names (e.g. `Show.S01E01.1080p.WEB-DL.DDP5.1.x264-NTb`), not
   random spam.
3. If results look good, you're done. If they're junk, drop the priority
   to 50 in Prowlarr and revisit.

#### Step 7 — Update this doc
- Update the priority column in the roster table above with the value you
  actually settled on.
- Commit the change. (Indexer config itself is **not** declarative in this
  repo — Prowlarr stores it in its PVC. The roster table here is the only
  record-of-truth for what's wired up.)

### 1c. Adding AnimeTosho (anime fallback for Nyaa)

Same steps as 1b, but at step 2 search for `AnimeTosho`. Set:
- Indexer Priority: **35** (lower than Nyaa so Nyaa wins ties).
- Categories: confirm only anime categories enabled.
- After save, sanity-check it shows results for an anime you know exists
  on both Nyaa and AnimeTosho.

Add to the roster table.

### 1d. Skipping YTS / TheRARBG / LimeTorrents

These are intentionally NOT in the recommended set:
- **YTS** — produces small low-bitrate rips that your `LQ` CF blocks
  anyway. Adding the indexer just wastes search calls.
- **TheRARBG** — quality has been mixed since RARBG's death; revisit in 6
  months.
- **LimeTorrents** — covered by 1337x + TGx; minimal additional value.

If you want to add any of these later, follow the same step 1–7 flow but
set priority to **50** so they only contribute when nothing else has the
release.

---

## 2. qBittorrent / download client tuning

> Why: post-grab behavior decides whether a torrent seeds, gets removed, or
> wedges queue. Wrong settings here can get you banned from private trackers.

**Categories**: `sonarr`, `radarr` (set by each *arr's download client) and
`prowlarr` (manual grabs from Prowlarr). All save under `/Downloads/<category>`.

**Seeding policy — Cleanuparr seeding rules** (owner decision 2026-10-29;
replaces "seed indefinitely" from 2026-10-25, which had grown to ~3,500
torrents and ~7 TB of downloads no longer in the library):
- qBittorrent's own Seeding Limits stay **off**. Removal is done by Cleanuparr's
  Download Cleaner (hourly; Cleanuparr UI → Download Cleaner), which can match
  per tracker. A removal deletes the `Downloads` copy only; library hardlinks
  survive.
- Rules, first match wins. All of them skip a torrent that uploaded or
  downloaded within the last **3 days**:

  | # | Matches | Removed when |
  |---|---|---|
  | 1 | FunFile (`funfile.org`) | ratio ≥ 1 or 30 days seeded |
  | 2 | Other private trackers | ratio ≥ 1 or 30 days |
  | 3 | Public sonarr/radarr tagged `cleanuparr-unlinked` (no library hardlink left: upgraded or deleted) | 7 days |
  | 4 | Public sonarr/radarr still in the library | ratio ≥ 2 or 30 days, but never while the swarm has < 3 seeders |
  | 5 | Public `prowlarr` (manual grabs) | ratio ≥ 2 or 30 days (import within 30 days) |

- Unlinked tagging covers `sonarr` and `radarr` only; `prowlarr` grabs may never
  be imported and would look unlinked. Cleanuparr mounts `/Downloads` read-only
  for this check.
- FunFile's exact hit-and-run rule was not verified (owner recollection: 1:1 or
  30 days). Check it if FunFile ever warns.
- Queueing: **300** active uploads / **350** active torrents (was 50/100,
  which left ~3,000 completed torrents queued at ratio 0).
- Manual imports from the `prowlarr` category are **copies**, not hardlinks,
  on purpose: library files stay independent of the torrents, so torrents can
  be pruned later (e.g. once a show is replaced by a season pack).

**Connectability**: PIA port forwarding via gluetun (CA Vancouver; PIA US
regions have no PF). gluetun pushes the forwarded port into qBittorrent and
binds it to `tun0` — see [helmrelease.yaml](qbittorrent/app/helmrelease.yaml).

**Upload limit**: managed by the `upload-throttle` sidecar, not the WebUI. It
polls Plex every 20s; while any **remote** (WAN) stream is active it holds the
global upload limit at `UP_LIMIT_STREAMING` (200 KiB/s), otherwise
`UP_LIMIT_IDLE` (1 MiB/s). Router QoS can't do this: all torrent traffic is
inside one VPN tunnel. Tune the two env values in the HelmRelease; a value set
in the WebUI is overwritten within 20s.

**Resume data and checking** (set 2026-10-29, WebUI → Advanced):
- Save resume data interval: **5 min** (was 60). Pieces downloaded since the last
  save are forgotten on any restart or OOM kill, so a recheck was needed after
  the 2026-10-29 `/incomplete` migration.
- Hashing threads: **2** (was 1).
- WebUI CSRF protection: **on**. API clients (gluetun's port push, the
  exporter, Homepage) send no Origin/Referer and are unaffected.

**Alerts**: [prometheusrule.yaml](qbittorrent/app/prometheusrule.yaml) covers
the WebUI being down, not connectable (forwarded port lost), torrents in
`error`/`missingFiles`, and moves stuck for 6 h.

**Stalled downloads**: Sonarr/Radarr never give up on a dead torrent by
themselves — see Cleanuparr (queue cleaner) for strike-based removal +
blocklist + re-search.

---

## 3. Sonarr / Radarr release profiles (preferred words)

> Why: complements custom formats. Cheaper to maintain, applies before CFs,
> good for tracker-specific or recurring-bug overrides.

**Sonarr** — Settings → Profiles → Release Profiles → Add:
- Tags: leave empty for global, or scope to specific series via tag.
- Must contain: leave empty (use CFs for hard requires).
- Must not contain:
  - Any tracker-specific spam pattern that CFs miss.
  - `\.PROPER\.RERIP\.` (double-fix releases that often regress).
- Preferred words (with score):
  - `REPACK` → **+5**
  - `PROPER` → **+5**
  - (Skip if your CFs already cover these — verify in Sonarr → System →
    Tasks → "Apply Custom Formats to Existing" then sample a few
    releases for double-counted scores.)
- Include Preferred when Renaming: **disabled** (avoids `[REPACK]` in
  filenames).

**Radarr** has the same feature under Settings → Profiles → Release Profiles.
Apply the same logic.

**Validation step**: after adding a release profile, manually search for one
known-bad and one known-good release in the Activity → Search tab and confirm
the displayed score matches expectations.

---

## 4. Recyclarr sync schedule

> Current: cron `0 0 * * *` (daily at midnight) — see
> [helmrelease.yaml](recyclarr/app/helmrelease.yaml).

Trade-offs:
- **Daily** (current): minimum noise, but config changes in this repo can
  take up to 24h to land. Fine for steady-state.
- **Every 6h** (`0 */6 * * *`): config changes land same-day. Slightly more
  log noise. Recommended once you stop tweaking CFs frequently.
- **On-demand only**: change the CronJob to suspended and trigger via
  `kubectl create job --from=cronjob/recyclarr recyclarr-manual-$(date +%s) -n media`.
  Reasonable if you've stabilized and don't want surprise upstream TRaSH
  changes.

To change: edit `cronjob.schedule` in
[helmrelease.yaml](recyclarr/app/helmrelease.yaml) and let Flux reconcile.

**Verify sync is healthy**:
```sh
kubectl -n media get jobs -l app.kubernetes.io/name=recyclarr --sort-by=.status.startTime
kubectl -n media logs -l app.kubernetes.io/name=recyclarr --tail=200
```

---

## 5. Bazarr score thresholds

> Why: Bazarr's default minimum match score is generous, which lets through
> low-quality auto-translated subs that play but read badly.

Bazarr UI → Settings → Subtitles:
- **Series → Minimum Score**: default `70` → recommend **`80`**.
- **Movies → Minimum Score**: default `80` → recommend **`90`**.
- **Use embedded subtitles**: enabled (skips downloads when the release
  already has decent embeds).
- **Adaptive searching**: enabled — backs off after first successful match
  to reduce provider hammering.

**Provider order** matters — drag in the UI:
1. OpenSubtitles.com (paid VIP if you have it, free otherwise) — highest
   metadata accuracy.
2. Subscene → still the largest free catalog for older content.
3. Addic7ed → community-curated TV, slow but high quality.
4. Anything else as fallback.

**Per-language scoring overrides**: for non-English series where matches
are sparse, drop the threshold to the default to avoid empty results.

---

## 5a. UI-only settings this stack depends on

These are set in the app UIs (or their APIs), not in Git. Re-apply them if an
app's database is ever rebuilt.

| App | Setting | Value | Why |
|---|---|---|---|
| Seerr | Default Sonarr / Radarr profile | **4K** | Covers SDTV → 2160p, so requesters don't need to know what exists |
| Seerr | Sonarr anime profile / series type | **Anime** / `anime` | Anime TV uses the anime CFs and absolute numbering |
| Seerr | Override rule (Settings → Services) | Radarr, keyword `210024` (anime) → profile **Anime** | Radarr has no anime-profile setting in Seerr; without this, anime films land on 4K |
| Sonarr / Radarr | 4K profile qualities | SDTV, DVD, 480p, 720p allowed **below** 1080p/2160p | Pre-HD shows only exist at SD; a 720p/1080p floor leaves them missing forever |
| Sonarr / Radarr | Recycle bin | `/media/.recyclebin`, 7-day cleanup | Upgrades delete the old file; this makes a bad import recoverable |
| Sonarr | Release profile "Block foreign dubs Sonarr cannot parse" | must not contain IndoCaps / Indonesian Dub | Foreign dubs the language parser misses |

Back-catalogue upgrade searches run from Git: the `recyclarr-upgrade-search`
CronJob (Sundays 03:00) searches 20 random cutoff-unmet/missing seasons in
Sonarr and 25 movies in Radarr. Raise `SONARR_MAX_SEASONS` /
`RADARR_MAX_MOVIES` in [helmrelease.yaml](recyclarr/app/helmrelease.yaml) to
cycle faster. Run it now with:
```sh
kubectl -n media create job --from=cronjob/recyclarr-upgrade-search upgrade-search-manual-$(date +%s)
```

---

## 6. Periodic verification

Run after any major change above:

| Check | Command / Location |
|---|---|
| Prowlarr → app sync OK | Prowlarr → System → Tasks → "Application Indexer Sync" recently green |
| Indexer health | Prowlarr → System → Status → no warnings |
| Sonarr/Radarr CF scores match Recyclarr config | App → Settings → Profiles → click each profile → spot-check 3 CFs |
| Recyclarr last sync | `kubectl -n media logs -l app.kubernetes.io/name=recyclarr --tail=50` |
| Bazarr download success rate | Bazarr → System → Logs filter `subtitle` |
| qBittorrent ratio compliance | qBittorrent UI → sort by ratio, anything <1.0 on private should still be seeding |

---

## Out of scope for this doc

- Custom format additions / quality profile structure → see
  [recyclarr/app/resources/recyclarr.yml](recyclarr/app/resources/recyclarr.yml).
- Storage / PVC / Volsync → [volsync-system/CLAUDE.md](../volsync-system/CLAUDE.md).
- New media app onboarding → [CLAUDE.md](./CLAUDE.md) in this folder and
  [docs/runbooks/add-an-app.md](../../../docs/runbooks/add-an-app.md).
