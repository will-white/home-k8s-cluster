#!/usr/bin/env bash
# Fence nodes whose kubelet has stopped reporting (Ready=Unknown) for longer
# than UNREACHABLE_THRESHOLD_SECONDS by applying the
# `node.kubernetes.io/out-of-service=nodeshutdown:NoExecute` taint.
#
# That taint tells the attach/detach controller to force-detach all
# VolumeAttachments on the node and the GC controller to immediately evict
# pods, which lets RWO PVCs (Ceph RBD, etc.) reattach on a live node.
#
# Idempotent: skips nodes that are healthy, or unreachable for less than the
# threshold.
#
# Unfencing: the out-of-service taint is never removed by Kubernetes itself,
# so a node that comes back stays NoExecute-tainted and nothing (e.g. its
# Ceph OSD pod) can schedule on it until a human removes the taint. For nodes
# that *this script* fenced (marked by the fenced-at annotation) the taint is
# removed once the node has been Ready=True for READY_GRACE_SECONDS. Taints
# applied by hand, without the annotation, are left alone.

set -euo pipefail

THRESHOLD="${UNREACHABLE_THRESHOLD_SECONDS:-3600}"
READY_GRACE="${READY_GRACE_SECONDS:-120}"
ANNOTATION_PREFIX="node-fencer.home.arpa"
TAINT_KEY="node.kubernetes.io/out-of-service"
TAINT_VALUE="nodeshutdown"
TAINT_EFFECT="NoExecute"
NOW="$(date -u +%s)"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# Parse an RFC3339 UTC timestamp (e.g. 2026-06-14T18:00:00Z, as emitted by
# Kubernetes .status.conditions[].lastTransitionTime) to epoch seconds.
# Works with both GNU coreutils (`date -d`) and BusyBox (`date -D ... -d`),
# so the script is portable across glibc and Alpine-based images.
to_epoch() {
    date -u -d "$1" +%s 2>/dev/null \
        || date -u -D "%Y-%m-%dT%H:%M:%SZ" -d "$1" +%s 2>/dev/null \
        || echo 0
}

mapfile -t NODES < <(kubectl get nodes -o name)

for node in "${NODES[@]}"; do
    name="${node#node/}"

    node_json="$(kubectl get "$node" -o json)"

    fenced="$(jq -r --arg k "$TAINT_KEY" \
        '.spec.taints // [] | map(select(.key == $k)) | length > 0' <<<"$node_json")"
    fenced_by_us="$(jq -r --arg a "${ANNOTATION_PREFIX}/fenced-at" \
        '.metadata.annotations[$a] != null' <<<"$node_json")"

    # Find the Ready condition.
    ready_json="$(jq -c '.status.conditions[]? | select(.type == "Ready")' <<<"$node_json")"

    if [[ -z "$ready_json" ]]; then
        continue
    fi

    status="$(jq -r '.status' <<<"$ready_json")"
    last_transition="$(jq -r '.lastTransitionTime' <<<"$ready_json")"

    if [[ "$fenced" == "true" ]]; then
        # Already fenced. Unfence only our own taints, and only once the
        # kubelet has been reporting Ready for a while (avoid flapping).
        if [[ "$fenced_by_us" != "true" || "$status" != "True" ]]; then
            continue
        fi

        transition_epoch="$(to_epoch "$last_transition")"
        if [[ "$transition_epoch" -eq 0 ]]; then
            log "WARN $name: could not parse lastTransitionTime '$last_transition'"
            continue
        fi

        age=$(( NOW - transition_epoch ))
        if (( age < READY_GRACE )); then
            log "SKIP $name: fenced, Ready=True for ${age}s (< ${READY_GRACE}s)"
            continue
        fi

        log "UNFENCE $name: Ready=True for ${age}s, removing taint ${TAINT_KEY}"
        if kubectl taint node "$name" "${TAINT_KEY}-"; then
            kubectl annotate "$node" \
                "${ANNOTATION_PREFIX}/fenced-at-" \
                "${ANNOTATION_PREFIX}/fenced-after-seconds-" \
                "${ANNOTATION_PREFIX}/unfenced-at=$(date -u +%FT%TZ)" \
                --overwrite >/dev/null
            log "OK    $name: unfenced"
        else
            log "ERROR $name: failed to remove taint"
            exit 1
        fi
        continue
    fi

    # Only act when kubelet has stopped reporting (Unknown). "False" means
    # the kubelet is up but failing health checks — leave that to a human.
    if [[ "$status" != "Unknown" ]]; then
        continue
    fi

    transition_epoch="$(to_epoch "$last_transition")"
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
            "${ANNOTATION_PREFIX}/fenced-at=$(date -u +%FT%TZ)" \
            "${ANNOTATION_PREFIX}/fenced-after-seconds=${age}" \
            "${ANNOTATION_PREFIX}/unfenced-at-" \
            --overwrite >/dev/null
        log "OK    $name: fenced"
    else
        log "ERROR $name: failed to apply taint"
        exit 1
    fi
done
