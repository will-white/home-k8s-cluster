#!/usr/bin/env bash
# Weekly back-catalogue upgrade search for Sonarr and Radarr.
#
# Sonarr/Radarr only upgrade from RSS (new uploads). Old batch releases never
# reappear in RSS, so a file stays at whatever was grabbed first unless
# something searches for it. This picks a random sample of "cutoff unmet" and
# "missing" items each run and asks the apps to search them; the apps' own
# profiles and custom formats decide whether anything is grabbed.
#
# Sonarr is searched per season (SeasonSearch) so anime batches and season
# packs are found, not just single episodes. Caps keep indexer load and
# surprise download volume bounded; a random sample rotates coverage.
set -euo pipefail

SONARR_URL=${SONARR_URL:-http://sonarr.media.svc.cluster.local}
RADARR_URL=${RADARR_URL:-http://radarr.media.svc.cluster.local}
SONARR_MAX_SEASONS=${SONARR_MAX_SEASONS:-20}
RADARR_MAX_MOVIES=${RADARR_MAX_MOVIES:-25}

api() { curl -fsS -m 120 -H "X-Api-Key: $1" -H "Content-Type: application/json" "${@:2}"; }

# Sonarr: unique (series, season) pairs from cutoff-unmet + missing, monitored only.
seasons=$(
  for w in cutoff missing; do
    api "$SONARR_API_KEY" "$SONARR_URL/api/v3/wanted/$w?pageSize=5000&monitored=true" \
      | jq -r '.records[] | select(.seasonNumber > 0) | "\(.seriesId) \(.seasonNumber)"'
  done | sort -u | shuf | head -n "$SONARR_MAX_SEASONS"
)
n=0
while read -r series season; do
  [ -z "$series" ] && continue
  api "$SONARR_API_KEY" -X POST "$SONARR_URL/api/v3/command" \
    -d "{\"name\":\"SeasonSearch\",\"seriesId\":$series,\"seasonNumber\":$season}" >/dev/null
  n=$((n + 1))
done <<< "$seasons"
echo "sonarr: queued $n season searches"

# Radarr: one MoviesSearch command for a random sample of cutoff-unmet + missing movies.
movies=$(
  for w in cutoff missing; do
    api "$RADARR_API_KEY" "$RADARR_URL/api/v3/wanted/$w?pageSize=5000&monitored=true" \
      | jq -r '.records[].id'
  done | sort -u | shuf | head -n "$RADARR_MAX_MOVIES" | jq -s -c .
)
if [ "$movies" != "[]" ]; then
  api "$RADARR_API_KEY" -X POST "$RADARR_URL/api/v3/command" \
    -d "{\"name\":\"MoviesSearch\",\"movieIds\":$movies}" >/dev/null
fi
echo "radarr: queued search for $(jq length <<< "$movies") movies"
