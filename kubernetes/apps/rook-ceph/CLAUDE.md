# rook-ceph — domain guide (`@storage-agent`)

Loaded automatically for work under `kubernetes/apps/rook-ceph/` (and the role
for `openebs-system/`). Everything here holds user data.

## Components

| Flux Kustomization | Holds |
|---|---|
| `rook-ceph` | Operator chart |
| `rook-ceph-cluster` | `CephCluster`, block pool, CephFS, RGW object store, StorageClasses, buckets, CNPG `PushSecret` for its bucket credentials |
| `rook-ceph-backup` | Nightly `rclone` of the RGW buckets (`cloudnative-pg`, `volsync-backups`) to Garage on the NAS, plus the manual restore Job. Runbook: [backup/DISASTER-RECOVERY.md](./rook-ceph/backup/DISASTER-RECOVERY.md) |
| `rook-ceph-mgr-maintenance` | mgr housekeeping |

## Conventions

- **StorageClasses are a closed set**: `ceph-block` (RWO, snapshot class
  `csi-ceph-blockpool`), `ceph-filesystem` (RWX, `csi-ceph-filesystem`),
  `ceph-bucket` (OBCs), `openebs-hostpath` (scratch, node-local). A new class
  needs a written purpose and a name that says it.
- **Snapshot classes are explicit** per StorageClass; nothing relies on a
  cluster default.
- **Pool changes** (replication size, failure domain, device class) are
  change-controlled: rationale in the PR, and `ceph -s` healthy before and
  after.
- Wiping a node's NVMe for a rebuild is in `README.md` here and in
  [docs/runbooks/bare-metal-rebuild.md](../../../docs/runbooks/bare-metal-rebuild.md).

## Boundaries (hard)

- Cluster-mutating Ceph commands (`ceph osd out/purge`, pool deletion, CRUSH
  edits) need explicit human approval and are logged in the PR or issue.
- Never delete a PVC, PV, `VolumeSnapshot`, OBC or bucket without named human
  approval.
- `HEALTH_WARN` / `HEALTH_ERR`: diagnose first (`ceph -s`, `ceph osd tree`,
  `ceph health detail`), never purge an OSD that is not out and drained.
- Chart `version:` and CRD bumps go through `@infra-agent` review; read the
  Rook upgrade notes for the exact minor.

## Validate

```bash
task kubernetes:validate APP=<ns>/<app>      # wraps the checks below
kustomize build --load-restrictor=LoadRestrictionsNone kubernetes/apps/rook-ceph/rook-ceph/cluster | kubeconform -strict -ignore-missing-schemas -
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s          # read-only
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree
kubectl get volumesnapshot,volumesnapshotcontent -A
```
