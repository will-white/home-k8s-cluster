# VolSync Template

## Flux Kustomization

This requires `postBuild` configured on the Flux Kustomization

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app plex
  namespace: flux-system
spec:
  # ...
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_CAPACITY: 5Gi
```

and then call the template in your applications `kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # ...
  - ../../../../templates/volsync
```

## Required `postBuild` vars:

- `APP`: The application name
- `VOLSYNC_CAPACITY`: The PVC size

## Optional `postBuild` vars:

- `VOLSYNC_MOVER_MEMORY_LIMIT`: Memory limit for mover pods (default: `1Gi`)
- `VOLSYNC_STORAGECLASS`: Storage class for volumes (default: `ceph-block`)
- `VOLSYNC_SNAPSHOTCLASS`: Snapshot class (default: `csi-ceph-blockpool`)
- `VOLSYNC_SNAP_ACCESSMODES`: Access modes for snapshots (default: `ReadWriteOnce`)
- `VOLSYNC_COPYMETHOD`: Copy method (default: `Snapshot`)
- `VOLSYNC_PUID`: User ID for mover security context (default: `1000`)
- `VOLSYNC_PGID`: Group ID for mover security context (default: `1000`)
- `VOLSYNC_RETAIN_DAILY`: Daily retention count (default: `3`)
- `VOLSYNC_RETAIN_HOURLY`: Hourly retention count (default: `6`)
- `VOLSYNC_RETAIN_WEEKLY`: Weekly retention count (default: `2`)
- `VOLSYNC_RETAIN_MONTHLY`: Monthly retention count (default: `1`)
