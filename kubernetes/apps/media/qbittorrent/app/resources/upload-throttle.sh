#!/usr/bin/env bash
# Plex-aware upload limit for qBittorrent.
#
# All torrent traffic leaves inside one VPN tunnel, so router QoS cannot tell it
# apart from anything else. Instead, poll Plex: while anyone streams from outside
# the LAN (Session.location == "wan", which uses the home uplink), hold
# qBittorrent's global upload limit low; otherwise allow the idle limit.
# LAN streams never touch the uplink and are ignored. If Plex cannot be read,
# fail safe to the streaming limit.
#
# Talks to qBittorrent on localhost (WebUI auth is bypassed for localhost).
set -uo pipefail

PLEX_URL=${PLEX_URL:-http://plex.internal:32400}
QBT_URL=${QBT_URL:-http://localhost:80}
UP_LIMIT_IDLE=${UP_LIMIT_IDLE:-1048576}       # bytes/s
UP_LIMIT_STREAMING=${UP_LIMIT_STREAMING:-204800}
INTERVAL=${INTERVAL:-20}

while true; do
  if wan=$(curl -fsS -m 10 -H "X-Plex-Token: $PLEX_TOKEN" -H "Accept: application/json" \
      "$PLEX_URL/status/sessions" \
      | jq '[.MediaContainer.Metadata[]? | select(.Session.location == "wan")] | length'); then
    if [ "$wan" -gt 0 ]; then target=$UP_LIMIT_STREAMING; why="$wan remote stream(s)"
    else target=$UP_LIMIT_IDLE; why="no remote streams"; fi
  else
    target=$UP_LIMIT_STREAMING; why="plex unreachable"
  fi
  if current=$(curl -fsS -m 10 "$QBT_URL/api/v2/app/preferences" | jq '.up_limit'); then
    if [ "$current" != "$target" ]; then
      if curl -fsS -m 10 -o /dev/null "$QBT_URL/api/v2/app/setPreferences" \
          --data-urlencode "json={\"up_limit\":$target}"; then
        echo "$(date -Is) up_limit $current -> $target ($why)"
      fi
    fi
  fi
  sleep "$INTERVAL"
done
