# Ceph RGW Disaster Recovery Runbook

This document describes how to backup Ceph RGW to Garage (TrueNAS) and restore in a disaster scenario.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Normal Operation                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    Daily Sync     ┌──────────────┐                │
│  │   Ceph RGW   │ ───────────────►  │    Garage    │                │
│  │  (Primary)   │    (rclone)       │  (TrueNAS)   │                │
│  └──────────────┘                   └──────────────┘                │
│         ▲                                                           │
│         │                                                           │
│    ┌────┴────┐                                                      │
│    │ Volsync │                                                      │
│    │  CNPG   │                                                      │
│    └─────────┘                                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       Disaster Recovery                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    Restore Sync   ┌──────────────┐                │
│  │  Fresh RGW   │ ◄───────────────  │    Garage    │                │
│  │  (New Ceph)  │    (rclone)       │  (TrueNAS)   │                │
│  └──────────────┘                   └──────────────┘                │
│         ▲                                  ▲                        │
│         │                                  │                        │
│    Option A                           Option B                      │
│    (after sync)                       (direct restore)              │
│         │                                  │                        │
│    ┌────┴────┐                       ┌─────┴─────┐                  │
│    │ Volsync │                       │  Volsync  │                  │
│    │  CNPG   │                       │   CNPG    │                  │
│    └─────────┘                       └───────────┘                  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### 1. Bitwarden Secrets Manager

Create a secret named `rclone-rgw-backup` with these keys:

| Key | Description | Example |
|-----|-------------|---------|
| `CEPH_ACCESS_KEY` | Ceph RGW access key | From `backup-user` ObjectStoreUser |
| `CEPH_SECRET_KEY` | Ceph RGW secret key | From `backup-user` ObjectStoreUser |
| `GARAGE_ENDPOINT` | Garage S3 endpoint | `http://truenas.local:3900` |
| `GARAGE_ACCESS_KEY` | Garage access key | From Garage admin |
| `GARAGE_SECRET_KEY` | Garage secret key | From Garage admin |

### 2. Garage Setup on TrueNAS

1. Install Garage on TrueNAS (Docker/VM/App)
2. Create buckets matching Ceph:
   - `volsync-backups`
   - `cloudnative-pg`
   - Any other buckets you use
3. Create access keys with write permissions

---

## Enabling Backup Sync

### Step 1: Verify Secrets

Ensure the `rclone-rgw-backup` secret exists in Bitwarden Secrets Manager.

### Step 2: Enable the Kustomization

Add the backup ks.yaml to the main kustomization:

```yaml
# kubernetes/apps/rook-ceph/rook-ceph/ks.yaml
# Add this new Kustomization block at the end
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: rook-ceph-backup
  namespace: flux-system
spec:
  # ... (already created in backup/ks.yaml)
```

### Step 3: Unsuspend the CronJob

Edit `backup/cronjob.yaml`:

```yaml
spec:
  suspend: false  # Change from true to false
```

### Step 4: Verify Sync

```bash
# Check CronJob status
kubectl get cronjob -n rook-ceph rclone-rgw-backup

# Trigger a manual sync
kubectl create job --from=cronjob/rclone-rgw-backup -n rook-ceph rclone-test

# Watch the logs
kubectl logs -n rook-ceph -l job-name=rclone-test -f
```

---

## Disaster Recovery Procedures

### Scenario 1: Complete Cluster Loss

**Situation:** Entire Kubernetes cluster is gone. You need to restore from scratch.

#### Option A: Restore to Fresh Ceph RGW

1. **Bootstrap new cluster with Ceph**
   ```bash
   # Deploy Talos + Flux as normal
   # Wait for Ceph to be healthy
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
   ```

2. **Create the restore job**
   ```bash
   # Apply the restore job (uncomment from cronjob.yaml or create manually)
   kubectl apply -f - <<EOF
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: rclone-rgw-restore
     namespace: rook-ceph
   spec:
     ttlSecondsAfterFinished: 86400
     template:
       spec:
         restartPolicy: OnFailure
         containers:
           - name: rclone
             image: rclone/rclone:1.68
             args:
               - sync
               - --config=/config/rclone.conf
               - --verbose
               - --transfers=4
               - --checkers=8
               - --fast-list
               - garage:
               - ceph:
             volumeMounts:
               - name: rclone-config
                 mountPath: /config
                 readOnly: true
         volumes:
           - name: rclone-config
             secret:
               secretName: rclone-rgw-backup
   EOF
   ```

3. **Wait for sync to complete**
   ```bash
   kubectl logs -n rook-ceph -l job-name=rclone-rgw-restore -f
   ```

4. **Deploy applications**
   - Volsync will find existing restic repos and can restore PVCs
   - CloudNative-PG will find WAL archives and can recover databases

#### Option B: Restore Directly from Garage (Faster)

1. **Bootstrap new cluster WITHOUT Ceph Object Store**
   - Deploy Ceph for block storage only
   - Skip RGW deployment initially

2. **Update Volsync to point to Garage**
   
   Temporarily modify `kubernetes/templates/volsync/minio.yaml`:
   ```yaml
   AWS_S3_ENDPOINT: "http://truenas.local:3900"  # Garage endpoint
   ```

3. **Update CloudNative-PG to point to Garage**
   
   Modify `kubernetes/apps/database/cloudnative-pg/cluster/cluster16.yaml`:
   ```yaml
   endpointURL: http://truenas.local:3900  # Garage endpoint
   ```

4. **Restore applications from Garage**
   - Volsync restores PVCs from Garage
   - CNPG recovers from Garage

5. **Later: Set up RGW and migrate back** (optional)

---

### Scenario 2: Single OSD Failure

**Situation:** One drive failed, cluster is degraded but operational.

1. **Check cluster health**
   ```bash
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
   ```

2. **Verify backups are current**
   ```bash
   kubectl get cronjob -n rook-ceph rclone-rgw-backup
   kubectl get jobs -n rook-ceph -l job-name=rclone-rgw-backup
   ```

3. **Replace drive and let Ceph rebalance**
   - See OSD replacement procedure (separate doc)

---

### Scenario 3: RGW Data Corruption

**Situation:** RGW is running but data is corrupted.

1. **Stop applications writing to RGW**
   ```bash
   flux suspend ks volsync-system
   flux suspend ks cloudnative-pg-cluster
   ```

2. **Clear corrupted buckets**
   ```bash
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- \
     radosgw-admin bucket rm --bucket=volsync-backups --purge-objects
   ```

3. **Restore from Garage**
   ```bash
   kubectl create job --from=cronjob/rclone-rgw-backup -n rook-ceph rclone-restore
   # Note: Modify args to sync garage: → ceph: direction
   ```

4. **Resume applications**
   ```bash
   flux resume ks volsync-system
   flux resume ks cloudnative-pg-cluster
   ```

---

## Verification Checklist

### Regular Health Checks

- [ ] CronJob ran successfully in last 24 hours
- [ ] No failed jobs in `kubectl get jobs -n rook-ceph`
- [ ] Garage accessible from cluster
- [ ] Bucket sizes match between Ceph and Garage

### Monthly DR Test

- [ ] Spin up test cluster
- [ ] Restore one PVC from Garage
- [ ] Verify data integrity
- [ ] Document any issues

---

## Key Endpoints & Credentials

| Resource | Location | Notes |
|----------|----------|-------|
| Ceph RGW (internal) | `http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80` | In-cluster only |
| Ceph RGW (external) | `https://rgw.${SECRET_DOMAIN}` | Via ingress |
| Garage | `http://truenas.local:3900` | Update with your TrueNAS IP |
| RGW Credentials | Bitwarden: `rclone-rgw-backup` | CEPH_ACCESS_KEY, CEPH_SECRET_KEY |
| Garage Credentials | Bitwarden: `rclone-rgw-backup` | GARAGE_ACCESS_KEY, GARAGE_SECRET_KEY |

---

## Troubleshooting

### Rclone sync is slow

```bash
# Check transfer stats
kubectl logs -n rook-ceph -l job-name=rclone-rgw-backup -f

# Increase parallelism (edit cronjob.yaml)
args:
  - --transfers=8
  - --checkers=16
```

### Permission denied errors

```bash
# Verify credentials
kubectl get secret -n rook-ceph rclone-rgw-backup -o yaml

# Test manually
kubectl run -it --rm rclone-test --image=rclone/rclone:1.68 -- \
  --config=/dev/stdin lsd ceph: <<EOF
[ceph]
type = s3
provider = Ceph
endpoint = http://rook-ceph-rgw-ceph-objectstore.rook-ceph.svc:80
access_key_id = YOUR_KEY
secret_access_key = YOUR_SECRET
EOF
```

### Bucket doesn't exist on Garage

```bash
# Create bucket via rclone
kubectl run -it --rm rclone-test --image=rclone/rclone:1.68 -- \
  --config=/config/rclone.conf mkdir garage:volsync-backups
```
