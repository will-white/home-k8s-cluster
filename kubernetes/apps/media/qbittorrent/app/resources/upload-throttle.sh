#!/usr/bin/env bash
# Plex- and gaming-aware upload limit for qBittorrent.
#
# The router shapes the uplink with FQ-CoDel, but a saturated uplink still adds
# latency, and all torrent traffic is one VPN flow the router cannot tell apart.
# So this sidecar lowers qBittorrent's global upload limit while the uplink is
# needed for something latency-sensitive:
#
#   - Plex: anyone streaming from outside the LAN (Session.location == "wan").
#     LAN streams never touch the uplink and are ignored. If Plex cannot be
#     read, fail safe to the streaming limit.
#   - Gaming: a watched device (GAMING_HOSTS, by MAC) has a real-time UDP flow
#     to the internet above its packets/s threshold (GAMING_PPS, or a per-host
#     "@pps" override for hosts with a busy idle baseline). Read from OPNsense's pfTop
#     (read-only API user qbt-gaming-detector); MACs are mapped to the current
#     IPv4 + IPv6 addresses through the router's ARP/NDP tables, so privacy
#     addresses and DHCP changes are followed. Gaming stays on for GAMING_HOLD
#     seconds after the last hit (loading screens, menus). If OPNsense cannot be
#     read, assume not gaming: a broken key must not throttle forever.
#
# Talks to qBittorrent on localhost (WebUI auth is bypassed for localhost).
set -uo pipefail

PLEX_URL=${PLEX_URL:-http://plex.internal:32400}
QBT_URL=${QBT_URL:-http://localhost:80}
OPNSENSE_URL=${OPNSENSE_URL:-https://opnsense.internal:8443}
OPNSENSE_API_KEY=${OPNSENSE_API_KEY:-}
OPNSENSE_API_SECRET=${OPNSENSE_API_SECRET:-}
UP_LIMIT_IDLE=${UP_LIMIT_IDLE:-1048576}       # bytes/s
UP_LIMIT_STREAMING=${UP_LIMIT_STREAMING:-204800}
UP_LIMIT_GAMING=${UP_LIMIT_GAMING:-204800}
GAMING_HOSTS=${GAMING_HOSTS:-}                # "name=mac[@pps] ..."
GAMING_PPS=${GAMING_PPS:-30}                  # default threshold, packets/s
GAMING_HOLD=${GAMING_HOLD:-180}
# UDP ports that are never gaming: DNS, NTP, QUIC/HTTPS, mDNS, SSDP, and
# Discord voice (server ports 19294-19344). Entries are ports or "lo-hi" ranges.
GAMING_IGNORE_PORTS=${GAMING_IGNORE_PORTS:-53 123 443 5353 1900 19294-19344}
INTERVAL=${INTERVAL:-20}

STATE=/tmp/upload-throttle
mkdir -p "$STATE"
last_gaming=0

opn() {
  curl -fsS -m 10 -k -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" "$@"
}

# Prints "<name> <pps> <threshold> <flow>" for the flow furthest over its
# host's threshold, or nothing. Returns non-zero if OPNsense could not be read.
gaming_flow() {
  local macs now
  macs=$(printf '%s\n' $GAMING_HOSTS | jq -R --argjson def "$GAMING_PPS" '
    split("=") | (.[1] | split("@")) as $m
    | {($m[0] | ascii_downcase): {name: .[0], pps: (($m[1] // "") | tonumber? // $def)}}' | jq -s 'add // {}')
  # Responses go to files and are read with --slurpfile: the pfTop table can
  # exceed the kernel's argv limit ("jq: Argument list too long") via --argjson.
  opn "$OPNSENSE_URL/api/diagnostics/interface/get_arp" > "$STATE/arp.json" || return 1
  opn "$OPNSENSE_URL/api/diagnostics/interface/get_ndp" > "$STATE/ndp.json" || return 1
  opn -H 'Content-Type: application/json' -X POST \
      -d '{"current":1,"rowCount":-1,"searchPhrase":"udp"}' \
      "$OPNSENSE_URL/api/diagnostics/firewall/query_pf_top" > "$STATE/top.json" || return 1
  now=$(date +%s)
  # Current packet counters per flow from a watched host to a public address.
  jq -n --argjson macs "$macs" --slurpfile arp "$STATE/arp.json" \
      --slurpfile ndp "$STATE/ndp.json" --slurpfile top "$STATE/top.json" \
      --arg ignore "$GAMING_IGNORE_PORTS" '
    ([($arp[0] + $ndp[0])[] | select($macs[.mac | ascii_downcase])
      | {key: (.ip | sub("%.*"; "")), value: $macs[.mac | ascii_downcase]}] | from_entries) as $ips
    | ($ignore | split(" ") | map(select(length > 0))) as $ign
    | [$top[0].rows[]
       | select(.proto == "udp" and .dir == "in" and $ips[.src_addr])
       | select(.dst_addr | test("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|f[cd]|fe80)") | not)
       | select((.dst_port | tonumber) as $p
              | $ign | any(if test("^[0-9]+-[0-9]+$")
                            then (split("-") | map(tonumber)) as $r | $p >= $r[0] and $p <= $r[1]
                            else (tonumber? // -1) == $p end) | not)
       | {key: "\(.src_addr):\(.src_port)>\(.dst_addr):\(.dst_port)",
          value: {host: $ips[.src_addr].name, limit: $ips[.src_addr].pps,
                  pkts: (.pkts | tonumber), age: (.age | tonumber)}}]
    | from_entries' > "$STATE/flows.json" || return 1
  # Packets/s since the previous poll; a flow first seen now uses its lifetime average.
  jq -r --slurpfile prev <(cat "$STATE/prev.json" 2>/dev/null || echo '{}') \
      --argjson now "$now" --argjson last "$(cat "$STATE/prev.ts" 2>/dev/null || echo 0)" '
    ($prev[0] // {}) as $p
    | [to_entries[]
       | .value as $f
       | (if $p[.key] and $now > $last and $f.pkts >= $p[.key].pkts
          then ($f.pkts - $p[.key].pkts) / ($now - $last)
          else $f.pkts / ([$f.age, 1] | max) end) as $pps
       | {host: $f.host, pps: $pps, limit: $f.limit, flow: .key}]
    | max_by(.pps / .limit) // empty
    | "\(.host) \(.pps | floor) \(.limit) \(.flow)"' "$STATE/flows.json"
  mv "$STATE/flows.json" "$STATE/prev.json"
  echo "$now" > "$STATE/prev.ts"
}

while true; do
  if wan=$(curl -fsS -m 10 -H "X-Plex-Token: $PLEX_TOKEN" -H "Accept: application/json" \
      "$PLEX_URL/status/sessions" \
      | jq '[.MediaContainer.Metadata[]? | select(.Session.location == "wan")] | length'); then
    if [ "$wan" -gt 0 ]; then target=$UP_LIMIT_STREAMING; why="$wan remote stream(s)"
    else target=$UP_LIMIT_IDLE; why="no remote streams"; fi
  else
    target=$UP_LIMIT_STREAMING; why="plex unreachable"
  fi

  if [ -n "$GAMING_HOSTS" ] && [ -n "$OPNSENSE_API_KEY" ]; then
    if flow=$(gaming_flow); then
      read -r host pps limit conn <<<"$flow"
      if [ -n "$flow" ] && [ "$pps" -ge "$limit" ]; then
        [ $((last_gaming + GAMING_HOLD)) -lt "$(date +%s)" ] && echo "$(date -Is) gaming: $host $pps pkt/s >= $limit ($conn)"
        last_gaming=$(date +%s)
      fi
    else
      echo "$(date -Is) opnsense unreachable; gaming detection skipped this round"
    fi
    if [ $((last_gaming + GAMING_HOLD)) -ge "$(date +%s)" ] && [ "$UP_LIMIT_GAMING" -lt "$target" ]; then
      target=$UP_LIMIT_GAMING; why="gaming"
    fi
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
