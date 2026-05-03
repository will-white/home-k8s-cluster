#!/usr/bin/env bash
# Fence nodes whose kubelet has stopped reporting (Ready=Unknown) for longer
# than UNREACHABLE_THRESHOLD_SECONDS by applying the
# `node.kubernetes.io/out-of-service=nodeshutdown:NoExecute` taint.
#
# That taint tells the attach/detach controller to force-detach all
# VolumeAttachments on the node and the GC controller to immediately evict
# pods, which lets RWO PVCs (Ceph RBD, etc.) reattach on a live node.
#
# Idempotent: skips nodes that are already tainted, healthy, or unreachable
# for less than the threshold.

set -euo pipefail

THRESHOLD="${UNREACHABLE_THRESHOLD_SECONDS:-3600}"
TAINT_KEY="node.kubernetes.io/out-of-service"
TAINT_VALUE="nodeshutdown"
TAINT_EFFECT="NoExecute"
NOW="$(date -u +%s)"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

mapfile -t NODES < <(kubectl get nodes -o name)

for node in "${NODES[@]}"; do
    name="${node#node/}"

    # Skip if already fenced.
    if kubectl get "$node" -o json \
        | jq -e --arg k "$TAINT_KEY" \
            '.spec.taints // [] | map(select(.key == $k)) | length > 0' >/dev/null; then
        continue
    fi

    # Find the Ready condition.
    ready_json="$(kubectl get "$node" -o json \
        | jq -c '.status.conditions[]? | select(.type == "Ready")')"

    if [[ -z "$ready_json" ]]; then
        continue
    fi

    status="$(jq -r '.status' <<<"$ready_json")"
    last_transition="$(jq -r '.lastTransitionTime' <<<"$ready_json")"

    # Only act when kubelet has stopped reporting (Unknown). "False" means
    # the kubelet is up but failing health checks — leave that to a human.
    if [[ "$status" != "Unknown" ]]; then
        continue
    fi

    transition_epoch="$(date -u -d "$last_transition" +%s 2>/dev/null || echo 0)"
    if [[ "$transition_epoch" -eq 0 ]]; then
        log "WARN $name: could not parse lastTransitionTime '$last_transition'"
        continue
    fi

    age=$(( NOW - transition_epoch ))
    if (( age < THRESHOLD )); then
        log "SKIP $name: Ready=Unknown for ${age}s (< ${THRESHOLD}s)"
        continue
    fi

    log "FENCE $name: Ready=Unknown for ${age}s, applying taint ${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}"
    if kubectl taint node "$name" "${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}" --overwrite; then
        kubectl annotate "$node" \
            "node-fencer.home.arpa/fenced-at=$(date -u +%FT%TZ)" \
            "node-fencer.home.arpa/fenced-after-seconds=${age}" \
            --overwrite >/dev/null
        log "OK    $name: fenced"
    else
        log "ERROR $name: failed to apply taint"
        exit 1
    fi
done
