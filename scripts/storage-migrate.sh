#!/bin/bash
# storage-migrate.sh — ceph-block → ceph-filesystem cutover
#
# Run AFTER the manifest changes in this branch are committed and Flux has
# pulled them. Runs ONE app per invocation, fails loudly on errors.
#
# Usage:  scripts/storage-migrate.sh <app>
# Apps:   kometa | recyclarr | zigbee2mqtt-ota | seerr | bazarr | qbittorrent
#
# Requires: kubectl, flux, jq. KUBECONFIG must point at the cluster.

set -euo pipefail

APP="${1:-}"
NS_media="media"
NS_default="default"
NFS_SCRATCH="/mnt/main/_migrate"   # used only by the seerr rsync path

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date -u +%T)] $*"; }

confirm() {
    read -rp "  ↪ $1 [y/N] " ans
    [[ "${ans,,}" == "y" ]] || die "aborted by user"
}

wait_pvc_bound() {
    local ns="$1" pvc="$2" sc_expected="$3"
    log "Waiting for PVC $ns/$pvc to bind on $sc_expected..."
    for i in $(seq 1 60); do
        local phase sc
        phase=$(kubectl -n "$ns" get pvc "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null || true)
        sc=$(kubectl -n "$ns" get pvc "$pvc" -o jsonpath='{.spec.storageClassName}' 2>/dev/null || true)
        if [[ "$phase" == "Bound" && "$sc" == "$sc_expected" ]]; then
            log "  bound."
            return 0
        fi
        sleep 5
    done
    die "PVC $ns/$pvc did not bind on $sc_expected within 5min"
}

cutover_simple_cronjob() {
    # For kometa, recyclarr, zigbee2mqtt-ota — disposable data, just delete & let Flux recreate.
    local ns="$1" pvc="$2"
    log "=== cutover_simple_cronjob ns=$ns pvc=$pvc ==="

    log "Suspending Flux Kustomization $APP..."
    flux suspend ks "$APP"

    log "Deleting any active jobs/pods that mount $pvc..."
    kubectl -n "$ns" get pods -o json \
      | jq -r --arg pvc "$pvc" \
          '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name' \
      | xargs -r -n1 kubectl -n "$ns" delete pod --grace-period=0 --force

    log "Deleting PVC $ns/$pvc..."
    confirm "DELETE PVC $ns/$pvc?"
    kubectl -n "$ns" delete pvc "$pvc" --wait=true --timeout=120s

    log "Resuming + reconciling..."
    flux resume ks "$APP"
    flux reconcile ks "$APP" --with-source

    wait_pvc_bound "$ns" "$pvc" "ceph-filesystem"
    log "DONE: $APP migrated."
}

cutover_seerr() {
    local ns="media" pvc="seerr"
    log "=== cutover_seerr (rsync via NFS scratch) ==="

    [[ -d "$NFS_SCRATCH" ]] || die "NFS scratch path $NFS_SCRATCH not visible from this host. Either mount it or run from inside the cluster."

    log "Suspending Flux Kustomization seerr..."
    flux suspend ks seerr

    log "Scaling statefulset/seerr to 0..."
    kubectl -n "$ns" scale sts seerr --replicas=0
    kubectl -n "$ns" wait --for=delete pod -l app.kubernetes.io/name=seerr --timeout=120s || true

    log "Running backup job (rsync seerr PVC -> NFS scratch)..."
    kubectl -n "$ns" delete job seerr-migrate-backup --ignore-not-found
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: seerr-migrate-backup
  namespace: $ns
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: rsync
          image: docker.io/instrumentisto/rsync-ssh:alpine
          command: ["sh","-c","mkdir -p /scratch/seerr && rsync -aH --delete /old/ /scratch/seerr/ && echo OK"]
          volumeMounts:
            - { name: old, mountPath: /old }
            - { name: scratch, mountPath: /scratch }
      volumes:
        - name: old
          persistentVolumeClaim: { claimName: seerr }
        - name: scratch
          nfs: { server: 192.168.5.10, path: /mnt/main }
EOF
    kubectl -n "$ns" wait --for=condition=complete job/seerr-migrate-backup --timeout=600s

    log "Backup OK. Deleting old PVC..."
    confirm "DELETE PVC $ns/$pvc (data is in NFS scratch)?"
    kubectl -n "$ns" delete pvc "$pvc" --wait=true --timeout=120s

    log "Resume Flux to create new RWX cephfs PVC..."
    flux resume ks seerr
    flux reconcile ks seerr --with-source
    wait_pvc_bound "$ns" "$pvc" "ceph-filesystem"

    log "Running restore job (NFS scratch -> new seerr PVC)..."
    kubectl -n "$ns" delete job seerr-migrate-restore --ignore-not-found
    cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: seerr-migrate-restore
  namespace: $ns
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: rsync
          image: docker.io/instrumentisto/rsync-ssh:alpine
          command: ["sh","-c","rsync -aH /scratch/seerr/ /new/ && echo OK"]
          volumeMounts:
            - { name: new, mountPath: /new }
            - { name: scratch, mountPath: /scratch }
      volumes:
        - name: new
          persistentVolumeClaim: { claimName: seerr }
        - name: scratch
          nfs: { server: 192.168.5.10, path: /mnt/main }
EOF
    kubectl -n "$ns" wait --for=condition=complete job/seerr-migrate-restore --timeout=600s

    log "Scaling statefulset/seerr back to 1..."
    kubectl -n "$ns" scale sts seerr --replicas=1
    kubectl -n "$ns" rollout status sts/seerr --timeout=300s

    log "DONE: seerr migrated. NFS scratch left at $NFS_SCRATCH/seerr — delete after verifying."
}

cutover_volsync() {
    # For bazarr, qbittorrent — uses Volsync bootstrap restore.
    local ns="media" pvc="$1"
    local bootstrap_dest="volsync-${pvc}-bootstrap-dest"

    log "=== cutover_volsync ns=$ns pvc=$pvc ==="

    log "Suspending Flux Kustomization $APP..."
    flux suspend ks "$APP"

    log "Scaling deployment/$pvc to 0..."
    kubectl -n "$ns" scale deploy "$pvc" --replicas=0 || true

    # Force-delete any pods still on the dead node (mj0581rw scenario).
    log "Force-deleting any pod stuck Terminating on an unreachable node..."
    kubectl -n "$ns" get pods -l "app.kubernetes.io/name=$pvc" -o json \
      | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | .metadata.name' \
      | xargs -r -n1 kubectl -n "$ns" delete pod --grace-period=0 --force

    # Clean up any orphaned VolumeAttachments for this PVC's PV.
    log "Cleaning orphaned VolumeAttachments for $pvc..."
    local pv
    pv=$(kubectl -n "$ns" get pvc "$pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
    if [[ -n "$pv" ]]; then
        kubectl get volumeattachment -o json \
          | jq -r --arg pv "$pv" '.items[] | select(.spec.source.persistentVolumeName == $pv) | .metadata.name' \
          | xargs -r -n1 kubectl delete volumeattachment
    fi

    log "Deleting old bootstrap dest PVC and old app PVC..."
    confirm "DELETE PVC $ns/$pvc and $ns/$bootstrap_dest? (Latest backup is in Kopia/S3.)"
    kubectl -n "$ns" delete pvc "$bootstrap_dest" --ignore-not-found --wait=false
    kubectl -n "$ns" delete pvc "$pvc" --wait=false
    # PVCs may be slow to release if attachers need to finalize; force after 60s.
    sleep 60
    kubectl -n "$ns" patch pvc "$pvc" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
    kubectl -n "$ns" patch pvc "$bootstrap_dest" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true

    log "Resume Flux to create RWX cephfs PVCs and re-run bootstrap restore..."
    flux resume ks "$APP"
    flux reconcile ks "$APP" --with-source

    log "Waiting for ReplicationDestination $pvc-bootstrap to complete fresh restore..."
    for i in $(seq 1 120); do
        local last
        last=$(kubectl -n "$ns" get replicationdestination "$pvc-bootstrap" \
            -o jsonpath='{.status.lastManualSync}' 2>/dev/null || true)
        if [[ "$last" == "restore-cephfs-2026-05-03" ]]; then
            log "  bootstrap restore complete."
            break
        fi
        sleep 10
    done

    wait_pvc_bound "$ns" "$pvc" "ceph-filesystem"

    log "Scaling deployment/$pvc back to 1..."
    kubectl -n "$ns" scale deploy "$pvc" --replicas=1
    kubectl -n "$ns" rollout status deploy/"$pvc" --timeout=300s

    log "DONE: $APP migrated."
}

case "$APP" in
    kometa)            cutover_simple_cronjob "$NS_media"   "kometa" ;;
    recyclarr)         cutover_simple_cronjob "$NS_media"   "recyclarr" ;;
    zigbee2mqtt-ota)   cutover_simple_cronjob "$NS_default" "zigbee2mqtt-ota-state" ;;
    seerr)             cutover_seerr ;;
    bazarr)            cutover_volsync "bazarr" ;;
    qbittorrent)       cutover_volsync "qbittorrent" ;;
    "")                die "Usage: $0 <kometa|recyclarr|zigbee2mqtt-ota|seerr|bazarr|qbittorrent>" ;;
    *)                 die "Unknown app: $APP" ;;
esac
