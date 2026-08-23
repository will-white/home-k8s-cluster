#!/bin/bash
# nodes-up.sh — bring a SUBSET of nodes back after scripts/nodes-down.sh
#
# `task talos:cluster-up` is whole-cluster: it waits on ALL nodes being Ready,
# so it cannot be used for a partial return. This does the same work scoped to
# the nodes you name, in the order that actually works.
#
# Usage:  scripts/nodes-up.sh <ip|hostname> [<ip|hostname> ...]
#         task talos:nodes-up NODES="192.168.5.53 192.168.5.54"
#
# Also works after an UNPLANNED node loss — pass the nodes that came back.
# See docs/runbooks/full-cluster-shutdown.md.
#
# Requires: kubectl, jq. KUBECONFIG comes from Task.

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date -u +%T)] $*"; }
hr()  { printf '%.0s─' {1..66}; echo; }

ceph_exec() { kubectl -n rook-ceph exec deploy/rook-ceph-tools -- "$@"; }

[[ $# -gt 0 ]] || die "no nodes given. Usage: $0 <ip|hostname> [...]"
command -v jq >/dev/null || die "jq not found"

NODES=()
ALL_JSON="$(kubectl get nodes -o json)"
for want in "$@"; do
    name="$(jq -r --arg w "$want" '
        .items[] as $n
        | (($n.status.addresses[] | select(.type=="InternalIP") | .address)) as $ip
        | select($n.metadata.name == $w or $ip == $w) | $n.metadata.name' <<<"$ALL_JSON" | head -1)"
    [[ -n "$name" ]] || die "'$want' does not match any node name or InternalIP"
    NODES+=("$name")
done

hr
log "Bringing back: ${NODES[*]}"
hr

# ── 1. Wait for the kubelet ──────────────────────────────────────────────────
log "Waiting for nodes to report Ready (15m timeout)"
for n in "${NODES[@]}"; do
    kubectl wait --for=condition=Ready "node/$n" --timeout=15m
done

# ── 2. Clear the out-of-service taint ────────────────────────────────────────
# Kubernetes NEVER removes this; node-fencer applies it after 3600s unreachable
# and an admin must take it off. The node reports Ready and runs nothing.
log "Clearing out-of-service taint (harmless if it was never applied)"
for n in "${NODES[@]}"; do
    kubectl taint node "$n" node.kubernetes.io/out-of-service- 2>/dev/null || true
done

# ── 3. Uncordon ──────────────────────────────────────────────────────────────
log "Uncordoning"
kubectl uncordon "${NODES[@]}" 2>/dev/null || true

# ── 4. Wait for Ceph to PEER — not for active+clean ──────────────────────────
# norecover/nobackfill are exactly what stops PGs reaching active+clean, so
# waiting for it here never finishes. Peering only needs the OSDs back and
# talking; recovery is what the flags are holding back.
log "Waiting for OSDs to rejoin and PGs to peer (no inactive PGs)"
peered=0
for i in $(seq 1 60); do
    st="$(ceph_exec ceph status 2>/dev/null || true)"
    osdline="$(grep -E '^\s+osd:' <<<"$st" || true)"
    inactive="$(grep -oE '[0-9]+ pgs inactive' <<<"$st" | head -1 || true)"
    printf '  [%02d] %s | inactive: %s\n' "$i" "$(echo "$osdline" | xargs)" "${inactive:-none}"
    if [[ -z "$inactive" ]] && grep -qE 'osd:.*[0-9]+ osds: ([0-9]+) up' <<<"$st"; then
        up="$(grep -oE '[0-9]+ osds: [0-9]+ up' <<<"$st" | grep -oE '[0-9]+ up' | grep -oE '^[0-9]+')"
        tot="$(grep -oE '[0-9]+ osds:' <<<"$st" | grep -oE '^[0-9]+')"
        [[ "$up" == "$tot" ]] && { peered=1; log "all $tot OSDs up, no inactive PGs"; break; }
    fi
    sleep 20
done
[[ "$peered" == "1" ]] || die "PGs still inactive or OSDs still down after 20m — investigate before unsetting flags"

# ── 5. Only now unset the flags, which is what lets recovery run ─────────────
log "Unsetting Ceph flags — recovery starts now"
ceph_exec bash -c 'for f in norecover nobackfill norebalance noout; do ceph osd unset $f; done' >/dev/null

# ── 6. Watch it settle ───────────────────────────────────────────────────────
log "Waiting for all PGs active+clean"
for i in $(seq 1 60); do
    pgstat="$(ceph_exec ceph pg stat 2>/dev/null | head -1 || true)"
    echo "  [$i] $pgstat"
    grep -qE 'active\+clean' <<<"$pgstat" && ! grep -qE 'degraded|undersized|inactive|peer' <<<"$pgstat" && break
    sleep 20
done

# ── 7. The aftershock sweep — this step is not optional ──────────────────────
# The blocked-I/O window leaves RBD volumes remounted read-only (ext4 sets
# `emergency_ro`) and the kernel does not undo it when Ceph recovers.
#
# Most victims DO NOT crash: they keep serving whatever does not need a write,
# so a "not Running" check misses them entirely. On 2026-08-22 that check found
# 3 crashlooping pods and missed 7 silently-degraded volumes, including Home
# Assistant, Alertmanager and zwave-js-ui. Scan the NODES instead — and scan
# ALL of them, because affected volumes sit on nodes that never went down.
hr
log "Scanning every node for read-only (emergency_ro) Ceph mounts"

ALL_IPS="$(jq -r '.items[] | (.status.addresses[]|select(.type=="InternalIP")|.address)' <<<"$ALL_JSON")"
RO_PVCS=""
if command -v talosctl >/dev/null 2>&1; then
    for ip in $ALL_IPS; do
        # Do not pre-filter this line: emergency_ro comes AFTER stripe=, so a
        # sed that trims the tail silently hides every hit.
        found="$(talosctl -n "$ip" read /proc/mounts 2>/dev/null \
                 | grep 'emergency_ro' | grep -oE 'pvc-[0-9a-f-]+' | sort -u || true)"
        [[ -n "$found" ]] && RO_PVCS+="$found"$'\n'
    done
else
    echo "  ! talosctl not available — skipping node scan (check by hand)"
fi

RO_PVCS="$(sort -u <<<"$RO_PVCS" | sed '/^$/d')"
if [[ -n "$RO_PVCS" ]]; then
    echo "  ✗ read-only volumes found — these pods are degraded but probably 'Running':"
    PVC_JSON="$(kubectl get pvc -A -o json)"
    restart=""
    while read -r vol; do
        [[ -z "$vol" ]] && continue
        read -r ns name < <(jq -r --arg v "$vol" '.items[] | select(.spec.volumeName==$v)
                            | "\(.metadata.namespace) \(.metadata.name)"' <<<"$PVC_JSON" | head -1)
        [[ -z "${ns:-}" ]] && { echo "    $vol (no matching PVC)"; continue; }
        pod="$(kubectl -n "$ns" get pods -o json \
              | jq -r --arg c "$name" '.items[] | select(.spec.volumes[]?.persistentVolumeClaim?.claimName==$c)
                                       | .metadata.name' | head -1)"
        echo "    $ns/$name -> pod ${pod:-<none>}"
        [[ -n "$pod" ]] && restart+="kubectl -n $ns delete pod $pod"$'\n'
    done <<<"$RO_PVCS"
    echo
    echo "  Fix is a pod restart, which detaches and remounts the volume read-write:"
    echo "$restart" | sed 's/^/    /'
    echo "  Data is usually intact — verify before assuming loss (see runbook)."
else
    echo "  ✓ no read-only Ceph mounts on any node"
fi

echo
log "Other stragglers (not Running/Completed)"
bad="$(kubectl get pods -A --no-headers 2>/dev/null \
      | awk '$4!="Running" && $4!="Completed" {print "    "$1"/"$2"  "$4}' || true)"
[[ -n "$bad" ]] && echo "$bad" || echo "  ✓ none"

echo
ceph_exec ceph status 2>/dev/null | sed -n '1,6p' || true
hr
log "Bring-up complete. Flux was never suspended for a partial shutdown."
