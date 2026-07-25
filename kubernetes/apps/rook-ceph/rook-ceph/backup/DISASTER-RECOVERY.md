# Ceph RGW Disaster Recovery Runbook

How Ceph RGW object data is backed up to Garage (on the NAS) and how to
rehydrate it in a disaster.

## Architecture

```
Normal operation (nightly CronJob rclone-rgw-backup, 03:00):

  Ceph RGW bucket            Garage bucket
  ─────────────────          ─────────────
  cloudnative-pg   ── sync ─► cloudnative-pg      (CNPG barman: base + WAL)
  volsync-backups  ── sync ─► volsync-backups     (volsync kopia repo)

Restore (manual Job rclone-rgw-restore): same, reversed (garage: ─► ceph:).
```

Each bucket is synced with **its own OBC credentials**, not a shared user.
This matters: the app buckets are owned by their OBC-provisioned users, and a
shared `backup-user` gets `403 AccessDenied` on them (S3 does not grant
cross-owner access from admin *caps*). Because the job reads credentials live
from the OBC secrets, it keeps working after a rebuild, when Rook re-creates
the OBCs with the same bucket names but fresh users and keys.

### Components (in `backup/`)

| File | Purpose |
|------|---------|
| `cronjob.yaml` | Nightly backup. Per-bucket source remotes via `RCLONE_CONFIG_*` env from the OBC secrets; `[garage]` destination from `rclone.conf`. |
| `externalsecret.yaml` | Renders `rclone.conf` with only the `[garage]` remote (Bitwarden `rclone-rgw-backup`: endpoint + keys). Note `region = garage` — Garage validates the SigV4 scope against its `s3_region`; without it you get `AuthorizationHeaderMalformed`. |
| `obc-cred-mirror.yaml` | The `volsync-backups` OBC secret lives in `volsync-system`. This mirrors it into `rook-ceph` via an ESO Kubernetes-provider `SecretStore` + scoped RBAC (`ServiceAccount`/`ClusterRole`/`ClusterRoleBinding` reading only the `kopia-bucket` secret). |
| `restore-job.yaml` | **Manual** restore Job (garage → ceph). NOT in `kustomization.yaml`, so Flux never runs it. |

### Credentials

| Bucket | Source of creds | Namespace |
|--------|-----------------|-----------|
| `cloudnative-pg` | OBC secret `cloudnative-pg` | `rook-ceph` |
| `volsync-backups` | OBC secret `kopia-bucket`, mirrored to `volsync-obc-creds` | `volsync-system` → `rook-ceph` |
| Garage endpoint/keys | Bitwarden `rclone-rgw-backup` (`GARAGE_ENDPOINT`, `GARAGE_ACCESS_KEY`, `GARAGE_SECRET_KEY`) | — |

Garage endpoint is currently `http://nas.internal:30188`.

---

## ⚠ Golden rule

The backup is a **mirror** (`rclone sync`, which deletes). If it runs while Ceph
RGW is empty (e.g. mid-rebuild), it will **wipe the good copy in Garage**.

**Before any restore, suspend the backup and leave it suspended until RGW is
repopulated and verified:**

```bash
kubectl patch cronjob -n rook-ceph rclone-rgw-backup \
  --type merge -p '{"spec":{"suspend":true}}'
```

Re-enable afterwards by setting `suspend: false` in `cronjob.yaml` (Flux owns
the field, so change it in git, not just live).

---

## Verifying the backup

```bash
# CronJob should not be suspended and should have run in the last 24h
kubectl get cronjob -n rook-ceph rclone-rgw-backup

# Manual run
kubectl create job --from=cronjob/rclone-rgw-backup -n rook-ceph rclone-manual
kubectl logs -n rook-ceph -l job-name=rclone-manual -f

# Compare sizes (radosgw-admin: always pass the zone, see gotcha below)
```

### radosgw-admin zone gotcha

The tools pod defaults to the empty `default` zone, so bare `radosgw-admin
bucket list` / `user list` return `[]` and look like data loss. Always pass the
real zone:

```bash
Z="--rgw-realm=ceph-objectstore --rgw-zonegroup=ceph-objectstore --rgw-zone=ceph-objectstore"
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- radosgw-admin bucket list $Z
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- radosgw-admin bucket stats --bucket=cloudnative-pg $Z
```

---

## Rehydration

Restore is two layers: **object layer** (Garage → Ceph RGW) then **app layer**
(bucket → running database / PVC).

### Layer 1 — Object restore (Garage → Ceph RGW)

1. **Suspend the backup** (golden rule above).
2. Confirm the OBCs are Bound and their secrets exist:
   ```bash
   kubectl get objectbucketclaim -A
   kubectl get secret -n rook-ceph cloudnative-pg volsync-obc-creds
   ```
   On a fresh cluster, wait for Flux to reconcile `rook-ceph` (OBCs + the
   `obc-cred-mirror.yaml` ExternalSecret) before continuing.
3. Run the restore Job:
   ```bash
   kubectl apply -f kubernetes/apps/rook-ceph/rook-ceph/backup/restore-job.yaml
   kubectl logs -n rook-ceph -l job-name=rclone-rgw-restore -f
   ```
4. Verify object counts match Garage, then `kubectl delete -f restore-job.yaml`.

### Layer 2a — CloudNativePG (Postgres)

CNPG recovers from the barman store in the `cloudnative-pg` bucket. In
`kubernetes/apps/database/cloudnative-pg/cluster/cluster16.yaml`:

1. Bump `serverName` (e.g. `postgres16-v1` → `postgres16-v2`) so the recovered
   cluster writes to a new WAL prefix and does not clobber the archive it is
   recovering from.
2. Uncomment the `bootstrap.recovery` + `externalClusters` block; set
   `previousCluster` to the OLD `serverName` (`postgres16-v1`).
3. Commit; let Flux create the cluster. It restores the base backup and replays
   WAL from `s3://cloudnative-pg/`.
4. Once healthy, revert to the normal (non-recovery) spec in a follow-up commit.

### Layer 2b — volsync (PVCs, kopia)

Each app's PVC bootstraps from a `ReplicationDestination` named
`<app>-bootstrap` (see `kubernetes/templates/volsync/`), which restores from the
kopia repo in `volsync-backups`. Normal app reconciliation triggers this via the
PVC `dataSourceRef`; no manual step beyond having the bucket restored (Layer 1)
and applying the app.

### After restore

- Verify apps are healthy and data is intact.
- Set `suspend: false` on the backup CronJob (in git) and confirm the next run
  is a small incremental, not a full re-upload or a mass deletion.

---

## Full-cluster-loss checklist

1. Rebuild Talos + Flux + Rook; wait for Ceph healthy and RGW `Ready`.
2. **Suspend** the backup CronJob before it can fire.
3. Wait for OBCs Bound + `volsync-obc-creds` synced.
4. Layer 1 object restore (`restore-job.yaml`), verify counts.
5. Layer 2a CNPG recovery, Layer 2b volsync — bring apps up, verify.
6. Resume the backup (git `suspend: false`); confirm the next run is incremental.

---

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `AuthorizationHeaderMalformed … expected scope …/garage/…` | Missing `region = garage` on the `[garage]` remote. |
| Backup transfers 0 bytes, no errors | Source remote can't see the bucket — check it uses the bucket's OBC creds, not `backup-user` (which 403s). |
| `403 AccessDenied` listing a bucket | Wrong credentials for that bucket's owner. |
| `radosgw-admin` shows no buckets/users | Wrong zone — pass the `$Z` realm/zonegroup/zone flags. |
| `volsync-obc-creds` missing/not synced | Check the `volsync-obc` SecretStore is `Valid` and the RBAC in `obc-cred-mirror.yaml` is applied. |
