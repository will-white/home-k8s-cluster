# Volsync: restore a PVC from Kopia

Every stateful app snapshots its PVC to the shared Kopia repository
(`s3://volsync-backups` on Ceph RGW, mirrored nightly to Garage). Three
situations, three procedures. All of them touch user data: get explicit,
named approval before deleting or overwriting a PVC.

## Where things are

| Thing | Location |
|---|---|
| Template (claim, bootstrap `ReplicationDestination`, `ReplicationSource`) | `kubernetes/templates/volsync/` |
| Per-app knobs (`VOLSYNC_*`) | the app's `ks.yaml` `postBuild.substitute` |
| Kopia web UI (browse snapshots, restore single files) | `https://kopia.${SECRET_DOMAIN}` |
| Freshness check | `volsync-canary` CronJob in `volsync-system` (daily; a failure pages via `KubeJobFailed`) |
| Repository password and S3 keys | Bitwarden `VOLSYNC_KOPIA_PASSWORD`, `VOLSYNC_BUCKET_ACCESS_KEY`, `VOLSYNC_BUCKET_SECRET_KEY` |

Snapshot identity is `<app>@<namespace>` (`username: ${APP}`, hostname = the
namespace); the canary ConfigMap lists every identity that must stay fresh.

## A. Fresh cluster, or the PVC was deleted

Nothing to do by hand: the claim in the template has
`dataSourceRef: ReplicationDestination <app>-bootstrap`, so when Flux
creates the PVC Volsync restores the latest snapshot first, then the app
starts. Watch it:

```bash
kubectl -n <ns> get replicationdestination <app>-bootstrap -o yaml | yq .status
kubectl -n <ns> get pvc <app>                      # Bound once the restore finished
kubectl -n <ns> logs job/volsync-dst-<app>-bootstrap -f   # mover log while it runs
```

A restore that reports `Successful` after seconds with a tiny PVC was the
2026-05 "0 bytes restored" bug: check that
`VOLSYNC_BOOTSTRAP_SOURCE_NAMESPACE` is set (it feeds `sourceIdentity`) and
that the identity exists in the Kopia UI.

## B. Roll an existing PVC back to an earlier snapshot

The bootstrap destination only runs at PVC creation. For an in-place restore
use a one-off `ReplicationDestination` with `copyMethod: Direct` that writes
into the live claim while the app is stopped.

1. Stop the app and pause Flux so it does not start it again:

   ```bash
   flux -n flux-system suspend ks <app>
   flux -n <ns> suspend hr <app>
   kubectl -n <ns> scale deploy/<app> --replicas=0    # or sts
   ```

2. Apply the restore (pick the snapshot with `restoreAsOf`, or `previous: N`
   to step back N snapshots):

   ```yaml
   apiVersion: volsync.backube/v1alpha1
   kind: ReplicationDestination
   metadata:
     name: <app>-restore
     namespace: <ns>
   spec:
     trigger:
       manual: restore-$(date +%Y%m%d)
     kopia:
       repository: <app>-volsync
       copyMethod: Direct
       destinationPVC: <app>
       sourceIdentity:
         sourceName: <app>
         sourceNamespace: <ns>
       restoreAsOf: "2026-10-28T03:00:00Z"   # optional, RFC3339
       moverSecurityContext:
         runAsUser: 1000
         runAsGroup: 1000
         fsGroup: 1000
       moverResources:
         requests: {cpu: 100m, memory: 512Mi}
         limits: {memory: 2Gi}
   ```

   `kubectl apply -f` it, then watch `kubectl -n <ns> get replicationdestination
   <app>-restore -o yaml | yq .status` until `lastManualSync` equals the
   trigger. Match `runAsUser` to the app's `VOLSYNC_PUID`.

3. Delete the restore object, resume and verify:

   ```bash
   kubectl -n <ns> delete replicationdestination <app>-restore
   flux -n <ns> resume hr <app>
   flux -n flux-system resume ks <app>
   kubectl -n <ns> get pods -l app.kubernetes.io/name=<app> -w
   ```

4. The next scheduled `ReplicationSource` run snapshots the restored state;
   check the canary stays green the next morning.

## C. Single files

Open `https://kopia.${SECRET_DOMAIN}`, browse `<app>@<ns>:/data`, download or
mount the path. Copy the file into the running pod with `kubectl cp`. No
Volsync objects involved.

## D. Migrate a PVC to another StorageClass or access mode

The claim's StorageClass and `dataSourceRef` are immutable, so this is
"restore into a new claim": set the new `PVC_VOLSYNC_STORAGECLASS` /
`VOLSYNC_STORAGECLASS` / `VOLSYNC_SNAPSHOTCLASS` / `*_ACCESSMODES` in `ks.yaml`,
bump `VOLSYNC_BOOTSTRAP_TRIGGER` to a fresh value (e.g. `restore-cephfs-<date>`),
let the last backup run, suspend the app, delete the old PVC **with approval**,
and let Flux recreate it per procedure A. `paperless` is the worked example in
git history (`VOLSYNC_BOOTSTRAP_TRIGGER: restore-cephfs-2026-05-03`).

## Whole-repository loss

If RGW itself is gone, rehydrate the bucket from Garage first:
[rook-ceph/backup/DISASTER-RECOVERY.md](../../kubernetes/apps/rook-ceph/rook-ceph/backup/DISASTER-RECOVERY.md),
then procedure A applies to every app.
