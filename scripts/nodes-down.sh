#!/bin/bash
# nodes-down.sh — power off a SUBSET of nodes without breaking Ceph
#
# The whole-cluster path is `task talos:cluster-down`. This is the partial
# case, where the rest of the cluster keeps serving and so Ceph min_size, the
# PDBs and the CNPG primary all matter in ways they do not for a full
# shutdown. See docs/runbooks/full-cluster-shutdown.md.
#
# Usage:  scripts/nodes-down.sh <ip|hostname> [<ip|hostname> ...]
#         task talos:nodes-down NODES="192.168.5.53 192.168.5.54"
#
# Refuses to run when Ceph reports that losing these OSDs would take PGs
# offline (`ceph osd ok-to-stop`). That check is the whole point of this
# script: with size 3 / min_size 2 and one OSD per host, two hosts is the
# threshold where client I/O starts blocking. Override with FORCE_UNSAFE=1
# only after reading the runbook and accepting blocked I/O.
#
# Requires: talosctl, kubectl, jq. KUBECONFIG/TALOSCONFIG come from Task.

set -euo pipefail

CNPG_NS="database"
CNPG_CLUSTER="postgres16"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date -u +%T)] $*"; }
hr()  { printf '%.0s─' {1..66}; echo; }

confirm() {
    read -rp "  ↪ $1 [y/N] " ans
    [[ "${ans,,}" == "y" ]] || die "aborted by user"
}

ceph_exec() { kubectl -n rook-ceph exec deploy/rook-ceph-tools -- "$@"; }

[[ $# -gt 0 ]] || die "no nodes given. Usage: $0 <ip|hostname> [...]"
command -v talosctl >/dev/null || die "talosctl not found"
command -v jq >/dev/null || die "jq not found"

# ── Resolve arguments to (node name, ip) pairs ───────────────────────────────
NODES=(); IPS=()
ALL_JSON="$(kubectl get nodes -o json)"
for want in "$@"; do
    read -r name ip < <(jq -r --arg w "$want" '
        .items[] as $n
        | (($n.status.addresses[] | select(.type=="InternalIP") | .address)) as $ip
        | select($n.metadata.name == $w or $ip == $w)
        | "\($n.metadata.name) \($ip)"' <<<"$ALL_JSON" | head -1)
    [[ -n "${name:-}" ]] || die "'$want' does not match any node name or InternalIP"
    NODES+=("$name"); IPS+=("$ip")
done

# ── Map nodes to OSD ids and ask Ceph whether this is safe ───────────────────
OSD_JSON="$(kubectl -n rook-ceph get pods -l app=rook-ceph-osd -o json)"
OSDS=()
for n in "${NODES[@]}"; do
    while read -r id; do [[ -n "$id" ]] && OSDS+=("$id"); done < <(
        jq -r --arg n "$n" '.items[] | select(.spec.nodeName==$n)
                            | .metadata.labels["ceph-osd-id"] // empty' <<<"$OSD_JSON")
done

hr
log "Nodes to stop : ${NODES[*]}"
log "Addresses     : ${IPS[*]}"
log "OSDs affected : ${OSDS[*]:-none}"
hr

if [[ ${#OSDS[@]} -gt 0 ]]; then
    log "Asking Ceph whether these OSDs can stop together..."
    # ceph writes the JSON verdict to stdout and an "Error EBUSY:" line to
    # stderr, so keep only the JSON object for jq.
    set +e
    raw="$(ceph_exec ceph osd ok-to-stop "${OSDS[@]}" 2>&1)"; rc=$?
    set -e
    ok_out="$(grep -m1 '^{' <<<"$raw" || true)"

    if [[ $rc -eq 0 ]]; then
        echo "  ✓ ok-to-stop: safe — PGs stay above min_size"
        deg="$(jq -r '.ok_become_degraded // [] | length' <<<"$ok_out" 2>/dev/null || echo "?")"
        echo "    PGs that will become degraded (not offline): $deg"
    else
        echo "  ✗ ok-to-stop: UNSAFE" >&2
        bad="$(jq -r '.bad_become_inactive // [] | join(" ")' <<<"$ok_out" 2>/dev/null || true)"
        cnt="$(jq -r '.num_not_ok_pgs // "?"' <<<"$ok_out" 2>/dev/null || echo "?")"
        echo "    ${cnt} PGs would go offline — client I/O on them blocks until a node returns." >&2
        [[ -n "$bad" ]] && echo "    Affected PGs: $bad" >&2
        echo >&2
        if [[ "${FORCE_UNSAFE:-0}" == "1" ]]; then
            echo "    FORCE_UNSAFE=1 set — continuing anyway." >&2
        else
            die "refusing to proceed. Take one node at a time, or set FORCE_UNSAFE=1 if you accept blocked I/O (see the runbook)."
        fi
    fi
else
    log "No OSDs on these nodes — no Ceph availability impact."
fi

# ── Report what else lives here, and what is about to start ──────────────────
hr
log "Workloads that will be disrupted:"
for n in "${NODES[@]}"; do
    cnt=$(kubectl get pods -A --field-selector "spec.nodeName=$n" --no-headers 2>/dev/null | grep -cv Completed || true)
    echo "    $n: $cnt running pods"
done

PRIMARY_POD="$(kubectl -n "$CNPG_NS" get cluster "$CNPG_CLUSTER" -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
PRIMARY_NODE=""
if [[ -n "$PRIMARY_POD" ]]; then
    PRIMARY_NODE="$(kubectl -n "$CNPG_NS" get pod "$PRIMARY_POD" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)"
    echo "    CNPG primary: $PRIMARY_POD on $PRIMARY_NODE"
fi

# Anything on a schedule that fires during the window strands its mover pod.
soon="$(kubectl get replicationsources -A -o json 2>/dev/null \
    | jq -r --arg now "$(date -u +%s)" '
        .items[] | select(.status.nextSyncTime != null)
        | select(((.status.nextSyncTime | fromdateiso8601) - ($now|tonumber)) < 1800)
        | "    \(.metadata.namespace)/\(.metadata.name) at \(.status.nextSyncTime)"' 2>/dev/null || true)"
if [[ -n "$soon" ]]; then
    echo
    echo "  ⚠ Volsync syncs firing within 30 minutes — these will strand their"
    echo "    mover pods if they start while the nodes are down:"
    echo "$soon"
fi
hr

confirm "Power off ${NODES[*]}?"

# ── Move the CNPG primary off a doomed node (switchover, not failover) ───────
if [[ -n "$PRIMARY_NODE" ]] && printf '%s\n' "${NODES[@]}" | grep -qx "$PRIMARY_NODE"; then
    log "CNPG primary is on $PRIMARY_NODE — switching over first"
    DOOMED_JSON="$(printf '%s\n' "${NODES[@]}" | jq -R . | jq -sc .)"
    TARGET="$(kubectl -n "$CNPG_NS" get pods -l "cnpg.io/cluster=$CNPG_CLUSTER" -o json \
        | jq -r --argjson d "$DOOMED_JSON" '
            .items[]
            | select(.spec.nodeName as $n | ($d | any(. == $n)) | not)
            | select(.status.phase=="Running") | .metadata.name' | head -1)"
    [[ -n "$TARGET" ]] || die "no surviving CNPG instance to promote"
    log "Promoting $TARGET"
    kubectl -n "$CNPG_NS" patch cluster "$CNPG_CLUSTER" --subresource=status --type=merge \
        -p "{\"status\":{\"targetPrimary\":\"$TARGET\"}}"
    for _ in $(seq 1 30); do
        cur="$(kubectl -n "$CNPG_NS" get cluster "$CNPG_CLUSTER" -o jsonpath='{.status.currentPrimary}')"
        [[ "$cur" == "$TARGET" ]] && { log "primary is now $cur"; break; }
        sleep 5
    done
else
    log "CNPG primary is not on a doomed node — no switchover needed"
fi

# ── Ceph maintenance flags. Never nodown; see the runbook. ───────────────────
log "Setting Ceph flags (noout norebalance nobackfill norecover)"
ceph_exec bash -c 'for f in noout norebalance nobackfill norecover; do ceph osd set $f; done' >/dev/null

# ── Cordon, then power off ───────────────────────────────────────────────────
log "Cordoning ${NODES[*]}"
kubectl cordon "${NODES[@]}"

# --force skips the k8s drain: rook-ceph-osd and emqx-core sit at
# maxUnavailable 1 and postgres16-primary at 0, so draining more than one node
# deadlocks on the PDBs for the full 30m timeout. Talos still stops containers
# and unmounts cleanly.
log "Powering off (--force skips the k8s drain; PDBs would deadlock it)"
talosctl -n "$(IFS=,; echo "${IPS[*]}")" shutdown --force --wait=false

hr
log "Shutdown issued."
echo "  Nodes holding kernel CephFS/RBD mounts can take ~12 minutes to actually"
echo "  power off — do NOT reach for the power button."
echo
echo "  When they are back:  task talos:nodes-up NODES=\"${IPS[*]}\""
hr
