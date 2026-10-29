---
name: onboard-volsync
description: >-
  Put an app's PVC under the shared Volsync + Kopia backup pattern (or convert
  a hand-rolled PVC to it), including the canary identity and the storage
  class knobs that are easy to get wrong. Use when the user asks to "back
  up", "add volsync", "snapshot", "protect the data of" an app, or when a new
  stateful app is being added.
---

# Onboard an app to Volsync

Reference: `kubernetes/templates/volsync/README.md`,
`kubernetes/apps/volsync-system/CLAUDE.md`, restore procedure in
`docs/runbooks/volsync-restore.md`. Deleting or recreating a PVC is a user-data
operation: get explicit approval before any step that does.

## Case 1: new app, PVC not created yet (preferred)

1. `app/kustomization.yaml`: add `- ../../../../templates/volsync` and remove
   any `pvc.yaml`. The template creates the claim (`${VOLSYNC_CLAIM:-${APP}}`)
   from the bootstrap `ReplicationDestination`, the `ReplicationSource` and
   the `ExternalSecret`.
2. `ks.yaml`: `dependsOn: volsync`, and in `postBuild.substitute`:

   ```yaml
   VOLSYNC_CAPACITY: 5Gi
   VOLSYNC_BOOTSTRAP_SOURCE_NAMESPACE: <ns>        # feeds sourceIdentity; without it restores are empty
   PVC_VOLSYNC_STORAGECLASS: ceph-block            # the claim (immutable once created)
   VOLSYNC_STORAGECLASS: ceph-block                # mover cache/temp volumes
   VOLSYNC_SNAPSHOTCLASS: csi-ceph-blockpool
   # RWX (ceph-filesystem) apps add:
   # VOLSYNC_ACCESSMODES: ReadWriteMany
   # VOLSYNC_SNAP_ACCESSMODES: ReadWriteMany
   # VOLSYNC_SNAPSHOTCLASS: csi-ceph-filesystem
   ```

   Optional: `VOLSYNC_SCHEDULE` (default hourly), `VOLSYNC_PUID/PGID` to match
   the app's `runAsUser` (default 1000), `VOLSYNC_MOVER_MEMORY_LIMIT` (keep
   2Gi unless Kopia reports mmap errors).
3. HelmRelease: `persistence.config.existingClaim: *app` (the claim name).
4. Canary: add `<app>@<ns>:<max-age-hours>:<description>` to
   `kubernetes/apps/volsync-system/volsync-canary/app/configmap.yaml`
   (`3` for the default hourly schedule, `30` for a daily one, like the
   existing entries).

## Case 2: existing app with its own `pvc.yaml`

The claim's `dataSourceRef` cannot be added after creation, so there are two
options; say which one you are proposing.

- **Backup only, keep the PVC**: add
  `- ../../../../templates/volsync/source-only` instead of the full template
  (ReplicationSource + ExternalSecret, no claim). Same `ks.yaml` variables
  minus `VOLSYNC_CAPACITY`; set `CLAIM` if the PVC name differs from the app.
  Restores are then procedure B in the runbook (in-place `Direct` destination).
- **Convert to the full template** (restore-first on rebuild): source-only
  first, wait for one successful snapshot, then switch to the full template
  with a fresh `VOLSYNC_BOOTSTRAP_TRIGGER`, delete the old PVC **with
  approval**, and let Flux recreate it from the snapshot (runbook procedure D).

## Validate

```bash
task kubernetes:validate APP=<ns>/<app>
# after merge (needs KUBECONFIG):
kubectl -n <ns> get replicationsource <app> -o yaml | yq .status.lastSyncTime
kubectl -n <ns> get pvc <app>
```

Pure caches rebuilt from Git or upstream (recyclarr, kometa) are deliberately
not backed up; say so instead of adding them.
